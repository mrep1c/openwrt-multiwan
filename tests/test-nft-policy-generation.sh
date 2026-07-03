#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
lib="$repo_root/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
tmp="${TMPDIR:-/tmp}/multiwan-nft-policy-test.$$"
out="$tmp/rules.out"
lib_clean="$tmp/multiwan_nft.sh"
status=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	status=1
}

mkdir -p "$tmp/root/usr/share/libubox" "$tmp/root/lib/multiwan-nft"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
: > "$tmp/root/usr/share/libubox/jshn.sh"
: > "$tmp/root/lib/multiwan-nft/common.sh"
: > "$out"
tr -d '\r' < "$lib" > "$lib_clean"

IPKG_INSTROOT="$tmp/root"
NFT=:
NFT_FAMILY=inet
NFT_TABLE=multiwan_nft
MMX_MASK=0x3F0000
MMX_INVMASK=0xffc0ffff
MMX_DEFAULT=0x3F0000
MMX_BLACKHOLE=0x3D0000
MMX_UNREACHABLE=0x3E0000
NO_IPV6=0

. "$lib_clean"

LOG() { :; }
multiwan_nft_debug_enabled() { return 1; }
multiwan_nft_nft_delete_chain() { return 0; }
multiwan_nft_nft_create_chain() { return 0; }
multiwan_nft_nft_dump() { return 0; }
multiwan_nft_if_access() { return 0; }
multiwan_nft_is_iface_offline() { return 1; }
multiwan_nft_get_iface_hotplug_state() { printf 'online\n'; }

multiwan_nft_nft_add_rule() {
	chain="$1"
	shift
	printf 'add %s %s\n' "$chain" "$*" >> "$out"
}

multiwan_nft_nft_insert_rule() {
	chain="$1"
	shift
	printf 'insert %s %s\n' "$chain" "$*" >> "$out"
}

multiwan_nft_id2mask() {
	eval "value=\${$1:-0}"
	printf '0x%06x\n' "$((value << 16))"
}

multiwan_nft_get_iface_id() {
	var="$1"
	case "$2" in
		wan_low4) value=1 ;;
		wan_high4) value=2 ;;
		wan_low6) value=3 ;;
		wan_high6) value=4 ;;
		*) value= ;;
	esac
	eval "$var=\$value"
}

multiwan_nft_get_iface_family() {
	var="$1"
	case "$2" in
		wan_low4|wan_high4) value=ipv4 ;;
		wan_low6|wan_high6) value=ipv6 ;;
		*) value= ;;
	esac
	eval "$var=\$value"
}

network_get_device() {
	var="$1"
	case "$2" in
		wan_low4) value=eth-low4 ;;
		wan_high4) value=eth-high4 ;;
		wan_low6) value=eth-low6 ;;
		wan_high6) value=eth-high6 ;;
		*) value= ;;
	esac
	eval "$var=\$value"
}

config_get() {
	var="$1"
	section="$2"
	option="$3"
	default="${4:-}"
	value="$default"
	case "$section:$option" in
		policy_descending:last_resort) value=unreachable ;;
		high4:interface) value=wan_high4 ;;
		high4:metric) value=20 ;;
		high4:weight) value=5 ;;
		low4:interface) value=wan_low4 ;;
		low4:metric) value=10 ;;
		low4:weight) value=2 ;;
		wan_low4:family) value=ipv4 ;;
		wan_high4:family) value=ipv4 ;;
		high6:interface) value=wan_high6 ;;
		high6:metric) value=30 ;;
		high6:weight) value=7 ;;
		low6:interface) value=wan_low6 ;;
		low6:metric) value=5 ;;
		low6:weight) value=3 ;;
		wan_low6:family) value=ipv6 ;;
		wan_high6:family) value=ipv6 ;;
	esac
	eval "$var=\$value"
}

config_get_bool() {
	config_get "$@"
}

config_list_foreach() {
	section="$1"
	option="$2"
	callback="$3"
	[ "$section:$option" = "policy_descending:use_member" ] || return 0
	for member in high4 low4 high6 low6; do
		"$callback" "$member"
	done
}

multiwan_nft_create_policies_nft policy_descending

grep -Fq 'wan_low4 2 2' "$out" ||
	fail "lowest IPv4 metric member was not emitted"
grep -Fq 'wan_low6 3 3' "$out" ||
	fail "lowest IPv6 metric member was not emitted"
grep -Fq 'wan_high4' "$out" &&
	fail "higher-metric IPv4 member was emitted"
grep -Fq 'wan_high6' "$out" &&
	fail "higher-metric IPv6 member was emitted"
grep -F 'wan_low4 2 2' "$out" | grep -Fq 'meta nfproto ipv4' ||
	fail "IPv4 policy member lacks family guard"
grep -F 'wan_low6 3 3' "$out" | grep -Fq 'meta nfproto ipv6' ||
	fail "IPv6 policy member lacks family guard"

grep -Fq 'match="$family_guard"' "$lib" ||
	fail "user-rule generation does not seed match with family guard"
grep -Fq 'sticky_match="$family_guard"' "$lib" ||
	fail "sticky user-rule generation does not seed match with family guard"

if [ "$status" -ne 0 ]; then
	sed 's/^/RULE: /' "$out" >&2
	exit "$status"
fi
printf 'NFT policy generation checks passed\n'
