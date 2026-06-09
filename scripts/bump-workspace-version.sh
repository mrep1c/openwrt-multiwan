#!/bin/sh
set -eu

usage() {
	printf 'Usage: %s <version> [release] [notes-file]\n' "$0" >&2
	exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || usage

workspace_root="$(CDPATH= cd "$(dirname "$0")/../.." && pwd)"
combined="${workspace_root}/openwrt-multiwan"
nft="${workspace_root}/openwrt-multiwan-nft"
qos="${workspace_root}/openwrt-multiwan-qos"

run_bump() {
	repo="$1"
	shift
	sh "$repo/scripts/bump-version.sh" "$@"
}

run_bump "$combined" "$@"
[ -d "$nft" ] && run_bump "$nft" "$@"
[ -d "$qos" ] && run_bump "$qos" "$@"

printf 'Workspace package versions updated. Review, test, commit, and push separately.\n'
