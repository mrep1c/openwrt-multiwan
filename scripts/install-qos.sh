#!/bin/sh

set -u

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main}"
START_SERVICES="${START_SERVICES:-0}"
LOCK_DIR="/tmp/multiwan-qos-raw-install.lock"
MAIN_PACKAGES="kmod-sched ip-full nftables kmod-veth tc-full kmod-netem kmod-sched-ctinfo kmod-ifb kmod-sched-cake kmod-sched-red kmod-sched-drr kmod-sched-flower luci-lib-jsonc lua jsonfilter uclient-fetch ethtool"
LUCI_PACKAGES="luci-base jq uclient-fetch"
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

  all   Install MultiWAN QoS service and LuCI app (default)
  main  Install only the MultiWAN QoS service package files
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

mkdir "$LOCK_DIR" 2>/dev/null || die "another MultiWAN QoS install is already running"
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

migrate_dir() {
	local old_dir="$1"
	local new_dir="$2"

	[ -d "$old_dir" ] || return 0

	cp -R "$old_dir" "${old_dir}${BACKUP_SUFFIX}" 2>/dev/null || true
	[ -d "$new_dir" ] && cp -R "$new_dir" "${new_dir}${BACKUP_SUFFIX}" 2>/dev/null || true
	mkdir -p "$new_dir" || die "could not create $new_dir"
	cp -R "$old_dir"/. "$new_dir"/ 2>/dev/null || true
	rm -rf "$old_dir"
	log "Migrated $old_dir to $new_dir"
}

migrate_configs() {
	migrate_file /etc/config/qosmate /etc/config/multiwan-qos
	migrate_dir /etc/qosmate.d /etc/multiwan-qos.d
}

restart_luci() {
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart || true
	[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart || true
}

install_main() {
	install_packages "$MAIN_PACKAGES"
	migrate_configs

	install_file multiwan-qos/etc/config/multiwan-qos /etc/config/multiwan-qos 0644 keep
	install_file multiwan-qos/etc/config/multiwan-qos /etc/multiwan-qos.d/multiwan-qos-defaults 0644
	install_file multiwan-qos/etc/init.d/multiwan-qos /etc/init.d/multiwan-qos 0755
	install_file multiwan-qos/etc/multiwan-qos.sh /etc/multiwan-qos.sh 0755
	install_file multiwan-qos/etc/hotplug.d/iface/13-multiwan-qos-hotplug /etc/hotplug.d/iface/13-multiwan-qos-hotplug 0644
	install_file multiwan-qos/lib/multiwan-qos/hotplug-common.sh /lib/multiwan-qos/hotplug-common.sh 0644
	install_file multiwan-qos/lib/multiwan-qos/process-lock.sh /lib/multiwan-qos/process-lock.sh 0644
	install_file multiwan-qos/lib/multiwan-qos/realtime.sh /lib/multiwan-qos/realtime.sh 0644
	install_file multiwan-qos/lib/multiwan-qos/runtime-state.sh /lib/multiwan-qos/runtime-state.sh 0644
	install_file multiwan-qos/usr/sbin/multiwan-qos-adaptive /usr/sbin/multiwan-qos-adaptive 0755
	install_file multiwan-qos/usr/sbin/multiwan-qos-agent-watchdog /usr/sbin/multiwan-qos-agent-watchdog 0755
	install_file multiwan-qos/www/cgi-bin/multiwan-qos-agent /www/cgi-bin/multiwan-qos-agent 0755
	install_file multiwan-qos/www/cgi-bin/qosmate-agent /www/cgi-bin/qosmate-agent 0755

	for dist in experimental normal normmix20-64 pareto paretonormal; do
		install_file "multiwan-qos/usr/lib/tc/${dist}.dist" "/usr/lib/tc/${dist}.dist" 0644
	done

	/etc/init.d/multiwan-qos enable || true
	log "MultiWAN QoS main files installed."
}

install_luci() {
	[ -x /etc/init.d/multiwan-qos ] || die "install MultiWAN QoS main files first: sh install.sh main"

	install_packages "$LUCI_PACKAGES"

	install_file luci-app-multiwan-qos/root/usr/share/luci/menu.d/luci-app-multiwan-qos.json /usr/share/luci/menu.d/luci-app-multiwan-qos.json 0644
	install_file luci-app-multiwan-qos/root/usr/share/rpcd/acl.d/luci-app-multiwan-qos.json /usr/share/rpcd/acl.d/luci-app-multiwan-qos.json 0644
	install_file luci-app-multiwan-qos/root/usr/libexec/rpcd/luci.multiwan_qos /usr/libexec/rpcd/luci.multiwan_qos 0755
	install_file luci-app-multiwan-qos/root/usr/libexec/rpcd/luci.multiwan_qos_stats /usr/libexec/rpcd/luci.multiwan_qos_stats 0755

	for view in settings hfsc cake advanced rules ratelimits connections custom_rules ipsets statistics agent; do
		install_file "luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/${view}.js" "/www/luci-static/resources/view/multiwan-qos/${view}.js" 0644
	done

	restart_luci
	log "MultiWAN QoS LuCI files installed."
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
	/etc/init.d/multiwan-qos restart || /etc/init.d/multiwan-qos start
elif [ "$COMPONENT" != "luci" ]; then
	log "Start with: /etc/init.d/multiwan-qos start"
fi
