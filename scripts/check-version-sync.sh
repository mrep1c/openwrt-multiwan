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

check_package_makefile() {
	file="$1"
	has_po="$2"

	check_exact "$file" '^PKG_VERSION:=' "PKG_VERSION:=$version" "$file PKG_VERSION"
	release_line="$(unique_line "$file" '^PKG_RELEASE:=' "$file PKG_RELEASE")" || return 0
	release="${release_line#PKG_RELEASE:=}"
	case "$release" in
		''|*[!0-9]*)
			fail "$file PKG_RELEASE must be numeric, found '$release'"
			return 0
			;;
	esac
	if [ "$has_po" = 1 ]; then
		check_exact "$file" '^PKG_PO_VERSION:=' "PKG_PO_VERSION:=$version-r$release" "$file PKG_PO_VERSION"
	fi
}

check_package_makefile "multiwan-nft/Makefile" 0
check_package_makefile "luci-app-multiwan-nft/Makefile" 1
check_package_makefile "multiwan-qos/Makefile" 0
check_package_makefile "luci-app-multiwan-qos/Makefile" 1
check_exact "multiwan-qos/etc/init.d/multiwan-qos" '^VERSION=' "VERSION=\"$version\"" "QoS init VERSION"
check_exact "multiwan-qos/etc/multiwan-qos.sh" '^VERSION=' "VERSION=\"$version\" # will become obsolete in future releases as version string is now in the init script" "QoS rules script VERSION"
check_exact "luci-app-multiwan-qos/htdocs/luci-static/resources/multiwan-qos/settings.js" '^const UI_VERSION = ' "const UI_VERSION = '$version';" "QoS LuCI UI_VERSION"

grep -Fqx "## v$version" RELEASE_NOTES.md ||
	fail "RELEASE_NOTES.md is missing the v$version heading"
if grep -Fq 'Release notes pending.' RELEASE_NOTES.md; then
	fail "RELEASE_NOTES.md still contains a pending release-note placeholder"
fi

[ "$status" -eq 0 ] || exit "$status"
printf 'Version sync OK: %s\n' "$version"
