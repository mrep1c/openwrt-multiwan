#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-qos-fixes.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Test validate_ip_address
# -----------------------------------------------------------------------------
export IPKG_INSTROOT="$REPO_ROOT/multiwan-qos"
action=none
set -- none
. "$REPO_ROOT/multiwan-qos/etc/init.d/multiwan-qos"

# Valid IPv4 vectors
for ip in 0.0.0.0 255.255.255.255 192.168.1.1 10.0.0.50 1.2.3.4 172.16.254.1; do
    validate_ip_address "$ip" || fail "valid IP '$ip' was rejected by validate_ip_address"
done

# Invalid IPv4 vectors
for ip in "" "192.168.1" "192.168.1.1.1" "192.168.1.256" "256.0.0.1" \
          "01.1.1.1" "192.168.01.1" "000.0.0.0" "0.0.0.00" "192.168..1" \
          ".192.168.1.1" "192.168.1.1." "a.b.c.d" "192.168.1.1a" \
          "-1.0.0.1" "192.168. 1.1" "..." "192.168.1.01"; do
    validate_ip_address "$ip" && fail "invalid IP '$ip' was accepted by validate_ip_address"
done

printf 'IP validation tests passed.\n'

# -----------------------------------------------------------------------------
# 2. Exercise the shipped interface setup, with network operations mocked
# -----------------------------------------------------------------------------
. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/realtime.sh"
for function_name in setup_interface select_realtime_rate realtime_first_is_effective \
    get_dscp_classid_for_qdisc apply_tc_custom_ingress_rules setup_cake append_cake_opt; do
    eval "$(sed -n "/^$function_name() {/,/^}/p" "$REPO_ROOT/multiwan-qos/etc/multiwan-qos.sh")"
done

TC_LOG="$TEST_ROOT/tc.log"
tc() { printf '%s\n' "$*" >> "$TC_LOG"; }
ip() { return 0; }
print_msg() { :; }
log_msg() { :; }
error_out() { :; }
debug_log() { :; }
qdisc_setup_failed() { exit 77; }
cleanup_interface_state() { printf 'cleanup %s\n' "$1" >> "$TC_LOG"; }
disable_qos_offloads() { :; }
disable_configured_extra_offloads() { :; }
record_realtime_first_status() { :; }
get_tx_queue_count() { echo 1; }
cake_memory_limit() { echo 1048576; }
get_cake_link_params() { :; }
select_cake_qdisc() { REPLY=cake; }
record_cake_qdisc_type() { :; }
setup_interface_qdisc_direction() { printf 'shape %s\n' "$*" >> "$TC_LOG"; }
config_get_bool() { eval "$1=1"; }
config_get() {
    local mock_value="${4:-}"
    case "$2:$3" in
        *:device) mock_value="$2" ;;
        *:upload) mock_value=10000 ;;
        *:download) mock_value=20000 ;;
        *:qdisc) mock_value="$config_qdisc" ;;
        *:game_up) mock_value="$config_game_up" ;;
        *:game_down) mock_value="$config_game_down" ;;
        hfsc:GAMEUP) mock_value="$global_game_up" ;;
        hfsc:GAMEDOWN) mock_value="$global_game_down" ;;
        test_rule:proto) mock_value=tcp ;;
        test_rule:class) mock_value=ef ;;
        test_rule:dest_port) mock_value=443 ;;
    esac
    eval "$1=\"\$mock_value\""
}
config_foreach() { "$1" test_rule; }

global_enabled=1 realtime_first_scheduling=0 realtime_rate_mode=manual
ACKRATE=0 UDP_RATE_LIMIT_ENABLED=0 TCP_UPGRADE_ENABLED=0
TCP_DOWNPRIO_INITIAL_ENABLED=0 TCP_DOWNPRIO_SUSTAINED_ENABLED=0 SFO_ENABLED=0
WAN_INTERFACES='' NFT_TCPMSS_RULES='' NFT_ACK_RULES='' NFT_UDP_RATE_RULES=''
NFT_TCP_UPGRADE_RULES='' NFT_DOWNPRIO_RULES=''
ACK_FILTER_EGRESS=0 PRIORITY_QUEUE_EGRESS=diffserv4 PRIORITY_QUEUE_INGRESS=diffserv4
HOST_ISOLATION=0 RTT=100 LINK_COMPENSATION=''
EXTRA_PARAMETERS_EGRESS='' EXTRA_PARAMETERS_INGRESS=''
NAT_EGRESS=0 NAT_INGRESS=0 WASHDSCPUP=0 WASHDSCPDOWN=0 AUTORATE_INGRESS=0

config_game_up=2000 config_game_down=3000
global_game_up=999999 global_game_down=999999
for config_qdisc in hfsc hybrid; do
    : > "$TC_LOG"
    setup_interface wan0 || fail "$config_qdisc setup failed with per-interface overrides"
    grep -Fq "shape wan0 10000 2000 wan $config_qdisc" "$TC_LOG" || fail "upload override lost"
    grep -Fq "shape ifb-wan0 20000 3000 lan $config_qdisc" "$TC_LOG" || fail "download override lost"
    grep -Fq 'flower ip_proto tcp src_port 443 classid 1:11' "$TC_LOG" || fail "classful ingress rule lost"
done

config_game_up='' config_game_down='' global_game_up=1600 global_game_down=1700
: > "$TC_LOG"
setup_interface wan0 || fail "global fallback failed"
grep -Fq 'shape wan0 10000 1600 wan hybrid' "$TC_LOG" || fail "global upload fallback lost"
grep -Fq 'shape ifb-wan0 20000 1700 lan hybrid' "$TC_LOG" || fail "global download fallback lost"

# A second WAN must ignore irrelevant HFSC reserves and keep its own topology.
global_game_up=999999 global_game_down=999999 config_qdisc=cake
setup_interface wan1 || fail "CAKE setup rejected irrelevant reserves"
grep -Fq 'qdisc add dev wan1 root handle 1: cake bandwidth 10000kbit' "$TC_LOG" || fail "CAKE upload missing"
grep -Fq 'qdisc add dev ifb-wan1 root cake bandwidth 20000kbit ingress' "$TC_LOG" || fail "CAKE download missing"
grep -Fq 'filter add dev ifb-wan1' "$TC_LOG" && fail "CAKE received a custom ingress filter"
grep -Fq 'action ctinfo dscp 63 128 continue' "$TC_LOG" || fail "ctinfo restoration missing"
grep -Fq 'action mirred egress redirect dev ifb-wan1' "$TC_LOG" || fail "IFB redirect missing"
config_qdisc=htb
setup_interface wan2 || fail "HTB setup rejected irrelevant reserves"
grep -Fq 'shape wan2 10000 0 wan htb' "$TC_LOG" || fail "HTB upload setup missing"
grep -Fq 'shape ifb-wan2 20000 0 lan htb' "$TC_LOG" || fail "HTB download setup missing"

config_qdisc=hfsc
for direction in up down; do
    for invalid in 0 10000 999999; do
        config_game_up=2000 config_game_down=3000
        if [ "$direction" = up ]; then config_game_up="$invalid";
        else config_game_down=$((invalid * 2)); fi
        : > "$TC_LOG"
        result=0
        (setup_interface wan0) || result=$?
        [ "$result" -eq 77 ] || fail "invalid $direction reserve did not reach setup failure"
        [ ! -s "$TC_LOG" ] || fail "invalid reserve reached qdisc mutation"
    done
done

config_game_up=999999 config_game_down=999999
adaptive_start_rate=1000 adaptive_custom_start_rate=1000
for realtime_rate_mode in default adaptive; do
    expected=1500
    [ "$realtime_rate_mode" != adaptive ] || expected=1000
    : > "$TC_LOG"
    setup_interface wan0 || fail "$realtime_rate_mode rejected unused manual reserves"
    grep -Fq "shape wan0 10000 $expected wan hfsc" "$TC_LOG" || fail "wrong $realtime_rate_mode upload reserve"
    grep -Fq "shape ifb-wan0 20000 $expected lan hfsc" "$TC_LOG" || fail "wrong $realtime_rate_mode download reserve"
done

printf 'Interface setup, CAKE ingress guard, and realtime rate tests passed.\n'

# -----------------------------------------------------------------------------
# 4. Test health_check disabled bypass semantics
# -----------------------------------------------------------------------------
# Mock external dependencies for health_check
nft() {
    printf 'nft %s\n' "$*" >> "$TC_LOG"
    return 1 # If called, fail to ensure bypass works
}

tc() {
    printf 'tc %s\n' "$*" >> "$TC_LOG"
    return 1 # If called, fail to ensure bypass works
}

check_package() {
    return 0 # All packages present
}

# Test 4a: Service disabled (00) with valid config and packages -> clean (errors=0)
load_and_fix_config() { return 0; }
enabled() { return 1; }
config_get_bool() {
    # global.enabled = 0, agent.enabled = 0
    eval "$1=0"
}
config_load() { :; }
config_foreach() {
    # Mock configured interface
    local handler="$1"
    config_get() { eval "$1=eth0"; }
    "$handler" "wan"
}

: > "$TC_LOG"
output="$(health_check)"
result=$?
[ "$result" -eq 0 ] || fail "health_check returned error for disabled service: $output"
[ ! -s "$TC_LOG" ] || fail "health_check called nft or tc when service was disabled"

case "$output" in
    *"service:disabled;"*) ;;
    *) fail "health_check output missing 'service:disabled;': $output" ;;
esac
case "$output" in
    *"nft:disabled;"*) ;;
    *) fail "health_check output missing 'nft:disabled;': $output" ;;
esac
case "$output" in
    *"tc:disabled;"*) ;;
    *) fail "health_check output missing 'tc:disabled;': $output" ;;
esac
case "$output" in
    *"config:ok;"*) ;;
    *) fail "health_check output missing 'config:ok;': $output" ;;
esac
case "$output" in
    *"packages:ok;"*) ;;
    *) fail "health_check output missing 'packages:ok;': $output" ;;
esac
case "$output" in
    *"errors=0"*) ;;
    *) fail "health_check output reported non-zero errors for clean disabled state: $output" ;;
esac

# Test 4b: Service disabled (00) with broken config -> reports config:failed and errors=1
load_and_fix_config() { return 1; }
result=0
output="$(health_check)" || result=$?
[ "$result" -eq 1 ] || fail "health_check accepted broken config"
case "$output" in
    *"config:failed;"*) ;;
    *) fail "health_check did not report 'config:failed;' on broken config: $output" ;;
esac
case "$output" in
    *"errors=1"*) ;;
    *) fail "health_check did not increment errors on broken config: $output" ;;
esac

# Test 4c: Service disabled (00) with missing package -> reports packages:missing and errors=1
load_and_fix_config() { return 0; }
check_package() {
    if [ "$1" = "tc-full" ]; then
        return 1
    fi
    return 0
}
result=0
output="$(health_check)" || result=$?
[ "$result" -eq 1 ] || fail "health_check accepted a missing package"
case "$output" in
    *"packages:missing:tc-full"*) ;;
    *) fail "health_check did not report missing package: $output" ;;
esac
case "$output" in
    *"errors=1"*) ;;
    *) fail "health_check did not count missing package error: $output" ;;
esac

printf 'Health check disabled semantics tests passed.\n'

# -----------------------------------------------------------------------------
# 5. Test Makefiles and LuCI settings.js metadata
# -----------------------------------------------------------------------------
sh "$REPO_ROOT/scripts/check-version-sync.sh" || fail "package versions are out of sync"

grep -Fq "o = s_interfaces.option(form.Value, 'game_up'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/settings.js" ||
    fail "settings.js missing game_up option"

grep -Fq "o = s_interfaces.option(form.Value, 'game_down'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/settings.js" ||
    fail "settings.js missing game_down option"

grep -Fq "# option game_up '2000'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "starter config multiwan-qos missing game_up example"

grep -Fq "# option game_down '5000'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "starter config multiwan-qos missing game_down example"

printf 'Packaging and LuCI metadata checks passed.\n'

printf 'ALL QoS fix regression tests passed successfully.\n'
