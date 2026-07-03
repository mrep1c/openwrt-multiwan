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
nft_lib="$repo_root/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
qos_acl="$repo_root/luci-app-multiwan-qos/root/usr/share/rpcd/acl.d/luci-app-multiwan-qos.json"
custom_rules="$repo_root/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/custom_rules.js"
qos_stats_js="$repo_root/luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/statistics.js"
qos_stats_rpc="$repo_root/luci-app-multiwan-qos/root/usr/libexec/rpcd/luci.multiwan_qos_stats"
qos_rpc="$repo_root/luci-app-multiwan-qos/root/usr/libexec/rpcd/luci.multiwan_qos"
workflow_dir="$repo_root/.github/workflows"

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
	grep -Fq 'route list table all' "$nft_init" &&
		fail "NFT stop still performs broad table cleanup"
	grep -Fq "grep -E '^[1-3][0-9]{3}" "$nft_init" &&
		fail "NFT stop still deletes broad policy-rule ranges"
fi

if [ -f "$nft_lib" ]; then
	grep -Fq 'multiwan_nft_scan_policy_member()' "$nft_lib" ||
		fail "NFT policy generation lacks a scan pass"
	grep -Fq 'meta nfproto ipv4' "$nft_lib" ||
		fail "NFT policy/rule generation lacks IPv4 family guards"
	grep -Fq 'meta nfproto ipv6' "$nft_lib" ||
		fail "NFT policy/rule generation lacks IPv6 family guards"
	grep -Fq 'match="$family_guard"' "$nft_lib" ||
		fail "NFT user-rule generation does not seed matches with a family guard"
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
	grep -Fq 'local _cd_file=' "$qos_main" &&
		fail "QoS refresh-device still uses top-level local variables"
fi

if [ -f "$agent" ]; then
	grep -Fq 'os.execute("rm -rf " .. LOCK_DIR' "$agent" &&
		fail "agent still deletes locks without ownership verification"
	grep -Fq 'xpcall(main, format_traceback)' "$agent" ||
		fail "agent has no top-level exception cleanup"
	api_line="$(grep -n 'constant_time_compare(data.api_key, expected_key)' "$agent" | head -n 1 | cut -d: -f1)"
	rate_line="$(grep -n 'if not check_rate_limit()' "$agent" | head -n 1 | cut -d: -f1)"
	[ -n "$api_line" ] && [ -n "$rate_line" ] && [ "$api_line" -lt "$rate_line" ] ||
		fail "agent rate limiting does not happen after API key validation"
	awk '/Validate API key/ { exit } /if not check_rate_limit\(\)/ { found=1 } END { exit found ? 0 : 1 }' "$agent" &&
		fail "agent still rate-limits before API key validation"
fi

if [ -f "$qos_acl" ]; then
	read_acl="$(sed -n '/"read": {/,/"write": {/p' "$qos_acl")"
	printf '%s\n' "$read_acl" | grep -Eq '"setInitAction"|"exec"|\[ "write" \]|/usr/sbin/nft' &&
		fail "QoS ACL read scope still exposes mutating exec/write powers"
	grep -Fq '"/etc/multiwan-qos.sh": [ "write" ]' "$qos_acl" &&
		fail "QoS ACL still allows writing the root rules script"
	grep -Fq '"/tmp/multiwan_qos_stats_history.json"' "$qos_acl" &&
		fail "QoS ACL still exposes removed placeholder history data"
fi

if [ -f "$custom_rules" ]; then
	grep -Fq 'o.rawhtml = true' "$custom_rules" &&
		fail "custom rules validation still renders raw HTML"
	grep -Fq 'innerHTML' "$custom_rules" &&
		fail "custom rules validation still writes raw innerHTML"
	grep -Fq 'renderValidationResult(validationResult)' "$custom_rules" ||
		fail "custom rules validation does not use DOM/text rendering"
fi

if [ -f "$qos_stats_js" ]; then
	grep -Eq 'getHistoricalStats|getRrdData' "$qos_stats_js" &&
		fail "QoS statistics UI still calls placeholder history/RRD RPCs"
fi

if [ -f "$qos_stats_rpc" ]; then
	grep -Eq 'getHistoricalStats|getRrdData|get_historical_stats|get_rrd_data' "$qos_stats_rpc" &&
		fail "QoS statistics rpcd still exposes placeholder history/RRD methods"
fi

if [ -f "$qos_rpc" ]; then
	grep -Fq 'DEFAULT_CONNTRACK_LIMIT' "$qos_rpc" ||
		fail "QoS conntrack RPC lacks a default server-side cap"
	grep -Fq 'truncated' "$qos_rpc" ||
		fail "QoS conntrack RPC lacks truncation metadata"
	grep -Fq 'effective_max_connections' "$qos_rpc" ||
		fail "QoS conntrack RPC lacks effective cap metadata"
fi

if [ -d "$workflow_dir" ]; then
	grep -R 'release delete-asset' "$workflow_dir" >/dev/null 2>&1 &&
		fail "release workflows still delete assets before upload"
	grep -R 'release edit' "$workflow_dir" >/dev/null 2>&1 ||
		fail "release workflows do not refresh existing release metadata"
	grep -R -- '--target "$GITHUB_SHA"' "$workflow_dir" >/dev/null 2>&1 ||
		fail "release workflows do not target the current commit"
fi

grep -Fq -- '--component all|nft|qos' "$repo_root/scripts/bump-version.sh" ||
	fail "combined bump-version script is not component-aware"
grep -Fq -- '--component all|nft|qos' "$repo_root/scripts/bump-workspace-version.sh" ||
	fail "workspace bump-version script is not component-aware"

grep -Fq '/proc/[0-9]*/status' "$repo_root/tests/router-release-gate.sh" &&
	fail "router gate still uses a racy bulk /proc status snapshot"
grep -Eq '^[[:space:]]*/etc/hotplug\.d/iface/13-multiwan-qos-hotplug[[:space:]]*&' \
	"$repo_root/tests/router-release-gate.sh" &&
	fail "router gate executes an OpenWrt sourced hotplug hook directly"

[ "$status" -eq 0 ] || exit "$status"
printf 'Lifecycle static checks passed\n'
