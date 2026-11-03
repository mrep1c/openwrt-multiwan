#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_route_line_dev()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
eval "$(sed -n '/^multiwan_nft_route_key()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
eval "$(sed -n '/^multiwan_nft_read_route_table()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
eval "$(sed -n '/^multiwan_nft_route_replace_idempotent()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh")"
LOG() { :; }
multiwan_nft_dev_tbl_ipv4=' eth0=1 eth1=2 '
multiwan_nft_dev_tbl_ipv6=' eth0=3 eth1=4 '
IP4='mock_ip ipv4' IP6='mock_ip ipv6'
LOOKUP_FAILURE=0
mock_ip() {
    [ "$1" = "$family" ] && [ "$2 $3 $4 $5" = 'nexthop get id 81' ] || return 99
    [ "$LOOKUP_FAILURE" -eq 0 ] || return 1
    printf 'id 81 via 192.0.2.2 dev eth1 scope link\n'
}
for family in ipv4 ipv6; do
    case "$family" in ipv4) expected=2 ;; ipv6) expected=4 ;; esac
    for route in 'default nhid 81' 'default nhid 81 metric 99'; do
        selected=stale
        multiwan_nft_route_line_dev selected "$route" "$family" || fail 'ID-only lookup failed'
        [ "$selected" = "$expected" ] || fail 'Nexthop device selected the wrong WAN/family'
    done
    LOOKUP_FAILURE=1
    multiwan_nft_route_line_dev selected 'default nhid 81 via 192.0.2.2 dev eth1' "$family" || fail 'Expanded route queried an unnecessary nexthop'
    [ "$selected" = "$expected" ] || fail 'Expanded route lost its WAN'
    if multiwan_nft_route_line_dev selected 'default nhid 81' "$family"; then fail 'Failed nexthop read reported success'; fi
    [ -z "${selected:-}" ] || fail 'Failed lookup retained a stale WAN'
    multiwan_nft_route_line_dev selected '192.0.2.0/24 dev lan0' "$family" || fail 'Unmapped LAN device failed'
    [ -z "${selected:-}" ] || fail 'LAN route acquired a WAN owner'
    multiwan_nft_route_line_dev selected 'blackhole 192.0.2.0/24' "$family" || fail 'Device-free non-nexthop route failed'
    LOOKUP_FAILURE=0
done
dump_ip() {
    printf 'default nhid 94 metric 99\n\tnexthop via 192.0.2.2 dev eth0 weight 2\n\tnexthop via 198.51.100.2 dev eth1 weight 1\n'
    printf '198.18.1.0/24 metric 50\n\tnexthop via 192.0.2.2 dev eth0 weight 2\n\tnexthop via 198.51.100.2 dev eth1 weight 1\n'
    printf '198.18.2.0/24 nhid 81 via 198.51.100.2 dev eth1 metric 99\n'
}
routes=$(multiwan_nft_read_route_table dump_ip main) || fail 'Multipath dump rejected'
[ "$(printf '%s\n' "$routes" | wc -l)" -eq 3 ] || fail 'Multipath continuations became separate routes'
printf '%s\n' "$routes" | grep -qxF 'default nhid 94 metric 99' || fail 'Group dump retained its redundant expansion'
printf '%s\n' "$routes" | grep -qxF '198.18.2.0/24 nhid 81 metric 99' || fail 'Single-object identity depends on expanded dump mode'
one='default metric 99 nexthop via 192.0.2.2 dev eth0 weight 2'
flat='default via 192.0.2.2 dev eth0 metric 99'
[ "$(multiwan_nft_route_key "$one")" = "$(multiwan_nft_route_key "$flat")" ] || fail 'Kernel flattening caused valid route deletion'
for different in 'default via 192.0.2.3 dev eth0 metric 99' 'default via 192.0.2.2 dev eth0 metric 100'; do
    [ "$(multiwan_nft_route_key "$one")" != "$(multiwan_nft_route_key "$different")" ] || fail 'Route identity lost gateway or metric'
done
multi="$one nexthop via 198.51.100.2 dev eth1 weight 3"
[ "$(multiwan_nft_route_key "$multi")" = "$multi" ] || fail 'Multipath identity lost relative weights'
multiwan_nft_route_command() { echo 'FAIL: unchanged route was replaced'; return 1; }
multiwan_nft_route_replace_idempotent dump_ip 2 'default nhid 94 metric 99' || fail 'Unchanged object group was replaced'
dump_flat_ip() { printf '%s \n' "$flat"; }
multiwan_nft_route_replace_idempotent dump_flat_ip 2 "$one" || fail 'Kernel flattening caused repeated route replacement'
printf 'NFT nexthop tests passed: WAN ownership, lookup failure, complete groups and canonical route identity.\n'
