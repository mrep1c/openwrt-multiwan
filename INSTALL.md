# Install Guide

This guide covers the supported install methods for OpenWrt MultiWAN.

Use the router package feed for normal installs. Use the SDK source feed when
building firmware or packages. Use the raw installer only for development or
recovery work.

## Easy Router Install

Run this from SSH:

```sh
uclient-fetch -O /tmp/setup-multiwan-feed.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/setup-feed.sh
sh /tmp/setup-multiwan-feed.sh install
```

The helper:

- detects `apk` or `opkg`,
- selects the matching feed for the OpenWrt release,
- installs the feed signing key,
- updates package indexes,
- installs the selected packages,
- restarts `rpcd` and `uhttpd` after LuCI installs.

Modes:

```sh
sh /tmp/setup-multiwan-feed.sh setup
sh /tmp/setup-multiwan-feed.sh install
sh /tmp/setup-multiwan-feed.sh main
sh /tmp/setup-multiwan-feed.sh luci
sh /tmp/setup-multiwan-feed.sh remove
```

`main` installs only `multiwan-nft` and `multiwan-qos`.
`luci` installs only `luci-app-multiwan-nft` and `luci-app-multiwan-qos`.

## OpenWrt 25.12+ APK Feed

Install the feed public key:

```sh
mkdir -p /etc/apk/keys
uclient-fetch -O /etc/apk/keys/mrep1c-openwrt-multiwan-apk.pem https://github.com/mrep1c/openwrt-multiwan/releases/download/apk-25.12-noarch/mrep1c-openwrt-multiwan-apk.pem
```

Add the feed:

```sh
mkdir -p /etc/apk/repositories.d
echo "https://github.com/mrep1c/openwrt-multiwan/releases/download/apk-25.12-noarch/packages.adb" >> /etc/apk/repositories.d/customfeeds.list
apk update
```

Install backend services:

```sh
apk add multiwan-nft multiwan-qos
```

Install LuCI apps:

```sh
apk add luci-app-multiwan-nft luci-app-multiwan-qos
```

Install everything:

```sh
apk add multiwan-nft luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
```

LuCI APK Configuration users can paste this feed URL into the custom feeds
field after installing the public key:

```text
https://github.com/mrep1c/openwrt-multiwan/releases/download/apk-25.12-noarch/packages.adb
```

## OpenWrt 24.10 OPKG Feed

Install the feed public key:

```sh
uclient-fetch -O /tmp/mrep1c-openwrt-multiwan-opkg.pub https://github.com/mrep1c/openwrt-multiwan/releases/download/opkg-24.10-noarch/mrep1c-openwrt-multiwan-opkg.pub
opkg-key add /tmp/mrep1c-openwrt-multiwan-opkg.pub
```

Add the feed:

```sh
echo "src/gz multiwan https://github.com/mrep1c/openwrt-multiwan/releases/download/opkg-24.10-noarch" >> /etc/opkg/customfeeds.conf
opkg update
```

Install packages:

```sh
opkg install multiwan-nft multiwan-qos
opkg install luci-app-multiwan-nft luci-app-multiwan-qos
```

## OpenWrt 23.05 OPKG Feed

Install the feed public key:

```sh
uclient-fetch -O /tmp/mrep1c-openwrt-multiwan-opkg.pub https://github.com/mrep1c/openwrt-multiwan/releases/download/opkg-23.05-noarch/mrep1c-openwrt-multiwan-opkg.pub
opkg-key add /tmp/mrep1c-openwrt-multiwan-opkg.pub
```

Add the feed:

```sh
echo "src/gz multiwan https://github.com/mrep1c/openwrt-multiwan/releases/download/opkg-23.05-noarch" >> /etc/opkg/customfeeds.conf
opkg update
```

Install packages:

```sh
opkg install multiwan-nft multiwan-qos
opkg install luci-app-multiwan-nft luci-app-multiwan-qos
```

## SDK Source Feed

Use this path when building with the OpenWrt SDK or buildroot:

```sh
echo "src-git multiwan https://github.com/mrep1c/openwrt-multiwan.git" >> feeds.conf.default
./scripts/feeds update multiwan
./scripts/feeds install -p multiwan multiwan-nft luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
make menuconfig
```

Build selected packages:

```sh
make package/feeds/multiwan/multiwan-nft/compile V=s
make package/feeds/multiwan/luci-app-multiwan-nft/compile V=s
make package/feeds/multiwan/multiwan-qos/compile V=s
make package/feeds/multiwan/luci-app-multiwan-qos/compile V=s
```

Install generated packages only on routers that match the SDK release and
package manager.

## Raw Installer

The raw installer copies files from GitHub. It is useful for development and
recovery, but the package feed is the normal install path.

```sh
uclient-fetch -O /tmp/install-multiwan.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/install.sh
sh /tmp/install-multiwan.sh
```

Backend services only:

```sh
sh /tmp/install-multiwan.sh main
```

LuCI only:

```sh
sh /tmp/install-multiwan.sh luci
```

Start backend services after install:

```sh
START_SERVICES=1 sh /tmp/install-multiwan.sh main
```

## Verification

```sh
apk info -e multiwan-nft multiwan-qos
/etc/init.d/multiwan-nft status
/etc/init.d/multiwan-qos health_check
nft list table inet mwan3
nft list table inet dscptag
tc -s qdisc show
```

On OPKG systems:

```sh
opkg list-installed | grep -E 'multiwan-(nft|qos)'
```

LuCI refresh:

```sh
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
```

## Optional Firewall Mask Change

MultiWAN NFT defaults to routing mark mask `0x3F0000`. Custom masks are allowed
when they are hexadecimal, contain at least three set bits, and do not overlap
the lower byte `0x000000ff` used by MultiWAN QoS.

Example:

```sh
uci set multiwan-nft.globals.mmx_mask='0x00FC0000'
uci commit multiwan-nft
/etc/init.d/multiwan-nft restart
/etc/init.d/multiwan-qos restart
```
