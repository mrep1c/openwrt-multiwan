#!/bin/sh

set -u

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main}"
START_SERVICES="${START_SERVICES:-0}"
LOCK_DIR="/tmp/multiwan-nft-raw-install.lock"
MAIN_PACKAGES="ip-full nftables-json kmod-nft-fib jshn rpcd conntrack multiwan-nft-sockopt uclient-fetch"
LUCI_PACKAGES="luci-base uclient-fetch"
BACKUP_SUFFIX=".pre-multiwan-rename"
COMPONENT="${1:-all}"
STAGING_DIR=""
INSTALL_TMP=""
APPLY_STARTED=0
INSTALL_COMMITTED=0
INIT_PRESENT=0
INIT_ENABLED=0
INIT_RUNNING=0
INIT_CHANGED=0
RESTART_ATTEMPTED=0

log() {
	printf '%s\n' "$*"
}

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: sh install.sh [all|main|luci]

  all   Install MultiWAN NFT service and LuCI app (default)
  main  Install only the MultiWAN NFT service package files
  luci  Install only the LuCI app files; requires main service first
EOF
}

case "$COMPONENT" in
	all|both) COMPONENT="all" ;;
	main|luci) ;;
	-h|--help|help) usage; exit 0 ;;
	*) usage >&2; die "unknown install component: $COMPONENT" ;;
esac

cleanup() {
	local result=$? failed=0
	trap - EXIT
	trap '' HUP INT TERM
	[ -z "$INSTALL_TMP" ] || rm -f "$INSTALL_TMP" || failed=1
	if [ "$INSTALL_COMMITTED" -eq 0 ] && [ "$APPLY_STARTED" -eq 1 ]; then
		if [ "$RESTART_ATTEMPTED" -eq 1 ] && [ -x /etc/init.d/multiwan-nft ]; then
			/etc/init.d/multiwan-nft stop || failed=1
		fi
		if [ "$INIT_CHANGED" -eq 1 ] && [ "$INIT_PRESENT" -eq 0 ] && [ -x /etc/init.d/multiwan-nft ]; then
			/etc/init.d/multiwan-nft disable || failed=1
		fi
		rollback_files || failed=1
		if [ "$failed" -eq 0 ] && [ "$INIT_PRESENT" -eq 1 ]; then
			if [ "$INIT_CHANGED" -eq 1 ]; then
				if [ "$INIT_ENABLED" -eq 1 ]; then /etc/init.d/multiwan-nft enable; else /etc/init.d/multiwan-nft disable; fi || failed=1
			fi
			if [ "$RESTART_ATTEMPTED" -eq 1 ] && [ "$INIT_RUNNING" -eq 1 ]; then
				/etc/init.d/multiwan-nft start || failed=1
			fi
		fi
	fi
	if [ "$failed" -ne 0 ]; then
		printf 'Error: Rollback incomplete; backups retained at %s\n' "$STAGING_DIR" >&2
		result=1
	elif [ -n "$STAGING_DIR" ]; then
		rm -rf "$STAGING_DIR" || result=1
	fi
	rmdir "$LOCK_DIR" 2>/dev/null || true
	exit "$result"
}

mkdir "$LOCK_DIR" 2>/dev/null || die "another MultiWAN NFT install is already running"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

detect_pm() {
	if command -v apk >/dev/null 2>&1; then
		echo apk
	elif command -v opkg >/dev/null 2>&1; then
		echo opkg
	else
		return 1
	fi
}

pkg_installed() {
	local pm="$1"
	local pkg="$2"

	case "$pm" in
		apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
		opkg) opkg list-installed | grep -q "^$pkg " ;;
		*) return 1 ;;
	esac
}

install_packages() {
	local packages="$1"
	local pm missing pkg

	pm="$(detect_pm)" || die "no supported package manager found"
	missing=""

	for pkg in $packages; do
		pkg_installed "$pm" "$pkg" || missing="$missing $pkg"
	done

	[ -z "$missing" ] && return 0

	log "Installing missing packages:$missing"
	case "$pm" in
		apk)
			apk update || die "apk update failed"
			apk add $missing || die "apk add failed:$missing"
			;;
		opkg)
			opkg update || die "opkg update failed"
			opkg install $missing || die "opkg install failed:$missing"
			;;
	esac
}

fetch_url() {
	local url="$1"
	local out="$2"

	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$out" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$out" "$url"
	else
		return 1
	fi
}

remember_path() {
	local path="$1" backup="$STAGING_DIR/rollback$1"
	grep -Fxq "$path" "$STAGING_DIR/recorded" && return 0
	if [ -e "$path" ] || [ -L "$path" ]; then
		mkdir -p "${backup%/*}" && cp -pP "$path" "$backup" || die "could not save $path"
		printf 'present %s\n' "$path" >> "$STAGING_DIR/journal" || die "could not record $path"
	else
		printf 'absent %s\n' "$path" >> "$STAGING_DIR/journal" || die "could not record $path"
	fi
	printf '%s\n' "$path" >> "$STAGING_DIR/recorded" || die "could not record $path"
}

rollback_files() {
	local state path failed=0
	while read -r state path; do
		case "$state" in
			present) rm -f "$path" && cp -pP "$STAGING_DIR/rollback$path" "$path" || failed=1 ;;
			absent) rm -f "$path" || failed=1 ;;
			*) failed=1 ;;
		esac
	done < "$STAGING_DIR/journal"
	return "$failed"
}

install_file() {
	local src="$1"
	local dst="$2"
	local mode="$3"
	local policy="${4:-force}"
	local tmp="${dst}.tmp.$$"
	local staged="$STAGING_DIR$dst"

	if [ "$policy" = "keep" ] && [ -e "$dst" ]; then
		log "Keeping existing $dst"
		return 0
	fi

	if [ "$INSTALL_PHASE" = download ]; then
		mkdir -p "${staged%/*}" || die "could not prepare $dst"
		fetch_url "$RAW_BASE/$src" "$staged" || die "failed to download $src"
		chmod "$mode" "$staged" || die "could not set permissions for $dst"
		return 0
	fi
	remember_path "$dst"
	mkdir -p "${dst%/*}" || die "could not create ${dst%/*}"
	INSTALL_TMP="$tmp"
	cp "$staged" "$tmp" && chmod "$mode" "$tmp" || {
		rm -f "$tmp"
		die "could not prepare installation of $dst"
	}
	mv "$tmp" "$dst" || die "could not install $dst"
	INSTALL_TMP=""
	log "Installed $dst"
}

migrate_file() {
	local old_path="$1"
	local new_path="$2"

	[ -f "$old_path" ] || return 0

	remember_path "$old_path"
	remember_path "$new_path"
	remember_path "${old_path}${BACKUP_SUFFIX}"
	remember_path "${new_path}${BACKUP_SUFFIX}"
	cp -p "$old_path" "${old_path}${BACKUP_SUFFIX}" || die "could not back up $old_path"
	if [ -f "$new_path" ]; then
		cp -p "$new_path" "${new_path}${BACKUP_SUFFIX}" || die "could not back up $new_path"
	fi
	mv "$old_path" "$new_path" || die "could not migrate $old_path to $new_path"
	log "Migrated $old_path to $new_path"
}

migrate_configs() {
	migrate_file /etc/config/mwan3 /etc/config/multiwan-nft
	migrate_file /etc/mwan3.user /etc/multiwan-nft.user
}

restart_luci() {
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart || true
	[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart || true
}

install_main() {
	if [ "${INSTALL_PHASE:-install}" != download ]; then
		migrate_configs
		if [ -f /lib/multiwan-nft/multiwan_nft.sh ]; then
			remember_path /var/run/multiwan-nft-upgrade-pending
			(umask 077; : > /var/run/multiwan-nft-upgrade-pending) || die "could not record previous installation"
		fi
	fi
	install_file multiwan-nft/files/etc/config/multiwan-nft /etc/config/multiwan-nft 0644 keep
	install_file multiwan-nft/files/etc/init.d/multiwan-nft /etc/init.d/multiwan-nft 0755
	install_file multiwan-nft/files/etc/multiwan-nft.user /etc/multiwan-nft.user 0755 keep
	install_file multiwan-nft/files/etc/hotplug.d/iface/15-multiwan-nft /etc/hotplug.d/iface/15-multiwan-nft 0644
	install_file multiwan-nft/files/etc/hotplug.d/iface/16-multiwan-nft-user /etc/hotplug.d/iface/16-multiwan-nft-user 0644
	install_file multiwan-nft/files/lib/multiwan-nft/common.sh /lib/multiwan-nft/common.sh 0644
	install_file multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh /lib/multiwan-nft/multiwan_nft.sh 0644
	install_file multiwan-nft/files/lib/multiwan-nft/process-lock.sh /lib/multiwan-nft/process-lock.sh 0644
	install_file multiwan-nft/files/usr/libexec/rpcd/multiwan_nft /usr/libexec/rpcd/multiwan_nft 0755
	install_file multiwan-nft/files/usr/sbin/multiwan-nft /usr/sbin/multiwan-nft 0755
	install_file multiwan-nft/files/usr/sbin/multiwan-nft-track /usr/sbin/multiwan-nft-track 0755
	install_file multiwan-nft/files/usr/sbin/multiwan-nft-rtmon /usr/sbin/multiwan-nft-rtmon 0755

	[ "${INSTALL_PHASE:-install}" != download ] || return 0
	INIT_CHANGED=1
	/etc/init.d/multiwan-nft enable || die "could not enable MultiWAN NFT"
	log "MultiWAN NFT main files installed."
	log "Generic command and DNS binding uses the installed target-specific multiwan-nft-sockopt package."
}

install_luci() {
	if [ "$INSTALL_PHASE" != download ] || [ "$COMPONENT" = luci ]; then
		[ -x /etc/init.d/multiwan-nft ] || die "install MultiWAN NFT main files first: sh install.sh main"
	fi

	install_file luci-app-multiwan-nft/root/usr/libexec/luci-multiwan-nft /usr/libexec/luci-multiwan-nft 0755
	install_file luci-app-multiwan-nft/root/usr/share/luci/menu.d/luci-app-multiwan-nft.json /usr/share/luci/menu.d/luci-app-multiwan-nft.json 0644
	install_file luci-app-multiwan-nft/root/usr/share/rpcd/acl.d/luci-app-multiwan-nft.json /usr/share/rpcd/acl.d/luci-app-multiwan-nft.json 0644
	install_file luci-app-multiwan-nft/htdocs/luci-static/resources/view/status/include/90_multiwan_nft.js /www/luci-static/resources/view/status/include/90_multiwan_nft.js 0644
	install_file luci-app-multiwan-nft/htdocs/luci-static/resources/view/multiwan-nft/multiwan-nft.css /www/luci-static/resources/view/multiwan-nft/multiwan-nft.css 0644

	for view in globals interface member notify policy rule; do
		install_file "luci-app-multiwan-nft/htdocs/luci-static/resources/view/multiwan-nft/network/${view}.js" "/www/luci-static/resources/view/multiwan-nft/network/${view}.js" 0644
	done

	for view in detail diagnostics overview troubleshooting; do
		install_file "luci-app-multiwan-nft/htdocs/luci-static/resources/view/multiwan-nft/status/${view}.js" "/www/luci-static/resources/view/multiwan-nft/status/${view}.js" 0644
	done

	[ "$INSTALL_PHASE" != download ] || return 0
	restart_luci
	log "MultiWAN NFT LuCI files installed."
}

case "$COMPONENT" in all|main) install_packages "$MAIN_PACKAGES" ;; esac
case "$COMPONENT" in all|luci) install_packages "$LUCI_PACKAGES" ;; esac

INSTALL_UMASK=$(umask)
umask 077
STAGING_DIR=$(mktemp -d /tmp/multiwan-nft-install.XXXXXX) || die "could not create download staging directory"
: > "$STAGING_DIR/journal" && : > "$STAGING_DIR/recorded" || die "could not prepare restore journal"
umask "$INSTALL_UMASK"
# Finish every download before migration, provenance or live-file replacement.
for INSTALL_PHASE in download install; do
	if [ "$INSTALL_PHASE" = install ]; then
		APPLY_STARTED=1
		if [ "$COMPONENT" != luci ] && [ -x /etc/init.d/multiwan-nft ]; then
			INIT_PRESENT=1
			/etc/init.d/multiwan-nft enabled >/dev/null 2>&1 && INIT_ENABLED=1
			/etc/init.d/multiwan-nft running >/dev/null 2>&1 && INIT_RUNNING=1
		fi
	fi
	case "$COMPONENT" in
		all) install_main; install_luci ;;
		main) install_main ;;
		luci) install_luci ;;
	esac
done

if [ "$START_SERVICES" = "1" ] && [ "$COMPONENT" != "luci" ]; then
	RESTART_ATTEMPTED=1
	/etc/init.d/multiwan-nft restart || /etc/init.d/multiwan-nft start || die "could not start MultiWAN NFT"
elif [ "$COMPONENT" != "luci" ]; then
	log "Start with: /etc/init.d/multiwan-nft start"
fi
INSTALL_COMMITTED=1
