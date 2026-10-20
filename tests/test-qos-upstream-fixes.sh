#!/bin/sh

set -u

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwan-qos-upstream.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
QOS_SCRIPT="$REPO_ROOT/multiwan-qos/etc/multiwan-qos.sh"
QOS_INIT="$REPO_ROOT/multiwan-qos/etc/init.d/multiwan-qos"
DEFAULT_IFS="$IFS"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

logger() { printf '%s\n' "$*" >> "$TEST_ROOT/syslog"; }
for source in "$QOS_INIT" "$QOS_SCRIPT"; do
    eval "$(sed -n '/^log_msg() {/,/^}/p' "$source")"
    {
        printf 'before\n'
        log_msg normal
        log_msg -warn warning
        log_msg -err error
        printf 'after\n'
    } > "$TEST_ROOT/stdout" 2> "$TEST_ROOT/stderr"
    [ "$(cat "$TEST_ROOT/stdout")" = "$(printf 'before\nnormal\nafter')" ] ||
        fail "$source logging damaged redirected stdout"
    [ "$(cat "$TEST_ROOT/stderr")" = "$(printf 'Warning: warning\nError: error')" ] ||
        fail "$source logging damaged redirected stderr"
done
grep -Fq 'user.warn Warning: warning' "$TEST_ROOT/syslog" || fail "warning syslog severity was lost"
eval "$(sed -n '/^print_msg() {/,/^}/p' "$QOS_SCRIPT")"
{
    printf 'before\n'
    print_msg normal
    print_msg -warn warning
    printf 'after\n'
} > "$TEST_ROOT/stdout" 2> "$TEST_ROOT/stderr"
[ "$(cat "$TEST_ROOT/stdout")" = "$(printf 'before\nnormal\nafter')" ] ||
    fail "fallback print_msg damaged redirected stdout"
[ "$(cat "$TEST_ROOT/stderr")" = 'Warning: warning' ] || fail "fallback warning was not on stderr"

for helper in get_cake_link_params should_apply_root_stab create_nft_sets; do
    eval "$(sed -n "/^$helper() {/,/^}/p" "$QOS_SCRIPT")"
done
ETHER_VLAN_KEYWORD='ether-vlan'
for DOWNLOAD_IFB_STAB in 0 1; do
    [ "$(get_cake_link_params pppoe-vlan-gpon 35 69 hybrid wan)" = raw ] ||
        fail "Hybrid upload applies overhead twice"
    if [ "$DOWNLOAD_IFB_STAB" -eq 1 ]; then
        expected=raw
    else
        expected='raw overhead 35 mpu 69'
    fi
    [ "$(get_cake_link_params pppoe-vlan-gpon 35 69 hybrid lan)" = "$expected" ] ||
        fail "Hybrid download accounting disagrees with parent STAB"
    [ "$(get_cake_link_params pppoe-vlan-gpon 35 69)" = 'raw overhead 35 mpu 69' ] ||
        fail "standalone CAKE accounting changed"
done
for helper in setup_hybrid setup_hybrid_realtime_first; do
    sed -n "/^$helper() {/,/^}/p" "$QOS_SCRIPT" |
        grep -Fq 'get_cake_link_params "$PRESET" "$OVERHEAD" "$MPU" "hybrid" "$DIR"' ||
        fail "$helper does not pass the shaping direction"
done

_NL_='
'
debug_log() { :; }
config_get_bool() { export "$1=1"; }
config_get() {
    local value
    case "$3" in
        name) value=example ;;
        family) value="$set_family" ;;
        mode) value="$set_mode" ;;
        ip4) value='192.168.1.0/24 192.168.1.50' ;;
        ip6) value='2001:db8::/64 2001:db8::1' ;;
        *) value="${4:-}" ;;
    esac
    export "$1=$value"
}
config_foreach() { "$1" example; }
for set_family in ipv4 ipv6; do
    set_mode=static
    output="$(create_nft_sets)"
    case "$output" in *'flags interval; auto-merge;'*) ;; *) fail "static $set_family overlaps cannot merge" ;; esac
    set_mode=dynamic
    output="$(create_nft_sets)"
    case "$output" in *'flags dynamic, timeout; timeout 1h;'*) ;; *) fail "dynamic $set_family timeout changed" ;; esac
    case "$output" in *auto-merge*) fail "dynamic $set_family acquired interval merging" ;; esac
done

eval "$(sed -n '/^validate_inline_rules() {/,/^}/p' "$QOS_INIT")"
printf 'ip dscp set ef\n' > "$TEST_ROOT/inline.nft"
nft() {
    [ "$1 $2" = '--check --file' ] || return 1
    [ -s "$3" ] || return 1
    printf '%s\n' "$3" >> "$TEST_ROOT/check-paths"
    return "$NFT_RESULT"
}
NFT_RESULT=0
validate_inline_rules "$TEST_ROOT/inline.nft" "$TEST_ROOT/validation" || fail "valid inline rule was rejected"
validate_inline_rules "$TEST_ROOT/inline.nft" "$TEST_ROOT/validation" || fail "second validation failed"
[ "$(sort -u "$TEST_ROOT/check-paths" | wc -l)" -eq 2 ] || fail "validators shared a scratch file"
while IFS= read -r path; do
    [ ! -e "$path" ] || fail "successful validation leaked its scratch file"
done < "$TEST_ROOT/check-paths"
NFT_RESULT=1
if validate_inline_rules "$TEST_ROOT/inline.nft" "$TEST_ROOT/validation"; then
    fail "nft validation failure was ignored"
fi
path="$(tail -n 1 "$TEST_ROOT/check-paths")"
[ ! -e "$path" ] || fail "failed validation leaked its scratch file"
mktemp() { return 1; }
if validate_inline_rules "$TEST_ROOT/inline.nft" "$TEST_ROOT/validation"; then
    fail "scratch creation failure was ignored"
fi
unset -f mktemp

# Exercise the top-level dataplane block with temporary paths and a mocked nft.
sed -n '/^if \[ -s "$INLINE_FILE" \]; then$/,/^fi$/p' "$QOS_SCRIPT" > "$TEST_ROOT/inline-block"
INLINE_FILE="$TEST_ROOT/inline.nft"
INLINE_INCLUDE=''
NFT_RESULT=0
error_out() { :; }
. "$TEST_ROOT/inline-block"
[ "$INLINE_INCLUDE" = "include \"$INLINE_FILE\"" ] || fail "dataplane did not include valid inline rules"
path="$(tail -n 1 "$TEST_ROOT/check-paths")"
[ ! -e "$path" ] || fail "dataplane leaked its scratch file"
if (mktemp() { return 1; }; . "$TEST_ROOT/inline-block"); then
    fail "dataplane ignored scratch creation failure"
fi

printf 'QoS upstream regression tests passed. No real networking commands ran.\n'
