#!/bin/sh

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-policy.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
eval "$(sed '1,5d' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
LOG() { printf '%s\n' "$*" >> "$TEST_ROOT/log"; }
MMX_MASK=0x3f0000
MMX_INVMASK=0xffc0ffff
MMX_DEFAULT=0x3f0000
MMX_BLACKHOLE=0x3d0000
MMX_UNREACHABLE=0x3e0000
NO_IPV6=0
NFT_BATCH_FILE=
NFT=nft_mock
MEMBERS='m1 m2 m3 m6'
M1_METRIC=001
M1_WEIGHT=0001
M2_METRIC=1
M2_WEIGHT=2
M3_METRIC=2
M3_WEIGHT=4
M6_METRIC=9
M6_WEIGHT=5
STATE1=online
STATE2=online
STATE3=online
STATE6=online
ENABLED1=1
ENABLED2=1
ENABLED3=1
ENABLED6=1
LAST_RESORT=unreachable
config_get() {
    local value
    case "$2:$3" in
        m1:interface|duplicate:interface) value=wan1 ;;
        m2:interface) value=wan2 ;;
        m3:interface) value=wan3 ;;
        m6:interface) value=wan6 ;;
        m1:metric) value=$M1_METRIC ;; m1:weight) value=$M1_WEIGHT ;;
        m2:metric) value=$M2_METRIC ;; m2:weight) value=$M2_WEIGHT ;;
        m3:metric) value=$M3_METRIC ;; m3:weight) value=$M3_WEIGHT ;;
        m6:metric) value=$M6_METRIC ;; m6:weight) value=$M6_WEIGHT ;;
        duplicate:metric) value=1 ;; duplicate:weight) value=3 ;;
        wan6:family) value=ipv6 ;;
        wan1:family|wan2:family|wan3:family) value=ipv4 ;;
        balanced:last_resort) value=$LAST_RESORT ;;
        *) value= ;;
    esac
    export "$1=${value:-${4:-}}"
}
config_get_bool() {
    case "$2:$3" in
        wan1:enabled) export "$1=$ENABLED1" ;; wan2:enabled) export "$1=$ENABLED2" ;;
        wan3:enabled) export "$1=$ENABLED3" ;; wan6:enabled) export "$1=$ENABLED6" ;;
        *) export "$1=${4:-0}" ;;
    esac
}
HAS_POLICY=1
config_foreach() { [ "$2" != policy ] || [ "$HAS_POLICY" -eq 0 ] || "$1" balanced; }
config_list_foreach() {
    local callback="$3" member
    if [ "$1:$2" = balanced:use_member ]; then
        for member in $MEMBERS; do "$callback" "$member"; done
    fi
    return 0
}
network_get_device() { export "$1=eth-$2"; }
multiwan_nft_get_iface_id() {
    case "$2" in wan1) export "$1=1" ;; wan2) export "$1=2" ;; wan3) export "$1=3" ;; wan6) export "$1=4" ;; *) export "$1=" ;; esac
}
multiwan_nft_get_iface_hotplug_state() {
    case "$1" in wan1) printf '%s\n' "$STATE1" ;; wan2) printf '%s\n' "$STATE2" ;; wan3) printf '%s\n' "$STATE3" ;; wan6) printf '%s\n' "$STATE6" ;; esac
}
CHECK_FAIL=0
APPLY_FAIL=0
TABLE_EXISTS=1
OBJECTS_EXIST=1
nft_mock() {
    printf '%s\n' "$*" >> "$TEST_ROOT/nft.calls"
    case "$*" in
        'list table inet multiwan_nft') [ "$TABLE_EXISTS" -eq 1 ] ;;
        'list chain inet multiwan_nft '*|'list set inet multiwan_nft '*) [ "$OBJECTS_EXIST" -eq 1 ] ;;
        '-c -f '*) cp "$3" "$TEST_ROOT/checked"; [ "$CHECK_FAIL" -eq 0 ] ;;
        '-f '*)
            [ "$APPLY_FAIL" -eq 0 ] || return 1
            cp "$2" "$TEST_ROOT/live"
            ;;
        *) fail "Policy update escaped transaction: $*" ;;
    esac
}
apply_policy() {
    : > "$TEST_ROOT/nft.calls"
    multiwan_nft_set_policies_nft || fail 'Policy transaction failed'
    [ -z "$NFT_BATCH_FILE" ] || fail 'Policy batch context leaked'
    cmp -s "$TEST_ROOT/checked" "$TEST_ROOT/live" || fail 'Applied batch differs from checked batch'
}
require_line() { grep -qF "$1" "$TEST_ROOT/live" || fail "Missing policy command: $1"; }
reject_line() { if grep -qF "$1" "$TEST_ROOT/live"; then fail "Unexpected policy command: $1"; fi; }

apply_policy
require_line 'flush chain inet multiwan_nft multiwan_nft_policy_balanced'
require_line 'flush set inet multiwan_nft multiwan_nft_policy_balanced_members_ipv4'
require_line 'flush set inet multiwan_nft multiwan_nft_policy_balanced_members_ipv6'
require_line 'comment "wan1 1 3"'
require_line 'comment "wan2 2 3"'
require_line 'numgen random mod 3 lt 2'
require_line 'comment "wan6 5 5"'
reject_line 'comment "wan3 '
reject_line '001'
reject_line '0001'
require_line 'add element inet multiwan_nft multiwan_nft_policy_balanced_members_ipv4 { 0x10000 }'
require_line 'add element inet multiwan_nft multiwan_nft_policy_balanced_members_ipv6 { 0x40000 }'
reject_line 'multiwan_nft_policy_balanced_members_ipv4 { 0x30000 }'

ENABLED2=0
apply_policy
require_line 'comment "wan1 1 1"'
reject_line 'comment "wan2 '
reject_line 'multiwan_nft_policy_balanced_members_ipv4 { 0x20000 }'
ENABLED2=1
STATE1=offline
STATE2=offline
apply_policy
require_line 'comment "wan3 4 4"'
reject_line 'comment "wan1 '
reject_line 'comment "wan2 '
STATE1=online
STATE2=online

MEMBERS='m1 duplicate m2'
apply_policy
require_line 'numgen random mod 4 lt 3'
require_line 'numgen random mod 6 lt 2'
require_line 'comment "wan1 1 6"'
require_line 'comment "wan1 3 6"'
require_line 'comment "wan2 2 6"'

MEMBERS=m1
M1_METRIC=000256
M1_WEIGHT=001000
apply_policy
require_line 'comment "wan1 1000 1000"'
M1_METRIC=001
M1_WEIGHT=0001
MEMBERS=
for LAST_RESORT in unreachable default blackhole; do
    apply_policy
    require_line "comment \"$LAST_RESORT\""
    reject_line 'add element '
done
LAST_RESORT=unreachable
MEMBERS='m1 m6'
NO_IPV6=1
apply_policy
reject_line 'members_ipv6'
reject_line 'comment "wan6 '
NO_IPV6=0
OBJECTS_EXIST=0
apply_policy
require_line 'add chain inet multiwan_nft multiwan_nft_policy_balanced'
require_line 'add set inet multiwan_nft multiwan_nft_policy_balanced_members_ipv4 { type mark;'
OBJECTS_EXIST=1

cp "$TEST_ROOT/live" "$TEST_ROOT/saved-live"
for M1_METRIC in 0 257 -1 1:2 bogus 123456789012345678901234567890; do
    if multiwan_nft_set_policies_nft; then fail "Invalid metric accepted: $M1_METRIC"; fi
    cmp -s "$TEST_ROOT/live" "$TEST_ROOT/saved-live" || fail 'Invalid metric changed live policy or eligibility'
done
M1_METRIC=1
for M1_WEIGHT in 0 1001 -1 1:2 bogus 123456789012345678901234567890; do
    if multiwan_nft_set_policies_nft; then fail "Invalid weight accepted: $M1_WEIGHT"; fi
    cmp -s "$TEST_ROOT/live" "$TEST_ROOT/saved-live" || fail 'Invalid weight changed live policy or eligibility'
done
M1_WEIGHT=1
for failure in check apply table; do
    CHECK_FAIL=0; APPLY_FAIL=0; TABLE_EXISTS=1
    case "$failure" in check) CHECK_FAIL=1 ;; apply) APPLY_FAIL=1 ;; table) TABLE_EXISTS=0 ;; esac
    if multiwan_nft_set_policies_nft; then fail "Policy $failure failure was hidden"; fi
    cmp -s "$TEST_ROOT/live" "$TEST_ROOT/saved-live" || fail "Policy $failure failure changed live policy or eligibility"
    [ -z "$NFT_BATCH_FILE" ] || fail 'Failed transaction leaked policy batch context'
done

HAS_POLICY=0
CHECK_FAIL=0; APPLY_FAIL=0; TABLE_EXISTS=1
multiwan_nft_set_policies_nft || fail 'Empty starter configuration should not fail startup'
printf 'NFT policy tests passed: validated members, family tiers, disabled/stale interfaces, cumulative weights and transactional failures.\n'
