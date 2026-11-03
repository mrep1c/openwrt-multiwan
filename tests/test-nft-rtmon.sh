#!/bin/sh
set -u
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-rtmon.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_add_all_routes()/,/^main()/p' "$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon" | sed '$d')"
eval "$(sed -n '/^multiwan_nft_read_route_table()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
eval "$(sed -n '/^multiwan_nft_route_command()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
LOG() { :; }
config_get() { export "$1=$FAMILY"; }
config_get_bool() { export "$1=$ENABLED"; }
config_foreach() { "$1" wan; }
config_list_foreach() { "$3" 220; }
network_get_device() { export "$1=wan0"; }
multiwan_nft_update_dev_to_table() { :; }
LOOKUP_FAILURE=0
multiwan_nft_route_line_dev() { export "$1="; [ "$LOOKUP_FAILURE" -eq 0 ]; }
multiwan_nft_get_routes() { [ "$SOURCE_FAILURE" -eq 0 ] || return 1; [ "$DUPLICATE" = 0 ] || printf '%s\n' "$ROUTE"; }
multiwan_nft_set_connected_ipv4() { printf 'ipv4\n' >> "$TEST_ROOT/connected"; }
multiwan_nft_set_connected_ipv6() { printf 'ipv6\n' >> "$TEST_ROOT/connected"; }
multiwan_nft_set_custom_ipset() { printf 'refresh\n' >> "$TEST_ROOT/custom"; }
multiwan_nft_get_track_status() { printf '%s\n' 'not enabled'; }
multiwan_nft_nft_add_set_element() { printf '%s %s\n' "$1" "$2" >> "$TEST_ROOT/sets"; }
multiwan_nft_route_replace_idempotent() { printf '%s %s\n' "$2" "$3" >> "$TEST_ROOT/replace"; [ "$MUTATION_FAILURE" -eq 0 ]; }
mock_ip() {
    if [ "$1 $2" = 'route list' ]; then
        printf '%s\n' "$ROUTE"
        [ "$TARGET_FAILURE" -ne "$4" ] || return 1
    else printf '%s\n' "$*" >> "$TEST_ROOT/commands"; [ "$MUTATION_FAILURE" -eq 0 ]; fi
}
IP4=mock_ip
IP6=mock_ip
NO_IPV6=0
MULTIWAN_NFT_ROUTE_LINE_EXP=p
FAMILY=ipv4
ENABLED=1
DUPLICATE=0
SOURCE_FAILURE=0 TARGET_FAILURE=0 MUTATION_FAILURE=0
ROUTE='198.18.0.0/24 dev lan0'
multiwan_nft_rtmon_route_handle "Deleted $ROUTE" ipv4
grep -qF "route del table 1 $ROUTE" "$TEST_ROOT/commands" || fail 'Enabled untracked WAN retained deleted shared route'
: > "$TEST_ROOT/commands"
DUPLICATE=1
: > "$TEST_ROOT/connected"
multiwan_nft_rtmon_route_handle "Deleted $ROUTE" ipv4
[ ! -s "$TEST_ROOT/commands" ] || fail 'Route still present in another source table was deleted'
[ -s "$TEST_ROOT/connected" ] || fail 'Live extra-table duplicate prevented removal from main connected set'
DUPLICATE=0
ENABLED=0
multiwan_nft_rtmon_route_handle "Deleted $ROUTE" ipv4
[ ! -s "$TEST_ROOT/commands" ] || fail 'Disabled WAN received shared route update'
ENABLED=1
multiwan_nft_rtmon_route_handle "$ROUTE" ipv4
grep -qxF 'multiwan_nft_connected_v4 198.18.0.0/24' "$TEST_ROOT/sets" || fail 'Wrong IPv4 connected set'
FAMILY=ipv6
ROUTE='2001:db8:12::/64 dev lan0'
multiwan_nft_rtmon_route_handle "$ROUTE" ipv6
grep -qxF 'multiwan_nft_connected_v6 2001:db8:12::/64' "$TEST_ROOT/sets" || fail 'Wrong IPv6 connected set'
: > "$TEST_ROOT/sets"
multiwan_nft_rtmon_route_handle 'default via 2001:db8::1 dev wan0' ipv6
[ ! -s "$TEST_ROOT/sets" ] || fail 'Default route polluted connected set'
[ "$(multiwan_nft_rtmon_source_table '198.18.0.0/24 dev lan0')" = main ] || fail 'Main route was not monitored'
[ "$(multiwan_nft_rtmon_source_table '198.18.0.0/24 dev lan0 table 220')" = 220 ] || fail 'Configured extra table was ignored'
if multiwan_nft_rtmon_source_table '198.18.0.0/24 dev lan0 table 123'; then fail 'Unowned table was monitored'; fi
multiwan_nft_rtmon_route_handle "$ROUTE" ipv6 220
[ -s "$TEST_ROOT/custom" ] || fail 'Extra-table change did not refresh custom bypass sets'
for FAMILY in ipv4 ipv6; do
    : > "$TEST_ROOT/commands"
    : > "$TEST_ROOT/custom"
    LOOKUP_FAILURE=1
    if multiwan_nft_rtmon_route_handle "$ROUTE" "$FAMILY" 220; then fail 'Failed nexthop ownership read accepted an event'; fi
    [ ! -s "$TEST_ROOT/commands" ] && [ ! -s "$TEST_ROOT/custom" ] || fail 'Failed ownership read mutated routes or sets'
    LOOKUP_FAILURE=0
    SOURCE_FAILURE=1
    if multiwan_nft_rtmon_route_handle "Deleted $ROUTE" "$FAMILY" 220; then fail 'Failed source inventory accepted delete event'; fi
    [ ! -s "$TEST_ROOT/commands" ] && [ ! -s "$TEST_ROOT/custom" ] || fail 'Failed source inventory mutated routes or sets'
    SOURCE_FAILURE=0 TARGET_FAILURE=1
    if multiwan_nft_rtmon_route_handle "Deleted $ROUTE" "$FAMILY"; then fail 'Failed owned-table inventory reported success'; fi
    [ ! -s "$TEST_ROOT/commands" ] || fail 'Partial owned-table dump permitted deletion'
    TARGET_FAILURE=0 MUTATION_FAILURE=1
    for event in "$ROUTE" "Deleted $ROUTE"; do
        if multiwan_nft_rtmon_route_handle "$event" "$FAMILY"; then fail 'Route mutation failure was hidden'; fi
    done
    MUTATION_FAILURE=0
done
config_foreach() { "$1" wan; "$1" wan2; }
TARGET_FAILURE=1
if multiwan_nft_rtmon_route_handle "Deleted $ROUTE" ipv6; then fail 'Later successful interface hid earlier inventory failure'; fi
TARGET_FAILURE=0
config_foreach() { "$1" wan; }
NFT=mock_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft
ACTIVE=1 SNAPSHOT_FAILURE=none
mock_nft() { [ "$ACTIVE" -eq 1 ]; }
multiwan_nft_set_custom_ipset() { printf 'custom\n' >> "$TEST_ROOT/refresh"; [ "$SNAPSHOT_FAILURE" != custom ]; }
multiwan_nft_set_connected_ipv4() { printf 'ipv4\n' >> "$TEST_ROOT/refresh"; [ "$SNAPSHOT_FAILURE" != connected ]; }
multiwan_nft_set_connected_ipv6() { printf 'ipv6\n' >> "$TEST_ROOT/refresh"; [ "$SNAPSHOT_FAILURE" != connected ]; }
HAS_GROUP=0
multiwan_nft_create_iface_route() {
    printf '%s\n' "$1" >> "$TEST_ROOT/populate"
    [ "$HAS_GROUP" -ne 1 ] || MULTIWAN_NFT_ROUTE_HAS_NEXTHOPS=1
    [ "$SNAPSHOT_FAILURE" != routes ]
}
for FAMILY in ipv4 ipv6; do
    : > "$TEST_ROOT/populate"
    : > "$TEST_ROOT/refresh"
    multiwan_nft_add_all_routes "$FAMILY" || fail 'Initial route reconciliation failed'
    grep -qx wan "$TEST_ROOT/populate" || fail 'Initial snapshot did not use shared stale-route reconciliation'
    [ "$(cat "$TEST_ROOT/refresh")" = "$(printf 'custom\n%s' "$FAMILY")" ] || fail 'Initial snapshot omitted live route sets'
    [ "$RTMON_NEXTHOPS_ACTIVE" -eq 0 ] || fail 'Plain routes activated unrelated nexthop notifications'
done
HAS_GROUP=1 FAMILY=ipv4
multiwan_nft_add_all_routes ipv4 || fail 'Grouped-route snapshot failed'
[ "$RTMON_NEXTHOPS_ACTIVE" -eq 1 ] || fail 'Snapshot lost its observed nexthop dependency'
HAS_GROUP=0
for condition in disabled missing-chain other-family; do
    : > "$TEST_ROOT/populate"
    ENABLED=1 ACTIVE=1 FAMILY=ipv4
    case "$condition" in disabled) ENABLED=0 ;; missing-chain) ACTIVE=0 ;; other-family) FAMILY=ipv6 ;; esac
    multiwan_nft_add_all_routes ipv4 || fail 'Inactive interface snapshot failed'
    [ ! -s "$TEST_ROOT/populate" ] || fail "Inactive interface received initial routes: $condition"
done
ENABLED=1 ACTIVE=1 FAMILY=ipv4
for SNAPSHOT_FAILURE in custom connected routes; do
    RTMON_NEXTHOPS_ACTIVE=1
    if multiwan_nft_add_all_routes ipv4; then fail "Initial snapshot hid $SNAPSHOT_FAILURE failure"; fi
    [ "$RTMON_NEXTHOPS_ACTIVE" -eq 1 ] || fail 'Failed snapshot erased nexthop dependencies'
done
multiwan_nft_add_all_routes() { printf '%s\n' "$1" >> "$TEST_ROOT/nexthop-refresh"; [ "$SNAPSHOT_FAILURE" = none ]; }
SNAPSHOT_FAILURE=none
RTMON_NEXTHOPS_ACTIVE=0
: > "$TEST_ROOT/nexthop-refresh"
multiwan_nft_rtmon_event 'id 94 group 91/92' ipv6 || fail 'Unused-family nexthop event failed'
[ ! -s "$TEST_ROOT/nexthop-refresh" ] || fail 'Unused-family event repeated a full snapshot'
RTMON_NEXTHOPS_ACTIVE=1
for FAMILY in ipv4 ipv6; do
    for event in 'id 81 via 192.0.2.2 dev wan0' 'Deleted id 81 via 192.0.2.2 dev wan0'; do
        : > "$TEST_ROOT/nexthop-refresh"
        multiwan_nft_rtmon_event "$event" "$FAMILY" || fail 'Nexthop notification failed'
        [ "$(cat "$TEST_ROOT/nexthop-refresh")" = "$FAMILY" ] || fail 'Nexthop change did not reconcile family routes'
    done
    for event in 'default nhid 94 metric 99' "$(printf '198.18.1.0/24 metric 99 \\\tnexthop via 192.0.2.2 dev wan0 weight 1')"; do
        : > "$TEST_ROOT/nexthop-refresh"
        multiwan_nft_rtmon_route_handle "$event" "$FAMILY" || fail 'Grouped-route notification failed'
        [ "$(cat "$TEST_ROOT/nexthop-refresh")" = "$FAMILY" ] || fail 'Grouped route did not reconcile every family table'
    done
done
SNAPSHOT_FAILURE=routes
if multiwan_nft_rtmon_event 'id 81 via 192.0.2.2 dev wan0' ipv4; then fail 'Failed nexthop resync was hidden'; fi
if multiwan_nft_rtmon_route_handle 'default nhid 94 metric 99' ipv6; then fail 'Failed group resync was hidden'; fi
RTMON_NEXTHOPS_ACTIVE=0
for FAMILY in ipv4 ipv6; do
    case "$FAMILY" in
        ipv4) ROUTE='default via 192.0.2.2 dev wan0' ;;
        ipv6) ROUTE='default via 2001:db8::2 dev wan0 metric 512 pref medium' ;;
    esac
    SNAPSHOT_FAILURE=none
    : > "$TEST_ROOT/nexthop-refresh"
    : > "$TEST_ROOT/commands"
    multiwan_nft_rtmon_route_handle "Deleted $ROUTE" "$FAMILY" || fail 'Default withdrawal reconciliation failed'
    [ "$(cat "$TEST_ROOT/nexthop-refresh")" = "$FAMILY" ] || fail 'Default deletion bypassed provider-aware reconciliation'
    [ ! -s "$TEST_ROOT/commands" ] || fail 'Default deletion blindly removed a possible recovery route'
    SNAPSHOT_FAILURE=routes
    if multiwan_nft_rtmon_route_handle "Deleted $ROUTE" "$FAMILY"; then fail 'Failed default reconciliation was hidden'; fi
    [ ! -s "$TEST_ROOT/commands" ] || fail 'Failed default reconciliation directly deleted route state'
done
printf 'NFT route monitor regression tests passed. No real networking commands ran.\n'
