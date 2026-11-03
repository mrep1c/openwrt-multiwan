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
config_foreach() { :; }
config_get() { export "$1=${4:-}"; }
config_get_bool() { export "$1=$SOURCE_ROUTING"; }

multiwan_nft_init || fail "NFT initialization failed with mocked UCI"

sanitize_route() {
    printf '%s\n' "$1" | sed -ne "$MULTIWAN_NFT_ROUTE_LINE_EXP"
}

expected='192.0.2.0/24 dev eth0 scope link src 192.0.2.1'
for flags in 'dead linkdown' 'linkdown dead' dead linkdown; do
    actual="$(sanitize_route "$expected $flags")"
    [ "$actual" = "$expected" ] || fail "route flags survived sanitization: $flags"
done

route='192.0.2.0/24 dev eth0 dead linkdown scope link'
[ "$(sanitize_route "$route")" = '192.0.2.0/24 dev eth0 scope link' ] ||
    fail "flags in the middle of a route were not removed"

route='fd00:1::/64 via fe80::dead dev eth0 proto static metric 1024 pref medium'
[ "$(sanitize_route "$route")" = "$route" ] || fail "IPv6 address ending in dead was changed"

for route in '198.18.190.0/24 nhid 71 via 198.51.100.2 dev eth1' '2001:db8:190::/64 nhid 72 via fe80::2 dev eth1 metric 512 pref medium' '198.18.190.0/24 nhid 71 dev eth1 scope link'; do
    [ "$(sanitize_route "$route")" = "$route" ] || fail 'Expanded nexthop lost its device or object identity before WAN selection'
done
for route in '198.18.190.0/24 nhid 71' '2001:db8:190::/64 nhid 72 metric 512 pref medium'; do
    [ "$(sanitize_route "$route")" = "$route" ] || fail 'ID-only nexthop route was changed'
done

route='default from 2001:db8::/64 via fe80::1 dev eth0'
[ "$(sanitize_route "$route")" = 'default via fe80::1 dev eth0' ] ||
    fail "disabled source routing did not remove the source prefix"
SOURCE_ROUTING=1
multiwan_nft_init || fail "NFT initialization failed with source routing enabled"
[ "$(sanitize_route "$route")" = "$route" ] || fail "enabled source routing lost its source prefix"

for name in read_route_table route_for_iface route_command route_key create_iface_route; do
    eval "$(sed -n "/^multiwan_nft_$name()/,/^}/p" "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
done
ubus() { return 0; }
network_get_device() { [ "$2" = wan_4 ] && export "$1=eth-new" || export "$1=eth-old"; }
multiwan_nft_get_iface_id() { export "$1=1"; }
multiwan_nft_update_dev_to_table() { :; }
multiwan_nft_record_owned_table() { :; }
multiwan_nft_get_routes() { printf '192.0.2.0/24 dev lan0\n'; }
multiwan_nft_route_line_dev() { export "$1="; }
multiwan_nft_route_replace_idempotent() { :; }
DEFAULT_MODE=valid
multiwan_nft_restore_iface_table_default_route() {
    printf '%s\n' "$2" > "$TEST_ROOT/restored-device"
    MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES=
    [ "$DEFAULT_MODE" != error ] || return 1
    [ "$DEFAULT_MODE" != valid ] || MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES='default via 198.51.100.2 dev eth-new metric 20'
    return 0
}
mock_ip() {
    case "$1 $2" in
        'route list') printf 'default via 198.51.100.1 dev eth-old\ndefault via 198.51.100.254 dev eth-new metric 7\ndefault via 198.51.100.2 dev eth-new metric 20\n' ;;
        *) printf '%s\n' "$*" >> "$TEST_ROOT/ip.calls" ;;
    esac
}
IP4=mock_ip
multiwan_nft_create_iface_route wan || fail 'Alias route replacement failed'
[ "$(cat "$TEST_ROOT/restored-device")" = eth-new ] || fail 'Default restoration used stale parent device'
grep -qxF 'route del table 1 default via 198.51.100.1 dev eth-old' "$TEST_ROOT/ip.calls" || fail 'Device replacement retained old WAN default'
grep -qxF 'route del table 1 default via 198.51.100.254 dev eth-new metric 7' "$TEST_ROOT/ip.calls" || fail 'Same-device stale gateway/metric survived reconciliation'
if grep -qxF 'route del table 1 default via 198.51.100.2 dev eth-new metric 20' "$TEST_ROOT/ip.calls"; then fail 'Current provider recovery default was deleted'; fi
: > "$TEST_ROOT/ip.calls"
DEFAULT_MODE=empty
multiwan_nft_create_iface_route wan || fail 'Withdrawn provider default reconciliation failed'
grep -qxF 'route del table 1 default via 198.51.100.2 dev eth-new metric 20' "$TEST_ROOT/ip.calls" || fail 'Withdrawn provider default survived'
: > "$TEST_ROOT/ip.calls"
DEFAULT_MODE=error
if multiwan_nft_create_iface_route wan; then fail 'Provider read error was hidden'; fi
[ ! -s "$TEST_ROOT/ip.calls" ] || fail 'Provider read error deleted route state'

for name in get_routes; do
    eval "$(sed -n "/^multiwan_nft_$name()/,/^}/p" "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
done
eval "$(sed -n '/^multiwan_nft_rtmon_route_handle()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon")"
config_list_foreach() { "$3" 220; }
multiwan_nft_route_line_dev() { export "$1=1"; }
multiwan_nft_set_connected_ipv4() { :; }
multiwan_nft_set_connected_ipv6() { :; }
IP4=mock_ip IP6=mock_ip
RTMON_NEXTHOPS_ACTIVE=0
SOURCE_ROUTE=
mock_ip() {
    if [ "$1 $2" = 'route list' ]; then
        case "$4" in
            main) ;;
            220) [ -z "$SOURCE_ROUTE" ] || printf '%s\n' "$SOURCE_ROUTE" ;;
            1) printf '%s \n' "$ROUTE" ;;
            *) return 1 ;;
        esac
    else
        printf '%s\n' "$*" >> "$TEST_ROOT/ip.calls"
    fi
}
for family in ipv4 ipv6; do
    case "$family" in
        ipv4) NO_IPV6=1; ROUTE='198.18.254.0/24 dev wan0 scope link' ;;
        ipv6) NO_IPV6=0; ROUTE='2001:db8:254::/64 dev wan0 metric 1024 pref medium' ;;
    esac
    for event_route in "$ROUTE " "$(printf '  %s\t  ' "$ROUTE")"; do
        : > "$TEST_ROOT/ip.calls"
        multiwan_nft_rtmon_route_handle "Deleted $event_route" "$family" || fail 'Whitespace route deletion failed'
        grep -qxF "route del table 1 $ROUTE" "$TEST_ROOT/ip.calls" ||
            fail 'Whitespace mismatch retained a deleted owned route'
    done
    : > "$TEST_ROOT/ip.calls"
    SOURCE_ROUTE="$(printf '  %s  expires 30sec  ' "$ROUTE")"
    multiwan_nft_rtmon_route_handle "Deleted $ROUTE " "$family" || fail 'Live duplicate route check failed'
    [ ! -s "$TEST_ROOT/ip.calls" ] || fail 'Whitespace or expiry text hid a still-live extra-table duplicate'
    SOURCE_ROUTE=
done

printf 'NFT route regression tests passed. No real networking commands ran.\n'
