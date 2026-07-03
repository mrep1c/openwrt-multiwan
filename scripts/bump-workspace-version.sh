#!/bin/sh
set -eu

usage() {
	printf 'Usage: %s [--component all|nft|qos] <version> [release] [notes-file]\n' "$0" >&2
	exit 2
}

component="all"
if [ "${1:-}" = "--component" ]; then
	[ "$#" -ge 3 ] || usage
	component="$2"
	shift 2
fi

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || usage
case "$component" in
	all|nft|qos) ;;
	*) printf 'ERROR: invalid component: %s\n' "$component" >&2; exit 1 ;;
esac

workspace_root="$(CDPATH= cd "$(dirname "$0")/../.." && pwd)"
combined="${workspace_root}/openwrt-multiwan"
nft="${workspace_root}/openwrt-multiwan-nft"
qos="${workspace_root}/openwrt-multiwan-qos"

run_bump() {
	repo="$1"
	shift
	sh "$repo/scripts/bump-version.sh" "$@"
}

run_bump "$combined" --component "$component" "$@"
case "$component" in
	all)
		[ -d "$nft" ] && run_bump "$nft" "$@"
		[ -d "$qos" ] && run_bump "$qos" "$@"
		;;
	nft)
		[ -d "$nft" ] && run_bump "$nft" "$@"
		;;
	qos)
		[ -d "$qos" ] && run_bump "$qos" "$@"
		;;
esac

printf 'Workspace package versions updated. Review, test, commit, and push separately.\n'
