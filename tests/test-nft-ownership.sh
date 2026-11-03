#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-ownership.XXXXXX")
work_dir=$(mktemp -d /tmp/multiwan-nft-rtmon-ipv4.XXXXXX)
unrelated= owned=
cleanup() {
    for pid in "$unrelated" "$owned"; do
        [ -z "$pid" ] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }
    done
    rm -f "$work_dir/owner" "$work_dir/child"
    rmdir "$work_dir"
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh"
self_start=$(mw_process_start_time "$$")
token=rtmon:99999999:1:owned-test
printf '99999999 1 %s\n' "$token" > "$work_dir/owner"
printf '%s %s %s\n' "$$" "$self_start" "$token" > "$work_dir/child"
mw_rtmon_orphan_pids ipv4 > "$TEST_ROOT/pids"
grep -qxF "$$:$self_start" "$TEST_ROOT/pids" || fail 'Recorded owned orphan was missed'
for invalid in start token extra; do
    case "$invalid" in
        start) printf '%s %s %s\n' "$$" "$((self_start+1))" "$token" ;;
        token) printf '%s %s wrong-token\n' "$$" "$self_start" ;;
        extra) printf '%s %s %s extra\n' "$$" "$self_start" "$token" ;;
    esac > "$work_dir/child"
    mw_rtmon_orphan_pids ipv4 > "$TEST_ROOT/pids"
    if grep -qF "$$:" "$TEST_ROOT/pids"; then fail 'Invalid child identity was accepted'; fi
done
printf '%s %s %s\n' "$$" "$self_start" "$token" > "$work_dir/child"
chmod 777 "$work_dir"
mw_rtmon_orphan_pids ipv4 > "$TEST_ROOT/pids"
if grep -qF "$$:" "$TEST_ROOT/pids"; then fail 'Publicly writable ownership metadata was trusted'; fi
chmod 700 "$work_dir"
printf '%s %s rtmon:%s:%s:live\n' "$$" "$self_start" "$$" "$self_start" > "$work_dir/owner"
printf '%s %s rtmon:%s:%s:live\n' "$$" "$self_start" "$$" "$self_start" > "$work_dir/child"
mw_rtmon_orphan_pids ipv4 > "$TEST_ROOT/pids"
if grep -qF "$$:" "$TEST_ROOT/pids"; then fail 'Live worker child was treated as orphaned'; fi

eval "$(sed -n '/^multiwan_nft_helper_pids()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
command -v bash >/dev/null 2>&1 || fail 'Bash is required for the inert argv fixture'
bash -c 'exec -a "$1" sleep 30' _ 'vim /usr/sbin/multiwan-nft-track' &
unrelated=$!
bash -c 'exec -a "$1" sleep 30' _ '/bin/sh /usr/sbin/multiwan-nft-track' &
owned=$!
attempt=0
while ! tr '\0' ' ' < "/proc/$owned/cmdline" | grep -qF '/bin/sh /usr/sbin/multiwan-nft-track'; do
    attempt=$((attempt+1)); [ "$attempt" -lt 50 ] || fail 'Argv fixture did not start'
    sleep 0.02
done
multiwan_nft_helper_pids multiwan-nft-track > "$TEST_ROOT/pids"
grep -q "^$owned:" "$TEST_ROOT/pids" || fail 'Package helper was not recognized'
if grep -q "^$unrelated:" "$TEST_ROOT/pids"; then fail 'Editor of a helper script was mistaken for a running helper'; fi
printf 'NFT ownership tests passed: recorded orphan identity, live owners, unsafe metadata, PID reuse and unrelated argv.\n'
