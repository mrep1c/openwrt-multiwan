#!/bin/sh

set -u
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-cleanup.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || fail 'Python 3 is required by the JSON fixture adapter'
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
CORE_FILE="$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
eval "$(sed -n '/^multiwan_nft_delete_iface_set_entries()/,/^}/p' "$CORE_FILE")"
eval "$(sed -n '/^multiwan_nft_flush_conntrack_iface()/,/^}/p' "$CORE_FILE")"
eval "$(sed -n '/^multiwan_nft_flush_conntrack_mark()/,/^}/p' "$CORE_FILE")"
LOG() { :; }
NFT=nft_mock
MMX_MASK=0x3f0000
INTERFACE_ID=1
multiwan_nft_get_iface_id() { export "$1=$INTERFACE_ID"; }

# Translate real JSON fixtures into jshn-style shell nodes; the product traverses them.
cat > "$TEST_ROOT/json-fixture.py" <<'PY'
import json
import shlex
import sys
sequence = 0
def emit(value, parent=''):
    global sequence
    node = 'N' + str(sequence)
    sequence += 1
    pairs = list(enumerate(value, 1)) if isinstance(value, list) else list(value.items())
    print('JSON_PARENT_' + node + '=' + shlex.quote(parent))
    print('JSON_KEYS_' + node + '=' + shlex.quote(' '.join(str(key) for key, _ in pairs)))
    for key, item in pairs:
        kind = 'array' if isinstance(item, list) else 'object' if isinstance(item, dict) else 'int' if isinstance(item, int) else 'string'
        output = emit(item, node) if isinstance(item, (list, dict)) else item
        print('JSON_TYPE_' + node + '_' + str(key) + '=' + shlex.quote(kind))
        print('JSON_VALUE_' + node + '_' + str(key) + '=' + shlex.quote(str(output)))
    return node
print('JSON_CUR=' + emit(json.loads(sys.argv[1])))
PY
json_load() {
    local variables
    variables="$(python3 "$TEST_ROOT/json-fixture.py" "$1" 2>/dev/null)" || return 1
    eval "$variables"
}
json_select() {
    local kind next
    if [ "$1" = .. ]; then
        eval "JSON_CUR=\${JSON_PARENT_$JSON_CUR}"
        return 0
    fi
    eval "kind=\${JSON_TYPE_${JSON_CUR}_$1:-}"
    case "$kind" in object|array) ;; *) return 1 ;; esac
    eval "next=\${JSON_VALUE_${JSON_CUR}_$1}"
    JSON_CUR=$next
}
json_get_keys() {
    local value
    eval "value=\${JSON_KEYS_$JSON_CUR:-}"
    export "$1=$value"
}
json_get_var() {
    local value
    eval "value=\${JSON_VALUE_${JSON_CUR}_$2:-}"
    export "$1=$value"
}
cat > "$TEST_ROOT/set4.json" <<'EOF'
{"nftables":[{"metainfo":{"json_schema_version":1}},{"set":{"family":"inet","table":"multiwan_nft","name":"multiwan_nft_sticky_ipv4_test","type":["ipv4_addr","mark"],"flags":["timeout"],"timeout":600,"elem":[{"elem":{"val":{"concat":["192.0.2.10",65536]},"timeout":600,"expires":599}},{"elem":{"val":{"concat":["192.0.2.20",131072]},"timeout":600,"expires":599}}]}}]}
EOF
cat > "$TEST_ROOT/set6.json" <<'EOF'
{"nftables":[{"metainfo":{"json_schema_version":1}},{"set":{"family":"inet","table":"multiwan_nft","name":"multiwan_nft_sticky_ipv6_test","type":["ipv6_addr","mark"],"flags":["timeout"],"timeout":600,"elem":[{"elem":{"val":{"concat":["2001:db8::10","0x10000"]},"timeout":600,"expires":599}},{"elem":{"val":{"concat":["2001:db8::20",131072]},"timeout":600,"expires":599}}]}}]}
EOF
SETS_MODE=populated
NFT_READ_FAIL=0
NFT_CHECK_FAIL=0
NFT_APPLY_FAIL=0
nft_mock() {
    printf '%s\n' "$*" >> "$TEST_ROOT/nft.calls"
    case "$*" in
        'list table inet multiwan_nft')
            [ "$SETS_MODE" != absent ] || return 0
            printf 'set multiwan_nft_sticky_ipv4_test {\nset multiwan_nft_sticky_ipv6_test {\n'
            ;;
        '-j list set inet multiwan_nft multiwan_nft_sticky_ipv4_test'|'-j list set inet multiwan_nft multiwan_nft_sticky_ipv6_test')
            [ "$NFT_READ_FAIL" -eq 0 ] || return 1
            if [ "$SETS_MODE" = malformed ]; then printf 'not JSON\n'; return; fi
            if [ "$SETS_MODE" = empty ]; then printf '{"nftables":[{"set":{"name":"%s","elem":[]}}]}\n' "$6"; return; fi
            case "$6" in *ipv4*) cat "$TEST_ROOT/set4.json" ;; *) cat "$TEST_ROOT/set6.json" ;; esac
            ;;
        '-c -f '*) printf '%s\n' "$3" > "$TEST_ROOT/batch.path"; [ "$NFT_CHECK_FAIL" -eq 0 ] ;;
        '-f '*)
            [ "$NFT_APPLY_FAIL" -eq 0 ] || return 1
            cat "$2" >> "$TEST_ROOT/applied"
            ;;
        *) fail "Unexpected nft command: $*" ;;
    esac
}

multiwan_nft_delete_iface_set_entries wan || fail 'Scoped sticky cleanup failed'
[ "$MULTIWAN_NFT_STICKY_DELETED" -eq 2 ] || fail 'Cleanup did not select one entry per family'
grep -qF 'multiwan_nft_sticky_ipv4_test { 192.0.2.10 . 0x00010000 }' "$TEST_ROOT/applied" || fail 'IPv4 exact key missing'
grep -qF 'multiwan_nft_sticky_ipv6_test { 2001:db8::10 . 0x00010000 }' "$TEST_ROOT/applied" || fail 'IPv6 exact key missing'
if grep -Eq '192\.0\.2\.20|2001:db8::20|timeout|expires' "$TEST_ROOT/applied"; then fail 'Cleanup selected another WAN or expiry metadata'; fi
[ ! -e "$(cat "$TEST_ROOT/batch.path")" ] || fail 'Cleanup leaked its batch file'

for SETS_MODE in absent empty; do
    : > "$TEST_ROOT/nft.calls"
    rm -f "$TEST_ROOT/applied"
    multiwan_nft_delete_iface_set_entries wan || fail 'Empty sticky cleanup failed'
    [ "$MULTIWAN_NFT_STICKY_DELETED" -eq 0 ] || fail 'Empty cleanup reported deletions'
    [ ! -e "$TEST_ROOT/applied" ] || fail 'Empty cleanup submitted a deletion batch'
done
SETS_MODE=populated
for failure in read check apply malformed; do
    NFT_READ_FAIL=0; NFT_CHECK_FAIL=0; NFT_APPLY_FAIL=0
    rm -f "$TEST_ROOT/applied"
    case "$failure" in
        read) NFT_READ_FAIL=1 ;;
        check) NFT_CHECK_FAIL=1 ;;
        apply) NFT_APPLY_FAIL=1 ;;
        malformed) SETS_MODE=malformed ;;
    esac
    if multiwan_nft_delete_iface_set_entries wan; then fail "Sticky $failure failure was hidden"; fi
    [ ! -e "$TEST_ROOT/applied" ] || fail "Sticky $failure failure submitted deletions"
done
SETS_MODE=populated
NFT_READ_FAIL=0; NFT_CHECK_FAIL=0; NFT_APPLY_FAIL=0
INTERFACE_ID=
: > "$TEST_ROOT/nft.calls"
multiwan_nft_delete_iface_set_entries unknown || fail 'Unknown interface cleanup failed'
[ ! -s "$TEST_ROOT/nft.calls" ] || fail 'Unknown interface queried nft'
INTERFACE_ID=1

PURGE_FAMILY=ipv4
config_get() { case "$3" in family) export "$1=$PURGE_FAMILY" ;; *) export "$1=${4:-}" ;; esac; }
CONNTRACK_MODE=populated
cat > "$TEST_ROOT/conntrack-fixture.py" <<'PY'
import pathlib
import sys
root, action, family, selector, mode = sys.argv[1:]
root = pathlib.Path(root)
rows = [line.split() for line in (root / 'conntrack.db').read_text().splitlines()]
mark, mask = (int(value, 0) for value in selector.split('/'))
selected = [row for row in rows if row[0] == family and int(row[2]) & mask == mark & mask]
def render(row):
    return f'{row[1]} 0 30 src=fixture dst=fixture mark={row[2]} id={row[3]}'
if action == '-L':
    if mode == 'read-fail' or mode == 'relist-fail' and (root / 'conntrack.delete-attempt').exists():
        raise SystemExit(1)
    for row in selected:
        print(render(row))
elif action == '-D':
    (root / 'conntrack.delete-attempt').touch()
    if mode == 'delete-fail':
        raise SystemExit(1)
    deleted = [] if mode == 'expired' else selected[:1] if mode in ('partial-fail', 'relist-fail') else selected
    removed = selected if mode == 'expired' else deleted
    if deleted:
        with (root / 'conntrack.deleted').open('a') as output:
            for row in deleted:
                output.write(' '.join(row) + '\n')
                print(render(row))
    (root / 'conntrack.db').write_text(''.join(' '.join(row) + '\n' for row in rows if row not in removed))
    if mode in ('partial-fail', 'relist-fail', 'expired'):
        raise SystemExit(1)
else:
    raise AssertionError(action)
PY
reset_conntracks() {
    cat > "$TEST_ROOT/conntrack.db" <<'EOF'
ipv4 tcp 65582 v4-tcp
ipv4 udp 65546 v4-udp
ipv4 icmp 65536 v4-icmp
ipv4 esp 65735 v4-esp
ipv4 udp 131118 v4-other-wan
ipv6 tcp 65582 v6-tcp
ipv6 udp 65546 v6-udp
ipv6 icmpv6 65536 v6-icmp
ipv6 esp 65735 v6-esp
ipv6 udp 131118 v6-other-wan
EOF
    : > "$TEST_ROOT/conntrack.calls"
    rm -f "$TEST_ROOT/conntrack.deleted" "$TEST_ROOT/conntrack.delete-attempt"
}
conntrack() {
    printf '%s\n' "$*" >> "$TEST_ROOT/conntrack.calls"
    local action="$1" family= mark=
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f) family="$2"; shift ;;
            -m) mark="$2"; shift ;;
            -p) fail 'Failed-WAN purge must include every tracked protocol' ;;
            *) fail "Unexpected conntrack option: $1" ;;
        esac
        shift
    done
    [ "$family" = "$PURGE_FAMILY" ] || fail 'Conntrack used the wrong family'
    [ "$mark" = '0x10000/0x3f0000' ] || fail 'Conntrack deletion was not scoped by routing mask'
    python3 "$TEST_ROOT/conntrack-fixture.py" "$TEST_ROOT" "$action" "$family" "$mark" "$CONNTRACK_MODE"
}
for PURGE_FAMILY in ipv4 ipv6; do
    reset_conntracks
    multiwan_nft_flush_conntrack_iface wan || fail "$PURGE_FAMILY scoped purge failed"
    [ "$MULTIWAN_NFT_CONNTRACK_PURGED" -eq 4 ] || fail "$PURGE_FAMILY purge count wrong"
    [ "$(wc -l < "$TEST_ROOT/conntrack.deleted")" -eq 4 ] || fail "$PURGE_FAMILY purge missed a protocol"
    [ "$(wc -l < "$TEST_ROOT/conntrack.db")" -eq 6 ] || fail 'Purge altered another family or WAN'
    for protocol in tcp udp esp; do grep -q "^$PURGE_FAMILY $protocol " "$TEST_ROOT/conntrack.deleted" || fail "Purge missed $protocol"; done
    grep -Eq "^$PURGE_FAMILY icmp(v6)? " "$TEST_ROOT/conntrack.deleted" || fail 'Purge missed ICMP'
    grep -qF 'v4-other-wan' "$TEST_ROOT/conntrack.db" || fail 'Purge removed another IPv4 WAN'
    grep -qF 'v6-other-wan' "$TEST_ROOT/conntrack.db" || fail 'Purge removed another IPv6 WAN'
    if grep -q 'other-wan' "$TEST_ROOT/conntrack.deleted"; then fail 'Another WAN was selected'; fi
done
reset_conntracks
grep -v '^ipv6 .* 65[0-9]* ' "$TEST_ROOT/conntrack.db" > "$TEST_ROOT/empty.db"
mv "$TEST_ROOT/empty.db" "$TEST_ROOT/conntrack.db"
: > "$TEST_ROOT/conntrack.calls"
multiwan_nft_flush_conntrack_iface wan || fail 'Empty conntrack purge failed'
[ "$MULTIWAN_NFT_CONNTRACK_PURGED" -eq 0 ] || fail 'Empty conntrack purge reported deletions'
[ ! -e "$TEST_ROOT/conntrack.deleted" ] || fail 'Empty conntrack purge called deletion'
for CONNTRACK_MODE in read-fail delete-fail partial-fail relist-fail; do
    reset_conntracks
    cp "$TEST_ROOT/conntrack.db" "$TEST_ROOT/saved.db"
    if multiwan_nft_flush_conntrack_iface wan; then fail "$CONNTRACK_MODE was hidden"; fi
    [ "$MULTIWAN_NFT_CONNTRACK_PURGED" -lt 4 ] || fail 'Failed deletion reported every session purged'
    grep -qF 'v4-other-wan' "$TEST_ROOT/conntrack.db" || fail 'Failed purge removed another IPv4 WAN'
    grep -qF 'v6-other-wan' "$TEST_ROOT/conntrack.db" || fail 'Failed purge removed another IPv6 WAN'
    case "$CONNTRACK_MODE" in
        partial-fail|relist-fail)
            [ "$MULTIWAN_NFT_CONNTRACK_PURGED" -eq 1 ] || fail 'Actual partial deletion count was lost'
            [ "$(wc -l < "$TEST_ROOT/conntrack.deleted")" -eq 1 ] || fail 'Partial deletion fixture did not execute'
            ;;
        *) cmp -s "$TEST_ROOT/conntrack.db" "$TEST_ROOT/saved.db" || fail 'Failed enumeration/deletion changed fixture sessions' ;;
    esac
done
reset_conntracks
CONNTRACK_MODE=expired
multiwan_nft_flush_conntrack_iface wan || fail 'Already-expired sessions caused a false purge failure'
[ "$MULTIWAN_NFT_CONNTRACK_PURGED" -eq 0 ] || fail 'Expired sessions were reported as deleted'
[ "$(wc -l < "$TEST_ROOT/conntrack.db")" -eq 6 ] || fail 'Expiry race affected other WAN or family'
PURGE_FAMILY=invalid
: > "$TEST_ROOT/conntrack.calls"
if multiwan_nft_flush_conntrack_iface wan; then fail 'Unknown conntrack family accepted'; fi
[ ! -s "$TEST_ROOT/conntrack.calls" ] || fail 'Invalid family queried conntrack'
PURGE_FAMILY=ipv6
INTERFACE_ID=
: > "$TEST_ROOT/conntrack.calls"
MULTIWAN_NFT_CONNTRACK_PURGED=99
multiwan_nft_flush_conntrack_iface unknown || fail 'Unknown interface purge failed'
[ "$MULTIWAN_NFT_CONNTRACK_PURGED" -eq 0 ] || fail 'Unknown interface retained stale purge count'
[ ! -s "$TEST_ROOT/conntrack.calls" ] || fail 'Unknown interface queried conntrack'

printf 'NFT cleanup tests passed. nftables, conntrack and JSON inputs used controlled fixtures.\n'
