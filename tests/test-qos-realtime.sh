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
grep -Fq "form.ListValue, 'adaptive_start_rate'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector is missing"
grep -Fq "o.value('1000', _('1000 kbit/s'))" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector does not offer 1000"
grep -Fq "o.value('1500', _('1500 kbit/s'))" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive baseline selector does not offer 1500"
grep -Fq 'mw_realtime_adaptive_range "$line_rate" "$ADAPTIVE_START_RATE"' \
    "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
    fail "Adaptive monitor does not pass the configured baseline"
grep -Fq "option adaptive_demand_reserve '300'" \
    "$REPO_ROOT/multiwan-qos/etc/config/multiwan-qos" ||
    fail "default config does not preserve the 300 kbit/s Adaptive demand reserve"
grep -Fq "form.Value, 'adaptive_demand_reserve'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive demand reserve input is missing"
grep -Fq "o.datatype = 'range(0, 1800)'" \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI Adaptive demand reserve range is missing"
grep -Fq 'config_get TARGET_RESERVE_KBIT hfsc adaptive_demand_reserve 300' \
    "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" ||
    fail "Adaptive monitor does not load the configured demand reserve"
grep -Fq 'plus the configured Adaptive Demand Reserve' \
    "$REPO_ROOT/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/hfsc.js" ||
    fail "LuCI does not describe the configured demand reserve"
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
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1000:1800 ] ||
    fail "legacy Adaptive range changed without a selector"

mw_realtime_adaptive_range 100000 1500
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1500:1800 ] ||
    fail "1500 Adaptive start rate was not selected"

mw_realtime_adaptive_range 4000 1500
[ "$MW_RT_FLOOR:$MW_RT_START:$MW_RT_CEILING" = 300:1000:1000 ] ||
    fail "selected Adaptive start rate ignored the 25 percent link cap"

mw_realtime_adaptive_range 100000 invalid
[ "$MW_RT_START" -eq 1000 ] || fail "invalid Adaptive start rate did not fail safe to 1000"

mw_realtime_adaptive_profile_range 100000
[ "$MW_RT_PROFILE_START:$MW_RT_PROFILE_FLOOR:$MW_RT_PROFILE_CEILING" = 1000:1000:1000 ] ||
    fail "Adaptive selector changed the fixed finite-queue profile"

printf 'QoS realtime-rate regression tests passed.\n'
