# Release Notes

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
