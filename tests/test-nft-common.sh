#!/bin/sh

set -u
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-common.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/state"
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="$MULTIWAN_NFT_STATUS_DIR/nft_log"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/tracker"
LOG() { printf '%s\n' "$*" >> "$TEST_ROOT/log"; }
TEST_MASK=0x3f0000
ENABLED4=1
ENABLED6=0
CAPACITY_COUNT=0
config_load() { return "${CONFIG_LOAD_RESULT:-0}"; }
config_get() {
    case "$2:$3" in
        globals:mmx_mask) export "$1=$TEST_MASK" ;;
        wan4:family) export "$1=ipv4" ;;
        wan6:family|disabled6:family) export "$1=ipv6" ;;
        wan4:TYPE|wan6:TYPE|explicit_4:TYPE) export "$1=interface" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_get_bool() {
    case "$2:$3" in
        wan4:enabled) export "$1=$ENABLED4" ;;
        wan6:enabled) export "$1=$ENABLED6" ;;
        disabled6:enabled) export "$1=0" ;;
        *) export "$1=${4:-0}" ;;
    esac
}
config_foreach() {
    local index
    if [ "$CAPACITY_COUNT" -gt 0 ]; then
        "$1" wan4
        index=2
        while [ "$index" -le "$CAPACITY_COUNT" ]; do
            "$1" "disabled$index"
            index=$((index + 1))
        done
    else
        "$1" wan4; "$1" wan6; "$1" disabled6
    fi
}
config_list_foreach() { :; }

for mask in 0x3f0000 0X3F0000 0x5500 0x80000300; do
    normalized="$(multiwan_nft_normalize_mask "$mask")" || fail "Valid mask rejected: $mask"
    [ "$((normalized))" -eq "$((mask))" ] || fail "Mask value changed: $mask"
done
for mask in '' garbage 63 0x 0xxyz 0x0 0x00000300 0xff 0xffffffff 0x100000000; do
    if multiwan_nft_normalize_mask "$mask" >/dev/null; then fail "Invalid mask accepted: $mask"; fi
done
[ "$(multiwan_nft_count_one_bits 0)" -eq 0 ] || fail 'Zero mask popcount wrong'
[ "$(multiwan_nft_count_one_bits 0x3f0000)" -eq 6 ] || fail 'Default mask popcount wrong'
[ "$(multiwan_nft_count_one_bits 0x80000300)" -eq 3 ] || fail 'High mask bit lost'
id=5
mask=0x5500
[ "$(multiwan_nft_id2mask id mask)" = 0x1100 ] || fail 'Sparse-mask ID mapping wrong'
mask=0x80000300
[ "$(multiwan_nft_id2mask id mask)" = 0x80000100 ] || fail 'High-bit ID mapping wrong'

multiwan_nft_init || fail 'Initialization failed'
[ "$MMX_MASK" = 0x003f0000 ] || fail 'Mask was not normalized'
[ "$MULTIWAN_NFT_INTERFACE_MAX" -eq 60 ] || fail 'Reserved IDs were not excluded'
[ "$((MMX_DEFAULT))" -eq "$((MMX_MASK))" ] || fail 'Default mark does not cover routing mask'
[ "$MMX_BLACKHOLE" = 0x3d0000 ] || fail 'Blackhole mark wrong'
[ "$MMX_UNREACHABLE" = 0x3e0000 ] || fail 'Unreachable mark wrong'
[ "$((MMX_INVMASK & MMX_MASK))" -eq 0 ] || fail 'Inverse mask overlaps routing bits'
[ "$((MMX_INVMASK | MMX_MASK))" -eq "$((0xffffffff))" ] || fail 'Inverse mask loses unrelated mark bits'
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = "$MMX_MASK" ] || fail 'Mask cache was not published'
TEST_MASK=0x5500
multiwan_nft_init || fail 'Cached initialization failed'
[ "$MMX_MASK" = 0x003f0000 ] || fail 'Active cached mask changed before restart'
cache_identity=$(ls -id "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")
multiwan_nft_init readonly || fail 'Read-only cached initialization failed'
[ "$MMX_MASK" = 0x003f0000 ] || fail 'Read-only query used unapplied UCI mask'
[ "$(ls -id "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = "$cache_identity" ] || fail 'Read-only initialization rewrote the active mask cache'
multiwan_nft_init prepare || fail 'Deferred startup preparation failed'
[ "$MMX_MASK" = 0x00005500 ] || fail 'Preparation did not calculate current UCI mask'
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x003f0000 ] &&
    [ "$(ls -id "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = "$cache_identity" ] || fail 'Preparation published the unapplied mask'
multiwan_nft_publish_mask || fail 'Explicit mask publication failed'
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x00005500 ] || fail 'Explicit publication lost the prepared mask'
MMX_MASK=invalid
if multiwan_nft_publish_mask; then fail 'Publisher accepted an invalid mask'; fi
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x00005500 ] || fail 'Invalid publication changed the active cache'
MMX_MASK=0x003f0000
mktemp() { return 1; }
if multiwan_nft_publish_mask; then fail 'Publisher hid a temporary-file failure'; fi
unset -f mktemp
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x00005500 ] || fail 'Failed publication changed the active cache'
multiwan_nft_init startup || fail 'Startup initialization failed'
[ "$MMX_MASK" = 0x00005500 ] && [ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = "$MMX_MASK" ] || fail 'Startup retained an old cached mask instead of current UCI'
printf 'invalid\n' > "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
multiwan_nft_init || fail 'Invalid cache recovery failed'
[ "$MMX_MASK" = 0x00005500 ] || fail 'Invalid cache did not reload UCI mask'
rm -rf "$MULTIWAN_NFT_STATUS_DIR"
multiwan_nft_init readonly || fail 'Cold read-only initialization failed'
[ "$MMX_MASK" = 0x00005500 ] || fail 'Cold read-only initialization did not use UCI'
[ ! -e "$MULTIWAN_NFT_STATUS_DIR" ] || fail 'Cold read-only initialization created runtime state'
CONFIG_LOAD_RESULT=7
if multiwan_nft_init startup; then fail 'Failed configuration load was ignored'; fi
[ ! -e "$MULTIWAN_NFT_STATUS_DIR" ] || fail 'Failed configuration load created runtime state'
CONFIG_LOAD_RESULT=0
TEST_MASK=0x3f0000
CAPACITY_COUNT=4
multiwan_nft_init startup || fail 'Could not seed the applied cache for validation failure'
cache_identity=$(ls -id "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")
TEST_MASK=0x700
CAPACITY_COUNT=5
if multiwan_nft_init startup; then fail 'Startup accepted more interfaces than its new mask can hold'; fi
[ "$(cat "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = 0x003f0000 ] &&
    [ "$(ls -id "$MULTIWAN_NFT_STATUS_DIR/mmx_mask")" = "$cache_identity" ] || fail 'Rejected startup changed the applied mask cache'
rm -rf "$MULTIWAN_NFT_STATUS_DIR"
if multiwan_nft_init startup; then fail 'Cold startup accepted an invalid interface count'; fi
[ ! -e "$MULTIWAN_NFT_STATUS_DIR" ] || fail 'Rejected cold startup created routing runtime'

CAPACITY_COUNT=60
TEST_MASK=0x3f0000
rm -f "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
multiwan_nft_init || fail 'Default mask rejected 60 interface sections'
[ "$MULTIWAN_NFT_INTERFACE_MAX" -eq 60 ] || fail 'Default capacity changed'
CAPACITY_COUNT=61
if multiwan_nft_init; then fail 'Disabled interface sections bypassed the 60-ID limit'; fi
CAPACITY_COUNT=4
TEST_MASK=0x700
rm -f "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
multiwan_nft_init || fail 'Three-bit mask rejected four interface sections'
[ "$MULTIWAN_NFT_INTERFACE_MAX" -eq 4 ] || fail 'Three-bit mask capacity wrong'
CAPACITY_COUNT=5
if multiwan_nft_init; then fail 'Three-bit mask accepted a reserved interface ID'; fi
CAPACITY_COUNT=0
TEST_MASK=0x3f0000
rm -f "$MULTIWAN_NFT_STATUS_DIR/mmx_mask"
multiwan_nft_init || fail 'Initialization did not recover after correcting interface count'

multiwan_nft_has_enabled_family ipv4 || fail 'Enabled IPv4 family missing'
if multiwan_nft_has_enabled_family ipv6; then fail 'Disabled IPv6 interface enabled a monitor'; fi
ENABLED6=1
multiwan_nft_has_enabled_family ipv6 || fail 'Enabled IPv6 family missing'
ENABLED4=0
if multiwan_nft_has_enabled_family ipv4; then fail 'Disabled IPv4 interface enabled a monitor'; fi
if multiwan_nft_has_enabled_family invalid; then fail 'Unknown family accepted'; fi
[ "$(set +u; multiwan_nft_get_track_status wan4)" = 'not enabled' ] || fail 'Optional tracking reported down'
(
    tracker_pid=
    status_iface="test_tracking_$$"
    trap 'if [ -n "$tracker_pid" ]; then kill "$tracker_pid" 2>/dev/null || :; wait "$tracker_pid" 2>/dev/null || :; fi' EXIT HUP INT TERM
    mkdir -p "$TEST_ROOT/usr/sbin" "$MULTIWAN_NFT_TRACK_STATUS_DIR/$status_iface"
    cat > "$TEST_ROOT/usr/sbin/multiwan-nft-track" <<'EOF'
#!/bin/sh
sleep 300 &
child=$!
trap 'kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; exit 0' TERM INT
touch "$TRACK_STATUS_READY"
wait "$child"
EOF
    chmod +x "$TEST_ROOT/usr/sbin/multiwan-nft-track"
    config_list_foreach() { [ "$1:$2" = "$status_iface:track_ip" ] && "$3" 192.0.2.2; }
    export TRACK_STATUS_READY="$TEST_ROOT/tracker-ready"
    "$TEST_ROOT/usr/sbin/multiwan-nft-track" "$status_iface" &
    tracker_pid=$!
    attempts=0
    while [ ! -e "$TRACK_STATUS_READY" ]; do
        attempts=$((attempts + 1)); [ "$attempts" -lt 50 ] || fail 'Tracking-status fixture did not start'
        sleep 0.1
    done
    for status in online offline disabled waiting; do
        printf '%s\n' "$status" > "$MULTIWAN_NFT_TRACK_STATUS_DIR/$status_iface/STATUS"
        case "$status" in disabled|waiting) expected=paused;; *) expected=active;; esac
        actual=$(set +u; multiwan_nft_get_track_status "$status_iface")
        [ "$actual" = "$expected" ] || fail "Live tracker in $status reported '$actual', expected $expected"
    done
    kill "$tracker_pid"; wait "$tracker_pid" || fail 'Tracking-status fixture did not retire'
    tracker_pid=
    [ "$(set +u; multiwan_nft_get_track_status "$status_iface")" = down ] || fail 'Stale paused metadata reported a live tracker'
    config_list_foreach() { :; }
    [ "$(set +u; multiwan_nft_get_track_status "$status_iface")" = 'not enabled' ] || fail 'Stale metadata enabled unconfigured tracking'
) || fail 'Live tracking-status regression failed'
for MULTIWAN_NFT_DEBUG in 1 yes true on; do multiwan_nft_debug_enabled || fail 'Enabled debug flag rejected'; done
MULTIWAN_NFT_DEBUG=0
if multiwan_nft_debug_enabled; then fail 'Disabled debug flag accepted'; fi

IP4=ip4_mock
IP6=ip6_mock
NETIFD4=192.0.2.2
NETIFD6=2001:db8::2
NETIFD_PREFIX=
PREFIX_ADDRESS=
DEVICE_ADDRESS4=
DEVICE_ADDRESS6=
ALIAS_AVAILABLE=1
ubus() { printf '%s\n' "$*" >> "$TEST_ROOT/network.calls"; return "$ALIAS_AVAILABLE"; }
network_get_ipaddr() { printf 'ipaddr %s\n' "$2" >> "$TEST_ROOT/network.calls"; export "$1=$NETIFD4"; }
network_get_ipaddr6() { printf 'ipaddr6 %s\n' "$2" >> "$TEST_ROOT/network.calls"; export "$1=$NETIFD6"; }
network_get_prefix6() { printf 'prefix6 %s\n' "$2" >> "$TEST_ROOT/network.calls"; export "$1=$NETIFD_PREFIX"; }
network_get_device() { printf 'device %s\n' "$2" >> "$TEST_ROOT/network.calls"; export "$1=eth-wan"; }
for pair in 'wan4_4 wan4' 'wan6_6 wan6' 'wan4_6 wan4_6' 'wan6_4 wan6_4' 'lan_4 lan_4' 'explicit_4 explicit_4' 'wan4 wan4'; do
    set -- $pair
    multiwan_nft_get_logical_iface logical "$1"
    [ "$logical" = "$2" ] || fail "Hotplug alias mapped to wrong logical interface: $1"
done
ALIAS_AVAILABLE=0
multiwan_nft_get_device device wan4
grep -qx 'device wan4_4' "$TEST_ROOT/network.calls" || fail 'WAN device ignored available family alias'
ALIAS_AVAILABLE=1
: > "$TEST_ROOT/network.calls"
multiwan_nft_get_device device wan4
grep -qx 'device wan4' "$TEST_ROOT/network.calls" || fail 'WAN device did not fall back to logical interface'
ip4_mock() {
    printf 'ip4 %s\n' "$*" >> "$TEST_ROOT/network.calls"
    [ "$*" = 'address ls dev eth-wan scope global' ] || fail 'IPv4 source fallback used wrong address scope'
    [ -z "$DEVICE_ADDRESS4" ] || printf '    inet %s/24 scope global eth-wan\n' "$DEVICE_ADDRESS4"
    return 0
}
ip6_mock() {
    printf 'ip6 %s\n' "$*" >> "$TEST_ROOT/network.calls"
    case "$*" in
        "address ls to $NETIFD_PREFIX scope global")
            [ -z "$PREFIX_ADDRESS" ] || printf '    inet6 %s/64 scope global\n' "$PREFIX_ADDRESS"
            ;;
        'address ls dev eth-wan scope global')
            [ -z "$DEVICE_ADDRESS6" ] || printf '    inet6 %s/64 scope global\n' "$DEVICE_ADDRESS6"
            ;;
        *) fail 'IPv6 source fallback used wrong prefix or scope' ;;
    esac
    return 0
}

multiwan_nft_get_src_ip source wan4
[ "$source" = 192.0.2.2 ] || fail 'Netifd IPv4 source not used'
ALIAS_AVAILABLE=0
: > "$TEST_ROOT/network.calls"
multiwan_nft_get_src_ip source wan6
[ "$source" = 2001:db8::2 ] || fail 'Netifd IPv6 source not used'
grep -qx 'ipaddr6 wan6_6' "$TEST_ROOT/network.calls" || fail 'Family-specific netifd alias not used'
if grep -q '^ip6\|^prefix6' "$TEST_ROOT/network.calls"; then fail 'Direct source unnecessarily queried fallback addresses'; fi

NETIFD6=
NETIFD_PREFIX=2001:db8:22::/56
PREFIX_ADDRESS=2001:db8:22::1
: > "$TEST_ROOT/network.calls"
multiwan_nft_get_src_ip source wan6
[ "$source" = 2001:db8:22::1 ] || fail 'IPv6 delegated-prefix source not selected'
grep -qx 'ip6 address ls to 2001:db8:22::/56 scope global' "$TEST_ROOT/network.calls" || fail 'Delegated-prefix lookup missing'
if grep -q '^device\|^ip6 address ls dev' "$TEST_ROOT/network.calls"; then fail 'PD source unnecessarily fell back to WAN device'; fi

PREFIX_ADDRESS=
DEVICE_ADDRESS6=2001:db8:ffff::2
multiwan_nft_get_src_ip source wan6
[ "$source" = 2001:db8:ffff::2 ] || fail 'IPv6 global device source not selected'
DEVICE_ADDRESS6=
source=stale
multiwan_nft_get_src_ip source wan6
[ "$source" = :: ] || fail 'Missing IPv6 source retained stale address'
NETIFD4=
DEVICE_ADDRESS4=198.51.100.2
multiwan_nft_get_src_ip source wan4
[ "$source" = 198.51.100.2 ] || fail 'IPv4 global device source not selected'
DEVICE_ADDRESS4=
multiwan_nft_get_src_ip source wan4
[ "$source" = 0.0.0.0 ] || fail 'Missing IPv4 source did not use explicit sentinel'

mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4"
get_uptime() { printf '150\n'; }
printf '100\n' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4/ONLINE"
[ "$(get_online_time wan4)" -eq 50 ] || fail 'Online elapsed time wrong'
printf '0\n' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan4/ONLINE"
[ -z "$(get_online_time wan4)" ] || fail 'Offline interface reported online time'

printf 'NFT common-helper tests passed. Network and configuration inputs were mocked.\n'
