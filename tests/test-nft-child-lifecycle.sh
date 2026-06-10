#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
rtmon="$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon"
tracker="$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-track"
lock_helper="$repo_root/multiwan-nft/files/lib/multiwan-nft/process-lock.sh"
tmp="${TMPDIR:-/tmp}/multiwan-nft-child-test.$$"

cleanup() {
	[ -n "${parent_pid:-}" ] && kill -KILL "$parent_pid" 2>/dev/null || true
	[ -n "${child_pid:-}" ] && kill -KILL "$child_pid" 2>/dev/null || true
	for test_dir in ${test_dirs:-}; do
		rm -f "$test_dir/events" "$test_dir/error" \
			"$test_dir/owner" "$test_dir"/.owner.* 2>/dev/null
		rmdir "$test_dir" 2>/dev/null || true
	done
	rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

mkdir -p "$tmp/lib/functions" "$tmp/lib/multiwan-nft" "$tmp/bin"
: > "$tmp/lib/functions.sh"
: > "$tmp/lib/functions/network.sh"
cp "$lock_helper" "$tmp/lib/multiwan-nft/process-lock.sh"
# shellcheck disable=SC1090
. "$lock_helper"

cat > "$tmp/lib/multiwan-nft/multiwan_nft.sh" <<EOF
IP4="$tmp/bin/ip -4"
IP6="$tmp/bin/ip -6"
NO_IPV6=0
NFT=true
NFT_FAMILY=inet
NFT_TABLE=multiwan_nft
MULTIWAN_NFT_ROUTE_LINE_EXP=p
MULTIWAN_NFT_DEBUG=1
multiwan_nft_init() { return 0; }
multiwan_nft_update_dev_to_table() { return 0; }
multiwan_nft_get_routes() { return 0; }
multiwan_nft_route_line_dev() { return 0; }
multiwan_nft_route_replace_idempotent() { return 0; }
multiwan_nft_get_track_status() { printf 'active\n'; }
multiwan_nft_nft_add_set_element() { return 0; }
multiwan_nft_set_connected_ipv4() { return 0; }
multiwan_nft_set_connected_ipv6() { return 0; }
config_foreach() { return 0; }
config_get() { return 0; }
network_get_device() { return 0; }
LOG() { printf '%s\n' "\$*" >> "$tmp/rtmon.log"; }
EOF

cat > "$tmp/lib/multiwan-nft/common.sh" <<EOF
MAX_SLEEP=2147483647
LOG() { printf '%s\n' "\$*" >> "$tmp/tracker.log"; }
EOF

cat > "$tmp/bin/ip" <<'EOF'
#!/bin/sh
case "${MW_FAKE_IP_MODE:-hold}" in
	hold)
		trap 'exit 0' HUP INT TERM
		printf '10.0.0.0/24 dev fake table 100\n'
		while :; do sleep 1; done
		;;
	exit)
		printf 'synthetic monitor failure\n' >&2
		exit 7
		;;
esac
EOF
chmod +x "$tmp/bin/ip"

child_of() {
	local wanted_parent="$1" dir ppid
	for dir in /proc/[0-9]*; do
		[ -r "$dir/status" ] || continue
		ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "$dir/status" 2>/dev/null)"
		[ "$ppid" = "$wanted_parent" ] && {
			printf '%s\n' "${dir##*/}"
			return 0
		}
	done
	return 1
}

wait_gone() {
	local pid="$1" start="$2" count=0
	while process_running "$pid" "$start" && [ "$count" -lt 10 ]; do
		sleep 1
		count=$((count + 1))
	done
	! process_running "$pid" "$start"
}

process_running() {
	local pid="$1" start="$2" state
	mw_process_identity_alive "$pid" "$start" || return 1
	state="$(sed -n 's/^State:[[:space:]]*\([A-Z]\).*/\1/p' "/proc/$pid/status" 2>/dev/null)"
	[ "$state" != "Z" ]
}

workdir_for_owner() {
	local wanted_pid="$1" work_dir owner_pid owner_start owner_token

	for work_dir in /tmp/multiwan-nft-rtmon-ipv4.*; do
		[ -r "$work_dir/owner" ] || continue
		read -r owner_pid owner_start owner_token < "$work_dir/owner" || continue
		[ "$owner_pid" = "$wanted_pid" ] && {
			printf '%s\n' "$work_dir"
			return 0
		}
	done
	return 1
}

test_dirs=""
# Some desktop shells force SIGINT to ignored for every asynchronous job.
# TERM/HUP are exercised here; the router gate tests INT under BusyBox/procd.
for signal in TERM HUP; do
	MW_FAKE_IP_MODE=hold MULTIWAN_NFT_LIB_ROOT="$tmp/lib" \
		sh -c 'trap - HUP INT TERM; exec sh "$1" ipv4' sh "$rtmon" &
	parent_pid=$!
	parent_start="$(mw_process_start_time "$parent_pid")"
	child_pid=""
	count=0
	while [ -z "$child_pid" ] && [ "$count" -lt 10 ]; do
		child_pid="$(child_of "$parent_pid" 2>/dev/null || true)"
		[ -n "$child_pid" ] || sleep 1
		count=$((count + 1))
	done
	[ -n "$child_pid" ] || fail "no route monitor child for $signal test"
	child_start="$(mw_process_start_time "$child_pid")"
	work_dir="$(workdir_for_owner "$parent_pid")"
	test_dirs="$test_dirs $work_dir"
	kill "-$signal" "$parent_pid"
	if ! wait_gone "$parent_pid" "$parent_start"; then
		kill -KILL "$parent_pid" 2>/dev/null || true
		fail "route monitor parent ignored $signal"
	fi
	wait "$parent_pid" 2>/dev/null || true
	parent_pid=""
	wait_gone "$child_pid" "$child_start" || fail "route monitor child survived parent $signal"
	child_pid=""
done

# A SIGKILL cannot run parent cleanup. The next instance must reclaim the dead
# owner's workspace without colliding when the kernel later reuses its PID.
MW_FAKE_IP_MODE=hold MULTIWAN_NFT_LIB_ROOT="$tmp/lib" \
	sh -c 'trap - HUP INT TERM; exec sh "$1" ipv4' sh "$rtmon" &
parent_pid=$!
parent_start="$(mw_process_start_time "$parent_pid")"
child_pid=""
count=0
while [ -z "$child_pid" ] && [ "$count" -lt 10 ]; do
	child_pid="$(child_of "$parent_pid" 2>/dev/null || true)"
	[ -n "$child_pid" ] || sleep 1
	count=$((count + 1))
done
[ -n "$child_pid" ] || fail "no route monitor child for stale-workspace test"
child_start="$(mw_process_start_time "$child_pid")"
stale_dir="$(workdir_for_owner "$parent_pid")"
test_dirs="$test_dirs $stale_dir"
kill -KILL "$parent_pid"
wait "$parent_pid" 2>/dev/null || true
parent_pid=""
kill -KILL "$child_pid" 2>/dev/null || true
wait_gone "$child_pid" "$child_start" || fail "killed route monitor child remained alive"
child_pid=""

MW_FAKE_IP_MODE=hold MULTIWAN_NFT_LIB_ROOT="$tmp/lib" \
	sh -c 'trap - HUP INT TERM; exec sh "$1" ipv4' sh "$rtmon" &
parent_pid=$!
parent_start="$(mw_process_start_time "$parent_pid")"
child_pid=""
count=0
while [ -z "$child_pid" ] && [ "$count" -lt 10 ]; do
	child_pid="$(child_of "$parent_pid" 2>/dev/null || true)"
	[ -n "$child_pid" ] || sleep 1
	count=$((count + 1))
done
[ -n "$child_pid" ] || fail "replacement route monitor did not start"
[ ! -e "$stale_dir" ] || fail "dead-owner route monitor workspace was not reclaimed"
child_start="$(mw_process_start_time "$child_pid")"
work_dir="$(workdir_for_owner "$parent_pid")"
test_dirs="$test_dirs $work_dir"
kill -TERM "$parent_pid"
wait_gone "$parent_pid" "$parent_start" || fail "replacement route monitor parent ignored TERM"
wait "$parent_pid" 2>/dev/null || true
parent_pid=""
wait_gone "$child_pid" "$child_start" || fail "replacement route monitor child survived cleanup"
child_pid=""
[ ! -e "$work_dir" ] || fail "owned route monitor workspace survived clean shutdown"

MW_FAKE_IP_MODE=exit MULTIWAN_NFT_LIB_ROOT="$tmp/lib" \
	sh -c 'trap - HUP INT TERM; exec sh "$1" ipv4' sh "$rtmon" &
parent_pid=$!
parent_start="$(mw_process_start_time "$parent_pid")"
count=0
while process_running "$parent_pid" "$parent_start" && [ "$count" -lt 10 ]; do
	sleep 1
	count=$((count + 1))
done
! process_running "$parent_pid" "$parent_start" || fail "parent did not detect dead route monitor child"
wait "$parent_pid" 2>/dev/null || true
parent_pid=""

MULTIWAN_NFT_LIB_ROOT="$tmp/lib"
MULTIWAN_NFT_TRACK_LIBRARY_ONLY=1
export MULTIWAN_NFT_LIB_ROOT MULTIWAN_NFT_TRACK_LIBRARY_ONLY
# shellcheck disable=SC1090
. "$tracker"
sleep 30 &
probe_pid=$!
probe_start="$(mw_process_start_time "$probe_pid")"
stop_child "$probe_pid" "$probe_start" "synthetic probe"
! kill -0 "$probe_pid" 2>/dev/null || fail "tracker child survived owned cleanup"

printf 'NFT child lifecycle checks passed\n'
