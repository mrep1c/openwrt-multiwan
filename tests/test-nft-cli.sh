#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
CLI_FILE="$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-cli.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v cc >/dev/null 2>&1 || fail 'A C compiler is required for the inert preload fixture'

MULTIWAN_NFT_LIB_ROOT="$TEST_ROOT/lib"
IPKG_INSTROOT="$TEST_ROOT"
CLI_COMMANDS="$TEST_ROOT/commands"
CLI_CAPTURE_ARGS="$TEST_ROOT/arguments"
CLI_CAPTURE_ENV="$TEST_ROOT/environment"
LD_PRELOAD=
export MULTIWAN_NFT_LIB_ROOT IPKG_INSTROOT CLI_COMMANDS CLI_CAPTURE_ARGS CLI_CAPTURE_ENV LD_PRELOAD
mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft" "$TEST_ROOT/usr/share/libubox"
: > "$TEST_ROOT/lib/functions.sh"
: > "$TEST_ROOT/lib/functions/network.sh"
: > "$TEST_ROOT/usr/share/libubox/jshn.sh"
: > "$CLI_COMMANDS"
cat > "$TEST_ROOT/lib/multiwan-nft/multiwan_nft.sh" <<'SH'
MMX_DEFAULT=0x003f0000
NO_IPV6=${TEST_NO_IPV6:-0}
NFT=cli_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft
cli_nft() {
    [ "$*" = 'list chains inet' ] || return 1
    case "${REPORT_NFT_STATE:-running}" in
        error) echo 'fixture nft inventory failure' >&2; return 8 ;;
        running) printf 'table inet multiwan_nft {\n chain multiwan_nft_hook {\n }\n}\n' ;;
        *)
            printf 'table inet foreign {\n chain multiwan_nft_hook {\n }\n}\n'
            [ "$REPORT_NFT_STATE" = absent ] || printf 'table inet multiwan_nft {\n chain multiwan_nft_hook_similar {\n }\n}\n'
            ;;
    esac
    return 0
}
IP4='ip -4'
IP6='ip -6'
multiwan_nft_init() { printf 'init:%s\n' "$*" >> "$CLI_COMMANDS"; return "${INIT_RESULT:-0}"; }
multiwan_nft_reconfiguration_pending() { [ "${RECONFIGURATION_PENDING:-0}" -eq 1 ]; }
config_load() { :; }
config_get() {
    case "$2:$3" in
        wan6:family) export "$1=ipv6" ;;
        bad-family:family) export "$1=invalid" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_foreach() { local callback="$1"; shift 2; "$callback" wan "$@"; }
multiwan_nft_get_true_iface() { export "$1=${2}_alias"; }
network_get_device() {
    case "$2" in
        wan_alias) export "$1=eth4" ;;
        wan6_alias) export "$1=eth6" ;;
        no-source_alias) export "$1=eth4" ;;
        *) export "$1=" ;;
    esac
}
multiwan_nft_get_src_ip() {
    case "$2" in
        wan) export "$1=198.51.100.2" ;;
        wan6) export "$1=2001:db8::2" ;;
        *) export "$1=0.0.0.0" ;;
    esac
}
multiwan_nft_ifup() { printf 'ifup <%s> <%s>\n' "$1" "$2" >> "$CLI_COMMANDS"; return "${ACTION_RESULT:-0}"; }
multiwan_nft_interface_hotplug_shutdown() { printf 'ifdown <%s> <%s>\n' "$1" "$2" >> "$CLI_COMMANDS"; return "${ACTION_RESULT:-0}"; }
multiwan_nft_report_iface_status() {
    if [ "${2:-}" = stopped ]; then printf 'interface %s stopped\n' "$1"; return 0; fi
    printf 'interface %s\n' "$1"; return "${REPORT_RESULT:-0}"
}
multiwan_nft_report_connected_v4() { printf 'connected4\n'; return "${REPORT_RESULT:-0}"; }
multiwan_nft_report_connected_v6() { printf 'connected6\n'; return "${REPORT_RESULT:-0}"; }
multiwan_nft_report_policies_v4() { printf 'policies4\n'; return "${REPORT_RESULT:-0}"; }
multiwan_nft_report_policies_v6() { printf 'policies6\n'; return "${REPORT_RESULT:-0}"; }
multiwan_nft_report_rules_v4() { printf 'rules4\n'; return "${REPORT_RESULT:-0}"; }
multiwan_nft_report_rules_v6() { printf 'rules6\n'; return "${REPORT_RESULT:-0}"; }
SH

CLI_RUNNER="$(readlink /proc/$$/exe)"
case "$CLI_RUNNER" in
    *busybox) run_cli() { "$CLI_RUNNER" ash "$CLI_FILE" "$@"; } ;;
    *) run_cli() { "$CLI_RUNNER" "$CLI_FILE" "$@"; } ;;
esac
assert_exit() {
    local expected="$1" result
    shift
    run_cli "$@" > "$TEST_ROOT/stdout" 2> "$TEST_ROOT/stderr"
    result=$?
    [ "$result" -eq "$expected" ] || fail "CLI '$*' returned $result, expected $expected"
}

assert_exit 0
assert_exit 0 --help
assert_exit 2 unknown-command
for command in ifup ifdown; do
    : > "$CLI_COMMANDS"
    assert_exit 2 "$command"
    [ ! -s "$CLI_COMMANDS" ] || fail "Invalid $command initialized runtime"
    assert_exit 2 "$command" ''
    [ ! -s "$CLI_COMMANDS" ] || fail "Empty $command interface initialized runtime"
    assert_exit 2 "$command" wan extra
    [ ! -s "$CLI_COMMANDS" ] || fail "Extra $command arguments initialized runtime"
done
assert_exit 2 use
assert_exit 2 use wan
assert_exit 2 connected extra
assert_exit 2 internal invalid-family
INIT_RESULT=5
export INIT_RESULT
assert_exit 5 interfaces
assert_exit 5 ifup wan
assert_exit 5 ifdown wan
INIT_RESULT=0
ACTION_RESULT=7
export ACTION_RESULT
assert_exit 7 ifup 'wan with spaces'
grep -Fxq 'ifup <wan with spaces> <cmd>' "$CLI_COMMANDS" || fail 'Dispatcher split the interface argument'
assert_exit 7 ifdown wan
ACTION_RESULT=0
REPORT_RESULT=9
export REPORT_RESULT
assert_exit 9 interfaces
assert_exit 9 policies
assert_exit 9 connected
assert_exit 9 rules
assert_exit 9 status
REPORT_RESULT=0
TEST_NO_IPV6=1
export TEST_NO_IPV6
assert_exit 0 policies
assert_exit 0 connected
assert_exit 0 rules
TEST_NO_IPV6=0
RECONFIGURATION_PENDING=1
export RECONFIGURATION_PENDING
for command in interfaces policies connected rules status; do
    assert_exit 0 "$command"
    [ "$(grep -c 'Routing configuration is incomplete' "$TEST_ROOT/stdout")" -eq 1 ] || fail 'CLI hid or duplicated routing protection warning'
done
RECONFIGURATION_PENDING=0
assert_exit 0 interfaces
if grep -q 'configuration is incomplete' "$TEST_ROOT/stdout"; then fail 'CLI retained a cleared protection warning'; fi
for command in interfaces policies connected rules status; do
    : > "$CLI_COMMANDS"
    assert_exit 0 "$command"
    [ "$(cat "$CLI_COMMANDS")" = init:readonly ] || fail "CLI $command initialized mutable runtime"
done
REPORT_RESULT=9
export REPORT_RESULT REPORT_NFT_STATE
for REPORT_NFT_STATE in stopped absent; do
    for command in interfaces policies connected rules status; do
        assert_exit 0 "$command"
        grep -qx 'MultiWAN NFT is stopped.' "$TEST_ROOT/stdout" || fail "CLI $command hid the stopped service"
        [ ! -s "$TEST_ROOT/stderr" ] || fail "Stopped CLI $command queried absent routing objects"
        case "$command" in interfaces|status)
            grep -qx 'interface wan stopped' "$TEST_ROOT/stdout" || fail 'Stopped interface rows were omitted'
            ;;
        esac
    done
done
RECONFIGURATION_PENDING=1
assert_exit 0 status
grep -q 'Routing configuration is incomplete' "$TEST_ROOT/stdout" || fail 'Stopped report hid retained routing protection'
RECONFIGURATION_PENDING=0 REPORT_RESULT=0 REPORT_NFT_STATE=error
for command in interfaces policies connected rules status; do
    assert_exit 8 "$command"
    grep -q 'fixture nft inventory failure' "$TEST_ROOT/stderr" || fail 'Failed inventory error was hidden'
    if grep -q 'is stopped' "$TEST_ROOT/stdout"; then fail 'Failed inventory was reported as stopped'; fi
done
REPORT_NFT_STATE=running
(
    MULTIWAN_NFT_CLI_LIBRARY_ONLY=1
    . "$CLI_FILE"
    multiwan_nft_init() { fail 'Lifecycle dispatcher initialized runtime before rc.common'; }
    start() { :; }; stop() { :; }; restart() { :; }
    main start && main stop && main restart
) || fail 'Lifecycle command bypass failed'

cat > "$TEST_ROOT/capture arguments.sh" <<'SH'
#!/bin/sh
printf '%s\0' "$@" > "$CLI_CAPTURE_ARGS"
printf '%s\n' "$FAMILY" "$DEVICE" "$SRCIP" "$FWMARK" "$LD_PRELOAD" > "$CLI_CAPTURE_ENV"
printf '{"ok":true}\n'
exit "${CAPTURE_RESULT:-0}"
SH
chmod +x "$TEST_ROOT/capture arguments.sh"
assert_exit 1 use wan "$TEST_ROOT/capture arguments.sh"
[ ! -e "$CLI_CAPTURE_ARGS" ] || fail 'Command ran without the binding library'
grep -qF 'binding library is missing' "$TEST_ROOT/stderr" || fail 'Missing helper failure was not explicit'

# This inert library tests environment/argv transport; socket binding has separate C tests.
printf 'int multiwan_nft_cli_fixture;\n' > "$TEST_ROOT/preload.c"
cc -shared -fPIC -o "$TEST_ROOT/lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0" "$TEST_ROOT/preload.c" || fail 'Preload fixture build failed'
assert_exit 127 use wan "$TEST_ROOT/no-such-command"
assert_exit 1 use no-device "$TEST_ROOT/capture arguments.sh"
assert_exit 1 use no-source "$TEST_ROOT/capture arguments.sh"
assert_exit 1 use bad-family "$TEST_ROOT/capture arguments.sh"
CAPTURE_RESULT=7
export CAPTURE_RESULT
assert_exit 7 use wan "$TEST_ROOT/capture arguments.sh" 'two words' '' '*' 'literal;semi' "'single quote'" 'back\slash'
printf '%s\0' 'two words' '' '*' 'literal;semi' "'single quote'" 'back\slash' > "$TEST_ROOT/expected-arguments"
cmp -s "$TEST_ROOT/expected-arguments" "$CLI_CAPTURE_ARGS" || fail 'Bound command arguments were split or expanded'
printf '%s\n' ipv4 eth4 198.51.100.2 0x003f0000 "$TEST_ROOT/lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0" > "$TEST_ROOT/expected-environment"
cmp -s "$TEST_ROOT/expected-environment" "$CLI_CAPTURE_ENV" || fail 'Binding environment changed'
printf '{"ok":true}\n' > "$TEST_ROOT/expected-stdout"
cmp -s "$TEST_ROOT/expected-stdout" "$TEST_ROOT/stdout" || fail 'Binding diagnostics polluted command stdout'
grep -qF 'Running command through wan' "$TEST_ROOT/stderr" || fail 'Binding context missing from stderr'

CAPTURE_RESULT=0
: > "$CLI_COMMANDS"
assert_exit 0 use wan6 "$TEST_ROOT/capture arguments.sh" 'IPv6 argument'
[ "$(cat "$CLI_COMMANDS")" = init:readonly ] || fail 'Bound command initialized mutable runtime'
printf '%s\n' ipv6 eth6 2001:db8::2 0x003f0000 "$TEST_ROOT/lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0" > "$TEST_ROOT/expected-environment"
cmp -s "$TEST_ROOT/expected-environment" "$CLI_CAPTURE_ENV" || fail 'IPv6 binding environment changed'

printf 'NFT CLI regressions passed: argv, exit status, binding environment, family aliases, and missing-helper failure.\n'
