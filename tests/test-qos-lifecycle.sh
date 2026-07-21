#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

export IPKG_INSTROOT="$REPO_ROOT/multiwan-qos"
action=none
# A non-command source argument prevents the init script's direct-call helper
# from dispatching update commands during this hermetic test.
set -- none
. "$REPO_ROOT/multiwan-qos/etc/init.d/multiwan-qos"

MULTIWAN_QOS_START_RESULT=23
start_result=0
service_started || start_result=$?
[ "$start_result" -eq 23 ] || fail "service_started did not preserve startup failure"

lifecycle_finished=0
finish_qos_lifecycle() {
    lifecycle_finished=1
}
MULTIWAN_QOS_STOP_RESULT=29
stop_result=0
service_stopped || stop_result=$?
[ "$stop_result" -eq 29 ] || fail "service_stopped did not preserve teardown failure"
[ "$lifecycle_finished" -eq 1 ] || fail "service_stopped skipped lifecycle cleanup"

log_msg() { :; }
ethtool() { :; }
ip() { return 1; }
deferred_result=0
restore_offload_state_file "$REPO_ROOT/multiwan-qos/Makefile" || deferred_result=$?
[ "$deferred_result" -eq 2 ] || fail "unavailable device was not treated as deferred restoration"
[ -r "$REPO_ROOT/multiwan-qos/Makefile" ] || fail "deferred restoration removed its state file"

printf 'QoS lifecycle regression tests passed.\n'
