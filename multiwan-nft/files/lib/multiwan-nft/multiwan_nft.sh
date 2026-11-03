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

multiwan_nft_nft_write_batch()
{
	printf "$@" >> "$NFT_BATCH_FILE" || { NFT_BATCH_FAILED=1; return 1; }
}

# nft helper: ensure table exists (for queries only)
multiwan_nft_nft_init_table()
{
	$NFT list table $NFT_FAMILY $NFT_TABLE &>/dev/null && return 0
	if [ -n "$NFT_BATCH_FILE" ]; then
		LOG warn "nft: policy transaction requires existing table $NFT_FAMILY $NFT_TABLE"
		return 1
	fi
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
	if [ -n "$NFT_BATCH_FILE" ]; then
		multiwan_nft_nft_write_batch 'add element %s %s %s { %s }\n' "$NFT_FAMILY" "$NFT_TABLE" "$setname" "$element"
		return $?
	fi
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
	if [ -n "$NFT_BATCH_FILE" ]; then
		if $NFT list set $NFT_FAMILY $NFT_TABLE "$setname" &>/dev/null; then
			multiwan_nft_nft_write_batch 'flush set %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$setname"
		else
			multiwan_nft_nft_write_batch 'add set %s %s %s { %s; %s }\n' "$NFT_FAMILY" "$NFT_TABLE" "$setname" "$settype" "${setflags:+$setflags;}"
		fi
		return $?
	fi
	
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

	if [ -n "$NFT_BATCH_FILE" ]; then
		if $NFT list chain $NFT_FAMILY $NFT_TABLE "$chain" &>/dev/null; then
			multiwan_nft_nft_write_batch 'flush chain %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$chain"
		elif [ -n "$chaintype" ]; then
			multiwan_nft_nft_write_batch 'add chain %s %s %s { %s; }\n' "$NFT_FAMILY" "$NFT_TABLE" "$chain" "$chaintype"
		else
			multiwan_nft_nft_write_batch 'add chain %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$chain"
		fi
		return $?
	fi
	
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
	if [ -n "$NFT_BATCH_FILE" ]; then
		multiwan_nft_nft_write_batch 'add rule %s %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$chain" "$*"
		return $?
	fi
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
	if [ -n "$NFT_BATCH_FILE" ]; then
		multiwan_nft_nft_write_batch 'insert rule %s %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$chain" "$*"
		return $?
	fi
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
${1:-}

table $NFT_FAMILY $NFT_TABLE {
	# Sets for network matching
	set multiwan_nft_custom_v4 {
		type ipv4_addr
		flags interval
		auto-merge
	}
	
	set multiwan_nft_connected_v4 {
		type ipv4_addr
		flags interval
		auto-merge
	}
	
	set multiwan_nft_dynamic_v4 {
		type ipv4_addr
		flags interval
		auto-merge
	}
"
	
	# Add IPv6 sets if supported
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}
	set multiwan_nft_custom_v6 {
		type ipv6_addr
		flags interval
		auto-merge
	}
	
	set multiwan_nft_connected_v6 {
		type ipv6_addr
		flags interval
		auto-merge
	}
	
	set multiwan_nft_dynamic_v6 {
		type ipv6_addr
		flags interval
		auto-merge
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
	chain multiwan_nft_sticky_refresh {
	}
	chain multiwan_nft_save {
		meta mark and $MMX_MASK == $MMX_DEFAULT ct mark and $MMX_MASK != $MMX_DEFAULT ct mark set ct mark and $MMX_INVMASK or $MMX_DEFAULT
		meta mark and $MMX_MASK == $MMX_BLACKHOLE ct mark and $MMX_MASK != $MMX_BLACKHOLE ct mark set ct mark and $MMX_INVMASK or $MMX_BLACKHOLE
		meta mark and $MMX_MASK == $MMX_UNREACHABLE ct mark and $MMX_MASK != $MMX_UNREACHABLE ct mark set ct mark and $MMX_INVMASK or $MMX_UNREACHABLE
	}
	chain multiwan_nft_restore {
		ct mark and $MMX_MASK == $MMX_DEFAULT meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return
		ct mark and $MMX_MASK == $MMX_BLACKHOLE meta mark set meta mark and $MMX_INVMASK or $MMX_BLACKHOLE return
		ct mark and $MMX_MASK == $MMX_UNREACHABLE meta mark set meta mark and $MMX_INVMASK or $MMX_UNREACHABLE return
	}
	
	# Main hook chain with common logic
	chain multiwan_nft_hook {
"
	# ICMPv6 exemption
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}		icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, nd-redirect } return
"
	fi
	
	buf="${buf}		# Keep multicast, reserved IPv4 and limited broadcast on the main-stack path.
		ip daddr 224.0.0.0/3 return
		ip6 daddr ff00::/8 return
		
		# Keep connection routing decisions, including existing main-table NAT flows.
		meta mark and $MMX_MASK == 0 jump multiwan_nft_restore
		
		# Jump to interface input chain
		meta mark and $MMX_MASK == 0 jump multiwan_nft_ifaces_in
		
		# Unmarked connected traffic bypasses policy selection.
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
	
	buf="${buf}		# Router-owned addresses need no WAN selection, including peer-only prefixes.
		meta mark and $MMX_MASK == 0 fib daddr type local meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT
		# Jump to user rules
		meta mark and $MMX_MASK == 0 jump multiwan_nft_rules
		ct direction original jump multiwan_nft_sticky_refresh
		jump multiwan_nft_save
		# Save incoming WAN identity before connected destinations use main routing.
		meta nfproto ipv4 jump multiwan_nft_custom_v4
		meta nfproto ipv4 jump multiwan_nft_connected_v4
		meta nfproto ipv4 jump multiwan_nft_dynamic_v4
"
	if [ "$NO_IPV6" -eq 0 ]; then
		buf="${buf}		meta nfproto ipv6 jump multiwan_nft_custom_v6
		meta nfproto ipv6 jump multiwan_nft_connected_v6
		meta nfproto ipv6 jump multiwan_nft_dynamic_v6
"
	fi
	buf="${buf}
		
		# Per-interface save rules retain WAN identity before connected bypass.
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
	
	printf '%s\n%s\n' "$buf" "${2:-}"
}

# Load the base ruleset atomically
multiwan_nft_load_base_ruleset()
{
	local ruleset definition name elements reset="" restore=""
	if ! definition="$($NFT -t list table "$NFT_FAMILY" "$NFT_TABLE" 2>/dev/null)"; then
		$NFT add table "$NFT_FAMILY" "$NFT_TABLE" || return 1
		definition="$($NFT -t list table "$NFT_FAMILY" "$NFT_TABLE")" || return 1
	fi
	# Flush retains old set flags. Recreate derived sets atomically, retaining cached data.
	for name in $(printf '%s\n' "$definition" | awk '$1 == "set" && $2 ~ /^multiwan_nft_(custom|connected)_v[46]$/ { print $2 }'); do
		case "$name" in *_v6) [ "$NO_IPV6" -eq 0 ] || continue ;; esac
		definition="$($NFT -s list set "$NFT_FAMILY" "$NFT_TABLE" "$name")" || return 1
		elements="$(printf '%s\n' "$definition" | awk '
			/^[[:space:]]*elements[[:space:]]*=/ { sub(/^[[:space:]]*elements[[:space:]]*=[[:space:]]*/, ""); copying=1 }
			copying { print; if (index($0, "}")) exit }
		')" || return 1
		reset="$reset
delete set $NFT_FAMILY $NFT_TABLE $name"
		[ -z "$elements" ] || restore="$restore
add element $NFT_FAMILY $NFT_TABLE $name $elements"
	done
	ruleset="$(multiwan_nft_generate_base_ruleset "$reset" "$restore")" || return 1
	
	printf '%s\n' "$ruleset" > "${MULTIWAN_NFT_STATUS_NFT_LOG_DIR}/base-ruleset.nft"
	
	if printf '%s\n' "$ruleset" | $NFT -f -; then
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
		multiwan_nft_get_device device "$1"
		[ -z "$device" ] && return
		config_get_bool enabled "$1" enabled 0
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
	local _tid route_line route_device route_family entry curr_table IP nhid nexthop
	route_line=$2
	route_family=$3
	route_device=$(echo "$route_line" | sed -ne "s/.*dev \([^ ]*\).*/\1/p")
	unset "$1"
	if [ -z "$route_device" ]; then
		nhid=$(printf '%s\n' "$route_line" | sed -n 's/.* nhid \([0-9][0-9]*\)\( .*\)\?$/\1/p')
		if [ -n "$nhid" ]; then
			case "$route_family" in ipv4) IP="$IP4" ;; ipv6) IP="$IP6" ;; *) return 1 ;; esac
			# ID-only dumps still need the referenced object's device for WAN ownership.
			nexthop="$(LC_ALL=C $IP nexthop get id "$nhid" 2>&1)" || {
				LOG error "Could not resolve nexthop $nhid: $nexthop"
				return 1
			}
			route_device=$(printf '%s\n' "$nexthop" | sed -n 's/.* dev \([^ ]*\).*/\1/p')
		fi
	fi
	[ -n "$route_device" ] || return 0

	curr_table=$(eval "echo \"\$multiwan_nft_dev_tbl_${route_family}\"")
	for entry in $curr_table; do
		if [ "${entry%%=*}" = "$route_device" ]; then
			_tid=${entry##*=}
			export "$1=$_tid"
			return
		fi
	done
	return 0
}

# multiwan_nft_count_one_bits() is defined in common.sh — removed duplicate here (#16)

multiwan_nft_get_iface_id()
{
	local _tmp
	[ -z "$multiwan_nft_iface_tbl" ] && multiwan_nft_update_iface_to_table
	_tmp="${multiwan_nft_iface_tbl##* ${2}=}"
	_tmp=${_tmp%% *}
	case "$_tmp" in ''|*[!0-9]*) _tmp= ;; *)
		[ "$_tmp" -le "${MULTIWAN_NFT_INTERFACE_MAX:-4294967295}" ] || _tmp= ;;
	esac
	export "$1=$_tmp"
}

multiwan_nft_replace_network_set()
{
	local setname="$1" family="$2" IP pattern table routes networks="" network batch_file error separator=""
	shift 2
	case "$family" in ipv4) IP="$IP4"; pattern="$IPv4_REGEX" ;; ipv6) IP="$IP6"; pattern="$IPv6_REGEX" ;; *) return 1 ;; esac
	for table in "$@"; do
		routes="$(multiwan_nft_read_route_table "$IP" "$table")" || return 1
		networks="$networks$(printf '%s\n' "$routes" | awk '{print $1}' | grep -E "^($pattern)(/[0-9]+)?$")
"
	done
	batch_file=$(mktemp /tmp/multiwan-nft-networks.XXXXXX) || return 1
	local NFT_BATCH_FILE="$batch_file" NFT_BATCH_FAILED=0
	multiwan_nft_nft_write_batch 'flush set %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$setname"
	for network in $(printf '%s' "$networks" | sort -u); do
		[ -n "$separator" ] || multiwan_nft_nft_write_batch 'add element %s %s %s { ' "$NFT_FAMILY" "$NFT_TABLE" "$setname"
		multiwan_nft_nft_write_batch '%s%s' "$separator" "$network"
		separator=', '
	done
	[ -z "$separator" ] || multiwan_nft_nft_write_batch ' }\n'
	if [ "$NFT_BATCH_FAILED" -ne 0 ]; then rm -f "$batch_file"; return 1; fi
	error="$($NFT -f "$batch_file" 2>&1)"
	local result=$?
	rm -f "$batch_file"
	[ "$result" -eq 0 ] || { LOG error "Network set $setname was preserved after update failure: $error"; return 1; }
}

multiwan_nft_set_custom_ipset()
{
	local tables=""
	multiwan_nft_collect_route_table() { tables="$tables $1"; }
	config_list_foreach globals rt_table_lookup multiwan_nft_collect_route_table
	multiwan_nft_replace_network_set multiwan_nft_custom_v4 ipv4 $tables || return 1
	[ "$NO_IPV6" -ne 0 ] || multiwan_nft_replace_network_set multiwan_nft_custom_v6 ipv6 $tables
}

multiwan_nft_set_connected_ipv4()
{
	multiwan_nft_replace_network_set multiwan_nft_connected_v4 ipv4 main
}

multiwan_nft_set_connected_ipv6()
{
	[ "$NO_IPV6" -eq 0 ] || return 0
	multiwan_nft_replace_network_set multiwan_nft_connected_v6 ipv6 main
}
multiwan_nft_set_general_rules()
{
	local IP failed=0

	for IP in "$IP4" "$IP6"; do
		[ "$IP" = "$IP6" ] && [ "$NO_IPV6" -ne 0 ] && continue
		RULE_NO=$((MM_BLACKHOLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_BLACKHOLE/$MMX_MASK blackhole || {
				LOG warn "rule: failed to add global blackhole rule pref $RULE_NO"
				failed=1
			}
		fi

		RULE_NO=$((MM_UNREACHABLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_UNREACHABLE/$MMX_MASK unreachable || {
				LOG warn "rule: failed to add global unreachable rule pref $RULE_NO"
				failed=1
			}
		fi
	done
	[ "$failed" -eq 0 ]
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
	local id family iface device family_guard
	iface="$1"
	device="$2"

	config_get family "$iface" family ipv4
	multiwan_nft_get_iface_id id "$iface"

	[ -n "$id" ] || return 0
	[ "$family" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return
	family_guard="meta nfproto $family"

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
		$family_guard iifname "$device" meta mark and $MMX_MASK == 0 \
		meta mark set meta mark and $MMX_INVMASK or $mark_val comment "\"$iface\"" || return 1

	# Add jump from multiwan_nft_ifaces_in if not present
	if ! $NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_ifaces_in 2>/dev/null | \
		grep -q "jump multiwan_nft_iface_in_$iface"; then
		multiwan_nft_nft_add_rule multiwan_nft_ifaces_in \
			$family_guard meta mark and $MMX_MASK == 0 jump "multiwan_nft_iface_in_$iface" || return 1
		LOG debug "create_iface_nft: multiwan_nft_iface_in_$iface added"
	else
		LOG debug "create_iface_nft: multiwan_nft_iface_in_$iface already present"
	fi

	# Incoming WAN marks identify reply routes, not client sticky affinity.
	multiwan_nft_nft_insert_rule multiwan_nft_sticky_refresh \
		$family_guard iifname "$device" return comment "\"sticky_ingress_$iface\"" || return 1

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

	# Constant assignments preserve other skb mark bits on older nft releases.
	multiwan_nft_nft_add_rule multiwan_nft_restore \
		ct mark and $MMX_MASK == $mark_val \
		meta mark set meta mark and $MMX_INVMASK or $mark_val return \
		comment "\"ct_restore_$iface\"" || return 1

	# Add per-interface ct mark save rule to multiwan_nft_hook
	# Uses constant mark_val (not meta mark) so nftables accepts it.
	# This saves the interface mark to conntrack for connection persistence,
	# preserving all non-multiwan_nft ct mark bits (e.g., MultiWAN QoS DSCP).
	if ! $NFT list chain $NFT_FAMILY $NFT_TABLE multiwan_nft_save 2>/dev/null | \
		grep -q "\"ct_save_$iface\""; then
		multiwan_nft_nft_add_rule multiwan_nft_save \
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
	multiwan_nft_nft_delete_matching_rules multiwan_nft_save "\"ct_save_$iface\""
	multiwan_nft_nft_delete_matching_rules multiwan_nft_restore "\"ct_restore_$iface\""
	multiwan_nft_nft_delete_matching_rules multiwan_nft_sticky_refresh "\"sticky_ingress_$iface\""
	multiwan_nft_nft_delete_matching_rules multiwan_nft_ifaces_in "jump multiwan_nft_iface_in_$iface"

	# Delete the interface chain
	multiwan_nft_nft_delete_chain "multiwan_nft_iface_in_$iface"

	multiwan_nft_nft_dump "delete_iface_nft-$iface"
}

multiwan_nft_read_route_table()
{
	local IP="$1" table="$2" routes
	routes="$(LC_ALL=C $IP route list table "$table" 2>&1)" || {
		# Optional tables may appear only when their VPN/service starts.
		case "$table" in main|254) ;; *)
			case "$routes" in
				"Error: ipv4: FIB table does not exist."*|"Error: ipv6: FIB table does not exist."*) return 0 ;;
			esac ;;
		esac
		LOG error "Could not read routing table $table: $routes"
		return 1
	}
	# iproute2 can return success after an interrupted or truncated dump.
	case "$routes" in *"Dump was interrupted"*|*"Message truncated"*)
		LOG error "Incomplete routing table dump for table $table"
		return 1 ;;
	esac
	# A multipath continuation belongs to its route, never to a separate prefix.
	printf '%s\n' "$routes" | awk '
		function emit() {
			gsub(/[ \t]+/, " ", line); sub(/^ /, "", line); sub(/ $/, "", line)
			if (line ~ / nhid /) {
				sub(/ nexthop .*/, "", line)
				gsub(/ via (inet6 |inet )?[^ ]*/, "", line)
				gsub(/ dev [^ ]*/, "", line)
			}
			if (line != "") print line
		}
		/^[ \t]+nexthop / { line = line " " $0; next }
		{ emit(); line = $0 }
		END { emit() }'
}

multiwan_nft_route_for_iface()
{
	local route_line="$1" family="$2" id="$3" IP nhid nexthop= group= member weight header paths=
	local path tid selected= selected_id= count=0 total=0
	case "$family" in ipv4) IP="$IP4" ;; ipv6) IP="$IP6" ;; *) return 1 ;; esac
	nhid=$(printf '%s\n' "$route_line" | sed -n 's/.* nhid \([0-9][0-9]*\)\( .*\)\?$/\1/p')
	if [ -n "$nhid" ]; then
		nexthop="$(LC_ALL=C $IP nexthop get id "$nhid" 2>&1)" || {
			LOG error "Could not resolve nexthop $nhid: $nexthop"
			return 1
		}
		group=$(printf '%s\n' "$nexthop" | sed -n 's/^id [0-9][0-9]* group \([^ ]*\).*/\1/p')
		if [ -n "$group" ]; then
			header=$(printf '%s\n' "$route_line" | sed "s/ nhid $nhid//; s/ nexthop .*//")
			for member in $(printf '%s\n' "$group" | tr / ' '); do
				weight=${member#*,}; [ "$weight" != "$member" ] || weight=1
				member=${member%%,*}
				nexthop="$(LC_ALL=C $IP nexthop get id "$member" 2>&1)" || {
					LOG error "Could not resolve group $nhid member $member: $nexthop"
					return 1
				}
				paths="$paths
$nexthop weight $weight"
			done
		fi
	elif [ "${route_line#* nexthop }" != "$route_line" ]; then
		header=${route_line%% nexthop *}
		paths=$(printf '%s\n' "${route_line#* nexthop }" | sed 's/ nexthop /\n/g')
	fi
	if [ -z "$paths" ]; then
		multiwan_nft_route_line_dev tid "${nexthop:-$route_line}" "$family" || return 1
		{ [ -z "${route_line##default*}" ] || [ -z "${route_line##fe80::/64*}" ]; } && [ "$tid" != "$id" ] && return 0
		[ -z "$tid" ] || [ "$tid" = "$id" ] || return 0
		printf '%s\n' "$route_line"
		return 0
	fi
	while read -r path; do
		[ -n "$path" ] || continue
		total=$((total+1))
		multiwan_nft_route_line_dev tid "$path" "$family" || return 1
		{ [ -z "${route_line##default*}" ] || [ -z "${route_line##fe80::/64*}" ]; } && [ "$tid" != "$id" ] && continue
		[ -z "$tid" ] || [ "$tid" = "$id" ] || continue
		count=$((count+1))
		selected_id=$(printf '%s\n' "$path" | sed -n 's/^id \([0-9][0-9]*\) .*/\1/p')
		path=$(printf '%s\n' "$path" | sed 's/^id [0-9][0-9]* //; s/ scope [^ ]*//g; s/ proto [^ ]*//g; s/ dead//g; s/ linkdown//g; s/[ \t]\+/ /g; s/ $//')
		selected="$selected nexthop $path"
	done <<EOF
$paths
EOF
	[ "$count" -gt 0 ] || return 0
	if [ "$count" -eq "$total" ]; then
		printf '%s\n' "$route_line"
	elif [ -n "$group" ] && [ "$count" -eq 1 ]; then
		printf '%s\n' "$route_line" | sed "s/ nhid $nhid\( \|$\)/ nhid $selected_id\1/"
	else
		# Keep relative weights within this WAN without creating shared kernel objects.
		# shortcut: use owned nexthop groups when an exact per-WAN ratio exceeds 256.
		selected="$(printf '%s\n' "$selected" | sed 's/ nexthop /\n/g' | awk '
			function gcd(a, b, t) { while (b) { t = a % b; a = b; b = t }; return a }
			NF {
				weight = 1; path = ""
				for (i = 1; i <= NF; i++) {
					if ($i == "weight") weight = $(++i)
					else path = path " " $i
				}
				if (!(path in weights)) order[++count] = path
				weights[path] += weight
			}
			END {
				divisor = weights[order[1]]
				for (i = 2; i <= count; i++) divisor = gcd(divisor, weights[order[i]])
				for (i = 1; i <= count; i++) if (weights[order[i]] / divisor > 256) exit 1
				for (i = 1; i <= count; i++) printf " nexthop%s weight %d", order[i], weights[order[i]] / divisor
			}')" || { LOG error "Cannot represent exact per-WAN weights for route: $route_line"; return 1; }
		printf '%s%s\n' "$header" "$selected"
	fi
}

multiwan_nft_get_routes()
{
	local tables="main" table routes="" table_routes
	multiwan_nft_collect_source_table() { tables="$tables $1"; }
	config_list_foreach globals rt_table_lookup multiwan_nft_collect_source_table
	for table in $tables; do
		table_routes="$(multiwan_nft_read_route_table "$IP" "$table")" || return 1
		[ -n "$table_routes" ] || continue
		routes="$routes$table_routes
"
	done
	routes="$(printf '%s' "$routes" | sed -ne "$MULTIWAN_NFT_ROUTE_LINE_EXP")" || return 1
	printf '%s\n' "$routes" | sort -u
}

multiwan_nft_record_owned_table()
{
	local family="$1" id="$2"
	case "$family:$id" in ipv4:*|ipv6:*) ;; *) return 1 ;; esac
	case "$id" in ''|0|*[!0-9]*) return 1 ;; esac
	[ "${#id}" -le 8 ] && [ "$id" -le "$MULTIWAN_NFT_INTERFACE_MAX" ] || return 1
	mkdir -p "$MULTIWAN_NFT_STATUS_DIR/owned_tables" &&
		: > "$MULTIWAN_NFT_STATUS_DIR/owned_tables/$family.$id"
}

multiwan_nft_cleanup_owned_tables()
{
	local entry family id IP failed=0 pref output
	for entry in "$MULTIWAN_NFT_STATUS_DIR"/owned_tables/*; do
		[ -f "$entry" ] || continue
		entry=${entry##*/}; family=${entry%%.*}; id=${entry#*.}
		case "$family" in ipv4) IP="$IP4" ;; ipv6) IP="$IP6" ;; *) return 1 ;; esac
		case "$id" in ''|0|*[!0-9]*) return 1 ;; esac
		[ "${#id}" -le 8 ] && [ "$id" -le "$MULTIWAN_NFT_INTERFACE_MAX" ] || return 1
		for pref in "$((id+1000))" "$((id+2000))" "$((id+3000))"; do
			while $IP rule del pref "$pref" 2>/dev/null; do :; done
		done
		output="$(LC_ALL=C $IP route flush table "$id" 2>&1)" || {
			# An offline or disabled WAN may never have created its FIB table.
			case "$output" in
				"Error: $family: FIB table does not exist."*) ;;
				*) LOG error "Could not flush owned routing table $family/$id: $output"; failed=1 ;;
			esac
		}
	done
	for IP in "$IP4" "$IP6"; do
		[ "$IP" != "$IP6" ] || [ "$NO_IPV6" -eq 0 ] || continue
		while $IP rule del pref "$((MM_BLACKHOLE+2000))" fwmark "$MMX_BLACKHOLE/$MMX_MASK" blackhole 2>/dev/null; do :; done
		while $IP rule del pref "$((MM_UNREACHABLE+2000))" fwmark "$MMX_UNREACHABLE/$MMX_MASK" unreachable 2>/dev/null; do :; done
	done
	[ "$failed" -eq 0 ]
}

multiwan_nft_route_command()
{
	local IP="$1" action="$2" id="$3" route_line="$4"
	case "$route_line" in *" nhid "*)
		# Keep object identity; ip rejects its expanded via/device attributes.
		route_line="$(printf '%s\n' "$route_line" | sed 's/ via \(inet6 \|inet \)\?[^ ]*//g; s/ dev [^ ]*//g;')" || return 1 ;;
	esac
	$IP route "$action" table "$id" $route_line
}

multiwan_nft_route_key()
{
	# The kernel flattens a one-path multipath route and reorders via/device.
	printf '%s\n' "$1" | awk '
		{
			line = $0; tail = line; sub(/ nexthop /, "", tail)
			if (line ~ / nhid /) {
				sub(/ nexthop .*/, "", line)
				gsub(/ via (inet6 |inet )?[^ ]*/, "", line); gsub(/ dev [^ ]*/, "", line)
				print line; next
			}
			if (tail ~ / nexthop /) { print line; next }
			gsub(/ nexthop /, " ", line); gsub(/ weight [0-9]+/, "", line)
			via = ""; dev = ""
			if (match(line, / via (inet6 |inet )?[^ ]+/)) {
				via = substr(line, RSTART, RLENGTH); sub(/ via (inet6 |inet )?[^ ]+/, "", line)
			}
			if (match(line, / dev [^ ]+/)) {
				dev = substr(line, RSTART, RLENGTH); sub(/ dev [^ ]+/, "", line)
			}
			print line via dev
		}'
}

multiwan_nft_create_iface_route()
{
	local route_line family IP id source_routes desired_routes desired_keys current_routes route_failed device
	config_get family "$1" family ipv4
	multiwan_nft_get_iface_id id "$1"
	multiwan_nft_get_device device "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	multiwan_nft_update_dev_to_table
	multiwan_nft_record_owned_table "$family" "$id" || return 1

	source_routes="$(multiwan_nft_get_routes)" || return 1
	case "$source_routes" in *" nhid "*|*" nexthop "*) MULTIWAN_NFT_ROUTE_HAS_NEXTHOPS=1 ;; esac
	current_routes="$(multiwan_nft_read_route_table "$IP" "$id")" || return 1
	desired_routes="$(
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		multiwan_nft_route_for_iface "$route_line" "$family" "$id" || exit 1
	done <<EOF
$source_routes
EOF
	)" || return 1

	route_failed=0
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		multiwan_nft_route_replace_idempotent "$IP" "$id" "$route_line" || {
			route_failed=1
		}
	done <<EOF
$desired_routes
EOF
	[ "$route_failed" -eq 0 ] || return 1
	# Keep only provider-declared recovery defaults when main lacks them.
	multiwan_nft_restore_iface_table_default_route "$1" "$device" || return 1
	desired_routes="$desired_routes
${MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES:-}"

	desired_keys="$(multiwan_nft_route_key "$desired_routes")" || return 1
	# Compare canonical identities before removing stale or withdrawn routes.
	current_routes="$(multiwan_nft_read_route_table "$IP" "$id")" || return 1
	while read -r route_line; do
		[ -n "$route_line" ] || continue
		printf '%s\n' "$desired_keys" | grep -Fxq "$(multiwan_nft_route_key "$route_line")" && continue
		multiwan_nft_route_command "$IP" del "$id" "$route_line" || {
			LOG warn "route: failed to delete stale '$route_line' from table $id"
			route_failed=1
		}
	done <<EOF
$current_routes
EOF

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

	multiwan_nft_record_owned_table "$family" "$id" || return 1
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

multiwan_nft_set_tracker_oif_rules()
{
	local iface="$1" device="$2" id family IP mark_val source
	config_get family "$iface" family ipv4
	multiwan_nft_get_iface_id id "$iface"
	[ -n "$id" ] && [ -n "$device" ] || return 1
	case "$family" in
		ipv4) IP="$IP4" ;;
		ipv6) [ "$NO_IPV6" -eq 0 ] || return 1; IP="$IP6" ;;
		*) return 1 ;;
	esac
	mark_val="$(multiwan_nft_id2mask id MMX_MASK)"
	while $IP rule del pref $((id+2000)) 2>/dev/null; do :; done
	while $IP rule del pref $((id+3000)) 2>/dev/null; do :; done
	$IP rule add pref $((id+3000)) fwmark "$mark_val/$MMX_MASK" unreachable || return 1
	while $IP rule del pref $((id+1000)) 2>/dev/null; do :; done
	$IP rule add pref $((id+1000)) iif "$device" lookup "$id" || return 1
	multiwan_nft_get_src_ip source "$iface"
	case "$source" in ''|0.0.0.0|::) LOG warn "No usable source address for recovery on $iface"; return 1 ;; esac
	# Only explicit socket-helper bypass traffic may use an offline WAN.
	$IP rule add pref $((id+1000)) from "$source" oif "$device" \
		fwmark "$MMX_DEFAULT/$MMX_MASK" lookup "$id"
}
multiwan_nft_delete_iface_rules()
{
	local id family IP device mark_val

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

	network_get_device device "$1"
	mark_val="$(multiwan_nft_id2mask id MMX_MASK)"

	# These priorities are allocated from this package's interface ID and are
	# the complete owned rule identity, including tracker-only variants.
	while $IP rule del pref $((id+1000)) 2>/dev/null; do :; done
	while $IP rule del pref $((id+2000)) 2>/dev/null; do :; done
	while $IP rule del pref $((id+3000)) 2>/dev/null; do :; done
}

multiwan_nft_delete_iface_set_entries()
{
	local id setname mark_dec mark_hex batch_file set_json
	local nft_entries nft_entry listed_name elem_keys elem_key
	local element_addr element_mark element_mark_dec deleted

	multiwan_nft_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	mark_dec=$(multiwan_nft_id2mask id MMX_MASK)
	mark_dec=$((mark_dec))
	mark_hex=$(printf '0x%08x' "$mark_dec")
	batch_file=$(mktemp /tmp/multiwan-nft-sticky.XXXXXX) || return 1
	deleted=0

	# nft represents timed compound elements as nested JSON. Parse the key only;
	# timeout/expiry metadata must never be copied into a delete command.
	for setname in $($NFT list table $NFT_FAMILY $NFT_TABLE 2>/dev/null | grep -oE 'set multiwan_nft_sticky_[^ ]+' | awk '{print $2}'); do
		set_json="$($NFT -j list set $NFT_FAMILY $NFT_TABLE "$setname" 2>/dev/null)" || {
			rm -f "$batch_file"
			LOG warn "Could not read sticky set $setname as JSON"
			return 1
		}
		json_load "$set_json" || {
			rm -f "$batch_file"
			LOG warn "Could not parse sticky set $setname JSON"
			return 1
		}
		json_select nftables 2>/dev/null || continue
		json_get_keys nft_entries
		for nft_entry in $nft_entries; do
			json_select "$nft_entry" 2>/dev/null || continue
			if json_select set 2>/dev/null; then
				json_get_var listed_name name
				if [ "$listed_name" = "$setname" ] && json_select elem 2>/dev/null; then
					json_get_keys elem_keys
					for elem_key in $elem_keys; do
						element_addr=
						element_mark=
						json_select "$elem_key" 2>/dev/null || continue
						if json_select elem 2>/dev/null && json_select val 2>/dev/null && json_select concat 2>/dev/null; then
							json_get_var element_addr 1
							json_get_var element_mark 2
							json_select ..
							json_select ..
							json_select ..
						fi
						json_select ..
						case "$element_mark" in
							0x*|0X*) element_mark_dec=$((element_mark)) ;;
							*[!0-9]*|'') continue ;;
							*) element_mark_dec=$element_mark ;;
						esac
						[ "$element_mark_dec" -eq "$mark_dec" ] || continue
						[ -n "$element_addr" ] || continue
						printf 'delete element %s %s %s { %s . %s }\n' \
							"$NFT_FAMILY" "$NFT_TABLE" "$setname" "$element_addr" "$mark_hex" >> "$batch_file"
						deleted=$((deleted + 1))
					done
					json_select ..
				fi
				json_select ..
			fi
			json_select ..
		done
	done

	MULTIWAN_NFT_STICKY_DELETED=$deleted
	if [ "$deleted" -gt 0 ]; then
		if ! $NFT -c -f "$batch_file" >/dev/null 2>&1 || ! $NFT -f "$batch_file" >/dev/null 2>&1; then
			rm -f "$batch_file"
			LOG warn "Failed to delete exact sticky entries for interface $1"
			return 1
		fi
	fi
	rm -f "$batch_file"
	LOG info "Removed $deleted sticky entr$( [ "$deleted" -eq 1 ] && printf 'y' || printf 'ies' ) for interface $1"
	return 0
}


multiwan_nft_get_policy_member()
{
	config_get iface "$1" interface
	config_get metric "$1" metric 1
	config_get weight "$1" weight 1
	case "$metric:$weight" in *[!0-9:]*|:*|*:|*:*:*)
		LOG error "Invalid metric or weight for member $1"; return 1 ;;
	esac
	while [ "${metric#0}" != "$metric" ]; do metric=${metric#0}; done
	while [ "${weight#0}" != "$weight" ]; do weight=${weight#0}; done
	metric=${metric:-0}
	weight=${weight:-0}
	if [ "${#metric}" -gt 3 ] || [ "${#weight}" -gt 4 ] ||
		[ "$metric" -lt 1 ] || [ "$metric" -gt "$DEFAULT_LOWEST_METRIC" ] ||
		[ "$weight" -lt 1 ] || [ "$weight" -gt 1000 ]; then
		LOG error "Member $1 requires metric 1-$DEFAULT_LOWEST_METRIC and weight 1-1000"
		return 1
	fi
}

multiwan_nft_scan_policy_member()
{
	local iface family metric weight is_offline enabled

	multiwan_nft_get_policy_member "$1" || { policy_batch_failed=1; return 1; }

	[ -n "$iface" ] || return 0
	config_get_bool enabled "$iface" enabled 0
	[ "$enabled" -eq 1 ] || return 0
	[ "$metric" -gt "$DEFAULT_LOWEST_METRIC" ] && LOG warn "Member interface $iface has >$DEFAULT_LOWEST_METRIC metric. Not appending to policy" && return 0

	[ "$(multiwan_nft_get_iface_hotplug_state "$iface")" = "online" ]
	is_offline=$?
	[ "$is_offline" -eq 0 ] || return 0

	config_get family "$iface" family ipv4
	[ "$family" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return

	if [ "$family" = "ipv4" ]; then
		if [ "$metric" -lt "$lowest_metric_v4" ]; then
			total_weight_v4=$weight
			lowest_metric_v4=$metric
		elif [ "$metric" -eq "$lowest_metric_v4" ]; then
			total_weight_v4=$((total_weight_v4+weight))
		fi
	elif [ "$family" = "ipv6" ]; then
		if [ "$metric" -lt "$lowest_metric_v6" ]; then
			total_weight_v6=$weight
			lowest_metric_v6=$metric
		elif [ "$metric" -eq "$lowest_metric_v6" ]; then
			total_weight_v6=$((total_weight_v6+weight))
		fi
	fi
}

multiwan_nft_set_policy_nft()
{
	local id iface family metric weight device is_offline family_guard total_weight lowest_metric emitted_var emitted enabled

	multiwan_nft_get_policy_member "$1" || { policy_batch_failed=1; return 1; }

	[ -n "$iface" ] || return 0
	config_get_bool enabled "$iface" enabled 0
	[ "$enabled" -eq 1 ] || return 0
	network_get_device device "$iface"
	[ "$metric" -gt "$DEFAULT_LOWEST_METRIC" ] && return 0

	multiwan_nft_get_iface_id id "$iface"

	[ -n "$id" ] || return 0

	[ "$(multiwan_nft_get_iface_hotplug_state "$iface")" = "online" ]
	is_offline=$?

	config_get family "$iface" family ipv4
	if [ "$family" = "ipv4" ]; then
		family_guard="meta nfproto ipv4"
		total_weight=$total_weight_v4
		lowest_metric=$lowest_metric_v4
		emitted_var=policy_emitted_v4
	elif [ "$family" = "ipv6" ] && [ "$NO_IPV6" -eq 0 ]; then
		family_guard="meta nfproto ipv6"
		total_weight=$total_weight_v6
		lowest_metric=$lowest_metric_v6
		emitted_var=policy_emitted_v6
	else
		return
	fi

	local mark_val=$(multiwan_nft_id2mask id MMX_MASK)

	if [ "$is_offline" -eq 0 ]; then
		[ "$metric" -eq "$lowest_metric" ] || return 0
		multiwan_nft_nft_add_set_element "multiwan_nft_policy_${policy}_members_$family" "$mark_val" || { policy_batch_failed=1; return 1; }
		eval "emitted=\${$emitted_var:-0}"
		if [ "$emitted" -eq 0 ]; then
			eval "$emitted_var=$weight"
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$policy" \
				$family_guard meta mark and $MMX_MASK == 0 \
				meta mark set meta mark and $MMX_INVMASK or $mark_val return \
				comment "\"$iface $weight $total_weight\"" || policy_batch_failed=1
			return
		fi

		# Reverse insertion requires the cumulative weight of this prefix.
		eval "$emitted_var=$((emitted + weight))"
		multiwan_nft_nft_insert_rule "multiwan_nft_policy_$policy" \
			$family_guard meta mark and $MMX_MASK == 0 \
			numgen random mod $((emitted + weight)) lt $weight \
			meta mark set meta mark and $MMX_INVMASK or $mark_val return \
			comment "\"$iface $weight $total_weight\"" || policy_batch_failed=1

	fi
}

multiwan_nft_create_policies_nft()
{
	local last_resort lowest_metric_v4 lowest_metric_v6 total_weight_v4 total_weight_v6 policy policy_emitted_v4 policy_emitted_v6

	policy="$1"

	config_get last_resort "$1" last_resort unreachable

	multiwan_nft_nft_init_table || { policy_batch_failed=1; return 1; }
	multiwan_nft_nft_create_chain "multiwan_nft_policy_$1" || { policy_batch_failed=1; return 1; }
	multiwan_nft_nft_create_set "multiwan_nft_policy_${1}_members_ipv4" "type mark" "" || { policy_batch_failed=1; return 1; }
	if [ "$NO_IPV6" -eq 0 ]; then
		multiwan_nft_nft_create_set "multiwan_nft_policy_${1}_members_ipv6" "type mark" "" || { policy_batch_failed=1; return 1; }
	fi

	lowest_metric_v4=$DEFAULT_LOWEST_METRIC
	total_weight_v4=0

	lowest_metric_v6=$DEFAULT_LOWEST_METRIC
	total_weight_v6=0

	config_list_foreach "$1" use_member multiwan_nft_scan_policy_member

	policy_emitted_v4=0
	policy_emitted_v6=0

	# Then add only the member rules for the selected metric tier.
	config_list_foreach "$1" use_member multiwan_nft_set_policy_nft

	# Add last resort rule AFTER interface rules (so it's at the end)
	case "$last_resort" in
		blackhole)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_BLACKHOLE return \
				comment "\"blackhole\"" || { policy_batch_failed=1; return 1; }
			;;
		default)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_DEFAULT return \
				comment "\"default\"" || { policy_batch_failed=1; return 1; }
			;;
		*)
			multiwan_nft_nft_add_rule "multiwan_nft_policy_$1" \
				meta mark and $MMX_MASK == 0 meta mark set meta mark and $MMX_INVMASK or $MMX_UNREACHABLE return \
				comment "\"unreachable\"" || { policy_batch_failed=1; return 1; }
			;;
	esac
	
	multiwan_nft_nft_dump "create_policies_nft-$1"
}

multiwan_nft_set_policies_nft()
{
	local batch_file check_error apply_error NFT_BATCH_FILE NFT_BATCH_FAILED=0

	batch_file=$(mktemp /tmp/multiwan-nft-policy.XXXXXX) || return 1
	NFT_BATCH_FILE="$batch_file"
	policy_batch_failed=0
	config_foreach multiwan_nft_create_policies_nft policy
	NFT_BATCH_FILE=

	if [ "$policy_batch_failed" -ne 0 ] || [ "$NFT_BATCH_FAILED" -ne 0 ]; then
		rm -f "$batch_file"
		LOG warn "Policy batch generation failed; live policies were not changed"
		return 1
	fi
	if [ ! -s "$batch_file" ]; then rm -f "$batch_file"; return 0; fi
	check_error="$($NFT -c -f "$batch_file" 2>&1)" || {
		rm -f "$batch_file"
		LOG warn "Policy batch validation failed; live policies were not changed: $check_error"
		return 1
	}
	apply_error="$($NFT -f "$batch_file" 2>&1)" || {
		rm -f "$batch_file"
		LOG warn "Policy transaction failed; live policies were not changed: $apply_error"
		return 1
	}
	rm -f "$batch_file"
	multiwan_nft_nft_dump "set_policies_nft"
	return 0
}

multiwan_nft_set_sticky_nft()
{
	local interface
	local rule="$2"
	local ipv="$3"
	local policy="$4"

	local id iface family
	config_get interface "$1" interface
	[ -n "$interface" ] || return 0
	config_get family "$interface" family ipv4
	[ "$family" = "ipv4" ] && [ "$ipv" != "ipv4" ] && return 0
	[ "$family" = "ipv6" ] && [ "$ipv" != "ipv6" ] && return 0
	multiwan_nft_get_iface_id id "$interface"
	[ -n "$id" ] || return 0
	local mark_val=$(multiwan_nft_id2mask id MMX_MASK) address=ip
	[ "$ipv" = ipv6 ] && address=ip6
	# Eligibility changes atomically with the policy, including new backup tiers.
	multiwan_nft_nft_insert_rule "multiwan_nft_rule_$rule" \
		"fib saddr type != local (meta mark and 0 or $mark_val) @${policy}_members_$ipv $address saddr . (meta mark and 0 or $mark_val) @multiwan_nft_sticky_${ipv}_${rule} meta mark set meta mark and $MMX_INVMASK or $mark_val return"
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

multiwan_nft_prepare_external_set()
{
	local name="$1" family="$2" definition settype expression description
	case "$name" in ''|*[!a-zA-Z0-9_.-]*|multiwan_nft_*)
		LOG error "Invalid or reserved external nft set name '$name'"; return 1 ;;
	esac
	if definition="$($NFT list set "$NFT_FAMILY" "$NFT_TABLE" "$name" 2>/dev/null)"; then
		settype="$(printf '%s\n' "$definition" | awk '$1 == "type" && NF == 2 { print $2; exit }')"
		if [ -z "$settype" ]; then
			expression="$(printf '%s\n' "$definition" | awk '$1 == "typeof" { $1=""; sub(/^[[:space:]]+/, ""); print; exit }')"
			if [ -n "$expression" ]; then
				# Let nft resolve expression datatypes instead of enumerating selectors.
				description="$($NFT describe "$expression" 2>/dev/null)" || description=
				settype="$(printf '%s\n' "$description" | awk '{ for (i=1; i<NF; i++) if ($i == "datatype") { print $(i+1); exit } }')"
			fi
		fi
		[ "$settype" = "${family}_addr" ] && return 0
		case "$settype" in ipv4_addr|ipv6_addr) return 2 ;; esac
		LOG error "External nft set '$name' must contain IPv4 or IPv6 addresses"
		return 1
	fi
	$NFT add set "$NFT_FAMILY" "$NFT_TABLE" "$name" \
		"{ type ${family}_addr; flags interval; auto-merge; }"
}

multiwan_nft_unload_ruleset()
{
	local sets chains name batch_file external=0
	$NFT list table "$NFT_FAMILY" "$NFT_TABLE" >/dev/null 2>&1 || return 0
	sets="$($NFT list table "$NFT_FAMILY" "$NFT_TABLE")" || return 1
	sets="$(printf '%s\n' "$sets" | sed -n 's/^[[:space:]]*set \([^ ]*\) {.*/\1/p')"
	for name in $sets; do
		case "$name" in multiwan_nft_*) ;; *) external=1 ;; esac
	done
	if [ "$external" -eq 0 ]; then
		$NFT delete table "$NFT_FAMILY" "$NFT_TABLE"
		return $?
	fi
	chains="$($NFT list table "$NFT_FAMILY" "$NFT_TABLE")" || return 1
	chains="$(printf '%s\n' "$chains" | sed -n 's/^[[:space:]]*chain \([^ ]*\) {.*/\1/p')"
	batch_file=$(mktemp /tmp/multiwan-nft-stop.XXXXXX) || return 1
	printf 'flush table %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" > "$batch_file"
	for name in $chains; do
		printf 'delete chain %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$name" >> "$batch_file"
	done
	for name in $sets; do
		case "$name" in multiwan_nft_*)
			printf 'delete set %s %s %s\n' "$NFT_FAMILY" "$NFT_TABLE" "$name" >> "$batch_file" ;;
		esac
	done
	# DNS-populated external sets outlive routing restarts, like upstream ipsets.
	$NFT -f "$batch_file"
	local result=$?
	rm -f "$batch_file"
	return "$result"
}

multiwan_nft_set_user_nft_rule()
{
	local nft_set family proto policy src_ip src_port src_iface src_dev
	local sticky dest_ip dest_port use_policy timeout rule_policy rule ipv
	local global_logging rule_logging loglevel

	rule="$1"
	ipv="$2"
	rule_policy=0
	config_get_bool sticky "$1" sticky 0
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
	family=${family:-any}
	case "$family" in any|ipv4|ipv6) ;; *) LOG error "Invalid rule family '$family' for $rule"; return 1 ;; esac
	config_get_bool rule_logging "$1" logging 0
	config_get_bool global_logging globals logging 0
	config_get loglevel globals loglevel notice

	[ "$ipv" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && return
	[ "$family" = "ipv4" ] && [ "$ipv" = "ipv6" ] && return
	[ "$family" = "ipv6" ] && [ "$ipv" = "ipv4" ] && return

	# Colons identify IPv6, including IPv4-mapped IPv6 literals.
	local address_family="" current_family ipaddr
	for ipaddr in "$src_ip" "$dest_ip"; do
		[ -n "$ipaddr" ] || continue
		case "$ipaddr" in *:*) current_family=ipv6 ;; *) current_family=ipv4 ;; esac
		if [ -n "$address_family" ] && [ "$address_family" != "$current_family" ]; then
			LOG error "Source and destination families differ for rule $rule"
			return 1
		fi
		address_family=$current_family
	done
	if [ -n "$address_family" ] && [ "$address_family" != "$ipv" ]; then
		[ "$family" = any ] && return 0
		LOG error "Address family does not match rule $rule"
		return 1
	fi

	if [ -n "$src_iface" ]; then
		multiwan_nft_get_device src_dev "$src_iface"
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
			multiwan_nft_set_sticky_set "$rule" "$MMX_MASK" "$timeout" || return 1
		fi
	fi

	# Build match criteria
	local family_guard match base_match
	[ "$ipv" = "ipv4" ] && family_guard="meta nfproto ipv4" || family_guard="meta nfproto ipv6"
	match="$family_guard"
	
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
		local set_result=0
		multiwan_nft_prepare_external_set "$nft_set" "$ipv" || set_result=$?
		if [ "$set_result" -ne 0 ]; then
			[ "$set_result" -eq 2 ] && [ "$family" = any ] && return 0
			LOG error "External set '$nft_set' does not match rule $rule family $ipv"
			return 1
		fi
		if [ "$ipv" = "ipv6" ]; then
			match="$match ip6 daddr @$nft_set"
		else
			match="$match ip daddr @$nft_set"
		fi
	fi
	base_match="$match"
	
	# Mark check - only process unmarked traffic
	match="$match meta mark and $MMX_MASK == 0"
	if [ "$global_logging" = "1" ] && [ "$rule_logging" = "1" ]; then
		multiwan_nft_nft_add_rule multiwan_nft_rules $match \
			log prefix "\"MULTIWAN_NFT($rule)\"" level $loglevel || return 1
	fi

	if [ "$rule_policy" -eq 1 ]; then
		# Create rule chain if not exists (flush handled by multiwan_nft_set_user_rules_nft)
		if ! $NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_rule_$rule" &>/dev/null; then
			$NFT add chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_rule_$rule" || {
				LOG warn "nft: failed to create user rule chain multiwan_nft_rule_$rule"
				return 1
			}
		fi
		
		if [ "$sticky" -eq 1 ]; then
			config_list_foreach "$use_policy" use_member multiwan_nft_set_sticky_nft "$rule" "$ipv" "multiwan_nft_policy_$use_policy"
		fi
		
		# Jump to policy
		multiwan_nft_nft_add_rule "multiwan_nft_rule_$rule" \
			meta mark and $MMX_MASK == 0 jump "multiwan_nft_policy_$use_policy" || return 1
		
		# Add rule to multiwan_nft_rules chain (for new connections)
		if ! multiwan_nft_nft_add_rule multiwan_nft_rules $match jump "multiwan_nft_rule_$rule" \
			comment "\"$rule\""; then
			LOG warn "Failed to add rule '$rule' to multiwan_nft_rules chain"
		fi
		
		# Add sticky refresh for ALL matching traffic (even established)
		# This runs regardless of mark state to keep sticky timeout fresh
		if [ "$sticky" -eq 1 ]; then
			# Reuse the complete original match and accept only real interface marks.
			# Default/failure marks must never pollute a sticky set.
			local sticky_match="$base_match fib saddr type != local meta mark and $MMX_MASK @multiwan_nft_policy_${use_policy}_members_$ipv"
			
			if [ "$ipv" = "ipv4" ]; then
				multiwan_nft_nft_add_rule multiwan_nft_sticky_refresh $sticky_match \
					"update @multiwan_nft_sticky_ipv4_$rule { ip saddr . (meta mark and $MMX_MASK) }" \
					comment "\"sticky_refresh_$rule\""
			else
				multiwan_nft_nft_add_rule multiwan_nft_sticky_refresh $sticky_match \
					"update @multiwan_nft_sticky_ipv6_$rule { ip6 saddr . (meta mark and $MMX_MASK) }" \
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

	# Preserve first-match ordering when refreshing already marked connections.
	multiwan_nft_nft_add_rule multiwan_nft_sticky_refresh $base_match return
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
	local rule_failed=0 batch_file error result=0 NFT_BATCH_FILE NFT_BATCH_FAILED=0
	local current_table ingress_rule
	multiwan_nft_build_user_rule() {
		multiwan_nft_set_user_nft_rule "$@" || rule_failed=1
	}
	batch_file=$(mktemp /tmp/multiwan-nft-user.XXXXXX) || return 1
	NFT_BATCH_FILE="$batch_file"
	if ! multiwan_nft_nft_init_table || ! current_table="$($NFT list table $NFT_FAMILY $NFT_TABLE 2>/dev/null)"; then
		LOG error "Could not read current user rules; live user rules were preserved"
		rm -f "$batch_file"
		return 1
	fi
	multiwan_nft_nft_create_chain "multiwan_nft_rules" || rule_failed=1
	multiwan_nft_nft_create_chain "multiwan_nft_sticky_refresh" || rule_failed=1
	# Preserve the installed ingress devices even when netifd is unavailable.
	printf '%s\n' "$current_table" | awk '
		$1 == "chain" { refresh = ($2 == "multiwan_nft_sticky_refresh") }
		$1 == "}" { refresh = 0 }
		refresh && /comment "sticky_ingress_[^"]+"/ { print }
	' | while IFS= read -r ingress_rule; do
		multiwan_nft_nft_add_rule multiwan_nft_sticky_refresh "$ingress_rule" || exit 1
	done || rule_failed=1

	# Flush all existing per-rule chains before rebuilding
	# This prevents duplicate entries on rebuild (e.g. after interface bounce)
	# Must happen BEFORE the ipv loop so ipv4 rules aren't wiped by ipv6 pass
	local existing_chain
	for existing_chain in $(printf '%s\n' "$current_table" | \
		grep -oE 'chain multiwan_nft_rule_[^ ]+' | sed 's/chain //'); do
		multiwan_nft_nft_create_chain "$existing_chain" || rule_failed=1
	done

	for ipv in ipv4 ipv6; do
		[ "$ipv" = "ipv6" ] && [ "$NO_IPV6" -ne 0 ] && continue
		
		# Tracking pings are naturally protected by ip rules priority 1000 ("oif pppoe-wan")
		# Bypassing echo-requests entirely breaks local testing and NCSI failover.
		config_foreach multiwan_nft_build_user_rule rule "$ipv"
	done
	NFT_BATCH_FILE=
	if [ "$rule_failed" -ne 0 ] || [ "$NFT_BATCH_FAILED" -ne 0 ]; then
		LOG error "User rule generation failed; live user rules were preserved"
		result=1
	elif ! error="$($NFT -c -f "$batch_file" 2>&1)" || ! error="$($NFT -f "$batch_file" 2>&1)"; then
		LOG error "User rule transaction failed; live user rules were preserved: $error"
		result=1
	fi
	rm -f "$batch_file"
	[ "$result" -eq 0 ] || return "$result"
	multiwan_nft_nft_dump "set_user_rules_nft"
}

multiwan_nft_interface_hotplug_shutdown()
{
	local interface status device ifdown true_iface
	interface="$1"
	ifdown="${2:-}"
	status="$(multiwan_nft_get_iface_hotplug_state "$interface")"

	[ "$status" != "online" ] && [ "$ifdown" != 1 ] && return 0
	multiwan_nft_get_true_iface true_iface "$interface"
	network_get_device device "$true_iface" || device=

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
	multiwan_nft_delete_iface_nft "$1"
	multiwan_nft_delete_iface_set_entries "$1"
	multiwan_nft_delete_iface_route "$1"
	multiwan_nft_delete_iface_rules "$1"
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
	local device result tracking tracker_state IP error hotplug_state recovery_result true_iface uptime=0

	config_get_bool enabled "$1" enabled 0
	if [ "$enabled" -eq 0 ]; then
		echo " interface $1 is disabled and tracking is not enabled"
		return 0
	fi
	if [ "${2:-}" = stopped ]; then
		tracking="$(multiwan_nft_get_track_status "$1")"
		echo " interface $1 is stopped and tracking is $tracking"
		return 0
	fi
	tracking="$(multiwan_nft_get_track_status "$1")"
	if [ "$tracking" = paused ]; then
		tracker_state="$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/$1/STATUS" 2>/dev/null)"
		case "$tracker_state" in disabled|waiting)
			echo " interface $1 is $tracker_state and tracking is paused"
			return 0
			;;
		esac
	fi
	multiwan_nft_get_iface_id id "$1"
	multiwan_nft_get_true_iface true_iface "$1"
	network_get_device device "$true_iface"
	config_get family "$1" family ipv4

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	else
		IP="$IP6"
	fi
	if [ -z "$id" ] || [ -z "$device" ]; then
		result="offline"
	else
		hotplug_state="$(multiwan_nft_get_iface_hotplug_state "$1")"
		error=0
		# Check iif rule at pref id+1000: must match device and lookup table (bit 0)
		$IP rule list | grep -q "^$((id+1000)):.*iif $device.*lookup $id" ||
			error=$((error+1))
		if [ "$hotplug_state" = offline ]; then
			# Offline means exact tracker selectors at pref id+1000, no fwmark
			# lookup, and the package-owned unreachable guard still present.
			[ -z "$($IP rule | awk -v pref="$((id+2000)):" '$1 == pref')" ] ||
				error=$((error+4))
		else
			$IP rule list | grep -q "^$((id+1000)):.*oif $device.*lookup $id" ||
				error=$((error+2))
			[ -n "$($IP rule | awk -v pref="$((id+2000)):" '$1 == pref')" ] ||
				error=$((error+4))
		fi
		# Check fwmark unreachable rule at pref id+3000 (bit 3)
		[ -n "$($IP rule | awk -v pref="$((id+3000)):" '$1 == pref')" ] ||
			error=$((error+8))
		# Check nft interface chain (bit 4)
		$NFT list chain $NFT_FAMILY $NFT_TABLE "multiwan_nft_iface_in_$1" >/dev/null 2>&1 ||
			error=$((error+16))
		# Check default route in interface table (bit 5)
		[ -n "$($IP route list table $id default dev $device 2> /dev/null)" ] ||
			error=$((error+32))
	fi

	if [ "$result" = "offline" ]; then
		:
	elif [ "$error" -eq 0 ] && [ "$hotplug_state" = offline ]; then
		recovery_result="$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/$1/RECOVERY_RULE_RESULT" 2>/dev/null)"
		result="offline (isolated, recovery=${recovery_result:-unknown})"
	elif [ "$error" -eq 0 ]; then
		online=$(get_online_time "$1")
		network_get_uptime uptime "$true_iface" || uptime=0
		online="$(printf '%02dh:%02dm:%02ds\n' $((online/3600)) $((online%3600/60)) $((online%60)))"
		uptime="$(printf '%02dh:%02dm:%02ds\n' $((uptime/3600)) $((uptime%3600/60)) $((uptime%60)))"
		result="$hotplug_state $online, uptime $uptime"
	elif [ "$error" -gt 0 ] && [ "$error" -ne 63 ]; then
		result="error (${error})"
	elif [ "$enabled" = "1" ]; then
		result="offline"
	else
		result="disabled"
	fi

	echo " interface $1 is $result and tracking is $tracking"
}

multiwan_nft_report_policies()
{
	local policy="$1" family="${2:-ipv4}" rows total=0 iface weight last_resort
	rows="$(multiwan_nft_policy_members "$policy" "$family")" || return 1
	while read -r iface weight; do
		[ -z "$iface" ] || total=$((total + weight))
	done <<EOF
$rows
EOF
	if [ "$total" -gt 0 ]; then
		while read -r iface weight; do
			[ -z "$iface" ] || printf ' %s (%s%%)\n' "$iface" "$((weight * 100 / total))"
		done <<EOF
$rows
EOF
	else
		config_get last_resort "${policy#multiwan_nft_policy_}" last_resort unreachable
		printf ' %s\n' "$last_resort"
	fi
}

multiwan_nft_report_policies_v4()
{
	local policy output failed=0

	output="$($NFT list table "$NFT_FAMILY" "$NFT_TABLE")" || return 1
	for policy in $(printf '%s\n' "$output" | grep -oE 'chain multiwan_nft_policy_[^ ]+' | sed 's/chain //'); do
		echo "${policy#multiwan_nft_policy_}:"
		multiwan_nft_report_policies "$policy" "${1:-ipv4}" || failed=1
	done
	return "$failed"
}

multiwan_nft_report_policies_v6()
{
	multiwan_nft_report_policies_v4 ipv6
}

multiwan_nft_report_connected_v4()
{
	multiwan_nft_connected_elements ipv4
}

multiwan_nft_report_connected_v6()
{
	multiwan_nft_connected_elements ipv6
}

multiwan_nft_report_rules_v4()
{
	local family="${1:-ipv4}" output line rule policy sticky indicator
	output="$($NFT list chain "$NFT_FAMILY" "$NFT_TABLE" multiwan_nft_rules)" || return 1
	while IFS= read -r line; do
		case "$line" in *"meta nfproto $family "*'comment "'*) ;; *) continue ;; esac
		rule="$(printf '%s\n' "$line" | sed -n 's/.*comment "\([^"]*\)".*/\1/p')"
		[ -n "$rule" ] || continue
		config_get policy "$rule" use_policy
		config_get_bool sticky "$rule" sticky 0
		indicator=-
		[ "$sticky" -ne 1 ] || indicator=S
		printf '%s %s (%s)\n' "$indicator" "$rule" "$policy"
	done <<EOF
$output
EOF
}

multiwan_nft_report_rules_v6()
{
	multiwan_nft_report_rules_v4 ipv6
}

# Idempotent route replace: skip existing canonical routes, handle "File exists"
# gracefully. Only for add/replace paths — delete handling is separate.
# Args: $1=ip_cmd, $2=table_id, $3=route_line (single string, expanded for ip cmd)
multiwan_nft_route_replace_idempotent() {
	local ip_cmd="$1" tid="$2" route_line="$3" routes key

	routes="$(multiwan_nft_read_route_table "$ip_cmd" "$tid")" || return 1
	key="$(multiwan_nft_route_key "$route_line")" || return 1
	multiwan_nft_route_key "$routes" | grep -Fxq "$key" && return 0

	# Try replace (intentionally expand $route_line for ip command)
	# shellcheck disable=SC2086
	local err
	err=$(multiwan_nft_route_command "$ip_cmd" replace "$tid" "$route_line" 2>&1)
	local rv=$?

	[ "$rv" -eq 0 ] && return 0

	# Handle "File exists" — verify route is present
	case "$err" in
		*"File exists"*)
			routes="$(multiwan_nft_read_route_table "$ip_cmd" "$tid")" || return 1
			multiwan_nft_route_key "$routes" | grep -Fxq "$key" && return 0
			;;
	esac

	LOG warn "route replace failed: table $tid route '$route_line': $err"
	return 1
}

# Purge all protocols carrying one interface's exact MultiWAN mark.
# The offline IP-rule state already makes the mark unreachable; this purge
# forces applications to establish fresh sessions without touching traffic on
# any other WAN.
multiwan_nft_flush_conntrack_iface()
{
	local iface="$1"
	local id mark_val family

	MULTIWAN_NFT_CONNTRACK_PURGED=0
	multiwan_nft_get_iface_id id "$iface"
	[ -n "$id" ] || return 0

	mark_val=$(multiwan_nft_id2mask id MMX_MASK)
	config_get family "$iface" family ipv4
	case "$family" in ipv4|ipv6) ;; *) return 1 ;; esac
	multiwan_nft_flush_conntrack_mark "$family" "$mark_val" "$MMX_MASK" "$iface"
}

multiwan_nft_flush_conntrack_mark()
{
	local family="$1" mark_val="$2" mask="$3" iface="$4"
	local entries deleted count delete_error=0
	MULTIWAN_NFT_CONNTRACK_PURGED=0
	case "$family" in ipv4|ipv6) ;; *) return 1 ;; esac

	if command -v conntrack >/dev/null 2>&1; then
		entries="$(conntrack -L -f "$family" -m "$mark_val/$mask" 2>/dev/null)" || {
			LOG warn "Could not enumerate conntracks for interface $iface"
			return 1
		}
		[ -n "$entries" ] || return 0
		deleted="$(conntrack -D -f "$family" -m "$mark_val/$mask" 2>/dev/null)" || delete_error=1
		count=$(printf '%s\n' "$deleted" | sed '/^[[:space:]]*$/d' | wc -l)
		MULTIWAN_NFT_CONNTRACK_PURGED=$count
		if [ "$delete_error" -ne 0 ]; then
			# Entries may expire between listing and deleting; verify the remainder.
			entries="$(conntrack -L -f "$family" -m "$mark_val/$mask" 2>/dev/null)" || return 1
			[ -z "$entries" ] || { LOG warn "Could not purge every conntrack for interface $iface"; return 1; }
		fi
		LOG notice "Purged marked conntracks for interface $iface (mark=$mark_val/$mask, entries=$count)"
		return 0
	fi

	LOG warn "conntrack tool not found; cannot purge sessions for failed interface $iface"
	return 1
}

multiwan_nft_stage_conntrack_map()
{
	local destination="${1:-$MULTIWAN_NFT_STATUS_DIR/conntrack_map_pending}" temporary failed=0
	temporary=$(mktemp "${destination}.XXXXXX") || return 1
	multiwan_nft_conntrack_map_entry() {
		local enabled family id
		config_get_bool enabled "$1" enabled 0
		[ "$enabled" -eq 1 ] || return 0
		config_get family "$1" family ipv4
		multiwan_nft_get_iface_id id "$1"
		case "$family:$id" in ipv4:?*|ipv6:?*) ;; *) failed=1; return 1 ;; esac
		printf '%s %s %s\n' "$family" "$1" "$id" || failed=1
	}
	if ! { printf '%s\n' "$MMX_MASK" || failed=1; config_foreach multiwan_nft_conntrack_map_entry interface; } > "$temporary" ||
	   [ "$failed" -ne 0 ] || ! mv "$temporary" "$destination"; then
		rm -f "$temporary"
		return 1
	fi
}

multiwan_nft_import_legacy_conntrack_map()
{
	local tables rules masks old_mask temporary
	[ ! -f "$MULTIWAN_NFT_CONNTRACK_MAP" ] || return 0
	tables="$($NFT list tables)" || return 1
	printf '%s\n' "$tables" | grep -Fxq "table $NFT_FAMILY $NFT_TABLE" || return 0
	rules="$($NFT -n list table "$NFT_FAMILY" "$NFT_TABLE")" || return 1
	masks="$(printf '%s\n' "$rules" | awk '{
		for (i=1; i<=NF-3; i++)
			if ($i=="mark" && $(i+1)=="&" && $(i+2) ~ /^0x[0-9a-fA-F]+$/ && ($(i+3)=="==" || $(i+3)=="!="))
				print $(i+2)
	}')" || return 1
	if [ -z "$masks" ]; then
		printf '%s\n' "$rules" | grep -q 'chain multiwan_nft_hook {' || return 0
		LOG error "Previous routing hook has no recognizable mark mask"
		return 1
	fi
	masks="$(printf '%s\n' "$masks" | sort -u)" || return 1
	old_mask="$(multiwan_nft_normalize_mask "$masks")" || {
		LOG error "Could not identify one valid mask in the previous routing rules"
		return 1
	}
	# Old packages have no identity history; keep their mask through failed rebuilds.
	temporary=$(mktemp "${MULTIWAN_NFT_CONNTRACK_MAP}.XXXXXX") || return 1
	if ! printf '%s\nlegacy\n' "$old_mask" > "$temporary" || ! mv "$temporary" "$MULTIWAN_NFT_CONNTRACK_MAP"; then
		rm -f "$temporary"
		return 1
	fi
	LOG notice "Recovered previous routing mask $old_mask without an interface identity map"
}

multiwan_nft_guard_retired_marks()
{
	local mask="$1" records="$2" family mark iface
	local table="${NFT_TABLE}_reconcile"
	multiwan_nft_nft_buf_init
	multiwan_nft_nft_buf_add "add table $NFT_FAMILY $table"
	multiwan_nft_nft_buf_add "flush table $NFT_FAMILY $table"
	multiwan_nft_nft_buf_add "add chain $NFT_FAMILY $table retired"
	while read -r family mark iface; do
		[ -n "$family" ] || continue
		if [ "$mark" = nonzero ]; then
			multiwan_nft_nft_buf_add "add rule $NFT_FAMILY $table retired meta nfproto $family ct mark and $mask != 0 counter drop"
		else
			multiwan_nft_nft_buf_add "add rule $NFT_FAMILY $table retired meta nfproto $family ct mark and $mask == $mark counter drop"
		fi
	done <<EOF
$records
EOF
	multiwan_nft_nft_buf_add "add chain $NFT_FAMILY $table input { type filter hook input priority 2147483646; }"
	multiwan_nft_nft_buf_add "add rule $NFT_FAMILY $table input jump retired"
	multiwan_nft_nft_buf_add "add chain $NFT_FAMILY $table postrouting { type filter hook postrouting priority 2147483646; }"
	multiwan_nft_nft_buf_add "add rule $NFT_FAMILY $table postrouting jump retired"
	multiwan_nft_nft_buf_commit || return 1
	# Linux 6.12 aborts check-only transactions after an RCU grace period.
	$NFT -c add rule "$NFT_FAMILY" "$table" input counter
}

multiwan_nft_release_retired_marks()
{
	local tables table="${NFT_TABLE}_reconcile"
	tables="$($NFT list tables)" || return 1
	printf '%s\n' "$tables" | grep -Fxq "table $NFT_FAMILY $table" || return 0
	# Drain readers of replaced routing rules before removing protection.
	$NFT -c add rule "$NFT_FAMILY" "$table" input counter || return 1
	$NFT delete table "$NFT_FAMILY" "$table"
}

multiwan_nft_flush_legacy_conntrack_marks()
{
	local mask="$1" family entries marks mark normalized
	for family in ipv4 ipv6; do
		[ "$family" != ipv6 ] || [ "$NO_IPV6" -eq 0 ] || continue
		entries="$(conntrack -L -f "$family" -o extended 2>/dev/null)" || return 1
		marks="$(printf '%s\n' "$entries" | sed -n 's/.* mark=\([^ ]*\).*/\1/p')" || return 1
		marks="$(printf '%s\n' "$marks" | sort -u)" || return 1
		normalized=""
		for mark in $marks; do
			case "$mark" in ''|*[!0-9]*) return 1 ;; esac
			[ "${#mark}" -le 10 ] && [ "$mark" -le 4294967295 ] || return 1
			mark=$((mark & mask))
			[ "$mark" -ne 0 ] || continue
			normalized="$normalized$(printf '0x%08x\n' "$mark")
"
		done
		marks="$(printf '%s' "$normalized" | sort -u)" || return 1
		for mark in $marks; do
			multiwan_nft_flush_conntrack_mark "$family" "$mark" "$mask" 'legacy ownership' || return 1
		done
	done
}

multiwan_nft_reconcile_conntrack_map()
{
	local cached_mask old_mask records family iface id extra old_max mark retired=""
	multiwan_nft_stage_conntrack_map || return 1
	multiwan_nft_import_legacy_conntrack_map || return 1
	if [ ! -f "$MULTIWAN_NFT_CONNTRACK_MAP" ]; then
		[ ! -e "$MULTIWAN_NFT_UPGRADE_PENDING" ] && return 0
		LOG error "Previous package has no routing identity history; reboot before starting to discard unidentifiable connection marks"
		return 1
	fi
	cached_mask=$(head -n 1 "$MULTIWAN_NFT_CONNTRACK_MAP")
	old_mask=$(multiwan_nft_normalize_mask "$cached_mask") || return 1
	old_max=$(((1 << $(multiwan_nft_count_one_bits "$old_mask")) - 4))
	records=$(sed '1d' "$MULTIWAN_NFT_CONNTRACK_MAP") || return 1
	if [ "$records" = legacy ]; then
		retired='ipv4 nonzero legacy'
		[ "$NO_IPV6" -ne 0 ] || retired="$retired
ipv6 nonzero legacy"
		multiwan_nft_guard_retired_marks "$old_mask" "$retired" || return 1
		multiwan_nft_flush_legacy_conntrack_marks "$old_mask"
		return $?
	fi
	# Validate the entire saved map before deleting any connection state.
	while read -r family iface id extra; do
		[ -n "$family" ] || continue
		case "$family" in ipv4|ipv6) ;; *) return 1 ;; esac
		case "$iface" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
		case "$id" in ''|0*|*[!0-9]*) return 1 ;; esac
		[ -z "$extra" ] && [ "${#id}" -le 8 ] && [ "$id" -le "$old_max" ] || return 1
	done <<EOF
$records
EOF
	while read -r family iface id extra; do
		[ -n "$family" ] || continue
		[ "$family" != ipv6 ] || [ "$NO_IPV6" -eq 0 ] || continue
		if [ "$old_mask" = "$MMX_MASK" ] &&
		   grep -Fxq "$family $iface $id" "$MULTIWAN_NFT_STATUS_DIR/conntrack_map_pending"; then
			continue
		fi
		mark=$(multiwan_nft_id2mask id old_mask)
		retired="$retired$family $mark $iface
"
	done <<EOF
$records
EOF
	if [ "$old_mask" != "$MMX_MASK" ]; then
		for family in ipv4 ipv6; do
			[ "$family" != ipv6 ] || [ "$NO_IPV6" -eq 0 ] || continue
			for id in "$((old_max+1))" "$((old_max+2))" "$((old_max+3))"; do
				mark=$(multiwan_nft_id2mask id old_mask)
				retired="$retired$family $mark special-action
"
			done
		done
	fi
	[ -n "$retired" ] || return 0
	multiwan_nft_guard_retired_marks "$old_mask" "$retired" || return 1
	while read -r family mark iface; do
		[ -n "$family" ] || continue
		multiwan_nft_flush_conntrack_mark "$family" "$mark" "$old_mask" "$iface (previous ID)" || return 1
	done <<EOF
$retired
EOF
}

multiwan_nft_commit_conntrack_map()
{
	mv "$MULTIWAN_NFT_STATUS_DIR/conntrack_map_pending" "$MULTIWAN_NFT_CONNTRACK_MAP" || return 1
	multiwan_nft_release_retired_marks || return 1
	rm -f "$MULTIWAN_NFT_UPGRADE_PENDING"
}

multiwan_nft_restore_iface_default_route()
{
	local iface="$1"
	local device="$2"
	local table="$3"
	local label="$4"
	local family true_iface status metric IP
	local route_keys route_key target mask nexthop route_metric restored=0 source_routing route_source restore_failed=0
	local default_routes default_source default_gateway match_metric
	local route_type target_type mask_type max_prefix
	MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES=""

	[ -n "$table" ] || return 0
	[ -n "$label" ] || label="table $table"

	config_get family "$iface" family ipv4
	config_get_bool source_routing globals source_routing 0
	[ -n "$device" ] || multiwan_nft_get_device device "$iface"
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
		return 1
	fi

	json_load "$status" || {
		LOG warn "Could not restore $label default route for $iface: ubus status for $true_iface is invalid"
		return 1
	}
	json_get_var metric metric
	[ -n "$metric" ] || metric=0

	json_get_type route_type route
	[ "$route_type" = array ] && json_select route 2>/dev/null || {
		LOG warn "Could not restore $label default route for $iface: ubus status for $true_iface has no route data"
		return 1
	}
	json_get_keys route_keys
	for route_key in $route_keys; do
		json_get_type route_type "$route_key"
		[ "$route_type" = object ] || { restore_failed=1; continue; }
		target=
		mask=
		nexthop=
		route_metric=
		json_select "$route_key" 2>/dev/null || continue
		json_get_var target target
		json_get_var mask mask
		json_get_var nexthop nexthop
		json_get_var route_metric metric
		json_get_var route_source source
		json_get_type target_type target
		json_get_type mask_type mask
		json_select ..
		# Malformed declarations must not look like an explicit withdrawal.
		[ "$target_type" = string ] && [ -n "$target" ] && [ "$mask_type" = int ] || { restore_failed=1; continue; }
		case "$mask" in ''|*[!0-9]*) restore_failed=1; continue ;; esac
		max_prefix=32
		[ "$family" != ipv6 ] || max_prefix=128
		[ "${#mask}" -le 3 ] && [ "$mask" -le "$max_prefix" ] || { restore_failed=1; continue; }

		[ -n "$route_metric" ] || route_metric="$metric"
		[ -n "$route_metric" ] || route_metric=0

		if [ "$family" = "ipv4" ]; then
			[ "$target" = "0.0.0.0" ] && [ "${mask:-0}" = "0" ] || continue
		else
			[ "$target" = "::" ] && [ "${mask:-0}" = "0" ] || continue
		fi

		set -- default
		default_source=::/0
		if [ "$family" = ipv6 ] && [ "$source_routing" -eq 1 ] && [ -n "$route_source" ] && [ "$route_source" != ::/0 ]; then
			set -- "$@" from "$route_source"
			default_source="$route_source"
		fi
		default_gateway=
		case "$nexthop" in ''|0.0.0.0|::) ;; *) set -- "$@" via "$nexthop"; default_gateway="$nexthop" ;; esac
		if ! $IP route replace table "$table" "$@" dev "$device" proto static metric "$route_metric" 2>/dev/null; then
			restore_failed=1
			continue
		fi
		restored=1
		LOG notice "Restored $label default route for $iface via $nexthop dev $device metric $route_metric"
		set -- route list table "$table" exact default
		[ "$family" != ipv6 ] || set -- "$@" from exact "$default_source"
		default_routes="$($IP "$@" 2>&1)" || {
			LOG warn "Could not verify $label recovery default for $iface: $default_routes"
			restore_failed=1
			continue
		}
		match_metric="$route_metric"
		[ "$family:$match_metric" != ipv6:0 ] || match_metric=1024
		# Filter only source in ip, which retains the full canonical route text.
		default_routes=$(printf '%s\n' "$default_routes" | awk -v dev="$device" -v via="$default_gateway" -v metric="$match_metric" '
			{ d=""; g=""; m=0; for (i=1; i<NF; i++) {
				if ($i=="dev") d=$(i+1); else if ($i=="via") g=$(i+1); else if ($i=="metric") m=$(i+1)
			} if (d==dev && g==via && m==metric) { sub(/[ \t]+$/, ""); print } }
		') || { restore_failed=1; continue; }
		[ -n "$default_routes" ] || {
			LOG warn "Could not identify $label recovery default for $iface via $nexthop metric $route_metric"
			restore_failed=1
			continue
		}
		MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES="$MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES$default_routes
"
	done
	json_select ..

	if [ "$restored" = "1" ]; then
		$IP route flush cache 2>/dev/null
		LOG debug "Flushed route cache after restoring $label default route for $iface"
	else
		LOG notice "No $label default route restored for $iface ($device)"
	fi
	[ "$restore_failed" -eq 0 ]
}

multiwan_nft_restore_iface_table_default_route()
{
	local id

	multiwan_nft_get_iface_id id "$1"
	[ -n "$id" ] || return 0
	multiwan_nft_restore_iface_default_route "$1" "$2" "$id" "table $id"
}

multiwan_nft_flush_conntrack()
{
	local interface="$1"
	local action="$2"
	local flush_config
	MULTIWAN_NFT_FLUSH_MATCHED=0
	MULTIWAN_NFT_FLUSH_FAILED=0

	handle_flush() {
		local flush_conntrack="$1"
		local action="$2"

		if [ "$action" = "$flush_conntrack" ] && [ "$MULTIWAN_NFT_FLUSH_MATCHED" -eq 0 ]; then
			MULTIWAN_NFT_FLUSH_MATCHED=1
			if multiwan_nft_flush_conntrack_iface "$interface"; then
				LOG info "Scoped connection tracking purge completed for interface '$interface' on action '$action'"
			else
				MULTIWAN_NFT_FLUSH_FAILED=1
			fi
		fi
	}

	# Interpret legacy scalars without rewriting the user's configuration.
	config_get flush_config "$interface" flush_conntrack
	[ "$flush_config" != always ] || flush_config=ifup
	case "$flush_config" in
		ifup|connected) handle_flush "$flush_config" "$action" ;;
		*) config_list_foreach "$interface" flush_conntrack handle_flush "$action" ;;
	esac
	[ "$MULTIWAN_NFT_FLUSH_FAILED" -eq 0 ]
}

multiwan_nft_track_clean()
{
	rm -rf "${MULTIWAN_NFT_STATUS_DIR:?}/${1}" &> /dev/null
	rmdir --ignore-fail-on-non-empty "$MULTIWAN_NFT_STATUS_DIR"
}
