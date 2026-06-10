#!/bin/sh
set -eu

backup="${1:-$(cat /root/multiwan-candidate-last-backup 2>/dev/null)}"
backup="$(printf '%s' "$backup" | tr -d '\r\n')"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ "$(id -u)" = 0 ] || fail "run this script as root"
[ -n "$backup" ] && [ -d "$backup" ] || fail "backup directory not found"

for required in \
	/etc/init.d/multiwan-nft \
	/lib/multiwan-nft/common.sh \
	/usr/sbin/multiwan-nft-rtmon \
	/usr/sbin/multiwan-nft-track \
	/etc/init.d/multiwan-qos \
	/etc/multiwan-qos.sh
do
	[ -f "$backup$required" ] || fail "backup is missing $required"
	sh -n "$backup$required" || fail "backup shell syntax is invalid: $required"
done

DISABLE_ON_STOP=0 /etc/init.d/multiwan-qos stop || true
/etc/init.d/multiwan-nft stop || true

find "$backup" -type f ! -path "$backup/.missing/*" | while IFS= read -r source; do
	target="${source#$backup}"
	mkdir -p "$(dirname "$target")"
	cp -p "$source" "$target"
done

if [ -d "$backup/.missing" ]; then
	find "$backup/.missing" -type f | while IFS= read -r marker; do
		target="${marker#$backup/.missing}"
		rm -f "$target"
	done
fi

/etc/init.d/multiwan-nft start
/etc/init.d/multiwan-qos start

echo "Restored MultiWAN runtime files from $backup"
