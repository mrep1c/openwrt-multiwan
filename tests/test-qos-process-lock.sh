#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-qos-lock.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

# The lock helper must not need external cat(1) or date(1). These commands used
# to be spawned several times for every rate change and hotplug lock.
cat() { fail "process identity forked cat"; }
date() { fail "lock token forked date"; }

set -- none
. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/process-lock.sh"

self_start="$(mw_process_start_time "$$")" || fail "could not read the current process identity"
case "$self_start" in ''|*[!0-9]*) fail "process start time was not numeric" ;; esac
mw_process_identity_alive "$$" "$self_start" || fail "current process identity was not alive"
mw_process_identity_alive "$$" "$((self_start + 1))" && fail "mismatched process start time was accepted"

lock_dir="$TEST_ROOT/primary.lock"
mw_lock_acquire "$lock_dir" || fail "could not acquire an empty lock"
lock_token="$MW_LOCK_TOKEN"
case "$lock_token" in
	"lock:$$:$self_start:"[0-9]*) ;;
	*) fail "lock token did not use the BusyBox-safe process identity" ;;
esac
[ -r "$lock_dir/owner" ] || fail "lock acquisition did not publish ownership"

if sh -c 'helper="$1"; lock_dir="$2"; set -- none; . "$helper"; mw_lock_acquire "$lock_dir"' \
    sh "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/process-lock.sh" "$lock_dir"; then
	fail "a competing process acquired a live lock"
fi
mw_lock_release_for "$lock_dir" wrong-token || fail "wrong-token release returned failure"
[ -d "$lock_dir" ] || fail "wrong-token release removed another owner's lock"
mw_lock_release_for "$lock_dir" "$lock_token" || fail "owner could not release its lock"
[ ! -e "$lock_dir" ] || fail "released lock directory remains"

stale_dir="$TEST_ROOT/stale.lock"
mkdir "$stale_dir" || fail "could not create stale lock fixture"
printf '%s %s %s\n' "$$" "$((self_start + 1))" stale-token > "$stale_dir/owner"
mw_lock_reclaim_stale "$stale_dir" || fail "could not reclaim a stale process identity"
[ ! -e "$stale_dir" ] || fail "stale lock directory remains"

live_dir="$TEST_ROOT/live.lock"
mkdir "$live_dir" || fail "could not create live lock fixture"
printf '%s %s %s\n' "$$" "$self_start" live-token > "$live_dir/owner"
mw_lock_reclaim_stale "$live_dir" && fail "reclaimed a live process identity"
[ -d "$live_dir" ] || fail "live lock directory was removed"

printf 'QoS process-lock regression tests passed.\n'
