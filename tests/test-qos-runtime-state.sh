#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-qos-runtime.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

log_msg() { :; }
error_out() { :; }

MULTIWAN_QOS_RUNTIME_ROOT="$TEST_ROOT/runtime"
MULTIWAN_QOS_QDISC_LEDGER="$MULTIWAN_QOS_RUNTIME_ROOT/qdisc-devices"
MULTIWAN_QOS_OFFLOAD_ROOT="$MULTIWAN_QOS_RUNTIME_ROOT/offloads"
MULTIWAN_QOS_ETS_PROBE_STATE="$MULTIWAN_QOS_RUNTIME_ROOT/ets-probe-device"
. "$REPO_ROOT/multiwan-qos/lib/multiwan-qos/runtime-state.sh"

# Ownership ledger updates are atomic, deduplicated, and safe for an initially
# absent state file.
mw_qos_ledger_add wan0 || fail "could not create ownership ledger"
mw_qos_ledger_add wan0 || fail "duplicate ledger add failed"
mw_qos_ledger_add wan1 || fail "second ledger add failed"
[ "$(grep -c . "$MULTIWAN_QOS_QDISC_LEDGER")" -eq 2 ] || fail "ledger add did not deduplicate devices"
mw_qos_ledger_remove wan0 || fail "ledger remove failed"
[ "$(cat "$MULTIWAN_QOS_QDISC_LEDGER")" = wan1 ] || fail "ledger remove changed the wrong device"
mw_qos_ledger_commit wan2 wan2 wan3 || fail "ledger commit failed"
[ "$(grep -c . "$MULTIWAN_QOS_QDISC_LEDGER")" -eq 2 ] || fail "ledger commit did not deduplicate devices"
mw_qos_ledger_commit || fail "empty ledger commit failed"
[ ! -e "$MULTIWAN_QOS_QDISC_LEDGER" ] || fail "empty ledger commit left stale ownership"
mw_qos_ledger_add 'bad/device' >/dev/null 2>&1 && fail "unsafe device name entered the ledger"

WAN_ROOT=1
WAN_INGRESS=1
IFB_ROOT=1
IFB_EXISTS=1
IFB_TYPE=ifb
TC_DELETE_FAIL=0
PROBE_EXISTS=0
PROBE_NAME=
PROBE_QDISC=0
PROBE_TC_ADD_FAIL=0
PROBE_TC_ADD_COUNT=0

tc() {
    if [ "$1" = qdisc ] && [ "$2" = show ] && [ "$3" = dev ]; then
        case "$4" in
            wan0)
                [ "$WAN_ROOT" -eq 0 ] || printf 'qdisc cake 1: root\n'
                [ "$WAN_INGRESS" -eq 0 ] || printf 'qdisc ingress ffff: parent ffff:fff1\n'
                ;;
            ifb-wan0) [ "$IFB_ROOT" -eq 0 ] || printf 'qdisc cake 1: root\n' ;;
        esac
        return 0
    fi
    if [ "$1" = qdisc ] && [ "$2" = del ] && [ "$3" = dev ]; then
        case "$4" in
            mqe*) PROBE_QDISC=0; return 0 ;;
        esac
        [ "$TC_DELETE_FAIL" -eq 0 ] || return 1
        case "$4:$5" in
            wan0:root) WAN_ROOT=0 ;;
            wan0:ingress) WAN_INGRESS=0 ;;
            ifb-wan0:root) IFB_ROOT=0 ;;
        esac
        return 0
    fi
    if [ "$1" = qdisc ] && [ "$2" = add ] && [ "$3" = dev ]; then
        case "$4" in
            mqe*)
                PROBE_TC_ADD_COUNT=$((PROBE_TC_ADD_COUNT + 1))
                [ "$PROBE_TC_ADD_FAIL" -eq 0 ] || return 1
                PROBE_QDISC=1
                return 0
                ;;
        esac
    fi
    return 1
}

ip() {
    case "$*" in
        'link show ifb-wan0') [ "$IFB_EXISTS" -eq 1 ] ;;
        'link del ifb-wan0') IFB_EXISTS=0; IFB_ROOT=0 ;;
        'link show wan0') return 0 ;;
        'link show absent0') return 1 ;;
        'link show mqe'*) [ "$PROBE_EXISTS" -eq 1 ] ;;
        'link add name mqe'*' type ifb')
            PROBE_NAME="$4"
            PROBE_EXISTS=1
            ;;
        'link del mqe'*) PROBE_EXISTS=0; PROBE_QDISC=0 ;;
        '-o link show type ifb')
            if [ "$IFB_EXISTS" -eq 1 ] && [ "$IFB_TYPE" = ifb ]; then
                printf '1: ifb-wan0: <UP>\n'
            fi
            if [ "$PROBE_EXISTS" -eq 1 ]; then
                printf '2: %s: <UP>\n' "$PROBE_NAME"
            fi
            ;;
        *) return 1 ;;
    esac
}

mw_qos_cleanup_device wan0 || fail "owned qdisc cleanup failed"
[ "$WAN_ROOT:$WAN_INGRESS:$IFB_EXISTS" = 0:0:0 ] || fail "owned qdisc cleanup left runtime state"

# A name collision with a non-IFB device must fail closed instead of deleting
# another subsystem's link.
WAN_ROOT=0
WAN_INGRESS=0
IFB_ROOT=0
IFB_EXISTS=1
IFB_TYPE=veth
foreign_result=0
mw_qos_cleanup_device wan0 || foreign_result=$?
[ "$foreign_result" -ne 0 ] || fail "non-IFB name collision was accepted"
[ "$IFB_EXISTS" -eq 1 ] || fail "non-IFB name collision was deleted"

# Deletion command failures are verified against final state and surfaced.
WAN_ROOT=1
WAN_INGRESS=0
IFB_EXISTS=0
IFB_TYPE=ifb
TC_DELETE_FAIL=1
cleanup_result=0
mw_qos_cleanup_device wan0 || cleanup_result=$?
[ "$cleanup_result" -ne 0 ] || fail "remaining root qdisc was reported as clean"

mkdir -p "$MULTIWAN_QOS_OFFLOAD_ROOT"
printf 'gro on\n' > "$MULTIWAN_QOS_OFFLOAD_ROOT/absent0"
ethtool() { return 0; }
restore_result=0
mw_qos_restore_offload_state absent0 || restore_result=$?
[ "$restore_result" -eq 2 ] || fail "unavailable offload device was not deferred"
[ -f "$MULTIWAN_QOS_OFFLOAD_ROOT/absent0" ] || fail "deferred offload journal was removed"

printf 'gro on\n' > "$MULTIWAN_QOS_OFFLOAD_ROOT/wan0"
mw_qos_restore_offload_state wan0 || fail "available offload device was not restored"
[ ! -f "$MULTIWAN_QOS_OFFLOAD_ROOT/wan0" ] || fail "restored offload journal was retained"

PROBE_EXISTS=1
PROBE_NAME=mqe123_0
mkdir -p "${MULTIWAN_QOS_ETS_PROBE_STATE%/*}"
printf 'mqe123_0\n' > "$MULTIWAN_QOS_ETS_PROBE_STATE"
MULTIWAN_QOS_ETS_PROBE_DEVICE=
mw_qos_cleanup_ets_probe || fail "owned ETS probe cleanup failed"
[ "$PROBE_EXISTS" -eq 0 ] || fail "owned ETS probe device was retained"
[ ! -f "$MULTIWAN_QOS_ETS_PROBE_STATE" ] || fail "owned ETS probe state was retained"

MULTIWAN_QOS_SCH_ETS_DIR="$TEST_ROOT/sch_ets"
mkdir -p "$MULTIWAN_QOS_SCH_ETS_DIR"
PROBE_TC_ADD_FAIL=0
PROBE_TC_ADD_COUNT=0
PROBE_EXISTS=0
PROBE_NAME=
mw_qos_probe_ets 1 1 'test topology was unchanged' || fail "ETS parser/kernel probe failed"
[ "$PROBE_TC_ADD_COUNT" -eq 2 ] || fail "ETS probe skipped an enabled topology"
[ "$PROBE_EXISTS" -eq 0 ] || fail "successful ETS probe retained its IFB"
[ ! -f "$MULTIWAN_QOS_ETS_PROBE_STATE" ] || fail "successful ETS probe retained ownership state"

PROBE_TC_ADD_FAIL=1
PROBE_TC_ADD_COUNT=0
PROBE_EXISTS=0
probe_result=0
mw_qos_probe_ets 1 0 'test topology was unchanged' || probe_result=$?
[ "$probe_result" -ne 0 ] || fail "failed ETS qdisc creation was accepted"
[ "$PROBE_EXISTS" -eq 0 ] || fail "failed ETS probe retained its IFB"
[ ! -f "$MULTIWAN_QOS_ETS_PROBE_STATE" ] || fail "failed ETS probe retained stale ownership state"

# Full teardown combines configured and journaled ownership, preserves only
# failed devices, and reports partial cleanup to its caller.
mw_qos_ledger_commit wan0 wan1 || fail "could not seed teardown ledger"
CONFIG_LOAD_OK=1
CONFIG_DEVICE=wan0
config_load() { [ "$CONFIG_LOAD_OK" -eq 1 ]; }
config_foreach() { "$1" cfg0; }
config_get() { eval "$1=\$CONFIG_DEVICE"; }
network_get_device() { eval "$1=wan9"; }
mw_qos_restore_offload_state_file() { return 0; }
TEARDOWN_FAIL_WAN1=1
CLEANED_DEVICES=
mw_qos_cleanup_device() {
    CLEANED_DEVICES="${CLEANED_DEVICES:+$CLEANED_DEVICES }$1"
    [ "$1" != wan1 ] || [ "$TEARDOWN_FAIL_WAN1" -eq 0 ]
}
NFT_DESTROYS=
nft() {
    case "$1" in
        list) return 0 ;;
        destroy) NFT_DESTROYS="${NFT_DESTROYS:+$NFT_DESTROYS }$3/$4" ;;
    esac
}
teardown_result=0
mw_qos_teardown_runtime || teardown_result=$?
[ "$teardown_result" -ne 0 ] || fail "partial teardown was reported as successful"
[ "$CLEANED_DEVICES" = 'wan0 wan1' ] || fail "teardown did not deduplicate config and ledger ownership"
[ "$(cat "$MULTIWAN_QOS_QDISC_LEDGER")" = wan1 ] || fail "teardown did not retain only failed ownership"
[ "$NFT_DESTROYS" = 'inet/multiwan_qos_mcast inet/dscptag netdev/multiwan_qos_ingress' ] || fail "teardown skipped an owned nft table"

TEARDOWN_FAIL_WAN1=0
CLEANED_DEVICES=
NFT_DESTROYS=
mw_qos_teardown_runtime || fail "retry teardown failed"
[ "$CLEANED_DEVICES" = wan0\ wan1 ] || fail "retry teardown lost configured or journaled ownership"
[ ! -e "$MULTIWAN_QOS_QDISC_LEDGER" ] || fail "successful retry retained stale ownership"

mw_qos_ledger_commit wan2 || fail "could not seed malformed-config teardown ledger"
CONFIG_LOAD_OK=0
CLEANED_DEVICES=
teardown_result=0
mw_qos_teardown_runtime || teardown_result=$?
[ "$teardown_result" -ne 0 ] || fail "malformed configuration was not reported"
[ "$CLEANED_DEVICES" = wan2 ] || fail "malformed configuration prevented ledger-based cleanup"
[ ! -e "$MULTIWAN_QOS_QDISC_LEDGER" ] || fail "malformed-config cleanup retained successful ownership"

CONFIG_LOAD_OK=1
CONFIG_DEVICE=
CLEANED_DEVICES=
mw_qos_teardown_runtime || fail "network-derived teardown failed"
[ "$CLEANED_DEVICES" = wan9 ] || fail "teardown lost the network-derived legacy device fallback"

printf 'QoS runtime-state regression tests passed.\n'
