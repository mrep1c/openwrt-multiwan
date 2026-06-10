#!/bin/sh
set -eu

# Run from a copy of this repository on an OpenWrt router. The currently
# installed runtime files are backed up before the source candidate is staged.

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="/root/multiwan-1.0.3-candidate-backup-$stamp"
stage_dir="/tmp/multiwan-1.0.3-stage.$$"
stage_started=0
stage_complete=0

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

restore_backup() {
	[ -d "$backup" ] || return 0

	find "$backup" -type f ! -path "$backup/.missing/*" | while IFS= read -r source; do
		target="${source#$backup}"
		mkdir -p "$(dirname "$target")"
		cp -p "$source" "$target"
	done

	if [ -d "$backup/.missing" ]; then
		find "$backup/.missing" -type f | while IFS= read -r marker; do
			target="${marker#$backup/.missing}"
			rm -f "$target"
		done
	fi
}

cleanup() {
	rc=$?
	trap - EXIT HUP INT TERM
	if [ "$stage_started" -eq 1 ] && [ "$stage_complete" -eq 0 ]; then
		echo "Candidate staging failed; restoring $backup" >&2
		restore_backup
		/etc/init.d/multiwan-nft start >/dev/null 2>&1 || true
		/etc/init.d/multiwan-qos start >/dev/null 2>&1 || true
	fi
	rm -rf "$stage_dir"
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$(id -u)" = 0 ] || fail "run this script as root"
[ -f "$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon" ] ||
	fail "run this script from the combined openwrt-multiwan repository"

mkdir -p "$backup" "$stage_dir"

prepare_file() {
	local source="$1" relative="$2" kind="$3"
	local prepared="$stage_dir/$relative"

	[ -f "$source" ] || fail "candidate source is missing: $source"
	mkdir -p "$(dirname "$prepared")"
	sed 's/\r$//' "$source" > "$prepared"
	case "$kind" in
		sh)
			sh -n "$prepared" || fail "shell syntax check failed: $source"
			;;
		lua)
			if command -v lua >/dev/null 2>&1; then
				lua -e "assert(loadfile([[$prepared]]))" ||
					fail "Lua syntax check failed: $source"
			fi
			;;
	esac
}

prepare_file "$repo_root/multiwan-nft/files/etc/init.d/multiwan-nft" \
	etc/init.d/multiwan-nft sh
prepare_file "$repo_root/multiwan-nft/files/lib/multiwan-nft/common.sh" \
	lib/multiwan-nft/common.sh sh
prepare_file "$repo_root/multiwan-nft/files/lib/multiwan-nft/process-lock.sh" \
	lib/multiwan-nft/process-lock.sh sh
prepare_file "$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-rtmon" \
	usr/sbin/multiwan-nft-rtmon sh
prepare_file "$repo_root/multiwan-nft/files/usr/sbin/multiwan-nft-track" \
	usr/sbin/multiwan-nft-track sh
prepare_file "$repo_root/multiwan-qos/etc/init.d/multiwan-qos" \
	etc/init.d/multiwan-qos sh
prepare_file "$repo_root/multiwan-qos/etc/multiwan-qos.sh" \
	etc/multiwan-qos.sh sh
prepare_file "$repo_root/multiwan-qos/lib/multiwan-qos/hotplug-common.sh" \
	lib/multiwan-qos/hotplug-common.sh sh
prepare_file "$repo_root/multiwan-qos/lib/multiwan-qos/process-lock.sh" \
	lib/multiwan-qos/process-lock.sh sh
prepare_file "$repo_root/multiwan-qos/www/cgi-bin/multiwan-qos-agent" \
	www/cgi-bin/multiwan-qos-agent lua

backup_path() {
	local target="$1"
	if [ -e "$target" ]; then
		mkdir -p "$backup$(dirname "$target")"
		cp -p "$target" "$backup$target"
	else
		mkdir -p "$backup/.missing$(dirname "$target")"
		: > "$backup/.missing$target"
	fi
}

stage_file() {
	local relative="$1" target="$2" mode="$3"
	backup_path "$target"
	mkdir -p "$(dirname "$target")"
	cp "$stage_dir/$relative" "$target"
	chmod "$mode" "$target"
}

DISABLE_ON_STOP=0 /etc/init.d/multiwan-qos stop || true
/etc/init.d/multiwan-nft stop || true
stage_started=1

stage_file etc/init.d/multiwan-nft \
	/etc/init.d/multiwan-nft 755
stage_file lib/multiwan-nft/common.sh \
	/lib/multiwan-nft/common.sh 644
stage_file lib/multiwan-nft/process-lock.sh \
	/lib/multiwan-nft/process-lock.sh 644
stage_file usr/sbin/multiwan-nft-rtmon \
	/usr/sbin/multiwan-nft-rtmon 755
stage_file usr/sbin/multiwan-nft-track \
	/usr/sbin/multiwan-nft-track 755

stage_file etc/init.d/multiwan-qos \
	/etc/init.d/multiwan-qos 755
stage_file etc/multiwan-qos.sh \
	/etc/multiwan-qos.sh 755
stage_file lib/multiwan-qos/hotplug-common.sh \
	/lib/multiwan-qos/hotplug-common.sh 644
stage_file lib/multiwan-qos/process-lock.sh \
	/lib/multiwan-qos/process-lock.sh 644
stage_file www/cgi-bin/multiwan-qos-agent \
	/www/cgi-bin/multiwan-qos-agent 755

backup_path /etc/multiwan-qos-agent-watchdog.lua
rm -f /etc/multiwan-qos-agent-watchdog.lua

echo "$backup" > /root/multiwan-candidate-last-backup

/etc/init.d/multiwan-nft start
/etc/init.d/multiwan-qos start
stage_complete=1

echo "Candidate staged successfully."
echo "Backup: $backup"
echo "Run: $repo_root/tests/router-release-gate.sh --staged-source"
echo "Rollback: $repo_root/tests/restore-router-candidate.sh $backup"
