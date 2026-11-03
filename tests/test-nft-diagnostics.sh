#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-diagnostics.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/state"
multiwan_nft_init() { fail 'Read-only diagnostics initialized mutable runtime state'; }
eval "$(sed '/^\. /d; /^main "\$@"$/d' "$REPO_ROOT/luci-app-multiwan-nft/root/usr/libexec/luci-multiwan-nft")"
[ ! -e "$MULTIWAN_NFT_STATUS_DIR" ] || fail 'Loading diagnostics created service runtime state'
mkdir -p "$MULTIWAN_NFT_STATUS_DIR/iface_state"
: > "$TEST_ROOT/commands"
RULE_MODE=online

config_load() { [ "${CONFIG_LOAD_FAIL:-0}" -eq 0 ]; }
config_get() {
    case "$2:$3" in
        wan6:family) export "$1=ipv6" ;;
        wan:family) export "$1=ipv4" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_foreach() {
    "$1" wan "${3:-}"
    "$1" wan6 "${3:-}"
}
config_list_foreach() {
    local iface="$1" callback="$3"
    shift 3
    case "$iface" in
        wan) "$callback" 1.1.1.1 "$@" ;;
        wan6) "$callback" 2606:4700:4700::1111 "$@" ;;
    esac
}
ubus() {
    case "$*" in
        'call network.interface.wan_4 status'|'call network.interface.wan6_6 status') return 0 ;;
        *) return 1 ;;
    esac
}
network_get_gateway() {
    printf 'gateway4 %s\n' "$2" >> "$TEST_ROOT/commands"
    [ "$2" = wan_4 ] || fail 'IPv4 gateway queried the wrong netifd interface'
    export "$1=198.51.100.1"
}
network_get_gateway6() {
    printf 'gateway6 %s\n' "$2" >> "$TEST_ROOT/commands"
    [ "$2" = wan6_6 ] || fail 'IPv6 gateway queried the wrong netifd interface'
    export "$1=fe80::1"
}
network_get_device() {
    case "$2" in
        wan_4) export "$1=eth4" ;;
        wan6_6) export "$1=eth6" ;;
        *) fail "Device queried unknown netifd interface: $2" ;;
    esac
}
ping() { printf 'ping %s\n' "$*" >> "$TEST_ROOT/commands"; }
ping6() { printf 'ping6 %s\n' "$*" >> "$TEST_ROOT/commands"; }
ip() {
    printf 'ip %s\n' "$*" >> "$TEST_ROOT/commands"
    case "$*" in
        '-4 rule list')
            printf '%s\n' '1001: from all iif eth4 lookup 1' '1001: from all oif eth4 lookup 1' \
                '2001: from all fwmark 0x10000/0x3f0000 lookup 1' '3001: from all fwmark 0x10000/0x3f0000 unreachable'
            ;;
        '-6 rule list')
            case "$RULE_MODE" in
                online)
                    printf '%s\n' '1002: from all iif eth6 lookup 2' '1002: from all oif eth6 lookup 2' \
                        '2002: from all fwmark 0x20000/0x3f0000 lookup 2' '3002: from all fwmark 0x20000/0x3f0000 unreachable'
                    ;;
                offline)
                    printf '%s\n' '1002: from all iif eth6 lookup 2' \
                        '1002: from 2001:db8::2 to 2606:4700:4700::1111 ipproto ipv6-icmp oif eth6 lookup 2' \
                        '3002: from all fwmark 0x20000/0x3f0000 unreachable'
                    ;;
                wrong-preferences)
                    printf '%s\n' '11002: from all iif eth6 lookup 2' '11002: from all oif eth6 lookup 2' \
                        '12002: from all fwmark 0x20000/0x3f0000 lookup 2' '13002: from all fwmark 0x20000/0x3f0000 unreachable'
                    ;;
            esac
            ;;
        '-4 route list table 1') printf '%s\n' 'default via 198.51.100.1 dev eth4' ;;
        '-6 route list table 2') printf '%s\n' 'default via fe80::1 dev eth6' ;;
        *) fail "Unexpected ip command: $*" ;;
    esac
}
assert_command() { grep -Fxq -- "$1" "$TEST_ROOT/commands" || fail "Command not run: $1"; }

diag_gateway wan > "$TEST_ROOT/gateway4" || fail 'IPv4 gateway diagnostic failed'
diag_gateway wan6 > "$TEST_ROOT/gateway6" || fail 'IPv6 gateway diagnostic failed'
diag_tracking wan > "$TEST_ROOT/track4" || fail 'IPv4 tracking diagnostic failed'
diag_tracking wan6 > "$TEST_ROOT/track6" || fail 'IPv6 tracking diagnostic failed'
assert_command 'gateway4 wan_4'
assert_command 'gateway6 wan6_6'
assert_command 'ping -c 5 -W 1 -I eth4 198.51.100.1'
assert_command 'ping6 -c 5 -W 1 -I eth6 fe80::1'
assert_command 'ping -c 5 -W 1 -I eth4 1.1.1.1'
assert_command 'ping6 -c 5 -W 1 -I eth6 2606:4700:4700::1111'
# BusyBox can resolve applets outside PATH, so model missing ping6 explicitly.
(command() { return 1; }; diag_ping ipv6 -c 1 ::1) || fail 'Single-binary IPv6 ping fallback failed'
assert_command 'ping -6 -c 1 ::1'

printf '%s\n' online > "$MULTIWAN_NFT_STATUS_DIR/iface_state/wan6"
diag_rules wan6 > "$TEST_ROOT/rules6" || fail 'IPv6 rules diagnostic failed'
grep -qF 'All required IP rules for interface "wan6" found' "$TEST_ROOT/rules6" || fail 'Complete IPv6 rules were not recognized'
diag_rules wan > "$TEST_ROOT/rules4" || fail 'IPv4 rules diagnostic failed after IPv6 lookup'
grep -qF 'All required IP rules for interface "wan" found' "$TEST_ROOT/rules4" || fail 'Interface ID was not reset between rule lookups'
assert_command 'ip -6 rule list'
assert_command 'ip -4 rule list'

RULE_MODE=wrong-preferences
diag_rules wan6 > "$TEST_ROOT/rules-wrong"
grep -qF 'Incomplete IP rules' "$TEST_ROOT/rules-wrong" || fail 'Substring preferences were mistaken for exact priorities'
if grep -qF 'All required IP rules' "$TEST_ROOT/rules-wrong"; then fail 'Incorrect preferences passed rule diagnostics'; fi
RULE_MODE=offline
printf '%s\n' offline > "$MULTIWAN_NFT_STATUS_DIR/iface_state/wan6"
diag_rules wan6 > "$TEST_ROOT/rules-offline"
grep -qF 'All required IP rules for offline interface "wan6" found (isolated for recovery)' "$TEST_ROOT/rules-offline" || fail 'Expected offline isolation was reported as missing lookup rules'

diag_routes wan6 > "$TEST_ROOT/routes6" || fail 'IPv6 route diagnostic failed'
diag_routes wan > "$TEST_ROOT/routes4" || fail 'IPv4 route diagnostic failed after IPv6 lookup'
assert_command 'ip -6 route list table 2'
assert_command 'ip -4 route list table 1'
if (diag_routes nonexistent) > "$TEST_ROOT/missing-route" 2>&1; then fail 'Unknown interface reused the previous table ID'; fi
if (diag_rules nonexistent) > "$TEST_ROOT/missing-rules" 2>&1; then fail 'Unknown interface reused the previous rule ID'; fi
before=$(wc -l < "$TEST_ROOT/commands")
CONFIG_LOAD_FAIL=1
if diag_cmd gateway wan > "$TEST_ROOT/failed-config" 2>&1; then fail 'Diagnostic ignored failed configuration load'; fi
[ "$(wc -l < "$TEST_ROOT/commands")" -eq "$before" ] || fail 'Failed configuration load launched a probe'
CONFIG_LOAD_FAIL=0
diag_cmd routes wan6 > "$TEST_ROOT/dispatched-routes" || fail 'Read-only diagnostic dispatch failed'

printf 'NFT diagnostics regressions passed: read-only loading, configuration failures, family probes, rules/routes and offline isolation.\n'
