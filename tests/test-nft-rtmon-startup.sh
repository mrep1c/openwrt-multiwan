#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-rtmon-startup.XXXXXX")
worker=
cleanup() {
    [ -z "$worker" ] || { kill -TERM "$worker" 2>/dev/null || :; wait "$worker" 2>/dev/null || :; }
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft"
for file in functions.sh functions/network.sh multiwan-nft/multiwan_nft.sh; do : > "$TEST_ROOT/lib/$file"; done
cp "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" "$TEST_ROOT/lib/multiwan-nft/"
cat > "$TEST_ROOT/ip-monitor" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import socket
import sys
import time

root = Path(os.environ['RTMON_TEST_ROOT'])
if root.joinpath('hold-term').exists():
    def hold_termination(signum, frame):
        root.joinpath('child-terminating').touch()
        while not root.joinpath('allow-exit').exists():
            time.sleep(.02)
        sys.exit(0)
    signal.signal(signal.SIGTERM, hold_termination)
family = sys.argv[1]
assert sys.argv[2:] == ['-o', 'monitor', 'route', 'nexthop'], sys.argv
try:
    os.fstat(1000)
except OSError:
    pass
else:
    sys.stderr.write('inherited manager lock descriptor\n')
    sys.exit(8)
root.joinpath('child').write_text(str(os.getpid()))
while not root.joinpath('release').exists():
    time.sleep(.02)
if root.joinpath('die').exists():
    sys.stderr.write('controlled subscription failure\n')
    sys.exit(7)
# Reserve the PID port ID so readiness must use the child's socket inode.
query = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
query.bind((0, 0))
monitor = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE)
group = 0x40 if family == '-4' else 0x400
if root.joinpath('wrong-group').exists():
    group = 0x40 if group == 0x400 else 0x400
group |= 0x80000000  # RTNLGRP_NEXTHOP
if root.joinpath('missing-nexthop').exists():
    group &= ~0x80000000
monitor.bind((0, group))
fd = os.open(root / 'input', os.O_RDWR)
with os.fdopen(fd) as stream:
    for line in stream:
        if line.rstrip('\n') == 'BURST_EVENT':
            sys.stdout.write('id 94 group 91/92,3\n' * 64)
            sys.stdout.flush()
            continue
        if line.rstrip('\n') == 'SOURCE_BURST':
            route = '198.18.99.0/24' if family == '-4' else '2001:db8:99::/64'
            sys.stdout.write((route + ' dev test0\n') * 64)
            sys.stdout.flush()
            continue
        if line.rstrip('\n') == 'PARTIAL_BURST':
            sys.stdout.write('id 94 group 91/92,3\nid 95 group 91/')
            sys.stdout.flush()
            continue
        if line.rstrip('\n') == 'STREAM_ERROR':
            sys.stderr.write('controlled notification loss, unknown locale and errno\n')
            sys.stderr.flush()
            continue
        print(line.rstrip('\n'), flush=True)
PY
chmod 755 "$TEST_ROOT/ip-monitor"
cat > "$TEST_ROOT/worker.sh" <<'SH'
#!/bin/sh
RTMON_TEST_ROOT=$1
export RTMON_TEST_ROOT
MULTIWAN_NFT_LIB_ROOT="$1/lib"
MULTIWAN_NFT_RTMON_LIBRARY_ONLY=1
. "$2/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon"
IP4="$1/ip-monitor -4" IP6="$1/ip-monitor -6" NO_IPV6=0
LOG() { printf '%s\n' "$*" >> "$RTMON_TEST_ROOT/log"; }
multiwan_nft_rtmon_with_lock() { "$@"; }
multiwan_nft_rtmon_source_table() {
    case "$1" in '198.18.99.0/24 dev test0'|'2001:db8:99::/64 dev test0') printf 'main\n' ;; *) return 1 ;; esac
}
mkfifo() { command mkfifo "$@"; printf '%s\n' "$RTMON_WORK_DIR" > "$RTMON_TEST_ROOT/workspace"; }
multiwan_nft_add_all_routes() {
    multiwan_nft_rtmon_subscribed "$1" || { LOG 'snapshot ran before subscription'; return 1; }
    printf 'snapshot\n' > "$RTMON_TEST_ROOT/snapshot"
    printf 'snapshot\n' >> "$RTMON_TEST_ROOT/refresh-count"
    printf 'Deleted old route\nnew route\n' > "$RTMON_TEST_ROOT/input"
}
multiwan_nft_rtmon_event() {
    case "$1" in
        id\ [0-9]*) multiwan_nft_add_all_routes "$2"; return $? ;;
        FAILED_EVENT) return 1 ;;
        SKIPPED_EVENT) : > "$RTMON_TEST_ROOT/skipped"; return 2 ;;
    esac
    printf '%s\n' "$1" >> "$RTMON_TEST_ROOT/events"
}
main "$3"
SH
wait_for() {
    local count=0
    until "$@"; do
        count=$((count+1)); [ "$count" -lt 300 ] || { cat "$TEST_ROOT/log" 2>/dev/null || :; fail 'Monitor startup/recovery deadline'; }
        sleep 0.05
    done
}
start_worker() {
    rm -f "$TEST_ROOT/release" "$TEST_ROOT/child" "$TEST_ROOT/snapshot" "$TEST_ROOT/events" "$TEST_ROOT/input" "$TEST_ROOT/workspace" "$TEST_ROOT/log"
    mkfifo "$TEST_ROOT/input"
    exec 1000>>"$TEST_ROOT/inherited-lock"
    busybox ash "$TEST_ROOT/worker.sh" "$TEST_ROOT" "$REPO_ROOT" "$1" &
    worker=$!
    exec 1000>&-
    wait_for test -s "$TEST_ROOT/workspace"
    wait_for test -s "$TEST_ROOT/child"
}
assert_clean() {
    local workspace
    workspace=$(cat "$TEST_ROOT/workspace")
    [ ! -d "$workspace" ] || fail 'Startup left its owned workspace'
    ! kill -0 "$(cat "$TEST_ROOT/child")" 2>/dev/null || fail 'Startup left its owned child'
}
for family in ipv4 ipv6; do
    start_worker "$family"
    [ ! -e "$TEST_ROOT/snapshot" ] || fail 'Snapshot preceded child subscription'
    : > "$TEST_ROOT/release"
    complete() { [ -f "$TEST_ROOT/events" ] && [ "$(wc -l < "$TEST_ROOT/events")" -eq 2 ]; }
    wait_for complete
    [ "$(cat "$TEST_ROOT/events")" = "$(printf 'Deleted old route\nnew route')" ] || fail 'Initial snapshot lost queued events'
    # Repeated loss must recover in the same supervisor, without a respawn limit.
    round=0
    limit=6
    [ "$family" = ipv4 ] || limit=2
    while [ "$round" -lt "$limit" ]; do
        old_child=$(cat "$TEST_ROOT/child")
        expected=$(((round+2)*2))
        printf 'STREAM_ERROR\n' > "$TEST_ROOT/input"
        recovered() {
            [ "$(cat "$TEST_ROOT/child")" != "$old_child" ] &&
                [ "$(wc -l < "$TEST_ROOT/events")" -eq "$expected" ]
        }
        wait_for recovered
        ! kill -0 "$old_child" 2>/dev/null || fail 'Recovery left the old stream child alive'
        kill -0 "$worker" || fail 'Stream loss terminated the supervised parent'
        round=$((round+1))
    done
    old_child=$(cat "$TEST_ROOT/child")
    expected=$((expected+2))
    printf 'FAILED_EVENT\n' > "$TEST_ROOT/input"
    wait_for recovered
    ! kill -0 "$old_child" 2>/dev/null || fail 'Event recovery left the old child alive'
    kill -0 "$worker" || fail 'Failed update terminated the supervised parent'
    old_child=$(cat "$TEST_ROOT/child")
    rm -f "$TEST_ROOT/skipped"
    printf 'SKIPPED_EVENT\n' > "$TEST_ROOT/input"
    wait_for test -f "$TEST_ROOT/skipped"
    printf 'after skip\n' > "$TEST_ROOT/input"
    skipped_complete() { [ "$(tail -n 1 "$TEST_ROOT/events")" = 'after skip' ]; }
    wait_for skipped_complete
    [ "$(cat "$TEST_ROOT/child")" = "$old_child" ] || fail 'Intentional refusal restarted the stream'
    before=$(wc -l < "$TEST_ROOT/refresh-count")
    expected_events=$(( $(wc -l < "$TEST_ROOT/events") + 2 ))
    printf 'BURST_EVENT\n' > "$TEST_ROOT/input"
    batched() { [ "$(wc -l < "$TEST_ROOT/events")" -ge "$expected_events" ]; }
    wait_for batched
    [ "$(wc -l < "$TEST_ROOT/refresh-count")" -eq "$((before+1))" ] || fail 'Queued nexthop burst repeated full snapshots'
    before=$(wc -l < "$TEST_ROOT/refresh-count")
    expected_events=$(( $(wc -l < "$TEST_ROOT/events") + 2 ))
    printf 'SOURCE_BURST\n' > "$TEST_ROOT/input"
    wait_for batched
    [ "$(wc -l < "$TEST_ROOT/refresh-count")" -eq "$((before+1))" ] || fail 'Queued source-route burst was replayed event by event'
    old_child=$(cat "$TEST_ROOT/child")
    before=$(wc -l < "$TEST_ROOT/refresh-count")
    expected_events=$(( $(wc -l < "$TEST_ROOT/events") + 2 ))
    printf 'PARTIAL_BURST\n' > "$TEST_ROOT/input"
    partial_recovered() { [ "$(cat "$TEST_ROOT/child")" != "$old_child" ] && batched; }
    wait_for partial_recovered
    [ "$(wc -l < "$TEST_ROOT/refresh-count")" -eq "$((before+1))" ] || fail 'Partial notification was treated as a complete update'
    ! kill -0 "$old_child" 2>/dev/null || fail 'Partial-frame recovery left the old stream alive'
    kill -TERM "$worker"
    wait "$worker"
    worker=
    assert_clean
done
for mode in die wrong-group missing-nexthop; do
    : > "$TEST_ROOT/$mode"
    start_worker ipv4
    : > "$TEST_ROOT/release"
    status=0
    wait "$worker" || status=$?
    worker=
    [ "$status" -ne 0 ] || fail "Invalid subscription accepted: $mode"
    [ ! -e "$TEST_ROOT/snapshot" ] || fail "Snapshot ran with invalid subscription: $mode"
    assert_clean
    rm "$TEST_ROOT/$mode"
done
start_worker ipv6
kill -TERM "$worker"
wait "$worker"
worker=
[ ! -e "$TEST_ROOT/snapshot" ] || fail 'Terminated startup performed snapshot'
assert_clean
: > "$TEST_ROOT/hold-term"
start_worker ipv4
: > "$TEST_ROOT/release"
wait_for test -e "$TEST_ROOT/snapshot"
kill -TERM "$worker"
wait_for test -e "$TEST_ROOT/child-terminating"
kill -TERM "$worker"
: > "$TEST_ROOT/allow-exit"
wait "$worker"
worker=
assert_clean
printf 'NFT monitor startup tests passed: real subscriptions, socket identity, queued events, stream/update recovery, intentional refusals and repeated TERM cleanup. No routes changed.\n'
