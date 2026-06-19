#!/bin/sh
set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

status=0

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	status=1
}

[ -f VERSION ] || {
	fail "missing VERSION file"
	exit "$status"
}

version="$(tr -d ' \t\r\n' < VERSION)"
[ -n "$version" ] || fail "VERSION is empty"

unique_line() {
	file="$1"
	pattern="$2"
	label="$3"

	[ -f "$file" ] || {
		fail "missing file for $label: $file"
		return 1
	}

	count="$(grep -Ec "$pattern" "$file" || true)"
	if [ "$count" -ne 1 ]; then
		fail "expected exactly one $label in $file, found $count"
		return 1
	fi

	grep -E "$pattern" "$file" | tr -d '\r'
}

check_exact() {
	file="$1"
	pattern="$2"
	expected="$3"
	label="$4"

	line="$(unique_line "$file" "$pattern" "$label")" || return 0
	if [ "$line" != "$expected" ]; then
		fail "$label mismatch in $file: expected '$expected', found '$line'"
	fi
}

package_version() {
	file="$1"
	label="$2"

	line="$(unique_line "$file" '^PKG_VERSION:=' "$label PKG_VERSION")" || return 1
	printf '%s\n' "${line#PKG_VERSION:=}"
}

package_release() {
	file="$1"
	label="$2"

	line="$(unique_line "$file" '^PKG_RELEASE:=' "$label PKG_RELEASE")" || return 1
	release="${line#PKG_RELEASE:=}"
	case "$release" in
		''|*[!0-9]*)
			fail "$label PKG_RELEASE must be numeric, found '$release'"
			return 1
			;;
	esac
	printf '%s\n' "$release"
}

nft_version="$(package_version "multiwan-nft/Makefile" "multiwan-nft/Makefile")" || nft_version=""
nft_release="$(package_release "multiwan-nft/Makefile" "multiwan-nft/Makefile")" || nft_release=""
if [ -n "$nft_version" ] && [ -n "$nft_release" ]; then
	check_exact "luci-app-multiwan-nft/Makefile" '^PKG_VERSION:=' "PKG_VERSION:=$nft_version" "luci-app-multiwan-nft/Makefile PKG_VERSION"
	check_exact "luci-app-multiwan-nft/Makefile" '^PKG_RELEASE:=' "PKG_RELEASE:=$nft_release" "luci-app-multiwan-nft/Makefile PKG_RELEASE"
	check_exact "luci-app-multiwan-nft/Makefile" '^PKG_PO_VERSION:=' "PKG_PO_VERSION:=$nft_version-r$nft_release" "luci-app-multiwan-nft/Makefile PKG_PO_VERSION"
fi

qos_version="$(package_version "multiwan-qos/Makefile" "multiwan-qos/Makefile")" || qos_version=""
qos_release="$(package_release "multiwan-qos/Makefile" "multiwan-qos/Makefile")" || qos_release=""
if [ -n "$qos_version" ] && [ -n "$qos_release" ]; then
	check_exact "luci-app-multiwan-qos/Makefile" '^PKG_VERSION:=' "PKG_VERSION:=$qos_version" "luci-app-multiwan-qos/Makefile PKG_VERSION"
	check_exact "luci-app-multiwan-qos/Makefile" '^PKG_RELEASE:=' "PKG_RELEASE:=$qos_release" "luci-app-multiwan-qos/Makefile PKG_RELEASE"
	check_exact "luci-app-multiwan-qos/Makefile" '^PKG_PO_VERSION:=' "PKG_PO_VERSION:=$qos_version-r$qos_release" "luci-app-multiwan-qos/Makefile PKG_PO_VERSION"
fi
check_exact "multiwan-qos/etc/init.d/multiwan-qos" '^VERSION=' "VERSION=\"$qos_version\"" "QoS init VERSION"
check_exact "multiwan-qos/etc/multiwan-qos.sh" '^VERSION=' "VERSION=\"$qos_version\" # will become obsolete in future releases as version string is now in the init script" "QoS rules script VERSION"
check_exact "luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/settings.js" '^const UI_VERSION = ' "const UI_VERSION = '$qos_version';" "QoS LuCI UI_VERSION"

grep -Fqx "## v$version" RELEASE_NOTES.md ||
	fail "RELEASE_NOTES.md is missing the v$version heading"
if grep -Fq 'Release notes pending.' RELEASE_NOTES.md; then
	fail "RELEASE_NOTES.md still contains a pending release-note placeholder"
fi

[ "$status" -eq 0 ] || exit "$status"
printf 'Version sync OK: release %s; nft %s-r%s; qos %s-r%s\n' "$version" "$nft_version" "$nft_release" "$qos_version" "$qos_release"
