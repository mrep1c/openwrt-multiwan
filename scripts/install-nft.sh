#!/bin/sh

set -u

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main}"
START_SERVICES="${START_SERVICES:-0}"
LOCK_DIR="/tmp/multiwan-nft-raw-install.lock"
MAIN_PACKAGES="ip-full nftables jshn rpcd conntrack uclient-fetch"
LUCI_PACKAGES="luci-base uclient-fetch"
BACKUP_SUFFIX=".pre-multiwan-rename"
COMPONENT="${1:-all}"

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
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

mkdir "$LOCK_DIR" 2>/dev/null || die "another MultiWAN NFT install is already running"
trap cleanup EXIT INT TERM

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

install_file() {
	local src="$1"
	local dst="$2"
	local mode="$3"
	local policy="${4:-force}"
	local tmp="${dst}.tmp.$$"

	if [ "$policy" = "keep" ] && [ -e "$dst" ]; then
		log "Keeping existing $dst"
		return 0
	fi

	mkdir -p "${dst%/*}" || die "could not create ${dst%/*}"
	fetch_url "$RAW_BASE/$src" "$tmp" || {
		rm -f "$tmp"
		die "failed to download $src"
	}
	mv "$tmp" "$dst" || die "could not install $dst"
	chmod "$mode" "$dst" 2>/dev/null || true
	log "Installed $dst"
}

migrate_file() {
	local old_path="$1"
	local new_path="$2"

	[ -f "$old_path" ] || return 0

	cp -p "$old_path" "${old_path}${BACKUP_SUFFIX}" 2>/dev/null || true
	[ -f "$new_path" ] && cp -p "$new_path" "${new_path}${BACKUP_SUFFIX}" 2>/dev/null || true
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
	install_packages "$MAIN_PACKAGES"
	migrate_configs

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

	/etc/init.d/multiwan-nft enable || true
	log "MultiWAN NFT main files installed."
	log "Raw install uses native interface binding; libwrap_mwan3_sockopt is not built by this package."
}

install_luci() {
	[ -x /etc/init.d/multiwan-nft ] || die "install MultiWAN NFT main files first: sh install.sh main"

	install_packages "$LUCI_PACKAGES"

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

	restart_luci
	log "MultiWAN NFT LuCI files installed."
}

case "$COMPONENT" in
	all)
		install_main
		install_luci
		;;
	main)
		install_main
		;;
	luci)
		install_luci
		;;
esac

if [ "$START_SERVICES" = "1" ] && [ "$COMPONENT" != "luci" ]; then
	/etc/init.d/multiwan-nft restart || /etc/init.d/multiwan-nft start
elif [ "$COMPONENT" != "luci" ]; then
	log "Start with: /etc/init.d/multiwan-nft start"
fi
