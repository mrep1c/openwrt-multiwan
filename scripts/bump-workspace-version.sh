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

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
sh "$repo_root/scripts/bump-version.sh" --component "$component" "$@"

printf 'Combined repository package versions updated. Review, test, commit, and push.\n'
