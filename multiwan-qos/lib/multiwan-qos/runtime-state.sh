#!/bin/sh

# Shared runtime-state helpers for the init service and dataplane engine.
# Keep qdisc ownership, offload journaling, and ETS probing in one place so
# start, stop, rollback, refresh, and hotplug all enforce the same rules.

: "${MULTIWAN_QOS_RUNTIME_ROOT:=/var/run/multiwan-qos}"
: "${MULTIWAN_QOS_QDISC_LEDGER:=$MULTIWAN_QOS_RUNTIME_ROOT/qdisc-devices}"
: "${MULTIWAN_QOS_OFFLOAD_ROOT:=$MULTIWAN_QOS_RUNTIME_ROOT/offloads}"
: "${MULTIWAN_QOS_ETS_PROBE_STATE:=$MULTIWAN_QOS_RUNTIME_ROOT/ets-probe-device}"
: "${MULTIWAN_QOS_SCH_ETS_DIR:=/sys/module/sch_ets}"
MULTIWAN_QOS_ETS_PROBE_DEVICE="${MULTIWAN_QOS_ETS_PROBE_DEVICE:-}"

mw_qos_warn() {
	if type log_msg >/dev/null 2>&1; then
		log_msg -warn "$1"
	else
		logger -t multiwan_qos "Warning: $1"
	fi
}

mw_qos_error() {
	if type error_out >/dev/null 2>&1; then
		error_out "$1"
	elif type log_msg >/dev/null 2>&1; then
		log_msg -err "$1"
	else
		logger -t multiwan_qos "Error: $1"
	fi
}

mw_qos_device_name_safe() {
	case "$1" in
		''|*[!A-Za-z0-9_.:@-]*) return 1 ;;
	esac
}

mw_qos_owned_root_present() {
	tc qdisc show dev "$1" 2>/dev/null |
		grep -Eq '^qdisc (hfsc|htb|cake|cake_mq) .* root'
}

mw_qos_ingress_present() {
	tc qdisc show dev "$1" 2>/dev/null | grep -q '^qdisc ingress ffff:'
}

mw_qos_is_ifb() {
	ip -o link show type ifb 2>/dev/null | awk -F': ' -v expected="$1" '
		{
			name = $2
			sub(/@.*/, "", name)
			if (name == expected) found = 1
		}
		END { exit(found ? 0 : 1) }
	'
}

# Remove only MultiWAN QoS-owned qdiscs plus the matching owned IFB. The
# function verifies final state and returns failure if any owned object remains.
mw_qos_cleanup_device() {
	local device="$1" lan_dev="ifb-$1" result=0

	mw_qos_device_name_safe "$device" || return 1
	command -v tc >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 || {
		mw_qos_warn "Cannot verify QoS cleanup for $device because tc or ip is unavailable."
		return 1
	}
	if mw_qos_owned_root_present "$device"; then
		tc qdisc del dev "$device" root >/dev/null 2>&1 ||
			mw_qos_warn "Root qdisc removal command failed for $device; verifying final state."
	fi
	if mw_qos_ingress_present "$device"; then
		tc qdisc del dev "$device" ingress >/dev/null 2>&1 ||
			mw_qos_warn "Ingress qdisc removal command failed for $device; verifying final state."
	fi
	if ip link show "$lan_dev" >/dev/null 2>&1; then
		if ! mw_qos_is_ifb "$lan_dev"; then
			mw_qos_warn "Refusing to remove non-IFB device $lan_dev."
			result=1
		else
			if mw_qos_owned_root_present "$lan_dev"; then
				tc qdisc del dev "$lan_dev" root >/dev/null 2>&1 ||
					mw_qos_warn "Root qdisc removal command failed for $lan_dev; verifying final state."
			fi
			ip link del "$lan_dev" >/dev/null 2>&1 ||
				mw_qos_warn "IFB removal command failed for $lan_dev; verifying final state."
		fi
	fi
	if mw_qos_owned_root_present "$device"; then
		mw_qos_warn "Owned root qdisc remains on $device after teardown."
		result=1
	fi
	if mw_qos_ingress_present "$device"; then
		mw_qos_warn "Owned ingress qdisc remains on $device after teardown."
		result=1
	fi
	if ip link show "$lan_dev" >/dev/null 2>&1; then
		mw_qos_warn "Owned IFB device $lan_dev remains after teardown."
		result=1
	fi
	return "$result"
}

mw_qos_offload_feature_name() {
	case "$1" in
		gro) echo generic-receive-offload ;;
		gso) echo generic-segmentation-offload ;;
		tso) echo tcp-segmentation-offload ;;
		rx-gro-list|tx-udp-segmentation|hw-tc-offload) echo "$1" ;;
		*) return 1 ;;
	esac
}

mw_qos_save_offload_state() {
	local device="$1" feature long_name value saved=0 state_file tmp

	mw_qos_device_name_safe "$device" || return 1
	state_file="$MULTIWAN_QOS_OFFLOAD_ROOT/$device"
	[ -e "$state_file" ] && return 0
	mkdir -p "$MULTIWAN_QOS_OFFLOAD_ROOT" || return 1
	tmp="${state_file}.$$"
	: > "$tmp" || return 1
	for feature in gro gso tso rx-gro-list tx-udp-segmentation hw-tc-offload; do
		long_name="$(mw_qos_offload_feature_name "$feature")" || continue
		value="$(ethtool -k "$device" 2>/dev/null | awk -v name="${long_name}:" '$1 == name { print $2; exit }')"
		case "$value" in
			on|off)
				printf '%s %s\n' "$feature" "$value" >> "$tmp" || {
					rm -f "$tmp"
					return 1
				}
				saved=$((saved + 1))
				;;
		esac
	done
	[ "$saved" -gt 0 ] || { rm -f "$tmp"; return 1; }
	mv "$tmp" "$state_file" || { rm -f "$tmp"; return 1; }
}

# Returns 2 when the device is temporarily absent. The journal is retained so
# a later stop or attach can restore it without turning absence into teardown
# failure.
mw_qos_restore_offload_state_file() {
	local state_file="$1" device feature value result=0

	[ -r "$state_file" ] || return 0
	device="${state_file##*/}"
	mw_qos_device_name_safe "$device" || return 1
	command -v ethtool >/dev/null 2>&1 || {
		mw_qos_warn "Could not restore saved offloads for $device because ethtool is unavailable."
		return 1
	}
	ip link show "$device" >/dev/null 2>&1 || {
		mw_qos_warn "Deferring saved offload restoration for unavailable device $device."
		return 2
	}
	while read -r feature value; do
		case "$feature:$value" in
			gro:on|gro:off|gso:on|gso:off|tso:on|tso:off|rx-gro-list:on|rx-gro-list:off|tx-udp-segmentation:on|tx-udp-segmentation:off|hw-tc-offload:on|hw-tc-offload:off)
				ethtool -K "$device" "$feature" "$value" >/dev/null 2>&1 || {
					mw_qos_warn "Could not restore $feature=$value on $device."
					result=1
				}
				;;
		esac
	done < "$state_file"
	if [ "$result" -eq 0 ]; then
		rm -f "$state_file" || result=1
	fi
	return "$result"
}

mw_qos_restore_offload_state() {
	mw_qos_restore_offload_state_file "$MULTIWAN_QOS_OFFLOAD_ROOT/$1"
}

mw_qos_ledger_commit() {
	local state_file="$MULTIWAN_QOS_QDISC_LEDGER" tmp="${MULTIWAN_QOS_QDISC_LEDGER}.$$" device

	mkdir -p "${state_file%/*}" || return 1
	if [ "$#" -eq 0 ]; then
		rm -f "$state_file" "$tmp" || return 1
		return 0
	fi
	: > "$tmp" || return 1
	for device in "$@"; do
		mw_qos_device_name_safe "$device" || { rm -f "$tmp"; return 1; }
		grep -Fqx "$device" "$tmp" 2>/dev/null ||
			printf '%s\n' "$device" >> "$tmp" || { rm -f "$tmp"; return 1; }
	done
	mv "$tmp" "$state_file" || { rm -f "$tmp"; return 1; }
}

mw_qos_ledger_add() {
	local device="$1" tmp="${MULTIWAN_QOS_QDISC_LEDGER}.$$"

	mw_qos_device_name_safe "$device" || return 1
	mkdir -p "${MULTIWAN_QOS_QDISC_LEDGER%/*}" || return 1
	if [ -f "$MULTIWAN_QOS_QDISC_LEDGER" ]; then
		awk -v device="$device" '
			$0 == device { found = 1 }
			NF { print }
			END { if (!found) print device }
		' "$MULTIWAN_QOS_QDISC_LEDGER" > "$tmp" || { rm -f "$tmp"; return 1; }
	else
		printf '%s\n' "$device" > "$tmp" || return 1
	fi
	mv "$tmp" "$MULTIWAN_QOS_QDISC_LEDGER" || { rm -f "$tmp"; return 1; }
}

mw_qos_ledger_remove() {
	local device="$1" tmp="${MULTIWAN_QOS_QDISC_LEDGER}.$$"

	mw_qos_device_name_safe "$device" || return 1
	[ -f "$MULTIWAN_QOS_QDISC_LEDGER" ] || return 0
	awk -v device="$device" 'NF && $0 != device { print }' \
		"$MULTIWAN_QOS_QDISC_LEDGER" > "$tmp" || { rm -f "$tmp"; return 1; }
	if [ -s "$tmp" ]; then
		mv "$tmp" "$MULTIWAN_QOS_QDISC_LEDGER" || { rm -f "$tmp"; return 1; }
	else
		rm -f "$tmp" "$MULTIWAN_QOS_QDISC_LEDGER" || return 1
	fi
}

# Full dataplane teardown. Configuration finds currently declared interfaces;
# the ledger finds interfaces that were renamed or removed from configuration.
# Only devices that fail verified cleanup remain in the ownership ledger.
mw_qos_teardown_runtime() {
	local cleanup_devices="" failed_devices="" device state_file table_spec restore_result result=0

	collect_teardown_device() {
		local candidate="$1"

		mw_qos_device_name_safe "$candidate" || return 1
		case " $cleanup_devices " in
			*" $candidate "*) ;;
			*) cleanup_devices="${cleanup_devices:+$cleanup_devices }$candidate" ;;
		esac
	}

	collect_configured_device() {
		local section="$1" configured_device

		config_get configured_device "$section" device
		if [ -z "$configured_device" ] && type network_get_device >/dev/null 2>&1; then
			network_get_device configured_device "$section" 2>/dev/null
		fi
		[ -n "$configured_device" ] || return 0
		collect_teardown_device "$configured_device" || {
			mw_qos_warn "Ignored unsafe QoS device identity '$configured_device' during teardown."
			result=1
		}
	}

	if config_load multiwan-qos; then
		config_foreach collect_configured_device interface
	else
		mw_qos_error "Failed to load multiwan-qos while collecting configured interfaces for teardown."
		result=1
	fi
	if [ -r "$MULTIWAN_QOS_QDISC_LEDGER" ]; then
		while IFS= read -r device; do
			[ -n "$device" ] || continue
			collect_teardown_device "$device" || result=1
		done < "$MULTIWAN_QOS_QDISC_LEDGER"
	fi

	for device in $cleanup_devices; do
		if ! mw_qos_cleanup_device "$device"; then
			failed_devices="${failed_devices:+$failed_devices }$device"
			result=1
		fi
		rm -f "$MULTIWAN_QOS_RUNTIME_ROOT/realtime-first/${device}.status"
		rm -rf "$MULTIWAN_QOS_RUNTIME_ROOT/adaptive/${device}-wan" \
			"$MULTIWAN_QOS_RUNTIME_ROOT/adaptive/ifb-${device}-lan"
	done

	for state_file in "$MULTIWAN_QOS_OFFLOAD_ROOT"/*; do
		[ -f "$state_file" ] || continue
		mw_qos_restore_offload_state_file "$state_file"
		restore_result=$?
		case "$restore_result" in
			0|2) ;;
			*) result=1 ;;
		esac
	done
	rmdir "$MULTIWAN_QOS_OFFLOAD_ROOT" 2>/dev/null || :

	set -- $failed_devices
	mw_qos_ledger_commit "$@" || {
		mw_qos_error "Could not publish the remaining QoS ownership ledger."
		result=1
	}

	if command -v nft >/dev/null 2>&1; then
		for table_spec in \
			"inet multiwan_qos_mcast" \
			"inet dscptag" \
			"netdev multiwan_qos_ingress"; do
			set -- $table_spec
			if nft list table "$1" "$2" >/dev/null 2>&1; then
				nft destroy table "$1" "$2" 2>/dev/null || result=1
			fi
		done
	else
		mw_qos_warn "Cannot verify nftables teardown because nft is unavailable."
		result=1
	fi
	return "$result"
}

mw_qos_cleanup_ets_probe() {
	local probe_device="${MULTIWAN_QOS_ETS_PROBE_DEVICE:-}"

	if [ -z "$probe_device" ] && [ -r "$MULTIWAN_QOS_ETS_PROBE_STATE" ]; then
		IFS= read -r probe_device < "$MULTIWAN_QOS_ETS_PROBE_STATE"
	fi
	[ -n "$probe_device" ] || return 0
	case "$probe_device" in mqe[0-9]*_[0-9]*) ;; *) return 1 ;; esac
	command -v ip >/dev/null 2>&1 || return 1
	if ! ip link show "$probe_device" >/dev/null 2>&1; then
		rm -f "$MULTIWAN_QOS_ETS_PROBE_STATE" || return 1
		MULTIWAN_QOS_ETS_PROBE_DEVICE=
		return 0
	fi
	mw_qos_is_ifb "$probe_device" || return 1
	ip link del "$probe_device" >/dev/null 2>&1 || return 1
	rm -f "$MULTIWAN_QOS_ETS_PROBE_STATE" || return 1
	MULTIWAN_QOS_ETS_PROBE_DEVICE=
}

# Probe both the userspace tc parser and kernel ETS implementation on an owned
# disposable IFB. Arguments indicate whether the five-band HFSC and three-band
# Hybrid layouts are required.
mw_qos_probe_ets() {
	local requires_hfsc="$1" requires_hybrid="$2" unchanged_message="$3"
	local attempt=0 probe_device probe_result=0

	[ "$requires_hfsc" -eq 1 ] 2>/dev/null || [ "$requires_hybrid" -eq 1 ] 2>/dev/null || return 0
	mw_qos_cleanup_ets_probe || {
		mw_qos_error "Realtime First Scheduling preflight could not remove the previously owned ETS probe device. Its identity remains in $MULTIWAN_QOS_ETS_PROBE_STATE."
		return 1
	}
	if [ ! -d "$MULTIWAN_QOS_SCH_ETS_DIR" ]; then
		command -v modprobe >/dev/null 2>&1 && modprobe sch_ets >/dev/null 2>&1
	fi
	[ -d "$MULTIWAN_QOS_SCH_ETS_DIR" ] || {
		mw_qos_error "Realtime First Scheduling requires sch_ets (OpenWrt 24.10 or newer). $unchanged_message"
		return 1
	}
	while [ "$attempt" -lt 10 ]; do
		probe_device="mqe$$_$attempt"
		if ! ip link show "$probe_device" >/dev/null 2>&1; then
			mkdir -p "${MULTIWAN_QOS_ETS_PROBE_STATE%/*}" &&
				printf '%s\n' "$probe_device" > "$MULTIWAN_QOS_ETS_PROBE_STATE" || return 1
			if ip link add name "$probe_device" type ifb >/dev/null 2>&1; then
				MULTIWAN_QOS_ETS_PROBE_DEVICE="$probe_device"
				break
			fi
			rm -f "$MULTIWAN_QOS_ETS_PROBE_STATE"
		fi
		probe_device=
		attempt=$((attempt + 1))
	done
	[ -n "${MULTIWAN_QOS_ETS_PROBE_DEVICE:-}" ] || probe_result=1
	if [ "$probe_result" -eq 0 ] && [ "$requires_hfsc" -eq 1 ]; then
		tc qdisc add dev "$MULTIWAN_QOS_ETS_PROBE_DEVICE" root handle 2: ets \
			bands 5 strict 1 quanta 9000 13500 4500 3000 \
			priomap 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 >/dev/null 2>&1 || probe_result=1
		[ "$probe_result" -ne 0 ] ||
			tc qdisc del dev "$MULTIWAN_QOS_ETS_PROBE_DEVICE" root >/dev/null 2>&1 || probe_result=1
	fi
	if [ "$probe_result" -eq 0 ] && [ "$requires_hybrid" -eq 1 ]; then
		tc qdisc add dev "$MULTIWAN_QOS_ETS_PROBE_DEVICE" root handle 2: ets \
			bands 3 strict 1 quanta 13500 1500 \
			priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 >/dev/null 2>&1 || probe_result=1
	fi
	if [ "$probe_result" -ne 0 ]; then
		mw_qos_cleanup_ets_probe || mw_qos_error "ETS preflight failed and the owned probe could not be removed; cleanup will be retried later."
		mw_qos_error "Realtime First Scheduling preflight failed: tc could not create an ETS qdisc. $unchanged_message"
		return 1
	fi
	mw_qos_cleanup_ets_probe || {
		mw_qos_error "Realtime First Scheduling preflight succeeded, but its owned probe device could not be removed. Its identity was retained for cleanup."
		return 1
	}
}
