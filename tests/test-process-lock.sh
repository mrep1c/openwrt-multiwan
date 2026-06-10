#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
tmp_base="${TMPDIR:-/tmp}/multiwan-process-lock-test.$$"

cleanup() {
	rm -rf "$tmp_base"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$tmp_base"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tested=0
for helper in \
	"$repo_root/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" \
	"$repo_root/multiwan-qos/lib/multiwan-qos/process-lock.sh"
do
	[ -f "$helper" ] || continue
	tested=$((tested + 1))
	lock="$tmp_base/lock-$tested"

	# shellcheck disable=SC1090
	. "$helper"
	mw_lock_acquire "$lock" || fail "$helper: initial acquire"
	first_token="$MW_LOCK_TOKEN"
	(
		# shellcheck disable=SC1090
		. "$helper"
		! mw_lock_acquire "$lock"
	) || fail "$helper: live owner was not exclusive"

	mw_lock_release_for "$lock" "not-the-owner"
	mw_lock_owner_alive "$lock" || fail "$helper: foreign token released live lock"
	mw_lock_release_for "$lock" "$first_token"
	[ ! -d "$lock" ] || fail "$helper: owner release left lock directory"

	self_start="$(mw_process_start_time "$$")"
	mkdir "$lock"
	printf '%s %s stale-token\n' "$$" "$((self_start + 1))" > "$lock/owner"
	mw_lock_acquire "$lock" || fail "$helper: mismatched start time was not reclaimed"
	second_token="$MW_LOCK_TOKEN"
	mw_lock_release_for "$lock" "$first_token"
	mw_lock_owner_alive "$lock" || fail "$helper: old owner token removed successor lock"
	mw_lock_release_for "$lock" "$second_token"

	mkdir "$lock.guard"
	printf '%s %s stale-guard\n' "$$" "$((self_start + 1))" > "$lock.guard/owner"
	mw_lock_acquire "$lock" || fail "$helper: stale guard was not reclaimed"
	mw_lock_release

	ready="$tmp_base/ready-$tested"
	sh -c '. "$1"; mw_lock_acquire "$2" || exit 1; : > "$3"; sleep 30' \
		sh "$helper" "$lock" "$ready" &
	owner_pid=$!
	count=0
	while [ ! -f "$ready" ] && [ "$count" -lt 20 ]; do
		sleep 1
		count=$((count + 1))
	done
	[ -f "$ready" ] || fail "$helper: child owner did not acquire lock"
	kill -KILL "$owner_pid" 2>/dev/null || true
	wait "$owner_pid" 2>/dev/null || true
	mw_lock_acquire "$lock" || fail "$helper: dead owner lock was not reclaimed"
	mw_lock_release

	printf 'PASS: %s\n' "$helper"
done

[ "$tested" -gt 0 ] || fail "no process-lock helper found"
