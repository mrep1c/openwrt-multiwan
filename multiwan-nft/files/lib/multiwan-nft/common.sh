#!/bin/sh

IP4="${IP4:-ip -4}"
IP6="${IP6:-ip -6}"
SCRIPTNAME="${SCRIPTNAME:-${0##*/}}"

MULTIWAN_NFT_STATUS_DIR="${MULTIWAN_NFT_STATUS_DIR:-/var/run/multiwan_nft}"
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="${MULTIWAN_NFT_STATUS_DIR}/nft_log"
MULTIWAN_NFT_TRACK_STATUS_DIR="${MULTIWAN_NFT_TRACK_STATUS_DIR:-/var/run/multiwan-nft-track}"
MULTIWAN_NFT_TRACK_OWNER_FORMAT_FILE="${MULTIWAN_NFT_STATUS_DIR}/tracker-owner-v1"
MULTIWAN_NFT_PROC_ROOT="${MULTIWAN_NFT_PROC_ROOT:-/proc}"
MULTIWAN_NFT_UPTIME_FILE="${MULTIWAN_NFT_UPTIME_FILE:-${MULTIWAN_NFT_PROC_ROOT}/uptime}"

MULTIWAN_NFT_INTERFACE_MAX=""

MMX_MASK=""
MMX_DEFAULT=""
MMX_BLACKHOLE=""
MMX_INVMASK=""
MM_BLACKHOLE=""

MMX_UNREACHABLE=""
MM_UNREACHABLE=""
MAX_SLEEP=$(((1<<31)-1))

# Check for kernel IPv6 support. Configured MultiWAN IPv6 use is checked
# separately after UCI has been loaded.
if [ -z "${NO_IPV6+x}" ]; then
	[ -f "${MULTIWAN_NFT_PROC_ROOT}/net/if_inet6" ]
	NO_IPV6=$?
fi

# nftables commands
NFT="${NFT:-nft}"
NFT_TABLE="${NFT_TABLE:-multiwan_nft}"
NFT_FAMILY="${NFT_FAMILY:-inet}"

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

MULTIWAN_NFT_TRACKING_CONFIGURED=0
MULTIWAN_NFT_LEGACY_TRACK_STATUS=""

multiwan_nft_collect_track_ip()
{
	MULTIWAN_NFT_TRACKING_CONFIGURED=1
}

# Keep tracker status queries cheap: the tracker publishes its PID and kernel
# start time in tmpfs. The start time prevents a reused PID from being treated
# as the old tracker process.
multiwan_nft_process_start_time()
{
	local pid="$1" stat rest

	case "$pid" in
		""|*[!0-9]*) return 1 ;;
	esac
	[ -r "${MULTIWAN_NFT_PROC_ROOT}/$pid/stat" ] || return 1
	stat=""
	{ IFS= read -r stat < "${MULTIWAN_NFT_PROC_ROOT}/$pid/stat" || [ -n "$stat" ]; } 2>/dev/null || return 1
	rest="${stat##*) }"
	set -- $rest
	[ "$#" -ge 20 ] || return 1
	shift 19
	case "$1" in
		""|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$1"
}

multiwan_nft_process_identity_alive()
{
	local pid="$1" expected_start="$2" current_start

	case "$pid:$expected_start" in
		*[!0-9:]*|:|*:) return 1 ;;
	esac
	kill -0 "$pid" 2>/dev/null || return 1
	current_start="$(multiwan_nft_process_start_time "$pid")" || return 1
	[ "$current_start" = "$expected_start" ]
}

# Compatibility fallback for a tracker that was already running while the
# package was upgraded. New tracker processes always use the owner journal.
multiwan_nft_get_legacy_track_status()
{
	local interface="$1" pid pid_dir cmdline child_dir child_ppid child_cmdline

	pid=""
	for pid_dir in "${MULTIWAN_NFT_PROC_ROOT}"/[0-9]*; do
		[ -r "$pid_dir/cmdline" ] || continue
		cmdline="$(tr '\0' ' ' 2>/dev/null < "$pid_dir/cmdline")"
		case "$cmdline" in
			*"/usr/sbin/multiwan-nft-track $interface"|*"/usr/sbin/multiwan-nft-track $interface ")
				pid="${pid_dir##*/}"
				break
				;;
		esac
	done
	[ -n "$pid" ] || return 1

	MULTIWAN_NFT_LEGACY_TRACK_STATUS="active"
	for child_dir in "${MULTIWAN_NFT_PROC_ROOT}"/[0-9]*; do
		[ -r "$child_dir/status" ] || continue
		child_ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "$child_dir/status" 2>/dev/null)"
		[ "$child_ppid" = "$pid" ] || continue
		child_cmdline="$(tr '\0' ' ' 2>/dev/null < "$child_dir/cmdline")"
		case "$child_cmdline" in
			"sleep $MAX_SLEEP"|"sleep $MAX_SLEEP ")
				MULTIWAN_NFT_LEGACY_TRACK_STATUS="paused"
				break
				;;
		esac
	done
	return 0
}

multiwan_nft_get_track_status()
{
	local interface="$1" owner_file pid start token

	MULTIWAN_NFT_TRACKING_CONFIGURED=0
	config_list_foreach "$interface" track_ip multiwan_nft_collect_track_ip
	if [ "$MULTIWAN_NFT_TRACKING_CONFIGURED" -eq 0 ]; then
		printf '%s\n' "not enabled"
		return 0
	fi

	owner_file="${MULTIWAN_NFT_TRACK_STATUS_DIR}/${interface}/OWNER"
	pid=""
	start=""
	token=""
	if [ -r "$owner_file" ]; then
		read -r pid start token < "$owner_file" || true
	fi
	case "$token" in
		"tracker:${interface}:"*)
			if multiwan_nft_process_identity_alive "$pid" "$start"; then
				printf '%s\n' "active"
				return 0
			fi
			;;
	esac

	# start_service creates this marker only after procd has replaced any
	# pre-upgrade trackers. From then on, a missing/dead owner means down and
	# does not require a compatibility scan of /proc.
	if [ -e "$MULTIWAN_NFT_TRACK_OWNER_FORMAT_FILE" ]; then
		printf '%s\n' "down"
		return 0
	fi

	if multiwan_nft_get_legacy_track_status "$interface"; then
		printf '%s\n' "$MULTIWAN_NFT_LEGACY_TRACK_STATUS"
	else
		printf '%s\n' "down"
	fi
}

MULTIWAN_NFT_ENABLED_FAMILY_WANTED=""
MULTIWAN_NFT_ENABLED_FAMILY_FOUND=0

multiwan_nft_check_enabled_family()
{
	local section="$1" enabled family

	config_get_bool enabled "$section" enabled 0
	[ "$enabled" -eq 1 ] || return
	config_get family "$section" family ipv4
	[ "$family" = "$MULTIWAN_NFT_ENABLED_FAMILY_WANTED" ] &&
		MULTIWAN_NFT_ENABLED_FAMILY_FOUND=1
}

multiwan_nft_has_enabled_family()
{
	local wanted_family="$1"

	case "$wanted_family" in
		ipv4|ipv6) ;;
		*) return 1 ;;
	esac

	MULTIWAN_NFT_ENABLED_FAMILY_WANTED="$wanted_family"
	MULTIWAN_NFT_ENABLED_FAMILY_FOUND=0
	config_foreach multiwan_nft_check_enabled_family interface
	[ "$MULTIWAN_NFT_ENABLED_FAMILY_FOUND" -eq 1 ]
}

multiwan_nft_init()
{
	local bitcnt mmdefault source_routing mask_file mask_tmp cached_mask normalized_mask

	config_load 'multiwan-nft'

	if [ ! -d "$MULTIWAN_NFT_STATUS_DIR/iface_state" ] ||
		[ ! -d "$MULTIWAN_NFT_STATUS_NFT_LOG_DIR" ]; then
		mkdir -p "$MULTIWAN_NFT_STATUS_DIR/iface_state" \
			"$MULTIWAN_NFT_STATUS_NFT_LOG_DIR" || return 1
	fi

	# MultiWAN NFT routing mark mask. The lower byte is reserved for MultiWAN QoS.
	mask_file="${MULTIWAN_NFT_STATUS_DIR}/mmx_mask"
	cached_mask=
	if [ -s "$mask_file" ]; then
		{ IFS= read -r cached_mask < "$mask_file" || [ -n "$cached_mask" ]; } 2>/dev/null || cached_mask=
	fi
	if [ -n "$cached_mask" ] &&
		normalized_mask="$(multiwan_nft_normalize_mask "$cached_mask" 2>/dev/null)"; then
		MMX_MASK="$normalized_mask"
	else
		[ ! -e "$mask_file" ] || LOG warn "Ignoring empty or invalid cached firewall mask; reloading it from UCI"
		config_get MMX_MASK globals mmx_mask '0x3F0000'
		normalized_mask="$(multiwan_nft_normalize_mask "$MMX_MASK")" || return 1
		MMX_MASK="$normalized_mask"
	fi

	# Avoid rewriting the tmpfs cache on every CLI, hotplug, and monitor init.
	if [ "$cached_mask" != "$MMX_MASK" ]; then
		mask_tmp="$(mktemp "${MULTIWAN_NFT_STATUS_DIR}/mmx_mask.XXXXXX")" || {
			LOG error "Failed to create temporary firewall mask state file"
			return 1
		}
		if printf '%s\n' "$MMX_MASK" > "$mask_tmp"; then
			mv "$mask_tmp" "$mask_file" || {
				rm -f "$mask_tmp"
				LOG error "Failed to update firewall mask state file"
				return 1
			}
		else
			rm -f "$mask_tmp"
			LOG error "Failed to write firewall mask state file"
			return 1
		fi
	fi
	LOG debug "Using firewall mask ${MMX_MASK}"

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
	bitcnt=$(multiwan_nft_count_one_bits "$MMX_MASK")
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
	local uptime

	uptime=""
	{ IFS=' ' read -r uptime _ < "$MULTIWAN_NFT_UPTIME_FILE" || [ -n "$uptime" ]; } 2>/dev/null || return 1
	printf '%s\n' "${uptime%%.*}"
}

get_online_time() {
	local time_n time_u iface
	iface="$1"
	time_u=""
	if [ -r "$MULTIWAN_NFT_TRACK_STATUS_DIR/${iface}/ONLINE" ]; then
		{ IFS= read -r time_u < "$MULTIWAN_NFT_TRACK_STATUS_DIR/${iface}/ONLINE" || [ -n "$time_u" ]; } 2>/dev/null || time_u=
	fi
	[ -z "${time_u}" ] || [ "${time_u}" = "0" ] || {
		time_n="$(get_uptime)"
		printf '%s\n' $((time_n-time_u))
	}
}
