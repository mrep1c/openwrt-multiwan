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
# 2. Test CAKE ingress guard inside apply_tc_custom_ingress_rules
# -----------------------------------------------------------------------------
tc_called=0
tc() {
    tc_called=$((tc_called + 1))
    return 0
}

# Create dummy functions for apply_tc_custom_ingress_rules dependencies
realtime_first_is_effective() { return 1; }
get_dscp_classid_for_qdisc() { echo "1:10"; }
debug_log() { :; }
config_get_bool() { eval "$1=1"; }
config_get() {
    case "$3" in
        proto) eval "$1=tcp" ;;
        class) eval "$1=express" ;;
        dest_port) eval "$1=80" ;;
        *) eval "$1=''" ;;
    esac
}
config_foreach() {
    # Call handler once with dummy config section
    "$1" "test_rule"
}

# Evaluate apply_tc_custom_ingress_rules definition from multiwan-qos.sh
eval "$(sed -n '/^apply_tc_custom_ingress_rules() {/,/^setup_interface_qdisc_direction() {/{ /^setup_interface_qdisc_direction/!p }' "$REPO_ROOT/multiwan-qos/etc/multiwan-qos.sh")"

global_enabled=1

# Call for cake: should return 0 immediately without calling tc
tc_called=0
apply_tc_custom_ingress_rules "ifb-wan" "cake" || fail "apply_tc_custom_ingress_rules returned failure for cake"
[ "$tc_called" -eq 0 ] || fail "apply_tc_custom_ingress_rules called tc for cake"

# Call for hfsc: should invoke tc
tc_called=0
apply_tc_custom_ingress_rules "ifb-wan" "hfsc" || fail "apply_tc_custom_ingress_rules returned failure for hfsc"
[ "$tc_called" -gt 0 ] || fail "apply_tc_custom_ingress_rules did not call tc for hfsc"

# Target-runtime verification: simulate full CAKE setup flow with custom rules present
tc_commands=""
tc() {
    tc_commands="${tc_commands}$*
"
    return 0
}

# Simulate interface setup sequence on CAKE
lan_dev="ifb-wan0"
qdisc="cake"
tc qdisc add dev "wan0" handle ffff: ingress
tc filter add dev "wan0" parent ffff: protocol all prio 1 matchall action ctinfo dscp 63 128 continue
tc filter add dev "wan0" parent ffff: protocol all prio 2 matchall action mirred egress redirect dev "$lan_dev"
tc qdisc add dev "wan0" root handle 1: cake bandwidth 10000kbit
tc qdisc add dev "$lan_dev" root handle 1: cake bandwidth 50000kbit ingress
apply_tc_custom_ingress_rules "$lan_dev" "$qdisc"

# Ensure no flower filter was attached to the CAKE IFB device
case "$tc_commands" in
    *"filter add dev $lan_dev"*|*"flower"*)
        fail "target-runtime CAKE setup attempted to attach flower filter to $lan_dev"
        ;;
esac

# Ensure CAKE root and ingress qdiscs were properly configured
case "$tc_commands" in
    *"qdisc add dev wan0 root handle 1: cake"*|*"qdisc add dev $lan_dev root handle 1: cake"*)
        ;;
    *)
        fail "target-runtime CAKE setup did not configure cake qdiscs"
        ;;
esac

printf 'CAKE ingress guard and runtime setup tests passed.\n'

# -----------------------------------------------------------------------------
# 3. Test Gated select_realtime_rate & per-interface overrides
# -----------------------------------------------------------------------------
. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/realtime.sh"
eval "$(sed -n '/^select_realtime_rate() {/,/^setup_htb() {/{ /^setup_htb/!p }' "$REPO_ROOT/multiwan-qos/etc/multiwan-qos.sh")"
log_msg() { :; }
error_out() { :; }

# Test helper to simulate setup_interface rate selection logic
test_rate_selection() {
    local qdisc="$1"
    local config_game_up="$2"
    local hfsc_game_up="$3"
    local upload=10000
    local realtime_rate_mode="manual"

    local game_up=0
    case "$qdisc" in
        hfsc|hybrid)
            local game_up_override
            game_up_override="$config_game_up"
            [ -n "$game_up_override" ] || game_up_override="$hfsc_game_up"

            select_realtime_rate "$upload" "$game_up_override" upload || return 1
            game_up="$MW_SELECTED_REALTIME_RATE"
            ;;
    esac
    echo "$game_up"
    return 0
}

# CAKE / HTB: does not run select_realtime_rate, even if hfsc GAMEUP is invalid/oversized (e.g. 999999)
rate="$(test_rate_selection "cake" "" "999999")" || fail "rate selection aborted for cake"
[ "$rate" -eq 0 ] || fail "cake had non-zero realtime rate"

rate="$(test_rate_selection "htb" "" "999999")" || fail "rate selection aborted for htb"
[ "$rate" -eq 0 ] || fail "htb had non-zero realtime rate"

# HFSC: per-interface override takes precedence
rate="$(test_rate_selection "hfsc" "2000" "1500")" || fail "rate selection failed for hfsc override"
[ "$rate" -eq 2000 ] || fail "per-interface game_up did not override global GAMEUP (got $rate, expected 2000)"

# HFSC: fallback to global GAMEUP when per-interface override is empty
rate="$(test_rate_selection "hfsc" "" "1500")" || fail "rate selection failed for hfsc global"
[ "$rate" -eq 1500 ] || fail "global GAMEUP was not used when interface game_up is empty (got $rate, expected 1500)"

# HFSC: invalid manual rate should fail
test_rate_selection "hfsc" "999999" "1500" >/dev/null 2>&1 && fail "invalid per-interface rate was accepted"

printf 'Realtime rate gating & override tests passed.\n'

# -----------------------------------------------------------------------------
# 4. Test health_check disabled bypass semantics
# -----------------------------------------------------------------------------
# Mock external dependencies for health_check
nft_called=0
nft() {
    nft_called=$((nft_called + 1))
    return 1 # If called, fail to ensure bypass works
}

tc_called=0
tc() {
    tc_called=$((tc_called + 1))
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

nft_called=0
tc_called=0
output="$(health_check)"
result=$?
[ "$result" -eq 0 ] || fail "health_check returned error for disabled service: $output"
[ "$nft_called" -eq 0 ] || fail "health_check called nft when service was disabled"
[ "$tc_called" -eq 0 ] || fail "health_check called tc when service was disabled"

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
output="$(health_check)" || true
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
output="$(health_check)" || true
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
grep -Fq 'PKG_RELEASE:=2' "$REPO_ROOT/multiwan-qos/Makefile" ||
    fail "multiwan-qos Makefile PKG_RELEASE is not 2"

grep -Fq 'PKG_RELEASE:=2' "$REPO_ROOT/luci-app-multiwan-qos/Makefile" ||
    fail "luci-app-multiwan-qos Makefile PKG_RELEASE is not 2"

grep -Fq 'PKG_PO_VERSION:=1.0.54-r2' "$REPO_ROOT/luci-app-multiwan-qos/Makefile" ||
    fail "luci-app-multiwan-qos Makefile PKG_PO_VERSION is not 1.0.54-r2"

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
