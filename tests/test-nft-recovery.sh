#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-recovery.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_set_tracker_oif_rules()/,/^multiwan_nft_delete_iface_rules()/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" | sed '$d')"
LOG() { :; }
FAMILY=ipv4
SOURCE=192.0.2.2
ID=1
NO_IPV6=0
MMX_MASK=0x3f0000
MMX_DEFAULT=0x3f0000
IP4='mock_ip -4'
IP6='mock_ip -6'
IP_FAIL=
config_get() { export "$1=$FAMILY"; }
multiwan_nft_get_iface_id() { export "$1=$ID"; }
multiwan_nft_id2mask() { printf 0x10000; }
multiwan_nft_get_src_ip() { export "$1=$SOURCE"; }
mock_ip() {
    printf '%s\n' "$*" >> "$TEST_ROOT/ip.calls"
    case "$*" in *'rule del '*) return 1 ;; esac
    case "$IP_FAIL:$*" in guard:*' unreachable'|iif:*' iif '*|bypass:*' from '*) return 1 ;; esac
    return 0
}
for FAMILY in ipv4 ipv6; do
    case "$FAMILY" in ipv4) SOURCE=192.0.2.2; flag=-4 ;; *) SOURCE=2001:db8::2; flag=-6 ;; esac
    : > "$TEST_ROOT/ip.calls"
    multiwan_nft_set_tracker_oif_rules wan wan0 || fail 'Valid explicit bypass recovery rule failed'
    grep -qxF -- "$flag rule add pref 3001 fwmark 0x10000/0x3f0000 unreachable" "$TEST_ROOT/ip.calls" || fail 'Failed WAN mark lost isolation'
    grep -qxF -- "$flag rule add pref 1001 iif wan0 lookup 1" "$TEST_ROOT/ip.calls" || fail 'Incoming WAN lookup missing'
    grep -qxF -- "$flag rule add pref 1001 from $SOURCE oif wan0 fwmark 0x3f0000/0x3f0000 lookup 1" "$TEST_ROOT/ip.calls" || fail 'Helper bypass lacks exact source/device/default mark'
    if grep -Eq ' dport | ipproto | to ' "$TEST_ROOT/ip.calls"; then fail 'Recovery incorrectly depends on a resolved target/protocol'; fi
    [ "$(grep -c 'rule add ' "$TEST_ROOT/ip.calls")" -eq 3 ] || fail 'Unexpected broad recovery rule'
done
for IP_FAIL in guard iif bypass; do
    if multiwan_nft_set_tracker_oif_rules wan wan0; then fail "Installation failure was hidden: $IP_FAIL"; fi
done
IP_FAIL=
for SOURCE in '' :: 0.0.0.0; do
    : > "$TEST_ROOT/ip.calls"
    if multiwan_nft_set_tracker_oif_rules wan wan0; then fail 'Missing source accepted'; fi
    grep -qF ' unreachable' "$TEST_ROOT/ip.calls" || fail 'Missing source left failed WAN routable'
    if grep -qF ' from ' "$TEST_ROOT/ip.calls"; then fail 'Missing source installed bypass'; fi
done
ID=
if multiwan_nft_set_tracker_oif_rules unknown wan0; then fail 'Unknown interface accepted'; fi
ID=1
NO_IPV6=1
if multiwan_nft_set_tracker_oif_rules wan wan0; then fail 'Unavailable IPv6 accepted'; fi
eval "$(sed -n '/^multiwan_nft_flush_conntrack()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
config_get() { export "$1=$FLUSH_CONFIG"; }
config_list_foreach() { local value; for value in $FLUSH_CONFIG; do "$3" "$value" "$4"; done; }
multiwan_nft_flush_conntrack_iface() { PURGE_CALLS=$((PURGE_CALLS+1)); return "$PURGE_RESULT"; }
PURGE_RESULT=0
for example in 'always:ifup:1' 'always:connected:0' 'never:ifup:0' 'ifup:ifup:1' 'connected:connected:1' 'connected:ifup:0' 'ifup connected:connected:1' 'ifup ifup:ifup:1' ':ifup:0'; do
    FLUSH_CONFIG=${example%%:*}; remainder=${example#*:}; action=${remainder%%:*}; expected=${remainder##*:}
    PURGE_CALLS=0
    multiwan_nft_flush_conntrack wan "$action" || fail 'Recovery action interpretation failed'
    [ "$PURGE_CALLS" -eq "$expected" ] && [ "$MULTIWAN_NFT_FLUSH_MATCHED" -eq "$expected" ] || fail 'Legacy scalar/list recovery action changed meaning'
done
FLUSH_CONFIG=always PURGE_RESULT=1 PURGE_CALLS=0
if multiwan_nft_flush_conntrack wan ifup; then fail 'Legacy action hid purge failure'; fi
sh "$REPO_ROOT/multiwan-nft/files/etc/uci-defaults/multiwan-nft-migrate-flush_conntrack" || fail 'Compatibility defaults script failed'
printf 'NFT recovery regressions passed: exact helper bypass, incoming lookup, failed-mark isolation, families, legacy actions and failure reporting.\n'
