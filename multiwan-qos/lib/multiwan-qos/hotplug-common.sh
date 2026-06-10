#!/bin/sh
# MultiWAN QoS hotplug common logic — sourced by 13-multiwan-qos-hotplug.
# Single source of truth: the packaged hotplug script and the
# generated one (init.d/multiwan_qos create_hotplug_script) both
# source this file instead of embedding the logic inline.

[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0

. /lib/functions.sh
. /lib/multiwan-qos/process-lock.sh

is_managed=0

check_interface() {
    local config="$1"
    local device enabled
    config_get device "$config" device
    config_get_bool enabled "$config" enabled 1

    # Check if the event device matches AND interface is enabled
    if [ "$device" = "$DEVICE" ] && [ "$enabled" -eq 1 ]; then
        is_managed=1
        return 1 # Break loop
    fi
}

config_load 'multiwan-qos'
config_foreach check_interface interface

if [ "$is_managed" -eq 1 ]; then
    lockdir="/tmp/multiwan_qos-hotplug.lock"
    pending_file="/tmp/multiwan_qos-hotplug.pending"
    max_restarts=4

    if ! mw_lock_acquire "$lockdir"; then
        if mw_lock_owner_alive "$lockdir"; then
            echo "$ACTION $INTERFACE $DEVICE" > "$pending_file"
            logger -t multiwan_qos "Queued hotplug restart for $INTERFACE ($DEVICE); restart already running as pid $MW_LOCK_OWNER_PID"
            exit 0
        fi
        echo "$ACTION $INTERFACE $DEVICE" > "$pending_file"
        logger -t multiwan_qos "Queued hotplug restart for $INTERFACE ($DEVICE); restart lock is busy"
        exit 0
    fi
    lock_token="$MW_LOCK_TOKEN"
    release_hotplug_lock() {
        mw_lock_release_for "$lockdir" "$lock_token"
    }
    trap release_hotplug_lock EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    restart_count=0
    while :; do
        restart_count=$((restart_count + 1))

        # Debounce paired ifdown/ifup events; this restart covers events queued
        # before it starts. Events queued while it runs trigger one more pass.
        sleep 2
        rm -f "$pending_file" 2>/dev/null
        logger -t multiwan_qos "Restarting multiwan_qos due to $ACTION of $INTERFACE ($DEVICE)"
        /etc/init.d/multiwan-qos restart || exit $?

        [ -f "$pending_file" ] || break
        if [ "$restart_count" -ge "$max_restarts" ]; then
            rm -f "$pending_file" 2>/dev/null
            logger -t multiwan_qos "Reached hotplug restart coalescing limit; future events will trigger a new restart"
            break
        fi
        logger -t multiwan_qos "Processing coalesced hotplug restart request"
    done
fi
