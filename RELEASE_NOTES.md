# Release Notes

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
