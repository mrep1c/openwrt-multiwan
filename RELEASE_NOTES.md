# Release Notes

## Unreleased

- MultiWAN NFT 1.1.17 builds and verifies on AArch64, ARMv7 and MIPSel with the
  malformed CLI argument repair. All 74 package inputs match the retained SDK
  record. Only the backend CLI payload changes from 1.1.16; engine, helper,
  Nping and LuCI payloads are unchanged. Exact delivered install/rollback/reinstall
  passes published 1.0.13/1.1.17, with config/hooks, WAN probes, weights and eleven
  modern file hashes preserved. Packaged malformed CLI arguments return 2 without
  recreating stopped runtime or changing its map. Twelve workers retire and all
  28 original targets plus the original 1.1.16 stopped baseline restore.
  Physical/manual/load acceptance and production publication remain pending.

- Adds actual routed dynamic-bypass add/remove checks for LAN/router TCP/UDP.
  Fixed SNAT and IPv6 retain identity; standard MASQUERADE egress changes retire
  old state, with retry/reconnection verified separately. Focused and complete
  native routing passes each cover twelve combinations, 66 successful observations
  and four MASQUERADE retirements. No routing-engine change is required.

- Journals raw-installer file/link, migration-backup and provenance changes before
  application, restoring them on handled failures and interruption. Failed
  requested backend startup restores prior enabled/running state; unsuccessful
  restoration returns failure with retained private backups. Scopes the private
  umask to staging so fresh live directories keep caller permissions. Expanded
  both-shell tests and all four CI steps pass, including explicit HUP rollback.
  Native rename and hangup controls verify
  exact 28-file rollback with stable workers/probes, successful retry and six
  retired identities. New packages and physical/manual acceptance remain open.

- Prepares every raw-installer download and permission before changing live files,
  legacy config names or upgrade provenance. An actual failed second download
  reproduces partial replacement in the old script. Both-shell all-component,
  fresh/existing, retry, migration, dependency and signal regressions pass; the
  existing shell gates and added raw CI step pass. Native all/main/luci/repeat and
  rejected preparation preserve current source/config/probes and worker identity.
  Nine workers retire and all 28 original files plus the stopped baseline restore.
  Local deployment/rollback faults, new APKs and full acceptance remain separate.

- Fixes malformed CLI ifup/ifdown initializing mutable runtime before returning
  usage errors. Existing argument checks now precede initialization inside each
  command. Focused old/fixed ash/dash regressions and full existing shell gates
  pass. A reversible native source trial passes all twelve advertised commands
  and 34 invocations, including argv/exit behavior, bound probes, pause/resume,
  restart and stopped reports. Six worker identities retire; original source,
  startup/config/map/root rules/world/netifd restore. Holds frozen 1.1.16 pending
  a new build; no new APK or publication is implied by this source repair.

- MultiWAN NFT 1.1.16 fixes live paused/waiting trackers reporting active, restores
  the RPC `tracking` field and consistent `running` flag, and stops CLI treating
  intentionally absent paused-interface routes as an error. Stale tracker metadata
  still reports down and does not hide routing checks. Three focused regressions
  fail on 1.1.15 and pass in ash/dash. Full shell/UI/packaging checks, three SDKs and
  actual 1.1.15-to-1.1.16 APK integration pass with preserved config/comments/hook,
  both bound probes and installed pause/wait/resume behavior. Only three backend
  payloads change; packet/routing engine and helper/Nping/LuCI contents stay
  unchanged. The separate controlled-test bundle includes seventeen rollback
  baselines. Physical/manual and full audit acceptance
  remain open; no push or publication occurred.

- Accounts for all 142 upstream declarations/generated resolver helpers, including
  the legacy migration callback outside the eight runtime modules, and
  reconciles their responsibilities with 26 behavioral contract groups, retained
  tests and explicit acceptance limits. Separately verifies the unchanged 1.1.16
  guide's exact install/rollback/reinstall using published 1.0.13 and current APKs;
  configuration/comments/hook, WAN weights, ten installed files and twelve retired
  workers pass. The exact stopped baseline, APK world and network-manager identity
  restore. Current raw installation, complete installed CLI dispatch,
  physical/manual/load acceptance and production publication remain open.

- Verifies 24 IPv4/IPv6 dynamic-bypass packet cases and 25 fresh protocol-selector
  cases on unchanged 1.1.15, including GRE/ESP names/numbers and IPv6 hop-by-hop
  headers. Both complete packet runs retain the original assertions; the final
  run proves protocol packets enter without saved WAN marks. Adds the native
  dynamic producer migration/lifecycle contract and verifies its exact example,
  failed-update atomicity, empty unions and repopulation. Packages and delivery
  are unchanged. Tunnel interoperability, physical/manual and full acceptance
  remain separate.

- Verifies fresh TCP/443 sticky affinity with two eligible WANs in both families.
  After initial equal-weight selection, policy weights favor the other WAN 1000:1;
  all twenty-four distinct fresh connections retain affinity and correct conntrack
  marks. The complete focused TCP test passes after a three-line temporary-address
  cleanup correction, with both phases retained. Packages and delivery are unchanged.

- Verifies the exact delivered install, rollback and reinstall instructions using
  real published 1.0.13 and current 1.1.15 APKs on a disposable stock OpenWrt VM.
  Configuration/comments/hooks, policy weights, both WANs and installed source
  checks pass; legacy rollback removes the socket helper. Twelve recorded workers
  retire, and the exact original stopped baseline and APK world restore. The
  existing delivery is unchanged. Other rollback baselines, physical/manual
  acceptance and production publication remain open.

- Adds real IPv4/IPv6 TCP/443 affinity proof: active refresh, expiry during UDP/443
  traffic, recreation by the established connection and metric changes preserving
  old TCP/NAT identity. TCP/UDP separation, port lists/ranges, source devices,
  source/destination CIDRs and canonical ICMP selectors pass. A concurrent framed
  TCP/UDP test helper and the complete extended native routing suite pass on
  unchanged 1.1.15 APKs. Broader physical/manual acceptance remains open.

- Adds 24 native IPv4/IPv6 special-action cases covering direct rules and empty
  policy fallbacks for LAN/router UDP, exact marks and established WAN/NAT
  continuity. The complete extended routing/NAT suite passes on unchanged 1.1.15
  packages. Differential packet capture identifies an initial test-client issue:
  soft ICMP errors require the Linux UDP error queue. No runtime or APK change is
  needed; physical/manual and other acceptance gates remain open.

- MultiWAN NFT 1.1.15 permits clean stop when an offline/disabled WAN has an
  ownership record without a kernel FIB table; genuine flush failures still
  report failure. Holds the unreleased 1.1.14 candidate. Full shell/UI/packaging,
  all three SDK builds, actual 1.1.14-to-1.1.15 upgrade, installed notifications,
  both-family absent-table checks and stock-kernel packet/routing assertions pass.
  A routing namespace-holder timeout is retained and qualified separately; final
  assertions are unchanged. The controlled-test bundle has sixteen exact rollback
  baselines. Physical/manual acceptance, production publication and full parity
  remain open.

- MultiWAN NFT 1.1.14 includes kmod-nft-fib in the dependency repair command and stops LuCI defaults from writing an unused option or committing valid existing configuration. Missing globals still initialize. Actual 1.1.13-to-1.1.14 installation preserves configuration/comments; installed repair and private real-UCI pending-edit tests pass. Three SDKs, complete ash/dash gates, UI and packaging checks pass. Only init/defaults payloads change from 1.1.12. The 50-file controlled-test bundle retains fifteen rollback baselines. The held 1.1.13 test build exposed the conffile defect and was never published. Physical/manual acceptance, production CI/signing and full parity remain open.
- Native both-family software flowtable testing now verifies the documented sticky boundary on the unchanged packet engine: replies continue during real offload while affinity expires, then same-flow refresh recovers after removal. Offload must remain disabled for packet-driven refresh. Hardware offload/DSA/load are unverified; no automatic firewall changes or offload support are added.

- Narrows SDK package selection while retaining required dependencies, target settings and signing configuration. Exact OpenWrt 25.12.6 builds reduce kernel-module APK packaging from 922 to 21 on AArch64, 889 to 47 on ARMv7 and 892 to 31 on MIPSel; every backend/helper/Nping/LuCI APK remains byte-identical to frozen 1.1.12. The shared selector is used by feed CI and the documented SDK build. Production-key CI execution remains unverified.
- Final 1.1.12 also passes a fresh standard-kernel boot with IPv6 disabled: real socket rejection, IPv4 probes/DNS, routing/default recovery, failover, fw4 reload, worker restart and read-only CLI/RPC. Independent raw-evidence checks and exact stopped-baseline restoration pass. The diagnostic serial-format failure and successful resume remain qualified separately; no product change is needed.

- MultiWAN NFT 1.1.12 uses the native kernel FIB to keep new unmarked router-local connections out of WAN policy selection, including peer-only IPv4 and IPv6 no-prefix-route addresses. Incoming WAN reply identity remains intact; address changes need no copied local-route state. APK and raw installers declare kmod-nft-fib. Three SDK builds, packet/routing tests and the full shell retry pass. Actual upgrade and eight native local/address-change cases verify replies, cached-affinity bypass and QoS fields. A separate 44-file controlled-test bundle includes thirteen rollback baselines. The frozen 1.1.11 bundle is held. Physical/manual acceptance and full parity remain open; no push or publication occurred.

- MultiWAN NFT 1.1.11 extends the existing IPv4 bypass from multicast /4 to 224.0.0.0/3, keeping reserved IPv4 and limited broadcast out of WAN policy selection. The full packet suite covers LAN/WAN special traffic, IPv6 control types, ordinary boundaries and unrelated marks. Three SDK builds and actual native 1.1.10-to-1.1.11 installation pass, including broadcast/reserved/multicast boundaries and both-family sticky replies. A separate 41-file controlled-test bundle includes twelve rollback baselines. The frozen 1.1.10 bundle is held. Physical/manual acceptance and full parity remain open; no push or publication occurred.

- MultiWAN NFT 1.1.10 excludes WAN-originated traffic from client sticky refresh while preserving conntrack reply routing. Ingress guards follow installed devices and survive atomic user-rule rebuilds without requiring netifd. Both-family packet, routing/NAT, shell, UI and packaging regressions pass. Three SDK builds match current sources, and actual native 1.1.9-to-1.1.10 installation preserves configuration and passes both-family reply/sticky checks. A separate 38-file controlled-test bundle includes eleven rollback baselines. The frozen 1.1.9 bundle is held, and no push or public feed update occurred. Standard OpenWrt 25.12 images are the supported scope; custom kernels built without IPv6 are excluded. Physical/manual acceptance and full parity remain open.

- MultiWAN NFT 1.1.9 accepts address sets declared with `typeof` as well as `type`. The shared check asks nftables for the expression's datatype, covering IPv4/IPv6 payload and connection address selectors. Wrong-family, non-address and compound sets remain rejected without changing their contents or replacing working rules. Runtime changes are limited to external-set validation; LuCI changes only its package version.
- Final 1.1.9 passes all three SDK builds, the packet regression, 15 native OpenWrt set-type cases and an actual 1.1.8-to-1.1.9 APK upgrade with unchanged configuration. Package payload checks limit the runtime change to the backend core; helpers, hooks, Nping and LuCI remain byte-identical to final 1.1.8. A separate 35-file AArch64 controlled-test bundle includes ten rollback baselines. Physical/manual acceptance and full parity remain open. Further stock network-manager crash analysis and experimental platform patching are skipped at the user's request.
- MultiWAN NFT 1.1.8 applies the selected address family during hostname resolution in the shared socket helper. A dual-address DNS-server hostname could select IPv6 and fail an IPv4 tracker even when its IPv4 server was healthy. Resolution now selects the requested family for tracking and generic `use`. Explicit numeric interface-address conversion remains available to Nping; socket source/device/mark/family checks still reject incompatible traffic. LuCI changes only its package version.
- Final 1.1.8 passes all three SDK builds, native both-family DNS/Nping and a real reboot after a stopped-1.0.13 unknown-history refusal. The reboot clears old kernel connection state and automatically starts reordered WAN identities; the original configuration and stopped baseline restore. Independent archives, exact payload checks and a 32-file controlled-test bundle with nine rollback baselines are retained. Physical/manual acceptance, remaining platform/topology cases and production publication remain open.
- Documents complete recovery after explicit full nftables ruleset loss: restore fw4 before MultiWAN, restore separately managed set definitions, and repopulate DNS sets. Native 1.1.7 passes normal reload preservation and full-flush recovery with actual IPv4/IPv6 client NAT, DNS sets, stable routing identities and retained WAN/QoS marks. No routing runtime change is required. After restoring a clean daemon/client baseline, the fixture passes with explicit interface shutdown; earlier netifd teardown crashes and physical/manual acceptance remain open.
- MultiWAN NFT 1.1.7 records upgrade provenance before replacing package or raw-install files. Startup refuses to reuse WAN IDs when an existing installation has lost both its saved map and live routing mask; reboot clears its unidentifiable old connection marks. A native stopped-1.0.13 upgrade reproduced stale WAN-mark reuse in 1.1.6. Focused ash/dash checks, all three SDK builds, running-1.0.13/final-1.1.6 upgrades, stopped-legacy refusal/recovered-ownership and stopped-modern reorder pass. A 29-file controlled-test bundle includes eight rollback baselines. Broader final-1.1.6 evidence remains recorded separately; physical/manual acceptance and production sign-off remain open.
- Coalesces queued ordinary source-route bursts through the monitor's existing bounded drain and full reconciliation. Native 256-route-per-family stress exposed serial notification backlog; the real-loop regression, complete native addition/update/withdrawal stress, final SDK builds and installed-package checks pass. Archived interim 1.1.6 APKs contain only the preceding tracker repair.
- MultiWAN NFT 1.1.6 refreshes an expired cached IPv6 tracker source through the existing metadata-refresh path when a usable replacement exists. Overlapping delegated-prefix expiry reproduced the stale binding while routing and a fresh bound command already used the surviving source. Focused regressions and installed-package automatic recovery, old-default withdrawal and cleanup pass. Actual 1.0.13/1.1.5 upgrades, a signed-feed upgrade and HTTP administrator/read-only API checks pass. The controlled router-test bundle includes seven rollback baselines. Physical acceptance, interactive LuCI and full parity remain open; frozen 1.1.5 APKs do not contain these later repairs.
- MultiWAN NFT 1.1.5 repairs sticky refresh, active failover membership, weighted selection, mark preservation, route synchronization, scoped connection cleanup, and IPv6 source/default handling. Policy and user-rule updates retain the previous rules on failure. Package validation and remaining gates are recorded in the parity notes.
- Normalizes route-notification whitespace against policy-table snapshots so actual IPv4/IPv6 withdrawals remove stale copied routes. Deleted defaults use provider-aware reconciliation, preserving a still-declared recovery gateway and removing genuinely withdrawn defaults. Combined native IPv4-only and IPv6 checks include real bound traffic through the retained default.
- Ignores repeated stop signals while the route monitor completes bounded child and workspace cleanup. Native MIPSel validation reproduced a second TERM aborting cleanup; the retained regression holds the child during termination and verifies that repeated TERM still removes the owned workspace. Earlier candidate bundles remain unchanged.
- Prepares a changed routing mask without publishing it until connection protection succeeds. Failed base replacement restores the old cache, and new worker definitions follow successful base loading. Rejected startup now returns failure through the service callback instead of reporting success; native fault/retry checks cover guard creation, cache publication and atomic base replacement.
- Reports a clean stopped state without treating absent routing objects as failures. Disabled-interface labels and retained-protection warnings remain visible. A checked hook inventory avoids false running state from foreign chain names; active inventory/table/member/set/rule failures remain errors instead of disappearing in reporting pipelines.
- Makes CLI reports and bound commands initialize without writing routing runtime. Startup explicitly applies the current UCI mask, while queries, workers and cleanup retain the applied mask. Inactive hotplug events exit before initialization; failed configuration loads stop initialization. Mask/capacity validation precedes runtime publication, preserving existing state on rejection. This repairs a native-reproduced cold query/cache sequence that silently ignored a later mask edit.
- Keeps complete multipath routes together, filters grouped nexthops to each WAN, combines equivalent gateway paths and preserves relative weights. Canonical route identities prevent needless replacements and stale deletion after kernel normalization. Bounded notification batching and observed nexthop dependencies avoid repeated full snapshots for unrelated families. See the parity notes for remaining validation and weight limits.
- Keeps stopped-service LuCI diagnostics read-only: set listing and rule/route inspection no longer initialize routing runtime state. Diagnostic probes load configuration explicitly and stop if that load fails.
- Adds the target-built `multiwan-nft-sockopt` dependency for bound probes and generic `use`, DNS health checks, corrected tracker parsing, family-aware status/diagnostics, and read-only LuCI permissions.
- Adds OpenWrt 25.12.6 APK feeds for `aarch64_generic`, `arm_cortex-a7_neon-vfpv4`, and `mipsel_24kc`, with parallel SDK builds and automatic architecture selection. Existing OPKG releases are frozen. Native sets replace legacy ipset/DNS integration; see the install guide for migration and runtime limits.
- Adds retained shell, socket, packet, routing/NAT, UI, migration, and package regressions. Physical-router acceptance and signed feed publication remain separate release gates.
- Preserves shutdown device information for tracked and untracked WANs, removes affected old conntracks before reusing interface IDs, and records route-monitor ownership so cleanup leaves unrelated processes alive. Status queries no longer make a stopped service appear running.
- Interprets legacy connection-recovery settings without rewriting user configuration. Real OpenWrt ARM64 VM checks cover package installation/reinstallation, procd restart, bound probes, recovery, untracked notifications and fw4 reload.
- Keeps workers supervised during package upgrades, refreshes workers when their code/configuration changes, and validates installed runtime files instead of reading APK's incomplete transaction database during first installation.
- Honors DNS probe timeout/retry settings, reloads rpcd after package installation/removal, and displays stopped and transitional states correctly in both status views. Adds an optional Nping 7.992 package for IPv6 probing and permits metadata-only socket creation while retaining traffic-family checks.
- Installs the LuCI diagnostics helper as executable and grants read-only sessions the RPC method needed for safe diagnostics while denying WAN/UCI mutations. Manual interface down now pauses tracking until explicit up; metadata updates preserve the pause and the latest down signal cancels a pending up signal.
- Maps dynamic family aliases to their configured logical WAN for hotplug and user hooks. Routes, source-interface rules and status follow the active alias device; replaced devices lose stale defaults. Disabled WANs report disabled without treating missing owned rules as errors.
- Blocks retired connection marks during live interface-ID/mask changes so old rules cannot recreate purged sessions before reassignment. Failed interface/route/set/rule setup leaves the guard active; successful startup or service stop removes it. Unaffected WAN/family sessions remain intact in packet/NAT tests.
- Reports incomplete routing configuration in CLI and both LuCI status views while preserving WAN health state. CLI/RPC uptime uses the active family alias, RPC link state follows that alias, enabled values follow UCI boolean semantics, and configured-disabled WANs report Disabled.
- Serializes route-monitor population and events with service updates, and refreshes cached interface IDs only after the applied map is committed. Live IPv4/IPv6 interface reorders no longer let an old monitor copy backup defaults into a reassigned primary table; unapplied UCI order stays separate from live routing.
- Subscribes to route notifications before the initial snapshot and verifies the owned socket's family subscription. Initial reconciliation refreshes route sets and removes stale copied routes; concurrent IPv4/IPv6 add/delete notifications remain queued. Monitor children explicitly close inherited service-lock descriptors.
- Recovers from live route-notification errors, including netlink queue overflow, by replacing the affected child stream and reconciling routes/sets within the same supervised parent. Repeated recovery retains applied IDs across unapplied UCI edits and does not exhaust procd crash retries.
- Removes obsolete same-device default gateways and metrics while retaining provider-declared recovery defaults without deleting them. Explicit provider withdrawal clears stale defaults; missing or malformed provider status stops cleanup. Handles multiple IPv6 source selectors, device-only defaults and canonical route whitespace.
- Fixes NFT route copying for dead/linkdown flags, static QoS IP set overlaps, redirected QoS logging, and duplicate Hybrid CAKE overhead when parent STAB is active.
- Uses unique inline-rule scratch files, adds NFT route and QoS regression checks to compatibility CI, and updates the active build SDK to OpenWrt 25.12.6.
- Adds an Adaptive start/idle-rate selector for the existing 1000 kbit/s baseline and a new 1500 kbit/s baseline, raises demand headroom from 200 to 300 kbit/s for both choices, and retains the 25% link cap and fixed finite-queue profile.

## v1.0.27

- Adds Auto, Manual, and supervised Adaptive realtime reserve modes for HFSC/Hybrid.
- Corrects BFIFO, PFIFO, RED, NETEM, and QFQ child queue budgeting, including the ineffective burst/minimum calculations.
- Prevents broadened private-LAN IFB fallback rules and fixes software-flow-offload ctinfo priority ordering.
- Removes tracker-triggered QoS qdisc rebuilds so health checks follow normal hysteresis without disrupting traffic.
- Reports hardware firewall flow offload as degraded compatibility while continuing startup.

## v1.0.26

QoS realtime freshness tuning.

- Corrects Hybrid HFSC default/bulk link-sharing curves so both service-curve segments exactly match their parent rate, preventing saturated IFB queues from becoming stuck.
- Rejects Hybrid realtime rates that reach or exceed the internally shaped parent instead of creating an invalid class tree.
- Replaces the visible `MAXDEL` control with `Realtime Freshness` presets plus a custom target.
- Adds qdisc-aware sizing so PFIFO, BFIFO, RED, QFQ children, NETEM fallback, and slow-link fq_codel target capping derive from the freshness target.
- Keeps `PACKETSIZE` as the manual PFIFO average packet size input and removes the unused packet-size selector.
- Migrates existing `hfsc.MAXDEL` values to `hfsc.freshness_mode='custom'` and `hfsc.freshness_target_ms` to preserve current router behavior on upgrade.
- Keeps standalone DRR independent of freshness because it no longer has child qdisc queues.

## v1.0.17

QoS DRR game queue feed release.

- Exposes DRR as a selectable HFSC/Hybrid game queue discipline in LuCI.
- Adds `kmod-sched-drr` to QoS package and runtime dependency checks.
- Leaves QFQ hidden because OpenWrt does not package it as a normal scheduler module.

## v1.0.16

QoSmate audit follow-up and feed release.

- Adds optional pure CAKE multi-queue support through `USE_MQ` and `cake_mq`, with automatic fallback to plain CAKE.
- Recognizes `cake_mq` in status and LuCI statistics while keeping Hybrid mode on plain CAKE child qdiscs.
- Cleans the shipped default config around interface sections, supported tuning defaults, and CAKE option clarity.
- Makes `auto_setup` target a specific OpenWrt network instead of assuming only `wan`.
- Improves status and health output for multi-WAN interface sections and removes stale single-WAN fallbacks.
- Removes the unused `multiwan_qos_id2mask` helper.

## v1.0.15

Security, routing, and feed-release hardening for the MultiWAN package set.

- Fixes stored-XSS risk in QoS custom-rule validation rendering.
- Tightens QoS LuCI ACLs so read-only users no longer get restart, shell, nft, or root-script write powers.
- Validates QoS agent API keys before rate limiting, so invalid keys cannot exhaust authenticated request slots.
- Makes NFT policy generation metric-aware per address family and adds family guards to prevent cross-family marks.
- Narrows NFT stop cleanup to owned tables/rules and hardens early status reads.
- Repairs raw installers, removes placeholder stats RPC/UI calls, updates docs, and improves release asset replacement.

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
- Keeps pure CAKE, HFSC, HTB, link-layer presets, and realtime queue sizing unchanged.

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
