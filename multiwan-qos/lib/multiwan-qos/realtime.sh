#!/bin/sh

# Shared realtime rate and finite-queue calculations.

mw_realtime_auto_rate() {
    local line_rate="$1" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1
    MW_RT_RATE=1500
    [ "$MW_RT_RATE" -gt "$cap" ] && MW_RT_RATE="$cap"
}

mw_realtime_adaptive_range() {
    local line_rate="$1" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1

    MW_RT_FLOOR=300
    [ "$MW_RT_FLOOR" -gt "$cap" ] && MW_RT_FLOOR="$cap"
    MW_RT_START=1000
    [ "$MW_RT_START" -gt "$cap" ] && MW_RT_START="$cap"
    [ "$MW_RT_START" -lt "$MW_RT_FLOOR" ] && MW_RT_START="$MW_RT_FLOOR"
    MW_RT_CEILING=1800
    [ "$MW_RT_CEILING" -gt "$cap" ] && MW_RT_CEILING="$cap"
    [ "$MW_RT_CEILING" -lt "$MW_RT_START" ] && MW_RT_CEILING="$MW_RT_START"
}

mw_realtime_adaptive_profile_range() {
    local line_rate="$1" cap

    case "$line_rate" in ''|*[!0-9]*) line_rate=1 ;; esac
    [ "$line_rate" -gt 0 ] 2>/dev/null || line_rate=1
    cap=$((line_rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1

    MW_RT_PROFILE_FLOOR=1500
    [ "$MW_RT_PROFILE_FLOOR" -gt "$cap" ] && MW_RT_PROFILE_FLOOR="$cap"
    MW_RT_PROFILE_START=1500
    [ "$MW_RT_PROFILE_START" -gt "$cap" ] && MW_RT_PROFILE_START="$cap"
    [ "$MW_RT_PROFILE_START" -lt "$MW_RT_PROFILE_FLOOR" ] &&
        MW_RT_PROFILE_START="$MW_RT_PROFILE_FLOOR"
    MW_RT_PROFILE_CEILING=2000
    [ "$MW_RT_PROFILE_CEILING" -gt "$cap" ] && MW_RT_PROFILE_CEILING="$cap"
    [ "$MW_RT_PROFILE_CEILING" -lt "$MW_RT_PROFILE_START" ] &&
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
