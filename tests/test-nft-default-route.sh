#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-default.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_restore_iface_default_route()/,/^multiwan_nft_restore_iface_table_default_route()/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" | sed '$d')"
LOG() { :; }
config_get() { export "$1=$FAMILY"; }
config_get_bool() { export "$1=$SOURCE_ROUTING"; }
network_get_device() { export "$1=pppoe-wan"; }
multiwan_nft_get_true_iface() { export "$1=wan"; }
PROVIDER_MODE=valid METRIC=10 QUERY_FAIL=0
ubus() { [ "$PROVIDER_MODE" = unavailable ] || printf '{}\n'; }
json_load() { [ "$PROVIDER_MODE" != invalid ]; }
ACTIVE_ROUTE=0
json_select() { case "$1" in 1|2) ACTIVE_ROUTE=$1 ;; route) ACTIVE_ROUTE=0 ;; esac; [ "$1:$PROVIDER_MODE" != route:missing ]; }
json_get_keys() {
    case "$PROVIDER_MODE" in withdrawn) export "$1=" ;; multiple|partial) export "$1=1 2" ;; *) export "$1=1" ;; esac
}
json_get_type() {
    case "$2:$PROVIDER_MODE" in
        route:object) export "$1=object" ;; route:*) export "$1=array" ;;
        1:record) export "$1=array" ;; 1:*) export "$1=object" ;;
        2:partial) export "$1=null" ;; 2:*) export "$1=object" ;;
        target:malformed) export "$1=int" ;; target:*) export "$1=string" ;;
        mask:mask-type) export "$1=string" ;; mask:*) export "$1=int" ;;
    esac
}
json_get_var() {
    if [ "$ACTIVE_ROUTE" = 2 ]; then
        case "$2" in metric) export "$1=21"; return ;; source) export "$1=2001:db8:2::/64"; return ;; nexthop) export "$1=fe80::2"; return ;; esac
    fi
    case "$2" in
        metric) export "$1=$METRIC" ;; target) [ "$FAMILY" = ipv6 ] && export "$1=::" || export "$1=0.0.0.0" ;;
        mask) case "$PROVIDER_MODE" in mask-bound) export "$1=129" ;; *) export "$1=0" ;; esac ;;
        nexthop) export "$1=$GATEWAY" ;; source) export "$1=$ROUTE_SOURCE" ;;
        *) fail 'Unexpected JSON field' ;;
    esac
}
mock_ip() {
    printf '%s\n' "$*" >> "$TEST_ROOT/ip.calls"
    [ "$IP_FAIL" -eq 0 ] || return 1
    if [ "$2 $3" = 'route list' ]; then
        [ "$QUERY_FAIL" -eq 0 ] || return 1
        local selector= gateway= effective_metric="$METRIC"
        if [ "$FAMILY:$SOURCE_ROUTING" = ipv6:1 ] && [ -n "$ROUTE_SOURCE" ] && [ "$ROUTE_SOURCE" != ::/0 ]; then selector=" from $ROUTE_SOURCE"; fi
        [ -z "$GATEWAY" ] || gateway=" via $GATEWAY"
        if [ "$ACTIVE_ROUTE" = 2 ]; then selector=' from 2001:db8:2::/64'; gateway=' via fe80::2'; effective_metric=21; fi
        [ "$FAMILY:$METRIC" != ipv6:0 ] || effective_metric=1024
        printf 'default%s%s dev pppoe-wan proto static metric %s  \t\n' "$selector" "$gateway" "$effective_metric"
        printf 'default%s via 192.0.2.254 dev pppoe-wan metric 7\n' "$selector"
        printf 'default%s%s dev other-wan metric %s\n' "$selector" "$gateway" "$effective_metric"
        printf 'default%s%s dev pppoe-wan metric 99\n' "$selector" "$gateway"
    fi
    return 0
}
IP4='mock_ip -4'
IP6='mock_ip -6'
NO_IPV6=0
IP_FAIL=0
FAMILY=ipv6
ROUTE_SOURCE=2001:db8:1::/64
GATEWAY=fe80::1
SOURCE_ROUTING=1
multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'Source-specific IPv6 default failed'
grep -qxF -- '-6 route replace table 1 default from 2001:db8:1::/64 via fe80::1 dev pppoe-wan proto static metric 10' "$TEST_ROOT/ip.calls" || fail 'IPv6 source prefix was lost'
[ "$(printf '%s' "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES")" = 'default from 2001:db8:1::/64 via fe80::1 dev pppoe-wan proto static metric 10' ] || fail 'Recovery allowlist retained an unrelated gateway/device/metric'
: > "$TEST_ROOT/ip.calls"
SOURCE_ROUTING=0
multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'Default without source routing failed'
if grep -q 'route replace.* from ' "$TEST_ROOT/ip.calls"; then fail 'Disabled source routing retained selector'; fi
for FAMILY in ipv4 ipv6; do
    GATEWAY=
    : > "$TEST_ROOT/ip.calls"
    multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'Device-only PPP default failed'
    grep -qF 'default dev pppoe-wan' "$TEST_ROOT/ip.calls" || fail 'Device-only default was omitted'
    if grep -qF ' via ' "$TEST_ROOT/ip.calls"; then fail 'Device-only default invented a gateway'; fi
done
METRIC=0
multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'IPv6 zero metric normalization failed'
printf '%s\n' "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES" | grep -q 'metric 1024' || fail 'IPv6 kernel default metric was not retained'
METRIC=10
for PROVIDER_MODE in unavailable invalid missing object record malformed mask-type mask-bound; do
    if multiwan_nft_restore_iface_default_route wan pppoe-wan 1 ''; then fail "Unknown provider state was accepted: $PROVIDER_MODE"; fi
    [ -z "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES" ] || fail 'Provider error retained another interface allowlist'
done
PROVIDER_MODE=withdrawn
multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'Explicit default withdrawal was rejected'
[ -z "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES" ] || fail 'Withdrawn default remained eligible'
PROVIDER_MODE=valid QUERY_FAIL=1
if multiwan_nft_restore_iface_default_route wan pppoe-wan 1 ''; then fail 'Failed kernel verification was hidden'; fi
QUERY_FAIL=0
PROVIDER_MODE=multiple FAMILY=ipv6 SOURCE_ROUTING=1 GATEWAY=fe80::1 METRIC=10
multiwan_nft_restore_iface_default_route wan pppoe-wan 1 '' || fail 'Multiple provider defaults failed'
[ "$(printf '%s' "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES" | grep -c '^default')" -eq 2 ] || fail 'A provider default was omitted'
printf '%s' "$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES" | grep -q 'from 2001:db8:2::/64 via fe80::2.*metric 21' || fail 'Second source-specific default was lost'
PROVIDER_MODE=partial
if multiwan_nft_restore_iface_default_route wan pppoe-wan 1 ''; then fail 'Partially malformed route declarations were accepted'; fi
PROVIDER_MODE=valid
IP_FAIL=1
if multiwan_nft_restore_iface_default_route wan pppoe-wan 1 ''; then fail 'Failed route replacement reported success'; fi
printf 'NFT default-route tests passed: IPv6 source routing, device-only defaults and failed replacement reporting.\n'
