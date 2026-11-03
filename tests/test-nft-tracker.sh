#!/bin/sh

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-tracker.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
TRACK_FILE="$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-track"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft" "$TEST_ROOT/bin"
for file in functions.sh functions/network.sh multiwan-nft/common.sh multiwan-nft/process-lock.sh; do
    : > "$TEST_ROOT/lib/$file"
done
MULTIWAN_NFT_LIB_ROOT="$TEST_ROOT/lib"
MULTIWAN_NFT_TRACK_LIBRARY_ONLY=1
. "$TRACK_FILE"
LOG() { :; }

export TRACK_ARGS="$TEST_ROOT/args"
for program in ping ping4 ping6 arping httping nping nslookup; do
    cat > "$TEST_ROOT/bin/$program" <<'EOF'
#!/bin/sh
if [ "$1" = --version ]; then printf 'Nping version %s\n' "${NPING_VERSION:-7.992}"; exit; fi
printf '%s\n' "$@" > "$TRACK_ARGS"
printf '%s\n' "$LC_ALL" > "$TRACK_ARGS.locale"
EOF
    chmod +x "$TEST_ROOT/bin/$program"
done
PATH="$TEST_ROOT/bin:$PATH"
DEVICE=wan0
SRC_IP=192.0.2.2
FAMILY=ipv4
MMX_DEFAULT=0x3f0000
LIBRARY="$MULTIWAN_NFT_LIB_ROOT/multiwan-nft/libwrap_mwan3_sockopt.so.1.0"
touch "$LIBRARY"
# Shell probes inspect the launch contract without loading a library into a process.
probe_argv() {
    PROBE_CALLED=1
    printf '%s\n' "$@" > "$TRACK_ARGS"
    printf '%s\n' "$LC_ALL" > "$TRACK_ARGS.locale"
    printf '%s\n' "$FAMILY:$DEVICE:$SRCIP:$FWMARK" > "$TRACK_ARGS.binding"
    printf '%s\n' "$LD_PRELOAD" > "$TRACK_ARGS.preload"
}
for program in ping arping httping nping nslookup; do
    WRAP probe_argv "$program" 'argument with spaces'
    [ "$(tr '\n' '|' < "$TRACK_ARGS")" = "$program|argument with spaces|" ] || fail 'Wrapper split or modified probe arguments'
    [ "$(cat "$TRACK_ARGS.binding")" = 'ipv4:wan0:192.0.2.2:0x3f0000' ] || fail 'Required binding environment changed'
    [ "$(cat "$TRACK_ARGS.preload")" = "$LIBRARY" ] || fail 'Required binding library missing'
done
[ "$(cat "$TRACK_ARGS.locale")" = C ] || fail 'Probe locale is not fixed for output parsing'
FAMILY=ipv6
SRC_IP=2001:db8::2
WRAP probe_argv nping -6 -c 1 2001:db8::1 --icmp
[ "$(tr '\n' '|' < "$TRACK_ARGS")" = 'nping|-6|-c|1|2001:db8::1|--icmp|' ] || fail 'Nping family/options changed'
[ "$(cat "$TRACK_ARGS.binding")" = 'ipv6:wan0:2001:db8::2:0x3f0000' ] || fail 'IPv6 source binding changed'
if validate_track_method arping; then fail 'IPv6 arping must be rejected'; fi
if validate_track_method nping-arp; then fail 'IPv6 nping ARP must be rejected'; fi
validate_track_method nping-icmp || fail 'IPv6 nping ICMP must remain supported'
for NPING_VERSION in 7.95 7.99 7.991 unknown; do
    export NPING_VERSION
    if validate_track_method nping-icmp; then fail 'Broken or unknown IPv6 Nping accepted'; fi
done
for NPING_VERSION in 7.992 7.993 8.0; do
    export NPING_VERSION
    validate_track_method nping-icmp || fail 'Supported IPv6 Nping rejected'
done
FAMILY=ipv4
NPING_VERSION=7.95 validate_track_method nping-icmp || fail 'IPv4 Nping requires no upgrade'
validate_track_method arping || fail 'IPv4 arping should remain supported'
validate_track_method nping-arp || fail 'IPv4 nping ARP should remain supported'
validate_track_method nslookup || fail 'DNS tracking must be supported'
SRC_IP=192.0.2.2
LD_PRELOAD=/existing-wrapper.so WRAP probe_argv ping
[ "$(cat "$TRACK_ARGS.preload")" = "$LIBRARY:/existing-wrapper.so" ] || fail 'Existing preload library was discarded'
failing_probe() { return 7; }
if WRAP failing_probe; then fail 'Wrapper ignored probe failure'; else [ "$?" -eq 7 ] || fail 'Wrapper changed failure status'; fi
mv "$LIBRARY" "$LIBRARY.saved"
PROBE_CALLED=0
if WRAP probe_argv nslookup; then fail 'Missing helper accepted'; fi
[ "$PROBE_CALLED" -eq 0 ] || fail 'Missing helper ran an unbound probe'
if validate_wrap; then fail 'Missing helper validation succeeded'; fi
multiwan_nft_init() { :; }
if (trap - EXIT HUP INT TERM; main wan); then fail 'Tracker started without required binding helper'; fi
mv "$LIBRARY.saved" "$LIBRARY"
validate_wrap || fail 'Present binding helper rejected'

MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/status"
multiwan_nft_init() { :; }
multiwan_nft_debug_enabled() { return 1; }
validate_track_method() { PING=mockping; }
config_get() {
    case "$3" in
        family) export "$1=$TEST_FAMILY" ;;
        track_method) export "$1=$TEST_METHOD" ;;
        count) export "$1=2" ;;
        down|up) export "$1=${TEST_TRANSITION_ROUNDS:-1}" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_get_bool() {
    case "$3" in
        check_quality) export "$1=$TEST_QUALITY" ;;
        httping_ssl) export "$1=${TEST_SSL:-0}" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_list_foreach() { "$3" "$TEST_TARGET"; }
firstconnect() { STARTED=1; STATUS=online; DEVICE=wan0; }
mw_process_start_time() { printf '1\n'; }
WRAP() {
    printf '%s\n' "$*" > "$TEST_ROOT/main.args"
    printf '%s\n' "$TEST_OUTPUT"
    return "$TEST_EXIT"
}
update_status() {
    printf '%s|%s|%s\n' "$2" "${3:-}" "${4:-}"
    exit 0
}
quality_case() {
    local expected="$1"
    IFDOWN_EVENT=0
    IFUP_EVENT=0
    (trap - EXIT HUP INT TERM; main wan) > "$TEST_ROOT/result" 2> "$TEST_ROOT/error" || fail 'Tracker round failed'
    [ "$(cat "$TEST_ROOT/result")" = "$expected" ] || fail "Expected $expected, got $(cat "$TEST_ROOT/result")"
    [ ! -s "$TEST_ROOT/error" ] || fail "Tracker emitted an arithmetic/parser error: $(cat "$TEST_ROOT/error")"
}
TEST_FAMILY=ipv4
TEST_TARGET=198.51.100.1
TEST_METHOD=ping
TEST_QUALITY=1
TEST_EXIT=0
TEST_OUTPUT='2 packets transmitted, 1 received, 50% packet loss
rtt min/avg/max/mdev = 10.000/10.000/10.000/0.000 ms'
quality_case 'down|10|50'
TEST_OUTPUT='3 packets transmitted, 2 received, 33% packet loss
round-trip min/avg/max = 10.000/10.000/10.000 ms'
quality_case 'neutral|10|33'
TEST_OUTPUT='2 packets transmitted, 0 received, 100% packet loss'
quality_case 'down|999999|100'
TEST_OUTPUT='malformed output'
quality_case 'down|999999|100'
TEST_OUTPUT='2 packets transmitted, 2 received, 0% packet loss
rtt min/avg/max/mdev = 1.000/500.001/501.000/0.000 ms'
quality_case 'neutral|501|0'

TEST_METHOD=httping
TEST_FAMILY=ipv6
TEST_TARGET=2001:db8::1
TEST_SSL=1
TEST_OUTPUT='2 connects, 1 ok, 50.00% failed, time 30ms
round-trip min/avg/max = 10.0/10.0/10.0 ms'
quality_case 'down|10|50'
[ "$(cat "$TEST_ROOT/main.args")" = 'httping -6 -c 2 -t 4 https://2001:db8::1' ] || fail 'HTTPing IPv6 literal URL/options wrong'
TEST_OUTPUT='10 connects, 9 ok, 10.01% failed, time 30ms
round-trip min/avg/max = 10.0/10.0/10.0 ms'
quality_case 'neutral|10|11'
TEST_OUTPUT='2 connects, 2 ok, 0.00% failed, time 30ms
round-trip min/avg/max = 10.0/10.0/10.0 ms'
TEST_EXIT=1
quality_case 'down|999999|100'
TEST_EXIT=0
TEST_QUALITY=0
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'httping -6 -c 2 -t 4 -q https://2001:db8::1' ] || fail 'HTTPing reachability options wrong'
TEST_SSL=0
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'httping -6 -c 2 -t 4 -q http://2001:db8::1' ] || fail 'HTTPing IPv6 HTTP literal options wrong'
TEST_SSL=1
TEST_TARGET=health.example.com
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'httping -6 -c 2 -t 4 -q https://health.example.com' ] || fail 'HTTPing bracketed an IPv6-family hostname'

TEST_METHOD=nping-icmp
TEST_FAMILY=ipv4
SRC_IP=192.0.2.2
TEST_TARGET=198.51.100.1
TEST_OUTPUT='Raw packets sent: 2 (80B) | Rcvd: 2 (80B) | Lost: 0 (0.00%)'
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'nping -4 -e wan0 --source-ip=192.0.2.2 -c 2 198.51.100.1 --icmp' ] || fail 'Nping does not explicitly select interface/source'
TEST_METHOD=nping-arp
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'nping -4 -e wan0 --arp-sender-ip=192.0.2.2 -c 2 198.51.100.1 --arp' ] || fail 'Nping ARP does not set its actual sender address'
TEST_METHOD=nping-icmp
TEST_FAMILY=ipv6 TEST_TARGET=2001:db8::1 SRC_IP=2001:db8::2
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'nping -6 -e wan0 -c 2 2001:db8::1 --icmp' ] || fail 'Nping IPv6 must let bound socket generate source header'
TEST_FAMILY=ipv4 TEST_TARGET=198.51.100.1 SRC_IP=192.0.2.2
TEST_OUTPUT='Raw packets sent: 2 (80B) | Rcvd: 1 (40B) | Lost: 1 (50.00%)'
quality_case 'down||'
TEST_OUTPUT='malformed output'
quality_case 'down||'
TEST_OUTPUT='Raw packets sent: 2 (80B) | Rcvd: 2 (80B) | Lost: 0 (0.00%)'
TEST_EXIT=1
quality_case 'down||'

TEST_METHOD=nslookup
TEST_QUALITY=0
TEST_TARGET=198.51.100.53
TEST_EXIT=0
TEST_OUTPUT='Server: 198.51.100.53
Address: 198.51.100.53#53

Non-authoritative answer:
Name: www.google.com
Address: 192.0.2.10'
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'nslookup -retry=2 -t=4 www.google.com 198.51.100.53' ] || fail 'DNS tracking must honor configured retry count/timeout and selected server'
TEST_FAMILY=ipv6
TEST_TARGET=2001:db8::53
TEST_OUTPUT='Server: 2001:db8::53
Address: 2001:db8::53#53
Name: www.google.com
Address 1: 2001:db8::10'
quality_case 'up||'
[ "$(cat "$TEST_ROOT/main.args")" = 'nslookup -retry=2 -t=4 www.google.com 2001:db8::53' ] || fail 'IPv6 DNS retry count/timeout or server argument changed'
TEST_OUTPUT='Name: www.google.com
Addresses: 2001:db8::10
           192.0.2.10'
quality_case 'up||'
TEST_OUTPUT='Server: 2001:db8::53
Address: 2001:db8::53#53
** server cannot find www.google.com: NXDOMAIN'
quality_case 'down||'
TEST_OUTPUT='Name: www.google.com
Address: '
quality_case 'down||'
TEST_OUTPUT=''
quality_case 'down||'
TEST_OUTPUT='Name: www.google.com
Address: 192.0.2.10'
TEST_EXIT=1
quality_case 'down||'

# A kernel-expired IPv6 source must refresh before the next real probe round.
(
    TEST_METHOD=ping TEST_FAMILY=ipv6 TEST_QUALITY=0
    TEST_TARGET=2001:db8::1 SRC_IP=2001:db8::10
    IP6=expired_source_query
    expired_source_query() { return 0; }
    network_flush_cache() { :; }
    multiwan_nft_get_src_ip() { export "$1=2001:db8::20"; }
    firstconnect() {
        STARTED=1 STATUS=online DEVICE=wan0
        [ "${1:-}" != refresh ] || multiwan_nft_get_src_ip SRC_IP wan
    }
    WRAP() { printf '%s\n' "$SRC_IP" > "$TEST_ROOT/expiry-probe-source"; return 0; }
    quality_case 'up||'
    [ "$(cat "$TEST_ROOT/expiry-probe-source")" = 2001:db8::20 ] || fail 'Probe retained a kernel-expired source despite a usable replacement'
) || fail 'IPv6 source expiry was not handled by the actual tracker loop'

# Run four complete rounds through the existing failure/recovery state machine.
TEST_METHOD=ping
TEST_FAMILY=ipv4
TEST_QUALITY=0
TEST_TRANSITION_ROUNDS=2
PROBE_INDEX=0
WRAP() { [ "$PROBE_INDEX" -ge 2 ]; }
update_status() {
    PROBE_INDEX=$((PROBE_INDEX + 1))
    [ "$PROBE_INDEX" -lt 5 ] || exit 0
}
sleep() { :; }
get_uptime() { printf '123\n'; }
env() { printf '%s\n' "$*" >> "$TEST_ROOT/events"; }
firstconnect() { STARTED=1; STATUS=online; DEVICE=wan0; echo online > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"; }
IFDOWN_EVENT=0
IFUP_EVENT=0
(trap - EXIT HUP INT TERM; main wan) > "$TEST_ROOT/transitions" 2> "$TEST_ROOT/error" || fail 'Transition rounds failed'
[ ! -s "$TEST_ROOT/error" ] || fail "Transition state machine emitted an error: $(cat "$TEST_ROOT/error")"
[ "$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS")" = online ] || fail 'WAN did not recover after configured rounds'
grep -q 'ACTION=disconnecting' "$TEST_ROOT/events" || fail 'Missing disconnecting transition'
grep -q 'ACTION=disconnected' "$TEST_ROOT/events" || fail 'Missing offline transition'
grep -q 'ACTION=connecting' "$TEST_ROOT/events" || fail 'Missing connecting transition'
grep -q 'ACTION=connected' "$TEST_ROOT/events" || fail 'Missing online transition'

# Administrative down must not use the missing-device automatic retry path.
rm -f "$TEST_ROOT/paused-probes" "$TEST_ROOT/paused-connect"
(
    trap - EXIT HUP INT TERM
    IFDOWN_EVENT=1 IFUP_EVENT=0 READY_RECHECK_INTERVAL=1
    firstconnect() {
        echo called >> "$TEST_ROOT/paused-connect"
        STARTED=1 STATUS=online DEVICE=wan0
        echo online > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"
    }
    WRAP() { echo sent >> "$TEST_ROOT/paused-probes"; return 0; }
    update_status() { exit 0; }
    sleep() { command sleep 1; }
    stop_subprocs() { [ -z "$SLEEP_PID" ] || kill "$SLEEP_PID" 2>/dev/null || :; }
    main wan
) > "$TEST_ROOT/paused-output" 2> "$TEST_ROOT/paused-error" &
paused_pid=$!
attempt=0
while [ "$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS")" != disabled ] && kill -0 "$paused_pid" 2>/dev/null; do
    attempt=$((attempt+1)); [ "$attempt" -lt 30 ] || break
    command sleep 1
done
command sleep 1
if [ "$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS")" != disabled ] ||
   [ -e "$TEST_ROOT/paused-probes" ] || [ -e "$TEST_ROOT/paused-connect" ]; then
    kill "$paused_pid" 2>/dev/null || :; wait "$paused_pid" 2>/dev/null || :
    fail 'Administrative down resumed tracking without an up signal'
fi
kill -USR2 "$paused_pid"
wait "$paused_pid" || fail 'Administrative up did not resume the tracker'
[ -f "$TEST_ROOT/paused-probes" ] && [ -f "$TEST_ROOT/paused-connect" ] || fail 'Up signal did not refresh binding and resume probes'
(
    stop_subprocs() { :; }
    IFDOWN_EVENT=0 IFUP_EVENT=1
    if_down
    [ "$IFDOWN_EVENT" -eq 1 ] && [ "$IFUP_EVENT" -eq 0 ]
) || fail 'Latest down signal retained a pending up event'

eval "$(sed -n '/^firstconnect() {/,/^update_status()/p' "$TRACK_FILE" | sed '$d')"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/service"
mkdir -p "$MULTIWAN_NFT_STATUS_DIR/iface_state"
INTERFACE=wan
network_flush_cache() { :; }
multiwan_nft_get_true_iface() { export "$1=$2"; }
network_get_device() { export "$1=wan-new"; }
network_is_up() { return 0; }
multiwan_nft_get_src_ip() { export "$1=198.51.100.11"; }
config_get() { export "$1=$INITIAL_STATE"; }
connected() { STATUS=online; }
disconnected() { STATUS=offline; }
for state in online offline; do
    printf '%s\n' "$state" > "$MULTIWAN_NFT_STATUS_DIR/iface_state/wan"
    INITIAL_STATE=online STATUS=waiting SRC_IP=198.51.100.10
    [ "$state" != online ] || INITIAL_STATE=offline
    firstconnect refresh
    [ "$STATUS" = "$state" ] || fail 'Interface refresh reset committed health state'
    [ "$SRC_IP" = 198.51.100.11 ] && [ "$DEVICE" = wan-new ] || fail 'Interface refresh retained old source or device'
done
INITIAL_STATE=offline STATUS=''
firstconnect
[ "$STATUS" = offline ] || fail 'Cold tracker startup ignored initial state'

(
    FAMILY=ipv6 SRC_IP=2001:db8::10 INTERFACE=wan
    IP6=kernel_source_query CANDIDATE_SOURCE=2001:db8::20
    KERNEL_SOURCE_STATE=present SOURCE_QUERY_STATUS=0
    kernel_source_query() {
        printf '%s\n' "$*" > "$TEST_ROOT/source-query-args"
        case "$KERNEL_SOURCE_STATE" in
            present) printf '1: lo: <UP>\n    inet6 2001:db8::10/64 scope global\n' ;;
            failed) return 7 ;;
        esac
    }
    network_flush_cache() { echo flushed >> "$TEST_ROOT/source-cache"; }
    multiwan_nft_get_src_ip() {
        [ "$SOURCE_QUERY_STATUS" -eq 0 ] || return "$SOURCE_QUERY_STATUS"
        export "$1=$CANDIDATE_SOURCE"
    }
    firstconnect() { echo "$1" >> "$TEST_ROOT/source-refresh"; SRC_IP=$CANDIDATE_SOURCE; }
    refresh_expired_source
    [ ! -e "$TEST_ROOT/source-refresh" ] && [ ! -e "$TEST_ROOT/source-cache" ] || fail 'A still-local delegated source was refreshed'
    [ "$(cat "$TEST_ROOT/source-query-args")" = 'address ls to 2001:db8::10/128 scope global' ] || fail 'Delegated source query incorrectly limited lookup to the WAN device'
    KERNEL_SOURCE_STATE=failed
    refresh_expired_source
    [ "$SRC_IP" = 2001:db8::10 ] && [ ! -e "$TEST_ROOT/source-cache" ] || fail 'Failed address dump replaced a cached binding'
    KERNEL_SOURCE_STATE=absent SOURCE_QUERY_STATUS=7
    refresh_expired_source
    [ "$SRC_IP" = 2001:db8::10 ] && [ ! -e "$TEST_ROOT/source-refresh" ] || fail 'Failed source lookup replaced a cached binding'
    SOURCE_QUERY_STATUS=0
    refresh_expired_source
    [ "$SRC_IP" = 2001:db8::20 ] && [ "$(cat "$TEST_ROOT/source-refresh")" = refresh ] || fail 'Expired source did not use the existing metadata refresh path'
    rm -f "$TEST_ROOT/source-refresh" "$TEST_ROOT/source-query-args"
    SRC_IP=:: CANDIDATE_SOURCE=::
    refresh_expired_source
    [ ! -e "$TEST_ROOT/source-refresh" ] || fail 'Missing source repeatedly reset tracker state without a replacement'
    rm -f "$TEST_ROOT/source-query-args"
    FAMILY=ipv4
    refresh_expired_source
    [ ! -e "$TEST_ROOT/source-query-args" ] && [ ! -e "$TEST_ROOT/source-refresh" ] || fail 'IPv4 tracking acquired an IPv6 source-refresh dependency'
) || fail 'Expired-source refresh boundary regression'

printf 'NFT tracker regression tests passed. All probes and hotplug events were mocked.\n'
