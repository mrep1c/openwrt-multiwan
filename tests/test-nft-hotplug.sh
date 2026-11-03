#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-hotplug.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
HOTPLUG="$REPO_ROOT/multiwan-nft/files/etc/hotplug.d/iface/15-multiwan-nft"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/track"
mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan"
NFT=mock_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft NO_IPV6=0
INTERFACE=wan DEVICE=eth1 FIRSTCONNECT=0 MULTIWAN_NFT_SHUTDOWN=0
LOG() { :; }
mock_nft() { [ "$HOOK_RUNNING" -eq 1 ]; }
procd_lock() { :; }
procd_running() { [ "$PROCD_RUNNING" -eq 1 ]; }
procd_send_signal() { printf 'signal:%s\n' "$3" >> "$TEST_ROOT/events"; }
multiwan_nft_init() { printf 'init\n' >> "$TEST_ROOT/initializations"; }
service_running() { [ "$SERVICE_RUNNING" -eq 1 ]; }
config_load() { :; }
config_get_bool() { [ "$2" = wan ] && export "$1=$ENABLED" || export "$1=0"; }
config_get() {
    case "$2:$3" in
        wan:TYPE) export "$1=interface" ;;
        wan:family) export "$1=$FAMILY" ;;
        wan:initial_state) export "$1=$INITIAL_STATE" ;;
        *) export "$1=${4:-}" ;;
    esac
}
multiwan_nft_get_iface_hotplug_state() { cat "$TEST_ROOT/state"; }
multiwan_nft_set_iface_hotplug_state() { printf '%s\n' "$2" > "$TEST_ROOT/state"; }
multiwan_nft_create_iface_nft() { :; }
multiwan_nft_set_user_iface_rules_nft() { printf '%s\n' "$1" >> "$TEST_ROOT/source-rules"; }
multiwan_nft_create_iface_route() { [ "$ROUTE_FAIL" -eq 0 ]; }
multiwan_nft_set_general_rules() { :; }
multiwan_nft_set_connected_ipv4() { :; }
multiwan_nft_set_connected_ipv6() { :; }
multiwan_nft_flush_conntrack() { MULTIWAN_NFT_FLUSH_MATCHED=0; }
multiwan_nft_set_policies_nft() {
    local state
    state=$(cat "$TEST_ROOT/state")
    printf 'policy:%s\n' "$state" >> "$TEST_ROOT/events"
    [ "$state" != "$POLICY_FAIL_STATE" ] || return 1
    printf '%s\n' "$state" > "$TEST_ROOT/policy"
}
multiwan_nft_create_iface_rules() {
    [ "$RULE_FAIL_MODE" != online ] || return 1
    printf 'rules:online\n' >> "$TEST_ROOT/events"
    printf 'online\n' > "$TEST_ROOT/rules"
}
multiwan_nft_set_tracker_oif_rules() {
    [ "$RULE_FAIL_MODE" != offline ] || return 1
    printf 'rules:offline\n' >> "$TEST_ROOT/events"
    printf 'offline\n' > "$TEST_ROOT/rules"
}
hotplug() (
    set +e
    eval "$(sed -e '/^\. \/lib\//d' -e 's|/etc/init.d/multiwan-nft running|service_running|' "$HOTPLUG")"
)
reset_case() {
    ACTION=ifup MULTIWAN_NFT_STARTUP=cmd INITIAL_STATE=offline
    INTERFACE=wan FAMILY=ipv4 ENABLED=1
    ROUTE_FAIL=0 RULE_FAIL_MODE=none POLICY_FAIL_STATE=none
    PROCD_RUNNING=0 IFUPDATE_ADDRESSES=0 IFUPDATE_ROUTES=0 IFUPDATE_PREFIXES=0
    SERVICE_RUNNING=1 HOOK_RUNNING=1
    printf '%s\n' "$1" > "$TEST_ROOT/state"
    printf '%s\n' "$1" > "$TEST_ROOT/policy"
    printf '%s\n' "$1" > "$TEST_ROOT/rules"
    printf 'offline\n' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"
    rm -f "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/OFFLINE_REASON"
    : > "$TEST_ROOT/events"
    : > "$TEST_ROOT/source-rules"
    : > "$TEST_ROOT/initializations"
}
reset_case online
SERVICE_RUNNING=0
hotplug || fail 'Stopped-service event failed'
[ ! -s "$TEST_ROOT/initializations" ] && [ ! -s "$TEST_ROOT/events" ] || fail 'Stopped-service event initialized runtime'
reset_case online
HOOK_RUNNING=0
hotplug || fail 'Missing-hook event failed'
[ ! -s "$TEST_ROOT/initializations" ] && [ ! -s "$TEST_ROOT/events" ] || fail 'Missing-hook event initialized runtime'
reset_case offline
MULTIWAN_NFT_STARTUP=init
hotplug || fail 'Cold offline ifup failed'
[ "$(cat "$TEST_ROOT/rules")" = offline ] || fail 'Cold offline startup installed online lookup rules'
[ "$(cat "$TEST_ROOT/events")" = rules:offline ] || fail 'Cold startup rebuilt policy before all interfaces were ready'
reset_case online
hotplug || fail 'Repeated offline ifup failed'
[ "$(cat "$TEST_ROOT/state")" = offline ] && [ "$(cat "$TEST_ROOT/policy")" = offline ] &&
    [ "$(cat "$TEST_ROOT/rules")" = offline ] || fail 'Repeated offline ifup left state, policy and lookup rules inconsistent'
[ "$(cat "$TEST_ROOT/events")" = "$(printf 'policy:offline\nrules:offline')" ] || fail 'ifup changed routing before policy committed'
reset_case online
ROUTE_FAIL=1
if hotplug; then fail 'Route failure was hidden'; fi
[ "$(cat "$TEST_ROOT/state")" = online ] && [ ! -s "$TEST_ROOT/events" ] || fail 'Route failure published partial eligibility state'
reset_case online
POLICY_FAIL_STATE=offline
if hotplug; then fail 'Policy failure was hidden'; fi
[ "$(cat "$TEST_ROOT/state")" = online ] && [ "$(cat "$TEST_ROOT/rules")" = online ] || fail 'Rejected policy changed state or routing'
reset_case online
RULE_FAIL_MODE=offline
if hotplug; then fail 'Recovery rule failure was hidden'; fi
[ "$(cat "$TEST_ROOT/state")" = online ] && [ "$(cat "$TEST_ROOT/policy")" = online ] &&
    [ "$(cat "$TEST_ROOT/rules")" = online ] || fail 'Failed offline rules did not restore previous policy and routing'
reset_case offline
INITIAL_STATE=online RULE_FAIL_MODE=online
if hotplug; then fail 'Online rule failure was hidden'; fi
[ "$(cat "$TEST_ROOT/state")" = offline ] && [ "$(cat "$TEST_ROOT/policy")" = offline ] &&
    [ "$(cat "$TEST_ROOT/rules")" = offline ] || fail 'Failed online rules did not restore previous policy and routing'
reset_case offline
INITIAL_STATE=online
hotplug || fail 'Online ifup failed'
[ "$(cat "$TEST_ROOT/state")" = online ] && [ "$(cat "$TEST_ROOT/policy")" = online ] &&
    [ "$(cat "$TEST_ROOT/rules")" = online ] || fail 'Online ifup did not restore eligibility'
for state in online offline; do
    reset_case "$state"
    ACTION=ifupdate IFUPDATE_ADDRESSES=1 PROCD_RUNNING=1
    INITIAL_STATE=online
    [ "$state" != online ] || INITIAL_STATE=offline
    hotplug || fail 'Address update failed'
    [ "$(cat "$TEST_ROOT/state")" = "$state" ] && [ "$(cat "$TEST_ROOT/policy")" = "$state" ] &&
        [ "$(cat "$TEST_ROOT/rules")" = "$state" ] || fail 'Address update reset health state or left stale routing'
    grep -qxF "rules:$state" "$TEST_ROOT/events" || fail 'Address update did not rebuild lookup rules'
    grep -qxF 'signal:USR2' "$TEST_ROOT/events" || fail 'Address update did not refresh tracker binding'
done
reset_case offline
ACTION=ifupdate IFUPDATE_ROUTES=1 PROCD_RUNNING=1
hotplug || fail 'Route-only update failed'
grep -qxF 'rules:offline' "$TEST_ROOT/events" || fail 'Route-only update did not refresh routing'
if grep -q '^signal:' "$TEST_ROOT/events"; then fail 'Route-only update reset tracker counters'; fi
reset_case offline
ACTION=ifupdate IFUPDATE_PREFIXES=1 PROCD_RUNNING=1
hotplug || fail 'Prefix update failed'
grep -qxF 'signal:USR2' "$TEST_ROOT/events" || fail 'Prefix update did not refresh tracker source'
reset_case offline
ACTION=ifupdate IFUPDATE_ADDRESSES=0 IFUPDATE_DATA=1
hotplug || fail 'Data-only update failed'
[ ! -s "$TEST_ROOT/events" ] || fail 'Data-only update unnecessarily rebuilt routing'
reset_case offline
ACTION=ifupdate IFUPDATE_ADDRESSES=1 PROCD_RUNNING=1 ROUTE_FAIL=1
echo ifdown > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/OFFLINE_REASON"
hotplug || fail 'Address update attempted to reactivate an administratively stopped interface'
[ ! -s "$TEST_ROOT/events" ] || fail 'Address update changed routing or signaled a paused tracker'
for suffix in 4 6; do
    reset_case online
    [ "$suffix" = 4 ] && FAMILY=ipv4 || FAMILY=ipv6
    INTERFACE="wan_$suffix" INITIAL_STATE=online PROCD_RUNNING=1
    hotplug || fail 'Family alias ifup failed'
    grep -qxF 'signal:USR2' "$TEST_ROOT/events" || fail 'Family alias did not refresh logical tracker'
    grep -qxF "$INTERFACE" "$TEST_ROOT/source-rules" || fail 'Family alias source rules were not refreshed'
    grep -qxF wan "$TEST_ROOT/source-rules" || fail 'Logical source rules were not refreshed'
    [ ! -d "$MULTIWAN_NFT_TRACK_STATUS_DIR/$INTERFACE" ] || fail 'Family alias created duplicate tracker state'
done
reset_case online
INTERFACE=wan_4 ENABLED=0 PROCD_RUNNING=1
hotplug || fail 'Disabled parent alias event failed'
[ ! -s "$TEST_ROOT/events" ] || fail 'Family alias bypassed disabled parent guard'
reset_case online
INTERFACE=wan_6 PROCD_RUNNING=1
hotplug || fail 'Opposite-family alias event failed'
[ ! -s "$TEST_ROOT/events" ] || fail 'Opposite-family alias changed logical WAN state'
printf 'NFT hotplug tests passed: cold/repeated offline, online recovery, address/route/prefix refresh and route/policy/rule rollback.\n'
