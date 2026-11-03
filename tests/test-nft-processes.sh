#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-processes.XXXXXX")
worker=
cleanup() { [ -z "$worker" ] || { kill "$worker" 2>/dev/null || :; wait "$worker" 2>/dev/null || :; }; rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh"
self_start=$(mw_process_start_time "$$")
mw_process_identity_alive "$$" "$self_start" || fail 'Live process identity not recognized'
if mw_process_identity_alive "$$" "$((self_start + 1))"; then fail 'Reused PID identity accepted'; fi
mw_lock_acquire "$TEST_ROOT/live.lock" || fail 'Lock acquisition failed'
token=$MW_LOCK_TOKEN
mw_lock_release_for "$TEST_ROOT/live.lock" wrong-token
[ -d "$TEST_ROOT/live.lock" ] || fail 'Wrong owner released lock'
mw_lock_release_for "$TEST_ROOT/live.lock" "$token"
[ ! -e "$TEST_ROOT/live.lock" ] || fail 'Owner failed to release lock'
mkdir "$TEST_ROOT/stale.lock"
printf '%s %s stale\n' "$$" "$((self_start + 1))" > "$TEST_ROOT/stale.lock/owner"
mw_lock_reclaim_stale "$TEST_ROOT/stale.lock" || fail 'Stale PID lock was not reclaimed'

mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft"
for name in functions.sh functions/network.sh multiwan-nft/common.sh; do : > "$TEST_ROOT/lib/$name"; done
cp "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" "$TEST_ROOT/lib/multiwan-nft/"
cat > "$TEST_ROOT/worker.sh" <<'SH'
#!/bin/sh
MULTIWAN_NFT_LIB_ROOT="$1/lib"
MULTIWAN_NFT_TRACK_LIBRARY_ONLY=1
. "$2/multiwan-nft/files/usr/sbin/multiwan-nft-track"
LOG() { :; }
INTERFACE=test
STATUS=online
trap clean_up HUP INT TERM
trap if_down USR1
trap if_up USR2
while :; do
    sleep 30 &
    SLEEP_PID=$!
    SLEEP_START=$(mw_process_start_time "$SLEEP_PID")
    printf '%s\n' "$SLEEP_PID" > "$1/child"
    wait "$SLEEP_PID" || :
    printf '%s %s\n' "$IFDOWN_EVENT" "$IFUP_EVENT" >> "$1/events"
done
SH
busybox ash "$TEST_ROOT/worker.sh" "$TEST_ROOT" "$REPO_ROOT" &
worker=$!
wait_for() {
    local attempt=0
    while ! "$@"; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 150 ] || fail 'Worker did not respond within deadline'
        kill -0 "$worker" || fail 'Worker exited unexpectedly'
        sleep 0.05
    done
}
wait_for test -s "$TEST_ROOT/child"
first_child=$(cat "$TEST_ROOT/child")
kill -USR1 "$worker"
event_down() { [ -f "$TEST_ROOT/events" ] && grep -qxF '1 0' "$TEST_ROOT/events"; }
wait_for event_down
if kill -0 "$first_child" 2>/dev/null; then fail 'USR1 left owned probe child alive'; fi
kill -USR2 "$worker"
event_up() { grep -qxF '0 1' "$TEST_ROOT/events"; }
wait_for event_up
last_child=$(cat "$TEST_ROOT/child")
kill -TERM "$worker"
wait "$worker"
worker=
if kill -0 "$last_child" 2>/dev/null; then fail 'TERM left owned probe child alive'; fi
printf 'NFT process tests passed: PID identity, lock ownership, real USR1/USR2/TERM, and owned child cleanup.\n'
