#!/bin/sh
# Legacy compatibility shim for stale QoSmate hotplug scripts.

[ -r /lib/multiwan-qos/hotplug-common.sh ] || exit 0
. /lib/multiwan-qos/hotplug-common.sh
