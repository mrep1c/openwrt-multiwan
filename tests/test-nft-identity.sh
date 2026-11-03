#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-identity.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
CORE_FILE="$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
for name in stage_conntrack_map import_legacy_conntrack_map guard_retired_marks release_retired_marks flush_legacy_conntrack_marks reconcile_conntrack_map commit_conntrack_map; do
    eval "$(sed -n "/^multiwan_nft_$name()/,/^}/p" "$CORE_FILE")"
done
MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/runtime"
MULTIWAN_NFT_CONNTRACK_MAP="$TEST_ROOT/conntrack-map"
MULTIWAN_NFT_UPGRADE_PENDING="$TEST_ROOT/upgrade-pending"
mkdir "$MULTIWAN_NFT_STATUS_DIR"
MMX_MASK=0x003f0000
NO_IPV6=0
SECTIONS='wan1 wan2 wan6'
ID1=1 ID2=2 ID6=3
ENABLED1=1 FAMILY1=ipv4
PURGE_RESULT=0
NFT=mock_nft
GUARD_PRESENT=0 NFT_FAIL=none LEGACY_RULES=0
LOG() { :; }
mock_nft() {
    case "$1" in
        -n)
            [ "$NFT_FAIL" != legacy-read ] || return 1
            cat "$TEST_ROOT/legacy.rules" ;;
        -f)
            printf 'guard\n' >> "$TEST_ROOT/events"
            cat "$2" > "$TEST_ROOT/guard.nft"
            [ "$NFT_FAIL" != install ] || return 1
            GUARD_PRESENT=1 ;;
        -c)
            printf 'barrier\n' >> "$TEST_ROOT/events"
            [ "$NFT_FAIL" != barrier ] || return 1 ;;
        list)
            [ "$NFT_FAIL" != list ] || return 1
            [ "$LEGACY_RULES" -ne 1 ] || printf 'table inet multiwan_nft\n'
            [ "$GUARD_PRESENT" -ne 1 ] || printf 'table inet multiwan_nft_reconcile\n' ;;
        delete)
            printf 'release\n' >> "$TEST_ROOT/events"
            [ "$NFT_FAIL" != release ] || return 1
            GUARD_PRESENT=0 ;;
        *) fail 'Unexpected nft command' ;;
    esac
    return 0
}
conntrack() {
    [ "$GUARD_PRESENT" -eq 1 ] || fail 'Legacy connections read before the packet guard'
    printf '%s\n' 'udp src=192.0.2.1 mark=131073 use=1' 'udp src=192.0.2.1 mark=131074 use=1' 'tcp src=192.0.2.1 mark=4130053 use=1' 'udp src=192.0.2.1 mark=7 use=1' 'udp src=192.0.2.1 mark=16777280 use=1' 'tcp src=192.0.2.1 mark=4294967295 use=1'
    [ "$PURGE_RESULT" -eq 0 ]
}
config_foreach() { local name; for name in $SECTIONS; do "$1" "$name"; done; }
config_get() {
    case "$2:$3" in
        wan1:enabled) export "$1=$ENABLED1" ;;
        *:enabled) export "$1=1" ;;
        wan1:family) export "$1=$FAMILY1" ;;
        wan6:family) export "$1=ipv6" ;;
        *:family) export "$1=ipv4" ;;
    esac
}
config_get_bool() { config_get "$@"; }
multiwan_nft_get_iface_id() { case "$2" in wan1) export "$1=$ID1" ;; wan2) export "$1=$ID2" ;; wan6) export "$1=$ID6" ;; esac; }
multiwan_nft_flush_conntrack_mark() {
    [ "$GUARD_PRESENT" -eq 1 ] || fail 'Connections purged before the packet guard was installed'
    printf 'purge\n' >> "$TEST_ROOT/events"
    printf '%s %s %s\n' "$1" "$2" "$3" >> "$TEST_ROOT/purged"
    return "$PURGE_RESULT"
}
reset_map() {
    MMX_MASK=0x003f0000
    SECTIONS='wan1 wan2 wan6'
    ID1=1 ID2=2 ID6=3
    ENABLED1=1 FAMILY1=ipv4
    PURGE_RESULT=0
    GUARD_PRESENT=0 NFT_FAIL=none LEGACY_RULES=0
    rm -f "$MULTIWAN_NFT_CONNTRACK_MAP" "$MULTIWAN_NFT_UPGRADE_PENDING" "$TEST_ROOT/purged" "$TEST_ROOT/events" "$TEST_ROOT/guard.nft"
    multiwan_nft_reconcile_conntrack_map || fail 'Initial map failed'
    [ ! -e "$TEST_ROOT/purged" ] || fail 'Initial installation purged unrelated state'
    multiwan_nft_commit_conntrack_map || fail 'Initial map commit failed'
    cp "$MULTIWAN_NFT_CONNTRACK_MAP" "$TEST_ROOT/original"
}
reset_map
multiwan_nft_reconcile_conntrack_map || fail 'Unchanged map failed'
[ ! -e "$TEST_ROOT/purged" ] || fail 'Ordinary restart purged existing sessions'
multiwan_nft_commit_conntrack_map
cmp -s "$MULTIWAN_NFT_CONNTRACK_MAP" "$TEST_ROOT/original" || fail 'Unchanged restart changed the map'
[ ! -e "$TEST_ROOT/events" ] || fail 'Unchanged restart installed a packet guard'
ID1=2 ID2=1
multiwan_nft_reconcile_conntrack_map || fail 'Reordered IDs failed'
[ "$(wc -l < "$TEST_ROOT/purged")" -eq 2 ] || fail 'Reorder purged an unaffected family or special action'
grep -qxF 'ipv4 0x10000 0x003f0000' "$TEST_ROOT/purged" || fail 'Old WAN1 mark was not purged'
grep -qxF 'ipv4 0x20000 0x003f0000' "$TEST_ROOT/purged" || fail 'Old WAN2 mark was not purged'
[ "$(cat "$TEST_ROOT/events")" = "$(printf 'guard\nbarrier\npurge\npurge')" ] || fail 'Purge did not wait for the installed guard'
grep -qF 'meta nfproto ipv4 ct mark and 0x003f0000 == 0x20000' "$TEST_ROOT/guard.nft" || fail 'Guard lost the old family/mask/mark selector'
if grep -qF 'meta nfproto ipv6' "$TEST_ROOT/guard.nft"; then fail 'IPv4 ID changes blocked an unchanged IPv6 WAN'; fi
cmp -s "$MULTIWAN_NFT_CONNTRACK_MAP" "$TEST_ROOT/original" || fail 'Unfinished startup published its map'
multiwan_nft_commit_conntrack_map
[ "$GUARD_PRESENT" -eq 0 ] || fail 'Successful startup left affected WANs blocked'
grep -qxF 'ipv4 wan1 2' "$MULTIWAN_NFT_CONNTRACK_MAP" || fail 'Successful startup did not save new identity'
for change in removed disabled family; do
    reset_map
    case "$change" in removed) SECTIONS='wan2 wan6' ;; disabled) ENABLED1=0 ;; family) FAMILY1=ipv6 ;; esac
    multiwan_nft_reconcile_conntrack_map || fail "$change map failed"
    [ "$(cat "$TEST_ROOT/purged")" = 'ipv4 0x10000 0x003f0000' ] || fail "$change purged an unaffected mark"
done
reset_map
MMX_MASK=0x3f000000
multiwan_nft_reconcile_conntrack_map || fail 'Changed mask failed'
[ "$(wc -l < "$TEST_ROOT/purged")" -eq 9 ] || fail 'Mask change missed old family/interface/special marks'
for family in ipv4 ipv6; do
    for mark in 0x3d0000 0x3e0000 0x3f0000; do
        grep -qxF "$family $mark 0x003f0000" "$TEST_ROOT/purged" || fail 'Old special action retained an incompatible mask'
    done
done
reset_map
ID1=2 ID2=1 PURGE_RESULT=1
if multiwan_nft_reconcile_conntrack_map; then fail 'Startup hid a purge failure'; fi
cmp -s "$MULTIWAN_NFT_CONNTRACK_MAP" "$TEST_ROOT/original" || fail 'Failed purge replaced previous map'
[ "$GUARD_PRESENT" -eq 1 ] || fail 'Failed purge exposed retired marks'
multiwan_nft_release_retired_marks || fail 'Stopped-service guard cleanup failed'
[ "$GUARD_PRESENT" -eq 0 ] || fail 'Stopped-service cleanup retained a packet guard'
for NFT_FAIL in install barrier; do
    failure="$NFT_FAIL"
    reset_map
    ID1=2 ID2=1 NFT_FAIL="$failure"
    if multiwan_nft_reconcile_conntrack_map; then fail 'Guard installation failure was hidden'; fi
    [ ! -e "$TEST_ROOT/purged" ] || fail 'Guard failure purged sessions'
    cmp -s "$MULTIWAN_NFT_CONNTRACK_MAP" "$TEST_ROOT/original" || fail 'Guard failure replaced the saved map'
done
reset_map
ID1=2 ID2=1
multiwan_nft_reconcile_conntrack_map || fail 'Guard release fixture failed'
NFT_FAIL=release
if multiwan_nft_commit_conntrack_map; then fail 'Guard release failure was hidden'; fi
[ "$GUARD_PRESENT" -eq 1 ] || fail 'Guard release failure exposed changed WANs'
grep -qxF 'ipv4 wan1 2' "$MULTIWAN_NFT_CONNTRACK_MAP" || fail 'Committed routing identity was lost after a release failure'
NFT_FAIL=none
multiwan_nft_release_retired_marks || fail 'Guard release could not be retried'
for record in 'bogus wan1 1' 'ipv4 wan1 0' 'ipv4 wan1 08' 'ipv4 wan1 61' 'ipv4 wan1 1 extra'; do
    reset_map
    printf '%s\n%s\n' "$MMX_MASK" "$record" > "$MULTIWAN_NFT_CONNTRACK_MAP"
    if multiwan_nft_reconcile_conntrack_map; then fail 'Malformed saved identity accepted'; fi
    [ ! -e "$TEST_ROOT/purged" ] || fail 'Malformed identity purged connections'
done
reset_map
printf 'invalid mask\n' > "$MULTIWAN_NFT_CONNTRACK_MAP"
if multiwan_nft_reconcile_conntrack_map; then fail 'Malformed saved mask accepted'; fi
[ ! -e "$TEST_ROOT/purged" ] || fail 'Malformed mask purged connections'
reset_map
multiwan_nft_stage_conntrack_map || fail 'Manager identity staging failed'
cp "$MULTIWAN_NFT_STATUS_DIR/conntrack_map_pending" "$TEST_ROOT/manager-pending"
ID1=2 ID2=1
multiwan_nft_stage_conntrack_map "$TEST_ROOT/monitor-map" || fail 'Private monitor identity staging failed'
grep -qxF 'ipv4 wan1 2' "$TEST_ROOT/monitor-map" || fail 'Private map used stale IDs'
cmp -s "$MULTIWAN_NFT_STATUS_DIR/conntrack_map_pending" "$TEST_ROOT/manager-pending" || fail 'Monitor validation overwrote manager staging'
reset_map
rm "$MULTIWAN_NFT_CONNTRACK_MAP"
LEGACY_RULES=1
printf '%s\n' 'meta mark & 0x003f0000 == 0x00020000 ct mark set 0x00020000 comment "ct_save_old"' > "$TEST_ROOT/legacy.rules"
multiwan_nft_reconcile_conntrack_map || fail 'Legacy ownership reconciliation failed'
grep -qxF legacy "$MULTIWAN_NFT_CONNTRACK_MAP" || fail 'Legacy mask was not saved before rebuilding'
[ "$(head -n 1 "$MULTIWAN_NFT_CONNTRACK_MAP")" = 0x003f0000 ] || fail 'Wrong legacy mask recovered'
for family in ipv4 ipv6; do
    grep -qxF "$family 0x00020000 0x003f0000" "$TEST_ROOT/purged" || fail 'Legacy WAN mark survived'
    grep -qxF "$family 0x003f0000 0x003f0000" "$TEST_ROOT/purged" || fail 'Legacy special-action mark survived'
done
[ "$(wc -l < "$TEST_ROOT/purged")" -eq 4 ] || fail 'Legacy migration purged unrelated mark bits'
grep -qF 'ct mark and 0x003f0000 != 0' "$TEST_ROOT/guard.nft" || fail 'Legacy guard allowed an unlisted old mark'
multiwan_nft_commit_conntrack_map || fail 'Legacy map commit failed'
[ "$GUARD_PRESENT" -eq 0 ] || fail 'Legacy migration left routing blocked'
reset_map
rm "$MULTIWAN_NFT_CONNTRACK_MAP"
LEGACY_RULES=1 PURGE_RESULT=1
if multiwan_nft_reconcile_conntrack_map; then fail 'Legacy purge failure was hidden'; fi
grep -qxF legacy "$MULTIWAN_NFT_CONNTRACK_MAP" || fail 'Failed legacy purge lost the recovered mask'
[ "$GUARD_PRESENT" -eq 1 ] || fail 'Failed legacy purge removed protection'
[ ! -e "$TEST_ROOT/purged" ] || fail 'Partial failed conntrack dump permitted deletion'
LEGACY_RULES=0 PURGE_RESULT=0 MMX_MASK=0x3f000000
multiwan_nft_reconcile_conntrack_map || fail 'Legacy retry after mask change failed'
grep -qF 'ct mark and 0x003f0000 != 0' "$TEST_ROOT/guard.nft" || fail 'Legacy retry used the new mask'
for failure in read mixed malformed unrecognized; do
    reset_map
    rm "$MULTIWAN_NFT_CONNTRACK_MAP"
    LEGACY_RULES=1
    case "$failure" in
        read) NFT_FAIL=legacy-read ;;
        mixed) printf '%s\n' 'meta mark & 0x003f0000 == 0x00010000' 'ct mark & 0x3f000000 != 0' > "$TEST_ROOT/legacy.rules" ;;
        malformed) printf '%s\n' 'ct mark & 0x000000ff != 0' > "$TEST_ROOT/legacy.rules" ;;
        unrecognized) printf '%s\n' 'chain multiwan_nft_hook { unexpected layout; }' > "$TEST_ROOT/legacy.rules" ;;
    esac
    if multiwan_nft_reconcile_conntrack_map; then fail "Unknown legacy ownership accepted: $failure"; fi
    [ ! -e "$TEST_ROOT/purged" ] || fail 'Unknown legacy mask purged state'
    [ ! -f "$MULTIWAN_NFT_CONNTRACK_MAP" ] || fail 'Unknown legacy mask was committed'
done
for previous_rules in absent empty marker-directory; do
    reset_map
    rm "$MULTIWAN_NFT_CONNTRACK_MAP"
    if [ "$previous_rules" = marker-directory ]; then mkdir "$MULTIWAN_NFT_UPGRADE_PENDING"; else touch "$MULTIWAN_NFT_UPGRADE_PENDING"; fi
    if [ "$previous_rules" = empty ]; then
        LEGACY_RULES=1
        printf 'table inet multiwan_nft { }\n' > "$TEST_ROOT/legacy.rules"
    fi
    for attempt in 1 2; do
        if multiwan_nft_reconcile_conntrack_map; then fail "Upgrade without ownership accepted: $previous_rules"; fi
        [ -e "$MULTIWAN_NFT_UPGRADE_PENDING" ] || fail 'Failed startup lost upgrade provenance'
        [ ! -e "$MULTIWAN_NFT_CONNTRACK_MAP" ] || fail 'Unknown ownership published a new map'
        [ ! -e "$TEST_ROOT/purged" ] || fail 'Unknown ownership deleted connection state'
        [ "$GUARD_PRESENT" -eq 0 ] || fail 'Unknown ownership blocked unrelated traffic'
    done
    # A reboot removes both this volatile marker and the old kernel connections.
    if [ -d "$MULTIWAN_NFT_UPGRADE_PENDING" ]; then rmdir "$MULTIWAN_NFT_UPGRADE_PENDING"; else rm "$MULTIWAN_NFT_UPGRADE_PENDING"; fi
    multiwan_nft_reconcile_conntrack_map || fail 'Post-reboot initialization failed'
    multiwan_nft_commit_conntrack_map || fail 'Post-reboot map commit failed'
done
reset_map
touch "$MULTIWAN_NFT_UPGRADE_PENDING"
multiwan_nft_reconcile_conntrack_map || fail 'Known modern ownership rejected during upgrade'
multiwan_nft_commit_conntrack_map || fail 'Known modern upgrade could not commit'
[ ! -e "$MULTIWAN_NFT_UPGRADE_PENDING" ] || fail 'Successful upgrade retained the reboot requirement'
reset_map
rm "$MULTIWAN_NFT_CONNTRACK_MAP"
touch "$MULTIWAN_NFT_UPGRADE_PENDING"
LEGACY_RULES=1
printf '%s\n' 'ct mark & 0x003f0000 != 0' > "$TEST_ROOT/legacy.rules"
multiwan_nft_reconcile_conntrack_map || fail 'Known live legacy ownership rejected during upgrade'
NFT_FAIL=release
if multiwan_nft_commit_conntrack_map; then fail 'Upgrade hid guard release failure'; fi
[ -e "$MULTIWAN_NFT_UPGRADE_PENDING" ] || fail 'Failed upgrade commit lost provenance'
NFT_FAIL=none
multiwan_nft_reconcile_conntrack_map || fail 'Known ownership upgrade retry failed'
multiwan_nft_commit_conntrack_map || fail 'Upgrade commit could not be retried'
[ ! -e "$MULTIWAN_NFT_UPGRADE_PENDING" ] || fail 'Successful retry retained upgrade provenance'
printf 'NFT identity tests passed: stable restart, reorder/removal/family/mask changes, scoped purge, unknown-upgrade refusal and failed-start preservation.\n'
