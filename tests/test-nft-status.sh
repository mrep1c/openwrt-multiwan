#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
. "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/common.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-status.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
MULTIWAN_NFT_TRACK_STATUS_DIR="$TEST_ROOT/track"
mkdir -p "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan"
eval "$(sed -n '/^multiwan_nft_report_iface_status()/,/^multiwan_nft_report_policies()/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" | sed '$d')"
config_get() { export "$1=${4:-}"; }
config_get_bool() { export "$1=$ENABLED"; }
multiwan_nft_get_iface_id() { export "$1=2"; }
multiwan_nft_get_iface_hotplug_state() { printf 'online\n'; }
multiwan_nft_get_track_status() { printf '%s\n' "${TEST_TRACK_STATUS:-active}"; }
get_online_time() { printf '42\n'; }
UPTIME_FAIL=0
network_get_uptime() {
    [ "$2" = wan_4 ] || fail 'CLI uptime queried stale logical interface'
    [ "$UPTIME_FAIL" -eq 0 ] || return 1
    export "$1=89"
}
ubus() { return 0; }
network_get_device() { [ "$2" != wan_4 ] || export "$1=$DEVICE"; }
mock_ip() {
    [ "${CHECK_STOPPED:-0}" -eq 0 ] || fail 'Stopped interface report inspected IP rules/routes'
    [ "${CHECK_PAUSED:-0}" -eq 0 ] || fail 'Paused interface report inspected intentionally absent routing objects'
    [ "$ENABLED" -eq 1 ] || fail 'Disabled status inspected routing state'
    case "$1" in
        rule) printf '1002: from all iif eth-alias lookup 2\n1002: from all oif eth-alias lookup 2\n2002: from all fwmark 0x20000/0x3f0000 lookup 2\n3002: from all fwmark 0x20000/0x3f0000 unreachable\n' ;;
        route) printf 'default dev eth-alias\n' ;;
    esac
}
IP4=mock_ip NFT=true
for DEVICE in '' eth-alias; do
    ENABLED=0
    result=$(set +u; multiwan_nft_report_iface_status wan)
    [ "$result" = ' interface wan is disabled and tracking is not enabled' ] || fail 'Disabled interface reported missing rules as a routing failure'
done
ENABLED=1 DEVICE=eth-alias
result=$(set +u; multiwan_nft_report_iface_status wan)
case "$result" in *'is online '*'tracking is active') ;; *) fail 'Online status used stale parent device' ;; esac
case "$result" in *'uptime 00h:01m:29s'*) ;; *) fail 'CLI uptime did not follow the active alias' ;; esac
UPTIME_FAIL=1
result=$(set +u; multiwan_nft_report_iface_status wan)
case "$result" in *'uptime 00h:00m:00s'*) ;; *) fail 'Failed CLI uptime query reused a stale value' ;; esac
TEST_TRACK_STATUS=paused CHECK_PAUSED=1
for tracker_state in disabled waiting; do
    printf '%s\n' "$tracker_state" > "$MULTIWAN_NFT_TRACK_STATUS_DIR/wan/STATUS"
    result=$(set +u; multiwan_nft_report_iface_status wan)
    [ "$result" = " interface wan is $tracker_state and tracking is paused" ] || fail 'Paused tracker reported a routing failure or wrong state'
done
TEST_TRACK_STATUS=down CHECK_PAUSED=0
result=$(set +u; multiwan_nft_report_iface_status wan)
case "$result" in *'is online '*'tracking is down') ;; *) fail 'Stale paused metadata hid live routing checks' ;; esac
TEST_TRACK_STATUS=active
NFT=false
result=$(set +u; multiwan_nft_report_iface_status wan)
case "$result" in *'is error (16)'*) ;; *) fail 'Active interface chain failure was hidden' ;; esac
CHECK_STOPPED=1
result=$(set +u; multiwan_nft_report_iface_status wan stopped)
[ "$result" = ' interface wan is stopped and tracking is active' ] || fail 'Stopped interface reported absent owned rules as errors'
ENABLED=0
result=$(set +u; multiwan_nft_report_iface_status wan stopped)
[ "$result" = ' interface wan is disabled and tracking is not enabled' ] || fail 'Stopped report lost configured-disabled state'
eval "$(sed -n '/^multiwan_nft_report_policies()/,/^multiwan_nft_report_connected_v4()/p' "$REPO_ROOT/multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh" | sed '$d')"
NFT=policy_nft
POLICY_LIST_RESULT=7 POLICY_MEMBER_FAIL=0
policy_nft() {
    [ "$POLICY_LIST_RESULT" -eq 0 ] || return "$POLICY_LIST_RESULT"
    printf 'table inet multiwan_nft {\n chain multiwan_nft_policy_first {\n }\n chain multiwan_nft_policy_second {\n }\n}\n'
}
multiwan_nft_policy_members() {
    [ "$POLICY_MEMBER_FAIL:$1" != '1:multiwan_nft_policy_first' ] || return 1
    printf 'wan 1\n'
}
if result=$(multiwan_nft_report_policies_v4); then fail 'Policy report hid a failed table read'; fi
POLICY_LIST_RESULT=0 POLICY_MEMBER_FAIL=1
if result=$(multiwan_nft_report_policies_v4); then fail 'A later successful policy hid an earlier member read failure'; fi
POLICY_MEMBER_FAIL=0
result=$(multiwan_nft_report_policies_v4) || fail 'Valid policy report failed'
case "$result" in *'second:'*'wan (100%)'*) ;; *) fail 'Valid policy rows were lost' ;; esac
printf 'NFT status tests passed: disabled state and active family-alias device.\n'
