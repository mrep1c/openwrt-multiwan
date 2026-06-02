#!/bin/sh
set -eu

MODE="${1:-setup}"
REPO="${REPO:-mrep1c/openwrt-multiwan}"
RELEASE_BASE="${RELEASE_BASE:-https://github.com/${REPO}/releases/download}"

APK_RELEASE_TAG="${APK_RELEASE_TAG:-apk-25.12-noarch}"
APK_KEY_URL="${APK_KEY_URL:-${RELEASE_BASE}/${APK_RELEASE_TAG}/mrep1c-openwrt-multiwan-apk.pem}"
APK_FEED_URL="${APK_FEED_URL:-${RELEASE_BASE}/${APK_RELEASE_TAG}/packages.adb}"
APK_KEY_FILE="${APK_KEY_FILE:-/etc/apk/keys/mrep1c-openwrt-multiwan-apk.pem}"
APK_FEEDS_FILE="${APK_FEEDS_FILE:-/etc/apk/repositories.d/customfeeds.list}"

OPKG_KEY_URL="${OPKG_KEY_URL:-}"
OPKG_FEED_URL="${OPKG_FEED_URL:-}"
OPKG_KEY_TMP="${OPKG_KEY_TMP:-/tmp/mrep1c-openwrt-multiwan-opkg.pub}"
OPKG_FEEDS_FILE="${OPKG_FEEDS_FILE:-/etc/opkg/customfeeds.conf}"

MAIN_PACKAGES="multiwan-nft multiwan-qos"
LUCI_PACKAGES="luci-app-multiwan-nft luci-app-multiwan-qos"
ALL_PACKAGES="$MAIN_PACKAGES $LUCI_PACKAGES"

usage() {
	cat <<'EOF'
Usage: sh setup-feed.sh [setup|install|main|luci|remove|help]

  setup    install the feed key, add the MultiWAN feed, update package lists
  install  setup feed, then install main and LuCI packages
  main     setup feed, then install backend/service packages only
  luci     setup feed, then install LuCI packages only
  remove   remove MultiWAN feed entries and feed key

Environment overrides:
  APK_RELEASE_TAG, APK_FEED_URL, APK_KEY_URL
  OPKG_FEED_URL, OPKG_KEY_URL
EOF
}

fetch_file() {
	url="$1"
	out="$2"

	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$out" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$out" "$url"
	elif command -v curl >/dev/null 2>&1; then
		curl -fL -o "$out" "$url"
	else
		echo "[ERROR] Need uclient-fetch, wget, or curl" >&2
		exit 1
	fi
}

package_manager() {
	if command -v apk >/dev/null 2>&1; then
		echo "apk"
		return 0
	fi
	if command -v opkg >/dev/null 2>&1; then
		echo "opkg"
		return 0
	fi
	echo "[ERROR] Could not find apk or opkg on this router." >&2
	exit 1
}

openwrt_release() {
	release=""
	if [ -r /etc/openwrt_release ]; then
		# shellcheck disable=SC1091
		. /etc/openwrt_release
		release="${DISTRIB_RELEASE:-}"
	fi
	printf '%s\n' "$release"
}

opkg_release_tag() {
	release="$(openwrt_release)"
	case "$release" in
		24.10*) echo "opkg-24.10-noarch" ;;
		23.05*) echo "opkg-23.05-noarch" ;;
		*)
			echo "[ERROR] Unsupported OPKG OpenWrt release: ${release:-unknown}." >&2
			echo "[ERROR] Supported OPKG releases are 24.10.x and 23.05.x." >&2
			exit 1
			;;
	esac
}

remove_apk_feed_entries() {
	mkdir -p "$(dirname "$APK_FEEDS_FILE")"
	touch "$APK_FEEDS_FILE"

	for file in /etc/apk/repositories /etc/apk/repositories.d/*.list "$APK_FEEDS_FILE"; do
		[ -e "$file" ] || continue
		tmpf="${file}.multiwan.tmp"
		grep -vF 'github.com/mrep1c/openwrt-multiwan' "$file" > "$tmpf" || true
		mv "$tmpf" "$file"
	done
}

remove_opkg_feed_entries() {
	mkdir -p "$(dirname "$OPKG_FEEDS_FILE")"
	touch "$OPKG_FEEDS_FILE"

	tmpf="${OPKG_FEEDS_FILE}.multiwan.tmp"
	grep -vF 'github.com/mrep1c/openwrt-multiwan' "$OPKG_FEEDS_FILE" > "$tmpf" || true
	mv "$tmpf" "$OPKG_FEEDS_FILE"
}

apk_setup_feed() {
	echo "[INFO] Installing APK public key"
	mkdir -p "$(dirname "$APK_KEY_FILE")"
	fetch_file "$APK_KEY_URL" "$APK_KEY_FILE"
	chmod 644 "$APK_KEY_FILE"

	echo "[INFO] Adding MultiWAN APK feed"
	remove_apk_feed_entries
	printf '%s\n' "$APK_FEED_URL" >> "$APK_FEEDS_FILE"

	echo "[INFO] Running apk update"
	apk update
	echo "[OK] MultiWAN APK feed is configured"
	echo "[INFO] Feed: $APK_FEED_URL"
}

opkg_urls() {
	tag="$(opkg_release_tag)"
	OPKG_KEY_URL="${OPKG_KEY_URL:-${RELEASE_BASE}/${tag}/mrep1c-openwrt-multiwan-opkg.pub}"
	OPKG_FEED_URL="${OPKG_FEED_URL:-${RELEASE_BASE}/${tag}}"
}

opkg_setup_feed() {
	opkg_urls

	if ! command -v opkg-key >/dev/null 2>&1; then
		echo "[ERROR] opkg-key is required to install the MultiWAN OPKG feed key." >&2
		exit 1
	fi

	echo "[INFO] Installing OPKG public key"
	fetch_file "$OPKG_KEY_URL" "$OPKG_KEY_TMP"
	opkg-key add "$OPKG_KEY_TMP"

	echo "[INFO] Adding MultiWAN OPKG feed"
	remove_opkg_feed_entries
	printf 'src/gz multiwan %s\n' "$OPKG_FEED_URL" >> "$OPKG_FEEDS_FILE"

	echo "[INFO] Running opkg update"
	opkg update
	echo "[OK] MultiWAN OPKG feed is configured"
	echo "[INFO] Feed: $OPKG_FEED_URL"
}

setup_feed() {
	pm="$(package_manager)"
	case "$pm" in
		apk) apk_setup_feed ;;
		opkg) opkg_setup_feed ;;
	esac
}

install_packages() {
	packages="$1"
	pm="$(package_manager)"
	setup_feed

	echo "[INFO] Installing: $packages"
	case "$pm" in
		apk)
			apk add $packages
			;;
		opkg)
			opkg install $packages
			;;
	esac

	case "$packages" in
		*luci-app-*)
			restart_luci_services
			;;
	esac
}

restart_luci_services() {
	if [ "${RESTART_LUCI:-1}" != "1" ]; then
		return 0
	fi

	echo "[INFO] Restarting rpcd/uhttpd so LuCI can load new menus and ACLs"
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart || true
	[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart || true
}

remove_feed() {
	pm="$(package_manager)"
	case "$pm" in
		apk)
			echo "[INFO] Removing MultiWAN APK feed entries"
			remove_apk_feed_entries
			if [ -f "$APK_KEY_FILE" ]; then
				echo "[INFO] Removing APK public key"
				rm -f "$APK_KEY_FILE"
			fi
			echo "[INFO] Running apk update"
			apk update
			;;
		opkg)
			echo "[INFO] Removing MultiWAN OPKG feed entries"
			remove_opkg_feed_entries
			echo "[INFO] Running opkg update"
			opkg update
			;;
	esac
	echo "[OK] MultiWAN feed removed"
}

case "$MODE" in
	setup)
		setup_feed
		;;
	install|all)
		install_packages "$ALL_PACKAGES"
		;;
	main)
		install_packages "$MAIN_PACKAGES"
		;;
	luci)
		install_packages "$LUCI_PACKAGES"
		;;
	remove)
		remove_feed
		;;
	help|-h|--help)
		usage
		;;
	*)
		usage >&2
		exit 1
		;;
esac
