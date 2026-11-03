#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-route-snapshot.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
CORE="$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
for name in read_route_table route_for_iface get_routes route_command route_key create_iface_route replace_network_set; do
    eval "$(sed -n "/^multiwan_nft_$name()/,/^}/p" "$CORE")"
done
LOG() { :; }
TABLES='220 221'
config_list_foreach() { local table; for table in $TABLES; do "$3" "$table"; done; }
config_get() { export "$1=$FAMILY"; }
config_get_bool() { export "$1=1"; }
config_foreach() { "$1" wan; }
multiwan_nft_get_iface_id() { export "$1=1"; }
multiwan_nft_get_device() { export "$1=wan0"; }
multiwan_nft_update_dev_to_table() { :; }
multiwan_nft_record_owned_table() { :; }
LOOKUP_FAILURE=0
multiwan_nft_route_line_dev() { export "$1="; [ "$LOOKUP_FAILURE" -eq 0 ]; }
multiwan_nft_route_replace_idempotent() { printf 'replace %s\n' "$3" >> "$TEST_ROOT/changes"; }
multiwan_nft_restore_iface_table_default_route() {
    MULTIWAN_NFT_RESTORED_DEFAULT_ROUTES=
    printf 'provider\n' >> "$TEST_ROOT/changes"
    : > "$TEST_ROOT/post"
}
mock_ip() {
    local family="$1" table
    shift
    if [ "$1 $2 $3" = 'route list table' ]; then
        table=$4
        if [ "$table" = 221 ]; then
            printf 'Error: %s: FIB table does not exist.\nDump terminated\n' "$family" >&2
            return 2
        fi
        if [ "$table" = "$FAIL_TABLE" ] || { [ "$table" = 1 ] && [ "$FAIL_MODE" = post ] && [ -f "$TEST_ROOT/post" ]; }; then
            printf '%s\n' "$PARTIAL"
            case "$FAIL_MODE" in
                warning) printf 'Dump was interrupted and may be inconsistent.\n' >&2; return 0 ;;
                truncated) printf 'Message truncated\n' >&2; return 0 ;;
                *) printf 'controlled route inventory failure\n' >&2; return 1 ;;
            esac
        fi
        cat "$TEST_ROOT/$table.$family"
    else
        printf '%s\n' "$*" >> "$TEST_ROOT/changes"
    fi
}
IP4='mock_ip ipv4' IP6='mock_ip ipv6'
NO_IPV6=0 MULTIWAN_NFT_ROUTE_LINE_EXP=p
NFT=mock_nft NFT_FAMILY=inet NFT_TABLE=multiwan_nft
IPv4_REGEX='[0-9.]+' IPv6_REGEX='[0-9a-f:]+'
mock_nft() { printf 'nft\n' >> "$TEST_ROOT/changes"; }
multiwan_nft_nft_write_batch() { printf "$@" >> "$NFT_BATCH_FILE"; }

for FAMILY in ipv4 ipv6; do
    case "$FAMILY" in
        ipv4) ONE='192.0.6.0/24 dev lan0'; TWO='192.0.7.0/24 dev lan0'; EXTRA='192.0.8.0/24 dev lan0'; STALE='192.0.9.0/24 dev lan0'; IP="$IP4" ;;
        ipv6) ONE='2001:db8:6::/64 dev lan0'; TWO='2001:db8:7::/64 dev lan0'; EXTRA='2001:db8:8::/64 dev lan0'; STALE='2001:db8:9::/64 dev lan0'; IP="$IP6" ;;
    esac
    printf '%s\n%s\n' "$ONE" "$TWO" > "$TEST_ROOT/main.$FAMILY"
    printf '%s\n%s\n' "$ONE" "$EXTRA" > "$TEST_ROOT/220.$FAMILY"
    printf '%s\n%s\n%s\n%s\n' "$ONE" "$TWO" "$EXTRA" "$STALE" > "$TEST_ROOT/1.$FAMILY"
    FAIL_TABLE=none FAIL_MODE=none PARTIAL="$ONE"
    routes=$(multiwan_nft_get_routes) || fail 'Complete snapshot rejected absent optional table'
    [ "$(printf '%s\n' "$routes" | wc -l)" -eq 3 ] || fail 'Complete snapshot lost routes or retained duplicates'
    LOOKUP_FAILURE=1
    : > "$TEST_ROOT/changes"
    if multiwan_nft_create_iface_route wan; then fail 'Failed nexthop ownership read accepted for reconciliation'; fi
    [ ! -s "$TEST_ROOT/changes" ] || fail 'Failed nexthop ownership read mutated route state'
    LOOKUP_FAILURE=0
    for FAIL_TABLE in main 220; do
        for FAIL_MODE in error warning truncated; do
            routes=
            if routes=$(multiwan_nft_get_routes); then fail "$FAMILY $FAIL_TABLE $FAIL_MODE snapshot reported success"; fi
            [ -z "$routes" ] || fail 'Failed snapshot exposed partial routes'
            : > "$TEST_ROOT/changes"
            if multiwan_nft_create_iface_route wan; then fail 'Incomplete source snapshot accepted for reconciliation'; fi
            [ ! -s "$TEST_ROOT/changes" ] || fail 'Incomplete source snapshot mutated route state'
            : > "$TEST_ROOT/changes"
            if multiwan_nft_replace_network_set test_set "$FAMILY" main 220; then fail 'Incomplete source snapshot accepted for NFT set'; fi
            [ ! -s "$TEST_ROOT/changes" ] || fail 'Incomplete source snapshot changed NFT set'
        done
    done
    FAIL_TABLE=1 FAIL_MODE=error
    : > "$TEST_ROOT/changes"
    if multiwan_nft_create_iface_route wan; then fail 'Failed owned-table read reported successful reconciliation'; fi
    if grep -q '^route del ' "$TEST_ROOT/changes"; then fail 'Failed owned-table inventory allowed deletion'; fi
    FAIL_TABLE=none FAIL_MODE=post
    rm -f "$TEST_ROOT/post"
    : > "$TEST_ROOT/changes"
    if multiwan_nft_create_iface_route wan; then fail 'Post-restore inventory failure was hidden'; fi
    if grep -q '^route del ' "$TEST_ROOT/changes"; then fail 'Partial post-restore inventory allowed deletion'; fi
    FAIL_MODE=none TABLES=
    : > "$TEST_ROOT/main.$FAMILY"
    : > "$TEST_ROOT/changes"
    multiwan_nft_create_iface_route wan || fail 'Valid empty source snapshot was rejected'
    grep -qF "route del table 1 $EXTRA" "$TEST_ROOT/changes" || fail 'Valid empty sources retained stale routes'
    TABLES='220 221'
done
printf 'NFT snapshot tests passed: complete collection, optional absence, partial/interrupted dumps, owned-table failures and valid empty cleanup.\n'
