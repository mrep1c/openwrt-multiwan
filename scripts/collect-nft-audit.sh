#!/bin/sh
# Read-only router diagnostics. No probes, service actions, or configuration writes.
exec 2>&1
[ "$(id -u)" = 0 ] || { echo 'Run this collector as root.'; exit 1; }
export LC_ALL=C
section() { printf '\n===== %s =====\n' "$1"; }
limited() { "$@" 2>&1 | head -n 160 | cut -c 1-1024; }

section 'System and package versions'
date -u
uname -r
ubus call system board | jsonfilter -e '@.model' -e '@.release.description'
apk --print-arch
apk info -v 2>/dev/null | grep -E '^(multiwan|luci-app-multiwan|nftables|ip-full|conntrack|busybox|nping|httping|dnsmasq|firewall4|mwan3)-'
section 'Installed file fingerprints'
for file in /lib/multiwan-nft/common.sh /lib/multiwan-nft/multiwan_nft.sh \
    /lib/multiwan-nft/process-lock.sh /etc/init.d/multiwan-nft \
    /usr/sbin/multiwan-nft /usr/sbin/multiwan-nft-track /usr/sbin/multiwan-nft-rtmon \
    /usr/libexec/rpcd/multiwan_nft /lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0; do
    [ ! -f "$file" ] || sha256sum "$file"
done

. /lib/functions.sh
table_ids=
interface_count=0
show_section() {
    local name="$1" kind option value
    config_get kind "$name" TYPE
    printf '\n[%s %s]\n' "$kind" "$name"
    # Deliberately exclude network/wireless configuration and arbitrary options.
    for option in mmx_mask source_routing rt_table_lookup logging loglevel enabled family \
        track_method track_ip reliability count size max_ttl timeout interval failure_interval \
        recovery_interval down up initial_state check_quality failure_latency recovery_latency \
        failure_loss recovery_loss interface metric weight use_member last_resort proto \
        src_ip dest_ip src_port dest_port sticky ipset use_policy; do
        config_get value "$name" "$option"
        [ -z "$value" ] || printf '%s=%s\n' "$option" "$value"
    done
    if [ "$kind" = interface ]; then
        interface_count=$((interface_count+1))
        table_ids="$table_ids $interface_count"
    fi
}
section 'MultiWAN configuration (selected fields)'
if config_load multiwan-nft; then config_foreach show_section; fi
section 'Applied map and runtime state'
for file in /var/run/multiwan-nft-conntrack-map /var/run/multiwan_nft/mmx_mask \
    /var/run/multiwan_nft/iface_state/* /var/run/multiwan-nft-track/*/STATUS; do
    [ ! -f "$file" ] || { printf '\n%s\n' "$file"; head -n 100 "$file"; }
done
if [ -f /var/run/multiwan-nft-conntrack-map ]; then
    applied_ids=$(awk '$1 ~ /^ipv[46]$/ && $3 ~ /^[1-9][0-9]*$/ { print $3 }' /var/run/multiwan-nft-conntrack-map)
    table_ids="$table_ids $applied_ids"
fi
. /usr/share/libubox/jshn.sh
section 'Supervised workers'
service_state=$(ubus -S call service list '{"name":"multiwan-nft"}')
if json_load "$service_state" && json_select multiwan-nft && json_select instances; then
    json_get_keys workers
    for worker in $workers; do
        json_select "$worker" || continue
        json_get_var running running
        json_get_var pid pid
        printf '%s running=%s pid=%s\n' "$worker" "$running" "$pid"
        json_select ..
    done
fi

section 'Network interface state (addresses and routes only)'
for object in $(ubus list 'network.interface.*'); do
    printf '\n%s\n' "$object"
    ubus call "$object" status | jsonfilter \
        -e '@.up' -e '@.pending' -e '@.proto' -e '@.device' -e '@.l3_device' \
        -e '@["ipv4-address"]' -e '@["ipv6-address"]' \
        -e '@["ipv6-prefix"]' -e '@["ipv6-prefix-assignment"]' -e '@.route' | head -n 100
done
section 'Flow offload and routing (first 160 lines per command)'
for option in flow_offloading flow_offloading_hw; do
    printf '%s=' "$option"
    uci -q get "firewall.@defaults[0].$option" || echo unset
done
sysctl net.ipv4.nexthop_compat_mode net.ipv6.nexthop_compat_mode
for family in 4 6; do
    printf '\nIPv%s rules\n' "$family"; limited ip -"$family" rule list
    printf '\nIPv%s main routes\n' "$family"; limited ip -"$family" route list table main
    printf '\nIPv%s nexthops\n' "$family"; limited ip -"$family" nexthop list
    for table in $(printf '%s\n' $table_ids | sort -nu); do
        printf '\nIPv%s policy table %s\n' "$family" "$table"
        limited ip -"$family" route list table "$table"
    done
done
section 'Conntrack statistics (no session addresses)'
conntrack -S
section 'System load and memory'
uptime
free
head -n 8 /proc/stat
section 'Listening TCP/UDP sockets (includes DNS listeners)'
if command -v ss >/dev/null 2>&1; then
    limited ss -lnutp
else
    limited netstat -lnutp
fi
section 'QoS qdisc counters'
if command -v tc >/dev/null 2>&1; then
    limited tc -s qdisc show
else
    echo 'tc is unavailable; no queue counters collected.'
fi
section 'QoS DSCP/conntrack rules'
if nft list table inet dscptag >/dev/null 2>&1; then
    limited nft -a list table inet dscptag
else
    echo 'QoS dscptag table unavailable; QoS may be stopped or absent.'
fi
section 'NFT tables and mark/offload rules in fw4'
nft list tables
nft -a list table inet fw4 | grep -E 'flowtable|flow add|meta mark|ct mark' | head -n 100 | cut -c 1-1024

for sample in 1 2; do
    section "MultiWAN NFT sample $sample (long element lists abbreviated)"
    date -u
    nft -a list table inet multiwan_nft | head -n 900 | cut -c 1-1024
    if nft list table inet multiwan_nft_reconcile >/dev/null 2>&1; then
        nft -a list table inet multiwan_nft_reconcile | head -n 100 | cut -c 1-1024
    else
        echo 'Routing protection table absent (normal outside a failed rebuild).'
    fi
    [ "$sample" != 1 ] || sleep 10
done
section 'Recent MultiWAN logs'
logread | grep -E 'multiwan|mwan3' | tail -n 100 | cut -c 1-1024
section 'End of read-only audit'
echo 'Addresses and recent logs are included; review them before sharing.'
