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
and takes precedence over this option. Its HFSC start/idle baseline can use the
1000 or 1500 kbit/s presets or a custom 300-2000 kbit/s value. The controller
adds its configurable demand reserve (300 kbit/s by default) exactly once to
served traffic plus queue-growth and 200 ms backlog-drain estimates, holds the
last safe rate through the 20-second session grace, and remains capped at both
2000 kbit/s and 25% of each link. By default, Adaptive retains the fixed
1000 kbit/s finite-queue profile. OpenWrt 23.05
remains supported for the normal QoS modes but does not ship the required
`sch_ets` module.

Adaptive keeps one-second active sampling and five-second idle sampling.
Agent notifications wake idle checks but preserve demand and burst history
on active directions. History resets when traffic resumes after the full
20-second idle interval, or when startup/counter resynchronization requires it.

BFIFO/PFIFO overflow retains its immediate rate response, including QFQ FIFO
children and NETEM's direction-specific PFIFO fallback. NETEM with configured
loss does not use drop counts alone to raise the rate. For NETEM backlog,
the controller subtracts a byte allowance for the current rate times
configured delay plus jitter before estimating growth and drain pressure.
This allowance is approximate, especially for delay distributions and bursts.
Managed queues such as RED and FQ-CoDel require served utilization of at least
80% of the current rate or two successive samples of backlog before drops
trigger an increase. Demand and sustained excess backlog can still increase
the rate. These are sampled heuristics that require router validation.

Rate-change timers advance only after a successful change. Reaching the
ceiling with continuing confirmed drops or sustained backlog reports
`ceiling-pressure`, without recording a fictitious increase. Status records
are published atomically and distinguish the last applied rate from the
requested rate, including failed updates and line-cap repair. LuCI displays
a per-device/direction table with rates, backlog, drops and the drop signal,
ceiling state, measurement age, and the decision/last applied update reason.
Measurement age is calculated at collection of the statistics snapshot;
the existing RPC cache can retain that snapshot for up to five seconds.

For HFSC or Hybrid in Adaptive mode, **Adapt Queue Capacity to Rate**
(`hfsc.adaptive_queue_budget=1`) makes BFIFO/PFIFO and NETEM capacity follow the
realtime rate while keeping the configured freshness target fixed unless
adaptive freshness is also enabled. Legacy QFQ
also supports all three BFIFO/PFIFO children. At 18 ms, BFIFO uses
2250 bytes at 1000 kbit/s and 4500 bytes at 2000 kbit/s. The existing leaf is
changed in place and verified before the class update, under the refresh lock.
If an update fails, the controller retains the previous class rate, attempts
to restore every changed leaf limit, and uses its existing bounded retry backoff.
Status exposes the last verified `profile_limit`, `profile_requested_limit`,
`freshness_target_ms`, and `profile_state`. For QFQ, `profile_limit` is the
common child limit; zero means that readback failed or children differ.

Capacity adaptation keeps a minimum burst reserve based on the fixed
1000 kbit/s queue profile, capped at 25% of each link. With a fixed freshness
target, the reserve uses that target; with experimental freshness, it uses the
20 ms baseline regardless of the saved preset. The reserve applies at setup
and during live updates, including NETEM's PFIFO fallback and QFQ FIFO children.
For example, BFIFO at 300 kbit/s with a 20 ms adaptive target keeps 2500 bytes
on an uncapped link rather than shrinking to one MTU. Capacity can grow above
the reserve and shrink back to it. Existing rate-decrease gates retain recent
burst history. This is bounded space for an unexpected burst, not a prediction
of game round boundaries or a guarantee that every burst fits. The reserve can
make actual waiting time exceed the selected target at low service rates.

This option is disabled by default. RED is excluded: changing its limit creates
a new internal FIFO and purges queued packets, so frequent updates would add
loss. QFQ with RED/FQ-CoDel children is also excluded. FQ-CoDel retains its
independent 5 ms target; DRR has no explicit freshness budget attached.
NETEM changes resend the configured delay, jitter, distribution, and loss.
The direction excluded from NETEM uses the existing PFIFO fallback, which also
adapts. NETEM keeps its minimum of 12 packets; at 18 ms and 1000-2000 kbit/s
with 450-byte packets, that floor keeps its limit unchanged. Configured NETEM
loss does not by itself trigger rate increases.
The MTU floor and PFIFO minimum still apply; packet capacity also depends on
packet sizes. The configured target is a queue budget, not a packet-age limit.
Installing or enabling the option requires service setup once; subsequent
rate and queue updates do not restart QoS.

**Adapt Freshness Target (Experimental)** (`hfsc.adaptive_freshness=1`) is a
separate toggle, disabled by default. It requires Adaptive mode, capacity
adaptation, and a direct BFIFO/PFIFO leaf. It starts at 20 ms and overrides
the saved freshness preset while enabled. The controller reuses existing
statistics; it adds no packet probes, faster polling, or per-packet userspace
processing. A compact state file is kept separately for each direction.

After the service rate settles, a window of at least 10 seconds and 10 valid
samples can propose a 1 ms step. Steps stay within 12-24 ms and are separated
by at least 20 seconds during traffic. If every sampled backlog drain estimate
is at least half the current target, the target can tighten. Reductions also
require the existing Adaptive timers to show ten seconds since the last FIFO
drop and ten seconds since the last rate increase. A blocked reduction reports
`freshness_reason=burst-hold`. This guard also applies to recovery toward 20 ms;
full idle still restores the baseline. It reuses existing samples and timestamps
and adds no faster polling. At least three drop
samples with every backlog estimate below half the target relax it instead.
The estimate is `ceil(backlog_bytes * 8 / rate_kbit)`, not measured packet
waiting time. A quiet, empty window brings targets above 20 ms back toward
20 ms. The existing idle grace holds the target; full idle and counter resets
restore 20 ms. Rate changes, missing samples, and polling gaps discard the
observation window. Failed updates keep the last successful target and use
the existing queue restoration and retry handling.

Target-only updates do not rewrite the HFSC class. When minimum limits or
packet rounding leave capacity unchanged, target changes make no additional
kernel reads or writes. Status adds `freshness_control`,
`freshness_requested_ms`, `freshness_reason`, and
`freshness_backlog_estimate_ms`. NETEM, QFQ, RED, FQ-CoDel, and DRR do not run
this millisecond controller. NETEM and QFQ retain their existing capacity
adaptation with a fixed target.

This is an experimental buffer-budget heuristic. One-second samples cannot
observe individual 12-24 ms packet delays or reliably separate every burst
from congestion. Actual delay also depends on packet sizes, queue minimums,
and HFSC service. Router measurements of latency, loss, CPU usage, and
stability are required before recommending this toggle for regular use.
Packet sojourn measurements remain the stronger signal for controlling
queue delay ([RFC 8289](https://www.rfc-editor.org/rfc/rfc8289.html#section-3.1)).

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

Download shaping happens on the WAN IFB before forwarded packets reach nftables.
For a private LAN device or a rule with negated ports, use a matching upload rule
so conntrack can carry its DSCP classification into reply traffic. A download-only
nftables rule cannot change that packet's earlier IFB classification. The tc flower
fallback skips private LAN addresses and negated matches; CAKE uses DSCP instead.

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
