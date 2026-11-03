#!/bin/sh
set -e
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-lifecycle.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_interface_hotplug_shutdown()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/track"
mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan"
printf 'online\n' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"
HOTPLUG_STATE=online
EVENT_RESULT=0
multiwan_nft_get_iface_hotplug_state() { printf '%s\n' "$HOTPLUG_STATE"; }
multiwan_nft_get_true_iface() { export "$1=${2}_6"; }
network_get_device() { [ "$2" = wan_6 ] || fail 'Device lookup skipped the netifd alias'; export "$1=pppoe-wan"; }
env() { printf '%s\n' "$@" >> "$TEST_ROOT/events"; return "$EVENT_RESULT"; }

multiwan_nft_interface_hotplug_shutdown wan ''
grep -qxF 'DEVICE=pppoe-wan' "$TEST_ROOT/events" || fail 'Shutdown notification lost DEVICE'
grep -qxF 'INTERFACE=wan' "$TEST_ROOT/events" || fail 'Shutdown notification changed logical interface'
grep -qxF 'MULTIWAN_NFT_SHUTDOWN=1' "$TEST_ROOT/events" || fail 'Shutdown lock bypass missing'
grep -qxF 'ACTION=disconnected' "$TEST_ROOT/events" || fail 'Shutdown action changed'
rm "$TEST_ROOT/events" "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"
multiwan_nft_interface_hotplug_shutdown wan ''
[ -s "$TEST_ROOT/events" ] || fail 'Untracked online interface received no shutdown event'
rm "$TEST_ROOT/events"
HOTPLUG_STATE=offline
multiwan_nft_interface_hotplug_shutdown wan '' || :
[ ! -e "$TEST_ROOT/events" ] || fail 'Offline interface received duplicate shutdown notification'
multiwan_nft_interface_hotplug_shutdown wan 1
grep -qxF 'ACTION=ifdown' "$TEST_ROOT/events" || fail 'Explicit ifdown was skipped while offline'
grep -qxF 'DEVICE=pppoe-wan' "$TEST_ROOT/events" || fail 'Explicit ifdown lost DEVICE'
EVENT_RESULT=7
if multiwan_nft_interface_hotplug_shutdown wan 1; then fail 'Hotplug failure was hidden'; else [ "$?" -eq 7 ] || fail 'Hotplug failure status changed'; fi
eval "$(sed -n '/^service_running()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/runtime"
mkdir "$MULTIWAN_NFT_STATUS_DIR"
NFT=mock_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft HOOK_PRESENT=0
mock_nft() { [ "$*" = 'list chain inet multiwan_nft multiwan_nft_hook' ] || fail 'Running check queried the wrong object'; [ "$HOOK_PRESENT" -eq 1 ]; }
if service_running; then fail 'Status directory alone made a stopped service appear running'; fi
HOOK_PRESENT=1
service_running || fail 'Live routing hook was not recognized'
rmdir "$MULTIWAN_NFT_STATUS_DIR"
if service_running; then fail 'Uninitialized service was reported as running'; fi
eval "$(sed -n '/^start_service()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
eval "$(sed -n '/^service_started()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
APK_SCRIPT=post-upgrade NO_IPV6=0
START_FAIL=none
LOG() { :; }
multiwan_nft_is_package_script_context() { return 0; }
wait_for_network() { :; }
multiwan_nft_check_required_packages() { printf 'deps\n' >> "$TEST_ROOT/start"; }
multiwan_nft_install_missing_packages() { fail 'Startup attempted a nested package transaction'; }
multiwan_nft_init() {
    printf 'init:%s\n' "$*" >> "$TEST_ROOT/start"
    mkdir -p "$MULTIWAN_NFT_STATUS_DIR"
    [ -e "$MULTIWAN_NFT_STATUS_DIR/mmx_mask" ] || printf '0x003f0000\n' > "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
}
multiwan_nft_publish_mask() {
    printf 'publish\n' >> "$TEST_ROOT/start"
    [ "$START_FAIL" != publish ] || return 1
    printf '0x55005500\n' > "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
}
multiwan_nft_update_iface_to_table() { :; }
multiwan_nft_reconcile_conntrack_map() { printf 'reconcile\n' >> "$TEST_ROOT/start"; [ "$START_FAIL" != guard ]; }
config_foreach() { :; }
multiwan_nft_load_base_ruleset() { printf 'base\n' >> "$TEST_ROOT/start"; [ "$START_FAIL" != base ]; }
sleep() { :; }
multiwan_nft_set_custom_ipset() { :; }
multiwan_nft_set_connected_ipv4() { :; }
multiwan_nft_set_connected_ipv6() { :; }
multiwan_nft_set_general_rules() { :; }
multiwan_nft_set_policies_nft() { :; }
multiwan_nft_set_user_rules_nft() { :; }
multiwan_nft_commit_conntrack_map() { printf 'commit\n' >> "$TEST_ROOT/start"; }
multiwan_nft_has_enabled_family() { return 1; }
start_service
[ "$(cat "$TEST_ROOT/start")" = "$(printf 'deps\ninit:prepare\nreconcile\npublish\nbase\ncommit')" ] || fail 'Startup did not protect identities before publishing the mask and base rules'
service_started || fail 'Successful service definition was reported as failed'
start_tracker() { printf 'tracker\n' >> "$TEST_ROOT/start"; }
multiwan_nft_ifup() { [ "$1:$START_FAIL" != 'first:iface' ]; }
multiwan_nft_create_iface_route() { [ "$1:$START_FAIL" != 'first:route' ]; }
multiwan_nft_set_connected_ipv4() { [ "$START_FAIL" != connected4 ]; }
multiwan_nft_set_connected_ipv6() { [ "$START_FAIL" != connected6 ]; }
multiwan_nft_set_general_rules() { [ "$START_FAIL" != general ]; }
config_foreach() { "$1" first; "$1" second; }
for START_FAIL in guard publish base iface route connected4 connected6 general; do
    : > "$TEST_ROOT/start"
    printf '0x003f0000\n' > "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
    if start_service; then fail "Startup hid a $START_FAIL failure"; fi
    if service_started; then fail "Framework callback hid a $START_FAIL failure"; fi
    if grep -qx commit "$TEST_ROOT/start"; then fail "Startup released retired marks after a $START_FAIL failure"; fi
    case "$START_FAIL" in guard|publish|base)
        [ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x003f0000 ] || fail "Failed $START_FAIL changed the applied mask"
        if grep -qx tracker "$TEST_ROOT/start"; then fail "Failed $START_FAIL submitted new worker definitions"; fi
        ;;
    esac
done
START_FAIL=none
: > "$TEST_ROOT/start"
start_service
grep -qx commit "$TEST_ROOT/start" || fail 'Successful startup did not commit after failure recovery'
(
    eval "$(sed -n '/^multiwan_nft_set_general_rules()/,/^multiwan_nft_set_general_nft()/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" | sed '/^# /d;$d')"
    mock_ip() { shift; [ "$1 $2" = 'rule list' ]; }
    IP4='mock_ip -4' IP6='mock_ip -6' NO_IPV6=1
    MM_BLACKHOLE=61 MM_UNREACHABLE=62 MMX_MASK=0x3f0000 MMX_BLACKHOLE=0x3d0000 MMX_UNREACHABLE=0x3e0000
    LOG() { :; }
    if multiwan_nft_set_general_rules; then fail 'Failed special-action rule installation reported success'; fi
)
for name in start_tracker start_rtmon; do
    eval "$(sed -n "/^$name()/,/^}/p" "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
done
config_get_bool() { export "$1=1"; }
config_get() { printf '192.0.2.1'; }
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { [ "$1" != file ] || printf '%s\n' "$*" >> "$TEST_ROOT/files"; }
start_tracker wan
start_rtmon ipv4
grep -qF '/lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0' "$TEST_ROOT/files" || fail 'Tracker does not refresh changed native binding code'
grep -qF '/lib/multiwan-nft/multiwan_nft.sh' "$TEST_ROOT/files" || fail 'Route monitor does not refresh changed routing code'
rpcd_reload() { printf 'reload\n' >> "$TEST_ROOT/rpcd"; }
for callback in postinst postrm; do
    body=$(sed -n "/^define Package\/multiwan-nft\/$callback$/,/^endef$/p" "$REPO_ROOT/multiwan-nft/Makefile" |
        sed '1d;$d;s/\$\$/\$/g;s|/etc/init.d/rpcd reload|rpcd_reload|')
    [ -n "$body" ] || fail "Missing rpcd package callback: $callback"
    ( IPKG_INSTROOT="$TEST_ROOT/staging"; eval "$body" ) || fail 'Image-staging callback failed'
    [ ! -e "$TEST_ROOT/rpcd" ] || fail 'Image-staging callback changed live rpcd'
    ( IPKG_INSTROOT=; eval "$body" ) || fail 'Runtime rpcd reload callback failed'
    [ "$(cat "$TEST_ROOT/rpcd")" = reload ] || fail 'Runtime package callback did not refresh rpcd object'
    rm "$TEST_ROOT/rpcd"
done
(
    eval "$(sed -n '/^multiwan_nft_cleanup_owned_tables()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
    MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/cleanup"
    MULTIWAN_NFT_INTERFACE_MAX=60
    IP4='cleanup_ip ipv4' IP6='cleanup_ip ipv6' NO_IPV6=0
    mkdir -p "$MULTIWAN_NFT_STATUS_DIR/owned_tables"
    : > "$MULTIWAN_NFT_STATUS_DIR/owned_tables/ipv4.1"
    : > "$MULTIWAN_NFT_STATUS_DIR/owned_tables/ipv6.2"
    : > "$MULTIWAN_NFT_STATUS_DIR/owned_tables/ipv4.3"
    cleanup_ip() {
        local family="$1" id
        shift
        case "$1 $2" in
            'rule del') return 2 ;;
            'route flush')
                id=$4
                printf '%s %s\n' "$family" "$id" >> "$TEST_ROOT/flushes"
                if [ "$FLUSH_MODE" = absent ] || [ "$id" = 3 ]; then
                    printf 'Error: %s: FIB table does not exist.\nFlush terminated\n' "$family" >&2
                    return 2
                fi
                [ "$FLUSH_MODE" != error ] || { printf 'RTNETLINK answers: Operation not permitted\n' >&2; return 2; }
                ;;
            *) fail 'Unexpected owned-table cleanup command' ;;
        esac
    }
    for FLUSH_MODE in existing absent; do
        : > "$TEST_ROOT/flushes"
        multiwan_nft_cleanup_owned_tables || fail 'Absent owned table prevented shutdown cleanup'
        [ "$(wc -l < "$TEST_ROOT/flushes")" -eq 3 ] || fail 'Cleanup skipped an owned table'
    done
    FLUSH_MODE=error
    : > "$TEST_ROOT/flushes"
    if multiwan_nft_cleanup_owned_tables; then fail 'Real owned-table flush error was hidden'; fi
    [ "$(wc -l < "$TEST_ROOT/flushes")" -eq 3 ] || fail 'Flush error prevented remaining owned-table cleanup'
)
printf 'NFT lifecycle tests passed: shutdown device, aliases, untracked interfaces, running state, package/RPC callbacks, worker file watches and absent-table cleanup.\n'
