#!/bin/sh
# Run the real controller functions with private state and mocked kernel calls.
set -u
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_PARENT="$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd)"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/qos-freshness.XXXXXX")" || exit 1
cleanup() {
    case "$TEST_ROOT" in "$TEST_PARENT"/qos-freshness.*) rm -rf -- "$TEST_ROOT" ;; esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/realtime.sh"
eval "$(sed -n '7,/^process_interface()/p' "$REPO_ROOT/multiwan-qos/usr/sbin/multiwan-qos-adaptive" |
    sed '$d' | sed 's|/sys/class/net/|$TEST_ROOT/sys/|g')"
STATE_ROOT="$TEST_ROOT/state"
RESTARTING="$TEST_ROOT/restarting"
LOCK_DIR="$TEST_ROOT/lock"
MW_ADAPTIVE_AGENT_SESSION_ID=''
FRESHNESS_MODE=auto
FRESHNESS_TARGET_MS=18
MAXDEL=24
PFIFOMIN=5
PACKETSIZE=450
ADAPTIVE_START_RATE=1000
ADAPTIVE_CUSTOM_START_RATE=1000
LOCK_HELD=0
LOCK_BUSY=0
FAIL_CLASS=0
FAIL_QUEUE=0
FAIL_QUEUE_PARENT=''
MISMATCH=0
FAIL_STATUS_MOVE=0
FAIL_STATS=0
SENT_BYTES=0
DROP_COUNT=0
BACKLOG_BYTES=0
BACKLOG_PACKETS=0
mkdir -p "$TEST_ROOT/kernel" "$TEST_ROOT/sys"
log() { :; }
mv() {
    case "${3:-}" in
        */status)
            [ "$2" = "$3.$$" ] || fail 'status was not written to a private temporary file'
            grep -q ' state=' "$2" || fail 'incomplete status was published'
            [ "$FAIL_STATUS_MOVE" -eq 0 ] || return 1
            ;;
    esac
    command mv "$@"
}
mw_lock_acquire() {
    [ "$LOCK_BUSY" -eq 0 ] || return 1
    LOCK_HELD=1
    MW_LOCK_TOKEN=test
}
mw_lock_release_for() {
    [ "$LOCK_HELD" -eq 1 ] || fail 'released an unowned lock'
    LOCK_HELD=0
}
tc() {
    local device kind limit parent key handle
    case "$1:$2" in
        -s:class)
            printf 'stats\n' >>"$TEST_ROOT/reads"
            [ "$FAIL_STATS" -eq 0 ] || return 1
            printf 'class hfsc 1:11 parent 1:1\n Sent %s bytes 20 pkt (dropped %s, overlimits 0 requeues 0)\n backlog %s %sp requeues 0\n' \
                "$SENT_BYTES" "$DROP_COUNT" "$BACKLOG_BYTES" "$BACKLOG_PACKETS"
            ;;
        -j:qdisc)
            printf 'qdisc\n' >>"$TEST_ROOT/reads"
            device="$5"
            parent="$7"; key="$device"; handle=10:
            case "$parent" in 10:1|10:2|10:3) key="$device-${parent#10:}"; handle="10${parent#10:}:" ;; esac
            kind="$(cat "$TEST_ROOT/kernel/$key.kind")"
            limit="$(cat "$TEST_ROOT/kernel/$key.limit")"
            [ "$MISMATCH" -eq 0 ] || [ ! -e "$TEST_ROOT/kernel/$key.changed" ] || limit=$((limit + 1))
            printf '[{"kind":"%s","handle":"%s","options":{"limit":%s}}]\n' "$kind" "$handle" "$limit"
            ;;
        qdisc:change)
            [ "$LOCK_HELD" -eq 1 ] || fail 'queue changed outside the refresh lock'
            device="$4"
            parent="$6"; key="$device"; handle=10:
            case "$parent" in 10:1|10:2|10:3) key="$device-${parent#10:}"; handle="10${parent#10:}:" ;; esac
            [ "$8" = "$handle" ] || fail 'queue handle changed'
            [ "$9" = "$(cat "$TEST_ROOT/kernel/$key.kind")" ] || fail 'queue kind changed'
            printf '%s\n' "$*" >>"$TEST_ROOT/updates"
            if [ "$FAIL_QUEUE_PARENT" = "$parent" ]; then FAIL_QUEUE_PARENT=''; return 1; fi
            if [ "$FAIL_QUEUE" -eq 1 ]; then FAIL_QUEUE=0; return 1; fi
            printf '%s\n' "${11}" >"$TEST_ROOT/kernel/$key.limit"
            : >"$TEST_ROOT/kernel/$key.changed"
            if [ "$9" = netem ]; then shift 9; printf '%s\n' "$*" >"$TEST_ROOT/kernel/$key.netem"; fi
            ;;
        class:change)
            [ "$LOCK_HELD" -eq 1 ] || fail 'class changed outside the refresh lock'
            printf '%s\n' "$*" >>"$TEST_ROOT/updates"
            if [ "$FAIL_CLASS" -eq 1 ]; then FAIL_CLASS=0; return 1; fi
            printf '%s\n' "${16%kbit}" >"$TEST_ROOT/kernel/$4.rate"
            ;;
        *) fail "unexpected kernel command: tc $*" ;;
    esac
}
jsonfilter() {
    local data="$2" tail kind handle limit
    [ "$#" -eq 8 ] || [ "$#" -eq 6 ] || return 1
    tail="${data#*\"kind\":\"}"; kind="${tail%%\"*}"
    tail="${data#*\"handle\":\"}"; handle="${tail%%\"*}"
    tail="${data#*\"limit\":}"; limit="${tail%%\}*}"
    printf '%s\n' "$kind" "$handle"
    [ "$#" -ne 8 ] || printf '%s\n' "$limit"
    return 0
}
fixture() {
    DEVICE="$1"
    DIRECTION=wan
    LINE_RATE=100000
    SHAPER_RATE=100000
    GAME_QDISC="$2"
    GAME_QDISC_CHILD="${4:-bfifo}"
    ADAPTIVE_QUEUE_BUDGET="$3"
    ADAPTIVE_FRESHNESS=0
    MW_ADAPTIVE_AGENT_SESSION_ID=''
    FRESHNESS_MODE=auto; FRESHNESS_TARGET_MS=18
    NETEM_DIRECTION=both; NETEM_DELAY_MS=0; NETEM_JITTER_MS=0; NETEM_DIST=normal; NETEM_LOSS=none
    ADAPTIVE_START_RATE=1000
    ADAPTIVE_CUSTOM_START_RATE=1000
    SENT_BYTES=0; DROP_COUNT=0; BACKLOG_BYTES=0b; BACKLOG_PACKETS=0
    FAIL_QUEUE=0; FAIL_QUEUE_PARENT=''; FAIL_CLASS=0; LOCK_BUSY=0; MISMATCH=0; FAIL_STATUS_MOVE=0; FAIL_STATS=0
    mkdir -p "$TEST_ROOT/sys/$DEVICE"
    printf '1500\n' >"$TEST_ROOT/sys/$DEVICE/mtu"
    printf '%s\n' "$GAME_QDISC" >"$TEST_ROOT/kernel/$DEVICE.kind"
    case "$GAME_QDISC" in pfifo) printf '5\n' ;; netem) printf '12\n' ;; *) printf '2250\n' ;; esac >"$TEST_ROOT/kernel/$DEVICE.limit"
    if [ "$GAME_QDISC" = qfq ]; then
        for child in 1 2 3; do
            printf '%s\n' "$GAME_QDISC_CHILD" >"$TEST_ROOT/kernel/$DEVICE-$child.kind"
            case "$GAME_QDISC_CHILD" in pfifo) printf '5\n' ;; *) printf '2250\n' ;; esac >"$TEST_ROOT/kernel/$DEVICE-$child.limit"
        done
    fi
    printf '1000\n' >"$TEST_ROOT/kernel/$DEVICE.rate"
    : >"$TEST_ROOT/updates"
    : >"$TEST_ROOT/reads"
}
sample() {
    MW_ADAPTIVE_LOOP_NOW_MS="$1"
    SENT_BYTES=$((SENT_BYTES + $2))
    DROP_COUNT=$((DROP_COUNT + $3))
    BACKLOG_BYTES="${4:-0b}"
    BACKLOG_PACKETS="${5:-0}"
    process_direction "$DEVICE" "$LINE_RATE" "$SHAPER_RATE" "$DIRECTION"
}
expect() {
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" = "$1" ] || fail "$DEVICE: wrong kernel rate"
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.limit")" = "$2" ] || fail "$DEVICE: wrong kernel FIFO limit"
    [ "$LOCK_HELD" -eq 0 ] || fail 'lock leaked'
}
status_has() {
    grep -Fq " $1 " "$STATE_ROOT/$DEVICE-$DIRECTION/status" || fail "$DEVICE: missing status $1"
}

fixture agent-history bfifo 0
sample 90000 0 0
sample 91000 250000 0
printf '1800\n' >"$STATE_ROOT/$DEVICE-wan/slow_rate"
printf '1600\n' >"$STATE_ROOT/$DEVICE-wan/peak_1"
MW_ADAPTIVE_AGENT_SESSION_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
sample 92000 12500 0
[ "$(cat "$STATE_ROOT/$DEVICE-wan/slow_rate")" -gt 1700 ] || fail 'agent event erased active demand history'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/peak_2")" -eq 1600 ] || fail 'agent event erased burst history'
MW_ADAPTIVE_AGENT_SESSION_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
sample 93000 0 0
sample 94000 12500 0
[ "$(cat "$STATE_ROOT/$DEVICE-wan/slow_rate")" -gt 1600 ] || fail 'agent event erased history during idle grace'
sample 114000 0 0
status_has 'poll_state=idle'
MW_ADAPTIVE_AGENT_SESSION_ID=cccccccccccccccccccccccccccccccc
: >"$TEST_ROOT/reads"
sample 115000 12500 0
grep -q '^stats' "$TEST_ROOT/reads" || fail 'agent event no longer wakes idle polling'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/slow_rate")" -eq 100 ] || fail 'traffic after full idle retained stale history'
status_has 'idle_poll_interval=5s'
printf 'PASS: agent events preserve active/grace history and still wake five-second idle polling.\n'

for agent_direction in wan lan; do
    fixture "agent-$agent_direction" bfifo 0
    DIRECTION="$agent_direction"
    sample 90000 0 0
    sample 91000 250000 0
    printf '1800\n' >"$STATE_ROOT/$DEVICE-$DIRECTION/slow_rate"
done
MW_ADAPTIVE_AGENT_SESSION_ID=dddddddddddddddddddddddddddddddd
for agent_direction in wan lan; do
    DEVICE="agent-$agent_direction"; DIRECTION="$agent_direction"
    sample 92000 12500 0
    [ "$(cat "$STATE_ROOT/$DEVICE-$DIRECTION/slow_rate")" -gt 1700 ] || fail 'global agent event erased another direction history'
done

fixture saturated bfifo 0
sample 90000 0 0
sample 91000 250000 0
sample 92000 12500 10
expect 2000 2250
status_has 'at_ceiling=1'
status_has 'saturation=pressure'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/last_increase")" -eq 91000 ] || fail 'ceiling pressure changed the increase timer'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/last_change_ms")" -eq 91000 ] || fail 'ceiling pressure changed the last applied update'
grep -q 'state=ceiling-pressure' "$STATE_ROOT/$DEVICE-wan/status" || fail 'ceiling falsely reported a rate increase'
sample 93000 12500 0
status_has 'saturation=reached'
sample 94000 12500 0 2Kb 4
sample 95000 12500 0 2Kb 4
status_has 'saturation=pressure'
fixture failed-timer bfifo 0
sample 90000 0 0
FAIL_CLASS=1
sample 91000 12500 1
expect 1000 2250
status_has 'requested_rate=1150'
status_has 'applied_rate=1000'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/last_increase")" -eq 0 ] || fail 'failed increase changed the timer'
fixture failed-decrease bfifo 0
sample 90000 0 0
sample 91000 250000 0
for timer_file in last_increase last_drop backlog_free_since lower_since; do
    printf '80000\n' >"$STATE_ROOT/$DEVICE-wan/$timer_file"
done
printf '100\n' >"$STATE_ROOT/$DEVICE-wan/slow_rate"
for history_file in peak peak_1 peak_2 peak_3 peak_4 rolling_peak; do
    printf '0\n' >"$STATE_ROOT/$DEVICE-wan/$history_file"
done
FAIL_CLASS=1
sample 92000 12500 0
expect 2000 2250
status_has 'requested_rate=1950'
status_has 'applied_rate=2000'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/last_decrease")" -eq 0 ] || fail 'failed decrease changed the timer'
fixture cap-repair bfifo 0
sample 90000 0 0
sample 91000 250000 0
LINE_RATE=4000; SHAPER_RATE=4000; FAIL_CLASS=1
sample 92000 12500 0
expect 2000 2250
status_has 'requested_rate=1000'
status_has 'applied_rate=2000'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/rate")" -eq 2000 ] || fail 'failed cap repair falsely committed the rate'
sample 93000 12500 0
sample 94000 12500 0
expect 1000 2250
fixture startup-unconfirmed bfifo 0
FAIL_CLASS=1
sample 90000 0 0
status_has 'applied_rate=unknown'
status_has 'saturation=unknown'
fixture stale-stats bfifo 0
sample 90000 0 0
sample 91000 250000 0
FAIL_STATS=1
sample 92000 12500 0
status_has 'stats_age_ms=1000'
status_has 'applied_rate=2000'
sample 93000 12500 0
status_has 'stats_age_ms=2000'
fixture status-atomic bfifo 0
sample 90000 0 0
old_status="$(cat "$STATE_ROOT/$DEVICE-wan/status")"
FAIL_STATUS_MOVE=1
write_status "$STATE_ROOT/$DEVICE-wan" wan "$DEVICE" 1000 100000 test 0 1000 0 0 && fail 'failed status publication reported success'
[ "$(cat "$STATE_ROOT/$DEVICE-wan/status")" = "$old_status" ] || fail 'failed publication damaged the previous status'
[ ! -e "$STATE_ROOT/$DEVICE-wan/status.$$" ] || fail 'failed status publication leaked temporary data'
printf 'PASS: ceiling pressure and failed writes preserve timers; status publication is atomic.\n'

fixture netem-loss netem 1
NETEM_LOSS=1%
sample 90000 0 0
sample 91000 12500 10
expect 1000 12
status_has 'drop_signal=netem-configured-loss'
status_has 'congestion_drop_delta=0'
fixture netem-pressure netem 1
NETEM_DELAY_MS=050; NETEM_JITTER_MS=0005; NETEM_LOSS=1%
sample 90000 0 0
sample 91000 12500 10 6000b 14
expect 1000 12
status_has 'pressure_backlog_bytes=0'
status_has 'netem_delay_allowance_bytes=6875'
sample 92000 12500 10 9000b 20
sample 93000 12500 10 9500b 21
[ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" -gt 1000 ] || fail 'NETEM excess backlog could not increase the rate'
fixture netem-overflow netem 1
NETEM_LOSS=0.00%
sample 90000 0 0
sample 91000 12500 1
expect 1150 12
fixture loss-fallback netem 0
NETEM_LOSS=1%; NETEM_DIRECTION=egress; DIRECTION=lan
sample 90000 0 0
sample 91000 12500 1
expect 1150 12
status_has 'drop_signal=fifo'
for managed_queue in red fq_codel; do
    fixture "managed-$managed_queue" "$managed_queue" 0
    sample 90000 0 0
    sample 91000 12500 1
    expect 1000 2250
    status_has 'drop_signal=managed-unconfirmed'
    sample 92000 125000 1
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" -gt 1000 ] || fail 'managed queue ignored drops under high utilization'
    fixture "managed-backlog-$managed_queue" "$managed_queue" 0
    sample 90000 0 0
    sample 91000 12500 1 2Kb 4
    expect 1000 2250
    sample 92000 12500 1 2Kb 4
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" -gt 1000 ] || fail 'managed queue ignored sustained backlog with drops'
done
printf 'PASS: FIFO overflow stays fast; NETEM emulation and low-demand managed-queue drops do not drive rate increases.\n'

fixture fixed bfifo 0
sample 100000 0 0
sample 101000 12500 1
expect 1150 2250
! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail 'default fixed mode resized the queue'

fixture live bfifo 1
sample 100000 0 0
sample 101000 12500 1 2Kb 3
expect 1150 2588
status_has 'profile_limit=2588'
status_has 'freshness_target_ms=18'
sample 102000 250000 0
expect 2000 4500
sample 103000 0 0
expect 2000 4500
sample 122000 0 0
expect 1000 2250
printf 'PASS: BFIFO tracks increases and the idle baseline; scaled backlog is accepted.\n'

fixture packets pfifo 1
sample 200000 0 0
sample 201000 125000 0
expect 1300 7
sample 202000 250000 0
expect 2000 10
SENT_BYTES=0; DROP_COUNT=0
sample 203000 0 0
expect 1000 5
printf 'PASS: PFIFO tracks rate and resynchronizes after counter reset.\n'

fixture floor bfifo 1
ADAPTIVE_START_RATE=custom; ADAPTIVE_CUSTOM_START_RATE=300
sample 300000 0 0
expect 300 2250
sample 301000 12500 1
expect 450 2250
fixture floor-disabled bfifo 0
ADAPTIVE_START_RATE=custom; ADAPTIVE_CUSTOM_START_RATE=300
sample 300000 0 0
expect 300 2250
fixture plateau pfifo 1
ADAPTIVE_START_RATE=custom; ADAPTIVE_CUSTOM_START_RATE=300
sample 300000 0 0
sample 301000 12500 1
expect 450 5
! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail 'unchanged PFIFO limit was rewritten'
printf 'PASS: low-rate capacity retains the fixed-profile burst reserve before and after overflow; identical limits skip queue writes.\n'

fixture decrease bfifo 1
sample 300000 0 0
sample 301000 250000 0
expect 2000 4500
decrease_time=301000
while [ "$decrease_time" -lt 341000 ]; do
    decrease_time=$((decrease_time + 1000))
    sample "$decrease_time" 12500 0
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" -eq 2000 ] || break
done
expect 1950 4388
status_has 'profile_requested_limit=4388'
sample "$((decrease_time + 1000))" 12500 1
expect 2000 4500
grep -q 'state=decrease-rollback' "$STATE_ROOT/$DEVICE-wan/status" || fail 'rate rollback was not exercised'
printf 'PASS: active decreases shrink FIFO; rate rollback restores its matching limit.\n'

fixture capped bfifo 1
ADAPTIVE_START_RATE=1500; LINE_RATE=4000; SHAPER_RATE=3920
sample 350000 0 0
sample 351000 250000 1
expect 1000 2250

fixture uplink bfifo 1
sample 360000 0 0
sample 361000 250000 0
expect 2000 4500
fixture ifb-uplink bfifo 1
DIRECTION=lan
sample 360000 0 0
expect 1000 2250
[ "$(cat "$STATE_ROOT/uplink-wan/profile_limit")" -eq 4500 ] || fail 'download changed upload profile state'
[ "$(cat "$STATE_ROOT/ifb-uplink-lan/profile_limit")" -eq 2250 ] || fail 'download profile state is missing'
printf 'PASS: link cap and independent upload/download profiles are preserved.\n'

fixture rollback bfifo 1
sample 400000 0 0
: >"$TEST_ROOT/updates"
FAIL_CLASS=1
sample 401000 12500 1
expect 1000 2250
status_has 'profile_limit=2250'
status_has 'profile_state=degraded'
[ "$(grep -c '^qdisc change' "$TEST_ROOT/updates")" -eq 2 ] || fail 'failed class update did not roll back FIFO'

fixture rejected bfifo 1
sample 400000 0 0
: >"$TEST_ROOT/updates"
FAIL_QUEUE=1
sample 401000 12500 1
expect 1000 2250
! grep -q '^class change' "$TEST_ROOT/updates" || fail 'class changed after FIFO failure'
: >"$TEST_ROOT/updates"
sample 402000 12500 1
[ ! -s "$TEST_ROOT/updates" ] || fail 'tc backoff did not suppress writes'

fixture mismatch bfifo 1
sample 400000 0 0
MISMATCH=1
sample 401000 12500 1
expect 1000 2250
status_has 'profile_state=degraded'
printf 'PASS: class failure rolls back FIFO; failed or mismatched FIFO readback blocks class changes and backs off.\n'

fixture busy bfifo 1
sample 500000 0 0
: >"$TEST_ROOT/updates"
LOCK_BUSY=1
sample 501000 12500 1
expect 1000 2250
[ ! -s "$TEST_ROOT/updates" ] || fail 'updates escaped a busy refresh lock'

fixture wrong bfifo 1
printf 'pfifo\n' >"$TEST_ROOT/kernel/$DEVICE.kind"
sample 600000 0 0
[ ! -s "$TEST_ROOT/updates" ] || fail 'mismatched queue type was modified'

fixture other fq_codel 1
sample 700000 0 0
sample 701000 12500 1
expect 1000 2250
! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail 'non-FIFO queue was modified'
printf 'PASS: lock contention, queue ownership, and FQ-CoDel behavior are preserved.\n'

fixture emulated netem 1
sample 800000 0 0
sample 801000 250000 0
expect 2000 12
! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail 'NETEM floor was rewritten'

fixture delayed netem 1
FRESHNESS_MODE=custom; FRESHNESS_TARGET_MS=50
NETEM_DELAY_MS=0; NETEM_JITTER_MS=7; NETEM_LOSS=1%
sample 800000 0 0
expect 1000 14
sample 801000 250000 0
expect 2000 28
[ "$(cat "$TEST_ROOT/kernel/$DEVICE.netem")" = 'limit 28 delay 1ms 7ms distribution normal loss 1%' ] || fail 'NETEM settings were lost'
FAIL_CLASS=1
sample 820000 0 0
expect 2000 28
[ "$(cat "$TEST_ROOT/kernel/$DEVICE.netem")" = 'limit 28 delay 1ms 7ms distribution normal loss 1%' ] || fail 'NETEM rollback lost settings'

fixture fallback netem 1
NETEM_DIRECTION=egress; DIRECTION=lan
printf 'pfifo\n' >"$TEST_ROOT/kernel/$DEVICE.kind"
printf '5\n' >"$TEST_ROOT/kernel/$DEVICE.limit"
sample 800000 0 0
sample 801000 250000 0
expect 2000 10
! grep -q ' netem ' "$TEST_ROOT/updates" || fail 'NETEM escaped its direction'
printf 'PASS: NETEM preserves settings, its packet floor, rollback, and the direction-scoped PFIFO fallback.\n'

expect_children() {
    [ "$(cat "$TEST_ROOT/kernel/$DEVICE.rate")" = "$1" ] || fail 'wrong QFQ parent rate'
    for child in 1 2 3; do
        [ "$(cat "$TEST_ROOT/kernel/$DEVICE-$child.limit")" = "$2" ] || fail "wrong QFQ child $child limit"
    done
    [ "$LOCK_HELD" -eq 0 ] || fail 'QFQ lock leaked'
}
for child_kind in bfifo pfifo; do
    fixture "qfq-$child_kind" qfq 1 "$child_kind"
    sample 900000 0 0
    sample 901000 250000 0
    case "$child_kind" in bfifo) child_limit=4500 ;; pfifo) child_limit=10 ;; esac
    expect_children 2000 "$child_limit"
    status_has "profile_limit=$child_limit"
    FAIL_CLASS=1
    sample 920000 0 0
    expect_children 2000 "$child_limit"
done

fixture partial qfq 1 bfifo
sample 900000 0 0
: >"$TEST_ROOT/updates"
FAIL_QUEUE_PARENT=10:2
sample 901000 250000 0
expect_children 1000 2250
! grep -q '^class change' "$TEST_ROOT/updates" || fail 'class changed after partial QFQ failure'
status_has 'profile_state=degraded'

fixture divergent qfq 1 pfifo
sample 900000 0 0
printf '7\n' >"$TEST_ROOT/kernel/$DEVICE-2.limit"
# Force a fresh read instead of relying on the cached common limit.
printf '0\n' >"$STATE_ROOT/$DEVICE-wan/profile_limit"
sample 901000 0 0
expect_children 1000 5

fixture ownership qfq 1 bfifo
printf 'pfifo\n' >"$TEST_ROOT/kernel/$DEVICE-3.kind"
sample 900000 0 0
[ ! -s "$TEST_ROOT/updates" ] || fail 'QFQ mutated children before verifying all identities'
printf 'PASS: QFQ updates all FIFO children, restores partial failures, repairs mixed limits, and checks ownership first.\n'

for excluded in red fq_codel; do
    fixture "excluded-$excluded" "$excluded" 1
    sample 900000 0 0
    sample 901000 250000 0
    ! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail "$excluded was resized"
    fixture "excluded-qfq-$excluded" qfq 1 "$excluded"
    sample 900000 0 0
    sample 901000 250000 0
    ! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail "QFQ $excluded was resized"
done
printf 'PASS: RED and FQ-CoDel remain excluded, including QFQ children.\n'
for fixed_kind in netem qfq; do
    fixture "fixed-$fixed_kind" "$fixed_kind" 0
    sample 900000 0 0
    sample 901000 250000 0
    ! grep -q '^qdisc change' "$TEST_ROOT/updates" || fail "disabled option changed $fixed_kind"
done
printf 'PASS: NETEM and QFQ keep their original behavior with the option disabled.\n'

# Exercise policy histories without kernel mocks, then verify application below.
freshness_trace() {
    previous_target="${freshness_trace_state%% *}"
    mw_realtime_adaptive_freshness_step "$freshness_trace_state" "$freshness_time" 2000 "$1" "$2" "${3:-1}" "${4:-1}" "${5:-2000}"
    [ "$MW_RT_FRESHNESS_REQUESTED_MS" -ge 12 ] && [ "$MW_RT_FRESHNESS_REQUESTED_MS" -le 24 ] || fail 'freshness escaped bounds'
    if [ "$MW_RT_FRESHNESS_REQUESTED_MS" -ne "$previous_target" ]; then
        [ "$((MW_RT_FRESHNESS_REQUESTED_MS - previous_target))" -le 1 ] &&
            [ "$((previous_target - MW_RT_FRESHNESS_REQUESTED_MS))" -le 1 ] || fail 'freshness step exceeded 1 ms'
        [ "$((freshness_time - freshness_previous_change))" -ge 20000 ] || fail 'freshness cooldown violated'
        freshness_previous_change="$freshness_time"
    fi
    freshness_trace_state="$MW_RT_FRESHNESS_REQUESTED_MS $MW_RT_FRESHNESS_CHANGE_MS $MW_RT_FRESHNESS_HISTORY"
}
freshness_time=100000
freshness_previous_change=100000
freshness_trace_state='20 100000 0 100000 2000 0 0 0 0'
for tick in $(seq 1 180); do
    freshness_time=$((freshness_time + 1000))
    freshness_trace 3000 1
done
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 12 ] || fail 'persistent sampled backlog did not tighten to 12 ms'
freshness_time=100000; freshness_previous_change=100000
freshness_trace_state='20 100000 0 100000 2000 0 0 0 0'
for tick in $(seq 1 100); do
    freshness_time=$((freshness_time + 1000))
    freshness_trace 0 1
done
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 24 ] || fail 'repeated low-backlog drops did not relax to 24 ms'
for tick in $(seq 1 100); do
    freshness_time=$((freshness_time + 1000))
    freshness_trace 0 0
done
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 20 ] || fail 'quiet traffic did not recover the baseline target'

for condition in rate-changing sample-gaps single-drop; do
    freshness_time=100000; freshness_previous_change=100000
    freshness_trace_state='20 100000 0 100000 2000 0 0 0 0'
    for tick in $(seq 1 30); do
        case "$condition" in
            rate-changing) freshness_time=$((freshness_time + 1000)); freshness_trace 3000 1 1 1 1500 ;;
            sample-gaps) freshness_time=$((freshness_time + 3000)); freshness_trace 3000 1 ;;
            single-drop)
                freshness_time=$((freshness_time + 1000))
                if [ "$tick" -eq 1 ]; then freshness_trace 0 1; else freshness_trace 0 0; fi
                ;;
        esac
    done
    [ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 20 ] || fail "$condition changed freshness"
done
mw_realtime_adaptive_freshness_step '24 100000 0 100000 2000 0 0 0 0' 101000 2000 0 0 0 1 2000
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 24 ] || fail 'idle grace discarded freshness'
mw_realtime_adaptive_freshness_step '24 100000 0 100000 2000 0 0 0 0' 121000 2000 0 0 0 0 2000
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 20 ] || fail 'idle baseline did not restore 20 ms'
mw_realtime_adaptive_freshness_step 'invalid state' 121000 2000 0 0 1 1 2000
[ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 20 ] || fail 'invalid freshness history was accepted'
for invalid_target in 11 25; do
    mw_realtime_adaptive_freshness_step "$invalid_target 0 0 0 2000 0 0 0 0" 121000 2000 0 0 1 1 2000
    [ "$MW_RT_FRESHNESS_REQUESTED_MS" -eq 20 ] || fail 'out-of-range stored freshness was accepted'
done
printf 'PASS: freshness policy obeys 12-24 ms bounds, 1 ms steps, cooldown, rate priority, sample gaps, and idle recovery.\n'

fixture observed-target bfifo 1
ADAPTIVE_FRESHNESS=1
sample 1000000 0 0
sample 1001000 250000 0
observed_time=1001000
while [ "$observed_time" -lt 1023000 ]; do
    observed_time=$((observed_time + 1000))
    sample "$observed_time" 250000 0 3000b 7
done
expect 2000 4750
status_has 'freshness_target_ms=19'
[ "$(grep -c '^qdisc' "$TEST_ROOT/reads")" -eq 6 ] || fail 'millisecond observation added queue polling'
printf 'PASS: continuous controller samples persist the window and change the target without extra queue polling.\n'

fixture target bfifo 1
ADAPTIVE_FRESHNESS=1
sample 1000000 0 0
sample 1001000 250000 0
expect 2000 5000
# Seed one completed observation window to isolate the kernel application path.
printf '982000\n' >"$STATE_ROOT/$DEVICE-wan/last_increase"
printf '982000\n' >"$STATE_ROOT/$DEVICE-wan/last_drop"
printf '20 982000 992000 1001000 2000 9 12 12 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
: >"$TEST_ROOT/updates"
sample 1002000 250000 0 3000b 7
expect 2000 4750
status_has 'freshness_target_ms=19'
status_has 'freshness_requested_ms=19'
status_has 'freshness_control=adaptive'
status_has 'freshness_reason=sampled-backlog'
! grep -q '^class change' "$TEST_ROOT/updates" || fail 'target-only update rewrote the HFSC class'
fixture target-download bfifo 1
ADAPTIVE_FRESHNESS=1; DIRECTION=lan
sample 1002000 0 0
expect 1000 2500
IFS=' ' read -r saved_target _ <"$STATE_ROOT/target-wan/freshness_state"
[ "$saved_target" -eq 19 ] || fail 'download changed upload freshness'
status_has 'freshness_target_ms=20'
DEVICE=target; DIRECTION=wan
SENT_BYTES=0; DROP_COUNT=0
sample 1003000 0 0
expect 1000 2500
status_has 'freshness_target_ms=20'

fixture target-failure bfifo 1
ADAPTIVE_FRESHNESS=1
sample 1000000 0 0
sample 1001000 250000 0
printf '982000\n' >"$STATE_ROOT/$DEVICE-wan/last_increase"
printf '982000\n' >"$STATE_ROOT/$DEVICE-wan/last_drop"
printf '20 982000 992000 1001000 2000 9 12 12 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
FAIL_QUEUE=1
sample 1002000 250000 0 3000b 7
expect 2000 5000
status_has 'freshness_target_ms=20'
status_has 'freshness_requested_ms=19'
status_has 'freshness_reason=update-failed'
IFS=' ' read -r saved_target saved_change _ <"$STATE_ROOT/$DEVICE-wan/freshness_state"
[ "$saved_target:$saved_change" = '20:982000' ] || fail 'failed update committed the target or cooldown'
: >"$TEST_ROOT/updates"
sample 1003000 250000 0
[ ! -s "$TEST_ROOT/updates" ] || fail 'freshness failure escaped bounded tc backoff'

fixture target-floor pfifo 1
ADAPTIVE_FRESHNESS=1
LINE_RATE=1200; SHAPER_RATE=1200
sample 1000000 0 0
printf '981000\n' >"$STATE_ROOT/$DEVICE-wan/last_drop"
printf '20 981000 991000 1000000 300 9 24 24 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
: >"$TEST_ROOT/updates"; : >"$TEST_ROOT/reads"
sample 1001000 37500 0 900b 2
expect 300 5
status_has 'freshness_target_ms=19'
[ ! -s "$TEST_ROOT/updates" ] || fail 'floor-limited target change caused kernel writes'
! grep -q '^qdisc' "$TEST_ROOT/reads" || fail 'floor-limited target change caused extra queue reads'
sample 1022000 0 0
expect 300 5
status_has 'freshness_target_ms=20'
printf 'PASS: target-only changes, independent directions, failed-update handling, counter resets, and minimum floors are verified.\n'

fixture burst-floor bfifo 1
ADAPTIVE_FRESHNESS=1
ADAPTIVE_START_RATE=custom; ADAPTIVE_CUSTOM_START_RATE=300
FRESHNESS_MODE=custom; FRESHNESS_TARGET_MS=50
sample 1100000 0 0
expect 300 2500
printf '12 1080000 0 1100000 300 0 0 0 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
sample 1101000 1250 0
expect 300 2500
status_has 'freshness_target_ms=12'
fixture burst-floor-capped bfifo 1
ADAPTIVE_FRESHNESS=1; LINE_RATE=1200; SHAPER_RATE=1200
sample 1100000 0 0
expect 300 1500
for burst_kind in bfifo pfifo; do
    fixture "burst-qfq-$burst_kind" qfq 1 "$burst_kind"
    ADAPTIVE_START_RATE=custom; ADAPTIVE_CUSTOM_START_RATE=300
    sample 1100000 0 0
    case "$burst_kind" in bfifo) burst_limit=2250 ;; pfifo) burst_limit=5 ;; esac
    expect_children 300 "$burst_limit"
done
printf 'PASS: experimental targets retain the 20 ms reserve; link caps and QFQ child reserves are preserved.\n'

for burst_signal in overflow rate-increase; do
    fixture "freshness-burst-$burst_signal" bfifo 1
    ADAPTIVE_FRESHNESS=1
    sample 1200000 0 0
    sample 1201000 250000 0
    printf '20 1180000 1192000 1201000 2000 9 12 12 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
    case "$burst_signal" in
        overflow) printf '1180000\n' >"$STATE_ROOT/$DEVICE-wan/last_increase"; burst_drops=1 ;;
        rate-increase) printf '1180000\n' >"$STATE_ROOT/$DEVICE-wan/last_drop"; burst_drops=0 ;;
    esac
    : >"$TEST_ROOT/updates"
    sample 1202000 250000 "$burst_drops" 3000b 7
    expect 2000 5000
    status_has 'freshness_reason=burst-hold'
    [ ! -s "$TEST_ROOT/updates" ] || fail 'burst hold changed the kernel queue or class'
    printf '20 1180000 1202000 1211000 2000 9 12 12 0\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
    sample 1212000 2500000 0 3000b 7
    expect 2000 4750
    status_has 'freshness_reason=sampled-backlog'
done
fixture burst-relax bfifo 1
ADAPTIVE_FRESHNESS=1
sample 1300000 0 0
sample 1301000 250000 0
printf '20 1280000 1292000 1301000 2000 9 0 0 2\n' >"$STATE_ROOT/$DEVICE-wan/freshness_state"
sample 1302000 250000 1
expect 2000 5250
status_has 'freshness_reason=burst-loss'
printf 'PASS: recent overflow and rate increases block tightening for ten seconds; relaxation remains available.\n'

for boundary_target in 12 13 23 24; do
    fixture "target-boundary-$boundary_target" bfifo 1
    ADAPTIVE_FRESHNESS=1
    sample 1000000 0 0
    sample 1001000 250000 0
    printf '%s 1001000 0 1001000 2000 0 0 0 0\n' "$boundary_target" >"$STATE_ROOT/$DEVICE-wan/freshness_state"
    sample 1002000 250000 0
    expect 2000 "$((boundary_target * 250))"
    status_has "freshness_target_ms=$boundary_target"
    : >"$TEST_ROOT/updates"
    sample 1003000 250000 0
    status_has "freshness_target_ms=$boundary_target"
    [ ! -s "$TEST_ROOT/updates" ] || fail 'stored boundary target caused repeated kernel writes'
done
printf 'PASS: newly allowed targets persist across controller samples.\n'

for unsupported in netem qfq red fq_codel; do
    fixture "target-excluded-$unsupported" "$unsupported" 1
    ADAPTIVE_FRESHNESS=1
    sample 1000000 0 0
    status_has 'freshness_control=unsupported'
done
fixture target-no-budget bfifo 0
ADAPTIVE_FRESHNESS=1; FRESHNESS_MODE=custom; FRESHNESS_TARGET_MS=50
sample 1000000 0 0
status_has 'freshness_target_ms=50'
status_has 'freshness_control=unsupported'
printf 'PASS: unsupported queues and disabled capacity adaptation retain configured freshness targets.\n'

# Exercise service setup too: the opt-in starts at 20 ms regardless of the saved preset.
eval "$(sed -n '/^setup_game_qdisc()/,/^}/p' "$REPO_ROOT/multiwan-qos/etc/multiwan-qos.sh")"
print_msg() { :; }
qdisc_setup_failed() { fail "$*"; }
tc() {
    case "$1:$2" in
        qdisc:del) return 0 ;;
        qdisc:add) setup_kind="$9"; setup_limit="${11}" ;;
        *) fail "unexpected setup command: tc $*" ;;
    esac
}
realtime_rate_mode=adaptive; adaptive_queue_budget=1; adaptive_freshness=1
setup_game_qdisc test-setup 100000 1000 bfifo wan 1500 24 5 450 custom 50 0 0 normal both none 1000
[ "$setup_kind:$setup_limit" = bfifo:2500 ] || fail 'adaptive freshness did not start setup at 20 ms'
adaptive_freshness=0
setup_game_qdisc test-setup 100000 1000 bfifo wan 1500 24 5 450 custom 50 0 0 normal both none 1000
[ "$setup_kind:$setup_limit" = bfifo:6250 ] || fail 'disabled freshness changed the configured setup target'
adaptive_freshness=1; realtime_rate_mode=manual
setup_game_qdisc test-setup 100000 1000 bfifo wan 1500 24 5 450 custom 50 0 0 normal both none 1000
[ "$setup_kind:$setup_limit" = bfifo:6250 ] || fail 'adaptive freshness changed manual mode'
realtime_rate_mode=adaptive
setup_game_qdisc test-setup 100000 1000 netem wan 1500 24 5 450 custom 50 0 0 normal both none 1000
[ "$setup_kind:$setup_limit" = netem:14 ] || fail 'adaptive freshness changed NETEM setup'
adaptive_freshness=1
setup_game_qdisc test-setup 100000 300 bfifo wan 1500 24 5 450 custom 50 0 0 normal both none 300
[ "$setup_kind:$setup_limit" = bfifo:2500 ] || fail 'startup omitted the experimental burst reserve'
adaptive_freshness=0
setup_game_qdisc test-setup 100000 300 bfifo wan 1500 24 5 450 balanced 18 0 0 normal both none 300
[ "$setup_kind:$setup_limit" = bfifo:2250 ] || fail 'startup omitted the fixed-target burst reserve'
adaptive_queue_budget=0
setup_game_qdisc test-setup 100000 300 bfifo wan 1500 24 5 450 balanced 18 0 0 normal both none 300
[ "$setup_kind:$setup_limit" = bfifo:1500 ] || fail 'disabled adaptation changed the startup queue'
adaptive_queue_budget=1; realtime_rate_mode=manual
setup_game_qdisc test-setup 100000 300 bfifo wan 1500 24 5 450 balanced 18 0 0 normal both none 300
[ "$setup_kind:$setup_limit" = bfifo:1500 ] || fail 'manual mode gained an adaptive reserve'
printf 'PASS: setup starts supported opt-in FIFOs at 20 ms and preserves manual, disabled, and NETEM targets.\n'
printf 'Adaptive queue freshness regression tests passed. No real networking commands ran.\n'
