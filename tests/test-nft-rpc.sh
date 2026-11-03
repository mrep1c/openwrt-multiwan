#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-rpc.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || fail 'Python 3 is required by the JSON fixture adapter'

# Model jshn's shell interface with a real JSON parser; product parsing stays intact.
cat > "$TEST_ROOT/rpc-json-fixture.py" <<'PY'
import json
import shlex
import sys

mode, data, *rest = sys.argv[1:]
if mode == 'read':
    sequence = 0
    def emit(value, parent=''):
        global sequence
        name = 'N' + str(sequence)
        sequence += 1
        pairs = list(enumerate(value, 1)) if isinstance(value, list) else list(value.items())
        print('JSON_PARENT_' + name + '=' + shlex.quote(parent))
        print('JSON_KEYS_' + name + '=' + shlex.quote(' '.join(str(key) for key, _ in pairs)))
        for key, item in pairs:
            kind = 'array' if isinstance(item, list) else 'object' if isinstance(item, dict) else 'boolean' if isinstance(item, bool) else 'int' if isinstance(item, int) else 'string'
            output = emit(item, name) if isinstance(item, (list, dict)) else item
            print('JSON_TYPE_' + name + '_' + str(key) + '=' + shlex.quote(kind))
            print('JSON_VALUE_' + name + '_' + str(key) + '=' + shlex.quote('' if output is None else str(output)))
        return name
    print('JSON_CUR=' + emit(json.loads(data)))
elif mode == 'write':
    with open(data) as stream:
        events = stream.read().split('\0')
    root = {}
    stack = [root]
    for index in range(0, len(events) - 2, 3):
        kind, key, value = events[index:index + 3]
        if kind == 'close':
            stack.pop()
            continue
        item = {} if kind == 'object' else [] if kind == 'array' else int(value or 0) if kind == 'int' else value == '1' if kind == 'boolean' else value
        if isinstance(stack[-1], list):
            stack[-1].append(item)
        else:
            stack[-1][key] = item
        if kind in ('object', 'array'):
            stack.append(item)
    assert len(stack) == 1, 'unbalanced JSON output'
    print(json.dumps(root))
elif mode == 'assert':
    assert json.loads(data) == json.loads(rest[0]), data
elif mode == 'status':
    payload = json.loads(data)
    assert payload['running'] is (len(rest) > 1 and rest[1] == '1'), 'global routing state must follow live hook'
    assert payload.get('reconfiguration_pending') is (len(rest) > 2 and rest[2] == '1'), 'routing protection must be separate from service/health state'
    status = payload['interfaces']['wan1']
    assert status['up'] is False, 'down interface must not inherit previous up value'
    assert status['uptime'] == 0, 'failed uptime query must produce zero'
    expected = json.loads(rest[0]) if rest else [{'ip': '1.1.1.1', 'status': 'up', 'latency': 12, 'packetloss': 0}]
    assert status['track_ip'] == expected, status['track_ip']
elif mode == 'alias':
    payload = json.loads(data)
    status = payload['interfaces']['wan1']
    assert status['up'] is True and status['uptime'] == 47, 'RPC ignored the active family alias'
    assert status['enabled'] is True, 'valid UCI enabled boolean was not normalized'
    assert status['status'] == 'online' and payload['reconfiguration_pending'] is True, 'protection overwrote health state'
elif mode == 'disabled':
    status = json.loads(data)['interfaces']['wan1']
    assert status['enabled'] is False and status['status'] == 'disabled', 'configured-disabled interface retained stale health status'
    assert status['up'] is True, 'configuration disabled state must not change actual link metadata'
elif mode == 'tracking':
    status = json.loads(data)['interfaces']['wan1']
    assert status['tracking'] == rest[0], status
    assert status['running'] is (rest[1] == '1'), status
PY

json_load() {
    local variables
    variables="$(python3 "$TEST_ROOT/rpc-json-fixture.py" read "$1")" || return 1
    eval "$variables"
}
json_select() {
    local type next
    if [ "$1" = .. ]; then
        eval "JSON_CUR=\${JSON_PARENT_$JSON_CUR}"
        return 0
    fi
    eval "type=\${JSON_TYPE_${JSON_CUR}_$1:-}"
    case "$type" in object|array) ;; *) return 1 ;; esac
    eval "next=\${JSON_VALUE_${JSON_CUR}_$1}"
    JSON_CUR=$next
}
json_get_keys() {
    local node="$JSON_CUR" value
    [ -z "${2:-}" ] || eval "node=\${JSON_VALUE_${JSON_CUR}_$2}"
    eval "value=\${JSON_KEYS_$node:-}"
    export "$1=$value"
}
json_get_var() {
    local value
    eval "value=\${JSON_VALUE_${JSON_CUR}_$2:-\${3:-}}"
    export "$1=$value"
}
json_get_type() {
    local value
    eval "value=\${JSON_TYPE_${JSON_CUR}_$2:-}"
    export "$1=$value"
}
json_init() { : > "$TEST_ROOT/events"; }
json_add_object() { printf 'object\0%s\0\0' "${1:-}" >> "$TEST_ROOT/events"; }
json_add_array() { printf 'array\0%s\0\0' "${1:-}" >> "$TEST_ROOT/events"; }
json_add_string() { printf 'string\0%s\0%s\0' "$1" "$2" >> "$TEST_ROOT/events"; }
json_add_int() { printf 'int\0%s\0%s\0' "$1" "$2" >> "$TEST_ROOT/events"; }
json_add_boolean() { printf 'boolean\0%s\0%s\0' "$1" "$2" >> "$TEST_ROOT/events"; }
json_close_object() { printf 'close\0\0\0' >> "$TEST_ROOT/events"; }
json_close_array() { json_close_object; }
json_dump() { python3 "$TEST_ROOT/rpc-json-fixture.py" write "$TEST_ROOT/events"; }

. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
eval "$(sed '/^\. /d; /^main "\$@"$/d' "$REPO_ROOT/multiwan-nft/files/usr/libexec/rpcd/multiwan_nft")"
NFT=fake_nft
NO_IPV6=0
EMPTY_SETS=0
RPC_HOOK=0
RPC_GUARD=0
TEST_ENABLED=1

fake_nft() {
    case "$*" in
        'list chain inet multiwan_nft multiwan_nft_hook') [ "$RPC_HOOK" -eq 1 ] ;;
        'list table inet multiwan_nft_reconcile') [ "$RPC_GUARD" -eq 1 ] ;;
        '-j list set inet multiwan_nft multiwan_nft_connected_v4')
            if [ "$EMPTY_SETS" -eq 1 ]; then printf '%s\n' '{"nftables":[{"set":{"elem":[]}}]}'; return; fi
            printf '%s\n' '{"nftables":[{"metainfo":{"json_schema_version":1}},{"set":{"name":"multiwan_nft_connected_v4","elem":["192.0.2.1",{"prefix":{"addr":"198.51.100.0","len":24}},{"elem":{"val":{"prefix":{"addr":"203.0.113.0","len":24}},"expires":20}},{"range":["10.0.0.1","10.0.0.2"]}]}}]}'
            ;;
        '-j list set inet multiwan_nft multiwan_nft_connected_v6')
            if [ "$EMPTY_SETS" -eq 1 ]; then printf '%s\n' '{"nftables":[{"set":{}}]}'; return; fi
            printf '%s\n' '{"nftables":[{"set":{"name":"multiwan_nft_connected_v6","elem":["2001:db8::1",{"prefix":{"addr":"2001:db8:1::","len":64}},{"elem":{"val":"fe80::1","expires":20}}]}}]}'
            ;;
        'list table inet multiwan_nft')
            printf '%s\n' 'chain multiwan_nft_policy_balanced {' 'chain multiwan_nft_policy_empty {'
            ;;
        '-j list chain inet multiwan_nft multiwan_nft_policy_balanced')
            printf '%s\n' '{"nftables":[{"chain":{"name":"multiwan_nft_policy_balanced"}},{"rule":{"comment":"tracker wan2 1.1.1.1"}},{"rule":{"comment":"wan6 1 1"}},{"rule":{"comment":"wan2 1 4"}},{"rule":{"comment":"wan1 3 3"}},{"rule":{"comment":"unreachable"}},{"rule":{"comment":"bogus 2 2"}},{"rule":{"comment":"wan1 -1 4"}},{"rule":{"comment":"wan1 1:2 3"}}]}'
            ;;
        '-j list chain inet multiwan_nft multiwan_nft_policy_empty')
            printf '%s\n' '{"nftables":[{"chain":{"name":"multiwan_nft_policy_empty"}},{"rule":{"comment":"blackhole"}}]}'
            ;;
        *) fail "Unexpected nft command: $*" ;;
    esac
}
config_load() { :; }
config_get() {
    case "$2:$3" in
        wan1:TYPE|wan2:TYPE|wan6:TYPE) export "$1=interface" ;;
        wan1:family|wan2:family) export "$1=ipv4" ;;
        wan6:family) export "$1=ipv6" ;;
        wan1:enabled) export "$1=$TEST_ENABLED" ;;
        *) export "$1=${4:-}" ;;
    esac
}
config_get_bool() {
    local value
    config_get value "$2" "$3" "${4:-0}"
    case "$value" in 1|yes|true|on) export "$1=1" ;; *) export "$1=0" ;; esac
}
ubus() { return 1; }
assert_json() { python3 "$TEST_ROOT/rpc-json-fixture.py" assert "$1" "$2" || fail 'Unexpected RPC JSON'; }

connected="$(printf '%s\n' '{"section":"connected"}' | main call status)"
assert_json "$connected" '{"connected":{"ipv4":["192.0.2.1","198.51.100.0/24","203.0.113.0/24","10.0.0.1-10.0.0.2"],"ipv6":["2001:db8::1","2001:db8:1::/64","fe80::1"]}}'
EMPTY_SETS=1
connected="$(printf '%s' '{"section":"connected"}' | main call status)"
assert_json "$connected" '{"connected":{"ipv4":[],"ipv6":[]}}'
EMPTY_SETS=0

policies="$(printf '%s\n' '{"section":"policies"}' | main call status)"
assert_json "$policies" '{"policies":{"ipv4":{"balanced":[{"interface":"wan2","percent":25},{"interface":"wan1","percent":75}],"empty":[]},"ipv6":{"balanced":[{"interface":"wan6","percent":100}],"empty":[]}}}'
NO_IPV6=1
policies="$(printf '%s\n' '{"section":"policies"}' | main call status)"
assert_json "$policies" '{"policies":{"ipv4":{"balanced":[{"interface":"wan2","percent":25},{"interface":"wan1","percent":75}],"empty":[]},"ipv6":{}}}'
NO_IPV6=0

MULTIWAN_NFT_STATUS_DIR="$TEST_ROOT/state"
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/track"
mkdir -p "$MULTIWAN_NFT_STATUS_DIR" "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1"
printf '%s\n' up > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1/TRACK_1.1.1.1"
printf '%s\n' 12 > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1/LATENCY_1.1.1.1"
printf '%s\n' 'not a target' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1/TRACK_OUTPUT"
config_foreach() { "$1" wan1 "${3:-}"; }
multiwan_nft_get_track_status() { printf '%s\n' "${TEST_TRACK_STATUS:-active}"; }
get_online_time() { printf '%s\n' 0; }
network_get_uptime() { return 1; }
network_is_up() { return 1; }
up=1
uptime=999
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" status "$status" || fail 'Incorrect interface defaults or tracking rows'
for pair in 'active active 1' 'paused paused 0' 'down down 0' 'not_enabled disabled 0'; do
    set -- $pair
    TEST_TRACK_STATUS=$1
    [ "$TEST_TRACK_STATUS" != not_enabled ] || TEST_TRACK_STATUS='not enabled'
    status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
    python3 "$TEST_ROOT/rpc-json-fixture.py" tracking "$status" "$2" "$3" || fail 'Incorrect RPC tracking state or running flag'
done
TEST_TRACK_STATUS=active
rm "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1/TRACK_1.1.1.1"
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" status "$status" '[]' || fail 'Unmatched tracking glob was reported as a target'
RPC_HOOK=1
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" status "$status" '[]' 1 || fail 'Live hook was not reported as running'
RPC_GUARD=1
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" status "$status" '[]' 1 1 || fail 'Held routing guard was not reported'
rmdir "$MULTIWAN_NFT_STATUS_DIR"
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" status "$status" '[]' 0 1 || fail 'Guard without a live routing hook was hidden'
mkdir "$MULTIWAN_NFT_STATUS_DIR"
TEST_ENABLED=yes
printf 'online\n' > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan1/STATUS"
ubus() { [ "$*" = 'call network.interface.wan1_4 status' ]; }
network_get_uptime() { [ "$2" = wan1_4 ] || fail 'Uptime queried stale logical interface'; export "$1=47"; }
network_is_up() { [ "$1" = wan1_4 ] || fail 'Link state queried stale logical interface'; }
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" alias "$status" || fail 'Alias link/uptime, enabled boolean or independent health state was incorrect'
TEST_ENABLED=no
status="$(printf '%s\n' '{"section":"interfaces"}' | main call status)"
python3 "$TEST_ROOT/rpc-json-fixture.py" disabled "$status" || fail 'Disabled configuration was not reflected in RPC status'

printf 'NFT RPC regressions passed: connected JSON, member families/weights, empty state, and interface defaults.\n'
