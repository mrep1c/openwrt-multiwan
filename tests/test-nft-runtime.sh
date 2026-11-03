#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-runtime.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
eval "$(sed -n '/^multiwan_nft_check_required_packages()/,/^}/p' "$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft")"
LOG() { :; }
IPKG_INSTROOT="$TEST_ROOT/root"
mkdir -p "$TEST_ROOT/bin" "$IPKG_INSTROOT/lib/multiwan-nft"
helper="$IPKG_INSTROOT/lib/multiwan-nft/libwrap_mwan3_sockopt.so.1.0"
: > "$helper"
for program in ip nft conntrack jshn rpcd flock; do
    printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/$program"
    chmod 755 "$TEST_ROOT/bin/$program"
done
IP4="$TEST_ROOT/bin/ip" NFT="$TEST_ROOT/bin/nft"
( PATH="$TEST_ROOT/bin"; multiwan_nft_check_required_packages ) || fail 'Usable tools were rejected without package metadata'
for program in ip nft conntrack jshn rpcd flock; do
    mv "$TEST_ROOT/bin/$program" "$TEST_ROOT/$program"
    if ( PATH="$TEST_ROOT/bin"; multiwan_nft_check_required_packages ); then fail "Missing runtime tool accepted: $program"; fi
    mv "$TEST_ROOT/$program" "$TEST_ROOT/bin/$program"
done
mv "$helper" "$TEST_ROOT/helper"
if ( PATH="$TEST_ROOT/bin"; multiwan_nft_check_required_packages ); then fail 'Missing native helper accepted'; fi
mv "$TEST_ROOT/helper" "$helper"
for program in ip nft; do
    printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/$program"
    if ( PATH="$TEST_ROOT/bin"; multiwan_nft_check_required_packages ); then fail "Unsupported runtime accepted: $program"; fi
    printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/$program"
done
init="$REPO_ROOT/multiwan-nft/files/etc/init.d/multiwan-nft"
eval "$(sed -n '/^MULTIWAN_NFT_REQUIRED_PACKAGES=/p' "$init")"
for name in multiwan_nft_detect_package_manager multiwan_nft_check_package multiwan_nft_install_missing_packages install_deps; do
    eval "$(sed -n "/^$name()/,/^}/p" "$init")"
done
export NFT_TEST_PKG_STATE="$TEST_ROOT/packages" NFT_TEST_PKG_CALLS="$TEST_ROOT/package-calls"
: > "$NFT_TEST_PKG_CALLS"
printf '%s\n' ip-full nftables-json jshn rpcd conntrack multiwan-nft-sockopt > "$NFT_TEST_PKG_STATE"
cat > "$TEST_ROOT/bin/apk" <<'EOF'
#!/bin/sh
case "$1" in
    info) [ "$2" = -e ] && grep -qx "$3" "$NFT_TEST_PKG_STATE" ;;
    update) echo update >> "$NFT_TEST_PKG_CALLS" ;;
    add)
        echo "$*" >> "$NFT_TEST_PKG_CALLS"
        [ "${NFT_TEST_ADD_FAIL:-0}" = 0 ] || exit 1
        shift
        printf '%s\n' "$@" >> "$NFT_TEST_PKG_STATE"
        ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$TEST_ROOT/bin/apk"
multiwan_nft_acquire_package_lock() { echo lock >> "$NFT_TEST_PKG_CALLS"; }
multiwan_nft_release_package_lock() { echo unlock >> "$NFT_TEST_PKG_CALLS"; }
# rc.common does not enable nounset; use the installed function's actual context.
( set +u; PATH="$TEST_ROOT/bin:$PATH"; install_deps ) || fail 'Missing FIB package repair failed'
grep -qx 'add kmod-nft-fib' "$NFT_TEST_PKG_CALLS" || fail 'Dependency repair omitted the required FIB kernel module'
grep -qx kmod-nft-fib "$NFT_TEST_PKG_STATE" || fail 'Dependency repair did not install the FIB module'
grep -qx unlock "$NFT_TEST_PKG_CALLS" || fail 'Successful dependency repair kept its lock'
: > "$NFT_TEST_PKG_CALLS"
( set +u; PATH="$TEST_ROOT/bin:$PATH"; install_deps ) || fail 'Already installed dependencies were rejected'
[ ! -s "$NFT_TEST_PKG_CALLS" ] || fail 'Already satisfied dependencies triggered package operations'
sed -i '/^kmod-nft-fib$/d' "$NFT_TEST_PKG_STATE"
export NFT_TEST_ADD_FAIL=1
if ( set +u; PATH="$TEST_ROOT/bin:$PATH"; install_deps ); then fail 'Failed FIB install reported success'; fi
grep -qx unlock "$NFT_TEST_PKG_CALLS" || fail 'Failed dependency repair kept its lock'
printf 'NFT runtime tests passed: actual tools/helper, iproute2/JSON, package-transaction context and FIB dependency repair/error handling.\n'
