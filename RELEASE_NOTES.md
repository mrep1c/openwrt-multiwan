# Release Notes

## v1.0.14

QoS adjusts Hybrid shaping and realtime tuning after Steam/download testing.

- Adds a 98% outer HFSC shaper in Hybrid so the root keeps modest headroom while CAKE children remain work-conserving.
- Raises the automatic realtime/game reserve from 1300 kbit to 1500 kbit, still capped at 25% on very slow links.
- Updates LuCI HFSC guidance for realtime reserve overrides and the MAXDEL stale-packet budget.
- Keeps pure CAKE, pure HFSC, HTB, link-layer presets, offload control, and manual GAMEUP/GAMEDOWN overrides unchanged.

## v1.0.13

QoS fix for Hybrid CAKE child queueing.

- Removes the nested CAKE bandwidth shaper from Hybrid default classes so HFSC remains the only shaper.
- Matches QoSmate's working Hybrid pattern: unshaped CAKE child leaves with `besteffort` on upload and `besteffort ingress` on download.
- Prevents Hybrid download IFB CAKE children from building stale queues during many-flow downloads such as Steam.
- Keeps pure CAKE, HFSC, HTB, link-layer presets, realtime queue sizing, and lifecycle tests unchanged.

## v1.0.12

QoS fixes avoidable Hybrid mode throughput loss.

- Removes the extra 95% CAKE child reduction in Hybrid after subtracting the realtime game reserve.
- Keeps Hybrid root HFSC shaping at the configured per-interface rate while setting the CAKE child to `RATE - GAMERATE`.
- Leaves pure CAKE, HFSC, HTB, link-layer overhead, IFB STAB, offload control, and MAXDEL queue behavior unchanged.

## v1.0.11

QoS clarifies HFSC realtime tuning without changing qdisc behavior.

- Updates LuCI HFSC labels and help to distinguish realtime bandwidth reserve overrides from the MAXDEL stale-packet budget.
- Documents MAXDEL guidance: 16 ms for sharper hit registration, 20 ms for balanced tuning, and 24 ms for burstier marking.
- Keeps the current 1300 kbit automatic realtime reserve, delay-budgeted finite queues, and manual GAMEUP/GAMEDOWN overrides unchanged.
- Confirms the shared realtime queue sizing path applies to both HFSC and Hybrid.

## v1.0.10

QoS refines realtime game queue latency after the low-rate burst-floor regression.

- Makes finite realtime queues delay-budgeted so BFIFO and RED no longer force a fixed 4500 byte floor on low-rate links.
- Treats MAXDEL as the stale-packet budget for BFIFO, RED, DRR/QFQ RED leaves, PFIFO, and NETEM fallback sizing.
- Sets the automatic realtime reserve to a fixed 1300 kbit, capped at 25% of link rate for very slow connections.
- Keeps manual GAMEUP and GAMEDOWN overrides authoritative for users who need a wider realtime lane.

## v1.0.9

QoS adds managed offload control for accurate shaping across restarts.

- Adds the Disable QoS Offloads advanced toggle, enabled by default.
- Disables only QoS-relevant offloads on managed WAN and IFB devices: GRO, GSO, TSO, rx-gro-list, tx-udp-segmentation, and hardware TC offload.
- Adds Extra Offload Devices for optional physical lower ports such as `eth1 eth2`.
- Adds `ethtool` as a backend dependency and runtime dependency.
- Re-applies offload control during QoS start, restart, soft refresh, hotplug/interface rebuilds, and package-managed setup.
- Leaves checksum, scatter-gather, and VLAN offloads untouched, and ignores fixed or unsupported `ethtool` features.

## v1.0.8

QoS adds adaptive realtime game lane sizing for lower-speed links and PC-agent gameplay.

- Changes automatic game/realtime reserves to 1% of rate plus 500 kbit, with a 1000 kbit floor, 3000 kbit ceiling, and 25% slow-link cap.
- Adds minimum burst floors for finite realtime qdiscs so BFIFO, PFIFO, RED, DRR/QFQ, and NETEM do not create tiny low-rate drop buckets.
- Keeps manual GAMEUP and GAMEDOWN overrides authoritative.

## v1.0.7

QoS cleans up first-install behavior and official package integrity checks.

- Ships backend and frontend MD5 registries in the package feed so official installs validate without missing-registry warnings.
- Downgrades missing integrity registries to a quiet custom/manual-install condition instead of printing an error.
- Runs config migration and dependency checking from the backend package post-install hook.
- Lets service start attempt one automatic dependency repair outside package-manager transactions before failing.

## v1.0.6

QoS fixes package dependency detection for fresh installs using the nftables-json flavor.

- Treats `nftables-json` as satisfying the `nftables` runtime dependency.
- Allows installs where the package manager provides the `nft` command through the JSON-capable nftables package.
- Keeps the existing dependency list and install behavior compatible with systems that use plain `nftables`.

## v1.0.5

Adds opt-in download IFB link-layer accounting and a conservative GPON VLAN preset.

- Adds the Download IFB STAB advanced toggle for HFSC, HTB, and Hybrid download IFB roots.
- Adds `pppoe-vlan-gpon-conservative` with overhead 39 and MPU 73.
- Keeps `pppoe-vlan-gpon` at 35/69 and keeps per-interface manual `overhead` and `mpu` overrides available.

## v1.0.4

QoS adds explicit PPPoE link-layer presets for Ethernet and GPON shaping.

- Adds PPPoE over Ethernet and PPPoE over VLAN/Ethernet presets for copper or Ethernet handoffs.
- Adds PPPoE over GPON and PPPoE over VLAN/GPON presets for fiber ONT/OLT bottlenecks without Ethernet preamble/IFG accounting.
- Documents `pppoe-vlan-gpon` as the intended preset for bridged GPON ONT + VLAN + OpenWrt PPPoE setups.
- Keeps per-interface manual `overhead` and `mpu` overrides available when preset defaults need adjustment.

## v1.0.3

Process lifecycle hardening for NFT and QoS.

- Makes the procd-supervised route monitor own and reap its `ip monitor`
  child, preventing duplicate orphan processes after stop/restart races.
- Uses private owner-validated route-monitor workspaces so stale FIFOs from a
  forcibly killed process cannot collide when the kernel reuses its PID.
- Disables procd respawn before NFT fallback cleanup and limits orphan
  recovery to exact route-monitor commands adopted by PID 1.
- Hardens tracking probe and sleep child cleanup.
- Protects NFT and QoS package, hotplug, and agent locks against PID reuse
  and cross-request lock deletion.
- Removes the dormant unsupervised QoS agent watchdog and verifies legacy
  process identity before signalling old watchdog processes.
- Preserves routing policy, QoS packet handling, and DSCP behavior.

## v1.0.2

NFT-only hotfix on top of v1.0.1.

- Cleans up orphaned `ip -4 monitor route` and `ip -6 monitor route`
  processes during MultiWAN NFT stop/restart.
- Keeps QoS packages at v1.0.1-r1.

## v1.0.1

Safe quality-of-life backport on top of v1.0.0.

- Keeps OpenWrt 23.05 OPKG, 24.10 OPKG, and 25.12+ APK feed support.
- Adds version-sync tooling for future package-visible releases.
- Synchronizes QoS package, runtime, and LuCI-displayed versions.
- Makes QoS LuCI health checks read-only and quiet.
- Reduces repeated QoS LuCI/agent reads without changing generated QoS rules.
- Adds defensive NFT temp-file, diagnostics, and helper-cleanup fixes.
- Improves LuCI guidance for MultiWAN mark masks and status display.

## v1.0.0

OpenWrt MultiWAN provides one signed package feed for MultiWAN NFT,
MultiWAN QoS, and both LuCI applications.

Included packages:

- `multiwan-nft`
- `luci-app-multiwan-nft`
- `multiwan-qos`
- `luci-app-multiwan-qos`

Supported router feeds:

- APK feed for OpenWrt 25.12 and newer.
- OPKG feed for OpenWrt 24.10.
- OPKG feed for OpenWrt 23.05.

Highlights:

- nftables-native multi-WAN routing with failover and load balancing.
- Latency-focused QoS shaping with nftables classification and DSCP marking.
- Separate conntrack mark layouts for routing and QoS state.
- Optional LuCI applications for configuration and monitoring.
- Optional Windows agent endpoint for live game-flow updates.
- Architecture-independent public package feeds.

Notes:

- Official OpenWrt is the supported target.
- The package feed is the recommended install path.
- The raw installer is intended for development and recovery use.
- Public feed packages do not include target-specific compiled wrapper
  binaries.
