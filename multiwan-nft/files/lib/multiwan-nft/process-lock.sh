#!/bin/sh

# Process identity and directory-lock helpers for BusyBox ash. Lock ownership is
# tied to both PID and /proc start time so a reused PID cannot inherit a lock.

MW_LOCK_SEQUENCE="${MW_LOCK_SEQUENCE:-0}"
MW_LOCK_DIR=""
MW_LOCK_TOKEN=""
MW_LOCK_OWNER_PID=""
MW_LOCK_OWNER_START=""
MW_LOCK_OWNER_TOKEN=""
MW_LOCK_GUARD_DIR=""
MW_LOCK_GUARD_TOKEN=""

mw_process_start_time() {
	local pid="$1" stat rest

	case "$pid" in
		""|*[!0-9]*) return 1 ;;
	esac
	[ -r "/proc/$pid/stat" ] || return 1
	stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
	rest="${stat##*) }"
	set -- $rest
	[ "$#" -ge 20 ] || return 1
	shift 19
	case "$1" in
		""|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$1"
}

mw_process_identity_alive() {
	local pid="$1" expected_start="$2" current_start

	case "$pid:$expected_start" in
		*[!0-9:]*|:|*:) return 1 ;;
	esac
	kill -0 "$pid" 2>/dev/null || return 1
	current_start="$(mw_process_start_time "$pid")" || return 1
	[ "$current_start" = "$expected_start" ]
}

mw_lock_read_owner() {
	local lock_dir="$1"

	MW_LOCK_OWNER_PID=""
	MW_LOCK_OWNER_START=""
	MW_LOCK_OWNER_TOKEN=""
	[ -r "$lock_dir/owner" ] || return 1
	read -r MW_LOCK_OWNER_PID MW_LOCK_OWNER_START MW_LOCK_OWNER_TOKEN < "$lock_dir/owner" || return 1
	[ -n "$MW_LOCK_OWNER_TOKEN" ] || return 1
	return 0
}

mw_lock_owner_alive() {
	local lock_dir="$1"

	mw_lock_read_owner "$lock_dir" || return 1
	mw_process_identity_alive "$MW_LOCK_OWNER_PID" "$MW_LOCK_OWNER_START"
}

mw_lock_write_owner() {
	local lock_dir="$1" pid="$2" start="$3" token="$4"
	local tmp="$lock_dir/.owner.$$"

	printf '%s %s %s\n' "$pid" "$start" "$token" > "$tmp" || {
		rm -f "$tmp"
		return 1
	}
	mv "$tmp" "$lock_dir/owner" || {
		rm -f "$tmp"
		return 1
	}
}

mw_lock_guard_release() {
	local guard_dir="$MW_LOCK_GUARD_DIR" token="$MW_LOCK_GUARD_TOKEN"

	[ -n "$guard_dir" ] || return 0
	if mw_lock_read_owner "$guard_dir" && [ "$MW_LOCK_OWNER_TOKEN" = "$token" ]; then
		rm -f "$guard_dir/owner" "$guard_dir"/.owner.* 2>/dev/null
		rmdir "$guard_dir" 2>/dev/null
	fi
	MW_LOCK_GUARD_DIR=""
	MW_LOCK_GUARD_TOKEN=""
}

mw_lock_guard_acquire() {
	local lock_dir="$1" guard_dir="${1}.guard"
	local self_start token attempts=0

	self_start="$(mw_process_start_time "$$")" || return 1
	MW_LOCK_SEQUENCE=$((MW_LOCK_SEQUENCE + 1))
	token="guard:$$:$self_start:$(date +%s 2>/dev/null):$MW_LOCK_SEQUENCE"

	while [ "$attempts" -lt 3 ]; do
		if mkdir "$guard_dir" 2>/dev/null; then
			if mw_lock_write_owner "$guard_dir" "$$" "$self_start" "$token"; then
				MW_LOCK_GUARD_DIR="$guard_dir"
				MW_LOCK_GUARD_TOKEN="$token"
				return 0
			fi
			rm -f "$guard_dir/owner" "$guard_dir"/.owner.* 2>/dev/null
			rmdir "$guard_dir" 2>/dev/null
			return 1
		fi

		if mw_lock_owner_alive "$guard_dir"; then
			return 1
		fi

		# A creator may be between mkdir and the atomic owner-file rename.
		[ -r "$guard_dir/owner" ] || sleep 1
		if mw_lock_owner_alive "$guard_dir"; then
			return 1
		fi

		rm -f "$guard_dir/owner" "$guard_dir"/.owner.* 2>/dev/null
		rmdir "$guard_dir" 2>/dev/null || return 1
		attempts=$((attempts + 1))
	done
	return 1
}

mw_lock_acquire_for() {
	local lock_dir="$1" owner_pid="$2" owner_start="$3" owner_token="$4"

	mw_process_identity_alive "$owner_pid" "$owner_start" || return 1
	mw_lock_guard_acquire "$lock_dir" || return 1

	if [ -d "$lock_dir" ]; then
		if mw_lock_owner_alive "$lock_dir"; then
			mw_lock_guard_release
			return 1
		fi
		rm -f "$lock_dir/owner" "$lock_dir"/.owner.* 2>/dev/null
		rmdir "$lock_dir" 2>/dev/null || {
			mw_lock_guard_release
			return 1
		}
	fi

	mkdir "$lock_dir" 2>/dev/null || {
		mw_lock_guard_release
		return 1
	}
	if ! mw_lock_write_owner "$lock_dir" "$owner_pid" "$owner_start" "$owner_token"; then
		rm -f "$lock_dir/owner" "$lock_dir"/.owner.* 2>/dev/null
		rmdir "$lock_dir" 2>/dev/null
		mw_lock_guard_release
		return 1
	fi
	mw_lock_guard_release
	return 0
}

mw_lock_acquire() {
	local lock_dir="$1" self_start token

	self_start="$(mw_process_start_time "$$")" || return 1
	MW_LOCK_SEQUENCE=$((MW_LOCK_SEQUENCE + 1))
	token="lock:$$:$self_start:$(date +%s 2>/dev/null):$MW_LOCK_SEQUENCE"
	mw_lock_acquire_for "$lock_dir" "$$" "$self_start" "$token" || return 1
	MW_LOCK_DIR="$lock_dir"
	MW_LOCK_TOKEN="$token"
	return 0
}

mw_lock_release_for() {
	local lock_dir="$1" owner_token="$2" attempts=0

	while ! mw_lock_guard_acquire "$lock_dir"; do
		attempts=$((attempts + 1))
		[ "$attempts" -lt 5 ] || return 1
		sleep 1
	done

	if mw_lock_read_owner "$lock_dir" && [ "$MW_LOCK_OWNER_TOKEN" = "$owner_token" ]; then
		rm -f "$lock_dir/owner" "$lock_dir"/.owner.* 2>/dev/null
		rmdir "$lock_dir" 2>/dev/null
	fi
	mw_lock_guard_release
	return 0
}

mw_lock_release() {
	local lock_dir="${1:-$MW_LOCK_DIR}" owner_token="${2:-$MW_LOCK_TOKEN}"

	[ -n "$lock_dir" ] && [ -n "$owner_token" ] || return 0
	mw_lock_release_for "$lock_dir" "$owner_token"
	[ "$lock_dir" = "$MW_LOCK_DIR" ] && MW_LOCK_DIR=""
	[ "$owner_token" = "$MW_LOCK_TOKEN" ] && MW_LOCK_TOKEN=""
}

mw_lock_reclaim_stale() {
	local lock_dir="$1"

	[ -d "$lock_dir" ] || return 0
	mw_lock_owner_alive "$lock_dir" && return 1
	if mw_lock_acquire "$lock_dir"; then
		mw_lock_release
		return 0
	fi
	return 1
}

case "${1:-}" in
	--claim)
		[ "$#" -eq 5 ] || exit 2
		mw_lock_acquire_for "$2" "$3" "$4" "$5"
		exit $?
		;;
	--release)
		[ "$#" -eq 3 ] || exit 2
		mw_lock_release_for "$2" "$3"
		exit $?
		;;
	--status)
		[ "$#" -eq 2 ] || exit 2
		if mw_lock_owner_alive "$2"; then
			printf '%s %s %s\n' "$MW_LOCK_OWNER_PID" "$MW_LOCK_OWNER_START" "$MW_LOCK_OWNER_TOKEN"
			exit 0
		fi
		exit 1
		;;
esac
