#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
status=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	status=1
}

check_lf() {
	file="$1"
	if LC_ALL=C grep -q "$(printf '\r')" "$file"; then
		fail "$file contains CRLF/carriage-return bytes"
	fi
}

rtmon="$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon"
nft_init="$repo_root/multiwan-nft/files/etc/init.d/multiwan-nft"
qos_init="$repo_root/multiwan-qos/etc/init.d/multiwan-qos"
qos_main="$repo_root/multiwan-qos/etc/multiwan-qos.sh"
agent="$repo_root/multiwan-qos/www/cgi-bin/multiwan-qos-agent"

for file in \
	"$repo_root/multiwan-nft/files/etc/init.d/multiwan-nft" \
	"$repo_root/multiwan-nft/files/lib/multiwan-nft/common.sh" \
	"$repo_root/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" \
	"$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon" \
	"$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-track" \
	"$repo_root/multiwan-qos/etc/init.d/multiwan-qos" \
	"$repo_root/multiwan-qos/etc/multiwan-qos.sh" \
	"$repo_root/multiwan-qos/lib/multiwan-qos/hotplug-common.sh" \
	"$repo_root/multiwan-qos/lib/multiwan-qos/process-lock.sh" \
	"$repo_root/multiwan-qos/www/cgi-bin/multiwan-qos-agent" \
	"$repo_root/tests/router-release-gate.sh" \
	"$repo_root/tests/stage-router-candidate.sh" \
	"$repo_root/tests/restore-router-candidate.sh"
do
	check_lf "$file"
done

if [ -f "$rtmon" ]; then
	grep -Eq 'monitor route[[:space:]]*\|[[:space:]]*while' "$rtmon" &&
		fail "route monitor still uses an anonymous pipeline reader"
	grep -Fq 'exec 3<> "$RTMON_FIFO"' "$rtmon" ||
		fail "route monitor does not own an RDWR FIFO"
	grep -Fq 'wait "$RTMON_PID"' "$rtmon" ||
		fail "route monitor child is not reaped"
	grep -Fq 'mktemp -d "/tmp/multiwan-nft-rtmon-${family}.XXXXXX"' "$rtmon" ||
		fail "route monitor workspace is not unique and BusyBox-compatible"
	grep -Fq 'mw_lock_read_owner "$RTMON_WORK_DIR"' "$rtmon" ||
		fail "route monitor cleanup does not verify workspace ownership"
	grep -Fq 'multiwan-nft-rtmon-${family}-$$.fifo' "$rtmon" &&
		fail "route monitor still derives its FIFO path from a reusable PID"
fi

if [ -f "$nft_init" ]; then
	stop_line="$(grep -n '^stop_service()' "$nft_init" | cut -d: -f1)"
	stopped_line="$(grep -n '^service_stopped()' "$nft_init" | cut -d: -f1)"
	init_line="$(awk -v start="$stopped_line" 'NR > start && /multiwan_nft_init/ { print NR; exit }' "$nft_init")"
	[ -n "$stop_line" ] && [ -n "$stopped_line" ] && [ "$stopped_line" -gt "$stop_line" ] ||
		fail "NFT init does not use the rc.common service_stopped lifecycle hook"
	[ -n "$init_line" ] && [ "$init_line" -gt "$stopped_line" ] ||
		fail "NFT fallback cleanup does not run after procd stops the service"
	grep -A 8 '^stop_service()' "$nft_init" |
		grep -Eq '^[[:space:]]*(type .*&&[[:space:]]*)?procd_kill[[:space:]]' &&
		fail "NFT stop duplicates rc.common procd_kill"
fi

if [ -f "$qos_init" ]; then
	grep -Eq 'killall[[:space:]].*watchdog|kill[[:space:]]+"?\$\(cat .*watchdog.*pid' "$qos_init" &&
		fail "QoS still signals watchdogs without command identity verification"
	grep -Fq 'rm -rf /tmp/multiwan_qos_agent.lock' "$qos_init" &&
		fail "QoS service still deletes the agent lock unconditionally"
fi

if [ -f "$qos_main" ]; then
	grep -Fq 'mkdir "$MULTIWAN_QOS_REFRESH_LOCK_DIR"' "$qos_main" &&
		fail "QoS refresh still uses an ownerless directory lock"
fi

if [ -f "$agent" ]; then
	grep -Fq 'os.execute("rm -rf " .. LOCK_DIR' "$agent" &&
		fail "agent still deletes locks without ownership verification"
	grep -Fq 'xpcall(main, format_traceback)' "$agent" ||
		fail "agent has no top-level exception cleanup"
fi

grep -Fq '/proc/[0-9]*/status' "$repo_root/tests/router-release-gate.sh" &&
	fail "router gate still uses a racy bulk /proc status snapshot"
grep -Eq '^[[:space:]]*/etc/hotplug\.d/iface/13-multiwan-qos-hotplug[[:space:]]*&' \
	"$repo_root/tests/router-release-gate.sh" &&
	fail "router gate executes an OpenWrt sourced hotplug hook directly"

[ "$status" -eq 0 ] || exit "$status"
printf 'Lifecycle static checks passed\n'
