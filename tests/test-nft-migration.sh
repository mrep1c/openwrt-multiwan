#!/bin/sh
set -eu
TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="${TEST_DIR%/tests}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/multiwan-nft-migration.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
die() { exit 1; }
log() { :; }
remember_path() { :; }
backup_suffix=.backup
BACKUP_SUFFIX=.backup
cp() { [ "$CP_FAIL" -eq 0 ] && command cp "$@"; }
for script in "$REPO_ROOT/multiwan-nft/files/etc/uci-defaults/10-multiwan-nft-migrate-config" "$REPO_ROOT/scripts/install-nft.sh"; do
    eval "$(sed -n '/^migrate_file()/,/^}/p' "$script")"
    old="$TEST_ROOT/old"
    new="$TEST_ROOT/new"
    printf 'mwan3 config\n' > "$old"
    printf 'existing native config\n' > "$new"
    CP_FAIL=1
    if (migrate_file "$old" "$new"); then fail 'Backup failure was ignored'; fi
    [ "$(cat "$old")" = 'mwan3 config' ] && [ "$(cat "$new")" = 'existing native config' ] || fail 'Backup failure destroyed configuration'
    CP_FAIL=0
    migrate_file "$old" "$new"
    [ ! -e "$old" ] && [ "$(cat "$new")" = 'mwan3 config' ] || fail 'Valid migration failed'
    [ "$(cat "$new.backup")" = 'existing native config' ] || fail 'Existing config backup missing'
    [ "$(cat "$old.backup")" = 'mwan3 config' ] || fail 'Original config backup missing'
    migrate_file "$old" "$new"
    [ "$(cat "$new")" = 'mwan3 config' ] || fail 'Repeated migration changed configuration'
done

# Exercise both installation paths before their first product file is replaced.
previous="$TEST_ROOT/previous-core"
pending="$TEST_ROOT/upgrade-pending"
preinst="$(sed -n '/^define Package\/multiwan-nft\/preinst$/,/^endef$/p' "$REPO_ROOT/multiwan-nft/Makefile" |
    sed '1d;$d;s/\$\$/\$/g' | sed "s|/lib/multiwan-nft/multiwan_nft.sh|$previous|g;s|/var/run/multiwan-nft-upgrade-pending|$pending|g")"
[ -n "$preinst" ] || fail 'Package upgrade provenance hook missing'
MAIN_PACKAGES=fixture
install_packages() { :; }
migrate_configs() { :; }
install_file() {
    [ "$1" = multiwan-nft/files/etc/config/multiwan-nft ] || fail 'Unexpected first installer write'
    [ ! -f "$previous" ] || [ -f "$pending" ] || fail 'Raw installer replaced files before recording upgrade'
    exit 0
}
eval "$(sed -n '/^install_main()/,/^}/p' "$REPO_ROOT/scripts/install-nft.sh" |
    sed "s|/lib/multiwan-nft/multiwan_nft.sh|$previous|g;s|/var/run/multiwan-nft-upgrade-pending|$pending|g")"
for installer in package raw; do
    rm -f "$previous" "$pending"
    run_install() {
        if [ "$installer" = package ]; then IPKG_INSTROOT= sh -c "$preinst"; else (install_main); fi
    }
    run_install || fail 'Fresh installation failed'
    [ ! -e "$pending" ] || fail 'Fresh installation acquired an upgrade marker'
    touch "$previous"
    for attempt in 1 2; do
        run_install || fail 'Upgrade provenance could not be recorded'
        [ -f "$pending" ] || fail 'Existing installation lost upgrade provenance'
        [ "$(stat -c %a "$pending")" = 600 ] || fail 'Upgrade marker has unsafe permissions'
    done
    rm "$pending"
    mkdir "$pending"
    if (run_install) 2>/dev/null; then fail 'Marker creation failure permitted replacement'; fi
    rmdir "$pending"
done
IPKG_INSTROOT="$TEST_ROOT/image" sh -c "$preinst" || fail 'Image staging failed'
[ ! -e "$pending" ] || fail 'Image staging changed the running system'
export NFT_TEST_UCI_CALLS="$TEST_ROOT/uci-calls" NFT_TEST_GLOBALS_PRESENT=1
mkdir "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/uci" <<'EOF'
#!/bin/sh
[ "$1" != -q ] || shift
echo "$*" >> "$NFT_TEST_UCI_CALLS"
case "$1" in
    get) [ "$2" = multiwan-nft.globals ] && [ "$NFT_TEST_GLOBALS_PRESENT" = 1 ] ;;
    add) echo cfg000001 ;;
    rename|set|commit) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$TEST_ROOT/bin/uci"
defaults="$REPO_ROOT/luci-app-multiwan-nft/root/etc/uci-defaults/60_luci-multiwan-nft"
PATH="$TEST_ROOT/bin:$PATH" sh "$defaults"
[ "$(cat "$NFT_TEST_UCI_CALLS")" = 'get multiwan-nft.globals' ] || fail 'LuCI defaults changed or committed an existing configuration'
: > "$NFT_TEST_UCI_CALLS"
NFT_TEST_GLOBALS_PRESENT=0 PATH="$TEST_ROOT/bin:$PATH" sh "$defaults"
expected=$(printf '%s\n' 'get multiwan-nft.globals' 'add multiwan-nft globals' 'rename multiwan-nft.cfg000001=globals' 'commit multiwan-nft')
[ "$(cat "$NFT_TEST_UCI_CALLS")" = "$expected" ] || fail 'Missing globals initialization changed its named-section behavior'
printf 'NFT migration tests passed: backups, failure preservation, idempotent retries, upgrade provenance and existing LuCI configuration preservation.\n'
