#!/bin/sh

. "${IPKG_INSTROOT}/usr/share/libubox/jshn.sh"
. "${IPKG_INSTROOT}/lib/multiwan-nft/common.sh"

CONNTRACK_FILE="/proc/net/nf_conntrack"
IPv6_REGEX="([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,7}:|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|"
IPv6_REGEX="${IPv6_REGEX}[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|"
IPv6_REGEX="${IPv6_REGEX}:((:[0-9a-fA-F]{1,4}){1,7}|:)|"
IPv6_REGEX="${IPv6_REGEX}fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|"
IPv6_REGEX="${IPv6_REGEX}::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
IPv4_REGEX="((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"

DEFAULT_LOWEST_METRIC=256

# nft helper: ensure table exists (for queries only)
multiwan_nft_nft_init_table()
{
	$NFT list table $NFT_FAMILY $NFT_TABLE &>/dev/null && return 0
	$NFT add table $NFT_FAMILY $NFT_TABLE || {
		LOG warn "nft: failed to create table $NFT_FAMILY $NFT_TABLE"
		return 1
	}
}

# nft helper: add element to set (direct call, safe for incremental updates)
multiwan_nft_nft_add_set_element()
{
	local setname="$1"
	local element="$2"
	$NFT add element $NFT_FAMILY $NFT_TABLE "$setname" "{ $element }" 2>/dev/null
}

# nft helper: delete chain if exists (direct call for cleanup)
multiwan_nft_nft_delete_chain()
{
	local chain="$1"
	$NFT delete chain $NFT_FAMILY $NFT_TABLE "$chain" 2>/dev/null || return 0
}

# nft helper: delete every matching rule handle in a chain.
# This is intentionally exhaustive so stale duplicate handles from interrupted
# hotplug/start rebuilds do not survive the next clean interface rebuild.
multiwan_nft_nft_delete_matching_rules()
{
	local chain="$1"
	local pattern="$2"
	local handle

	$NFT -a list chain $NFT_FAMILY $NFT_TABLE "$chain" 2>/dev/null | \
		grep "$pattern" | sed -n 's/.*handle \([0-9]*\).*/\1/p' | \
		while read -r handle; do
			[ -n "$handle" ] || continue
			$NFT delete rule $NFT_FAMILY $NFT_TABLE "$chain" handle "$handle" || \
				LOG warn "nft: failed to delete rule handle $handle from $chain"
		done
}

# nft helper: dump rules for debugging
multiwan_nft_nft_dump()
{
	local name="$1"
	multiwan_nft_debug_enabled || return 0
	$NFT list table $NFT_FAMILY $NFT_TABLE > "${MULTIWAN_NFT_STATUS_NFT_LOG_DIR}/nft-${name}.dump" 2>&1
}

# nft helper: create/flush a set (for incremental updates after base ruleset is loaded)
multiwan_nft_nft_create_set()
{
	local setname="$1"
	local settype="$2"
	local setflags="$3"
	
	if $NFT list set $NFT_FAMILY $NFT_TABLE "$setname" &>/dev/null; then
		$NFT flush set $NFT_FAMILY $NFT_TABLE "$setname" || {
			LOG warn "nft: failed to flush set $setname"
			return 1
		}
	else
		$NFT add set $NFT_FAMILY $NFT_TABLE "$setname" "{ $settype; $setflags; }" || {
			LOG warn "nft: failed to create set $setname"
			return 1
		}
	fi
}

# nft helper: create/flush a chain (for incremental updates)
multiwan_nft_nft_create_chain()
{
	local chain="$1"
	local chaintype="$2"
	
	if $NFT list chain $NFT_FAMILY $NFT_TABLE "$chain" &>/dev/null; then
		$NFT flush chain $NFT_FAMILY $NFT_TABLE "$chain" || {
			LOG warn "nft: failed to flush chain $chain"
			return 1
		}
	else
		if [ -n "$chaintype" ]; then
			$NFT add chain $NFT_FAMILY $NFT_TABLE "$chain" "{ $chaintype; }" || {
				LOG warn "nft: failed to create chain $chain"
				return 1
			}
		else
			$NFT add chain $NFT_FAMILY $NFT_TABLE "$chain" || {
				LOG warn "nft: failed to create chain $chain"
				return 1
			}
		fi
	fi
}

# nft helper: add rule to chain (for incremental updates)
multiwan_nft_nft_add_rule()
{
	local chain="$1"
	shift
	$NFT add rule $NFT_FAMILY $NFT_TABLE "$chain" "$@" || {
		LOG warn "nft: failed to add rule to $chain"
		return 1
	}
}

# nft helper: insert rule at beginning of chain
multiwan_nft_nft_insert_rule()
{
	local chain="$1"
	shift
	$NFT insert rule $NFT_FAMILY $NFT_TABLE "$chain" "$@" || {
		LOG warn "nft: failed to insert rule into $chain"
		return 1
	}
}

# Generate complete nftables ruleset for atomic loading
# This function generates the entire multiwan_nft nftables configuration as a string
# which can then be loaded atomically via nft -f
multiwan_nft_generate_base_ruleset()
{
	local buf=""
	
	# Table definition with flush
	buf="flush table $NFT_FAMILY $NFT_TABLE

table $NFT_FAMILY $NFT_TABLE {
	# Sets for network matching
	set multiwan_nft_custom_v4 {
		type ipv4_addr
		flags interval
	}
	
	set multiwan_nft_connected_v4 {
		type ipv4_addr
		flags interval
	}
	
	set multiwan_nft_dynamic_v4 {
		type ipv4_addr
		flags interval
	}
"
	
	# Add IPv6 sets if supported
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}
	set multiwan_nft_custom_v6 {
		type ipv6_addr
		flags interval
	}
	
	set multiwan_nft_connected_v6 {
		type ipv6_addr
		flags interval
	}
	
	set multiwan_nft_dynamic_v6 {
		type ipv6_addr
		flags interval
	}
"
	fi
	
	# Base chains
	buf="${buf}
	# Interface input chain
	chain multiwan_nft_ifaces_in {
	}
	
	# Set matching chains
	chain multiwan_nft_custom_v4 {
		ip daddr @multiwan_nft_custom_v4 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
	
	chain multiwan_nft_connected_v4 {
		ip daddr @multiwan_nft_connected_v4 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
	
	chain multiwan_nft_dynamic_v4 {
		ip daddr @multiwan_nft_dynamic_v4 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
"
	
	# IPv6 set chains
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}
	chain multiwan_nft_custom_v6 {
		ip6 daddr @multiwan_nft_custom_v6 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
	
	chain multiwan_nft_connected_v6 {
		ip6 daddr @multiwan_nft_connected_v6 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
	
	chain multiwan_nft_dynamic_v6 {
		ip6 daddr @multiwan_nft_dynamic_v6 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
	}
"
	fi
	
	# User rules chain
	buf="${buf}
	chain multiwan_nft_rules {
	}
	
	# Main hook chain with common logic
	chain multiwan_nft_hook {
"
	# ICMPv6 exemption
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}		icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } return
"
	fi
	
	buf="${buf}		# Skip multicast traffic entirely - no multiwan_nft marking
		# Multicast needs special kernel handling (igmpproxy/mrouted)
		# Marking it interferes with conntrack and causes flooding issues
		ip daddr 224.0.0.0/4 return
		ip6 daddr ff00::/8 return
		
		# Restore persistent interface/failure marks from conntrack, but do
		# not restore MMX_DEFAULT. Default-marked traffic must re-enter
		# multiwan_nft_rules so balanced policies can choose a WAN for fresh flows.
		meta mark and $MMX_MASK == 0 ct mark and $MMX_MASK != 0 ct mark and $MMX_MASK != $MMX_DEFAULT meta mark set ct mark and $MMX_MASK
		
		# Jump to interface input chain
		meta mark and $MMX_MASK == 0 jump multiwan_nft_ifaces_in
		
		# Jump to set matching chains
		meta mark and $MMX_MASK == 0 meta nfproto ipv4 jump multiwan_nft_custom_v4
		meta mark and $MMX_MASK == 0 meta nfproto ipv4 jump multiwan_nft_connected_v4
		meta mark and $MMX_MASK == 0 meta nfproto ipv4 jump multiwan_nft_dynamic_v4
"
	
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}		meta mark and $MMX_MASK == 0 meta nfproto ipv6 jump multiwan_nft_custom_v6
		meta mark and $MMX_MASK == 0 meta nfproto ipv6 jump multiwan_nft_connected_v6
		meta mark and $MMX_MASK == 0 meta nfproto ipv6 jump multiwan_nft_dynamic_v6
"
	fi
	
	buf="${buf}		# Jump to user rules
		meta mark and $MMX_MASK == 0 jump multiwan_nft_rules
		
		# Per-interface rules added by multiwan_nft_create_iface_nft save real WAN
		# marks to conntrack. Do not save MMX_DEFAULT here; persisting default
		# marks lets stale/default flows bypass balanced policy and fall back
		# to the main routing table's preferred WAN.
	}
	
	# Prerouting hook
	chain multiwan_nft_prerouting {
		type filter hook prerouting priority mangle;
		jump multiwan_nft_hook
	}
	
	# Output hook
	chain multiwan_nft_output {
		type route hook output priority mangle;
		jump multiwan_nft_hook
	}

}
"
	
	echo "$buf"
}

# Load the base ruleset atomically
multiwan_nft_load_base_ruleset()
{
	local ruleset
	
	# Ensure table exists before flush (for fresh installs)
	$NFT list table $NFT_FAMILY $NFT_TABLE &>/dev/null || \
		$NFT add table $NFT_FAMILY $NFT_TABLE
	
	ruleset=$(multiwan_nft_generate_base_ruleset)
	
	echo "$ruleset" > "${MULTIWAN_NFT_STATUS_NFT_LOG_DIR}/base-ruleset.nft"
	
	if echo "$ruleset" | $NFT -f -; then
		LOG notice "Base nftables ruleset loaded successfully"
		# Note: multiwan_nft_set_connected_* called from init script with proper delay
		return 0
	else
		LOG error "Failed to load base nftables ruleset"
		return 1
	fi
}



multiwan_nft_update_dev_to_table()
{
	local _tid
	# shellcheck disable=SC2034
	multiwan_nft_dev_tbl_ipv4=" "
	# shellcheck disable=SC2034
	multiwan_nft_dev_tbl_ipv6=" "

	update_table()
	{
		local family curr_table device enabled
		let _tid++
		config_get family "$1" family ipv4
		network_get_device device "$1"
		[ -z "$device" ] && return
		config_get enabled "$1" enabled
		[ "$enabled" -eq 0 ] && return
		curr_table=$(eval "echo	 \"\$multiwan_nft_dev_tbl_${family}\"")
		export "multiwan_nft_dev_tbl_$family=${curr_table}${device}=$_tid "
	}
	network_flush_cache
	config_foreach update_table interface
}

multiwan_nft_update_iface_to_table()
{
	local _tid
	multiwan_nft_iface_tbl=" "
	update_table()
	{
		let _tid++
		export multiwan_nft_iface_tbl="${multiwan_nft_iface_tbl}${1}=$_tid "
	}
	config_foreach update_table interface
}

multiwan_nft_route_line_dev()
{
	# must have multiwan_nft config already loaded
	# arg 1 is route device
	local _tid route_line route_device route_family entry curr_table
	route_line=$2
	route_family=$3
	route_device=$(echo "$route_line" | sed -ne "s/.*dev \([^ ]*\).*/\1/p")
	unset "$1"
	[ -z "$route_device" ] && return

	curr_table=$(eval "echo \"\$multiwan_nft_dev_tbl_${route_family}\"")
	for entry in $curr_table; do
		if [ "${entry%%=*}" = "$route_device" ]; then
			_tid=${entry##*=}
			export "$1=$_tid"
			return
		fi
	done
}

# multiwan_nft_count_one_bits() is defined in common.sh — removed duplicate here (#16)

multiwan_nft_get_iface_id()
{
	local _tmp
	[ -z "$multiwan_nft_iface_tbl" ] && multiwan_nft_update_iface_to_table
	_tmp="${multiwan_nft_iface_tbl##* ${2}=}"
	_tmp=${_tmp%% *}
	export "$1=$_tmp"
}

multiwan_nft_set_custom_ipset_v4()
{
	local custom_network_v4

	for custom_network_v4 in $($IP4 route list table "$1" | awk '{print $1}' | grep -E "$IPv4_REGEX"); do
		LOG notice "Adding network $custom_network_v4 from table $1 to multiwan_nft_custom_v4 set"
		multiwan_nft_nft_add_set_element "multiwan_nft_custom_v4" "$custom_network_v4"
	done
}

multiwan_nft_set_custom_ipset_v6()
{
	local custom_network_v6

	for custom_network_v6 in $($IP6 route list table "$1" | awk '{print $1}' | grep -E "$IPv6_REGEX"); do
		LOG notice "Adding network $custom_network_v6 from table $1 to multiwan_nft_custom_v6 set"
		multiwan_nft_nft_add_set_element "multiwan_nft_custom_v6" "$custom_network_v6"
	done
}

multiwan_nft_set_custom_ipset()
{
	# Sets already created by base ruleset, just flush and populate
	$NFT flush set $NFT_FAMILY $NFT_TABLE multiwan_nft_custom_v4 2>/dev/null
	config_list_foreach "globals" "rt_table_lookup" multiwan_nft_set_custom_ipset_v4

	if [ "$NO_IPV6" -eq 0 ]; then
		$NFT flush set $NFT_FAMILY $NFT_TABLE multiwan_nft_custom_v6 2>/dev/null
		config_list_foreach "globals" "rt_table_lookup" multiwan_nft_set_custom_ipset_v6
	fi

	multiwan_nft_nft_dump "set_custom_ipset"
}


multiwan_nft_set_connected_ipv4()
{
	local connected_network_v4
	local candidate_list cidr_list

	# Sets already created by base ruleset, just flush and populate
	$NFT flush set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v4 2>/dev/null

	candidate_list=""
	cidr_list=""
	route_lists()
	{
		# Only query main routing table — 'table 0' is superset that creates duplicates (#25)
		$IP4 route | awk '{print $1}'
	}
	for connected_network_v4 in $(route_lists | grep -E "$IPv4_REGEX"); do
		if [ -z "${connected_network_v4##*/*}" ]; then
			cidr_list="$cidr_list $connected_network_v4"
		else
			candidate_list="$candidate_list $connected_network_v4"
		fi
	done

	for connected_network_v4 in $cidr_list; do
		multiwan_nft_nft_add_set_element "multiwan_nft_connected_v4" "$connected_network_v4"
	done
	for connected_network_v4 in $candidate_list; do
		multiwan_nft_nft_add_set_element "multiwan_nft_connected_v4" "$connected_network_v4"
	done


	multiwan_nft_nft_dump "set_connected_v4"
}

multiwan_nft_set_connected_ipv6()
{
	local connected_network_v6
	[ "$NO_IPV6" -eq 0 ] || return

	# Sets already created by base ruleset, just flush and populate
	$NFT flush set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v6 2>/dev/null

	for connected_network_v6 in $($IP6 route | awk '{print $1}' | grep -E "$IPv6_REGEX"); do
		multiwan_nft_nft_add_set_element "multiwan_nft_connected_v6" "$connected_network_v6"
	done

	multiwan_nft_nft_dump "set_connected_v6"
}

# Stubs removed (#26): multiwan_nft_set_connected_ipset and multiwan_nft_set_dynamic_ipset
# Sets are created in the base ruleset — no stub wrappers needed

multiwan_nft_set_general_rules()
{
	local IP

	for IP in "$IP4" "$IP6"; do
		[ "$IP" = "$IP6" ] && [ "$NO_IPV6" -ne 0 ] && continue
		RULE_NO=$((MM_BLACKHOLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_BLACKHOLE/$MMX_MASK blackhole || \
				LOG warn "rule: failed to add global blackhole rule pref $RULE_NO"
		fi

		RULE_NO=$((MM_UNREACHABLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_UNREACHABLE/$MMX_MASK unreachable || \
				LOG warn "rule: failed to add global unreachable rule pref $RULE_NO"
		fi
	done
}

# multiwan_nft_set_general_nft is now handled by multiwan_nft_load_base_ruleset
# which loads the complete ruleset atomically via nft -f
# This stub is kept for compatibility with any code that might call it
multiwan_nft_set_general_nft()
{
	# Base chains and rules are now created atomically in multiwan_nft_load_base_ruleset
	# This function is a no-op stub for backward compatibility
	LOG debug "multiwan_nft_set_general_nft: skipped (handled by atomic base ruleset)"
	multiwan_nft_nft_dump "set_general_nft"
}

multiwan_nft_create_iface_nft()
{
	local id family iface device
	iface="$1"
	device="$2"

	config_get family "$iface" family ipv4
	multiwan_nft_get_iface_id id "$iface"

	[ -n "$id" ] || return 0
	[ "$family" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return

	multiwan_nft_nft_init_table || return 1
	# Remove any stale per-interface chain/rules before recreating this
	# interface. This keeps repeated ifup/start/hotplug events idempotent.
	multiwan_nft_delete_iface_nft "$iface"

	# Only create shared chain if not exist - don't flush (other interfaces may have added rules)
	if ! $NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_ifaces_in" &>/dev/null; then
		$NFT add chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_ifaces_in" || {
			LOG warn "nft: failed to create shared chain multiwan_nft_ifaces_in"
			return 1
		}
	fi
	# Per-interface chain can be flushed since it's unique
	multiwan_nft_nft_create_chain "multiwan_nft_iface_in_$iface" || return 1

	local setsfx
	[ "$family" = "ipv6" ] && setsfx="v6" || setsfx="v4"

	# Match source IPs from custom/connected/dynamic sets - mark as default
	for settype in custom connected dynamic; do
		if [ "$family" = "ipv4" ]; then
			multiwan_nft_nft_add_rule "multiwan_nft_iface_in_$iface" \
				iifname "$device" ip saddr @"multiwan_nft_${settype}_${setsfx}" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT \
				comment "\"default\"" || return 1
		else
			multiwan_nft_nft_add_rule "multiwan_nft_iface_in_$iface" \
				iifname "$device" ip6 saddr @"multiwan_nft_${settype}_${setsfx}" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT \
				comment "\"default\"" || return 1
		fi
	done

	# Mark traffic from this interface with its ID
	local mark_val=$(multiwan_nft_id2mask id MMX_MASK)
	multiwan_nft_nft_add_rule "multiwan_nft_iface_in_$iface" \
		iifname "$device" meta mark and $MMX_MASK == 0 \
		meta mark set meta mark and $MMX_INVMASK or $mark_val comment "\"$iface\"" || return 1

	# Add jump from multiwan_nft_ifaces_in if not present
	if ! $NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_ifaces_in 2>/dev/null | \
		grep -q "jump multiwan_nft_iface_in_$iface"; then
		multiwan_nft_nft_add_rule multiwan_nft_ifaces_in \
			meta mark and $MMX_MASK == 0 jump "multiwan_nft_iface_in_$iface" || return 1
		LOG debug "create_iface_nft: multiwan_nft_iface_in_$iface added"
	else
		LOG debug "create_iface_nft: multiwan_nft_iface_in_$iface already present"
	fi

	# Fix: Prevent multiwan_nft output hook from hijacking tracking pings.
	# Without libwrap, multiwan-nft-track uses 'ping -I $DEVICE' (SO_BINDTODEVICE).
	# The type-route output hook re-routes these pings through whichever
	# interface the policy selects, creating a deadlock: once an interface is
	# marked offline, its tracking pings get sent through a different WAN,
	# so the interface can never recover.
	# APPROACH HISTORY:
	#  - oif_track bypass in multiwan_nft_output: REVERTED (causes "Network Unreachable"
	#    for secondary WANs because pings fall through to main routing table)
	#  - Current fix: protect_tracking_pings rule in multiwan_nft_rules (see
	#    multiwan_nft_set_user_rules_nft) returns ICMP echo-request before user
	#    policies can hijack them. Mark stays 0, original SO_BINDTODEVICE
	#    routing is preserved.

	# Add per-interface ct mark save rule to multiwan_nft_hook
	# Uses constant mark_val (not meta mark) so nftables accepts it.
	# This saves the interface mark to conntrack for connection persistence,
	# preserving all non-multiwan_nft ct mark bits (e.g., MultiWAN QoS DSCP).
	if ! $NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_hook 2>/dev/null | \
		grep -q "\"ct_save_$iface\""; then
		multiwan_nft_nft_add_rule multiwan_nft_hook \
			meta mark and $MMX_MASK == $mark_val \
			ct mark and $MMX_MASK != $mark_val \
			ct mark set ct mark and $MMX_INVMASK or $mark_val \
			comment "\"ct_save_$iface\"" || return 1
		LOG debug "create_iface_nft: added ct mark save for $iface ($mark_val)"
	fi

	multiwan_nft_nft_dump "create_iface_nft-$iface"
}

multiwan_nft_delete_iface_nft()
{
	local iface="$1"
	local family

	config_get family "$iface" family ipv4
	[ "$family" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return

	# Remove all stale handles, not just the first one. Interrupted or
	# overlapping rebuilds can otherwise leave duplicate jumps/save rules.
	multiwan_nft_nft_delete_matching_rules multiwan_nft_output "\"oif_track_$iface\""
	multiwan_nft_nft_delete_matching_rules multiwan_nft_hook "\"ct_save_$iface\""
	multiwan_nft_nft_delete_matching_rules multiwan_nft_ifaces_in "jump multiwan_nft_iface_in_$iface"

	# Delete the interface chain
	multiwan_nft_nft_delete_chain "multiwan_nft_iface_in_$iface"

	multiwan_nft_nft_dump "delete_iface_nft-$iface"
}

multiwan_nft_extra_tables_routes()
{
	$IP route list table "$1"
}

multiwan_nft_get_routes()
{
	{
		$IP route list table main
		config_list_foreach "globals" "rt_table_lookup" multiwan_nft_extra_tables_routes
	} | sed -ne "$MULTIWAN_NFT_ROUTE_LINE_EXP" | sort -u
}

multiwan_nft_create_iface_route()
{
	local tid route_line family IP id desired_routes current_routes route_failed device
	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"
	network_get_device device "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	multiwan_nft_update_dev_to_table

	desired_routes="$(
	multiwan_nft_get_routes | while read -r route_line; do
		[ -n "$route_line" ] || continue
		tid=
		multiwan_nft_route_line_dev "tid" "$route_line" "$family"
		{ [ -z "${route_line##default*}" ] || [ -z "${route_line##fe80::/64*}" ]; } && [ "$tid" != "$id" ] && continue
		if [ -z "$tid" ] || [ "$tid" = "$id" ]; then
			echo "$route_line"
		fi
	done
	)"

	if [ -z "$desired_routes" ]; then
		LOG warn "route: no desired routes collected for table $id on interface $1; preserving existing table"
		return 0
	fi

	route_failed=0
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		multiwan_nft_route_replace_idempotent "$IP" "$id" "$route_line" || {
			route_failed=1
		}
	done <<EOF
$desired_routes
EOF

	# Remove stale routes that are no longer in the desired set.
	# Exact-line matching (grep -Fxq) is safe here because both desired_routes
	# and current_routes are produced by the same 'ip route' output pipeline,
	# so field order and whitespace are deterministic. A canonical route parser
	# would be needed only if false positives (stale routes surviving) are
	# observed in practice.
	current_routes="$($IP route list table "$id" 2>/dev/null)"
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		echo "$desired_routes" | grep -Fxq "$route_line" && continue
		# Keep this interface's own default route even when it is absent from
		# main. Disconnected events remove only main-table defaults; the
		# per-interface table default is still required for tracking recovery.
		if [ -n "$device" ] && [ "${route_line#default}" != "$route_line" ]; then
			case " $route_line " in
				*" dev $device "*) continue ;;
			esac
		fi
		$IP route del table "$id" $route_line || {
			LOG warn "route: failed to delete stale '$route_line' from table $id"
			route_failed=1
		}
	done <<EOF
$current_routes
EOF

	multiwan_nft_restore_iface_table_default_route "$1" "$device"

	[ "$route_failed" -eq 0 ] || return 1
}

multiwan_nft_delete_iface_route()
{
	local id family

	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"

	if [ -z "$id" ]; then
		LOG warn "delete_iface_route: could not find table id for interface $1"
		return 0
	fi

	if [ "$family" = "ipv4" ]; then
		$IP4 route flush table "$id"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		$IP6 route flush table "$id"
	fi
}

multiwan_nft_create_iface_rules()
{
	local id family IP

	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	multiwan_nft_delete_iface_rules "$1"

	$IP rule add pref $((id+1000)) iif "$2" lookup "$id" || {
		LOG warn "rule: failed to add iif rule for $1/$2 table $id"
		return 1
	}
	$IP rule add pref $((id+1000)) oif "$2" lookup "$id" || {
		LOG warn "rule: failed to add oif rule for $1/$2 table $id"
		return 1
	}
	$IP rule add pref $((id+2000)) fwmark "$(multiwan_nft_id2mask id MMX_MASK)/$MMX_MASK" lookup "$id" || {
		LOG warn "rule: failed to add fwmark lookup rule for $1 table $id"
		return 1
	}
	$IP rule add pref $((id+3000)) fwmark "$(multiwan_nft_id2mask id MMX_MASK)/$MMX_MASK" unreachable || {
		LOG warn "rule: failed to add fwmark unreachable rule for $1 table $id"
		return 1
	}
}

multiwan_nft_delete_iface_rules()
{
	local id family IP rule_id

	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	for rule_id in $($IP rule list | awk -F : '$1 % 1000 == '$id' && $1 > 1000 && $1 < 4000 {print $1}'); do
		$IP rule del pref $rule_id
	done
}

multiwan_nft_delete_iface_set_entries()
{
	local id setname

	multiwan_nft_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	local mark_hex=$(multiwan_nft_id2mask id MMX_MASK | awk '{ printf "0x%08x", $1; }')
	
	# Find and delete elements from sticky rule sets that contain this interface's mark
	# Use nft -j for reliable JSON parsing instead of fragile grep on text output (#19)
	for setname in $($NFT list sets $NFT_FAMILY $NFT_TABLE 2>/dev/null | grep -oE 'set multiwan_nft_sticky_[^ ]+' | awk '{print $2}'); do
		# List elements and filter by mark value
		local elements
		elements=$($NFT list set $NFT_FAMILY $NFT_TABLE "$setname" 2>/dev/null | \
			sed -n '/elements/,/}/p' | tr ',' '\n' | grep "$mark_hex")
		
		local elem
		for elem in $elements; do
			# Clean up whitespace and extract the element expression
			elem=$(echo "$elem" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
				sed 's/.*elements = {//;s/}$//')
			[ -z "$elem" ] && continue
			$NFT delete element $NFT_FAMILY $NFT_TABLE "$setname" "{ $elem }" 2>/dev/null || \
				LOG notice "failed to delete element from $setname"
		done
	done
}


multiwan_nft_set_policy_nft()
{
	local id iface family metric weight device is_lowest is_offline

	is_lowest=0
	config_get iface "$1" interface
	config_get metric "$1" metric 1
	config_get weight "$1" weight 1

	[ -n "$iface" ] || return 0
	network_get_device device "$iface"
	[ "$metric" -gt "$DEFAULT_LOWEST_METRIC" ] && LOG warn "Member interface $iface has >$DEFAULT_LOWEST_METRIC metric. Not appending to policy" && return 0

	multiwan_nft_get_iface_id id "$iface"

	[ -n "$id" ] || return 0

	[ "$(multiwan_nft_get_iface_hotplug_state "$iface")" = "online" ]
	is_offline=$?

	config_get family "$iface" family ipv4
	[ "$family" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return

	if [ "$family" = "ipv4" ] && [ "$is_offline" -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v4" ]; then
			is_lowest=1
			total_weight_v4=$weight
			lowest_metric_v4=$metric
		elif [ "$metric" -eq "$lowest_metric_v4" ]; then
			total_weight_v4=$((total_weight_v4+weight))
		else
			return
		fi
	elif [ "$family" = "ipv6" ] && [ "$is_offline" -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v6" ]; then
			is_lowest=1
			total_weight_v6=$weight
			lowest_metric_v6=$metric
		elif [ "$metric" -eq "$lowest_metric_v6" ]; then
			total_weight_v6=$((total_weight_v6+weight))
		else
			return
		fi
	fi

	local mark_val=$(multiwan_nft_id2mask id MMX_MASK)

	if [ "$is_lowest" -eq 1 ]; then
		# First/only interface in policy - takes all traffic
		multiwan_nft_nft_add_rule "multiwan_nft_policy_$policy" \
			meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $mark_val return \
			comment "\"$iface $weight $weight\""
	elif [ "$is_offline" -eq 0 ]; then
		# Additional interface - use probability-based load balancing
		# nft uses numgen random mod total, check < weight
		local total_weight
		[ "$family" = "ipv4" ] && total_weight=$total_weight_v4 || total_weight=$total_weight_v6
		
		multiwan_nft_nft_insert_rule "multiwan_nft_policy_$policy" \
			meta mark and $MMX_MASK == 0 \
			numgen random mod $total_weight lt $weight \
			meta mark set meta mark and $MMX_INVMASK or $mark_val return \
			comment "\"$iface $weight $total_weight\""
	elif [ -n "$device" ]; then
		# Offline but has device - use as fallback for direct output
		multiwan_nft_nft_insert_rule "multiwan_nft_policy_$policy" \
			oifname "$device" meta mark and $MMX_MASK == 0 \
			meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return \
			comment "\"out $iface $device\""
	fi
}

multiwan_nft_create_policies_nft()
{
	local last_resort lowest_metric_v4 lowest_metric_v6 total_weight_v4 total_weight_v6 policy

	policy="$1"

	config_get last_resort "$1" last_resort unreachable

	multiwan_nft_nft_init_table || return 1
	multiwan_nft_nft_create_chain "multiwan_nft_policy_$1" || return 1

	lowest_metric_v4=$DEFAULT_LOWEST_METRIC
	total_weight_v4=0

	lowest_metric_v6=$DEFAULT_LOWEST_METRIC
	total_weight_v6=0

	# First, add all member interface rules
	config_list_foreach "$1" use_member multiwan_nft_set_policy_nft

	# Add last resort rule AFTER interface rules (so it's at the end)
	case "$last_resort" in
		blackhole)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_BLACKHOLE return \
				comment "\"blackhole\"" || return 1
			;;
		default)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return \
				comment "\"default\"" || return 1
			;;
		*)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_UNREACHABLE return \
				comment "\"unreachable\"" || return 1
			;;
	esac
	
	multiwan_nft_nft_dump "create_policies_nft-$1"
}

multiwan_nft_set_policies_nft()
{
	config_foreach multiwan_nft_create_policies_nft policy
}

multiwan_nft_set_sticky_nft()
{
	local interface="$1"
	local rule="$2"
	local ipv="$3"
	local policy="$4"

	local id iface
	# Check if interface is in this policy
	if $NFT list chain $NFT_FAMILY $NFT_TABLE "$policy" 2>/dev/null | grep -q "\"$interface "; then
		multiwan_nft_get_iface_id id "$interface"
		[ -n "$id" ] || return 0
		
		local mark_val=$(multiwan_nft_id2mask id MMX_MASK)
		
		# If interface chain exists, add sticky rules
		# Sticky logic: if source IP + current mark combo exists in set, 
		# traffic is "stuck" to that interface. Otherwise, proceed with normal policy.
		if $NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_iface_in_$interface" &>/dev/null; then
			# Insert rule: Query set for specific WAN mark, if found, apply it and return
			if [ "$ipv" = "ipv4" ]; then
				multiwan_nft_nft_insert_rule "multiwan_nft_rule_$rule" \
					"ip saddr . $mark_val @multiwan_nft_sticky_${ipv}_${rule} meta mark set meta mark and $MMX_INVMASK or $mark_val return"
			else
				multiwan_nft_nft_insert_rule "multiwan_nft_rule_$rule" \
					"ip6 saddr . $mark_val @multiwan_nft_sticky_${ipv}_${rule} meta mark set meta mark and $MMX_INVMASK or $mark_val return"
			fi
		fi
	fi
}

multiwan_nft_set_sticky_set()
{
	local rule="$1"
	local mmx="$2"
	local timeout="$3"

	multiwan_nft_nft_init_table || return 1
	
	# Create sticky set for IPv4
	if ! $NFT list set $NFT_FAMILY $NFT_TABLE "multiwan_nft_sticky_ipv4_$rule" &>/dev/null; then
		$NFT add set $NFT_FAMILY $NFT_TABLE "multiwan_nft_sticky_ipv4_$rule" \
			"{ type ipv4_addr . mark; flags timeout; timeout ${timeout}s; }" || {
			LOG warn "nft: failed to create sticky IPv4 set for rule $rule"
			return 1
		}
	fi

	# Create sticky set for IPv6
	if [ "$NO_IPV6" -eq 0 ]; then
		if ! $NFT list set $NFT_FAMILY $NFT_TABLE "multiwan_nft_sticky_ipv6_$rule" &>/dev/null; then
			$NFT add set $NFT_FAMILY $NFT_TABLE "multiwan_nft_sticky_ipv6_$rule" \
				"{ type ipv6_addr . mark; flags timeout; timeout ${timeout}s; }" || {
				LOG warn "nft: failed to create sticky IPv6 set for rule $rule"
				return 1
			}
		fi
	fi

	multiwan_nft_nft_dump "set_sticky_set-$rule"
}

multiwan_nft_set_user_nft_rule()
{
	local nft_set family proto policy src_ip src_port src_iface src_dev
	local sticky dest_ip dest_port use_policy timeout rule_policy rule ipv
	local global_logging rule_logging loglevel

	rule="$1"
	ipv="$2"
	rule_policy=0
	config_get sticky "$1" sticky 0
	config_get timeout "$1" timeout 600
	config_get nft_set "$1" ipset
	config_get proto "$1" proto all
	config_get src_ip "$1" src_ip
	config_get src_iface "$1" src_iface
	config_get src_port "$1" src_port
	config_get dest_ip "$1" dest_ip
	config_get dest_port "$1" dest_port
	config_get use_policy "$1" use_policy
	config_get family "$1" family any
	config_get rule_logging "$1" logging 0
	config_get global_logging globals logging 0
	config_get loglevel globals loglevel notice

	[ "$ipv" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return
	[ "$family" = "ipv4" ] && [ "$ipv" = "ipv6" ] && return
	[ "$family" = "ipv6" ] && [ "$ipv" = "ipv4" ] && return

	# Validate IP addresses
	for ipaddr in "$src_ip" "$dest_ip"; do
		if [ -n "$ipaddr" ] && { { [ "$ipv" = "ipv4" ] && echo "$ipaddr" | grep -qE "$IPv6_REGEX"; } ||
					 { [ "$ipv" = "ipv6" ] && echo "$ipaddr" | grep -qE $IPv4_REGEX; } }; then
			LOG warn "invalid $ipv address $ipaddr specified for rule $rule"
			return
		fi
	done

	if [ -n "$src_iface" ]; then
		network_get_device src_dev "$src_iface"
		if [ -z "$src_dev" ]; then
			LOG notice "could not find device for src_iface $src_iface for rule $1"
			return
		fi
	fi

	# Skip ports for non-tcp/udp protocols
	if [ "$proto" != 'tcp' ] && [ "$proto" != 'udp' ]; then
		[ -n "$src_port" ] && LOG warn "src_port ignored for proto $proto"
		[ -n "$dest_port" ] && LOG warn "dest_port ignored for proto $proto"
		unset src_port dest_port
	fi

	# Note: iptables had a ~15 char chain name limit, nftables does not

	[ -z "$use_policy" ] && return

	# Determine action based on policy type
	local action_mark
	if [ "$use_policy" = "default" ]; then
		action_mark=$MMX_DEFAULT
	elif [ "$use_policy" = "unreachable" ]; then
		action_mark=$MMX_UNREACHABLE
	elif [ "$use_policy" = "blackhole" ]; then
		action_mark=$MMX_BLACKHOLE
	else
		rule_policy=1
		if [ "$sticky" -eq 1 ]; then
			multiwan_nft_set_sticky_set "$rule" "$MMX_MASK" "$timeout"
		fi
	fi

	# Build match criteria
	local match=""
	
	# Protocol
	[ "$proto" != "all" ] && match="$match meta l4proto $proto"
	
	# Source/dest IPs
	if [ "$ipv" = "ipv4" ]; then
		[ -n "$src_ip" ] && match="$match ip saddr $src_ip"
		[ -n "$dest_ip" ] && match="$match ip daddr $dest_ip"
	else
		[ -n "$src_ip" ] && match="$match ip6 saddr $src_ip"
		[ -n "$dest_ip" ] && match="$match ip6 daddr $dest_ip"
	fi
	
	# Interface
	[ -n "$src_dev" ] && match="$match iifname \"$src_dev\""
	
	# Ports (for TCP/UDP)
	# Convert UCI port syntax to nftables syntax:
	#   comma-separated: "80,443" -> "{ 80, 443 }"
	#   colon range: "1024:2048" -> "1024-2048"
	if [ "$proto" = "tcp" ] || [ "$proto" = "udp" ]; then
		if [ -n "$src_port" ]; then
			local nft_src_port="$(echo "$src_port" | sed 's/:/-/g')"
			echo "$nft_src_port" | grep -q ',' && nft_src_port="{ $nft_src_port }"
			match="$match $proto sport $nft_src_port"
		fi
		if [ -n "$dest_port" ]; then
			local nft_dest_port="$(echo "$dest_port" | sed 's/:/-/g')"
			echo "$nft_dest_port" | grep -q ',' && nft_dest_port="{ $nft_dest_port }"
			match="$match $proto dport $nft_dest_port"
		fi
	fi
	
	# External set matching
	if [ -n "$nft_set" ]; then
		if [ "$ipv" = "ipv6" ]; then
			match="$match ip6 daddr @$nft_set"
		else
			match="$match ip daddr @$nft_set"
		fi
	fi
	
	# Mark check - only process unmarked traffic
	match="$match meta mark and $MMX_MASK == 0"

	if [ "$rule_policy" -eq 1 ]; then
		# Create rule chain if not exists (flush handled by multiwan_nft_set_user_rules_nft)
		if ! $NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_rule_$rule" &>/dev/null; then
			$NFT add chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_rule_$rule" || {
				LOG warn "nft: failed to create user rule chain multiwan_nft_rule_$rule"
				return 1
			}
		fi
		
		if [ "$sticky" -eq 1 ]; then
			config_foreach multiwan_nft_set_sticky_nft interface "$rule" "$ipv" "multiwan_nft_policy_$use_policy"
		fi
		
		# Jump to policy
		multiwan_nft_nft_add_rule "multiwan_nft_rule_$rule" \
			meta mark and $MMX_MASK == 0 jump "multiwan_nft_policy_$use_policy" || return 1
		
		# Update sticky set
		if [ "$sticky" -eq 1 ]; then
			if [ "$ipv" = "ipv4" ]; then
				multiwan_nft_nft_add_rule "multiwan_nft_rule_$rule" \
					"update @multiwan_nft_sticky_ipv4_$rule { ip saddr . meta mark }" || return 1
			else
				multiwan_nft_nft_add_rule "multiwan_nft_rule_$rule" \
					"update @multiwan_nft_sticky_ipv6_$rule { ip6 saddr . meta mark }" || return 1
			fi
		fi
		
		# Add rule to multiwan_nft_rules chain (for new connections)
		if ! multiwan_nft_nft_add_rule multiwan_nft_rules $match jump "multiwan_nft_rule_$rule" \
			comment "\"$rule\""; then
			LOG warn "Failed to add rule '$rule' to multiwan_nft_rules chain"
		fi
		
		# Add sticky refresh for ALL matching traffic (even established)
		# This runs regardless of mark state to keep sticky timeout fresh
		if [ "$sticky" -eq 1 ]; then
			# Build base match without mark==0 check
			local sticky_match=""
			[ -n "$proto" ] && [ "$proto" != "all" ] && sticky_match="$sticky_match meta l4proto $proto"
			[ -n "$dest_port" ] && sticky_match="$sticky_match $proto dport $nft_dest_port"
			# Only update if packet has valid tracking info (removed impossible mark!=0 check)
			
			if [ "$ipv" = "ipv4" ]; then
				multiwan_nft_nft_add_rule multiwan_nft_rules $sticky_match \
					"update @multiwan_nft_sticky_ipv4_$rule { ip saddr . meta mark }" \
					comment "\"sticky_refresh_$rule\""
			else
				multiwan_nft_nft_add_rule multiwan_nft_rules $sticky_match \
					"update @multiwan_nft_sticky_ipv6_$rule { ip6 saddr . meta mark }" \
					comment "\"sticky_refresh_$rule\""
			fi
		fi
	else
		# Simple mark rule - no policy chain needed
		if ! multiwan_nft_nft_add_rule multiwan_nft_rules $match meta mark set meta mark and $MMX_INVMASK or $action_mark \
			comment "\"$rule\""; then
			LOG warn "Failed to add simple mark rule '$rule' to multiwan_nft_rules chain"
		fi
	fi
	
	# Flush matching conntrack entries so the rule takes effect immediately
	# on existing connections. Only flush when specific (non-broad) IPs are
	# configured to avoid disrupting all connections.
	if command -v conntrack >/dev/null 2>&1; then
		local src_broad=0 dest_broad=0
		multiwan_nft_is_broad_address "$src_ip" && src_broad=1
		multiwan_nft_is_broad_address "$dest_ip" && dest_broad=1

		if [ "$src_broad" -eq 0 ] && [ "$dest_broad" -eq 0 ]; then
			conntrack -D -s "$src_ip" -d "$dest_ip" 2>/dev/null && \
				LOG notice "Flushed conntrack entries for rule $rule (src=$src_ip dst=$dest_ip)"
		elif [ "$src_broad" -eq 0 ]; then
			conntrack -D -s "$src_ip" 2>/dev/null && \
				LOG notice "Flushed conntrack entries for rule $rule (src=$src_ip, dest broad)"
		elif [ "$dest_broad" -eq 0 ]; then
			conntrack -D -d "$dest_ip" 2>/dev/null && \
				LOG notice "Flushed conntrack entries for rule $rule (dst=$dest_ip, src broad)"
		else
			LOG debug "Skipping conntrack flush for rule $rule: both endpoints broad"
		fi
	fi

	# Logging rule if enabled
	if [ "$global_logging" = "1" ] && [ "$rule_logging" = "1" ]; then
		multiwan_nft_nft_add_rule multiwan_nft_rules $match \
			log prefix "\"MULTIWAN_NFT($rule)\"" level $loglevel
	fi
}

multiwan_nft_set_user_iface_rules_nft()
{
	local iface device is_src_iface
	iface=$1
	device=$2

	[ -z "$device" ] && {
		LOG notice "set_user_iface_rules_nft: could not find device for iface $iface"
		return
	}

	# Check if any rules reference this interface
	$NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_rules 2>/dev/null | grep -q "iifname \"$device\"" && return

	is_src_iface=0
	iface_rule()
	{
		local src_iface
		config_get src_iface "$1" src_iface
		[ "$src_iface" = "$iface" ] && is_src_iface=1
	}
	config_foreach iface_rule rule
	[ "$is_src_iface" -eq 1 ] && multiwan_nft_set_user_rules_nft
}

multiwan_nft_set_user_rules_nft()
{
	multiwan_nft_nft_init_table || return 1
	multiwan_nft_nft_create_chain "multiwan_nft_rules" || return 1

	# Flush all existing per-rule chains before rebuilding
	# This prevents duplicate entries on rebuild (e.g. after interface bounce)
	# Must happen BEFORE the ipv loop so ipv4 rules aren't wiped by ipv6 pass
	local existing_chain
	for existing_chain in $($NFT list chains $NFT_FAMILY $NFT_TABLE 2>/dev/null | \
		grep -oE 'chain multiwan_nft_rule_[^ ]+' | sed 's/chain //'); do
		$NFT flush chain $NFT_FAMILY $NFT_TABLE "$existing_chain" 2>/dev/null || \
			LOG warn "nft: failed to flush existing user rule chain $existing_chain"
	done

	for ipv in ipv4 ipv6; do
		[ "$ipv" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && continue
		
		# Tracking pings are naturally protected by ip rules priority 1000 ("oif pppoe-wan")
		# Bypassing echo-requests entirely breaks local testing and NCSI failover.
		config_foreach multiwan_nft_set_user_nft_rule rule "$ipv"
	done

	multiwan_nft_nft_dump "set_user_rules_nft"
}

multiwan_nft_interface_hotplug_shutdown()
{
	local interface status device ifdown
	interface="$1"
	ifdown="$2"
	[ -f $MULTIWAN_NFT_TRACK_STATUS_DIR/$interface/STATUS ] && {
		status=$(cat $MULTIWAN_NFT_TRACK_STATUS_DIR/$interface/STATUS)
	}

	[ "$status" != "online" ] && [ "$ifdown" != 1 ] && return

	if [ "$ifdown" = 1 ]; then
		env -i ACTION=ifdown \
			INTERFACE=$interface \
			DEVICE=$device \
			sh /etc/hotplug.d/iface/15-multiwan-nft
	else
		[ "$status" = "online" ] && {
			env -i MULTIWAN_NFT_SHUTDOWN="1" \
				ACTION="disconnected" \
				INTERFACE="$interface" \
				DEVICE="$device" /sbin/hotplug-call iface
		}
	fi

}

multiwan_nft_interface_shutdown()
{
	multiwan_nft_interface_hotplug_shutdown $1
	multiwan_nft_track_clean $1
}

multiwan_nft_ifup()
{
	local interface=$1
	local caller=$2

	local up l3_device status true_iface

	if [ "${caller}" = "cmd" ]; then
		# It is not necessary to obtain a lock here, because it is obtained in the hotplug
		# script, but we still want to do the check to print a useful error message
		/etc/init.d/multiwan-nft running || {
			echo 'The service multiwan_nft is global disabled.'
			echo 'Please execute "/etc/init.d/multiwan-nft start" first.'
			exit 1
		}
		config_load 'multiwan-nft'
	fi
	multiwan_nft_get_true_iface true_iface $interface
	status=$(ubus -S call network.interface.$true_iface status)

	[ -n "$status" ] && {
		json_load "$status"
		json_get_vars up l3_device
	}
	hotplug_startup()
	{
		env -i MULTIWAN_NFT_STARTUP=$caller ACTION=ifup \
		    INTERFACE=$interface DEVICE=$l3_device \
		    sh /etc/hotplug.d/iface/15-multiwan-nft
	}

	if [ "$up" != "1" ] || [ -z "$l3_device" ]; then
		return
	fi

	if [ "${caller}" = "init" ]; then
		# During service start the hotplug script intentionally bypasses
		# procd_lock, so run interface setup serially here. This prevents two
		# online WANs from mutating nft/ip rules and route tables at once.
		hotplug_startup
	else
		hotplug_startup
	fi

}

multiwan_nft_set_iface_hotplug_state() {
	local iface=$1
	local state=$2

	[ -d "$MULTIWAN_NFT_STATUS_DIR/iface_state" ] || mkdir -p "$MULTIWAN_NFT_STATUS_DIR/iface_state"
	echo "$state" > "$MULTIWAN_NFT_STATUS_DIR/iface_state/$iface"
}

multiwan_nft_get_iface_hotplug_state() {
	local iface=$1

	cat "$MULTIWAN_NFT_STATUS_DIR/iface_state/$iface" 2>/dev/null || echo "offline"
}

multiwan_nft_report_iface_status()
{
	local device result tracking IP error

	multiwan_nft_get_iface_id id "$1"
	network_get_device device "$1"
	config_get enabled "$1" enabled 0
	config_get family "$1" family ipv4

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	else
		IP="$IP6"
	fi
	if [ -z "$id" ] || [ -z "$device" ]; then
		result="offline"
	else
		error=0
		# Check iif rule at pref id+1000: must match device and lookup table (bit 0)
		$IP rule list | grep -q "^$((id+1000)):.*iif $device.*lookup $id" ||
			error=$((error+1))
		# Check oif rule at pref id+1000: must match device and lookup table (bit 1)
		$IP rule list | grep -q "^$((id+1000)):.*oif $device.*lookup $id" ||
			error=$((error+2))
		# Check fwmark lookup rule at pref id+2000 (bit 2)
		[ -n "$($IP rule | awk -v pref="$((id+2000)):" '$1 == pref')" ] ||
			error=$((error+4))
		# Check fwmark unreachable rule at pref id+3000 (bit 3)
		[ -n "$($IP rule | awk -v pref="$((id+3000)):" '$1 == pref')" ] ||
			error=$((error+8))
		# Check nft interface chain (bit 4)
		$NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_iface_in_$1" &>/dev/null ||
			error=$((error+16))
		# Check default route in interface table (bit 5)
		[ -n "$($IP route list table $id default dev $device 2> /dev/null)" ] ||
			error=$((error+32))
	fi

	if [ "$result" = "offline" ]; then
		:
	elif [ "$error" -eq 0 ]; then
		online=$(get_online_time "$1")
		network_get_uptime uptime "$1"
		online="$(printf '%02dh:%02dm:%02ds\n' $((online/3600)) $((online%3600/60)) $((online%60)))"
		uptime="$(printf '%02dh:%02dm:%02ds\n' $((uptime/3600)) $((uptime%3600/60)) $((uptime%60)))"
		result="$(multiwan_nft_get_iface_hotplug_state $1) $online, uptime $uptime"
	elif [ "$error" -gt 0 ] && [ "$error" -ne 63 ]; then
		result="error (${error})"
	elif [ "$enabled" = "1" ]; then
		result="offline"
	else
		result="disabled"
	fi

	tracking="$(multiwan_nft_get_track_status $1)"
	echo " interface $1 is $result and tracking is $tracking"
}

multiwan_nft_report_policies()
{
	local policy="$1"
	local percent total_weight weight iface

	# Parse policy chain from nft output
	local chain_output=$($NFT list chain $NFT_FAMILY $NFT_TABLE "$policy" 2>/dev/null)
	
	# Extract comments from nft output - format: comment "iface weight total_weight"
	# Collect all unique interfaces and their weights first (#17: fix fragile parsing)
	local all_comments
	all_comments=$(echo "$chain_output" | sed -n 's/.*comment "\([^"]*\)".*/\1/p')
	
	# Skip special entries (blackhole, unreachable, default, out)
	local member_lines
	member_lines=$(echo "$all_comments" | grep -v -E '^(blackhole|unreachable|default|out )' | grep -v '^$')
	
	# Calculate actual total weight from all member weights
	total_weight=0
	local line
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		weight=$(echo "$line" | awk '{print $2}')
		[ -n "${weight##*[!0-9]*}" ] && total_weight=$((total_weight + weight))
	done <<EOF
$member_lines
EOF

	# Validate total_weight is numeric and greater than 0
	if [ -n "$total_weight" ] && [ "$total_weight" -gt 0 ] 2>/dev/null; then
		local seen_ifaces=""
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			iface=$(echo "$line" | awk '{print $1}')
			weight=$(echo "$line" | awk '{print $2}')
			# Skip duplicates (ipv4 + ipv6 entries for same interface)
			echo "$seen_ifaces" | grep -q " $iface " && continue
			seen_ifaces="$seen_ifaces $iface "
			percent=$((weight*100/total_weight))
			echo " $iface ($percent%)"
		done <<EOF
$member_lines
EOF
	else
		# Single interface or last resort
		local single
		single=$(echo "$all_comments" | head -1 | awk '{print $1}')
		echo " ${single:-unknown}"
	fi
}

multiwan_nft_report_policies_v4()
{
	local policy

	for policy in $($NFT list table $NFT_FAMILY $NFT_TABLE 2>/dev/null | grep -oE 'chain multiwan_nft_policy_[^ ]+' | sed 's/chain //'); do
		echo "${policy#multiwan_nft_policy_}:"
		multiwan_nft_report_policies "$policy"
	done
}

multiwan_nft_report_policies_v6()
{
	# IPv6 policies are in the same table (inet family handles both)
	multiwan_nft_report_policies_v4
}

multiwan_nft_report_connected_v4()
{
	if $NFT list set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v4 &>/dev/null; then
		$NFT list set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?'
	fi
}

multiwan_nft_report_connected_v6()
{
	if $NFT list set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v6 &>/dev/null; then
		$NFT list set $NFT_FAMILY $NFT_TABLE multiwan_nft_connected_v6 | \
			grep -oE '([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}(/[0-9]+)?|::/[0-9]+'
	fi
}

multiwan_nft_report_rules_v4()
{
	if $NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_rules &>/dev/null; then
		$NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_rules | \
			grep -E 'jump|meta mark set' | \
			sed 's/.*jump multiwan_nft_policy_/- /' | \
			sed 's/.*jump multiwan_nft_rule_/S /' | \
			sed 's/.*meta mark set.*/- default/'
	fi
}

multiwan_nft_report_rules_v6()
{
	# IPv6 rules are in the same table
	multiwan_nft_report_rules_v4
}

# Returns 0 if address is a broad/default address that should not trigger
# conntrack flush. Used to skip flush for catch-all rules like 0.0.0.0/0.
multiwan_nft_is_broad_address() {
	case "$1" in
		""|"0.0.0.0/0"|"0.0.0.0"|"::/0"|"::") return 0 ;;
		*) return 1 ;;
	esac
}

# Idempotent route replace: skip if exact route exists, handle "File exists"
# gracefully. Only for add/replace paths — delete handling is separate.
# Args: $1=ip_cmd, $2=table_id, $3=route_line (single string, expanded for ip cmd)
multiwan_nft_route_replace_idempotent() {
	local ip_cmd="$1" tid="$2" route_line="$3"

	# Skip if exact route already present
	$ip_cmd route list table "$tid" 2>/dev/null | grep -Fxq "$route_line" && return 0

	# Try replace (intentionally expand $route_line for ip command)
	# shellcheck disable=SC2086
	local err
	err=$($ip_cmd route replace table "$tid" $route_line 2>&1)
	local rv=$?

	[ "$rv" -eq 0 ] && return 0

	# Handle "File exists" — verify route is present
	case "$err" in
		*"File exists"*)
			$ip_cmd route list table "$tid" 2>/dev/null | grep -Fxq "$route_line" && return 0
			;;
	esac

	LOG warn "route replace failed: table $tid route '$route_line': $err"
	return 1
}

# Flush conntrack entries marked with a specific interface's fwmark.
# This is an OPTIMIZATION — the default route removal in
# multiwan_nft_delete_iface_default_route() is what actually forces failover.
# This flush just speeds up the process by killing stale entries immediately
# instead of waiting for each connection to hit the unreachable rule.
#
# Uses conntrack-tools if available. If not installed, failover still works
# via the unreachable ip rule (pref 3xxx) once the default route is removed.
multiwan_nft_flush_conntrack_iface()
{
	local iface="$1"
	local id mark_val

	multiwan_nft_get_iface_id id "$iface"
	[ -n "$id" ] || return 0

	mark_val=$(multiwan_nft_id2mask id MMX_MASK)

	if command -v conntrack >/dev/null 2>&1; then
		if multiwan_nft_debug_enabled; then
			local count
			count=$(conntrack -D -m "$mark_val/$MMX_MASK" 2>/dev/null | grep -c "flow" 2>/dev/null)
			LOG notice "Flushed conntrack entries for interface $iface (mark=$mark_val/$MMX_MASK, entries=${count:-0})"
		else
			conntrack -D -m "$mark_val/$MMX_MASK" >/dev/null 2>&1
			LOG notice "Flushed conntrack entries for interface $iface (mark=$mark_val/$MMX_MASK)"
		fi
	else
		LOG notice "conntrack tool not found, skipping targeted flush for $iface (failover via route removal)"
	fi
}

multiwan_nft_delete_iface_main_route()
{
	local iface="$1"
	local device="$2"
	local family IP route_line routes deleted

	config_get family "$iface" family ipv4
	[ -n "$device" ] || network_get_device device "$iface"
	[ -n "$device" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return 0
	fi

	routes="$($IP route show table main 2>/dev/null)"
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		[ "${route_line#default}" = "$route_line" ] && continue
		case " $route_line " in
			*" dev $device "*)
				# shellcheck disable=SC2086
				$IP route del table main $route_line 2>/dev/null && {
					deleted=1
					LOG notice "Removed main-table default route for $iface: $route_line"
				}
				;;
		esac
	done <<EOF
$routes
EOF

	if [ "$deleted" = "1" ]; then
		$IP route flush cache 2>/dev/null
		LOG debug "Flushed route cache after removing main-table default route for $iface"
	fi
}

multiwan_nft_restore_iface_default_route()
{
	local iface="$1"
	local device="$2"
	local table="$3"
	local label="$4"
	local family true_iface status metric IP
	local route_keys route_key target mask nexthop route_metric restored

	[ -n "$table" ] || return 0
	[ -n "$label" ] || label="table $table"

	config_get family "$iface" family ipv4
	[ -n "$device" ] || network_get_device device "$iface"
	[ -n "$device" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return 0
	fi

	multiwan_nft_get_true_iface true_iface "$iface"
	status="$(ubus -S call "network.interface.$true_iface" status 2>/dev/null)"
	if [ -z "$status" ]; then
		LOG warn "Could not restore $label default route for $iface: ubus status for $true_iface is empty"
		return 0
	fi

	json_load "$status" || {
		LOG warn "Could not restore $label default route for $iface: ubus status for $true_iface is invalid"
		return 0
	}
	json_get_var metric metric
	[ -n "$metric" ] || metric=0

	json_select route 2>/dev/null || {
		LOG warn "Could not restore $label default route for $iface: ubus status for $true_iface has no route data"
		return 0
	}
	json_get_keys route_keys
	for route_key in $route_keys; do
		target=
		mask=
		nexthop=
		route_metric=
		json_select "$route_key" 2>/dev/null || continue
		json_get_var target target
		json_get_var mask mask
		json_get_var nexthop nexthop
		json_get_var route_metric metric
		json_select ..

		[ -n "$nexthop" ] || continue
		[ -n "$route_metric" ] || route_metric="$metric"
		[ -n "$route_metric" ] || route_metric=0

		if [ "$family" = "ipv4" ]; then
			[ "$target" = "0.0.0.0" ] && [ "${mask:-0}" = "0" ] || continue
		else
			[ "$target" = "::" ] && [ "${mask:-0}" = "0" ] || continue
		fi

		$IP route replace table "$table" default via "$nexthop" dev "$device" proto static metric "$route_metric" 2>/dev/null && {
			restored=1
			LOG notice "Restored $label default route for $iface via $nexthop dev $device metric $route_metric"
		}
	done
	json_select ..

	if [ "$restored" = "1" ]; then
		$IP route flush cache 2>/dev/null
		LOG debug "Flushed route cache after restoring $label default route for $iface"
	else
		LOG notice "No $label default route restored for $iface ($device)"
	fi
}

multiwan_nft_restore_iface_main_route()
{
	multiwan_nft_restore_iface_default_route "$1" "$2" "main" "main-table"
}

multiwan_nft_restore_iface_table_default_route()
{
	local id

	multiwan_nft_get_iface_id id "$1"
	[ -n "$id" ] || return 0
	multiwan_nft_restore_iface_default_route "$1" "$2" "$id" "table $id"
}

# Remove the default route from an interface's routing table.
# Called on 'disconnected' to prevent traffic from routing through a dead
# upstream. The full route table is preserved — only the default route is
# removed so that the unreachable ip rule (pref 3xxx) takes effect for
# traffic still carrying this interface's fwmark.
multiwan_nft_delete_iface_default_route()
{
	local id family IP

	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"
	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	$IP route del default table "$id" 2>/dev/null && \
		LOG notice "Removed default route from table $id for interface $1"
}

multiwan_nft_flush_conntrack()
{
	local interface="$1"
	local action="$2"

	handle_flush() {
		local flush_conntrack="$1"
		local action="$2"

		if [ "$action" = "$flush_conntrack" ]; then
			if [ "$action" = "ifup" ] || [ "$action" = "connected" ]; then
				# For failback, break existing connections routed on backup interfaces
				# so they can be re-routed over the interface that just came up.
				# NOTE: This is safe because the multiwan_qos ct_save_dscp chains no longer
				# use "ct state established,related return" — DSCP is re-saved on the
				# first egress packet after the flush regardless of conntrack state.
				if command -v conntrack >/dev/null 2>&1; then
					flush_other() {
						[ "$1" != "$interface" ] && multiwan_nft_flush_conntrack_iface "$1"
					}
					config_foreach flush_other interface
					# NOTE: Do NOT flush $MMX_DEFAULT conntrack entries here.
					# $MMX_DEFAULT matches router-originated traffic (DNS, DoH,
					# NTP) which should not be disrupted during failback.
					# The per-interface flush_other loop above handles re-routing.
					LOG info "Mwan3 failback connection tracking flushed on action '$action'"
				else
					echo f > "${CONNTRACK_FILE}"
					LOG info "Global connection tracking flushed on action '$action'"
				fi
			else
				# For ifdown/disconnected, just flush the interface that went down
				multiwan_nft_flush_conntrack_iface "$interface"
				LOG info "Connection tracking flushed for interface '$interface' on action '$action'"
			fi
		fi
	}

	if [ -e "$CONNTRACK_FILE" ]; then
		config_list_foreach "$interface" flush_conntrack handle_flush "$action"
	fi
}

multiwan_nft_track_clean()
{
	rm -rf "${MULTIWAN_NFT_STATUS_DIR:?}/${1}" &> /dev/null
	rmdir --ignore-fail-on-non-empty "$MULTIWAN_NFT_STATUS_DIR"
}
