#!/bin/sh
set -eu

MODE="${1:-all}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/mrep1c}"

fetch() {
	local url="$1"
	local dest="$2"

	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$dest" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$dest" "$url"
	elif command -v curl >/dev/null 2>&1; then
		curl -L -o "$dest" "$url"
	else
		echo "Install uclient-fetch, wget, or curl first." >&2
		exit 1
	fi
}

run_product_installer() {
	local repo="$1"
	local mode="$2"
	local tmp="/tmp/install-${repo}.sh"

	fetch "${RAW_BASE}/${repo}/main/install.sh" "$tmp"
	sh "$tmp" "$mode"
}

usage() {
	cat <<'EOF'
Usage: sh install.sh [all|main|luci|nft|nft-main|nft-luci|qos|qos-main|qos-luci]

Default:
  all       install MultiWAN NFT + LuCI and MultiWAN QoS + LuCI

Common:
  main      install both backend/service packages only
  luci      install both LuCI packages only

Per product:
  nft       install MultiWAN NFT + LuCI
  nft-main  install MultiWAN NFT backend only
  nft-luci  install MultiWAN NFT LuCI only
  qos       install MultiWAN QoS + LuCI
  qos-main  install MultiWAN QoS backend only
  qos-luci  install MultiWAN QoS LuCI only
EOF
}

case "$MODE" in
	all)
		run_product_installer openwrt-multiwan-nft all
		run_product_installer openwrt-multiwan-qos all
		;;
	main)
		run_product_installer openwrt-multiwan-nft main
		run_product_installer openwrt-multiwan-qos main
		;;
	luci)
		run_product_installer openwrt-multiwan-nft luci
		run_product_installer openwrt-multiwan-qos luci
		;;
	nft)
		run_product_installer openwrt-multiwan-nft all
		;;
	nft-main)
		run_product_installer openwrt-multiwan-nft main
		;;
	nft-luci)
		run_product_installer openwrt-multiwan-nft luci
		;;
	qos)
		run_product_installer openwrt-multiwan-qos all
		;;
	qos-main)
		run_product_installer openwrt-multiwan-qos main
		;;
	qos-luci)
		run_product_installer openwrt-multiwan-qos luci
		;;
	-h|--help|help)
		usage
		;;
	*)
		usage >&2
		exit 1
		;;
esac
