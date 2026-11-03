#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-rtmon-lock.XXXXXX")
worker=
cleanup() {
    exec 1000>&-
    [ -z "$worker" ] || { kill "$worker" 2>/dev/null || :; wait "$worker" 2>/dev/null || :; }
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_rtmon_refresh_config()/,/^main()/p' "$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon" | sed '$d')"
command -v multiwan_nft_rtmon_with_lock >/dev/null || fail 'Route monitor has no service serialization'
IPKG_INSTROOT="$TEST_ROOT/root"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/status"
MULTIWAN_NFT_CONNTRACK_MAP="$TEST_ROOT/map"
RTMON_WORK_DIR="$TEST_ROOT/work"
RTMON_CONFIG_READY=0
NFT=mock_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft
mkdir -p "$IPKG_INSTROOT/var/lock" "$MULTIWAN_NFT_STATUS_DIR" "$RTMON_WORK_DIR"
printf 'old\n' > "$MULTIWAN_NFT_CONNTRACK_MAP"
printf 'old\n' > "$TEST_ROOT/proposed"
LOG() { :; }
mock_nft() { [ ! -f "$TEST_ROOT/no-hook" ]; }
multiwan_nft_reconfiguration_pending() { [ -f "$TEST_ROOT/guard" ]; }
multiwan_nft_init() {
    [ ! -f "$TEST_ROOT/init-error" ] || return 1
    cached=$(cat "$TEST_ROOT/proposed")
    printf '%s\n' "$cached" >> "$TEST_ROOT/loads"
}
multiwan_nft_stage_conntrack_map() { printf '%s\n' "$cached" > "$1"; }
multiwan_nft_update_iface_to_table() { :; }
mutate() { printf '%s\n' "$cached" >> "$TEST_ROOT/events"; return "${callback_status:-0}"; }
assert_unlocked() {
    ( exec 9>>"$IPKG_INSTROOT/var/lock/procd_multiwan-nft.lock"; flock -n 9 ) || fail 'Callback leaked service lock'
}
wait_for_event() {
    local count=0
    until [ -s "$TEST_ROOT/events" ]; do
        count=$((count+1)); [ "$count" -lt 80 ] || fail 'Waiting worker never handled event'
        sleep 0.05
    done
}

# The worker inherits the manager's locked descriptor, then must open its own.
exec 1000>>"$IPKG_INSTROOT/var/lock/procd_multiwan-nft.lock"
flock 1000
( multiwan_nft_rtmon_with_lock mutate ) &
worker=$!
sleep 0.2
[ ! -e "$TEST_ROOT/events" ] || fail 'Inherited descriptor bypassed service lock'
printf 'new\n' > "$TEST_ROOT/proposed"
cp "$TEST_ROOT/proposed" "$TEST_ROOT/map-next"
mv "$TEST_ROOT/map-next" "$MULTIWAN_NFT_CONNTRACK_MAP"
exec 1000>&-
wait_for_event
wait "$worker"
worker=
grep -qx new "$TEST_ROOT/events" || fail 'Worker used configuration from before lock acquisition'
assert_unlocked

: > "$TEST_ROOT/events"
multiwan_nft_rtmon_with_lock mutate
printf 'unapplied\n' > "$TEST_ROOT/proposed"
multiwan_nft_rtmon_with_lock mutate
[ "$(cat "$TEST_ROOT/events")" = "$(printf 'new\nnew')" ] || fail 'Unapplied UCI order replaced active configuration'
[ "$(wc -l < "$TEST_ROOT/loads")" -eq 2 ] || fail 'Unchanged applied generation reloaded raw UCI'

printf 'applied\n' > "$TEST_ROOT/map-next"
mv "$TEST_ROOT/map-next" "$MULTIWAN_NFT_CONNTRACK_MAP"
if multiwan_nft_rtmon_with_lock mutate; then fail 'Mismatched identity map was accepted'; fi
assert_unlocked
printf 'applied\n' > "$TEST_ROOT/proposed"
multiwan_nft_rtmon_with_lock mutate
[ "$(tail -n 1 "$TEST_ROOT/events")" = applied ] || fail 'New committed generation was not loaded'

for condition in guard no-hook init-error; do
    : > "$TEST_ROOT/events"
    : > "$TEST_ROOT/$condition"
    RTMON_CONFIG_READY=0
    status=0
    multiwan_nft_rtmon_with_lock mutate || status=$?
    case "$condition:$status" in init-error:1|guard:2|no-hook:2) ;; *) fail "Wrong failure status during $condition: $status" ;; esac
    [ ! -s "$TEST_ROOT/events" ] || fail "Mutation ran during $condition"
    assert_unlocked
    rm "$TEST_ROOT/$condition"
done
rmdir "$MULTIWAN_NFT_STATUS_DIR"
status=0
multiwan_nft_rtmon_with_lock mutate || status=$?
[ "$status" -eq 2 ] || fail 'Stopped service was not reported as intentionally skipped'
[ ! -d "$MULTIWAN_NFT_STATUS_DIR" ] || fail 'Stopped service state was recreated'
assert_unlocked
mkdir "$MULTIWAN_NFT_STATUS_DIR"
callback_status=7
status=0
multiwan_nft_rtmon_with_lock mutate || status=$?
[ "$status" -eq 7 ] || fail 'Callback failure was hidden'
assert_unlocked
callback_status=0

flock() { printf 'controlled lock failure\n' >&2; return 1; }
multiwan_nft_rtmon_with_lock mutate && fail 'Lock error was accepted'
unset -f flock
assert_unlocked

: > "$TEST_ROOT/events"
exec 1000>>"$IPKG_INSTROOT/var/lock/procd_multiwan-nft.lock"
flock 1000
( trap 'exit 0' TERM; multiwan_nft_rtmon_with_lock mutate ) &
worker=$!
sleep 0.2
kill -TERM "$worker"
wait "$worker"
worker=
[ ! -s "$TEST_ROOT/events" ] || fail 'Terminated waiter mutated routes'
exec 1000>&-
assert_unlocked
exec 4<&-
printf 'NFT route monitor locking tests passed: inherited locks, applied generations, failure cleanup and stopped-state isolation.\n'
