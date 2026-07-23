#!/bin/sh

# Shared realtime rate and finite-queue calculations.

mw_realtime_resolve_freshness() {
    local mode="${1:-auto}" custom="$2" legacy="$3" target

    case "$legacy" in
        ''|*[!0-9]*) legacy=24 ;;
    esac
    [ "$legacy" -gt 0 ] 2>/dev/null || legacy=24

    case "$mode" in
        tight)
            target=14
            ;;
        balanced|auto|'')
            target=18
            ;;
        relaxed)
            target=22
            ;;
        custom)
            case "$custom" in
                ''|*[!0-9]*) target="$legacy" ;;
                *) target="$custom" ;;
            esac
            ;;
        *)
            target="$legacy"
            ;;
    esac

    [ "$target" -gt 0 ] 2>/dev/null || target="$legacy"
    [ "$target" -gt 0 ] 2>/dev/null || target=18
    MW_RT_FRESHNESS_MS="$target"
}

mw_realtime_resolve_packet_size() {
    local packet_size="$1" mtu="$2"

    case "$packet_size" in
        ''|*[!0-9]*) packet_size=450 ;;
    esac
    case "$mtu" in
        ''|*[!0-9]*) mtu=1500 ;;
    esac
    [ "$mtu" -gt 0 ] 2>/dev/null || mtu=1500

    [ "$packet_size" -gt "$mtu" ] 2>/dev/null && packet_size="$mtu"
    [ "$packet_size" -lt 64 ] 2>/dev/null && packet_size=64
    MW_RT_RESOLVED_PACKET_SIZE="$packet_size"
}

mw_realtime_auto_rate() {
    local line_rate="$1" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1
    MW_RT_RATE=1500
    [ "$MW_RT_RATE" -gt "$cap" ] && MW_RT_RATE="$cap"
}

mw_realtime_parse_tc_class_stats() {
    local output="$1" line tail bytes="" drops="" backlog_bytes="" backlog_packets=""

    while IFS= read -r line; do
        set -- $line
        [ "$#" -gt 0 ] || continue
        case "$1" in
            Sent)
                [ "$#" -ge 2 ] || continue
                bytes="$2"
                tail="${line#*dropped }"
                [ "$tail" != "$line" ] && drops="${tail%%,*}"
                ;;
            backlog)
                [ "$#" -ge 3 ] || continue
                backlog_bytes="${2%b}"
                backlog_packets="${3%p}"
                ;;
        esac
    done <<EOF
$output
EOF

    [ -n "$bytes" ] && [ -n "$drops" ] &&
        [ -n "$backlog_bytes" ] && [ -n "$backlog_packets" ] || return 1
    case "$bytes:$drops:$backlog_bytes:$backlog_packets" in
        *[!0-9:]*) return 1 ;;
    esac

    MW_RT_STATS_BYTES="$bytes"
    MW_RT_STATS_DROPS="$drops"
    MW_RT_STATS_BACKLOG_BYTES="$backlog_bytes"
    MW_RT_STATS_BACKLOG_PACKETS="$backlog_packets"
}

mw_realtime_adaptive_demand() {
    local sent_delta="$1" elapsed_ms="$2" backlog_bytes="$3"
    local previous_backlog_bytes="$4" drain_ms="${5:-200}" backlog_growth_bytes=0

    case "$sent_delta" in ''|*[!0-9]*) sent_delta=0 ;; esac
    case "$elapsed_ms" in ''|*[!0-9]*) elapsed_ms=1000 ;; esac
    case "$backlog_bytes" in ''|*[!0-9]*) backlog_bytes=0 ;; esac
    case "$previous_backlog_bytes" in ''|*[!0-9]*) previous_backlog_bytes="$backlog_bytes" ;; esac
    case "$drain_ms" in ''|*[!0-9]*) drain_ms=200 ;; esac
    [ "$elapsed_ms" -gt 0 ] 2>/dev/null || elapsed_ms=1000
    [ "$drain_ms" -gt 0 ] 2>/dev/null || drain_ms=200

    [ "$backlog_bytes" -le "$previous_backlog_bytes" ] ||
        backlog_growth_bytes=$((backlog_bytes - previous_backlog_bytes))
    MW_RT_SERVED_RATE=$((sent_delta * 8 / elapsed_ms))
    MW_RT_BACKLOG_GROWTH_RATE=$((backlog_growth_bytes * 8 / elapsed_ms))
    MW_RT_BACKLOG_DRAIN_RATE=$((backlog_bytes * 8 / drain_ms))
    MW_RT_INSTANT_DEMAND=$((MW_RT_SERVED_RATE + MW_RT_BACKLOG_GROWTH_RATE + MW_RT_BACKLOG_DRAIN_RATE))
}

mw_realtime_adaptive_target() {
    local demand="$1" reserve="$2" floor="$3" ceiling="$4" target

    case "$demand" in ''|*[!0-9]*) demand=0 ;; esac
    case "$reserve" in ''|*[!0-9]*) reserve=300 ;; esac
    case "$floor" in ''|*[!0-9]*) floor=300 ;; esac
    case "$ceiling" in ''|*[!0-9]*) ceiling=2000 ;; esac
    [ "$ceiling" -ge "$floor" ] 2>/dev/null || ceiling="$floor"

    target=$((demand + reserve))
    target=$(((target + 49) / 50 * 50))
    [ "$target" -lt "$floor" ] && target="$floor"
    [ "$target" -gt "$ceiling" ] && target="$ceiling"
    MW_RT_ADAPTIVE_TARGET="$target"
}

mw_realtime_adaptive_backlog_step() {
    local drain_rate="$1" step

    case "$drain_rate" in ''|*[!0-9]*) drain_rate=0 ;; esac
    step=$(((drain_rate + 49) / 50 * 50))
    [ "$step" -ge 50 ] || step=50
    MW_RT_BACKLOG_STEP="$step"
}

mw_realtime_adaptive_idle_state() {
    local idle_elapsed_ms="$1" grace_ms="${2:-20000}" current_rate="${3:-0}" baseline_rate="${4:-$current_rate}"

    case "$idle_elapsed_ms" in ''|*[!0-9]*) idle_elapsed_ms=0 ;; esac
    case "$grace_ms" in ''|*[!0-9]*) grace_ms=20000 ;; esac
    case "$current_rate" in ''|*[!0-9]*) current_rate=0 ;; esac
    case "$baseline_rate" in ''|*[!0-9]*) baseline_rate="$current_rate" ;; esac
    [ "$grace_ms" -gt 0 ] 2>/dev/null || grace_ms=20000

    if [ "$idle_elapsed_ms" -lt "$grace_ms" ]; then
        MW_RT_IDLE_HOLD=1
        MW_RT_IDLE_REMAINING_MS=$((grace_ms - idle_elapsed_ms))
        MW_RT_IDLE_TARGET="$current_rate"
    else
        MW_RT_IDLE_HOLD=0
        MW_RT_IDLE_REMAINING_MS=0
        MW_RT_IDLE_TARGET="$baseline_rate"
    fi
}

mw_realtime_adaptive_decrease_ready() {
    local now="$1" backlog_free_since="$2" last_drop="$3" last_increase="$4"
    local lower_since="$5" last_decrease="$6" backlog_free_ms="${7:-5000}"
    local drop_free_ms="${8:-10000}" rearm_ms="${9:-10000}"
    local confirm_ms="${10:-5000}" interval_ms="${11:-5000}"

    MW_RT_DECREASE_READY=0
    case "$now:$backlog_free_since:$last_drop:$last_increase:$lower_since:$last_decrease" in
        *[!0-9:]*) return 0 ;;
    esac
    [ "$backlog_free_since" -gt 0 ] || return 0
    [ "$last_drop" -gt 0 ] || return 0
    [ "$lower_since" -gt 0 ] || return 0
    [ $((now - backlog_free_since)) -ge "$backlog_free_ms" ] || return 0
    [ $((now - last_drop)) -ge "$drop_free_ms" ] || return 0
    [ $((now - last_increase)) -ge "$rearm_ms" ] || return 0
    [ $((now - lower_since)) -ge "$confirm_ms" ] || return 0
    [ $((now - last_decrease)) -ge "$interval_ms" ] || return 0
    MW_RT_DECREASE_READY=1
}

mw_realtime_adaptive_range() {
    local line_rate="$1" start_rate="${2:-1000}" custom_start_rate="${3:-1000}" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    case "$start_rate" in
        1000|1500) ;;
        custom)
            case "$custom_start_rate" in
                ''|*[!0-9]*) custom_start_rate=1000 ;;
            esac
            if [ "$custom_start_rate" -lt 300 ] 2>/dev/null || [ "$custom_start_rate" -gt 2000 ] 2>/dev/null; then
                custom_start_rate=1000
            fi
            start_rate="$custom_start_rate"
            ;;
        *) start_rate=1000 ;;
    esac
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1

    MW_RT_FLOOR=300
    [ "$MW_RT_FLOOR" -gt "$cap" ] && MW_RT_FLOOR="$cap"
    MW_RT_START="$start_rate"
    [ "$MW_RT_START" -gt "$cap" ] && MW_RT_START="$cap"
    [ "$MW_RT_START" -lt "$MW_RT_FLOOR" ] && MW_RT_START="$MW_RT_FLOOR"
    MW_RT_CEILING=2000
    [ "$MW_RT_CEILING" -gt "$cap" ] && MW_RT_CEILING="$cap"
    [ "$MW_RT_CEILING" -lt "$MW_RT_START" ] && MW_RT_CEILING="$MW_RT_START"
}

mw_realtime_adaptive_profile_range() {
    local line_rate="$1" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1

    # Adaptive changes only the HFSC service rate. Keep finite game leaves at
    # the known-good 1000 kbit profile so their freshness budget is stable.
    MW_RT_PROFILE_START=1000
    [ "$MW_RT_PROFILE_START" -gt "$cap" ] && MW_RT_PROFILE_START="$cap"
    MW_RT_PROFILE_FLOOR="$MW_RT_PROFILE_START"
    MW_RT_PROFILE_CEILING="$MW_RT_PROFILE_START"
}

mw_realtime_queue_budget() {
    local rate="$1" freshness="$2" mtu="$3" packet_size="$4" pfifo_min="$5"
    case "$rate" in ''|*[!0-9]*) rate=1 ;; esac
    case "$freshness" in ''|*[!0-9]*) freshness=18 ;; esac
    case "$mtu" in ''|*[!0-9]*) mtu=1500 ;; esac
    case "$packet_size" in ''|*[!0-9]*) packet_size=450 ;; esac
    case "$pfifo_min" in ''|*[!0-9]*) pfifo_min=5 ;; esac
    [ "$rate" -gt 0 ] 2>/dev/null || rate=1
    [ "$freshness" -gt 0 ] 2>/dev/null || freshness=18
    [ "$mtu" -gt 0 ] 2>/dev/null || mtu=1500
    [ "$packet_size" -lt 64 ] 2>/dev/null && packet_size=64
    [ "$packet_size" -gt "$mtu" ] 2>/dev/null && packet_size="$mtu"
    [ "$pfifo_min" -ge 0 ] 2>/dev/null || pfifo_min=5

    MW_RT_DELAY_BYTES=$(((freshness * rate + 7) / 8))
    [ "$MW_RT_DELAY_BYTES" -lt 1 ] && MW_RT_DELAY_BYTES=1

    MW_RT_BURST_FLOOR="$mtu"

    MW_RT_QUEUE_BYTES="$MW_RT_DELAY_BYTES"
    [ "$MW_RT_QUEUE_BYTES" -lt "$MW_RT_BURST_FLOOR" ] && MW_RT_QUEUE_BYTES="$MW_RT_BURST_FLOOR"

    MW_RT_PFIFO_LIMIT=$(((MW_RT_QUEUE_BYTES + packet_size - 1) / packet_size))
    [ "$MW_RT_PFIFO_LIMIT" -lt "$pfifo_min" ] && MW_RT_PFIFO_LIMIT="$pfifo_min"

    MW_RT_NETEM_LIMIT=$(((MW_RT_QUEUE_BYTES + packet_size - 1) / packet_size))
    [ "$MW_RT_NETEM_LIMIT" -lt 12 ] && MW_RT_NETEM_LIMIT=12

    MW_RT_RED_MAX="$MW_RT_QUEUE_BYTES"
    MW_RT_RED_MIN=$((MW_RT_RED_MAX / 3))
    [ "$MW_RT_RED_MIN" -lt 1 ] && MW_RT_RED_MIN=1
    MW_RT_RED_LIMIT=$((MW_RT_QUEUE_BYTES * 3))
    MW_RT_RED_BURST=$(((MW_RT_RED_MIN + MW_RT_RED_MIN + MW_RT_RED_MAX) / (3 * packet_size)))
    [ "$MW_RT_RED_BURST" -lt 2 ] && MW_RT_RED_BURST=2
    MW_RT_PACKET_SIZE="$packet_size"
}

mw_realtime_curve() {
    local rate="$1" shaper_rate="$2" burst_base_rate="${3:-$1}" burst_cap

    case "$rate" in ''|*[!0-9]*) rate=1 ;; esac
    case "$shaper_rate" in ''|*[!0-9]*) shaper_rate=1 ;; esac
    case "$burst_base_rate" in ''|*[!0-9]*) burst_base_rate="$rate" ;; esac
    [ "$rate" -gt 0 ] 2>/dev/null || rate=1
    [ "$shaper_rate" -gt 0 ] 2>/dev/null || shaper_rate=1
    [ "$burst_base_rate" -gt 0 ] 2>/dev/null || burst_base_rate="$rate"

    MW_RT_SCHEDULER_RATE="$rate"
    [ "$MW_RT_SCHEDULER_RATE" -gt "$shaper_rate" ] && MW_RT_SCHEDULER_RATE="$shaper_rate"
    MW_RT_BURST_DURATION=25
    MW_RT_BURST_RATE=$((burst_base_rate * 10))
    burst_cap=$((shaper_rate * 97 / 100))
    [ "$burst_cap" -gt 0 ] || burst_cap=1
    [ "$MW_RT_BURST_RATE" -gt "$burst_cap" ] && MW_RT_BURST_RATE="$burst_cap"

    # Keep the realtime curve concave or linear; a lower m1 changes HFSC eligibility semantics.
    [ "$MW_RT_BURST_RATE" -lt "$MW_RT_SCHEDULER_RATE" ] &&
        MW_RT_BURST_RATE="$MW_RT_SCHEDULER_RATE"
}
