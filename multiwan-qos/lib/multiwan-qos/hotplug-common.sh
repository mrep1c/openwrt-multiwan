#!/bin/sh
# MultiWAN QoS hotplug common logic — sourced by 13-multiwan-qos-hotplug.
# Single source of truth: the packaged hotplug script and the
# generated one (init.d/multiwan_qos create_hotplug_script) both
# source this file instead of embedding the logic inline.

[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0

. /lib/functions.sh

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

    if ! mkdir "$lockdir" 2>/dev/null; then
        oldpid="$(cat "$lockdir/pid" 2>/dev/null)"
        if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
            echo "$ACTION $INTERFACE $DEVICE" > "$pending_file"
            logger -t multiwan_qos "Queued hotplug restart for $INTERFACE ($DEVICE); restart already running as pid $oldpid"
            exit 0
        fi
        rm -f "$lockdir/pid" 2>/dev/null
        rmdir "$lockdir" 2>/dev/null
        mkdir "$lockdir" 2>/dev/null || {
            echo "$ACTION $INTERFACE $DEVICE" > "$pending_file"
            logger -t multiwan_qos "Queued hotplug restart for $INTERFACE ($DEVICE); restart lock is busy"
            exit 0
        }
    fi
    echo "$$" > "$lockdir/pid"
    lock_acquired=1
    hotplug_unlock() {
        [ "$lock_acquired" -eq 1 ] || return 0
        rm -f "$lockdir/pid" 2>/dev/null
        rmdir "$lockdir" 2>/dev/null
        lock_acquired=0
    }
    trap hotplug_unlock EXIT INT TERM

    restart_count=0
    while :; do
        restart_count=$((restart_count + 1))

        # Debounce paired ifdown/ifup events; this restart covers events queued
        # before it starts. Events queued while it runs trigger one more pass.
        sleep 2
        rm -f "$pending_file" 2>/dev/null
        logger -t multiwan_qos "Restarting multiwan_qos due to $ACTION of $INTERFACE ($DEVICE)"
        /etc/init.d/multiwan-qos restart || exit $?

        if [ -f "$pending_file" ]; then
            if [ "$restart_count" -ge "$max_restarts" ]; then
                rm -f "$pending_file" 2>/dev/null
                logger -t multiwan_qos "Reached hotplug restart coalescing limit; future events will trigger a new restart"
                break
            fi
            logger -t multiwan_qos "Processing coalesced hotplug restart request"
            continue
        fi

        hotplug_unlock
        if [ -f "$pending_file" ]; then
            if mkdir "$lockdir" 2>/dev/null; then
                lock_acquired=1
                echo "$$" > "$lockdir/pid"
                logger -t multiwan_qos "Processing hotplug restart queued during lock release"
                continue
            fi
            logger -t multiwan_qos "Hotplug restart queued for another worker during lock release"
        fi
        exit 0
    done
fi
