#!/bin/sh
# shellcheck disable=SC3043,SC1091,SC2155,SC3020,SC3010,SC2016,SC2317,SC3060,SC3057,SC3003

VERSION="1.0.11" # will become obsolete in future releases as version string is now in the init script

# uncomment to enable debug messages
# MULTIWAN_QOS_DEBUG=1

_NL_='
'
DEFAULT_IFS=" 	${_NL_}"
IFS="$DEFAULT_IFS"

: "${VERSION}" "${global_enabled:=}" "${nongameqdisc:=}" "${nongameqdiscoptions:=}" "${OVERHEAD:=}"
: "${gameqdisc:=pfifo}" "${nongameqdisc:=fq_codel}" "${ACK_FILTER_EGRESS:=auto}"
: "${DOWNLOAD_IFB_STAB:=0}"
: "${DISABLE_QOS_OFFLOADS:=1}"
: "${OFFLOAD_EXTRA_DEVICES:=}"
: "${MULTIWAN_QOS_REFRESH_LOCK_DIR:=/var/run/multiwan_qos-refresh.lock}"
: "${MULTIWAN_QOS_RESTARTING_FILE:=/tmp/multiwan_qos_restarting}"
QOS_OFFLOAD_EXTRA_APPLIED=0
QOS_OFFLOAD_WARNED_MISSING_ETHTOOL=0

. /lib/functions.sh
. /lib/multiwan-qos/process-lock.sh

# Config is loaded by the caller (multiwan_qos init), this is a fallback just in case
[ -n "$MULTIWAN_QOS_CONFIG_LOADED" ] || {
    . /etc/init.d/multiwan-qos
    load_and_fix_config || exit 1
}

# error_out() is defined in the init script which sources this file
# Only define it here as a fallback if not already defined
type error_out >/dev/null 2>&1 || error_out() { log_msg -err "${@}"; }

# prints each argument to a separate line
# Only define print_msg/log_msg if not already loaded from init script (#11)
if ! type print_msg >/dev/null 2>&1; then
print_msg() {
    local _arg msgs_dest="/dev/stdout" msgs_prefix=''
    for _arg in "$@"
    do
        case "${_arg}" in
            -err) msgs_dest="/dev/stderr" msgs_prefix="Error: " ;;
            -warn) msgs_dest="/dev/stderr" msgs_prefix="Warning: " ;;
            '') printf '\n' ;; # print out empty lines
            *)
                printf '%s\n' "${msgs_prefix}${_arg}" > "$msgs_dest"
                msgs_prefix=''
        esac
    done
    :
}

# logs each argument separately and prints to a separate line
# optional arguments: '-err', '-warn' to set logged error level
log_msg() {
    local msgs_prefix='' _arg err_l=info msgs_dest

    local IFS="$DEFAULT_IFS"
    for _arg in "$@"
    do
        case "${_arg}" in
            "-err") err_l=err msgs_prefix="Error: " ;;
            "-warn") err_l=warn msgs_prefix="Warning: " ;;
            '') printf '\n' ;; # print out empty lines
            *)
                case "$err_l" in
                    err|warn) msgs_dest="/dev/stderr" ;;
                    *) msgs_dest="/dev/stdout"
                esac
                printf '%s\n' "${msgs_prefix}${_arg}" > "$msgs_dest"
                logger -t multiwan_qos -p user."$err_l" "${msgs_prefix}${_arg}"
                msgs_prefix=''
        esac
    done
    :
}
fi # end of print_msg/log_msg guard

config_load 'multiwan-qos' || { error_out "Failed to get UCI config."; exit 1; }

# Check if Software Flow Offloading is enabled
SFO_ENABLED=0
[ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ] && SFO_ENABLED=1

# Calculated values - moved to per-interface setup


# Get tc stab parameters for HFSC/HTB/Hybrid
# $1 = preset, $2 = overhead, $3 = mpu
get_tc_overhead_params() {
    local preset="$1"
    local overhead="$2"
    local mpu="$3"
    
    # Detect ATM-based presets
    case "$preset" in
        pppoe-ethernet)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-84} overhead ${overhead:-46} linklayer ethernet"
            ;;
        pppoe-vlan-ethernet)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-84} overhead ${overhead:-50} linklayer ethernet"
            ;;
        pppoe-gpon)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-69} overhead ${overhead:-31} linklayer ethernet"
            ;;
        pppoe-vlan-gpon)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-69} overhead ${overhead:-35} linklayer ethernet"
            ;;
        pppoe-vlan-gpon-conservative)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-73} overhead ${overhead:-39} linklayer ethernet"
            ;;
        *atm*|*adsl*|*pppoa*|*pppoe*|*bridged*|*ipoa*|conservative)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-68} overhead ${overhead:-44} linklayer atm"
            ;;
        docsis)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-64} overhead ${overhead:-25} linklayer ethernet"
            ;;
        cake-ethernet)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-64} overhead ${overhead:-38} linklayer ethernet"
            ;;
        raw)
            if [ -n "$mpu" ]; then
                printf '%s' "stab mpu $mpu overhead ${overhead:-0} linklayer ethernet"
            else
                printf '%s' "stab overhead ${overhead:-0} linklayer ethernet"
            fi
            ;;
        *)
            printf '%s' "stab mtu 2047 tsize 512 mpu ${mpu:-64} overhead ${overhead:-40} linklayer ethernet"
            ;;
    esac
}

fq_codel_memory_limit() {
    local rate="$1"
    local mem=$((rate * 1000 / 8))

    [ "$mem" -lt 4000000 ] && mem=4000000
    [ "$mem" -gt 16777216 ] && mem=16777216
    printf '%s' "$mem"
}

# Get CAKE parameters from common link settings
# $1 = preset, $2 = overhead, $3 = mpu, $4 = "hybrid" (optional)
get_cake_link_params() {
    local preset="$1"
    local oh="$2"
    local mpu="$3"
    local mode="$4"
    local base=""
    local vlan_keyword="${ETHER_VLAN_KEYWORD:+ $ETHER_VLAN_KEYWORD}"

    # Determine base keyword and default overhead
    case "$preset" in
        pppoe-ethernet)
            base="ethernet"; : "${oh:=46}"; : "${mpu:=84}"; vlan_keyword=""
            ;;
        pppoe-vlan-ethernet)
            base="ethernet"; : "${oh:=50}"; : "${mpu:=84}"; vlan_keyword=""
            ;;
        pppoe-gpon)
            base="raw";      : "${oh:=31}"; : "${mpu:=69}"; vlan_keyword=""
            ;;
        pppoe-vlan-gpon)
            base="raw";      : "${oh:=35}"; : "${mpu:=69}"; vlan_keyword=""
            ;;
        pppoe-vlan-gpon-conservative)
            base="raw";      : "${oh:=39}"; : "${mpu:=73}"; vlan_keyword=""
            ;;
        *atm*|*adsl*|*pppoa*|*pppoe*|*bridged*|*ipoa*|conservative)
            [ "$mode" = "hybrid" ] && base="atm" || base="${preset}"
            : "${oh:=44}"
            ;;
        docsis)       base="docsis";   : "${oh:=25}" ;;
        cake-ethernet) base="ethernet"; [ "$mode" != "hybrid" ] && oh="" || : "${oh:=38}" ;;
        raw)          base="raw";      : "${oh:=0}" ;;
        ethernet|*)   base="ethernet"; : "${oh:=40}" ;;
    esac

    # Build parameters
    printf "%s%s%s%s" \
        "$base" \
        "${oh:+ overhead $oh}" \
        "${mpu:+ mpu $mpu}" \
        "$vlan_keyword"
}

should_apply_root_stab() {
    local dir="$1"
    [ "$dir" != "lan" ] || [ "${DOWNLOAD_IFB_STAB:-0}" = "1" ]
}

disable_qos_offload_feature() {
    local dev="$1" feature="$2"
    ethtool -K "$dev" "$feature" off >/dev/null 2>&1 || true
}

disable_qos_offloads() {
    local dev="$1" role="$2" feature

    [ "${DISABLE_QOS_OFFLOADS:-1}" = "1" ] || return 0
    [ -n "$dev" ] || return 0

    if ! command -v ethtool >/dev/null 2>&1; then
        if [ "${QOS_OFFLOAD_WARNED_MISSING_ETHTOOL:-0}" -eq 0 ] 2>/dev/null; then
            log_msg -warn "QoS offload control requested but ethtool is not installed; skipping offload changes."
            QOS_OFFLOAD_WARNED_MISSING_ETHTOOL=1
        fi
        return 0
    fi

    if ! ip link show "$dev" >/dev/null 2>&1; then
        [ "$role" = "extra" ] && log_msg -warn "QoS offload extra device $dev not found; skipping."
        return 0
    fi

    for feature in gro gso tso rx-gro-list tx-udp-segmentation hw-tc-offload; do
        disable_qos_offload_feature "$dev" "$feature"
    done
}

disable_configured_extra_offloads() {
    local dev

    [ "${QOS_OFFLOAD_EXTRA_APPLIED:-0}" -eq 0 ] 2>/dev/null || return 0
    QOS_OFFLOAD_EXTRA_APPLIED=1

    for dev in $OFFLOAD_EXTRA_DEVICES; do
        disable_qos_offloads "$dev" "extra"
    done
}

##############################
# Variable checks and dynamic rule generation
##############################

# FIX: ACK rates are now calculated per-interface in setup_interface() (Bug #8)
# Removed deprecated calculate_ack_rates() function call
# ACK rate limiting is now configured directly in setup_interface() per WAN interface

# Debug function
debug_log() {
    [ -n "$MULTIWAN_QOS_DEBUG" ] || return 0
    logger -s -t multiwan_qos "$1" >&2
}

get_priomap_elements() {
    # The nft priomap is global while qdiscs are per-interface. Always keep
    # the full HFSC map so mixed HFSC + Hybrid/HTB setups do not lose HFSC
    # lanes. Per-interface tc filters still collapse unsupported classes.
    echo "ef : 1:11, cs5 : 1:11, cs6 : 1:11, cs7 : 1:11, cs4 : 1:12, af41 : 1:12, af42 : 1:12, cs2 : 1:14, af11 : 1:14, cs1 : 1:15, cs0 : 1:13"
}

get_dscp_classid_for_qdisc() {
    local dscp_class="$1" qdisc="${2:-hfsc}"

    case "$qdisc" in
        hfsc)
            case "$dscp_class" in
                ef|cs5|cs6|cs7) echo "1:11" ;;
                cs4|af41|af42) echo "1:12" ;;
                cs2|af11) echo "1:14" ;;
                cs1) echo "1:15" ;;
                cs0) echo "1:13" ;;
            esac
            ;;
        *)
            case "$dscp_class" in
                ef|cs5|cs6|cs7) echo "1:11" ;;
                cs4|af41|af42|cs0) echo "1:13" ;;
                cs2|af11|cs1) echo "1:15" ;;
            esac
            ;;
    esac
}

# Shell variable to track set name -> family mappings (#12: replaces /tmp/multiwan_qos_set_families file)
MULTIWAN_QOS_SET_FAMILIES=""

# Function to create NFT sets from config
create_nft_sets() {
    local sets_created=""

    # shellcheck disable=SC2329
    create_set() {
        local section="$1" name ip_list mode timeout set_flags

        config_get name "$section" name
        # Only process if enabled (default: enabled)
        local enabled=1
        config_get_bool enabled "$section" enabled 1
        [ "$enabled" -eq 0 ] && return 0

        config_get mode "$section" mode "static"
        config_get timeout "$section" timeout "1h"
        config_get family "$section" family "ipv4"

        # Get the IP list based on family
        if [ "$family" = "ipv6" ]; then
            config_get ip_list "$section" ip6
            MULTIWAN_QOS_SET_FAMILIES="${MULTIWAN_QOS_SET_FAMILIES}${name} ipv6${_NL_}"
        else
            config_get ip_list "$section" ip4
            MULTIWAN_QOS_SET_FAMILIES="${MULTIWAN_QOS_SET_FAMILIES}${name} ipv4${_NL_}"
        fi

        # Use the family parameter from the UCI configuration ("ipv4" or "ipv6")
        if [ "$mode" = "dynamic" ]; then
            set_flags="dynamic, timeout"
            if [ "$family" = "ipv6" ]; then
                debug_log "Creating dynamic IPv6 set: $name"
                echo "set $name { type ipv6_addr; flags $set_flags; timeout $timeout; }"
            else
                debug_log "Creating dynamic IPv4 set: $name"
                echo "set $name { type ipv4_addr; flags $set_flags; timeout $timeout; }"
            fi
        else
            set_flags="interval"
            if [ -n "$ip_list" ]; then
                if [ "$family" = "ipv6" ]; then
                    debug_log "Creating static IPv6 set: $name"
                    echo "set $name { type ipv6_addr; flags $set_flags; elements = { $(echo "$ip_list" | tr ' ' ',') }; }"
                else
                    debug_log "Creating static IPv4 set: $name"
                    echo "set $name { type ipv4_addr; flags $set_flags; elements = { $(echo "$ip_list" | tr ' ' ',') }; }"
                fi
            else
                if [ "$family" = "ipv6" ]; then
                    debug_log "Creating empty static IPv6 set: $name"
                    echo "set $name { type ipv6_addr; flags $set_flags; }"
                else
                    debug_log "Creating empty static IPv4 set: $name"
                    echo "set $name { type ipv4_addr; flags $set_flags; }"
                fi
            fi
        fi
        sets_created="$sets_created $name"
    }

    # Reset the variable
    MULTIWAN_QOS_SET_FAMILIES=""

    config_foreach create_set ipset

    export MULTIWAN_QOS_SETS="$sets_created"
    [ -n "$sets_created" ] && debug_log "Created sets: $sets_created"
}

# Create NFT sets
SETS=$(create_nft_sets)

# Create rules
# shellcheck disable=SC2329
create_nft_rule() {
    # Trim leading and trailing whitespaces and tabs in variable $1
    trim_spaces() {
        local tr_in tr_out
        eval "tr_in=\"\${$1}\""
        tr_out="${tr_in%"${tr_in##*[! 	]}"}"
        tr_out="${tr_out#"${tr_out%%[! 	]*}"}"
        eval "$1=\"\${tr_out}\""
    }

    is_set_ref() {
        case "$1" in "@"*) return 0; esac
        return 1
    }

    # checks whether string is an ipv6 mask
    is_ipv6_mask() {
        case "$1" in
            ::*/::*) ;;
            *) return 1
        esac
        local inp="${1#"::"}"
        case "${inp%"/::"*}" in *"/"*) return 1; esac
        return 0
    }

    # Function to check if a single IP address is IPv6
    # Note: This assumes the input is a single IP, not a space-separated list
    # Handles CIDR notation (e.g. ::/0 or 192.168.1.0/24)
    is_ipv6() {
        local ip="${1%/*}"  # Remove CIDR suffix if present
        # Use regex pattern to properly validate IPv6
        case "$ip" in
            *:*:*|*::*) return 0 ;;
            *) return 1 ;;
        esac
    }

    local config="$1"
    local proto class counter name enabled trace

    config_get proto "$config" proto
    config_get class "$config" class
    config_get_bool counter "$config" counter 0
    config_get_bool trace "$config" trace 0
    config_get name "$config" name
    config_get_bool enabled "$config" enabled 1  # Default to enabled if not set

    # Check if the rule is enabled
    [ "$enabled" = "0" ] && return 0

    # Convert class to lowercase
    class=$(echo "$class" | tr 'A-Z' 'a-z')

    # Ensure class is not empty
    if [ -z "$class" ]; then
        print_msg -err "Class for rule '$config' is empty."
        return 1
    fi
    
    # Function to get set family
    get_set_family() {
        local setname="$1"
        printf '%s\n' "$MULTIWAN_QOS_SET_FAMILIES" | awk -v set="$setname" '$1 == set {print $2}'
    }
    
    # Function to separate IPs by family
    separate_ips_by_family() {
        local ips="$3" \
            ip prefix setname \
            ipv4_result="" \
            ipv6_result=""
        
        # Debug log (uncomment for troubleshooting)
        # debug_log "separate_ips_by_family: Processing IPs: '$ips'"
        
        for ip in $ips; do
            # Preserve != prefix
            prefix=""
            case "$ip" in '!='*)
                prefix="!="
                ip="${ip#"!="}"
            esac
            
            # debug_log "  Checking IP: '$ip'
            
            # Check if it's a set reference
            if is_set_ref "$ip"; then
                setname="${ip#"@"}"
                if [ "$(get_set_family "$setname")" = "ipv6" ]; then
                    ipv6_result="${ipv6_result}${ipv6_result:+ }${prefix}${ip}"
                    # debug_log "    -> IPv6 set: $setname"
                else
                    ipv4_result="${ipv4_result}${ipv4_result:+ }${prefix}${ip}"
                    # debug_log "    -> IPv4 set: $setname"
                fi
            # Check for IPv6 suffix format
            elif is_ipv6_mask "$ip"; then
                ipv6_result="${ipv6_result}${ipv6_result:+ }${prefix}${ip}"
                # debug_log "    -> IPv6 suffix format"
            # Regular IP check
            elif is_ipv6 "$ip"; then
                ipv6_result="${ipv6_result}${ipv6_result:+ }${prefix}${ip}"
                # debug_log "    -> IPv6 address"
            else
                ipv4_result="${ipv4_result}${ipv4_result:+ }${prefix}${ip}"
                # debug_log "    -> IPv4 address"
            fi
        done
        
        # debug_log "  Results: IPv4='$ipv4_result', IPv6='$ipv6_result'"
        eval "${1}=\"\${ipv4_result}\" ${2}=\"\${ipv6_result}\""
    }
    
    # Check and separate source and destination IPs
    local src_ip dest_ip \
        src_ip_v4='' src_ip_v6='' dest_ip_v4='' dest_ip_v6='' \
        has_ipv4=0 has_ipv6=0 \
        ip_val ip_type

    for ip_type in src_ip dest_ip; do
        config_get "${ip_type}" "$config" "${ip_type}"
        eval "ip_val=\"\${$ip_type}\""
        if [ -n "$ip_val" ]; then
            separate_ips_by_family "${ip_type}_v4" "${ip_type}_v6" "$ip_val"
            eval "
                [ -n \"\${${ip_type}_v4}\" ] && has_ipv4=1
                [ -n \"\${${ip_type}_v6}\" ] && has_ipv6=1
            "
        fi
    done

    # Log if mixed IPv4/IPv6 addresses are found
    if [ "$has_ipv4" -eq 1 ] && [ "$has_ipv6" -eq 1 ]; then 
        log_msg "" "Info: Mixed IPv4/IPv6 addresses in rule '$name' ($config). Splitting into separate rules." >&2
    fi

    # If no IP address was specified, we assume the rule applies to both IPv4 and IPv6
    if [ -z "$src_ip" ] && [ -z "$dest_ip" ] && [ "$has_ipv4" -eq 0 ] && [ "$has_ipv6" -eq 0 ]; then
        debug_log "Rule '$name' ($config): No IP specified, generating rules for both IPv4 and IPv6."
        has_ipv4=1
        has_ipv6=1
    fi

    # Function to handle multiple values with IP family awareness
    gen_rule() {
        add_res_rule() {
            if [ -z "$res_set_neg" ] && [ -z "$res_set_pos" ]; then
                error_out "no valid $1 found in '$values'. Rule skipped."
                return 1
            fi

            if [ -n "$res_set_neg" ]; then
                result="${result}${result:+ }${prefix} != { ${res_set_neg} }"
            fi

            if [ -n "$res_set_pos" ]; then
                result="${result}${result:+ }${prefix} { ${res_set_pos} }"
            fi
            :
        }

        local value setname family suffix mask comp_op negation \
            result='' res_set_neg='' res_set_pos='' has_ipv4='' has_ipv6='' set_ref_seen='' ipv6_mask_seen='' reg_val_seen='' \
            values="$1" \
            prefix="$2"
        
        for value in $values; do
            if [ -n "$set_ref_seen" ] || [ -n "$ipv6_mask_seen" ]; then
                error_out "invalid entry '$values'. When using nftables set reference or ipv6 mask, other values are not allowed."
                return 1
            fi

            # Check if value starts with '!=' and preserve the '!=' prefix
            negation=
            comp_op="=="
            case "$value" in '!='*)
                negation=" !="
                comp_op="!="
                value="${value#"!="}"
            esac

            # Handle set references (@setname)
            if is_set_ref "$value"; then
                if [ -n "$reg_val_seen" ]; then
                    error_out "invalid entry '$values'. When using nftables set reference or ipv6 mask, other values are not allowed."
                    return 1
                fi
                set_ref_seen=1
                setname="${value#@}"
                family="$(get_set_family "$setname")"
                debug_log "Set $setname has family: $family"
                
                if [ "$family" = "ipv6" ]; then
                    prefix="${prefix//ip /ip6 }"
                fi
                result="${prefix}${negation} @${setname}"
                continue
            fi

            # Check for IPv6 suffix format (::suffix/::mask)
            if is_ipv6_mask "$value"; then
                if [ -n "$reg_val_seen" ]; then
                    error_out "invalid entry '$values'. When using nftables set reference or ipv6 mask, other values are not allowed."
                    return 1
                fi
                ipv6_mask_seen=1
                # Extract suffix and mask
                suffix="${value%%"/::"*}"
                mask="${value#"${suffix}/"}"
                
                # Force IPv6 prefix and create bitwise AND|NOT match
                result="${prefix//ip /ip6 } & ${mask} ${comp_op} ${suffix}"
                continue
            fi

            # Validate prefix type
            case "$prefix" in 
                "ip saddr"|"ip daddr"|"ip6 saddr"|"ip6 daddr"|"th sport"|"th dport"|"meta l4proto")
                    ;;
                *)
                    error_out "unexpected prefix '$prefix'."
                    return 1
                    ;;
            esac

            case "$prefix" in *addr*)
                if is_ipv6 "$value"; then
                    has_ipv6=1
                else
                    has_ipv4=1
                fi
            esac

            # Collect values
            if [ -n "$negation" ]; then
                res_set_neg="${res_set_neg}${res_set_neg:+,}${value}"
            else
                res_set_pos="${res_set_pos}${res_set_pos:+,}${value}"
            fi

            reg_val_seen=1
        done

        if [ -n "$set_ref_seen" ] || [ -n "$ipv6_mask_seen" ]; then
            printf '%s\n' "$result"
            return 0
        fi

        # If mixed, log and signal error
        if [ -n "$has_ipv4" ] && [ -n "$has_ipv6" ]; then
            error_out "Mixed IPv4/IPv6 addresses within a set: { $values }. Rule skipped."
            return 1
        fi

        # Update prefix based on IP type
        if [ -n "$has_ipv6" ]; then
            prefix="${prefix//ip /ip6 }"
        fi

        # Construct the final rule
        case "$prefix" in
            *addr*)
                # IP address rules
                add_res_rule addresses || return 1
                ;;
                
            "th sport"|"th dport")
                # Port rules
                add_res_rule ports || return 1
                ;;
                
            "meta l4proto")
                # Protocol rules
                add_res_rule protocols || return 1
                ;;
        esac

        printf '%s\n' "$result"
    }

    # Initialize rule string
    local rule_cmd=""

    # Handle multiple protocols
    if [ -n "$proto" ]; then
        local proto_result
        if ! proto_result="$(gen_rule "$proto" "meta l4proto")"; then
            # Skip rule
            return 0
        fi
        rule_cmd="$rule_cmd $proto_result"
    fi

    # Note: Source and Destination IP handling is now done per-family in the rule generation below
    
    # Use connection tracking for source and destination ports
    local port port_type port_res port_seen=''

    for port_type in src_port dest_port; do
        config_get port "$config" "$port_type"
        if [ -n "$port" ]; then
            if ! port_res="$(gen_rule "$port" "th ${port_type%%"${port_type#?}"}port")"; then
                # Skip rule
                return 0
            fi
            rule_cmd="$rule_cmd $port_res"
            port_seen=1
        fi
    done

    # Build final rule(s) based on has_ipv4 and has_ipv6 flags
    local final_rule_v4=""
    local final_rule_v6=""
    local common_rule_part="$rule_cmd"
    trim_spaces common_rule_part # Trim common parts

    # Generate IPv4 rule if needed
    if [ "$has_ipv4" -eq 1 ]; then
        local rule_cmd_v4="$common_rule_part"
        
        # Add IPv4-specific IP addresses
        if [ -n "$src_ip_v4" ]; then
            local src_result
            if ! src_result="$(gen_rule "$src_ip_v4" "ip saddr")"; then
                # Skip rule
                return 0
            fi
            rule_cmd_v4="$rule_cmd_v4 $src_result"
        fi
        if [ -n "$dest_ip_v4" ]; then
            local dest_result
            if ! dest_result="$(gen_rule "$dest_ip_v4" "ip daddr")"; then
                # Skip rule
                return 0
            fi
            rule_cmd_v4="$rule_cmd_v4 $dest_result"
        fi
        
        local rev_rule_cmd_v4=""
        if [ "$counter" -eq 1 ]; then
            case "$rule_cmd_v4" in
                *saddr*|*daddr*|*sport*|*dport*)
                    rev_rule_cmd_v4="$rule_cmd_v4"
                    # Reverse matching logic by swapping source and destination
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//saddr/__TMP_ADDR__}"
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//daddr/saddr}"
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//__TMP_ADDR__/daddr}"
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//sport/__TMP_PORT__}"
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//dport/sport}"
                    rev_rule_cmd_v4="${rev_rule_cmd_v4//__TMP_PORT__/dport}"
                    ;;
            esac
        fi

        # Ensure we only add parts if there's something to match on (IP/Port/Proto)
        if [ -n "$proto" ] || [ -n "$src_ip_v4" ] || [ -n "$dest_ip_v4" ] || [ -n "$port_seen" ]; then
            rule_cmd_v4="$rule_cmd_v4 ip dscp set $class"
        fi
        [ "$counter" -eq 1 ] && rule_cmd_v4="$rule_cmd_v4 counter"
        [ "$trace" -eq 1 ] && rule_cmd_v4="$rule_cmd_v4 meta nftrace set 1"
        [ -n "$name" ] && rule_cmd_v4="$rule_cmd_v4 comment \"ipv4_${name}_OUT\""
            
        trim_spaces rule_cmd_v4 # Trim final rule
        # Ensure the rule is not just a semicolon
        if [ -n "$rule_cmd_v4" ] && [ "$rule_cmd_v4" != ";" ]; then
            final_rule_v4="$rule_cmd_v4;"
        fi

        if [ -n "$rev_rule_cmd_v4" ]; then
            rev_rule_cmd_v4="$rev_rule_cmd_v4 counter"
            [ "$trace" -eq 1 ] && rev_rule_cmd_v4="$rev_rule_cmd_v4 meta nftrace set 1"
            [ -n "$name" ] && rev_rule_cmd_v4="$rev_rule_cmd_v4 comment \"ipv4_${name}_IN\""
            trim_spaces rev_rule_cmd_v4
            if [ -n "$rev_rule_cmd_v4" ] && [ "$rev_rule_cmd_v4" != ";" ]; then
                final_rule_v4="$final_rule_v4${_NL_}$rev_rule_cmd_v4;"
            fi
        fi
    fi

    # Generate IPv6 rule if needed
    if [ "$has_ipv6" -eq 1 ]; then
        local rule_cmd_v6="$common_rule_part"
        
        # Add IPv6-specific IP addresses
        if [ -n "$src_ip_v6" ]; then
            local src_result
            if ! src_result="$(gen_rule "$src_ip_v6" "ip6 saddr")"; then
                # Skip rule
                return 0
            fi
            rule_cmd_v6="$rule_cmd_v6 $src_result"
        fi
        if [ -n "$dest_ip_v6" ]; then
            local dest_result
            if ! dest_result="$(gen_rule "$dest_ip_v6" "ip6 daddr")"; then
                # Skip rule
                return 0
            fi
            rule_cmd_v6="$rule_cmd_v6 $dest_result"
        fi
        
        local rev_rule_cmd_v6=""
        if [ "$counter" -eq 1 ]; then
            case "$rule_cmd_v6" in
                *saddr*|*daddr*|*sport*|*dport*)
                    rev_rule_cmd_v6="$rule_cmd_v6"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//saddr/__TMP_ADDR__}"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//daddr/saddr}"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//__TMP_ADDR__/daddr}"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//sport/__TMP_PORT__}"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//dport/sport}"
                    rev_rule_cmd_v6="${rev_rule_cmd_v6//__TMP_PORT__/dport}"
                    ;;
            esac
        fi

        # Ensure we only add parts if there's something to match on (IP/Port/Proto)
        if [ -n "$proto" ] || [ -n "$src_ip_v6" ] || [ -n "$dest_ip_v6" ] || [ -n "$port_seen" ]; then
            rule_cmd_v6="$rule_cmd_v6 ip6 dscp set $class"
        fi
        [ "$counter" -eq 1 ] && rule_cmd_v6="$rule_cmd_v6 counter"
        [ "$trace" -eq 1 ] && rule_cmd_v6="$rule_cmd_v6 meta nftrace set 1"
        [ -n "$name" ] && rule_cmd_v6="$rule_cmd_v6 comment \"ipv6_${name}_OUT\""

        trim_spaces rule_cmd_v6 # Trim final rule
        # Ensure the rule is not just a semicolon
        if [ -n "$rule_cmd_v6" ] && [ "$rule_cmd_v6" != ";" ]; then
             final_rule_v6="$rule_cmd_v6;"
        fi

        if [ -n "$rev_rule_cmd_v6" ]; then
            rev_rule_cmd_v6="$rev_rule_cmd_v6 counter"
            [ "$trace" -eq 1 ] && rev_rule_cmd_v6="$rev_rule_cmd_v6 meta nftrace set 1"
            [ -n "$name" ] && rev_rule_cmd_v6="$rev_rule_cmd_v6 comment \"ipv6_${name}_IN\""
            trim_spaces rev_rule_cmd_v6
            if [ -n "$rev_rule_cmd_v6" ] && [ "$rev_rule_cmd_v6" != ";" ]; then
                final_rule_v6="$final_rule_v6${_NL_}$rev_rule_cmd_v6;"
            fi
        fi
    fi

    # Output the generated rules (if any)
    [ -n "$final_rule_v4" ] && echo "$final_rule_v4"
    [ -n "$final_rule_v6" ] && echo "$final_rule_v6"

}

generate_dynamic_nft_rules() {
    # Check global enable setting
    if [ "$global_enabled" = "1" ]; then
        config_foreach create_nft_rule rule
    else
        echo "        # MultiWAN QoS custom rules are globally disabled"
    fi
}

##############################
# Rate Limit Functions
##############################

# Build nftables device match conditions from target values with direction support
# Detects IP/IPv6 addresses and generates appropriate match statements
# Args: $1=target_values, $2=direction (saddr/daddr), $3=result_var_name
# shellcheck disable=SC2329
build_device_conditions_for_direction() {
    local target_values="$1" direction="$2" result_var_v4="$3" result_var_v6="$4"
    local result_v4="" result_v6="" ipv4_pos="" ipv4_neg="" ipv6_pos="" ipv6_neg=""
    local value negation v
    
    for value in $target_values; do
        negation=""
        v="$value"
        
        # Check for negation prefix
        case "$v" in
            '!='*)
                negation="!="
                v="${v#!=}"
                ;;
        esac
        
        # Check for set reference (@setname)
        case "$v" in
            '@'*)
                # Set reference - determine family and use correct prefix
                local setname="${v#@}"
                local set_family
                set_family="$(printf '%s\n' "$MULTIWAN_QOS_SET_FAMILIES" | awk -v set="$setname" '$1 == set {print $2}')"
                
                if [ "$set_family" = "ipv6" ]; then
                    if [ -n "$negation" ]; then
                        result_v6="${result_v6}${result_v6:+ }ip6 ${direction} != @${setname}"
                    else
                        result_v6="${result_v6}${result_v6:+ }ip6 ${direction} @${setname}"
                    fi
                else
                    if [ -n "$negation" ]; then
                        result_v4="${result_v4}${result_v4:+ }ip ${direction} != @${setname}"
                    else
                        result_v4="${result_v4}${result_v4:+ }ip ${direction} @${setname}"
                    fi
                fi
                ;;
            *)
                # Detect address type and collect for set notation
                # Skip MAC addresses (not supported)
                if printf '%s' "$v" | grep -qE '^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$'; then
                    log_msg -warn "MAC address '$v' in rate limit rule ignored (not supported)"
                elif printf '%s' "$v" | grep -q ':' && ! printf '%s' "$v" | grep -qE '^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$'; then
                    # IPv6 address (contains colon, not a MAC address)
                    if [ -n "$negation" ]; then
                        ipv6_neg="${ipv6_neg}${ipv6_neg:+,}${v}"
                    else
                        ipv6_pos="${ipv6_pos}${ipv6_pos:+,}${v}"
                    fi
                else
                    # IPv4 address or CIDR
                    if [ -n "$negation" ]; then
                        ipv4_neg="${ipv4_neg}${ipv4_neg:+,}${v}"
                    else
                        ipv4_pos="${ipv4_pos}${ipv4_pos:+,}${v}"
                    fi
                fi
                ;;
        esac
    done
    
    # Build set-based conditions
    if [ -n "$ipv4_neg" ]; then
        result_v4="${result_v4}${result_v4:+ }ip ${direction} != { ${ipv4_neg} }"
    fi
    if [ -n "$ipv4_pos" ]; then
        result_v4="${result_v4}${result_v4:+ }ip ${direction} { ${ipv4_pos} }"
    fi
    if [ -n "$ipv6_neg" ]; then
        result_v6="${result_v6}${result_v6:+ }ip6 ${direction} != { ${ipv6_neg} }"
    fi
    if [ -n "$ipv6_pos" ]; then
        result_v6="${result_v6}${result_v6:+ }ip6 ${direction} { ${ipv6_pos} }"
    fi
    
    eval "${result_var_v4}=\"\${result_v4}\""
    if [ -n "$result_var_v6" ]; then
        eval "${result_var_v6}=\"\${result_v6}\""
    fi
}

# Generate rate limit rules from UCI config
generate_ratelimit_rules() {
    local rules=""
    
    # Process each ratelimit section
    # shellcheck disable=SC2329
    process_ratelimit_section() {
        local section="$1"
        local name enabled download_limit upload_limit burst_factor
        local target_values remote_values proto ports meter_suffix download_kbytes upload_kbytes
        local download_burst upload_burst
        
        config_get_bool enabled "$section" enabled 1
        [ "$enabled" -eq 0 ] && return 0
        
        config_get name "$section" name
        [ -z "$name" ] && {
            log_msg -warn "Rate limit section '$section' has no name - skipping"
            return 0
        }
        
        config_get download_limit "$section" download_limit "0"
        config_get upload_limit "$section" upload_limit "0"
        config_get burst_factor "$section" burst_factor "1.0"
        
        config_get target_values "$section" target
        config_get remote_values "$section" remote
        config_get proto "$section" proto
        config_get ports "$section" ports
        
        # Validate: need at least one target and one limit
        [ -z "$target_values" ] && {
            log_msg -warn "Rate limit rule '$name' has no target devices - skipping"
            return 0
        }
        [ "$download_limit" -eq 0 ] && [ "$upload_limit" -eq 0 ] && {
            log_msg -warn "Rate limit rule '$name' has no bandwidth limits - skipping"
            return 0
        }
        
        # Build protocol matches if specified
        local proto_match="" port_dl_match="" port_ul_match=""
        if [ -n "$proto" ] && [ "$proto" != "all" ]; then
            if [ "$proto" = "tcpudp" ]; then
                proto_match="meta l4proto { tcp, udp }"
            else
                proto_match="meta l4proto ${proto}"
            fi
            
            # Port matching requires protocol to be parsed correctly by nftables
            if [ -n "$ports" ]; then
                # Handle space-separated ports by enclosing in set notation if needed
                local formatted_ports
                if printf '%s' "$ports" | grep -q ' '; then
                    formatted_ports="{ $(echo "$ports" | tr ' ' ',') }"
                else
                    formatted_ports="$ports"
                fi
                
                if [ "$proto" = "tcpudp" ]; then
                    port_dl_match="@th,0,16 ${formatted_ports}"
                    port_ul_match="@th,16,16 ${formatted_ports}"
                else
                    # For download (from remote to target), match source port
                    port_dl_match="th sport ${formatted_ports}"
                    # For upload (from target to remote), match destination port
                    port_ul_match="th dport ${formatted_ports}"
                fi
            fi
        fi
        
        # Sanitize name for meter usage (only alphanumeric and underscore)
        meter_suffix="$(printf '%s' "$name" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_')"
        [ -z "$meter_suffix" ] && meter_suffix="unnamed_${section}"
        
        # Convert Kbit/s to kbytes/second (1 Kbit/s = 0.125 kbytes/s)
        # Clamp to minimum 1 to prevent burst=0 for very small rates (#8)
        download_kbytes=$((download_limit / 8))
        [ "$download_kbytes" -lt 1 ] && download_kbytes=1
        upload_kbytes=$((upload_limit / 8))
        [ "$upload_kbytes" -lt 1 ] && upload_kbytes=1
        
        # Calculate burst using robust decimal parsing
        # If burst_factor is 0, we don't add burst parameter at all (strict rate limit)
        local download_burst_param='' upload_burst_param=''
        
        # Parse burst_factor robustly (handle cases like "1.", ".5", "0.25", etc.)
        case "$burst_factor" in
            0|0.0|0.00) 
                # No burst - strict limiting
                ;;
            *.*) 
                # Has decimal point
                local burst_int="${burst_factor%.*}"
                local burst_dec="${burst_factor#*.}"
                
                # Handle missing parts
                [ -z "$burst_int" ] && burst_int='0'
                [ -z "$burst_dec" ] && burst_dec='0'
                
                # Pad or truncate decimal to 2 digits for centiprecision
                case "${#burst_dec}" in
                    1) burst_dec="${burst_dec}0" ;;  # 0.5 -> 50
                    2) ;;  # 0.25 -> 25
                    *) burst_dec="$(printf '%.2s' "$burst_dec")" ;;  # 0.125 -> 12
                esac
                
                # Calculate: burst = rate * (int + dec/100)
                local download_burst=$((download_kbytes * burst_int + download_kbytes * burst_dec / 100))
                local upload_burst=$((upload_kbytes * burst_int + upload_kbytes * burst_dec / 100))
                
                [ "$download_burst" -gt 0 ] && download_burst_param=" burst ${download_burst} kbytes"
                [ "$upload_burst" -gt 0 ] && upload_burst_param=" burst ${upload_burst} kbytes"
                ;;
            *)
                # Integer only (e.g. "1", "2")
                local download_burst=$((download_kbytes * burst_factor))
                local upload_burst=$((upload_kbytes * burst_factor))
                download_burst_param=" burst ${download_burst} kbytes"
                upload_burst_param=" burst ${upload_burst} kbytes"
                ;;
        esac
        
        # Separate targets by IP family
        local targets_v4='' targets_v6='' value prefix setname set_family
        
        for value in $target_values; do
            # Preserve != prefix
            prefix=''
            case "$value" in
                '!='*)
                    prefix='!='
                    value="${value#!=}"
                    ;;
            esac
            
            # Check if it's a set reference
            case "$value" in
                '@'*)
                    setname="${value#@}"
                    set_family="$(printf '%s\n' "$MULTIWAN_QOS_SET_FAMILIES" | awk -v set="$setname" '$1 == set {print $2}')"
                    if [ "$set_family" = "ipv6" ]; then
                        targets_v6="${targets_v6}${targets_v6:+ }${prefix}${value}"
                    else
                        targets_v4="${targets_v4}${targets_v4:+ }${prefix}${value}"
                    fi
                    ;;
                *)
                    # Check if IPv6 (contains colon and not MAC)
                    if printf '%s' "$value" | grep -q ':' && ! printf '%s' "$value" | grep -qE '^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$'; then
                        targets_v6="${targets_v6}${targets_v6:+ }${prefix}${value}"
                    else
                        targets_v4="${targets_v4}${targets_v4:+ }${prefix}${value}"
                    fi
                    ;;
            esac
        done
        
        # Build Remote match conditions
        local remote_dl_v4='' remote_ul_v4='' remote_dl_v6='' remote_ul_v6=''
        if [ -n "$remote_values" ]; then
            build_device_conditions_for_direction "$remote_values" "saddr" remote_dl_v4 remote_dl_v6
            build_device_conditions_for_direction "$remote_values" "daddr" remote_ul_v4 remote_ul_v6
        fi
        
        # Generate IPv4 rules
        if [ -n "$targets_v4" ]; then
            if [ "$download_limit" -gt 0 ]; then
                local download_conditions_v4=''
                build_device_conditions_for_direction "$targets_v4" "daddr" download_conditions_v4 ""
                
                local remote_v4_only="$remote_dl_v4"
                
                [ -n "$download_conditions_v4" ] && rules="${rules}
        # ${name} - Download limit (IPv4)
        ${download_conditions_v4}${remote_v4_only:+ ${remote_v4_only}}${proto_match:+ ${proto_match}}${port_dl_match:+ ${port_dl_match}} meter ${meter_suffix}_dl4 { ip daddr limit rate over ${download_kbytes} kbytes/second${download_burst_param} } counter drop comment \"${name} download\""
            fi
            
            if [ "$upload_limit" -gt 0 ]; then
                local upload_conditions_v4=''
                build_device_conditions_for_direction "$targets_v4" "saddr" upload_conditions_v4 ""
                
                local remote_v4_only="$remote_ul_v4"
                
                [ -n "$upload_conditions_v4" ] && rules="${rules}
        # ${name} - Upload limit (IPv4)
        ${upload_conditions_v4}${remote_v4_only:+ ${remote_v4_only}}${proto_match:+ ${proto_match}}${port_ul_match:+ ${port_ul_match}} meter ${meter_suffix}_ul4 { ip saddr limit rate over ${upload_kbytes} kbytes/second${upload_burst_param} } counter drop comment \"${name} upload\""
            fi
        fi
        
        # Generate IPv6 rules
        if [ -n "$targets_v6" ]; then
            if [ "$download_limit" -gt 0 ]; then
                local download_conditions_v6=''
                build_device_conditions_for_direction "$targets_v6" "daddr" "" download_conditions_v6
                
                local remote_v6_only="$remote_dl_v6"
                
                [ -n "$download_conditions_v6" ] && rules="${rules}
        # ${name} - Download limit (IPv6)
        ${download_conditions_v6}${remote_v6_only:+ ${remote_v6_only}}${proto_match:+ ${proto_match}}${port_dl_match:+ ${port_dl_match}} meter ${meter_suffix}_dl6 { ip6 daddr limit rate over ${download_kbytes} kbytes/second${download_burst_param} } counter drop comment \"${name} download\""
            fi
            
            if [ "$upload_limit" -gt 0 ]; then
                local upload_conditions_v6=''
                build_device_conditions_for_direction "$targets_v6" "saddr" "" upload_conditions_v6
                
                local remote_v6_only="$remote_ul_v6"
                
                [ -n "$upload_conditions_v6" ] && rules="${rules}
        # ${name} - Upload limit (IPv6)
        ${upload_conditions_v6}${remote_v6_only:+ ${remote_v6_only}}${proto_match:+ ${proto_match}}${port_ul_match:+ ${port_ul_match}} meter ${meter_suffix}_ul6 { ip6 saddr limit rate over ${upload_kbytes} kbytes/second${upload_burst_param} } counter drop comment \"${name} upload\""
            fi
        fi
    }
    
    # Process all ratelimit sections from UCI
    config_foreach process_ratelimit_section ratelimit
    
    # Output rate limit chain if rules exist
    if [ -n "$rules" ]; then
        printf '\n%s\n%s\n%s%s\n%s\n' \
            "    # Rate Limit Chain" \
            "    chain ratelimit {" \
            "        type filter hook forward priority 0; policy accept;" \
            "${rules}" \
            "    }"
    fi
}

# Generate dynamic rules (forward chain â€” post-DNAT, full IP + port matching)
DYNAMIC_RULES=$(generate_dynamic_nft_rules)

# PC Agent chain (populated dynamically by /www/cgi-bin/multiwan-qos-agent)
# Only created when agent is enabled in UCI config
AGENT_CHAIN=""
AGENT_JUMP=""
if [ "$AGENT_ENABLED" = "1" ] 2>/dev/null; then
    AGENT_CHAIN="
    # PC Agent dynamic chain â€” populated at runtime by the CGI endpoint
    chain multiwan_qos_agent {
    }"
    AGENT_JUMP="
        # PC Agent: jump to dynamic game rules
        counter jump multiwan_qos_agent"
fi

# Generate ingress netdev rules (pre-DNAT, port-based only â€” drives IFB classification)
# INGRESS_NFT_CHAINS is accumulated per WAN device inside setup_interface()
INGRESS_NFT_CHAINS=""

# ACK rate limiting is now per-interface (configured in setup_interface)
# NFT_ACK_RULES is populated during interface setup with per-WAN rates
# Legacy global ACKRATE is used when per-interface ackrate is unset
ack_rules=""  # Will be replaced by $NFT_ACK_RULES in generate_main_nft_file

# Check if UDPBULKPORT is set
if [ -n "$UDPBULKPORT" ]; then
    udpbulkport_rules="\
meta l4proto udp ct original proto-src \$udpbulkport counter jump mark_cs1
        meta l4proto udp ct original proto-dst \$udpbulkport counter jump mark_cs1"
else
    udpbulkport_rules="# UDP Bulk Port rules disabled, no ports defined."
fi

# Check if TCPBULKPORT is set
if [ -n "$TCPBULKPORT" ]; then
    tcpbulkport_rules="\
meta l4proto tcp ct original proto-dst \$tcpbulkport counter jump mark_cs1"
else
    tcpbulkport_rules="# TCP Bulk Port rules disabled, no ports defined."
fi

# Check if VIDCONFPORTS is set
if [ -n "$VIDCONFPORTS" ]; then
    vidconfports_rules="\
meta l4proto udp ct original proto-dst \$vidconfports counter jump mark_af42"
else
    vidconfports_rules="# VIDCONFPORTS Port rules disabled, no ports defined."
fi

# Check if REALTIME4 and REALTIME6 are set
if [ -n "$REALTIME4" ]; then
    realtime4_rules="\
meta l4proto udp ip daddr \$realtime4 ip dscp set cs5 counter
        meta l4proto udp ip saddr \$realtime4 ip dscp set cs5 counter"
else
    realtime4_rules="# REALTIME4 rules disabled, address not defined."
fi

if [ -n "$REALTIME6" ]; then
    realtime6_rules="\
meta l4proto udp ip6 daddr \$realtime6 ip6 dscp set cs5 counter
        meta l4proto udp ip6 saddr \$realtime6 ip6 dscp set cs5 counter"
else
    realtime6_rules="# REALTIME6 rules disabled, address not defined."
fi

# Check if LOWPRIOLAN4 and LOWPRIOLAN6 are set
if [ -n "$LOWPRIOLAN4" ]; then
    lowpriolan4_rules="\
meta l4proto udp ip daddr \$lowpriolan4 ip dscp set cs0 counter
        meta l4proto udp ip saddr \$lowpriolan4 ip dscp set cs0 counter"
else
    lowpriolan4_rules="# LOWPRIOLAN4 rules disabled, address not defined."
fi

if [ -n "$LOWPRIOLAN6" ]; then
    lowpriolan6_rules="\
meta l4proto udp ip6 daddr \$lowpriolan6 ip6 dscp set cs0 counter
        meta l4proto udp ip6 saddr \$lowpriolan6 ip6 dscp set cs0 counter"
else
    lowpriolan6_rules="# LOWPRIOLAN6 rules disabled, address not defined."
fi

# UDP rate limiting is now per-interface (configured in setup_interface)
# NFT_UDP_RATE_RULES is populated during interface setup with per-WAN scaled rates
udp_rate_limit_rules=""  # Will be replaced by $NFT_UDP_RATE_RULES

# TCP upgrade is now per-interface (configured in setup_interface)
# NFT_TCP_UPGRADE_RULES is populated during interface setup with per-WAN scaled rates
tcp_upgrade_rules=""  # Will be replaced by $NFT_TCP_UPGRADE_RULES

# TCP down-prioritization is now per-interface (configured in setup_interface)
# NFT_DOWNPRIO_RULES is populated during interface setup with per-WAN byte thresholds

##############################
# Inline Rules Check
##############################
INLINE_FILE="/etc/multiwan-qos.d/inline_dscptag.nft"
INLINE_INCLUDE=""

if [ -s "$INLINE_FILE" ]; then
    TMP_CHECK_FILE="/tmp/multiwan_qos_inline_sh_check.nft"

    {
        printf '%s\n\t%s\n' "table inet __multiwan_qos_sh_ctx {" "chain __dscptag_sh_ctx {"
        cat "$INLINE_FILE"
        printf "\n\t%s\n%s\n" "}" "}"
    } > "$TMP_CHECK_FILE"

    if nft --check --file "$TMP_CHECK_FILE" 2>/dev/null; then
        INLINE_INCLUDE="include \"$INLINE_FILE\""
    fi
    rm -f "$TMP_CHECK_FILE"
fi

##############################
#       dscptag.nft
##############################

# Replicate multiwan_nft's id2mask() to compute interface marks
# Spreads the bits of id into the mask positions
# e.g., id=1 mask=0x3f0000 -> 0x010000; id=2 -> 0x020000
multiwan_qos_id2mask() {
    local id="$1" mask="$2"
    local bit_msk bit_val result
    bit_msk=0
    bit_val=0
    result=0
    # Use arithmetic loop instead of 'seq' which may not exist on minimal OpenWrt (#6)
    while [ "$bit_msk" -le 31 ]; do
        if [ $(((mask>>bit_msk)&1)) = "1" ]; then
            if [ $(((id>>bit_val)&1)) = "1" ]; then
                result=$((result|(1<<bit_msk)))
            fi
            bit_val=$((bit_val+1))
        fi
        bit_msk=$((bit_msk+1))
    done
    printf "0x%08x" $result
}

# Generates a vmap to securely save DSCP into connection tracking.
# Nftables cannot simultaneously evaluate two dynamic variables (e.g. ct mark | ip dscp).
# To solve this, we map all 64 possible DSCP values to individual chains that 
# apply a constant bitwise mask. This strictly preserves all existing upper bits
# (like Mwan3's routing caches) without relying on fragile egress interface guessing.
generate_dscp_ct_save() {
    CT_SAVE_VMAP=""
    CT_SAVE_CHAINS=""
    local dscp_val val_hex
    
    # Use loop to generate 0-63
    local i=0
    while [ "$i" -le 63 ]; do
        dscp_val=$i
        val_hex=$(printf "0x%02x" $((dscp_val | 0x80)))
        
        CT_SAVE_CHAINS="${CT_SAVE_CHAINS}
    chain ct_save_dscp_${dscp_val} {
        ct mark and 0x000000ff == ${val_hex} return
        ct mark set ct mark and 0xFFFFFF00 or ${val_hex} counter return
    }"
        if [ -n "$CT_SAVE_VMAP" ]; then
            CT_SAVE_VMAP="$CT_SAVE_VMAP, $dscp_val : jump ct_save_dscp_${dscp_val}"
        else
            CT_SAVE_VMAP="$dscp_val : jump ct_save_dscp_${dscp_val}"
        fi
        i=$((i+1))
    done
}

# Arguments: None (uses global variables populated by setup_interface)
generate_main_nft_file() {
    ## Check if the folder does not exist
    if [ ! -d "/usr/share/nftables.d/ruleset-post" ]; then
        mkdir -p "/usr/share/nftables.d/ruleset-post"
    fi

    local priomap_elements
    priomap_elements="$(get_priomap_elements)"

    # Detect multiwan_nft and generate pre-combined ct mark save chains
    # Generate independent DSCP safe-save chains to preserve upper bits (Mwan3 marks)
    generate_dscp_ct_save

cat << DSCPEOF > /tmp/multiwan_qos_dscptag.nft.tmp

define udpbulkport = {$UDPBULKPORT}
define tcpbulkport = {$TCPBULKPORT}
define vidconfports = {$VIDCONFPORTS}
define realtime4 = {$REALTIME4}
define realtime6 = {$REALTIME6}
define lowpriolan4 = {$LOWPRIOLAN4}
define lowpriolan6 = {$LOWPRIOLAN6}

# Rate definitions removed from here as they are per-interface in qdisc
# define downrate = $DOWNRATE
# define uprate = $UPRATE

# TCP downprio thresholds are now per-interface (inline in rules, not nft defines)

define wan = { $WAN_INTERFACES }


table inet dscptag # forward declaration so the next command always works

delete table inet dscptag # clear all the rules

table inet dscptag {

    map priomap { type dscp : classid ;
        elements =  {$priomap_elements}
    }

# Create sets first
${SETS}

    set xfst4ack { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }

    set fast4ack { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }
    set med4ack { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }
    set slow4ack { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }
    set udp_meter { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }
    set slowtcp { typeof ct id . ct direction
        flags dynamic;
        size 65536;
        timeout 5m
    }

    chain drop995 {
    numgen random mod 1000 ge 995 return
    drop
    }
    chain drop95 {
    numgen random mod 1000 ge 950 return
    drop
    }
    chain drop50 {
    numgen random mod 1000 ge 500 return
    drop
    }

    chain mark_500ms {
        ip dscp < cs4 ip dscp != cs1 ip dscp set cs0 counter return
        ip6 dscp < cs4 ip6 dscp != cs1 ip6 dscp set cs0 counter
    }
    chain mark_10s {
        ip dscp < cs4 ip dscp set cs1 counter return
        ip6 dscp < cs4 ip6 dscp set cs1 counter
    }

    chain mark_cs0 {
        ip dscp set cs0 return
        ip6 dscp set cs0
    }
    chain mark_cs1 {
        ip dscp set cs1 return
        ip6 dscp set cs1
    }
    chain mark_af42 {
        ip dscp set af42 return
        ip6 dscp set af42
    }
$AGENT_CHAIN
    chain dscptag {
        type filter hook $NFT_HOOK priority $NFT_PRIORITY; policy accept;

        iif "lo" accept    
        $(if [ "$WASHDSCPDOWN" -eq 1 ] 2>/dev/null; then
            echo "# wash all the DSCP on ingress (packets from WAN) ... "
            echo "        meta iifname \$wan counter jump mark_cs0"
          fi
        )
        $(if [ "$WASHDSCPLAN" -eq 1 ] 2>/dev/null; then
            echo "# wash all DSCP from LAN devices (prevents self-tagging as EF) ... "
            echo "        meta iifname != \$wan meta iif != lo counter jump mark_cs0"
          fi
        )
        
        # Skip rule processing for ingress packets since they're already classified by tc-ctinfo
        # MOVED: Process rules first, then store in conntrack, then accept

        $NFT_TCPMSS_RULES

        $udpbulkport_rules

        $tcpbulkport_rules

        $NFT_ACK_RULES

        $vidconfports_rules

        $realtime4_rules

        $realtime6_rules

        $lowpriolan4_rules

        $lowpriolan6_rules

        $NFT_UDP_RATE_RULES
        
        # TCP down-prioritization (per-interface byte thresholds)
        $NFT_DOWNPRIO_RULES

        $NFT_TCP_UPGRADE_RULES
        
        # --- user inline rules begin ---
        $INLINE_INCLUDE
        # --- user inline rules end   ---
        
${DYNAMIC_RULES}
$AGENT_JUMP

        ## classify for the HFSC queues:
        meta priority set ip dscp map @priomap counter
        meta priority set ip6 dscp map @priomap counter

        # Skip multicast/IPTV - no ct mark save needed
        # IPTV enters on eth1 (not PPPoE), so iifname \$wan doesn't catch it
        ip daddr 224.0.0.0/4 return
        ip6 daddr ff00::/8 return

        # For INGRESS (WANâ†’LAN): skip ct mark save and return early
        # Ingress DSCP is washed, so we don't want to overwrite the correct egress-saved value
        # Also allows multiwan_nft_forward at priority 1 to run
        $(if [ "$WASHDSCPDOWNDELIVERY" -eq 1 ] 2>/dev/null; then
            echo "# wash DSCP before delivery to LAN (ensures clean CS0 packets reach LAN devices)"
            echo "        meta iifname \$wan counter jump mark_cs0"
          fi
        )
        meta iifname \$wan return

        # Store DSCP in conntrack ONLY for EGRESS (LANâ†’WAN) traffic
        # multiwan_qos uses lower 8 bits, multiwan_nft uses upper bits (MMX_MASK)
        # Securely store DSCP (+0x80 MultiWAN QoS marker) in conntrack for EGRESS traffic.
        # This uses the vmap to bitwise-OR the value into the lower 8 bits of ct_mark,
        # fully preserving any Mwan3 routing decisions in the upper 24 bits!
        # Gate the entire vmap on the MultiWAN QoS statemask bit (0x80).
        # (Optimization removed: gating on 0x80 == 0 broke dynamic DSCP updates
        # by the PC agent for established connections, as the updated DSCP was
        # never re-saved to conntrack. The target chains are still idempotent).
        ip dscp vmap { $CT_SAVE_VMAP }
        ip6 dscp vmap { $CT_SAVE_VMAP }

        $(if [ "$WASHDSCPUP" -eq 1 ] 2>/dev/null; then
            echo "# wash all DSCP on egress ... "
            echo "meta oifname \$wan jump mark_cs0"
          fi
        )
    }

$(generate_ratelimit_rules)

$CT_SAVE_CHAINS
}
DSCPEOF

    local validate_log="/tmp/multiwan_qos_dscptag_validate.log"
    if nft -c -f /tmp/multiwan_qos_dscptag.nft.tmp >"$validate_log" 2>&1; then
        mv /tmp/multiwan_qos_dscptag.nft.tmp /usr/share/nftables.d/ruleset-post/dscptag.nft
        rm -f "$validate_log"
        return 0
    fi

    if [ "$AGENT_ENABLED" = "1" ] && [ -z "$MULTIWAN_QOS_AGENT_NFT_FALLBACK" ]; then
        log_msg -warn "Agent-enabled nftables validation failed. Retrying without PC Agent chain for this run."
        MULTIWAN_QOS_AGENT_NFT_FALLBACK=1
        AGENT_CHAIN=""
        AGENT_JUMP=""
        generate_main_nft_file
        return $?
    fi

    error_out "Generated nftables rules failed validation. Existing active rules were not overwritten."
    if [ -s "$validate_log" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && log_msg -warn "nft validation: $line"
        done < "$validate_log"
    fi
    rm -f /tmp/multiwan_qos_dscptag.nft.tmp "$validate_log"
    return 1
}


# Info output block removed: it referenced stale single-WAN rate globals.
# Per-interface info, including optional realtime overrides, is now printed in
# setup_interface() instead.


##############################
#       QoS Setup Functions
##############################

# 1 - device
# 2 - class enum
# 3 - family (ipv4|ipv6)
add_tc_filter() {
    local class_id dsfield hex_match proto prio match_str \
        dev="$1" \
        class_enum="$2" \
        family="$3"

    case "$class_enum" in
        cs0|CS0) class_id=1:13 dsfield=0x00 hex_match=0x0000 ;; # 0 -> Default
        ef|EF) class_id=1:11 dsfield=0xb8 hex_match=0x0B80 ;; # 46
        cs1|CS1) class_id=1:15 dsfield=0x20 hex_match=0x0200 ;; # 8
        cs2|CS2) class_id=1:14 dsfield=0x40 hex_match=0x0400 ;; # 16
        cs4|CS4) class_id=1:12 dsfield=0x80 hex_match=0x0800 ;; # 32
        cs5|CS5) class_id=1:11 dsfield=0xa0 hex_match=0x0A00 ;; # 40
        cs6|CS6) class_id=1:11 dsfield=0xc0 hex_match=0x0C00 ;; # 48
        cs7|CS7) class_id=1:11 dsfield=0xe0 hex_match=0x0E00 ;; # 56
        af11|AF11) class_id=1:14 dsfield=0x28 hex_match=0x0280 ;; # 10
        af41|AF41) class_id=1:12 dsfield=0x88 hex_match=0x0880 ;; # 34
        af42|AF42) class_id=1:12 dsfield=0x90 hex_match=0x0900 ;; # 36
        *)
            log_msg -err "add_tc_filter: unsupported DSCP class '$class_enum'. Skipping."
            return 1
    esac

    case "$family" in
        ipv4)
            # Match DSCP in TOS field (IPv4 Byte 1)
            # DSCP is upper 6 bits of TOS. 
            # 0x00FC0000 at offset 0 matches bits 8-15 (Byte 1)
            proto=ip prio=10 
            # Strip 0x and pad/concatenate
            local raw_hex="${dsfield#0x}"
            val_hex="00${raw_hex}0000"
            match_str="u32 0x$val_hex 0x00fc0000 at 0"
            ;;
        ipv6)
            # Match DSCP in Traffic Class field (IPv6 Bits 4-11)
            # Let's use the proven user strings from Turn 9
            proto=ipv6 prio=11
            case "$class_enum" in
                ef|EF) val_hex="0b800000" ;;
                cs5|CS5) val_hex="0a000000" ;;
                cs6|CS6) val_hex="0c000000" ;;
                cs7|CS7) val_hex="0e000000" ;;
                cs4|CS4) val_hex="08000000" ;;
                af41|AF41) val_hex="08800000" ;;
                af42|AF42) val_hex="09000000" ;;
                cs2|CS2) val_hex="04000000" ;;
                af11|AF11) val_hex="02800000" ;;
                cs1|CS1) val_hex="02000000" ;;
                cs0|CS0) val_hex="00000000" ;;
            esac
            match_str="u32 0x$val_hex 0x0fc00000 at 0"
            ;;
    esac

    # shellcheck disable=SC2086
    tc filter add dev "$dev" parent 1: protocol "$proto" prio "$prio" u32 match $match_str classid "$class_id"
}

# Function to setup the specific game qdisc (pfifo, red, fq_codel, netem, etc.)
# Arguments: $1:DEV, $2:RATE, $3:GAMERATE, $4:QDISC_TYPE, $5:DIR, $6:MTU, ... HFSC params ...
setup_game_qdisc() {
    local DEV="$1" RATE="$2" GAMERATE="$3" QDISC_TYPE="$4" DIR="$5" MTU="$6"
    local MAXDEL="$7" PFIFOMIN="$8" PACKETSIZE="$9"
    local netemdelayms="${10}" netemjitterms="${11}" netemdist="${12}" NETEM_DIRECTION="${13}" pktlossp="${14}"

    # Ensure rates/packetsize are non-zero to avoid errors in calculations
    [ "$RATE" -le 0 ] && RATE=1
    [ "$GAMERATE" -le 0 ] && GAMERATE=1
    [ "$PACKETSIZE" -le 0 ] && PACKETSIZE=1

    local BFIFO_BURST_CAP_BYTES=3000
    local PFIFO_MIN_PACKETS=12
    local NETEM_MIN_PACKETS=12

    local target_bytes=$((MAXDEL * GAMERATE / 8))
    [ "$target_bytes" -lt 1 ] && target_bytes=1

    local burst_floor_bytes="$target_bytes"
    [ "$burst_floor_bytes" -gt "$BFIFO_BURST_CAP_BYTES" ] && burst_floor_bytes="$BFIFO_BURST_CAP_BYTES"

    local bfifo_limit="$target_bytes"
    [ "$bfifo_limit" -lt "$burst_floor_bytes" ] && bfifo_limit="$burst_floor_bytes"

    local pfifo_limit=$((PFIFOMIN + MAXDEL * GAMERATE / 8 / PACKETSIZE))
    local pfifo_delay_cap="$pfifo_limit"
    [ "$pfifo_limit" -lt "$PFIFO_MIN_PACKETS" ] && pfifo_limit=$PFIFO_MIN_PACKETS
    [ "$pfifo_limit" -gt "$pfifo_delay_cap" ] && pfifo_limit="$pfifo_delay_cap"

    local netem_limit=$((4 + 9 * GAMERATE / 8 / 500))
    local netem_delay_cap=$((target_bytes / 500))
    [ "$netem_delay_cap" -lt 1 ] && netem_delay_cap=1
    [ "$netem_limit" -lt "$NETEM_MIN_PACKETS" ] && netem_limit=$NETEM_MIN_PACKETS
    [ "$netem_limit" -gt "$netem_delay_cap" ] && netem_limit="$netem_delay_cap"

    # Calculate RED thresholds from the same stale-packet delay budget as BFIFO.
    local REDMAX="$target_bytes"
    local REDMIN=$((REDMAX / 3))
    [ "$REDMIN" -lt 1 ] && REDMIN=1
    # Calculate BURST: (min + min + max)/(3 * avpkt) as per RED documentation
    local BURST=$(( (REDMIN + REDMIN + REDMAX) / (3 * 500) )); [ "$BURST" -lt 2 ] && BURST=2

    # for fq_codel
    local INTVL=$((100+2*1500*8/GAMERATE))
    local TARG=$((540*8/GAMERATE+4))

    # Delete previous qdisc on this handle if it exists (optional, but good practice)
    tc qdisc del dev "$DEV" parent 1:11 handle 10: > /dev/null 2>&1

    case $QDISC_TYPE in
        "drr")
            tc qdisc add dev "$DEV" parent 1:11 handle 10: drr
            tc class add dev "$DEV" parent 10: classid 10:1 drr quantum 8000
            tc qdisc add dev "$DEV" parent 10:1 handle 11: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
            tc class add dev "$DEV" parent 10: classid 10:2 drr quantum 4000
            tc qdisc add dev "$DEV" parent 10:2 handle 12: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
            tc class add dev "$DEV" parent 10: classid 10:3 drr quantum 1000
            tc qdisc add dev "$DEV" parent 10:3 handle 13: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
        ;;
        "qfq")
            tc qdisc add dev "$DEV" parent 1:11 handle 10: qfq
            tc class add dev "$DEV" parent 10: classid 10:1 qfq weight 8000
            tc qdisc add dev "$DEV" parent 10:1 handle 11: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
            tc class add dev "$DEV" parent 10: classid 10:2 qfq weight 4000
            tc qdisc add dev "$DEV" parent 10:2 handle 12: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
            tc class add dev "$DEV" parent 10: classid 10:3 qfq weight 1000
            tc qdisc add dev "$DEV" parent 10:3 handle 13: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" probability 1.0 burst $BURST
        ;;
        "pfifo")
            tc qdisc add dev "$DEV" parent 1:11 handle 10: pfifo limit "$pfifo_limit"
        ;;
        "bfifo")
            tc qdisc add dev "$DEV" parent 1:11 handle 10: bfifo limit "$bfifo_limit"
            #tc qdisc add dev "$DEV" parent 1:11 handle 10: bfifo limit $((MAXDEL * RATE / 8))
        ;;
        "red")
            tc qdisc add dev "$DEV" parent 1:11 handle 10: red limit 150000 min $REDMIN max $REDMAX avpkt 500 bandwidth "${GAMERATE}kbit" burst $BURST probability 1.0
            ## send game packets to 10:, they're all treated the same
        ;;
        "fq_codel")
            tc qdisc add dev "$DEV" parent "1:11" handle 10: fq_codel memory_limit "$(fq_codel_memory_limit "$GAMERATE")" interval "${INTVL}ms" target "${TARG}ms" quantum $((MTU * 2))
        ;;
        "netem")
            # Only apply NETEM if this direction is enabled
            if [ "$NETEM_DIRECTION" = "both" ] || \
               { [ "$NETEM_DIRECTION" = "egress" ] && [ "$DIR" = "wan" ]; } || \
               { [ "$NETEM_DIRECTION" = "ingress" ] && [ "$DIR" = "lan" ]; }; then
                
                # Build netem arguments as positional params instead of eval (#9)
                local netem_args="limit $netem_limit"
                
                # If jitter is set but delay is 0, force minimum delay of 1ms
                if [ "$netemjitterms" -ne 0 ] && [ "$netemdelayms" -eq 0 ]; then
                    netemdelayms=1
                fi

                # Add delay parameter if set (either original or forced minimum)
                if [ "$netemdelayms" -ne 0 ]; then
                    netem_args="$netem_args delay ${netemdelayms}ms"
                    
                    # Add jitter if set
                    if [ "$netemjitterms" -ne 0 ]; then
                        netem_args="$netem_args ${netemjitterms}ms"
                        netem_args="$netem_args distribution $netemdist"
                    fi
                fi
                
                # Add packet loss if set
                if [ "$pktlossp" != "none" ] && [ -n "$pktlossp" ]; then
                    netem_args="$netem_args loss $pktlossp"
                fi
                
                # shellcheck disable=SC2086
                tc qdisc add dev "$DEV" parent 1:11 handle 10: netem $netem_args
            else
                # Use pfifo as fallback when NETEM is not applied in this direction
                tc qdisc add dev "$DEV" parent 1:11 handle 10: pfifo limit "$pfifo_limit"
            fi
        ;;
        *)
            print_msg -err "Unsupported game qdisc type '$QDISC_TYPE'. Using pfifo fallback."
            # pfifo fallback limit calculation
            tc qdisc add dev "$DEV" parent 1:11 handle 10: pfifo limit "$pfifo_limit"
        ;;
    esac
}

# Function to setup HFSC qdisc structure
# Arguments: $1:DEV, $2:RATE, $3:GAMERATE, $4:GAME_QDISC_TYPE, $5:DIR, $6:PRESET, $7:OVERHEAD, $8:MTU, $9:MPU
setup_hfsc() {
    local DEV="$1" RATE="$2" GAMERATE="$3" GAME_QDISC_TYPE="$4" DIR="$5" PRESET="$6" OVERHEAD="$7"
    local MTU="${8:-1500}"
    local MPU="$9"

    tc qdisc del dev "$DEV" root > /dev/null 2>&1

    # Get overhead parameters from CAKE configuration
    local TC_OH_PARAMS
    TC_OH_PARAMS=$(get_tc_overhead_params "$PRESET" "$OVERHEAD" "$MPU")
    
    # Apply STAB on upload roots, and on download IFB roots only when enabled.
    if should_apply_root_stab "$DIR"; then
        # shellcheck disable=SC2086
        tc qdisc replace dev "$DEV" handle 1: root ${TC_OH_PARAMS} hfsc default 13
    else
        tc qdisc replace dev "$DEV" handle 1: root hfsc default 13
    fi

    # DUR calculation
    local DUR=$((5*MTU*8/RATE)); [ "$DUR" -lt 25 ] && DUR=25

    # Main link class
    tc class add dev "$DEV" parent 1: classid 1:1 hfsc ls m2 "${RATE}kbit" ul m2 "${RATE}kbit"
    # gameburst calculation
    local gameburst=$((GAMERATE*10)); [ "$gameburst" -gt $((RATE*97/100)) ] && gameburst=$((RATE*97/100));

    # Define HFSC Classes
    tc class add dev "$DEV" parent 1:1 classid 1:11 hfsc rt m1 "${gameburst}kbit" d "${DUR}ms" m2 "${GAMERATE}kbit" # Realtime
    tc class add dev "$DEV" parent 1:1 classid 1:12 hfsc ls m1 "$((RATE*70/100))kbit" d "${DUR}ms" m2 "$((RATE*30/100))kbit" # Fast
    tc class add dev "$DEV" parent 1:1 classid 1:13 hfsc ls m1 "$((RATE*20/100))kbit" d "${DUR}ms" m2 "$((RATE*45/100))kbit" # Normal (Default)
    tc class add dev "$DEV" parent 1:1 classid 1:14 hfsc ls m1 "$((RATE*7/100))kbit" d "${DUR}ms" m2 "$((RATE*15/100))kbit"  # Low Prio
    tc class add dev "$DEV" parent 1:1 classid 1:15 hfsc ls m1 "$((RATE*3/100))kbit" d "${DUR}ms" m2 "$((RATE*10/100))kbit"  # Bulk

    # Attach Qdiscs
    setup_game_qdisc "$DEV" "$RATE" "$GAMERATE" "$GAME_QDISC_TYPE" "$DIR" \
                     "$MTU" "$MAXDEL" "$PFIFOMIN" "$PACKETSIZE" \
                     "$netemdelayms" "$netemjitterms" "$netemdist" "$NETEM_DIRECTION" "$pktlossp"

    # Attach non-game qdiscs
    local INTVL=$((100+2*MTU*8/RATE))
    local TARG=$((540*8/RATE+4))
    for i in 12 13 14 15; do 
        if [ "$nongameqdisc" = "cake" ]; then
            tc qdisc add dev "$DEV" parent "1:$i" cake $nongameqdiscoptions
        elif [ "$nongameqdisc" = "fq_codel" ]; then
            tc qdisc add dev "$DEV" parent "1:$i" fq_codel memory_limit "$(fq_codel_memory_limit "$RATE")" interval "${INTVL}ms" target "${TARG}ms" quantum $((MTU * 2))
        else
            print_msg -err "Unsupported qdisc for non-game traffic: $nongameqdisc"
            exit 1
        fi
    done

    # Apply DSCP Filters (on ingress always, on egress only when SFO active)
    # Ingress always needs filters, egress needs them only with SFO
    # Without SFO: nftables priomap handles egress classification
    # With SFO: nftables bypassed, tc filters needed for classification
    if [ "$DIR" = "lan" ] || [ "$SFO_ENABLED" = "1" ]; then
        # Delete existing filters first
        tc filter del dev "$DEV" parent 1: prio 10 > /dev/null 2>&1
        tc filter del dev "$DEV" parent 1: prio 11 > /dev/null 2>&1

        local family class_enum
        for family in ipv4 ipv6; do
            for class_enum in ef cs5 cs6 cs7 cs4 af41 af42 cs2 af11 cs1 cs0; do
                add_tc_filter "$DEV" "$class_enum" "$family"
            done
        done
    fi
    :
}


qdisc_setup_failed() {
    [ -n "$1" ] && error_out "$1"
    error_out "Failed to set up $ROOT_QDISC."
    # *** Any additional error handling needed? ***
    exit 1
}

# Appends option to ${CAKE_OPTS}
# 1: parameter: nat|wash|ack_filter|*
# 2: selector (1|0)
#    for wash, nat, ack-filter: selector value '1' translates to prefix '', any other value translates to prefix 'no[-]'
#    for other options: selector value '1' translates to 'don't skip option', any other value translates to 'skip option'
append_cake_opt() {
    [ ${#} = 2 ] || { error_out "append_cake_opt: invalid args '$*'."; return 1; }
    local prefix='' \
        param="$1" selector="$2"
    [ -n "$param" ] || return 0
    [ "$selector" != 1 ] &&
        case "$param" in
            wash|nat) prefix='no' ;;
            ack-filter) prefix='no-' ;;
            *) return 0 ;;
        esac
    CAKE_OPTS="${CAKE_OPTS} ${prefix}${param}"
    :
}

# Function to setup CAKE qdisc
# Arguments: $1:WAN_DEV, $2:LAN_DEV, $3:UPRATE, $4:DOWNRATE, $5:PRESET, $6:OVERHEAD, $7:MPU
setup_cake() {
    local WAN="$1" LAN="$2" UPRATE="$3" DOWNRATE="$4" PRESET="$5" OVERHEAD="$6" MPU="$7"

    tc qdisc del dev "$WAN" root > /dev/null 2>&1
    tc qdisc del dev "$LAN" root > /dev/null 2>&1
    
    # Get CAKE link parameters
    local ack_filter_egress_val cake_link_params="$(get_cake_link_params "$PRESET" "$OVERHEAD" "$MPU")"

    # Egress (Upload) CAKE setup
    case "$ACK_FILTER_EGRESS" in
        auto) ack_filter_egress_val=$(( (DOWNRATE / UPRATE) >= 15 )) ;;
        *[!0-9]*|'') qdisc_setup_failed "Invalid value '$ACK_FILTER_EGRESS' for ACK_FILTER_EGRESS." ;;
        *) ack_filter_egress_val=$ACK_FILTER_EGRESS ;;
    esac

    local CAKE_OPTS="bandwidth ${UPRATE}kbit"
    # shellcheck disable=SC2086
    append_cake_opt "$PRIORITY_QUEUE_EGRESS" "1" &&
    append_cake_opt "dual-srchost" "$HOST_ISOLATION" &&
    append_cake_opt "rtt ${RTT}ms" "${RTT:+1}" &&
    append_cake_opt "$cake_link_params" "1" &&
    append_cake_opt "$LINK_COMPENSATION" "1" &&
    append_cake_opt "$EXTRA_PARAMETERS_EGRESS" "1" &&
    append_cake_opt "nat" "$NAT_EGRESS" &&
    append_cake_opt "wash" "$WASHDSCPUP" &&
    append_cake_opt "ack-filter" "$ack_filter_egress_val" &&
    append_cake_opt "memlimit 16m" "1" &&
    tc qdisc add dev "$WAN" root handle 1: cake $CAKE_OPTS || qdisc_setup_failed
debug_log "EGRESS cake opts: '$CAKE_OPTS'"
    

    # Ingress (Download) CAKE setup
    CAKE_OPTS="bandwidth ${DOWNRATE}kbit ingress"
    # shellcheck disable=SC2086
    append_cake_opt "autorate-ingress" "$AUTORATE_INGRESS" &&
    append_cake_opt "$PRIORITY_QUEUE_INGRESS" "1" &&
    append_cake_opt "dual-dsthost" "$HOST_ISOLATION" &&
    append_cake_opt "rtt ${RTT}ms" "${RTT:+1}" &&
    append_cake_opt "$cake_link_params" "1" &&
    append_cake_opt "$LINK_COMPENSATION" "1" &&
    append_cake_opt "$EXTRA_PARAMETERS_INGRESS" "1" &&
    append_cake_opt "nat" "$NAT_INGRESS" &&
    append_cake_opt "wash" "$WASHDSCPDOWN" &&
    append_cake_opt "memlimit 16m" "1" &&
    tc qdisc add dev "$LAN" root cake $CAKE_OPTS || qdisc_setup_failed
debug_log "INGRESS cake opts: '$CAKE_OPTS'"
}

# Helper function to set up hybrid qdisc on an interface
# Arguments: $1:DEV, $2:RATE, $3:GAMERATE, $4:DIR, $5:PRESET, $6:OVERHEAD, $7:MPU, $8:MTU
setup_hybrid() {
    local DEV="$1" RATE="$2" GAMERATE="$3" DIR="$4" PRESET="$5" OVERHEAD="$6" MPU="$7"
    local MTU="${8:-1500}"

    # Calculate parameters
    local DUR=$((5*MTU*8/RATE)); [ "$DUR" -lt 25 ] && DUR=25
    local gameburst=$((GAMERATE*10)); [ "$gameburst" -gt $((RATE*97/100)) ] && gameburst=$((RATE*97/100));

    # Setup root HFSC qdisc (default to 1:13 - CAKE class)
    local TC_OH_PARAMS
    TC_OH_PARAMS=$(get_tc_overhead_params "$PRESET" "$OVERHEAD" "$MPU")
    
    # Ensure previous root is deleted before replacing
    tc qdisc del dev "$DEV" root > /dev/null 2>&1
    # Apply STAB on upload roots, and on download IFB roots only when enabled.
    if should_apply_root_stab "$DIR"; then
        # shellcheck disable=SC2086
        tc qdisc replace dev "$DEV" handle 1: root ${TC_OH_PARAMS} hfsc default 13
    else
        tc qdisc replace dev "$DEV" handle 1: root hfsc default 13
    fi

    # Main link class
    tc class add dev "$DEV" parent 1: classid 1:1 hfsc ls m2 "${RATE}kbit" ul m2 "${RATE}kbit"

    # Class 1:11 - High priority realtime (HFSC RT + gameqdisc)
    tc class add dev "$DEV" parent 1:1 classid 1:11 hfsc rt m1 "${gameburst}kbit" d "${DUR}ms" m2 "${GAMERATE}kbit"
    # Attach game qdisc (using $gameqdisc from HFSC config)
    setup_game_qdisc "$DEV" "$RATE" "$GAMERATE" "$gameqdisc" "$DIR" \
                     "$MTU" "$MAXDEL" "$PFIFOMIN" "$PACKETSIZE" \
                     "$netemdelayms" "$netemjitterms" "$netemdist" "$NETEM_DIRECTION" "$pktlossp"

    # Class 1:13 - CAKE class (most traffic - default)
    local cake_rate=$((RATE - GAMERATE)); [ "$cake_rate" -le 0 ] && cake_rate=1
    local cake_shaper_rate="$(calculate_cake_shaper_rate "$cake_rate")"
    tc class add dev "$DEV" parent 1:1 classid 1:13 hfsc ls m1 "${cake_rate}kbit" d "${DUR}ms" m2 "${cake_rate}kbit"

    # Attach CAKE qdisc - use "hybrid" mode to match HFSC overhead
    local cake_link_params="$(get_cake_link_params "$PRESET" "$OVERHEAD" "$MPU" "hybrid")"
    local CAKE_OPTS=""
    tc qdisc del dev "$DEV" parent 1:13 handle 13: > /dev/null 2>&1
    
    # shellcheck disable=SC2086
    if [ "$DIR" = "wan" ]; then
        CAKE_OPTS="bandwidth ${cake_shaper_rate}kbit besteffort" # Leave headroom under the HFSC child class.
        append_cake_opt "dual-srchost" "$HOST_ISOLATION" &&
        append_cake_opt "$EXTRA_PARAMETERS_EGRESS" "1" &&
        append_cake_opt "nat" "$NAT_EGRESS" &&
        append_cake_opt "wash" "$WASHDSCPUP"
    else # lan (ingress)
        CAKE_OPTS="bandwidth ${cake_shaper_rate}kbit besteffort ingress" # Leave headroom under the HFSC child class.
        append_cake_opt "dual-dsthost" "$HOST_ISOLATION" &&
        append_cake_opt "$EXTRA_PARAMETERS_INGRESS" "1" &&
        append_cake_opt "nat" "$NAT_INGRESS" &&
        append_cake_opt "wash" "$WASHDSCPDOWN"
    fi &&
    append_cake_opt "rtt ${RTT}ms" "${RTT:+1}" &&
    append_cake_opt "$cake_link_params" "1" &&
    append_cake_opt "$LINK_COMPENSATION" "1" &&
    append_cake_opt "memlimit 16m" "1" &&
    tc qdisc replace dev "$DEV" parent 1:13 handle 13: cake $CAKE_OPTS || qdisc_setup_failed
debug_log "$DIR HYBRID cake opts: '$CAKE_OPTS'"

    # Class 1:15 - Bulk traffic (HFSC LS + fq_codel)
    # Use HFSC limits: m1 3%, m2 10%
    local bulk_rate_m1=$((RATE*3/100)); [ "$bulk_rate_m1" -le 0 ] && bulk_rate_m1=1
    local bulk_rate_m2=$((RATE*10/100)); [ "$bulk_rate_m2" -le 0 ] && bulk_rate_m2=1
    tc class add dev "$DEV" parent 1:1 classid 1:15 hfsc ls m1 "${bulk_rate_m1}kbit" d "${DUR}ms" m2 "${bulk_rate_m2}kbit"
    # Attach fq_codel (using calculations and options from HFSC config)
    local INTVL=$((100+2*MTU*8/RATE))
    local TARG=$((540*8/RATE+4))
    tc qdisc del dev "$DEV" parent 1:15 handle 15: > /dev/null 2>&1
    tc qdisc replace dev "$DEV" parent 1:15 handle 15: fq_codel memory_limit "$(fq_codel_memory_limit "$RATE")" interval "${INTVL}ms" target "${TARG}ms" quantum $((MTU * 2))

    # Apply DSCP Filters (on ingress always, on egress only when SFO active)
    if [ "$DIR" = "lan" ] || [ "$SFO_ENABLED" = "1" ]; then
        # Delete existing filters
        tc filter del dev "$DEV" parent 1: prio 10 > /dev/null 2>&1
        tc filter del dev "$DEV" parent 1: prio 11 > /dev/null 2>&1

        local class_enum

        # IPv4 Filters (prio 10)
        # EF, CS5, CS6, CS7 -> Realtime
        # CS1 -> Bulk
        for class_enum in ef cs5 cs6 cs7 cs1; do
            add_tc_filter "$DEV" "$class_enum" "ipv4"
        done
        # Default rule sends to 1:13 (CAKE)

        # IPv6 Filters (prio 11)
        for class_enum in ef cs5 cs6 cs7 cs1 cs0; do
            add_tc_filter "$DEV" "$class_enum" "ipv6"
        done
    fi
}

# Helper functions for HTB dynamic parameter calculation
# Calculate optimal HTB quantum based on rate
# Args: $1=rate, $2=duration_us (default 1000), $3=link_preset (for ATM detection), $4=MTU
calculate_htb_quantum() {
    local rate="$1"
    local duration_us="${2:-1000}"  # Default 1ms = 1000Âµs
    local link_preset="$3"
    local MTU="${4:-1500}"
    
    # Duration-based calculation (SQM-style)
    # rate in kbit/s, duration in Âµs, result in bytes
    local quantum=$(((duration_us * rate) / 8000))
    
    # ATM-aware minimum
    case "$link_preset" in
        *atm*|*adsl*|*pppoa*|*pppoe*|*bridged*|*ipoa*|conservative)
            local min_quantum=$(((MTU + 48 + 47) / 48 * 53))
            [ "$quantum" -lt "$min_quantum" ] && quantum=$min_quantum
            ;;
        *)
            [ "$quantum" -lt "$MTU" ] && quantum=$MTU
            ;;
    esac
    
    # Maximum reasonable quantum (200KB)
    [ "$quantum" -gt 200000 ] && quantum=200000
    
    echo $quantum
}

# Calculate HTB burst size based on rate and target latency
# Args: $1=rate, $2=duration_us (default 10000), $3=MTU
calculate_htb_burst() {
    local rate="$1"
    local duration_us="${2:-10000}"  # Default 10ms = 10000Âµs
    local min_burst="${3:-1500}"
    
    # burst in bytes for given duration
    local burst=$(((duration_us * rate) / 8000))
    
    # Minimum burst should be at least 1 MTU
    [ "$burst" -lt "$min_burst" ] && burst=$min_burst
    
    echo $burst
}

# Calculate the realtime/game lane as a fixed small reserve. HFSC/HTB priority
# handles latency; this rate only needs to cover game/voice traffic plus modest
# overhead, with a slow-link cap to avoid consuming tiny connections.
calculate_realtime_rate() {
    local rate="$1" dir="$2" realtime cap

    [ "$rate" -gt 0 ] 2>/dev/null || rate=1

    realtime=1300

    # On very slow links, do not let the realtime lane consume the connection.
    cap=$((rate * 25 / 100))
    [ "$cap" -lt 1 ] && cap=1
    [ "$realtime" -gt "$cap" ] && realtime=$cap

    echo "$realtime"
}

calculate_cake_shaper_rate() {
    local rate="$1" shaper
    [ "$rate" -gt 0 ] 2>/dev/null || rate=1
    shaper=$((rate * 95 / 100))
    [ "$shaper" -lt 1 ] && shaper=1
    echo "$shaper"
}

# Function to setup HTB qdisc (simple.qos style with 3 classes)
# Arguments: $1:DEV, $2:RATE, $3:DIR, $4:PRESET, $5:OVERHEAD, $6:MPU, $7:MTU
setup_htb() {
    local DEV="$1" RATE="$2" DIR="$3" PRESET="$4" OVERHEAD="$5" MPU="$6"
    local MTU="${7:-1500}"

    # Ensure rate is valid
    [ "$RATE" -le 0 ] && RATE=1

    # Delete existing qdisc
    tc qdisc del dev "$DEV" root > /dev/null 2>&1

    # Get overhead parameters from CAKE configuration
    local TC_OH_PARAMS
    TC_OH_PARAMS=$(get_tc_overhead_params "$PRESET" "$OVERHEAD" "$MPU")

    # Setup HTB root with default to best effort (class 13).
    # Apply STAB on upload roots, and on download IFB roots only when enabled.
    if should_apply_root_stab "$DIR"; then
        # shellcheck disable=SC2086
        tc qdisc add dev "$DEV" root handle 1: $TC_OH_PARAMS htb default 13
    else
        tc qdisc add dev "$DEV" root handle 1: htb default 13
    fi

    # Calculate HTB quantum for root (all use same quantum)
    local HTB_QUANTUM="$(calculate_htb_quantum "$RATE" 1000 "$PRESET" "$MTU")"

    # Root class gets modest burst since we typically configure 80-90% of physical rate
    # This allows brief bursts into the headroom without causing bufferbloat
    local ROOT_BURST="$(calculate_htb_burst "$RATE" 1000 "$MTU")"   # 1ms burst
    local ROOT_CBURST="$(calculate_htb_burst "$RATE" 1000 "$MTU")"  # 1ms cburst

    # Create main rate limiting class
    tc class add dev "$DEV" parent 1: classid 1:1 htb \
        quantum "$HTB_QUANTUM" \
        rate "${RATE}kbit" ceil "${RATE}kbit" \
        burst "$ROOT_BURST" cburst "$ROOT_CBURST"

    # Realtime/gaming traffic needs a small latency lane, not a large fixed
    # share of the link. Keep this aligned with HFSC/Hybrid.
    local PRIO_RATE_MIN="$(calculate_realtime_rate "$RATE" "$DIR")"

    # Calculate ceiling - ensure it's at least min + some headroom
    local PRIO_CEIL=$((RATE / 3))  # Start with 33%

    # Ensure ceiling is at least min rate + 10%
    local min_ceiling=$((PRIO_RATE_MIN * 110 / 100))
    [ "$PRIO_CEIL" -lt "$min_ceiling" ] && PRIO_CEIL=$min_ceiling

    # Calculate BE and BK rates
    local BE_MIN_RATE=$((RATE / 6))    # 16% guaranteed
    local BK_MIN_RATE=$((RATE / 6))    # 16% guaranteed

    # Adjust if total mins exceed available bandwidth
    local total_min=$((PRIO_RATE_MIN + BE_MIN_RATE + BK_MIN_RATE))
    if [ "$total_min" -gt $((RATE * 90 / 100)) ]; then
        # Scale down proportionally
        BE_MIN_RATE=$((BE_MIN_RATE * RATE * 90 / 100 / total_min))
        BK_MIN_RATE=$((BK_MIN_RATE * RATE * 90 / 100 / total_min))
    fi

    # BE/BK ceiling - almost full rate minus a small reserve
    local BE_CEIL=$((RATE - 16))

    # Calculate individual burst values for each class
    # Priority class burst - based on its own rate
    local PRIO_BURST="$(calculate_htb_burst $PRIO_RATE_MIN 10000 "$MTU")"  # 10ms burst for rate
    local PRIO_CBURST="$(calculate_htb_burst $PRIO_RATE_MIN 5000 "$MTU")"  # 5ms burst for ceiling
    [ "$PRIO_CBURST" -lt "$MTU" ] && PRIO_CBURST=$MTU

    # Priority class (1:11) - for realtime/gaming traffic
    tc class add dev "$DEV" parent 1:1 classid 1:11 htb \
        quantum "$HTB_QUANTUM" \
        rate "${PRIO_RATE_MIN}kbit" ceil "${PRIO_CEIL}kbit" \
        burst "$PRIO_BURST" cburst "$PRIO_CBURST" prio 1

    # Calculate BE burst values - based on its own guaranteed rate
    local BE_BURST="$(calculate_htb_burst $BE_MIN_RATE 10000 "$MTU")"  # 10ms burst for rate
    local BE_CBURST="$(calculate_htb_burst $BE_MIN_RATE 5000 "$MTU")"  # 5ms burst for ceiling
    [ "$BE_CBURST" -lt "$MTU" ] && BE_CBURST=$MTU

    # Best Effort class (1:13) - default traffic
    tc class add dev "$DEV" parent 1:1 classid 1:13 htb \
        quantum "$HTB_QUANTUM" \
        rate "${BE_MIN_RATE}kbit" ceil "${BE_CEIL}kbit" \
        burst "$BE_BURST" cburst "$BE_CBURST" prio 2

    # Calculate BK burst values - based on its own guaranteed rate
    local BK_BURST="$(calculate_htb_burst $BK_MIN_RATE 10000 "$MTU")"  # 10ms burst for rate
    local BK_CBURST="$(calculate_htb_burst $BK_MIN_RATE 5000 "$MTU")"  # 5ms burst for ceiling
    [ "$BK_CBURST" -lt "$MTU" ] && BK_CBURST=$MTU

    # Background/Bulk class (1:15) - low priority
    tc class add dev "$DEV" parent 1:1 classid 1:15 htb \
        quantum "$HTB_QUANTUM" \
        rate "${BK_MIN_RATE}kbit" ceil "${BE_CEIL}kbit" \
        burst "$BK_BURST" cburst "$BK_CBURST" prio 3

    # Attach leaf qdiscs
    # Calculate fq_codel parameters
    local INTVL=$((100+2*MTU*8/RATE))
    local TARG=$((540*8/RATE+4))

    # Priority class gets fq_codel with aggressive settings
    tc qdisc add dev "$DEV" parent 1:11 handle 110: fq_codel \
        interval "${INTVL}ms" target "${TARG}ms" \
        quantum 300

    # Best effort with standard settings
    tc qdisc add dev "$DEV" parent 1:13 handle 130: fq_codel \
        interval "${INTVL}ms" target "${TARG}ms" \
        quantum 1500

    # Background with larger target
    tc qdisc add dev "$DEV" parent 1:15 handle 150: fq_codel \
        interval "$((INTVL*2))ms" target "$((TARG*2))ms" \
        quantum 300

    # Apply DSCP filters (on ingress always, on egress only when SFO active)
    if [ "$DIR" = "lan" ] || [ "$SFO_ENABLED" = "1" ]; then
        # Delete existing filters
        tc filter del dev "$DEV" parent 1: prio 10 > /dev/null 2>&1
        tc filter del dev "$DEV" parent 1: prio 11 > /dev/null 2>&1

        # IPv4 filters (prio 10)
        # Priority class: EF, CS5, CS6, CS7 -> 1:11
        # Background class: CS1 -> 1:15
        for class_enum in ef cs5 cs6 cs7 cs1; do
            add_tc_filter "$DEV" "$class_enum" "ipv4"
        done

        # IPv6 filters (prio 11)
        for class_enum in ef cs5 cs6 cs7 cs1 cs0; do
            add_tc_filter "$DEV" "$class_enum" "ipv6"
        done
    fi
}


# Global accumulation variables
WAN_INTERFACES=""
NFT_TCPMSS_RULES=""
NFT_ACK_RULES=""
NFT_UDP_RATE_RULES=""
NFT_TCP_UPGRADE_RULES=""
NFT_DOWNPRIO_RULES=""

# Setup logic for a single interface
# Parses all custom rules and explicitly attaches them iteratively as native tc flower logic to bypass the IFB redirect firewall bug loop.
apply_tc_custom_ingress_rules() {
    local lan_dev="$1" qdisc="${2:-hfsc}"
    
    process_tc_ingress_rule() {
        local config="$1"
        local enabled name proto class src_port_raw src_ip_raw dest_port_raw dest_ip_raw class_id

        config_get_bool enabled "$config" enabled 1
        [ "$enabled" -eq 0 ] && return 0

        config_get name          "$config" name      ""
        config_get proto         "$config" proto     ""
        config_get class         "$config" class     ""
        config_get src_port_raw  "$config" src_port  ""
        config_get dest_port_raw "$config" dest_port ""
        config_get src_ip_raw    "$config" src_ip    ""
        config_get dest_ip_raw   "$config" dest_ip   ""

        [ -z "$class" ] && return 0
        class_id="$(get_dscp_classid_for_qdisc "$class" "$qdisc")"
        [ -n "$class_id" ] || return 0

        [ -z "$src_port_raw" ] && [ -z "$dest_port_raw" ] && [ -z "$src_ip_raw" ] && [ -z "$dest_ip_raw" ] && return 0
        case "$src_port_raw$dest_port_raw$src_ip_raw$dest_ip_raw" in *'!='*) return 0 ;; esac

        local tc_l4proto=""
        [ "$proto" = "udp" ] && tc_l4proto="ip_proto udp"
        [ "$proto" = "tcp" ] && tc_l4proto="ip_proto tcp"

        # Direction detection:
        # "Out" rules (src_ip set): ports describe upload, swap for download replies
        # "In"  rules (dest_ip set, no src_ip): ports describe download, no swap needed
        local is_inbound=0
        [ -n "$dest_ip_raw" ] && [ -z "$src_ip_raw" ] && is_inbound=1

        local ip_list="${src_ip_raw:-${dest_ip_raw:-any}}"
        
        local ip port_match ip_fam
        for ip in $ip_list; do
            local ip_match="" match_ip_fams="ip ipv6"
            if [ "$ip" != "any" ]; then
                # Skip private LAN IP matching for WAN ingress hooks as they haven't been NAT'd yet.
                case "$ip" in
                    192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) ip_match="" ;;
                    *)
                        if [ "$is_inbound" -eq 1 ]; then
                            ip_match="dst_ip $ip"
                        else
                            ip_match="src_ip $ip"
                        fi
                        ;;
                esac
                # Detect IPv4 vs IPv6 natively via colon check
                if printf '%s' "$ip" | grep -q ':'; then match_ip_fams="ipv6"; else match_ip_fams="ip"; fi
            fi

            for ip_fam in $match_ip_fams; do
                # Determine L4 protocols to match
                local l4_list
                [ -n "$tc_l4proto" ] && l4_list="${tc_l4proto#ip_proto }" || l4_list="udp tcp"

                # Handle port matching
                if [ -n "$src_port_raw" ] || [ -n "$dest_port_raw" ]; then
                    local p_src p_dst
                    for l4 in $l4_list; do
                        for p_src in ${src_port_raw:-"__SKIP__"}; do
                            for p_dst in ${dest_port_raw:-"__SKIP__"}; do
                                local p_match="ip_proto $l4"
                                if [ "$is_inbound" -eq 1 ]; then
                                    # "In" rule: ports already describe download perspective, no swap
                                    [ "$p_src" != "__SKIP__" ] && p_match="$p_match src_port $p_src"
                                    [ "$p_dst" != "__SKIP__" ] && p_match="$p_match dst_port $p_dst"
                                else
                                    # "Out" rule: swap ports for download reply matching
                                    [ "$p_src" != "__SKIP__" ] && p_match="$p_match dst_port $p_src"
                                    [ "$p_dst" != "__SKIP__" ] && p_match="$p_match src_port $p_dst"
                                fi
                                
                                tc filter add dev "$lan_dev" parent 1: prio 1 protocol "$ip_fam" flower $p_match $ip_match classid "$class_id"
                            done
                        done
                    done
                else
                    # No ports, just match IP and/or L4 protocol
                    tc filter add dev "$lan_dev" parent 1: prio 1 protocol "$ip_fam" flower $tc_l4proto $ip_match classid "$class_id"
                fi
            done
        done
    }

    if [ "$global_enabled" = "1" ]; then
        config_foreach process_tc_ingress_rule rule
    fi
}

setup_interface_qdisc_direction() {
    local DEV="$1" RATE="$2" GAMERATE="$3" DIR="$4" ROOT_QDISC="$5" PRESET="$6" OVERHEAD="$7"
    local MTU="${8:-1500}"
    local MPU="$9"

    case "$ROOT_QDISC" in
        hfsc)
            setup_hfsc "$DEV" "$RATE" "$GAMERATE" "$gameqdisc" "$DIR" "$PRESET" "$OVERHEAD" "$MTU" "$MPU"
            ;;
        htb)
            setup_htb "$DEV" "$RATE" "$DIR" "$PRESET" "$OVERHEAD" "$MPU" "$MTU"
            ;;
        hybrid)
            setup_hybrid "$DEV" "$RATE" "$GAMERATE" "$DIR" "$PRESET" "$OVERHEAD" "$MPU" "$MTU"
            ;;
        *)
            setup_hfsc "$DEV" "$RATE" "$GAMERATE" "pfifo" "$DIR" "$PRESET" "$OVERHEAD" "$MTU" "$MPU"
            ;;
    esac
}

cleanup_interface_state() {
    local device="$1" lan_dev="$2"

    # Make interface setup idempotent. Stale ingress filters or IFB state can
    # silently survive a partial restart and blackhole the shaped WAN path.
    tc qdisc del dev "$device" root > /dev/null 2>&1
    tc qdisc del dev "$device" ingress > /dev/null 2>&1

    if ip link show "$lan_dev" > /dev/null 2>&1; then
        tc qdisc del dev "$lan_dev" root > /dev/null 2>&1
        ip link set "$lan_dev" down > /dev/null 2>&1
        ip link del "$lan_dev" > /dev/null 2>&1 || \
            qdisc_setup_failed "Failed to remove stale IFB device $lan_dev."
    fi
}

setup_interface() {
    local config="$1"
    local device download upload qdisc enabled preset overhead ackrate
    config_get device "$config" device
    config_get download "$config" download
    config_get upload "$config" upload
    config_get qdisc "$config" qdisc 'hfsc'
    config_get_bool enabled "$config" enabled 1
    config_get preset "$config" preset 'ethernet'
    config_get overhead "$config" overhead
    config_get mpu "$config" mpu
    config_get ackrate "$config" ackrate

    [ "$enabled" -eq 1 ] && [ -n "$device" ] || return 0

    # Check if device exists in the system (skip if offline)
    if ! ip link show "$device" >/dev/null 2>&1; then
        print_msg "Skipping interface $config - device $device not found (offline?)"
        return 0
    fi

    # Enforce minimum and maximum rate values to prevent divide-by-zero and misconfiguration
    # Max rate: 2.5 Gbps (2500000 kbps) - matches common max port speed
    if [ "$download" -lt 1000 ] 2>/dev/null; then
        log_msg -warn "Interface $config: download rate ($download kbps) below minimum. Setting to 1000 kbps."
        download=1000
    fi
    if [ "$download" -gt 2500000 ] 2>/dev/null; then
        log_msg -warn "Interface $config: download rate ($download kbps) exceeds maximum (2.5 Gbps). Setting to 2500000 kbps."
        download=2500000
    fi
    if [ "$upload" -lt 1000 ] 2>/dev/null; then
        log_msg -warn "Interface $config: upload rate ($upload kbps) below minimum. Setting to 1000 kbps."
        upload=1000
    fi
    if [ "$upload" -gt 2500000 ] 2>/dev/null; then
        log_msg -warn "Interface $config: upload rate ($upload kbps) exceeds maximum (2.5 Gbps). Setting to 2500000 kbps."
        upload=2500000
    fi

    print_msg "Configuring interface $config ($device)..."

    # Add to WAN list for nftables
    WAN_INTERFACES="${WAN_INTERFACES}${WAN_INTERFACES:+, }\"$device\""

    # MSS Clamping Logic per interface
    local mss_rules=""
    if [ "$upload" -lt 3000 ] && [ "$upload" -gt 0 ]; then
        local safe_mss="$MSS"
        [ "$safe_mss" -gt 1500 ] 2>/dev/null && safe_mss=1500
        [ "$safe_mss" -lt 536 ] 2>/dev/null && safe_mss=536
        mss_rules="${mss_rules}meta oifname \"$device\" tcp flags syn tcp option maxseg size set $safe_mss counter; "
    fi
    if [ "$download" -lt 3000 ] && [ "$download" -gt 0 ]; then
         local safe_mss="$MSS"
         [ "$safe_mss" -gt 1500 ] 2>/dev/null && safe_mss=1500
         [ "$safe_mss" -lt 536 ] 2>/dev/null && safe_mss=536
         mss_rules="${mss_rules}meta iifname \"$device\" tcp flags syn tcp option maxseg size set $safe_mss counter; "
    fi
    NFT_TCPMSS_RULES="$NFT_TCPMSS_RULES $mss_rules"

    # Per-interface ACK rate limiting (per-connection via ct id . ct direction)
    # Default: 5% of upload rate â€” matches upstream recommendation.
    # The formula produces kbit/s Ã— 5% used as pps: numerically appropriate since
    # a TCP flow at X kbit/s generates ~X/24 ACK/s with delayed ACK, and we want
    # to allow a reasonable fraction through per-connection before thinning kicks in.
    #
    # Bounds prevent edge-case problems:
    #   min 50 pps  â€” below this, TCP connections stall on very slow links
    #   max 5000 pps â€” per-connection ACK rates exceed this only in synthetic floods
    # Precedence: per-interface ackrate, legacy/global ACKRATE, then auto 5% of upload.
    # Set either per-interface ackrate or global ACKRATE to 0 to disable ACK thinning.
    if [ -z "$ackrate" ] && [ -n "$ACKRATE" ]; then
        ackrate="$ACKRATE"
    fi

    if [ -z "$ackrate" ]; then
        ackrate=$((upload * 5 / 100))
        [ "$ackrate" -lt 50 ] && ackrate=50
        [ "$ackrate" -gt 5000 ] && ackrate=5000
    fi
    
    if [ "$ackrate" -gt 0 ] 2>/dev/null; then
        # 4-tier stacking cascade (matches upstream multiwan_qos design):
        # slow == med (both at ackrate) -> stacked 50%+50% = 75% effective drop at base threshold
        # fast at 10x -> 95% drop (stacks through med+slow for ~99.4% total)
        # xfst at 100x -> 99.5% drop (ACK flood; stacks for near-100% total)
        # This intentional stacking is the upstream author's design for graduated aggression.
        local slowack=$ackrate
        local medack=$ackrate
        local fastack=$((ackrate * 10))
        local xfstack=$((ackrate * 100))
        
        # Generate per-interface ACK rate rules (match outgoing interface)
        # 'add' keyword matches upstream nftables idiom for dynamic rate-limit sets
        NFT_ACK_RULES="${NFT_ACK_RULES}
        # ACK rate limiting for $device (base:${ackrate} pps -> 75% drop; x10:${fastack} -> 95%; x100:${xfstack} -> 99.5%)
        meta oifname \"$device\" meta length < 100 tcp flags ack add @xfst4ack {ct id . ct direction limit rate over ${xfstack}/second} counter jump drop995
        meta oifname \"$device\" meta length < 100 tcp flags ack add @fast4ack {ct id . ct direction limit rate over ${fastack}/second} counter jump drop95
        meta oifname \"$device\" meta length < 100 tcp flags ack add @med4ack {ct id . ct direction limit rate over ${medack}/second} counter jump drop50
        meta oifname \"$device\" meta length < 100 tcp flags ack add @slow4ack {ct id . ct direction limit rate over ${slowack}/second} counter jump drop50"
        print_msg "  ACK rate limiting: base=${ackrate} pps (75% drop) | x10=${fastack} pps (95%) | x100=${xfstack} pps (99.5%)"
    fi

    # Per-interface UDP rate limiting (if globally enabled)
    # Scale rate based on upload: base 450pps at 10Mbps, scale proportionally
    if [ "$UDP_RATE_LIMIT_ENABLED" -eq 1 ] 2>/dev/null; then
        local udp_rate=$((upload * 450 / 10000))
        [ "$udp_rate" -lt 100 ] && udp_rate=100  # Minimum 100 pps
        [ "$udp_rate" -gt 2000 ] && udp_rate=2000  # Maximum 2000 pps
        
        NFT_UDP_RATE_RULES="${NFT_UDP_RATE_RULES}
        # UDP rate limiting for $device (rate: over ${udp_rate} pps)
        meta oifname \"$device\" meta l4proto udp ip dscp > cs2 update @udp_meter {ct id . ct direction limit rate over ${udp_rate}/second} counter ip dscp set cs0 counter
        meta oifname \"$device\" meta l4proto udp ip6 dscp > cs2 update @udp_meter {ct id . ct direction limit rate over ${udp_rate}/second} counter ip6 dscp set cs0 counter"
    fi

    # Per-interface TCP upgrade for slow connections (if globally enabled)
    # Scale rate based on upload: base 150pps at 10Mbps, scale proportionally
    if [ "$TCP_UPGRADE_ENABLED" -eq 1 ] 2>/dev/null; then
        local tcp_upgrade_rate=$((upload * 150 / 10000))
        [ "$tcp_upgrade_rate" -lt 50 ] && tcp_upgrade_rate=50  # Minimum 50 pps
        [ "$tcp_upgrade_rate" -gt 500 ] && tcp_upgrade_rate=500  # Maximum 500 pps
        
        NFT_TCP_UPGRADE_RULES="${NFT_TCP_UPGRADE_RULES}
        # TCP upgrade for $device (rate: ${tcp_upgrade_rate} pps)
        meta oifname \"$device\" meta l4proto tcp ip dscp != cs1 update @slowtcp {ct id . ct direction limit rate ${tcp_upgrade_rate}/second burst ${tcp_upgrade_rate} packets} ip dscp set af42 counter
        meta oifname \"$device\" meta l4proto tcp ip6 dscp != cs1 update @slowtcp {ct id . ct direction limit rate ${tcp_upgrade_rate}/second burst ${tcp_upgrade_rate} packets} ip6 dscp set af42 counter"
    fi

    # Per-interface TCP down-prioritization (if globally enabled)
    # Compute byte thresholds from this interface's download rate
    if [ "$TCP_DOWNPRIO_INITIAL_ENABLED" -eq 1 ] 2>/dev/null || [ "$TCP_DOWNPRIO_SUSTAINED_ENABLED" -eq 1 ] 2>/dev/null; then
        local first500ms=$((download * 500 / 8))
        local first10s=$((download * 10000 / 8))

        if [ "$TCP_DOWNPRIO_INITIAL_ENABLED" -eq 1 ] 2>/dev/null; then
            NFT_DOWNPRIO_RULES="${NFT_DOWNPRIO_RULES}
        # TCP downprio initial for $device (threshold: ${first500ms} bytes = 500ms at ${download} kbps)
        meta oifname \"$device\" meta l4proto tcp ct bytes < ${first500ms} jump mark_500ms"
        fi

        if [ "$TCP_DOWNPRIO_SUSTAINED_ENABLED" -eq 1 ] 2>/dev/null; then
            NFT_DOWNPRIO_RULES="${NFT_DOWNPRIO_RULES}
        # TCP downprio sustained for $device (threshold: ${first10s} bytes = 10s at ${download} kbps)
        meta oifname \"$device\" meta l4proto tcp ct bytes > ${first10s} jump mark_10s"
        fi
    fi


    # Read device MTU for correct qdisc calculations
    local dev_mtu
    dev_mtu=$(cat "/sys/class/net/$device/mtu" 2>/dev/null)
    [ -z "$dev_mtu" ] || [ "$dev_mtu" -le 0 ] 2>/dev/null && dev_mtu=1500

    # Setup IFB with matching MTU and optional multi-queue for CAKE
    local lan_dev="ifb-$device"
    local ifb_mq_args=""
    cleanup_interface_state "$device" "$lan_dev"
    disable_qos_offloads "$device" "wan"
    disable_configured_extra_offloads

    if [ "$qdisc" = "cake" ]; then
        local wan_tx_queues
        wan_tx_queues=$(find /sys/class/net/"$device"/queues/ -maxdepth 1 -type d -name 'tx-*' 2>/dev/null | wc -l)
        [ "$wan_tx_queues" -gt 1 ] && ifb_mq_args="numtxqueues $wan_tx_queues"
    fi
    tc qdisc add dev "$device" handle ffff: ingress || \
        qdisc_setup_failed "Failed to create ingress qdisc on $device."

    # shellcheck disable=SC2086  # ifb_mq_args needs word splitting
    ip link add name "$lan_dev" $ifb_mq_args type ifb || \
        qdisc_setup_failed "Failed to create IFB device $lan_dev."
    ip link set "$lan_dev" mtu "$dev_mtu" || \
        qdisc_setup_failed "Failed to set MTU $dev_mtu on $lan_dev."
    ip link set "$lan_dev" up || \
        qdisc_setup_failed "Failed to bring up IFB device $lan_dev."

    # Disable segmentation/aggregation offloads for proper per-packet QoS scheduling.
    disable_qos_offloads "$lan_dev" "ifb"

    # 1. Automatic Restoration (Priority 1): Restore DSCP from the Connection Mark
    # This must happen on ingress (ffff:) BEFORE the mirred redirect to carry the priority into the IFB.
    tc filter add dev "$device" parent ffff: protocol all prio 1 matchall \
        action ctinfo dscp 63 128 continue || \
        qdisc_setup_failed "Failed to install ctinfo ingress filter on $device."

    # 2. Redirect (Priority 2): Send the now-marked packet to the IFB device for shaping
    tc filter add dev "$device" parent ffff: protocol all prio 2 matchall \
        action mirred egress redirect dev "$lan_dev" || \
        qdisc_setup_failed "Failed to install IFB redirect from $device to $lan_dev."
    
    # Calculate a small realtime reserve per interface. The non-realtime lane
    # gets the rest of the link and is still host-fair through CAKE in hybrid.
    local game_up="$(calculate_realtime_rate "$upload" "wan")"
    local game_down="$(calculate_realtime_rate "$download" "lan")"
    local game_up_override game_down_override
    config_get game_up_override hfsc GAMEUP
    config_get game_down_override hfsc GAMEDOWN

    if [ -n "$game_up_override" ]; then
        if [ "$game_up_override" -gt 0 ] 2>/dev/null && [ "$game_up_override" -lt "$upload" ] 2>/dev/null; then
            game_up="$game_up_override"
        else
            log_msg -warn "Ignoring invalid hfsc.GAMEUP override '$game_up_override' for $device."
        fi
    fi

    if [ -n "$game_down_override" ]; then
        if [ "$game_down_override" -gt 0 ] 2>/dev/null && [ "$game_down_override" -lt "$download" ] 2>/dev/null; then
            game_down="$game_down_override"
        else
            log_msg -warn "Ignoring invalid hfsc.GAMEDOWN override '$game_down_override' for $device."
        fi
    fi
    
    case "$qdisc" in
        hfsc)
            print_msg "  Applying HFSC (UL: ${upload}k, DL: ${download}k, game UL/DL: ${game_up}k/${game_down}k, MTU: ${dev_mtu})"
            setup_interface_qdisc_direction "$device" "$upload" "$game_up" "wan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            setup_interface_qdisc_direction "$lan_dev" "$download" "$game_down" "lan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            ;;
        cake)
            print_msg "  Applying CAKE (UL: ${upload}k, DL: ${download}k, MTU: ${dev_mtu})"
            setup_cake "$device" "$lan_dev" "$upload" "$download" "$preset" "$overhead" "$mpu"
            ;;
        htb)
            print_msg "  Applying HTB (UL: ${upload}k, DL: ${download}k, MTU: ${dev_mtu})"
            setup_interface_qdisc_direction "$device" "$upload" 0 "wan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            setup_interface_qdisc_direction "$lan_dev" "$download" 0 "lan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            ;;
        hybrid)
            print_msg "  Applying Hybrid (UL: ${upload}k, DL: ${download}k, game UL/DL: ${game_up}k/${game_down}k, MTU: ${dev_mtu})"
            setup_interface_qdisc_direction "$device" "$upload" "$game_up" "wan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            setup_interface_qdisc_direction "$lan_dev" "$download" "$game_down" "lan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            ;;
        *)
            print_msg -err "Unsupported qdisc '$qdisc' for interface $config"
            # Fallback to HFSC?
            setup_interface_qdisc_direction "$device" "$upload" "$game_up" "wan" "hfsc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            setup_interface_qdisc_direction "$lan_dev" "$download" "$game_down" "lan" "hfsc" "$preset" "$overhead" "$dev_mtu" "$mpu"
            ;;
    esac

    # Instead of relying strictly on DSCP tags carrying into the IFB, map specific ports statelessly via tc flower rules ahead of the fallback matchers.
    apply_tc_custom_ingress_rules "$lan_dev" "$qdisc"

    # SFO compatibility
    if [ "$SFO_ENABLED" = "1" ]; then
        print_msg "  Enabling SFO compatibility"
        tc filter add dev "$device" parent 1: protocol all matchall action ctinfo dscp 63 128 continue
    fi
}

##############################
#       Main Logic
##############################

# Validate gameqdisc choice (used by HFSC and Hybrid)
# This assumes global gameqdisc setting applies to all interfaces using HFSC/Hybrid
case "$gameqdisc" in
    drr|qfq|pfifo|bfifo|red|fq_codel|netem) ;; # Supported qdiscs
    *)
        print_msg -warn "Unsupported gameqdisc '$gameqdisc' selected in config. Reverting to 'pfifo'."
        gameqdisc="pfifo"
        ;;
esac

# Handle refresh-device mode: rebuild qdiscs for one device only, then exit.
# Usage: /bin/sh /etc/multiwan-qos.sh refresh-device <device-name>
# Does NOT regenerate nftables rules or reload firewall.
if [ "$1" = "refresh-device" ]; then
    target_device="$2"
    [ -z "$target_device" ] && { error_out "Usage: multiwan_qos.sh refresh-device <device>"; exit 1; }

    [ -f "$MULTIWAN_QOS_RESTARTING_FILE" ] && {
        error_out "MultiWAN QoS is restarting; refresh-device is temporarily disabled."
        exit 1
    }

    refresh_lock_acquired=0
    refresh_lock_token=
    refresh_lock_cleanup() {
        [ "$refresh_lock_acquired" -eq 1 ] || return 0
        mw_lock_release_for "$MULTIWAN_QOS_REFRESH_LOCK_DIR" "$refresh_lock_token"
        refresh_lock_acquired=0
    }
    trap refresh_lock_cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mw_lock_acquire "$MULTIWAN_QOS_REFRESH_LOCK_DIR" || {
        if mw_lock_owner_alive "$MULTIWAN_QOS_REFRESH_LOCK_DIR"; then
            error_out "MultiWAN QoS refresh is already in progress as pid $MW_LOCK_OWNER_PID."
        else
            error_out "MultiWAN QoS refresh lock is busy."
        fi
        exit 1
    }
    refresh_lock_acquired=1
    refresh_lock_token="$MW_LOCK_TOKEN"

    # Per-device cooldown: prevent rapid sequential rebuilds from any caller.
    # The multiwan_nfttrack side has its own 60s cooldown; this 30s guard is
    # defense-in-depth on the multiwan_qos side.
    local _cd_file="/tmp/multiwan_qos_refresh_${target_device}"
    local _cd_now _cd_last _cd_secs=30
    _cd_now="$(date +%s 2>/dev/null)" || _cd_now=0
    _cd_last="$(cat "$_cd_file" 2>/dev/null)"
    case "$_cd_last" in ""|*[!0-9]*) _cd_last=0 ;; esac
    if [ "$_cd_now" -gt 0 ] && [ "$_cd_last" -gt 0 ] && \
       [ $((_cd_now - _cd_last)) -lt "$_cd_secs" ]; then
        log_msg "Skipping refresh for $target_device: cooldown active (${_cd_secs}s)"
        exit 0
    fi
    [ "$_cd_now" -gt 0 ] && printf '%s\n' "$_cd_now" > "$_cd_file" 2>/dev/null

    # Only allow refresh if the nft table already exists â€” qdisc refresh
    # relies on existing MultiWAN QoS classification/ctinfo state.
    nft list table inet dscptag >/dev/null 2>&1 || {
        error_out "MultiWAN QoS nft table is missing; use '/etc/init.d/multiwan-qos restart' instead"
        exit 1
    }

    refresh_interface_soft() {
        local config="$1" device download qdisc enabled preset overhead mpu
        local dev_mtu lan_dev game_down game_down_override

        config_get device "$config" device
        [ "$device" = "$target_device" ] || return 1

        config_get_bool enabled "$config" enabled 1
        [ "$enabled" -eq 1 ] || return 1

        config_get download "$config" download
        config_get qdisc "$config" qdisc 'hfsc'
        config_get preset "$config" preset 'ethernet'
        config_get overhead "$config" overhead
        config_get mpu "$config" mpu

        if [ "$download" -lt 1000 ] 2>/dev/null; then
            download=1000
        fi
        if [ "$download" -gt 2500000 ] 2>/dev/null; then
            download=2500000
        fi

        case "$qdisc" in
            hfsc|htb|hybrid) ;;
            *) return 1 ;;
        esac

        lan_dev="ifb-$device"
        ip link show "$lan_dev" >/dev/null 2>&1 || return 1

        dev_mtu=$(cat "/sys/class/net/$device/mtu" 2>/dev/null)
        [ -z "$dev_mtu" ] || [ "$dev_mtu" -le 0 ] 2>/dev/null && dev_mtu=1500

        game_down="$(calculate_realtime_rate "$download" "lan")"
        config_get game_down_override hfsc GAMEDOWN
        if [ -n "$game_down_override" ]; then
            if [ "$game_down_override" -gt 0 ] 2>/dev/null && [ "$game_down_override" -lt "$download" ] 2>/dev/null; then
                game_down="$game_down_override"
            else
                log_msg -warn "Ignoring invalid hfsc.GAMEDOWN override '$game_down_override' for $device."
            fi
        fi

        log_msg "Soft-refreshing qdisc tree for $device via $lan_dev"
        disable_qos_offloads "$device" "wan"
        disable_qos_offloads "$lan_dev" "ifb"
        disable_configured_extra_offloads
        setup_interface_qdisc_direction "$lan_dev" "$download" "$game_down" "lan" "$qdisc" "$preset" "$overhead" "$dev_mtu" "$mpu" || return 1
        apply_tc_custom_ingress_rules "$lan_dev" "$qdisc"
    }

    found=0
    refresh_single_interface() {
        local config="$1" device qdisc
        config_get device "$config" device
        [ "$device" = "$target_device" ] || return 0
        found=1
        local lan_dev="ifb-$device"
        config_get qdisc "$config" qdisc 'hfsc'
        [ "$qdisc" = "cake" ] && {
            log_msg "Refreshing qdiscs for $device using full rebuild"
            cleanup_interface_state "$device" "$lan_dev"
            setup_interface "$config"
            return 0
        }
        if refresh_interface_soft "$config"; then
            log_msg "Soft qdisc refresh complete for $device (WAN ingress left untouched)"
            return 0
        fi

        log_msg -warn "Soft qdisc refresh unavailable for $device; falling back to full refresh"
        cleanup_interface_state "$device" "$lan_dev"
        setup_interface "$config"
    }

    config_foreach refresh_single_interface interface

    [ "$found" -eq 1 ] || { error_out "Device '$target_device' not found in multiwan_qos config"; exit 1; }
    log_msg "Qdisc refresh complete for $target_device â€” nftables and firewall untouched"
    exit 0
fi

# Check for interfaces and remove empty ones
[ -z "$WAN_INTERFACES" ] && WAN_INTERFACES=""
disable_configured_extra_offloads

# Iterate interfaces
config_foreach setup_interface interface

if [ -z "$WAN_INTERFACES" ]; then
    print_msg -warn "No configured MultiWAN QoS WAN devices are currently available. Skipping nftables generation until hotplug restarts MultiWAN QoS."
    print_msg "DONE!"
    exit 0
fi

# Generate and apply NFT rules
generate_main_nft_file || exit 1
print_msg "NFTables rules generated."

# Setup multicast policing on LAN to prevent IPTV floods on unmanaged switches
# Only affects multicast (224.0.0.0/4) traffic â€” unicast (gaming, cameras) is untouched
# Uses nftables rate limiting instead of tc (no kernel module dependencies)
setup_multicast_policing() {
    local mcast_enabled mcast_rate mcast_dev

    # Read from UCI config (advanced section) using config_get
    config_get mcast_enabled advanced MULTICAST_POLICING '0'
    [ "$mcast_enabled" -eq 1 ] 2>/dev/null || return 0

    config_get mcast_rate advanced MULTICAST_RATE '13000'
    config_get mcast_dev advanced MULTICAST_LAN_DEVICE 'eth0'

    # Convert kbit/s to kbytes/s for nftables (nft uses bytes, not bits)
    local rate_kbytes=$((mcast_rate / 8))
    [ "$rate_kbytes" -lt 1 ] && rate_kbytes=1

    # Skip if LAN device doesn't exist
    ip link show "$mcast_dev" >/dev/null 2>&1 || {
        log_msg -warn "Multicast policing: device $mcast_dev not found, skipping"
        return 0
    }

    # Remove existing multicast policing table if present (idempotent)
    nft destroy table inet multiwan_qos_mcast 2>/dev/null

    # Create a dedicated table + chain for multicast policing
    # Capture exit code directly to avoid fragile $? after heredoc (#10)
    local nft_rv=0
    nft -f - <<EOF || nft_rv=$?
table inet multiwan_qos_mcast {
    chain mcast_police {
        type filter hook forward priority filter - 1; policy accept;
        ip daddr 224.0.0.0/4 oifname "$mcast_dev" limit rate over ${rate_kbytes} kbytes/second burst ${rate_kbytes} kbytes drop
    }
}
EOF

    if [ "$nft_rv" -eq 0 ]; then
        print_msg "Multicast policing: ${mcast_rate} kbit/s (${rate_kbytes} kbytes/s) on $mcast_dev"
    else
        log_msg -warn "Multicast policing: failed to create nftables rules"
    fi
}

setup_multicast_policing

print_msg "DONE!"

# Status output (generic)
if command -v tc >/dev/null; then
    # Maybe iterate over interfaces again to show status?
    # Or just say "Check 'tc -s qdisc' manually."
    print_msg "To check status, run: tc -s qdisc show dev <interface>"
fi


exit 0
