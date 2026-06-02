#!/bin/sh

IP4="ip -4"
IP6="ip -6"
SCRIPTNAME="$(basename "$0")"

MULTIWAN_NFT_STATUS_DIR="/var/run/multiwan_nft"
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="${MULTIWAN_NFT_STATUS_DIR}/nft_log"
MULTIWAN_NFT_TRACK_STATUS_DIR="/var/run/multiwan-nft-track"

MULTIWAN_NFT_INTERFACE_MAX=""

MMX_MASK=""
MMX_DEFAULT=""
MMX_BLACKHOLE=""
MMX_INVMASK=""
MM_BLACKHOLE=""

MMX_UNREACHABLE=""
MM_UNREACHABLE=""
MAX_SLEEP=$(((1<<31)-1))

# Check for IPv6 support
[ -f /proc/net/if_inet6 ]
NO_IPV6=$?

# nftables commands
NFT="nft"
NFT_TABLE="multiwan_nft"
NFT_FAMILY="inet"

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
	local tmpfile
	# FIX: Use mktemp instead of $$ to prevent symlink attacks (Bug #5)
	tmpfile="$(mktemp /tmp/multiwan_nft-rules-XXXXXX.nft)" || {
		LOG error "Failed to create temp file for nftables rules"
		return 1
	}
	echo "$MULTIWAN_NFT_NFT_BUF" > "$tmpfile"
	if $NFT -f "$tmpfile" 2>/dev/null; then
		rm -f "$tmpfile"
		return 0
	else
		LOG error "Failed to load nftables rules from $tmpfile"
		# Keep file for debugging
		return 1
	fi
}

LOG()
{
	local facility=$1; shift
	# in development, we want to show 'debug' level logs
	# when this release is out of beta, the comment in the line below
	# should be removed
	[ "$facility" = "debug" ] && return
	logger -t "${SCRIPTNAME}[$$]" -p $facility "$*"
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
	ubus call "network.interface.${2}_${V}" status &>/dev/null && _true_iface="${2}_${V}"
	export "$1=$_true_iface"
}

multiwan_nft_get_src_ip()
{
	local family _src_ip interface true_iface device addr_cmd default_ip IP sed_str
	interface=$2
	multiwan_nft_get_true_iface true_iface $interface

	unset "$1"
	config_get family "$interface" family ipv4
	if [ "$family" = "ipv4" ]; then
		addr_cmd='network_get_ipaddr'
		default_ip="0.0.0.0"
		sed_str='s/ *inet \([^ \/]*\).*/\1/;T; pq'
		IP="$IP4"
	elif [ "$family" = "ipv6" ]; then
		addr_cmd='network_get_ipaddr6'
		default_ip="::"
		sed_str='s/ *inet6 \([^ \/]*\).* scope.*/\1/;T; pq'
		IP="$IP6"
	fi

	$addr_cmd _src_ip "$true_iface"
	if [ -z "$_src_ip" ]; then
		network_get_device device $true_iface
		_src_ip=$($IP address ls dev $device 2>/dev/null | sed -ne "$sed_str")
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
	local track_ips pid
	multiwan_nft_list_track_ips()
	{
		track_ips="$1 $track_ips"
	}
	config_list_foreach "$1" track_ip multiwan_nft_list_track_ips

	if [ -n "$track_ips" ]; then
		pid="$(pgrep -f "multiwan-nft-track $1$")"
		if [ -n "$pid" ]; then
			if [ "$(cat /proc/"$(pgrep -P $pid)"/cmdline)" = "sleep${MAX_SLEEP}" ]; then
				tracking="paused"
			else
				tracking="active"
			fi
		else
			tracking="down"
		fi
	else
		tracking="not enabled"
	fi
	echo "$tracking"
}

multiwan_nft_init()
{
	local bitcnt mmdefault source_routing

	config_load 'multiwan-nft'

	[ -d $MULTIWAN_NFT_STATUS_DIR ] || mkdir -p $MULTIWAN_NFT_STATUS_DIR/iface_state
	[ -d "$MULTIWAN_NFT_STATUS_NFT_LOG_DIR" ] || mkdir -p "$MULTIWAN_NFT_STATUS_NFT_LOG_DIR"

	# multiwan_nft's MARKing mask (at least 3 bits should be set)
	if [ -e "${MULTIWAN_NFT_STATUS_DIR}/mmx_mask" ]; then
		MMX_MASK=$(cat "${MULTIWAN_NFT_STATUS_DIR}/mmx_mask" 2>/dev/null)
	else
		config_get MMX_MASK globals mmx_mask '0x3F0000'
		echo "$MMX_MASK"| tr 'A-F' 'a-f' > "${MULTIWAN_NFT_STATUS_DIR}/mmx_mask"
		LOG debug "Using firewall mask ${MMX_MASK}"
	fi

	case "$MMX_MASK" in
		""|*[!0-9a-fA-FxX]*) MMX_MASK='0x3F0000' ;;
	esac

	bitcnt=$(multiwan_nft_count_one_bits "$MMX_MASK")
	mmdefault=$(((1<<bitcnt)-1))
	MULTIWAN_NFT_INTERFACE_MAX=$((mmdefault-3))
	[ "$MULTIWAN_NFT_INTERFACE_MAX" -lt 0 ] && MULTIWAN_NFT_INTERFACE_MAX=0
	LOG debug "Max interface count is ${MULTIWAN_NFT_INTERFACE_MAX}"

	# remove "linkdown", expiry and source based routing modifiers from route lines
	config_get_bool source_routing globals source_routing 0
	[ "$source_routing" -eq 1 ] && unset source_routing
	MULTIWAN_NFT_ROUTE_LINE_EXP="s/offload//; s/linkdown //; s/expires [0-9]\+sec//; s/error [0-9]\+//; ${source_routing:+s/default\(.*\) from [^ ]*/default\1/;} p"

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
