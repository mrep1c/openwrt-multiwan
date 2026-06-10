#!/bin/sh
set -eu

# Run on an OpenWrt router after installing candidate packages. This test is
# intentionally disruptive: it repeatedly stops/restarts both services.

NFT_SERVICE=/etc/init.d/multiwan-nft
QOS_SERVICE=/etc/init.d/multiwan-qos
LOCK_HELPER=/lib/multiwan-qos/process-lock.sh
HOTPLUG_SCRIPT=/etc/hotplug.d/iface/13-multiwan-qos-hotplug
EXPECTED_VERSION=1.0.3-r1
SKIP_PACKAGE_VERSION=0
SIGNAL_ONLY=0
SKIP_STOP_START=0
QOS_IDLE_ONLY=0
SKIP_HOTPLUG=0
TEST_ROUTE=198.18.255.254/32
TEST_METRIC=42760
ORIGINAL_QOS_ENABLED="$(uci -q get multiwan-qos.global.enabled 2>/dev/null || true)"
ROUTE_ADDED=0
HOLDER_PID=
HOTPLUG_WORKERS=
STALE_RTMON_WORKDIR=
GATE_COMPLETE=0
CURRENT_STAGE=startup

while [ "$#" -gt 0 ]; do
	case "$1" in
		--staged-source) SKIP_PACKAGE_VERSION=1 ;;
		--signal-only) SIGNAL_ONLY=1 ;;
		--skip-stop-start) SKIP_STOP_START=1 ;;
		--qos-idle-only) QOS_IDLE_ONLY=1 ;;
		--idle-only) QOS_IDLE_ONLY=1; SKIP_HOTPLUG=1 ;;
		*) echo "Usage: $0 [--staged-source] [--signal-only] [--skip-stop-start] [--qos-idle-only] [--idle-only]" >&2; exit 2 ;;
	esac
	shift
done

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ "$SIGNAL_ONLY" -eq 0 ] || [ "$QOS_IDLE_ONLY" -eq 0 ] ||
	fail "--signal-only and --qos-idle-only cannot be combined"

run_or_fail() {
	local context="$1" rc
	shift
	CURRENT_STAGE="$context"
	if "$@"; then
		return 0
	else
		rc=$?
		fail "$context failed with exit code $rc"
	fi
}

cleanup() {
	rc=$?
	trap - EXIT HUP INT TERM
	[ "$ROUTE_ADDED" = 1 ] && ip -4 route del blackhole "$TEST_ROUTE" metric "$TEST_METRIC" 2>/dev/null || true
	[ -n "$HOLDER_PID" ] && kill -KILL "$HOLDER_PID" 2>/dev/null || true
	for worker in $HOTPLUG_WORKERS; do
		worker_pid="${worker%%:*}"
		worker_start="${worker#*:}"
		identity_alive "$worker_pid" "$worker_start" &&
			kill -TERM "$worker_pid" 2>/dev/null || true
	done
	rm -f /var/run/multiwan-qos-agent-watchdog.pid /tmp/multiwan-gate-lock-ready
	rm -rf /tmp/multiwan-gate-lock /tmp/multiwan-gate-lock.guard
	if [ -n "$STALE_RTMON_WORKDIR" ]; then
		rm -f "$STALE_RTMON_WORKDIR/events" "$STALE_RTMON_WORKDIR/error" \
			"$STALE_RTMON_WORKDIR/owner" "$STALE_RTMON_WORKDIR"/.owner.* 2>/dev/null
		rmdir "$STALE_RTMON_WORKDIR" 2>/dev/null || true
	fi
	if [ -n "$ORIGINAL_QOS_ENABLED" ]; then
		uci set multiwan-qos.global.enabled="$ORIGINAL_QOS_ENABLED"
		uci commit multiwan-qos
	fi
	if [ "$GATE_COMPLETE" -eq 0 ]; then
		echo "Gate did not complete during [$CURRENT_STAGE] (exit code $rc)" >&2
		echo "=== process state ===" >&2
		ps w | grep -E '[m]ultiwan-nft-(rtmon|track)|[i]p -[46] monitor route' >&2 || true
		echo "=== procd state ===" >&2
		ubus call service list '{"name":"multiwan-nft"}' >&2 || true
		echo "=== recent log ===" >&2
		logread 2>/dev/null |
			grep -E 'multiwan-nft|procd' |
			tail -n 80 >&2 || true
		echo "Restoring MultiWAN services" >&2
		"$NFT_SERVICE" restart >/dev/null 2>&1 || true
		"$QOS_SERVICE" start >/dev/null 2>&1 || true
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$(id -u)" = 0 ] || fail "run this gate as root"
[ -x "$NFT_SERVICE" ] || fail "multiwan-nft service is not installed"
[ -x "$QOS_SERVICE" ] || fail "multiwan-qos service is not installed"
[ -r "$LOCK_HELPER" ] || fail "QoS process-lock helper is not installed"
[ -r "$HOTPLUG_SCRIPT" ] || fail "QoS hotplug script is not installed"

process_start() {
	local pid="$1" stat rest
	stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
	rest="${stat##*) }"
	set -- $rest
	[ "$#" -ge 20 ] || return 1
	shift 19
	echo "$1"
}

identity_alive() {
	local pid="$1" start="$2" current state
	kill -0 "$pid" 2>/dev/null || return 1
	current="$(process_start "$pid")" || return 1
	[ "$current" = "$start" ] || return 1
	state="$(sed -n 's/^State:[[:space:]]*\([A-Z]\).*/\1/p' "/proc/$pid/status" 2>/dev/null)"
	[ "$state" != Z ]
}

matching_pids() {
	local pattern="$1" dir cmdline
	for dir in /proc/[0-9]*; do
		[ -r "$dir/cmdline" ] || continue
		cmdline="$(tr '\0' ' ' 2>/dev/null < "$dir/cmdline")" || continue
		case "$cmdline" in
			*"$pattern"*) echo "${dir##*/}" ;;
		esac
	done
}

direct_child_count() {
	local parent="$1" dir ppid count=0

	for dir in /proc/[0-9]*; do
		[ -r "$dir/status" ] || continue
		ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "$dir/status" 2>/dev/null)" || continue
		[ "$ppid" = "$parent" ] && count=$((count + 1))
	done
	echo "$count"
}

first_direct_child() {
	local parent="$1" dir ppid

	for dir in /proc/[0-9]*; do
		[ -r "$dir/status" ] || continue
		ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "$dir/status" 2>/dev/null)" || continue
		if [ "$ppid" = "$parent" ]; then
			echo "${dir##*/}"
			return 0
		fi
	done
	return 1
}

family_enabled() {
	local wanted="$1" section enabled family
	for section in $(uci -q show multiwan-nft | sed -n "s/^multiwan-nft\.\([^.=]*\)=interface$/\1/p"); do
		enabled="$(uci -q get "multiwan-nft.$section.enabled" || echo 0)"
		family="$(uci -q get "multiwan-nft.$section.family" || echo ipv4)"
		[ "$enabled" = 1 ] && [ "$family" = "$wanted" ] && return 0
	done
	return 1
}

expected_family_count() {
	family_enabled "$1" && echo 1 || echo 0
}

assert_process_count() {
	local pattern="$1" expected="$2" actual
	actual="$(matching_pids "$pattern" | wc -l)"
	[ "$actual" -eq "$expected" ] ||
		fail "expected $expected process(es) matching [$pattern], found $actual"
}

assert_rtmon_tree() {
	local family="$1" flag="$2" expected parent child child_ppid child_count
	expected="$(expected_family_count "$family")"
	assert_process_count "/usr/sbin/multiwan-nft-rtmon $family" "$expected"
	assert_process_count "ip -$flag monitor route" "$expected"
	[ "$expected" -eq 1 ] || return 0

	parent="$(matching_pids "/usr/sbin/multiwan-nft-rtmon $family")"
	child="$(matching_pids "ip -$flag monitor route")"
	child_ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$child/status" 2>/dev/null)" ||
		fail "IPv$flag monitor child $child disappeared during assertion"
	[ "$child_ppid" = "$parent" ] ||
		fail "IPv$flag monitor child $child is owned by $child_ppid, expected $parent"
	child_count="$(direct_child_count "$parent")"
	[ "$child_count" -eq 1 ] ||
		fail "rtmon parent $parent has $child_count direct children, expected one"
}

assert_all_rtmon_trees() {
	assert_rtmon_tree ipv4 4
	assert_rtmon_tree ipv6 6
}

rtmon_tree_ready() {
	local family="$1" flag="$2" parent child child_ppid child_count

	set -- $(matching_pids "/usr/sbin/multiwan-nft-rtmon $family")
	[ "$#" -eq 1 ] || return 1
	parent="$1"

	set -- $(matching_pids "ip -$flag monitor route")
	[ "$#" -eq 1 ] || return 1
	child="$1"

	child_ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$child/status" 2>/dev/null)" ||
		return 1
	[ "$child_ppid" = "$parent" ] || return 1
	child_count="$(direct_child_count "$parent")"
	[ "$child_count" -eq 1 ]
}

dump_rtmon_diagnostics() {
	local context="$1"

	echo "=== rtmon diagnostics: $context ===" >&2
	date >&2
	ps w | grep -E '[m]ultiwan-nft-(rtmon|track)|[i]p -[46] monitor route' >&2 || true
	ubus call service list '{"name":"multiwan-nft"}' >&2 || true
	logread 2>/dev/null |
		grep -E 'multiwan-nft|procd' |
		tail -n 80 >&2 || true
}

wait_for_rtmon_recovery() {
	local context="$1" family="$2" flag="$3" count=0

	while [ "$count" -lt 25 ]; do
		if rtmon_tree_ready "$family" "$flag"; then
			echo "PASS: $context recovered after ${count}s"
			return 0
		fi
		sleep 1
		count=$((count + 1))
	done

	dump_rtmon_diagnostics "$context"
	fail "$context did not recover a single supervised IPv$flag route monitor within 25 seconds"
}

assert_no_rtmon() {
	assert_process_count /usr/sbin/multiwan-nft-rtmon 0
	assert_process_count /usr/sbin/multiwan-nft-track 0
	assert_process_count "ip -4 monitor route" 0
	assert_process_count "ip -6 monitor route" 0
}

wait_for_tree() {
	sleep 6
	assert_all_rtmon_trees
}

package_version() {
	local pkg="$1"
	if command -v apk >/dev/null 2>&1; then
		apk list --installed "$pkg" 2>/dev/null | sed -n "s/^$pkg-\([^ ]*\).*/\1/p" | head -n 1
	else
		opkg status "$pkg" 2>/dev/null | sed -n 's/^Version: //p'
	fi
}

if [ "$SKIP_PACKAGE_VERSION" -eq 0 ]; then
	for pkg in multiwan-nft luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos; do
		version="$(package_version "$pkg")"
		[ "$version" = "$EXPECTED_VERSION" ] ||
			fail "$pkg version is [$version], expected [$EXPECTED_VERSION]"
	done
else
	echo "NOTE: package version check skipped for source-staged pre-push validation"
fi

if [ "$QOS_IDLE_ONLY" -eq 0 ]; then
if [ "$SIGNAL_ONLY" -eq 0 ]; then
	echo "== Dead-owner rtmon workspace recovery =="
	if family_enabled ipv4; then
		stale_family=ipv4
	elif family_enabled ipv6; then
		stale_family=ipv6
	else
		fail "no enabled MultiWAN address family for route-monitor testing"
	fi
	STALE_RTMON_WORKDIR="/tmp/multiwan-nft-rtmon-${stale_family}.gate-stale-$$"
	rm -f "$STALE_RTMON_WORKDIR/events" "$STALE_RTMON_WORKDIR/error" \
		"$STALE_RTMON_WORKDIR/owner" "$STALE_RTMON_WORKDIR"/.owner.* 2>/dev/null
	rmdir "$STALE_RTMON_WORKDIR" 2>/dev/null || true
	run_or_fail "create stale rtmon workspace" mkdir "$STALE_RTMON_WORKDIR"
	printf '999999 1 gate-stale\n' > "$STALE_RTMON_WORKDIR/owner"
	: > "$STALE_RTMON_WORKDIR/events"
	: > "$STALE_RTMON_WORKDIR/error"

	run_or_fail "full gate initial service reset" "$NFT_SERVICE" restart
	CURRENT_STAGE="full gate initial process-tree assertion"
	wait_for_tree
	[ ! -e "$STALE_RTMON_WORKDIR" ] ||
		fail "dead-owner route-monitor workspace was not reclaimed"
	STALE_RTMON_WORKDIR=

	if [ "$SKIP_STOP_START" -eq 0 ]; then
		echo "== NFT stop/start stress =="
		i=1
		while [ "$i" -le 50 ]; do
			echo "-- stop/start cycle $i/50 --"
			run_or_fail "NFT stop/start cycle $i stop" "$NFT_SERVICE" stop
			CURRENT_STAGE="NFT stop/start cycle $i immediate cleanup assertion"
			assert_no_rtmon
			sleep 6
			CURRENT_STAGE="NFT stop/start cycle $i delayed cleanup assertion"
			assert_no_rtmon
			run_or_fail "NFT stop/start cycle $i start" "$NFT_SERVICE" start
			CURRENT_STAGE="NFT stop/start cycle $i process-tree assertion"
			wait_for_tree
			i=$((i + 1))
		done
	else
		echo "NOTE: 50-cycle stop/start stage skipped after prior successful run"
	fi

	echo "== NFT restart/reload stress =="
	i=1
	while [ "$i" -le 25 ]; do
		echo "-- restart cycle $i/25 --"
		run_or_fail "NFT restart cycle $i" "$NFT_SERVICE" restart
		CURRENT_STAGE="NFT restart cycle $i process-tree assertion"
		wait_for_tree
		i=$((i + 1))
	done
	i=1
	while [ "$i" -le 10 ]; do
		echo "-- reload cycle $i/10 --"
		run_or_fail "NFT reload cycle $i" "$NFT_SERVICE" reload
		CURRENT_STAGE="NFT reload cycle $i process-tree assertion"
		wait_for_tree
		i=$((i + 1))
	done
fi

echo "== Parent and child signal recovery =="
for family_flag in "ipv4 4" "ipv6 6"; do
	set -- $family_flag
	family="$1"
	flag="$2"
	family_enabled "$family" || continue
	for target_signal in TERM KILL; do
		echo "-- IPv$flag child $target_signal recovery --"
		run_or_fail "IPv$flag child $target_signal preparation restart" "$NFT_SERVICE" restart
		CURRENT_STAGE="IPv$flag child $target_signal preparation assertion"
		wait_for_tree
		child="$(matching_pids "ip -$flag monitor route")"
		run_or_fail "IPv$flag child $target_signal injection" kill "-$target_signal" "$child"
		CURRENT_STAGE="IPv$flag child $target_signal recovery"
		wait_for_rtmon_recovery "IPv$flag child $target_signal" "$family" "$flag"
	done
	for target_signal in INT TERM KILL; do
		echo "-- IPv$flag parent $target_signal recovery --"
		run_or_fail "IPv$flag parent $target_signal preparation restart" "$NFT_SERVICE" restart
		CURRENT_STAGE="IPv$flag parent $target_signal preparation assertion"
		wait_for_tree
		parent="$(matching_pids "/usr/sbin/multiwan-nft-rtmon $family")"
		run_or_fail "IPv$flag parent $target_signal injection" kill "-$target_signal" "$parent"
		CURRENT_STAGE="IPv$flag parent $target_signal recovery"
		wait_for_rtmon_recovery "IPv$flag parent $target_signal" "$family" "$flag"
	done
done

if [ "$SIGNAL_ONLY" -eq 1 ]; then
	run_or_fail "signal gate final service reset" "$NFT_SERVICE" restart
	CURRENT_STAGE="signal gate final process-tree assertion"
	wait_for_tree
	GATE_COMPLETE=1
	echo "PASS: MultiWAN 1.0.3 forced signal recovery gate"
	exit 0
fi

echo "== Tracker child interruption =="
tracker="$(matching_pids "/usr/sbin/multiwan-nft-track " | head -n 1)"
if [ -n "$tracker" ]; then
	tracker_start="$(process_start "$tracker")"
	tracker_child="$(first_direct_child "$tracker" 2>/dev/null || true)"
	if [ -n "$tracker_child" ]; then
		tracker_child_start="$(process_start "$tracker_child")"
		kill -TERM "$tracker_child" 2>/dev/null || true
		sleep 3
		! identity_alive "$tracker_child" "$tracker_child_start" ||
			fail "tracking child $tracker_child survived TERM"
	fi
	kill -USR1 "$tracker"
	sleep 3
	identity_alive "$tracker" "$tracker_start" || fail "tracker exited after USR1"
	kill -USR2 "$tracker"
	sleep 5
	identity_alive "$tracker" "$tracker_start" || fail "tracker exited after USR2"
fi

echo "== Controlled route event =="
run_or_fail "controlled route add" ip -4 route add blackhole "$TEST_ROUTE" metric "$TEST_METRIC"
ROUTE_ADDED=1
sleep 2
run_or_fail "controlled route delete" ip -4 route del blackhole "$TEST_ROUTE" metric "$TEST_METRIC"
ROUTE_ADDED=0
sleep 2
CURRENT_STAGE="controlled route process-tree assertion"
assert_all_rtmon_trees

echo "== QoS lock ownership =="
rm -rf /tmp/multiwan-gate-lock /tmp/multiwan-gate-lock.guard
sh -c '. "$1"; mw_lock_acquire "$2" || exit 1; : > "$3"; sleep 35; mw_lock_release' \
	sh "$LOCK_HELPER" /tmp/multiwan-gate-lock /tmp/multiwan-gate-lock-ready &
HOLDER_PID=$!
holder_count=0
while [ ! -f /tmp/multiwan-gate-lock-ready ] && [ "$holder_count" -lt 10 ]; do
	sleep 1
	holder_count=$((holder_count + 1))
done
[ -f /tmp/multiwan-gate-lock-ready ] || fail "long-running lock holder did not start"
holder_start="$(process_start "$HOLDER_PID")"
! sh "$LOCK_HELPER" --claim /tmp/multiwan-gate-lock "$$" "$(process_start "$$")" gate-contender ||
	fail "second request stole a live lock"
sleep 31
identity_alive "$HOLDER_PID" "$holder_start" || fail "long-running lock holder exited too early"
! sh "$LOCK_HELPER" --claim /tmp/multiwan-gate-lock "$$" "$(process_start "$$")" gate-contender ||
	fail "lock was stolen solely because it was older than 30 seconds"
run_or_fail "long-running QoS lock holder completion" wait "$HOLDER_PID"
HOLDER_PID=
[ ! -d /tmp/multiwan-gate-lock ] || fail "long-running owner left its lock behind"

echo "== Legacy PID reuse protection =="
sleep 120 &
unrelated_pid=$!
echo "$unrelated_pid" > /var/run/multiwan-qos-agent-watchdog.pid
CURRENT_STAGE="QoS legacy PID reuse stop"
if ! DISABLE_ON_STOP=0 "$QOS_SERVICE" stop; then
	fail "QoS legacy PID reuse stop failed"
fi
kill -0 "$unrelated_pid" 2>/dev/null ||
	fail "QoS stop killed an unrelated PID from a legacy pidfile"
run_or_fail "unrelated PID cleanup" kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
run_or_fail "QoS restart after legacy PID test" "$QOS_SERVICE" start
sleep 8
else
	echo "NOTE: NFT and QoS lock/PID stages skipped after prior successful run"
fi

if [ "$SKIP_HOTPLUG" -eq 0 ]; then
	echo "== QoS hotplug coalescing =="
	qos_section="$(uci -q show multiwan-qos | sed -n 's/^multiwan-qos\.\([^.=]*\)=interface$/\1/p' | head -n 1)"
	if [ -n "$qos_section" ]; then
		qos_device="$(uci -q get "multiwan-qos.$qos_section.device" || true)"
		if [ -n "$qos_device" ]; then
			rm -f /tmp/multiwan_qos-hotplug.pending
			if [ -d /tmp/multiwan_qos-hotplug.lock ]; then
				sh -c '. "$1"; mw_lock_reclaim_stale "$2"' \
					sh "$LOCK_HELPER" /tmp/multiwan_qos-hotplug.lock ||
					fail "QoS hotplug lock is owned by a live process before stress test"
			fi
			hotplug_pids=""
			HOTPLUG_WORKERS=""
			i=1
			while [ "$i" -le 50 ]; do
				ACTION=ifup INTERFACE="$qos_section" DEVICE="$qos_device" \
					/bin/sh "$HOTPLUG_SCRIPT" &
				hotplug_pid=$!
				hotplug_start="$(process_start "$hotplug_pid" 2>/dev/null || true)"
				hotplug_pids="$hotplug_pids $hotplug_pid"
				[ -n "$hotplug_start" ] &&
					HOTPLUG_WORKERS="$HOTPLUG_WORKERS $hotplug_pid:$hotplug_start"
				i=$((i + 1))
			done
			hotplug_failed=0
			for hotplug_pid in $hotplug_pids; do
				wait "$hotplug_pid" || hotplug_failed=1
			done
			HOTPLUG_WORKERS=""
			[ "$hotplug_failed" -eq 0 ] ||
				fail "one or more QoS hotplug workers failed"

			wait_count=0
			while [ -d /tmp/multiwan_qos-hotplug.lock ] && [ "$wait_count" -lt 120 ]; do
				sleep 1
				wait_count=$((wait_count + 1))
			done
			[ ! -d /tmp/multiwan_qos-hotplug.lock ] ||
				fail "QoS hotplug lock remained after 120 seconds"
			[ ! -f /tmp/multiwan_qos-hotplug.pending ] ||
				fail "QoS hotplug pending event remained after coalescing"
		fi
	fi
else
	echo "NOTE: QoS hotplug stage skipped after prior successful run"
fi

run_or_fail "QoS health check" "$QOS_SERVICE" health_check
CURRENT_STAGE="QoS nft table check"
nft list table inet dscptag >/dev/null 2>&1 ||
	fail "QoS nft table inet dscptag is missing"

CURRENT_STAGE="tc ctinfo DSCP restore verification"
restore_found=0
for qos_section in $(uci -q show multiwan-qos | sed -n 's/^multiwan-qos\.\([^.=]*\)=interface$/\1/p'); do
	qos_device="$(uci -q get "multiwan-qos.$qos_section.device" || true)"
	[ -n "$qos_device" ] || continue
	tc_restore_output="$(tc filter show dev "$qos_device" parent ffff: 2>/dev/null || true)"
	if printf '%s\n' "$tc_restore_output" | grep -Fq 'ctinfo' &&
		{
			printf '%s\n' "$tc_restore_output" |
				grep -Eq 'dscp[[:space:]]+0x0*3f[[:space:]]+0x0*80' ||
			printf '%s\n' "$tc_restore_output" |
				grep -Eq 'dscp[[:space:]]+63[[:space:]]+128'
		}; then
		echo "PASS: tc ctinfo DSCP restore found on $qos_device"
		restore_found=1
		break
	fi
done
if [ "$restore_found" -ne 1 ]; then
	for qos_section in $(uci -q show multiwan-qos | sed -n 's/^multiwan-qos\.\([^.=]*\)=interface$/\1/p'); do
		qos_device="$(uci -q get "multiwan-qos.$qos_section.device" || true)"
		[ -n "$qos_device" ] || continue
		echo "=== tc ingress filters: $qos_device ===" >&2
		tc filter show dev "$qos_device" parent ffff: >&2 || true
	done
	fail "tc ctinfo DSCP restore action with mask/statemask 63/128 was not found"
fi

echo "== Ten-minute idle stability sample =="
CURRENT_STAGE="ten-minute idle stability sample setup"
parent="$(matching_pids "/usr/sbin/multiwan-nft-rtmon ipv4" | head -n 1)"
[ -n "$parent" ] || parent="$(matching_pids "/usr/sbin/multiwan-nft-rtmon ipv6" | head -n 1)"
[ -n "$parent" ] || fail "no route monitor available for idle sampling"
parent_start="$(process_start "$parent")"
set -- $(cat "/proc/$parent/stat")
cpu_before=$((${14} + ${15}))
rss_before=${24}
sleep 600
CURRENT_STAGE="ten-minute idle stability sample verification"
identity_alive "$parent" "$parent_start" || fail "route monitor restarted during idle sample"
set -- $(cat "/proc/$parent/stat")
cpu_after=$((${14} + ${15}))
rss_after=${24}
cpu_delta=$((cpu_after - cpu_before))
rss_delta=$((rss_after - rss_before))
[ "$cpu_delta" -le 300 ] || fail "idle rtmon consumed $cpu_delta CPU ticks"
[ "$rss_delta" -le 1024 ] || fail "idle rtmon RSS grew by $rss_delta pages"

assert_all_rtmon_trees
GATE_COMPLETE=1
if [ "$QOS_IDLE_ONLY" -eq 1 ]; then
	echo "PASS: MultiWAN 1.0.3 QoS and idle continuation gate"
else
	echo "PASS: MultiWAN 1.0.3 router release gate"
fi
echo "Manual packet capture is still required to prove live PC EF -> conntrack EF -> WAN-return EF."
