# Function and behavioral evidence reconciliation

Mapped package baseline: **1.1.16-r1**, November 3, 2026. This document separates source
replacement coverage, recorded software checks, and remaining release acceptance.
The full behavioral contract remains [NFT_PARITY.md](NFT_PARITY.md).

Current **1.1.17-r1** APKs build and verify for AArch64, ARMv7 and MIPSel; the
retained SDK record binds all 74 package inputs. Only CLI validation changes from
1.1.16. The exact delivered guide passes published 1.0.13 to 1.1.17, rollback and
reinstall. Both modern stages verify eleven files, both WAN-bound probes and 4:1
weights. Packaged malformed ifup/ifdown return 2 without recreating stopped
runtime or changing its map. Twelve workers retire; all 28 original targets,
config/startup/map/world/root rules/netifd and original 1.1.16 packages restore.
Independent verification passes (`cd6e66:0`); the record is
`guide-roundtrip-final-1.1.17-2026-11-03`. This is controlled software acceptance;
physical/manual/load validation remains open.

Production publication now passes at commit
`a54fafabc693b92df80182976ede37d6d44c0ba8`:
[compatibility CI](https://github.com/mrep1c/openwrt-multiwan/actions/runs/41716331516)
and [all three feed builds](https://github.com/mrep1c/openwrt-multiwan/actions/runs/41716378142)
succeed. Downloaded production-key indexes authenticate all 18 APKs, whose NFT
payloads match the audited SDKs. A stock 25.12.6 VM genuinely upgrades 1.1.16 to
1.1.17 with the production key and no `allow-untrusted`, then restores its original
baseline. QoS 1.0.60 source, runtime/LuCI files, permissions, package hooks and
dependencies match the previous published feed across all three architectures.
Evidence is retained in `published-feed-1.1.17-2026-11-04`; physical router
transport, interactive LuCI and sustained combined NFT/QoS load remain separate.

The routed dynamic-bypass gap is now exercised in focused and complete native
routing runs. Each passes twelve LAN/router TCP/UDP combinations and 66 successful
observations across fixed IPv4 SNAT, IPv4 MASQUERADE and native IPv6. Exact FIB
egress, source addresses, skb/conntrack/QoS bits and connection IDs are checked.
Fixed SNAT and IPv6 preserve established identity across add/remove. Four
MASQUERADE transitions per run retire old state when egress changes, with UDP
retry and new TCP connections recovering. This is the Linux NAT boundary, not
transparent session migration. Independent verification passes (`64084a:0`);
`dynamic-routing-native-2026-11-03` retains both rejected continuity assumptions,
the focused pass, complete routing pass and original baseline restoration.

The latest raw-installer repair journals original paths before local mutation,
including symlinks, migration backup names and upgrade provenance. Handled failure
restores those paths and removes the active temporary file. Failed requested
backend startup restores prior enabled/running state; failed restoration retains
private recovery data and returns failure. The private umask is scoped to staging.
Both-shell tests cover late main/LuCI failures, interrupted application, fresh
files, migration, symlinks, startup failure, retained backups and fresh directory
modes. A separate SIGHUP control exposes a skipped cleanup trap; the final source
handles HUP explicitly. Six targeted old-source controls fail as expected across
both shells. Native rename and hangup controls verify exact 28-file rollback
without changing running workers, followed by a successful retry. The original stopped
baseline restores. The evidence is `raw-rollback-native-2026-11-03`; this closes
the handled local-application gap, not power-loss/SIGKILL crash consistency.

The raw-development installer also has an unreleased preparation repair. Its old
second-download failure replaces init and records an upgrade marker; legacy
configuration migration also occurs before that failure. All selected downloads
and permissions are now prepared privately before live mutation. Both-shell
regressions cover all components, fresh/existing installs, retries, migration,
dependency failure and download interruption. Native all/main/luci/repeat and a
later failure while running pass with exact source/config/probes and stable
workers through the rejected preparation. Nine recorded workers retire, and all
28 original files, startup/world/map/root rules/netifd restore. The newer journal
record above supplies the separate local-application rollback proof.

The current worktree additionally repairs invalid CLI `ifup`/`ifdown` arguments
initializing mutable runtime before returning usage errors. Existing argument
checks now precede initialization inside each command. The focused regression
fails on 1.1.16 and passes in ash/dash; complete existing shell gates pass.
A reversible native one-file trial passes all twelve advertised commands and
34 invocations, including error exits, argv/stdout, both internal family reports,
WAN-bound IPv4 pings, pause/resume, restart and stopped reports. The original CLI
and stopped VM profile restore. This repair is not in the frozen 1.1.16 APKs;
those artifacts are held pending the next build. The immutable 142-function audit
record retains its earlier source/document hashes and is not relabeled as a new
package build.

## Declaration inventory

The retained official mwan3 2.12.2 archive and reviewed changes through 2.12.5
contain 133 explicit declarations and eight generated socket resolver helpers in
the eight runtime modules below. All **141** have an explicit native replacement
or documented external responsibility. The reviewed upstream patches add/remove
no declarations in those modules. Nested callbacks are included.

The complete package scan covers all fifteen upstream files. It finds one further
declaration in the legacy `flush_conntrack` migration script: **142 functions/helpers
in total**. Native runtime interprets `always`/`never` without rewriting user config;
the old mutation callback is replaced by that shared runtime responsibility and
a no-op defaults script. `test-nft-recovery.sh` covers legacy scalar/list values,
duplicate suppression and purge failure. The scoped-cleanup behavior change is
documented in `INSTALL.md`. Hotplug/user scripts declare no additional functions.
Upstream development-only test helpers are outside the installed runtime; the
package install recipe does not ship those test scripts.

| Module | Upstream explicit declarations | Native explicit declarations |
| --- | ---: | ---: |
| Routing/rules core | 53 | 85 |
| Common helpers | 11 | 25 |
| CLI | 14 | 15 |
| Tracker | 20 | 21 |
| Route monitor | 9 | 20 |
| Service/init | 6 | 24 |
| RPC | 10 | 14 |
| Socket helper | 10 | 13 |
| Total | 133 | 217 |

The machine-readable map gives upstream/native paths, declaration lines, nested
owners and replacement notes. Merged functions are mapped explicitly rather than
being treated as missing or silently ignored. No literal upstream UCI option read
is absent from the scanned native modules. Neither statement proves that an
option or function behaves correctly; the checks below supply behavioral evidence.

Workspace evidence: `diagnostics/mwan3-function-audit-1.1.16-2026-11-03/`, including
`inventory.json`, `function-map.json`, `supplemental-map.json` and `feature-map.json`. Its source hashes
bind the map to this candidate. Hotplug scripts, configuration migration, LuCI,
packaging and DNS producers are additional surfaces; they are assessed below even
though they are outside the eight upstream declaration modules.

## Recorded software proof by contract item

“Recorded” means assertions passed in the stated fixtures or virtual profile.
It is not hardware sign-off or a claim that every possible topology was tested.
All test paths below are relative to the repository; evidence record names are
relative to the workspace `diagnostics/` directory.

| Contract item | Retained tests and execution evidence | Scope or remaining check |
| --- | --- | --- |
| 1. Base rules/ownership | `test-nft-packets.py`, `test-nft-ownership.sh`, `test-nft-recovery.sh`; `shutdown-final-1.1.15-2026-11-03` and `bypass-protocols-final-1.1.15-2026-11-03` | Native generation, failed-batch preservation, owned cleanup and packet assertions. |
| 2. Mark allocation | `test-nft-common.sh`, `test-nft-identity.sh`, `test-nft-packets.py`; `cross32-lifecycle-1.1.9-2026-11-02` | Mask validation/capacity and unrelated-bit preservation; actual sparse bit-31 routing on both 32-bit targets. |
| 3. Connection affinity | `test-nft-packets.py`, `test-nft-routing.py`; `tcp-rules-final-1.1.15-2026-11-03`, `sticky-ingress-1.1.10-2026-11-02` | Both-family real TCP/UDP, WAN replies and established NAT continuity. |
| 4. Special actions | `test-nft-routing.py`; `special-actions-final-1.1.15-2026-11-03` | All 24 direct/fallback, both-family LAN/router combinations and retained established sessions. |
| 5. Connected/custom/dynamic bypass | `test-nft-route-snapshot.sh`, `test-nft-packets.py`, `test-nft-routing.py`; bypass-protocols, local-bypass and `dynamic-routing-native-2026-11-03` | Exact marks, producer transactions, local addresses and real routed add/remove transitions. Fixed SNAT/IPv6 continuity and MASQUERADE retirement/reconnection are separately verified. Physical provider filtering remains open. |
| 6. Special traffic | `test-nft-packets.py`; `special-traffic-1.1.11-2026-11-03` and the later complete packet suite | LAN/WAN multicast, reserved/broadcast, IPv6 control traffic and ordinary boundaries. |
| 7. Interface lifecycle | `test-nft-hotplug.sh`, `test-nft-lifecycle.sh`; native availability/device/alias profiles in `NFT_PARITY.md`, plus current package pause/wait/resume | Virtual unavailable/late interfaces and stable workers covered. Physical cable/provider events remain open. |
| 8. Route synchronization | `test-nft-routes.sh`, `test-nft-default-route.sh`, `test-nft-nexthop.sh`, `test-nft-rtmon*.sh`, `test-nft-routing.py`; `shutdown-final-1.1.15-2026-11-03`, route-burst/overflow records | Actual FIB/nexthop/group/withdrawal checks, finite bursts and lost-notification recovery. Sustained production throughput remains open. |
| 9. IPv6 source choice | `test-nft-common.sh`, `test-nft-tracker.sh`; DHCPv6 acquisition/bridge/RA and delegated-prefix expiry records | Actual direct/PD-only sources, address replacement and bound traffic. Physical ISP behavior remains open. |
| 10. Source routing | `test-nft-routes.sh`; `source-routing-1.1.9-2026-11-02` and its source-routing=0 reference | Both configuration modes, IA_NA/IA_PD and PD-only real FIB/client traffic; provider main routes retained. |
| 11. Policy selection | `test-nft-policy.sh`, `test-nft-packets.py`, `test-nft-routing.py`; complete native packet/routing records | Family tiers, invalid/duplicate/disabled members, empty fallback, real weighted two/three-member selection. |
| 12. Sticky | `test-nft-packets.py`, `test-nft-routing.py`; balanced-TCP, TCP-rules, ingress and overlapping-rules records | Both-family fresh/established refresh, idle expiry, failure/recovery, weight/metric changes and overlapping first-match rules. Flow offload must be disabled. |
| 13. Rule matching | `test-nft-packets.py`, `test-nft-routing.py`; bypass-protocols, TCP-rules and native-set-types records | Positive/negative protocol, ports/ranges, devices, CIDRs, order/logging and typed sets. GRE/ESP classification is covered; tunnel interoperability is not claimed. |
| 14. DNS sets | Native `vm-dns-sets-2026-10-31.sh`, `vm-dns-options-2026-10-31.sh`; full-ruleset-recovery record | Actual dnsmasq population, timed/untimed behavior and reload/repopulation. Untimed elements do not expire merely because DNS TTL elapsed. |
| 15. Tracking methods | `test-nft-tracker.sh`, `test-nft-sockopt.sh`; native optional-probe profiles and `cross32-native-final-1.1.9-2026-11-02` | Actual ping, ARP, HTTP/HTTPS, Nping ICMP/TCP/UDP and DNS; family/binding/options checked. Reachable controlled IPv6 responders used. |
| 16. Tracker state machine | `test-nft-tracker.sh`, `test-nft-common.sh`, `test-nft-status.sh`; `status-apk-final-1.1.16-2026-11-03` | Threshold/output/score fixtures plus real faults/signals and installed pause/wait/resume. Numeric quality boundary cases use controlled tool output. |
| 17. Recovery probes | `test-nft-recovery.sh`, `test-nft-tracker.sh`; cross32 lifecycle and IPv6-disabled records | Offline bound DNS/hostnames and intended-device/source counters; ordinary failed-WAN marks remain isolated. |
| 18. Reconnect cleanup | `test-nft-cleanup.sh`, `test-nft-routing.py`; complete native routing records | Actual scoped both-family UDP/ICMP cleanup, preserved other-WAN sessions and retry/failure fixtures. |
| 19. Service lifecycle | `test-nft-processes.sh`, `test-nft-lifecycle.sh`, `test-nft-identity.sh`; cross32 lifecycle, shutdown and current APK records | Real restart/TERM, PID/start identity retirement, lock/ownership handling and stopped restoration. |
| 20. Notifications | `test-nft-hotplug.sh`, `test-nft-lifecycle.sh`; `shutdown-final-1.1.15-2026-11-03` | 22 installed events, exact arguments, background-child survival, released lock and shutdown suppression. |
| 21. CLI | `test-nft-cli.sh`, `test-nft-status.sh`; CLI source record and `guide-roundtrip-final-1.1.17-2026-11-03` | All twelve commands and 34 source-trial invocations pass. Actual 1.1.17 APK rejects malformed ifup/ifdown without changing stopped runtime/map; full guide restoration passes. |
| 22. Generic use | `test-nft-cli.sh`, `test-nft-sockopt.sh`; native optional probes and cross32 socket/resolver records | Real dynamically linked commands; family/source/device/mark, descriptor reuse/duplication and resolver behavior. Static/privileged-loader limitations follow the documented preload model. |
| 23. RPC/LuCI | `test-nft-rpc.sh`, `test-nft-diagnostics.sh`, `test-nft-ui.js`; private HTTP ACL checks and current APK record | Actual RPC/HTTP permissions, JSON and installed status verified. Interactive browser testing remains unavailable. |
| 24. Installation/upgrade | `test-nft-installer.py`, migration/feed/packaging tests; SDK/APK/guide, raw-staged, `raw-rollback-native-2026-11-03` and `published-feed-1.1.17-2026-11-04` records | Raw preparation, success/retry and handled rollback pass in stated profiles. Exact 1.0.13/1.1.17 install/rollback/reinstall, config and worker/probe checks pass. Production feeds and a native production-key upgrade verify. |
| 25. Firewall coexistence | Full-ruleset-recovery and flowtable records | Native fw4 reload and explicit full-flush recovery covered. Actual software offload demonstrates why packet-driven refresh requires offload disabled. |
| 26. Compatibility | Current three SDK records, cross32 native/lifecycle, PPPoE/bridge/VLAN/DHCPv6 and IPv6-disabled profiles | Standard 25.12 images only; primary 25.12.6/nftables 1.1.6. Current ARMv7/MIPSel APKs build; earlier native helper proofs retain identical helper payloads. R5S/DSA/load acceptance remains open. |

The three 1.1.16 payload changes affect shared tracking status, the CLI interface
report and RPC serialization. The map verifies that the routing/rules engine
outside that report is byte-identical to the native-tested 1.1.15 source, and
common helpers outside the pause detector/unused constant are unchanged. The
retained 1.1.16 SDK record binds its 74 package inputs; shell/UI/packaging gates pass.
The current CLI repair is built and exercised from the delivered 1.1.17 APK.
Earlier evidence retains its actual version and fixture limits rather than being
relabeled as a complete 1.1.16 hardware run.

## Remaining acceptance

1. Physical R5S WAN failover/recovery, interactive LuCI and sustained hardware/load
   validation remain separate acceptance gates. Browser access is disabled and
   the user has not tested this candidate on the R5S.
2. Public GitHub transport from the physical router and combined NFT/QoS load
   remain unverified. Production CI, signing and feed publication are complete;
   the signed-index upgrade is verified through the synthetic VM HTTP bridge.

No rewrite is required by the findings to date. Repairs stay in the responsible
shared layers, with explicit migration for native sets and scoped cleanup.
