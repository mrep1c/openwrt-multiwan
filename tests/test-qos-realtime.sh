#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/realtime.sh"

grep -Fq "option adaptive_start_rate '1000'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "default config does not preserve the 1000 Adaptive baseline"
grep -Fq "option adaptive_custom_start_rate '1000'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "default config does not provide the custom Adaptive baseline"
grep -Fq "form.ListValue, 'adaptive_start_rate'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector is missing"
grep -Fq "o.value('1000', _('1000 kbit/s'))" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector does not offer 1000"
grep -Fq "o.value('1500', _('1500 kbit/s'))" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector does not offer 1500"
grep -Fq "o.value('custom', _('Custom'))" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector does not offer Custom"
grep -Fq "form.Value, 'adaptive_custom_start_rate'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI custom Adaptive baseline input is missing"
grep -Fq "o.datatype = 'range(300, 2000)'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI custom Adaptive baseline range is missing"
grep -Fq "o.depends({ realtime_rate_mode: 'adaptive', adaptive_start_rate: 'custom' })" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI custom Adaptive baseline input is not conditional"
grep -Fq 'mw_realtime_adaptive_range "$line_rate" "$ADAPTIVE_START_RATE" "$ADAPTIVE_CUSTOM_START_RATE"' \
    "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
    fail "Adaptive monitor does not pass the configured custom baseline"
grep -Fq "option adaptive_demand_reserve '300'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "default config does not preserve the 300 kbit/s Adaptive demand reserve"
grep -Fq "form.Value, 'adaptive_demand_reserve'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive demand reserve input is missing"
grep -Fq "o.datatype = 'range(0, 2000)'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive demand reserve range is missing"
grep -Fq 'config_get TARGET_RESERVE_KBIT hfsc adaptive_demand_reserve 300' \
    "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
    fail "Adaptive monitor does not load the configured demand reserve"
grep -Fq 'added exactly once to estimated realtime demand' \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI does not describe the literal Adaptive demand reserve"
for status_field in backlog_bytes instant_demand backlog_drain idle_hold; do
    grep -Fq "$status_field=" \
        "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
        fail "Adaptive status does not expose $status_field"
done
for controller_setting in \
    'BACKLOG_DRAIN_MS=200' \
    'SESSION_GRACE_MS=20000' \
    'DECREASE_CONFIRM_MS=5000' \
    'DECREASE_DROP_FREE_MS=10000' \
    'DECREASE_BACKLOG_FREE_MS=5000' \
    'DECREASE_REARM_MS=10000' \
    'DECREASE_INTERVAL_MS=5000'; do
    grep -Fq "$controller_setting" \
        "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
        fail "Adaptive controller setting is missing: $controller_setting"
done
for controller_helper in \
    mw_realtime_adaptive_demand \
    mw_realtime_adaptive_target \
    mw_realtime_adaptive_backlog_step \
    mw_realtime_adaptive_idle_state \
    mw_realtime_adaptive_decrease_ready; do
    grep -Fq "$controller_helper" \
        "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
        fail "Adaptive monitor does not use $controller_helper"
done
grep -A1 "createOption('PFIFOMIN'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" |
    grep -Fq "o.depends('gameqdisc', 'pfifo')" ||
    fail "LuCI PFIFO options are not conditional on PFIFO selection"
for netem_option in netemdelayms netemjitterms pktlossp; do
    grep -A1 "createOption('$netem_option'" \
        "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" |
        grep -Fq "o.depends('gameqdisc', 'netem')" ||
        fail "LuCI $netem_option is not conditional on NETEM selection"
done
grep -A8 "form.ListValue, 'netemdist'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" |
    grep -Fq "o.depends('gameqdisc', 'netem')" ||
    fail "LuCI NETEM distribution is not conditional on NETEM selection"

mw_realtime_adaptive_range 100000
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1000:2000 ] ||
    fail "default Adaptive range does not use the 2000 kbit/s ceiling"

mw_realtime_adaptive_range 100000 1500
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1500:2000 ] ||
    fail "1500 Adaptive start rate was not selected"

mw_realtime_adaptive_range 100000 custom 1250
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1250:2000 ] ||
    fail "custom Adaptive start rate was not selected"

mw_realtime_adaptive_range 100000 custom 2000
[ "$MW_RT_START:$MW_RT_CEILING" = 2000:2000 ] ||
    fail "maximum custom Adaptive start rate was not accepted"

mw_realtime_adaptive_range 4000 custom 1500
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1000:1000 ] ||
    fail "custom Adaptive start rate ignored the 25 percent link cap"

mw_realtime_adaptive_range 500 custom 1500
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 125:125:125 ] ||
    fail "Adaptive floor ignored a link cap below 300 kbit/s"

mw_realtime_adaptive_range 100000 invalid
[ "$MW_RT_START" -eq 1000 ] || fail "invalid Adaptive start rate did not fail safe to 1000"

mw_realtime_adaptive_range 100000 custom invalid
[ "$MW_RT_START" -eq 1000 ] || fail "invalid custom Adaptive start rate did not fail safe to 1000"

mw_realtime_adaptive_range 100000 custom 2001
[ "$MW_RT_START" -eq 1000 ] || fail "out-of-range custom Adaptive start rate did not fail safe to 1000"

mw_realtime_adaptive_profile_range 100000
[ "$MW_RT_PROFILE_START:$MW_RT_PROFILE_FLOOR:$MW_RT_PROFILE_CEILING" = 1000:1000:1000 ] ||
    fail "Adaptive selector changed the fixed finite-queue profile"

tc_stats='class hfsc 1:11 parent 1:1 rt m1 10000Kbit d 25.0ms m2 1000Kbit
 Sent 123456 bytes 789 pkt (dropped 4, overlimits 0 requeues 0)
 backlog 1500b 3p requeues 0'
mw_realtime_parse_tc_class_stats "$tc_stats" || fail "valid tc class statistics were rejected"
[ "$MW_RT_STATS_BYTES:$MW_RT_STATS_DROPS:$MW_RT_STATS_BACKLOG_BYTES:$MW_RT_STATS_BACKLOG_PACKETS" = 123456:4:1500:3 ] ||
    fail "tc class statistics were parsed incorrectly"
if mw_realtime_parse_tc_class_stats 'Sent invalid statistics'; then
    fail "malformed tc class statistics were accepted"
fi

mw_realtime_adaptive_demand 75000 1000 0 0 200
[ "$MW_RT_SERVED_RATE:$MW_RT_BACKLOG_GROWTH_RATE:$MW_RT_BACKLOG_DRAIN_RATE:$MW_RT_INSTANT_DEMAND" = 600:0:0:600 ] ||
    fail "served Adaptive demand was calculated incorrectly"

mw_realtime_adaptive_demand 75000 1000 1500 1000 200
[ "$MW_RT_SERVED_RATE:$MW_RT_BACKLOG_GROWTH_RATE:$MW_RT_BACKLOG_DRAIN_RATE:$MW_RT_INSTANT_DEMAND" = 600:4:60:664 ] ||
    fail "Adaptive backlog growth and drain demand were calculated incorrectly"

mw_realtime_adaptive_target 600 300 300 2000
[ "$MW_RT_ADAPTIVE_TARGET" -eq 900 ] || fail "Adaptive reserve was not added literally"
mw_realtime_adaptive_target 1980 300 300 2000
[ "$MW_RT_ADAPTIVE_TARGET" -eq 2000 ] || fail "Adaptive target ignored the 2000 kbit/s ceiling"
mw_realtime_adaptive_target 0 0 300 2000
[ "$MW_RT_ADAPTIVE_TARGET" -eq 300 ] || fail "Adaptive target ignored the floor"

mw_realtime_adaptive_backlog_step 60
[ "$MW_RT_BACKLOG_STEP" -eq 100 ] || fail "Adaptive backlog step was not rounded proportionally"
mw_realtime_adaptive_backlog_step 0
[ "$MW_RT_BACKLOG_STEP" -eq 50 ] || fail "Adaptive backlog step did not preserve the minimum increase"

mw_realtime_adaptive_idle_state 0 20000 1500 1000
[ "$MW_RT_IDLE_HOLD:$MW_RT_IDLE_REMAINING_MS:$MW_RT_IDLE_TARGET" = 1:20000:1500 ] || fail "Adaptive idle hold did not preserve the current rate immediately"
mw_realtime_adaptive_idle_state 19999 20000 1500 1000
[ "$MW_RT_IDLE_HOLD:$MW_RT_IDLE_REMAINING_MS:$MW_RT_IDLE_TARGET" = 1:1:1500 ] || fail "Adaptive idle hold released the current rate before the grace expired"
mw_realtime_adaptive_idle_state 20000 20000 1500 1000
[ "$MW_RT_IDLE_HOLD:$MW_RT_IDLE_REMAINING_MS:$MW_RT_IDLE_TARGET" = 0:0:1000 ] || fail "Adaptive idle hold did not return to baseline at the grace boundary"

mw_realtime_adaptive_decrease_ready 20000 15000 10000 10000 15000 15000 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 1 ] || fail "Adaptive decrease gates did not open at their exact thresholds"
mw_realtime_adaptive_decrease_ready 20000 15001 10000 10000 15000 15000 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 0 ] || fail "Adaptive decrease ignored the backlog-free gate"
mw_realtime_adaptive_decrease_ready 20000 15000 10001 10000 15000 15000 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 0 ] || fail "Adaptive decrease ignored the drop-free gate"
mw_realtime_adaptive_decrease_ready 20000 15000 10000 10001 15000 15000 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 0 ] || fail "Adaptive decrease ignored the post-increase gate"
mw_realtime_adaptive_decrease_ready 20000 15000 10000 10000 15001 15000 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 0 ] || fail "Adaptive decrease ignored the lower-demand confirmation gate"
mw_realtime_adaptive_decrease_ready 20000 15000 10000 10000 15000 15001 5000 10000 10000 5000 5000
[ "$MW_RT_DECREASE_READY" -eq 0 ] || fail "Adaptive decrease ignored the step interval"

printf 'QoS realtime-rate regression tests passed.\n'
