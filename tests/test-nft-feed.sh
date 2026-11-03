#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-feed.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(tr -d '\r' < "$REPO_ROOT/setup-feed.sh" | sed '/^case "$MODE" in/,$d')"
openwrt_release() { printf '%s\n' "$TEST_RELEASE"; }
apk() { case "$1" in --print-arch) printf '%s\n' "$TEST_ARCH" ;; update) : ;; *) fail 'Unexpected APK mutation' ;; esac; }
fetch_file() { printf '%s\n' "$1" >> "$TEST_ROOT/fetch"; printf 'test key\n' > "$2"; }
remove_apk_feed_entries() { : > "$APK_FEEDS_FILE"; }
APK_KEY_FILE="$TEST_ROOT/key"
APK_FEEDS_FILE="$TEST_ROOT/feeds"
TEST_RELEASE=25.12.6
for TEST_ARCH in aarch64_generic arm_cortex-a7_neon-vfpv4 mipsel_24kc; do
    APK_RELEASE_TAG= APK_KEY_URL= APK_FEED_URL=
    apk_setup_feed > "$TEST_ROOT/output"
    grep -qxF "$RELEASE_BASE/apk-25.12-$TEST_ARCH/packages.adb" "$APK_FEEDS_FILE" || fail 'Feed architecture mismatch'
    grep -qxF "$RELEASE_BASE/apk-25.12-$TEST_ARCH/mrep1c-openwrt-multiwan-apk.pem" "$TEST_ROOT/fetch" || fail 'Signing key architecture mismatch'
done
APK_RELEASE_TAG= APK_KEY_URL= APK_FEED_URL=
TEST_ARCH=unsupported
if apk_setup_feed > /dev/null 2>&1; then fail 'Unsupported CPU selected a foreign feed'; fi
TEST_ARCH=aarch64_generic
TEST_RELEASE=24.10.8
if apk_setup_feed > /dev/null 2>&1; then fail 'Old release silently selected a new ABI feed'; fi
APK_FEED_URL=https://example.invalid/custom/packages.adb
APK_KEY_URL=https://example.invalid/custom/key
apk_setup_feed > "$TEST_ROOT/output"
grep -qxF https://example.invalid/custom/packages.adb "$APK_FEEDS_FILE" || fail 'Explicit feed override was lost'
printf 'NFT feed selection tests passed. Only temporary files were changed.\n'
