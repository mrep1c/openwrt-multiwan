#!/bin/sh

IP4="ip -4"
IP6="ip -6"
SCRIPTNAME="$(basename "$0")"

MULTIWAN_NFT_STATUS_DIR="/var/run/multiwan_nft"
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="${MULTIWAN_NFT_STATUS_DIR}/nft_log"
MULTIWAN_NFT_TRACK_STATUS_DIR="/var/run/multiwan-nft-track"
# Survives service stop so a later start can identify old conntrack marks.
MULTIWAN_NFT_CONNTRACK_MAP="/var/run/multiwan-nft-conntrack-map"
MULTIWAN_NFT_UPGRADE_PENDING="/var/run/multiwan-nft-upgrade-pending"

MULTIWAN_NFT_INTERFACE_MAX=""

MMX_MASK=""
MMX_DEFAULT=""
MMX_BLACKHOLE=""
MMX_INVMASK=""
MM_BLACKHOLE=""

MMX_UNREACHABLE=""
MM_UNREACHABLE=""

# Check for kernel IPv6 support. Configured MultiWAN IPv6 use is checked
# separately after UCI has been loaded.
[ -f /proc/net/if_inet6 ]
NO_IPV6=$?

# nftables commands
NFT="nft"
NFT_TABLE="multiwan_nft"
NFT_FAMILY="inet"

multiwan_nft_reconfiguration_pending()
{
	$NFT list table "$NFT_FAMILY" "${NFT_TABLE}_reconcile" >/dev/null 2>&1
}

# Atomic ruleset buffer
MULTIWAN_NFT_NFT_BUF=""

# Initialize the nft buffer for atomic loading
multiwan_nft_nft_buf_init() {
	MULTIWAN_NFT_NFT_BUF=""
}

# Add a line to the nft buffer
multiwan_nft_nft_buf_add() {
	MULTIWAN_NFT_NFT_BUF="${MULTIWAN_NFT_NFT_BUF}${1}
"
}

# Load the buffered rules atomically
multiwan_nft_nft_buf_commit() {
	local tmpfile errfile
	tmpfile="$(mktemp /tmp/multiwan_nft-rules.XXXXXX)" || {
		LOG error "Failed to create temp file for nftables rules"
		return 1
	}
	errfile="${tmpfile}.error"
	printf '%s' "$MULTIWAN_NFT_NFT_BUF" > "$tmpfile"
	if $NFT -f "$tmpfile" >"$errfile" 2>&1; then
		rm -f "$tmpfile" "$errfile"
		return 0
	else
		LOG error "Failed to load nftables rules from $tmpfile"
		if [ -s "$errfile" ]; then
			while IFS= read -r line; do
				[ -n "$line" ] && LOG error "nft: $line"
			done < "$errfile"
		else
			rm -f "$errfile"
		fi
		# Keep the transaction and any error output for troubleshooting.
		return 1
	fi
}

multiwan_nft_debug_enabled()
{
	case "${MULTIWAN_NFT_DEBUG:-0}" in
		1|yes|true|on) return 0 ;;
	esac
	return 1
}

LOG()
{
	local facility=$1; shift
	[ "$facility" = "debug" ] && ! multiwan_nft_debug_enabled && return
	logger -t "${SCRIPTNAME}[$$]" -p $facility "$*"
}

multiwan_nft_connected_elements()
(
	local family="$1" suffix document keys key
	case "$family" in ipv4) suffix=v4 ;; ipv6) [ "$NO_IPV6" -eq 0 ] || return 0; suffix=v6 ;; *) return 1 ;; esac
	document="$($NFT -j list set "$NFT_FAMILY" "$NFT_TABLE" "multiwan_nft_connected_$suffix")" || return 1
	json_load "$document" || return 1
	json_select nftables || return 1
	json_get_keys keys
	for key in $keys; do
		json_select "$key" || return 1
		if json_select set 2>/dev/null; then
			if json_select elem 2>/dev/null; then
				local element_keys element_key
				json_get_keys element_keys
				multiwan_nft_print_element() {
					local kind address length first last
					json_get_type kind "$1"
					if [ "$kind" = string ]; then
						json_get_var address "$1"
						printf '%s\n' "$address"
						return
					fi
					json_select "$1" || return 1
					if json_select prefix 2>/dev/null; then
						json_get_var address addr
						json_get_var length len
						printf '%s/%s\n' "$address" "$length"
						json_select ..
					elif json_select range 2>/dev/null; then
						json_get_var first 1
						json_get_var last 2
						printf '%s-%s\n' "$first" "$last"
						json_select ..
					elif json_select elem 2>/dev/null; then
						multiwan_nft_print_element val || return 1
						json_select ..
					else
						return 1
					fi
					json_select ..
				}
				for element_key in $element_keys; do multiwan_nft_print_element "$element_key" || return 1; done
				json_select ..
			fi
			json_select ..
		fi
		json_select ..
	done
)

multiwan_nft_policy_members()
(
	local chain="$1" wanted="$2" document keys key comment iface weight total family section_type rows=""
	document="$($NFT -j list chain "$NFT_FAMILY" "$NFT_TABLE" "$chain")" || return 1
	json_load "$document" || return 1
	json_select nftables || return 1
	json_get_keys keys
	for key in $keys; do
		json_select "$key" || return 1
		if json_select rule 2>/dev/null; then
			json_get_var comment comment
			set -- $comment
			if [ "$#" -eq 3 ]; then
				iface="$1"; weight="$2"; total="$3"
				case "$weight:$total" in *[!0-9:]*|:*|*:|*:*:*) ;; *)
					[ "$weight" -gt 0 ] && [ "$total" -gt 0 ] || { json_select ..; json_select ..; continue; }
					config_get section_type "$iface" TYPE
					[ "$section_type" = interface ] || { json_select ..; json_select ..; continue; }
					config_get family "$iface" family ipv4
					[ "$family" != "$wanted" ] || rows="$rows$iface $weight
"
					;;
				esac
			fi
			json_select ..
		fi
		json_select ..
	done
	printf '%s' "$rows" | awk 'NF == 2 { if (!seen[$1]++) order[++n] = $1; weights[$1] += $2 } END { for (i = 1; i <= n; i++) print order[i], weights[order[i]] }'
)

multiwan_nft_get_logical_iface()
{
	local _logical_iface="$2" parent family section_type
	config_get section_type "$2" TYPE
	if [ "$section_type" != interface ]; then
		case "$2" in
			*_4) parent="${2%_4}"; family=ipv4 ;;
			*_6) parent="${2%_6}"; family=ipv6 ;;
			*) parent= ;;
		esac
		if [ -n "$parent" ]; then
			config_get section_type "$parent" TYPE
			if [ "$section_type" = interface ]; then
				local parent_family
				config_get parent_family "$parent" family ipv4
				[ "$parent_family" != "$family" ] || _logical_iface="$parent"
			fi
		fi
	fi
	export "$1=$_logical_iface"
}

multiwan_nft_get_true_iface()
{
	local family V
	_true_iface=$2
	config_get family "$2" family ipv4
	if [ "$family" = "ipv4" ]; then
		V=4
	elif [ "$family" = "ipv6" ]; then
		V=6
	fi
	ubus call "network.interface.${2}_${V}" status >/dev/null 2>&1 && _true_iface="${2}_${V}"
	export "$1=$_true_iface"
}

multiwan_nft_get_device()
{
	local _device_iface
	multiwan_nft_get_true_iface _device_iface "$2"
	network_get_device "$1" "$_device_iface"
}

multiwan_nft_get_src_ip()
{
	local family _src_ip interface true_iface device addr_cmd default_ip IP sed_str prefix
	interface=$2
	multiwan_nft_get_true_iface true_iface $interface

	unset "$1"
	config_get family "$interface" family ipv4
	if [ "$family" = "ipv4" ]; then
		addr_cmd='network_get_ipaddr'
		default_ip="0.0.0.0"
		sed_str='s/ *inet \([^ \/]*\).*/\1/;T; p;q'
		IP="$IP4"
	elif [ "$family" = "ipv6" ]; then
		addr_cmd='network_get_ipaddr6'
		default_ip="::"
		sed_str='s/ *inet6 \([^ \/]*\).* scope.*/\1/;T; p;q'
		IP="$IP6"
	fi

	$addr_cmd _src_ip "$true_iface"
	if [ -z "$_src_ip" ] && [ "$family" = ipv6 ]; then
		network_get_prefix6 prefix "$true_iface"
		[ -z "$prefix" ] || _src_ip=$($IP6 address ls to "$prefix" scope global 2>/dev/null | sed -ne "$sed_str")
	fi
	if [ -z "$_src_ip" ]; then
		network_get_device device $true_iface
		_src_ip=$($IP address ls dev "$device" scope global 2>/dev/null | sed -ne "$sed_str")
		if [ -n "$_src_ip" ]; then
			LOG warn "no src $family address found from netifd for interface '$true_iface' dev '$device' guessing $_src_ip"
		else
			_src_ip="$default_ip"
			LOG warn "no src $family address found for interface '$true_iface' dev '$device'"
		fi
	fi
	export "$1=$_src_ip"
}

multiwan_nft_get_track_status()
{
	local track_ips pid pid_dir cmdline status
	multiwan_nft_list_track_ips()
	{
		track_ips="$1 $track_ips"
	}
	config_list_foreach "$1" track_ip multiwan_nft_list_track_ips

	if [ -n "$track_ips" ]; then
		pid=""
		for pid_dir in /proc/[0-9]*; do
			[ -r "$pid_dir/cmdline" ] || continue
			cmdline="$(tr '\0' ' ' 2>/dev/null < "$pid_dir/cmdline")"
			case "$cmdline" in
				*"/usr/sbin/multiwan-nft-track $1"|*"/usr/sbin/multiwan-nft-track $1 ")
					pid="${pid_dir##*/}"
					break
					;;
			esac
		done
		if [ -n "$pid" ]; then
			status="$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/$1/STATUS" 2>/dev/null)"
			case "$status" in
				disabled|waiting) tracking="paused" ;;
				*) tracking="active" ;;
			esac
		else
			tracking="down"
		fi
	else
		tracking="not enabled"
	fi
	echo "$tracking"
}

multiwan_nft_has_enabled_family()
{
	local wanted_family="$1"

	case "$wanted_family" in
		ipv4|ipv6) ;;
		*) return 1 ;;
	esac

	MULTIWAN_NFT_ENABLED_FAMILY_FOUND=0
	multiwan_nft_check_enabled_family()
	{
		local section="$1" enabled family

		config_get_bool enabled "$section" enabled 0
		[ "$enabled" -eq 1 ] || return
		config_get family "$section" family ipv4
		[ "$family" = "$wanted_family" ] &&
			MULTIWAN_NFT_ENABLED_FAMILY_FOUND=1
	}

	config_foreach multiwan_nft_check_enabled_family interface
	[ "$MULTIWAN_NFT_ENABLED_FAMILY_FOUND" -eq 1 ]
}

multiwan_nft_init()
{
	local bitcnt mmdefault route_modifiers source_routing mask_file cached_mask normalized_mask interface_count=0 mode="${1:-}"

	config_load 'multiwan-nft' || return 1

	# MultiWAN NFT routing mark mask. The lower byte is reserved for MultiWAN QoS.
	mask_file="${MULTIWAN_NFT_STATUS_DIR}/mmx_mask"
	cached_mask=
	# Startup applies UCI; queries, workers and cleanup retain the active mask.
	[ "$mode" != startup ] && [ "$mode" != prepare ] && [ -s "$mask_file" ] && cached_mask="$(cat "$mask_file" 2>/dev/null)"
	if [ -n "$cached_mask" ] &&
		normalized_mask="$(multiwan_nft_normalize_mask "$cached_mask" 2>/dev/null)"; then
		MMX_MASK="$normalized_mask"
	else
		[ "$mode" = startup ] || [ "$mode" = prepare ] || [ ! -e "$mask_file" ] || LOG warn "Ignoring empty or invalid cached firewall mask; reloading it from UCI"
		config_get MMX_MASK globals mmx_mask '0x3F0000'
		normalized_mask="$(multiwan_nft_normalize_mask "$MMX_MASK")" || return 1
		MMX_MASK="$normalized_mask"
	fi

	bitcnt=$(multiwan_nft_count_one_bits "$MMX_MASK")
	mmdefault=$(((1<<bitcnt)-1))
	MULTIWAN_NFT_INTERFACE_MAX=$((mmdefault-3))
	[ "$MULTIWAN_NFT_INTERFACE_MAX" -lt 0 ] && MULTIWAN_NFT_INTERFACE_MAX=0
	LOG debug "Max interface count is ${MULTIWAN_NFT_INTERFACE_MAX}"
	multiwan_nft_count_interface() { interface_count=$((interface_count + 1)); }
	config_foreach multiwan_nft_count_interface interface
	if [ "${1:-}" != cleanup ] && [ "$interface_count" -gt "$MULTIWAN_NFT_INTERFACE_MAX" ]; then
		LOG error "$interface_count interface sections exceed the $MULTIWAN_NFT_INTERFACE_MAX IDs available in mask $MMX_MASK"
		return 1
	fi

	if [ "$mode" != readonly ]; then
		mkdir -p "$MULTIWAN_NFT_STATUS_DIR/iface_state" "$MULTIWAN_NFT_STATUS_NFT_LOG_DIR" || return 1
		if [ "$mode" != prepare ]; then
			multiwan_nft_publish_mask || return 1
		fi
	fi
	LOG debug "Using firewall mask ${MMX_MASK}"

	# Remove unsupported flags, expiry and source based routing modifiers.
	config_get_bool source_routing globals source_routing 0
	[ "$source_routing" -eq 1 ] && unset source_routing
	route_modifiers="s/offload//; s/ dead / /; s/ dead$/ /;"
	route_modifiers="$route_modifiers s/ linkdown / /; s/ linkdown$/ /;"
	route_modifiers="$route_modifiers s/expires [0-9]\+sec//; s/error [0-9]\+//;"
	# Match route events to the normalized table snapshots.
	MULTIWAN_NFT_ROUTE_LINE_EXP="$route_modifiers ${source_routing:+s/default\(.*\) from [^ ]*/default\1/;} s/[[:space:]]\+/ /g; s/^ //; s/ $//; p"

	# mark mask constants
	bitcnt=$(multiwan_nft_count_one_bits MMX_MASK)
	mmdefault=$(((1<<bitcnt)-1))
	MM_BLACKHOLE=$((mmdefault-2))
	MM_UNREACHABLE=$((mmdefault-1))

	# MMX_DEFAULT should equal MMX_MASK
	MMX_DEFAULT=$(multiwan_nft_id2mask mmdefault MMX_MASK)
	MMX_BLACKHOLE=$(multiwan_nft_id2mask MM_BLACKHOLE MMX_MASK)
	MMX_UNREACHABLE=$(multiwan_nft_id2mask MM_UNREACHABLE MMX_MASK)
	# Inverted mask: only clears multiwan_nft's bits when saving ct mark
	# Makes ct mark save independent of any other ct mark user (MultiWAN QoS, etc.)
	MMX_INVMASK=$(printf "0x%08x" $(( 0xFFFFFFFF ^ $(printf "%d" "$MMX_MASK") )))
}

multiwan_nft_publish_mask()
{
	local mask_file="${MULTIWAN_NFT_STATUS_DIR}/mmx_mask" mask_tmp normalized_mask
	normalized_mask="$(multiwan_nft_normalize_mask "$MMX_MASK")" || return 1
	mask_tmp="$(mktemp "${MULTIWAN_NFT_STATUS_DIR}/mmx_mask.XXXXXX")" || {
		LOG error "Failed to create temporary firewall mask state file"
		return 1
	}
	if printf '%s\n' "$normalized_mask" > "$mask_tmp"; then
		mv "$mask_tmp" "$mask_file" && return 0
	fi
	rm -f "$mask_tmp"
	LOG error "Failed to publish firewall mask state"
	return 1
}

multiwan_nft_normalize_mask()
{
	local value="$1" mask_hex mask_dec bitcnt

	case "$value" in
		0x*|0X*) ;;
		*)
			LOG error "Invalid firewall mask '$value': use a hexadecimal value starting with 0x"
			return 1
			;;
	esac

	mask_hex="${value#0x}"
	mask_hex="${mask_hex#0X}"
	case "$mask_hex" in
		""|*[!0-9a-fA-F]*)
			LOG error "Invalid firewall mask '$value': use only hexadecimal digits"
			return 1
			;;
	esac

	if [ "${#mask_hex}" -gt 8 ]; then
		LOG error "Invalid firewall mask '$value': value must fit in 32 bits"
		return 1
	fi

	mask_dec=$((0x$mask_hex))
	if [ $((mask_dec & 0x000000ff)) -ne 0 ]; then
		LOG error "Invalid firewall mask '$value': lower 8 bits are reserved for MultiWAN QoS"
		return 1
	fi

	bitcnt=$(multiwan_nft_count_one_bits "$mask_dec")
	if [ "$bitcnt" -lt 3 ]; then
		LOG error "Invalid firewall mask '$value': at least 3 bits must be set"
		return 1
	fi

	printf "0x%08x\n" "$mask_dec"
}

# maps the 1st parameter so it only uses the bits allowed by the bitmask (2nd parameter)
# which means spreading the bits of the 1st parameter to only use the bits that are set to 1 in the 2nd parameter
# 0 0 0 0 0 1 0 1 (0x05) 1st parameter
# 1 0 1 0 1 0 1 0 (0xAA) 2nd parameter
#     1   0   1          result
multiwan_nft_id2mask()
{
	local bit_msk bit_val result
	bit_val=0
	result=0
	bit_msk=0
	while [ "$bit_msk" -le 31 ]; do
		if [ $((($2>>bit_msk)&1)) = "1" ]; then
			if [ $((($1>>bit_val)&1)) = "1" ]; then
				result=$((result|(1<<bit_msk)))
			fi
			bit_val=$((bit_val+1))
		fi
		bit_msk=$((bit_msk+1))
	done
	printf "0x%x" $result
}

# counts how many bits are set to 1
# n&(n-1) clears the lowest bit set to 1
multiwan_nft_count_one_bits()
{
	local count n
	count=0
	n=$(($1))
	while [ "$n" -gt "0" ]; do
		n=$((n&(n-1)))
		count=$((count+1))
	done
	echo $count
}

get_uptime() {
	local uptime=$(cat /proc/uptime)
	echo "${uptime%%.*}"
}

get_online_time() {
	local time_n time_u iface
	iface="$1"
	time_u="$(cat "$MULTIWAN_NFT_TRACK_STATUS_DIR/${iface}/ONLINE" 2>/dev/null)"
	[ -z "${time_u}" ] || [ "${time_u}" = "0" ] || {
		time_n="$(get_uptime)"
		echo $((time_n-time_u))
	}
}
