#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-tracker.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

mkdir -p "$TEST_ROOT/lib/functions" "$TEST_ROOT/lib/multiwan-nft"
: > "$TEST_ROOT/lib/functions.sh"
: > "$TEST_ROOT/lib/functions/network.sh"
ln -s "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh" \
	"$TEST_ROOT/lib/multiwan-nft/common.sh"
ln -s "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" \
	"$TEST_ROOT/lib/multiwan-nft/process-lock.sh"

MULTIWAN_NFT_LIB_ROOT="$TEST_ROOT/lib"
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/status"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/tracker"
MULTIWAN_NFT_TRACK_LIBRARY_ONLY=1
NO_IPV6=0
set -- none
. "$REPO_ROOT/multiwan-nft/files/usr/sbin/multiwan-nft-track"

INTERFACE=wan
STATUS=testing
mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/$INTERFACE"
multiwan_nft_tracker_publish_owner || fail "tracker could not publish its owner journal"
[ -r "$TRACKER_OWNER_FILE" ] || fail "tracker owner journal was not created"

read -r owner_pid owner_start owner_token < "$TRACKER_OWNER_FILE" || fail "tracker owner journal was unreadable"
[ "$owner_pid" = "$$" ] || fail "tracker owner PID was wrong"
[ "$owner_start" = "$TRACKER_SELF_START" ] || fail "tracker owner start time was wrong"
[ "$owner_token" = "$TRACKER_OWNER_TOKEN" ] || fail "tracker owner token was wrong"

# A retiring process must not remove an owner journal already replaced by a
# respawned tracker.
printf '%s %s %s\n' "$$" "$TRACKER_SELF_START" replacement-token > "$TRACKER_OWNER_FILE"
multiwan_nft_tracker_remove_owner
[ -r "$TRACKER_OWNER_FILE" ] || fail "tracker removed a replacement owner's journal"

printf '%s %s %s\n' "$$" "$TRACKER_SELF_START" "$TRACKER_OWNER_TOKEN" > "$TRACKER_OWNER_FILE"
multiwan_nft_tracker_remove_owner
[ ! -e "$TRACKER_OWNER_FILE" ] || fail "tracker left its owner journal behind"

printf 'NFT tracker-owner regression tests passed.\n'
