#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-common.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"
}

MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/status"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/tracker"
MULTIWAN_NFT_UPTIME_FILE="$TEST_ROOT/uptime"
NO_IPV6=0
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"

TEST_CONFIG_MASK="0X003F0000"
TEST_TRACK_ENABLED=0

LOG() { :; }
config_load() { :; }
config_get() {
	local output="$1" section="$2" option="$3" default="${4:-}" value

	value="$default"
	case "$section:$option" in
		globals:mmx_mask) value="$TEST_CONFIG_MASK" ;;
		wan4:family) value=ipv4 ;;
		wan6:family) value=ipv6 ;;
	esac
	export "$output=$value"
}
config_get_bool() {
	local output="$1" section="$2" option="$3" default="${4:-0}" value

	value="$default"
	case "$section:$option" in
		wan4:enabled|wan6:enabled) value=1 ;;
	esac
	export "$output=$value"
}
config_list_foreach() {
	[ "$TEST_TRACK_ENABLED" -eq 1 ] && "$3" 1.1.1.1
}
config_foreach() {
	local callback="$1"

	"$callback" wan4
	"$callback" wan6
}

assert_eq "$(multiwan_nft_normalize_mask 0X003F0000)" "0x003f0000" "mask normalization failed"
assert_eq "$(multiwan_nft_count_one_bits 0x003f0000)" "6" "mask bit count failed"
assert_eq "$(multiwan_nft_id2mask 5 0xaa)" "0x22" "sparse mark mapping failed"
multiwan_nft_normalize_mask 0xff >/dev/null 2>&1 && fail "reserved QoS bits were accepted"
multiwan_nft_normalize_mask 0x30000 >/dev/null 2>&1 && fail "mask with fewer than three bits was accepted"

printf '%s\n' '123.45 9.87' > "$MULTIWAN_NFT_UPTIME_FILE"
assert_eq "$(get_uptime)" "123" "uptime parsing failed"
mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4"
printf '%s\n' 100 > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4/ONLINE"
assert_eq "$(get_online_time wan4)" "23" "online time calculation failed"

multiwan_nft_init || fail "initialization failed"
assert_eq "$MMX_MASK" "0x003f0000" "initialization did not normalize the configured mask"
assert_eq "$MULTIWAN_NFT_INTERFACE_MAX" "60" "interface limit was calculated incorrectly"
assert_eq "$(sed -n '1p' "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" "0x003f0000" "mask cache was not persisted"

# A valid tmpfs cache must avoid another mktemp/mv cycle on every CLI and
# hotplug initialization.
mktemp() { fail "unchanged mask cache was rewritten"; }
multiwan_nft_init || fail "cached initialization failed"

multiwan_nft_has_enabled_family ipv4 || fail "enabled IPv4 family was not found"
multiwan_nft_has_enabled_family ipv6 || fail "enabled IPv6 family was not found"
multiwan_nft_has_enabled_family invalid && fail "invalid address family was accepted"

TEST_TRACK_ENABLED=0
assert_eq "$(multiwan_nft_get_track_status wan4)" "not enabled" "disabled tracking status was wrong"

TEST_TRACK_ENABLED=1
self_start="$(multiwan_nft_process_start_time "$$")" || fail "could not identify the test process"
printf '%s %s %s\n' "$$" "$self_start" "tracker:wan4:$$:$self_start" > \
	"$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4/OWNER"

# A valid owner journal must not enter the expensive legacy /proc scan.
tr() { fail "valid tracker owner fell back to process scan"; }
sed() { fail "valid tracker owner fell back to child scan"; }
assert_eq "$(multiwan_nft_get_track_status wan4)" "active" "live tracker owner was not active"

rm -f "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4/OWNER"
printf '%s\n' 1 > "$MULTIWAN_NFT_TRACK_OWNER_FORMAT_FILE"
assert_eq "$(multiwan_nft_get_track_status wan4)" "down" "missing tracker owner was not down"

printf 'NFT common-library regression tests passed.\n'
