# OpenWrt MultiWAN

OpenWrt MultiWAN provides one package feed for MultiWAN NFT, MultiWAN QoS,
and their optional LuCI applications.

The feed contains four separately installable packages:

- `multiwan-nft`
- `luci-app-multiwan-nft`
- `multiwan-qos`
- `luci-app-multiwan-qos`

Install the backend packages for router services. Install the LuCI packages
when you want web configuration and status pages.

## Components

MultiWAN NFT is an nftables-native multi-WAN routing manager. It tracks WAN
health, applies routing policies, and supports failover and load-balancing
rules without relying on iptables or ipset.

MultiWAN QoS is a latency-focused traffic shaper. It uses nftables
classification, DSCP marking, tc qdiscs, IP sets, custom rules, connection
statistics, and an optional Windows agent endpoint for live game-flow updates.

HFSC and Hybrid also offer optional Realtime First Scheduling on OpenWrt 24.10
and newer. It places an ETS scheduler below the HFSC link shaper, sends
EF/CS5/CS6/CS7 traffic through one strict realtime band, and keeps the selected
game qdisc as that band's leaf. Adaptive mode retains the bounded HFSC topology
and takes precedence over this option. Its HFSC start/idle baseline can be
selected as 1000 or 1500 kbit/s, remains capped at 25% of each link, and
uses a configurable demand reserve that defaults to 300 kbit/s. Adaptive does
not resize the fixed 1000 kbit/s finite-queue profile. OpenWrt 23.05
remains supported for the normal QoS modes but does not ship the required
`sch_ets` module.

The two services are designed to coexist. MultiWAN QoS uses the lower byte of
conntrack marks for DSCP state, while MultiWAN NFT uses separate upper routing
mark bits.

If you customize `multiwan-nft.globals.mmx_mask`, keep the lower byte
(`0x000000ff`) clear so QoS can preserve DSCP state in conntrack marks.

## Requirements

- OpenWrt 25.12 or newer for the APK feed.
- OpenWrt 24.10 or 23.05 for the OPKG feeds.
- Firewall 4 and nftables.
- Working official OpenWrt package feeds for dependencies.
- `apk` on OpenWrt 25.12 or newer.
- `opkg` on OpenWrt 24.10 and 23.05.

Official OpenWrt is the supported target. Forks can change kernel modules,
package names, firewall behavior, or LuCI internals.

Do not run another QoS, SQM, or shaping system at the same time as
MultiWAN QoS unless you intentionally designed the qdisc and nftables
interaction.

## Quick Install

Run this from SSH on the router:

```sh
uclient-fetch -O /tmp/setup-multiwan-feed.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/setup-feed.sh
sh /tmp/setup-multiwan-feed.sh install
```

The helper detects `apk` or `opkg`, installs the feed signing key, adds the
correct feed, refreshes the package manager, installs all four packages, and
restarts LuCI services after the package transaction.

Helper modes:

```sh
sh /tmp/setup-multiwan-feed.sh setup
sh /tmp/setup-multiwan-feed.sh install
sh /tmp/setup-multiwan-feed.sh main
sh /tmp/setup-multiwan-feed.sh luci
sh /tmp/setup-multiwan-feed.sh remove
```

- `setup` adds only the feed and signing key.
- `install` installs backend and LuCI packages.
- `main` installs only `multiwan-nft` and `multiwan-qos`.
- `luci` installs only `luci-app-multiwan-nft` and `luci-app-multiwan-qos`.
- `remove` removes the custom feed entry.

## Manual Router Install

See [INSTALL.md](INSTALL.md) for full APK and OPKG instructions.

Main packages only:

```sh
apk update
apk add multiwan-nft multiwan-qos
```

LuCI packages:

```sh
apk update
apk add luci-app-multiwan-nft luci-app-multiwan-qos
```

On OPKG-based releases, use `opkg update` and `opkg install` with the same
package names after adding the matching feed.

Important: LuCI's APK Configuration screen needs the router APK feed URL that
ends in `packages.adb`. Do not paste a `.git` source-feed URL there.

## SDK Source Feed

Use this when building packages or firmware with the OpenWrt SDK/buildroot:

```sh
echo "src-git multiwan https://github.com/mrep1c/openwrt-multiwan.git" >> feeds.conf.default
./scripts/feeds update multiwan
./scripts/feeds install -p multiwan multiwan-nft luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
make menuconfig
```

Select the packages under Network and LuCI, then build normally.

## Raw Installer

The package feed is the recommended install path for clean routers. A raw
installer is available for development and recovery use:

```sh
uclient-fetch -O /tmp/install-multiwan.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/install.sh
sh /tmp/install-multiwan.sh
```

Modes:

```sh
sh /tmp/install-multiwan.sh main
sh /tmp/install-multiwan.sh luci
START_SERVICES=1 sh /tmp/install-multiwan.sh main
```

The raw installer copies scripts and LuCI files from GitHub. It does not build
target-specific binaries on the router.

## First Configuration

MultiWAN NFT:

1. Configure WAN interfaces in `/etc/config/network`.
2. Open LuCI > Network > MultiWAN NFT.
3. Enable each WAN interface and add tracking IPs.
4. Create members, policies, and rules.
5. Start or restart the service:

```sh
/etc/init.d/multiwan-nft restart
```

MultiWAN QoS:

1. Open LuCI > Network > MultiWAN QoS.
2. Select the WAN device and LAN device.
3. Set realistic upload and download rates.
4. Choose a shaping mode.
5. Save, apply, and run the health check:

```sh
/etc/init.d/multiwan-qos health_check
```

Windows agent:

1. Install `multiwan-qos` and `luci-app-multiwan-qos`.
2. Open LuCI > Network > MultiWAN QoS > Agent.
3. Enable the endpoint and copy the API key.
4. Install the Windows agent from
   `https://github.com/mrep1c/multiwan-qos-agent/releases`.
5. Enter the router address and API key in the agent settings.

## Verification

```sh
apk info -e multiwan-nft multiwan-qos
/etc/init.d/multiwan-nft status
/etc/init.d/multiwan-qos health_check
nft list table inet multiwan_nft
nft list table inet dscptag
tc -s qdisc show
```

On OPKG systems, replace `apk info -e` with:

```sh
opkg list-installed | grep -E 'multiwan-(nft|qos)'
```

## Useful Paths

- `/etc/config/multiwan-nft`
- `/etc/config/multiwan-qos`
- `/etc/init.d/multiwan-nft`
- `/etc/init.d/multiwan-qos`
- `/www/cgi-bin/multiwan-qos-agent`
- `/etc/multiwan-qos.d/`

## Troubleshooting

If a package cannot be found, confirm that the correct feed was added for the
router's OpenWrt release and run the package manager update command again.

If APK reports an untrusted signature, install the APK public key from the
feed release before running `apk update`.

If OPKG reports a signature error, install the OPKG public key with
`opkg-key add` before running `opkg update`.

If LuCI pages do not appear after install:

```sh
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
```

If MultiWAN QoS fails to shape traffic, run:

```sh
/etc/init.d/multiwan-qos health_check
nft list table inet dscptag
tc -s qdisc show
```

If MultiWAN NFT does not create rules, run:

```sh
/etc/init.d/multiwan-nft restart
/etc/init.d/multiwan-nft status
nft list table inet multiwan_nft
```

## Uninstall

```sh
apk del luci-app-multiwan-qos luci-app-multiwan-nft multiwan-qos multiwan-nft
```

On OPKG systems:

```sh
opkg remove luci-app-multiwan-qos luci-app-multiwan-nft multiwan-qos multiwan-nft
```

The helper can remove the feed entry:

```sh
sh /tmp/setup-multiwan-feed.sh remove
```

## Binary Notes

The public router feeds are architecture-independent and do not ship
`libwrap_mwan3_sockopt.so`. The C source remains in the tree for future
target-specific wrapper work, but the packaged runtime uses native interface
binding.
