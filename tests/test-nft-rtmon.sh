#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-rtmon.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"
}

mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft" \
	"$TEST_ROOT/root/lib/multiwan-nft" "$TEST_ROOT/root/usr/share/libubox"
: > "$TEST_ROOT/lib/functions.sh"
: > "$TEST_ROOT/lib/functions/network.sh"
: > "$TEST_ROOT/root/usr/share/libubox/jshn.sh"
ln -s "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh" \
	"$TEST_ROOT/root/lib/multiwan-nft/common.sh"
ln -s "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" \
	"$TEST_ROOT/lib/multiwan-nft/multiwan_nft.sh"
ln -s "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" \
	"$TEST_ROOT/lib/multiwan-nft/process-lock.sh"

MULTIWAN_NFT_LIB_ROOT="$TEST_ROOT/lib"
IPKG_INSTROOT="$TEST_ROOT/root"
MULTIWAN_NFT_RTMON_LIBRARY_ONLY=1
NO_IPV6=0
set -- none
. "$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon"

config_foreach() {
	local callback="$1"

	"$callback" wan4
	"$callback" wan6
	"$callback" wan4b
	"$callback" disabled
}
config_get() {
	local output="$1" section="$2" option="$3" default="${4:-}" value

	value="$default"
	case "$section:$option" in
		wan4:family|wan4b:family|disabled:family) value=ipv4 ;;
		wan6:family) value=ipv6 ;;
		disabled:enabled) value=0 ;;
		*:enabled) value=1 ;;
	esac
	export "$output=$value"
}
config_get_bool() {
	config_get "$@"
}
network_get_device() {
	local output="$1" resolved

	case "$2" in
		wan4) resolved=eth0 ;;
		wan6) resolved=eth1 ;;
		wan4b) resolved=eth2 ;;
		disabled) resolved=eth3 ;;
		*) resolved= ;;
	esac
	export "$output=$resolved"
}
network_flush_cache() { :; }
nft_stub() {
	case "$*" in
		*multiwan_nft_iface_in_wan4|*multiwan_nft_iface_in_wan4b) return 0 ;;
	esac
	return 1
}
NFT=nft_stub

multiwan_nft_update_dev_to_table
assert_eq "$multiwan_nft_dev_tbl_ipv4" " eth0=1 eth2=3 " "IPv4 device/table map was wrong"
assert_eq "$multiwan_nft_dev_tbl_ipv6" " eth1=2 " "IPv6 device/table map was wrong"
route_table=""
multiwan_nft_route_line_dev route_table "10.0.0.0/24 dev eth2 proto kernel" ipv4
assert_eq "$route_table" "3" "route device did not resolve to its interface table"
route_table=sentinel
multiwan_nft_route_line_dev route_table "10.1.0.0/24 dev eth9 proto kernel" ipv4
assert_eq "$route_table" "" "unknown route device did not clear the output table"

MAP_REFRESHES=0
multiwan_nft_update_dev_to_table() {
	MAP_REFRESHES=$((MAP_REFRESHES + 1))
	multiwan_nft_dev_tbl_ipv4=" eth9=4 "
}
MULTIWAN_NFT_RTMON_FAMILY=ipv4
MULTIWAN_NFT_RTMON_ROUTE_LINE="10.0.0.0/24 dev eth2 proto kernel"
multiwan_nft_rtmon_resolve_route_table
assert_eq "$MULTIWAN_NFT_RTMON_TID" "3" "cached route device did not resolve"
assert_eq "$MAP_REFRESHES" "0" "known route device unnecessarily refreshed the map"
MULTIWAN_NFT_RTMON_ROUTE_LINE="10.1.0.0/24 dev eth9 proto kernel"
multiwan_nft_rtmon_resolve_route_table
assert_eq "$MULTIWAN_NFT_RTMON_TID" "4" "new route device was not resolved after refresh"
assert_eq "$MAP_REFRESHES" "1" "unknown route device did not refresh the map exactly once"

MULTIWAN_NFT_RTMON_FAMILY=ipv4
MULTIWAN_NFT_RTMON_TID=0
MULTIWAN_NFT_RTMON_ACTIVE_TABLES=" "
config_foreach multiwan_nft_rtmon_collect_active_table interface
assert_eq "$MULTIWAN_NFT_RTMON_ACTIVE_TABLES" " 1 3 " "active route tables were collected incorrectly"

ROUTE_REPLACEMENTS=""
multiwan_nft_route_replace_idempotent() {
	ROUTE_REPLACEMENTS="${ROUTE_REPLACEMENTS}${ROUTE_REPLACEMENTS:+ }$2"
}
MULTIWAN_NFT_RTMON_IP="ip -4"
MULTIWAN_NFT_RTMON_ROUTE_LINE="10.0.0.0/24 dev eth9"
MULTIWAN_NFT_RTMON_TID=0
config_foreach multiwan_nft_rtmon_add_route_to_active_table interface
assert_eq "$ROUTE_REPLACEMENTS" "1 3" "route was not copied only to active tables"

ROUTE_PRESENT=1
ip_stub() {
	case "$1:$2" in
		route:list)
			[ "$ROUTE_PRESENT" -eq 1 ] && printf '%s\n' "$MULTIWAN_NFT_RTMON_ROUTE_LINE"
			;;
		route:del)
			printf '%s\n' "$*" > "$TEST_ROOT/deleted"
			;;
	esac
}
multiwan_nft_get_track_status() { printf '%s\n' active; }
MULTIWAN_NFT_RTMON_IP=ip_stub
MULTIWAN_NFT_RTMON_ROUTE_ACTION=del
MULTIWAN_NFT_RTMON_ROUTE_LINE="10.0.0.0/24 dev eth0"
MULTIWAN_NFT_RTMON_TID=1
multiwan_nft_rtmon_apply_route wan4
[ -s "$TEST_ROOT/deleted" ] || fail "existing route was not deleted"

rm -f "$TEST_ROOT/deleted"
ROUTE_PRESENT=0
multiwan_nft_rtmon_apply_route wan4
[ ! -e "$TEST_ROOT/deleted" ] || fail "already absent route was deleted again"

printf 'NFT route-monitor regression tests passed.\n'
