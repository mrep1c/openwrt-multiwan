#!/bin/sh
# Per-device MultiWAN QoS hotplug handling. This file is sourced by both the
# packaged and generated hotplug entry points.

[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0

. /lib/functions.sh
. /lib/functions/network.sh
. /lib/multiwan-qos/process-lock.sh

qos_is_enabled() {
    local enabled
    config_load multiwan-qos
    config_get_bool enabled global enabled 0
    [ "$enabled" -eq 1 ]
}

# A Default or Manual configuration may have no long-running procd process,
# so service "running" is not a valid enabled-state check.
qos_is_enabled || exit 0

[ -n "$DEVICE" ] || {
    network_flush_cache
    network_get_device DEVICE "$INTERFACE" 2>/dev/null
}
case "$DEVICE" in ''|*[!A-Za-z0-9_.:@-]*) exit 0 ;; esac

is_managed=0
check_interface() {
    local config="$1" device enabled
    config_get device "$config" device
    config_get_bool enabled "$config" enabled 1
    if [ "$device" = "$DEVICE" ] && [ "$enabled" -eq 1 ]; then
        is_managed=1
        return 1
    fi
}

config_load multiwan-qos
config_foreach check_interface interface
[ "$is_managed" -eq 1 ] || exit 0

state_root=/var/run/multiwan-qos/hotplug
lockdir="/tmp/multiwan_qos-hotplug-$DEVICE.lock"
pending_file="$state_root/$DEVICE.pending"
claimed_file="$state_root/$DEVICE.claim"
status_file="$state_root/$DEVICE.status"
mkdir -p "$state_root"

queue_event() {
    local pending_tmp="$pending_file.$$"
    printf '%s %s %s\n' "$ACTION" "$INTERFACE" "$DEVICE" > "$pending_tmp" &&
        mv "$pending_tmp" "$pending_file"
}

write_status() {
    local event_action="$1" result="$2" detail="$3"
    local status_tmp="$status_file.$$" now
    now="$(date +%s 2>/dev/null)" || now=0
    printf 'device=%s interface=%s action=%s result=%s time=%s detail=%s\n' \
        "$event_device" "$event_interface" "$event_action" "$result" "$now" "$detail" > "$status_tmp" &&
        mv "$status_tmp" "$status_file"
}

queue_event || exit 1
lock_acquired=0
attempt=0
while [ "$attempt" -lt 5 ]; do
    if mw_lock_acquire "$lockdir"; then
        lock_acquired=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
[ "$lock_acquired" -eq 1 ] || {
    logger -t multiwan_qos "Queued $ACTION for $INTERFACE ($DEVICE); per-device hotplug worker is active"
    exit 0
}

lock_token="$MW_LOCK_TOKEN"
release_hotplug_lock() {
    if [ -f "$claimed_file" ]; then
        if [ -f "$pending_file" ]; then
            rm -f "$claimed_file"
        else
            mv "$claimed_file" "$pending_file" 2>/dev/null || true
        fi
    fi
    mw_lock_release_for "$lockdir" "$lock_token"
}
trap release_hotplug_lock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Recover a claim left by an abruptly terminated previous worker. A newer
# pending event wins because hotplug intentionally coalesces to latest state.
if [ -f "$claimed_file" ]; then
    if [ -f "$pending_file" ]; then
        rm -f "$claimed_file"
    else
        mv "$claimed_file" "$pending_file" 2>/dev/null || true
    fi
fi

wait_for_l3_device() {
    local waited=0 resolved_device mtu
    while [ "$waited" -lt 120 ]; do
        [ -f "$pending_file" ] && return 2
        network_flush_cache
        resolved_device=
        network_get_device resolved_device "$event_interface" 2>/dev/null
        mtu="$(cat "/sys/class/net/$event_device/mtu" 2>/dev/null)"
        if network_is_up "$event_interface" &&
            [ "$resolved_device" = "$event_device" ] &&
            ip link show "$event_device" >/dev/null 2>&1; then
            case "$mtu" in ''|*[!0-9]*|0) ;; *) return 0 ;; esac
        fi
        waited=$((waited + 1))
        sleep 1
    done
    return 1
}

run_device_event() {
    local operation="$1" device="$2" retry=0 rv
    while [ "$retry" -lt 180 ]; do
        [ -f "$pending_file" ] && return 77
        /bin/sh /etc/multiwan-qos.sh device-event "$operation" "$device"
        rv=$?
        [ "$rv" -eq 75 ] || return "$rv"
        retry=$((retry + 1))
        sleep 1
    done
    return 75
}

while true; do
    if ! mv "$pending_file" "$claimed_file" 2>/dev/null; then
        [ -f "$pending_file" ] && continue
        break
    fi
    read -r event_action event_interface event_device < "$claimed_file"

    if ! qos_is_enabled; then
        write_status "$event_action" ignored "service-disabled"
        rm -f "$claimed_file"
        continue
    fi

    case "$event_action" in
        ifdown)
            run_device_event detach "$event_device"
            event_result=$?
            case "$event_result" in
                0)
                    write_status "$event_action" detached "affected-device-only"
                    logger -t multiwan_qos "Detached QoS for $event_interface ($event_device); healthy WANs were untouched"
                    ;;
                76) write_status "$event_action" ignored "service-disabled" ;;
                77) write_status "$event_action" superseded "newer-event-pending" ;;
                *)
                    write_status "$event_action" failed "detach-error-$event_result"
                    logger -t multiwan_qos "Failed to detach QoS for $event_interface ($event_device); healthy WANs were untouched"
                    ;;
            esac
            ;;
        ifup)
            wait_for_l3_device
            ready_result=$?
            if [ "$ready_result" -eq 2 ]; then
                write_status "$event_action" superseded "newer-event-pending"
                rm -f "$claimed_file"
                continue
            elif [ "$ready_result" -ne 0 ]; then
                write_status "$event_action" failed "l3-device-not-ready"
                logger -t multiwan_qos "QoS attach timed out waiting for $event_interface ($event_device)"
            else
                run_device_event attach "$event_device"
                event_result=$?
                case "$event_result" in
                    0)
                        write_status "$event_action" attached "affected-device-only"
                        logger -t multiwan_qos "Attached QoS for $event_interface ($event_device); healthy WANs were untouched"
                        ;;
                    76) write_status "$event_action" ignored "service-disabled" ;;
                    77) write_status "$event_action" superseded "newer-event-pending" ;;
                    *)
                        write_status "$event_action" failed "attach-error-$event_result"
                        logger -t multiwan_qos "Failed to attach QoS for $event_interface ($event_device); healthy WANs were untouched"
                        ;;
                esac
            fi
            ;;
    esac

    rm -f "$claimed_file"

    # Give a racing event time to publish its replacement request before this
    # worker releases the per-device lock.
    sleep 1
done
