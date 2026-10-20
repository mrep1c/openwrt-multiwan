#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-routes.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/state"
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="$MULTIWAN_NFT_STATUS_DIR/nft_log"
SOURCE_ROUTING=0
LOG() { :; }
config_load() { :; }
config_get() { export "$1=${4:-}"; }
config_get_bool() { export "$1=$SOURCE_ROUTING"; }

multiwan_nft_init || fail "NFT initialization failed with mocked UCI"

sanitize_route() {
    printf '%s\n' "$1" | sed -ne "$MULTIWAN_NFT_ROUTE_LINE_EXP"
}

expected='192.0.2.0/24 dev eth0 scope link src 192.0.2.1 '
for flags in 'dead linkdown' 'linkdown dead' dead linkdown; do
    actual="$(sanitize_route "$expected$flags")"
    [ "$actual" = "$expected" ] || fail "route flags survived sanitization: $flags"
done

route='192.0.2.0/24 dev eth0 dead linkdown scope link'
[ "$(sanitize_route "$route")" = '192.0.2.0/24 dev eth0 scope link' ] ||
    fail "flags in the middle of a route were not removed"

route='fd00:1::/64 via fe80::dead dev eth0 proto static metric 1024 pref medium'
[ "$(sanitize_route "$route")" = "$route" ] || fail "IPv6 address ending in dead was changed"

route='default from 2001:db8::/64 via fe80::1 dev eth0'
[ "$(sanitize_route "$route")" = 'default via fe80::1 dev eth0' ] ||
    fail "disabled source routing did not remove the source prefix"
SOURCE_ROUTING=1
multiwan_nft_init || fail "NFT initialization failed with source routing enabled"
[ "$(sanitize_route "$route")" = "$route" ] || fail "enabled source routing lost its source prefix"

printf 'NFT route regression tests passed. No real networking commands ran.\n'
