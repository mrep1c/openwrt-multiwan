#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
tmp_common="${TMPDIR:-/tmp}/multiwan-nft-common-test.$$"
trap 'rm -f "$tmp_common"' EXIT

SCRIPTNAME="test-family-helper"
sed 's/\r$//' "$repo_root/multiwan-nft/files/lib/multiwan-nft/common.sh" > "$tmp_common"
. "$tmp_common"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

config_foreach() {
	local callback="$1"
	shift 2
	for section in $TEST_SECTIONS; do
		"$callback" "$section" "$@"
	done
}

config_get_bool() {
	local destination="$1" section="$2" option="$3" default="$4" value
	eval "value=\${TEST_${section}_${option}:-\$default}"
	eval "$destination=\$value"
}

config_get() {
	local destination="$1" section="$2" option="$3" default="${4:-}" value
	eval "value=\${TEST_${section}_${option}:-\$default}"
	eval "$destination=\$value"
}

TEST_SECTIONS="wan wanb"
TEST_wan_enabled=1
TEST_wan_family=ipv4
TEST_wanb_enabled=1
TEST_wanb_family=ipv4
multiwan_nft_has_enabled_family ipv4 || fail "IPv4-only config missed IPv4"
multiwan_nft_has_enabled_family ipv6 && fail "IPv4-only config enabled IPv6"

TEST_wanb_family=ipv6
multiwan_nft_has_enabled_family ipv4 || fail "dual-stack config missed IPv4"
multiwan_nft_has_enabled_family ipv6 || fail "dual-stack config missed IPv6"

TEST_wan_enabled=0
TEST_wanb_enabled=0
multiwan_nft_has_enabled_family ipv4 && fail "disabled config enabled IPv4"
multiwan_nft_has_enabled_family ipv6 && fail "disabled config enabled IPv6"

printf 'family helper tests passed\n'
