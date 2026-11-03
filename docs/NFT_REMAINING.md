# Remaining parity investigation

These are open checks and explicitly identified unresolved failures. The main
acceptance contract remains [NFT_PARITY.md](NFT_PARITY.md). Do not declare full
parity from the completed repairs or the current test count.

**Current checkpoint: 1.1.17 passes controlled software acceptance.**
All three SDK targets and LuCI verify against 74 current package inputs. Only the
backend CLI payload differs from 1.1.16. The raw-installer handled rollback gap
and routed dynamic-bypass gap are covered by the records below.

Routed bypass passes focused and complete native routing runs (`64084a:0`): twelve
LAN/router TCP/UDP combinations per run, 66 successful observations and four
MASQUERADE retirements. Fixed SNAT and native IPv6 preserve established identity;
Linux MASQUERADE retires state when egress changes, requiring UDP retry or TCP
reconnection. Exact FIB/marks/QoS/NAT/conntrack IDs and original baseline restore
are verified. Both failed continuity assumptions are retained, not relabeled as
product regressions. The record is `diagnostics/dynamic-routing-native-2026-11-03/`.

The exact 59-file delivered guide passes install, rollback and reinstall between
published 1.0.13 and 1.1.17 (`cd6e66:0`), including eleven modern file hashes, both
bound probes, raw config/comments/hook, 4:1 weights and twelve retired workers.
Packaged malformed CLI arguments return 2 without recreating stopped runtime or
changing the map. All 28 original targets, original 1.1.16 packages and stopped
world/config/map/root rules/netifd baseline restore. Evidence is retained under
`diagnostics/guide-roundtrip-final-1.1.17-2026-11-03/`.

Remaining: physical R5S WAN/provider/DSA/load and manual LuCI acceptance;
production signing and publication. Local unsigned APKs are ready for controlled
LAN-connected testing. Earlier checkpoints below retain their historical limits.

**Handled raw file-application rollback now passes.** The restore journal saves
original files/links, legacy migration names/backups and provenance before writes.
Error/HUP/INT/TERM restores those paths and removes the active temporary file. Failed
requested startup restores prior enabled/running state when recovery succeeds;
failed restoration returns failure and retains private backups. Fresh directory
tests expose staging's private umask leak; final source restores the caller's
umask while retaining private staging/journal permissions. Both-shell coverage
and all four final CI steps pass. The SIGHUP failure control exposes a skipped
cleanup trap, now repaired explicitly. Six old-source controls fail as expected
across both shells. Native rename and hangup controls preserve running
worker identities and probes on rollback, then pass exact-source retry. All 28
original files, startup/config/map/world/root rules/netifd and the stopped profile
restore; six recorded workers retire. Independent verification passes (`8b0ba8:0`),
retained under `diagnostics/raw-rollback-native-2026-11-03/`. Power loss/SIGKILL and
persistent unwritable storage are outside automatic recovery. Routed dynamic
bypass, rebuilt release artifacts and physical/manual/load acceptance remain open.

**Preceding raw-installer preparation proof.**
An actual second-download 404 replaces init and leaves a marker in the old script;
the regression also shows legacy filenames moving before failure. All selected
files and modes are now prepared privately before live changes. Both-shell tests
cover main/all/luci, fresh/existing installs, repeats, config migration, dependencies
and signals; complete existing shell gates plus the new raw CI step pass. Native
all/main/luci/repeat and rejected preparation with running WANs pass, preserving
five source/config/probe stages and workers across LuCI-only/failure. Nine worker
identities retire; all 28 original files and startup/world/map/root rules/netifd
restore. Independent archive verification passes (`fa03ce:0`), retained under
`diagnostics/raw-staged-native-2026-11-03/`. The first red fixture's missing stat
command and exact ls correction are qualified separately. This is preparation
preservation; the newer journal record above covers handled local-write rollback. Rebuilt packages,
routed dynamic-bypass sessions and physical/manual/load acceptance remain open.

**Hold frozen 1.1.16-r1 for the unreleased CLI validation repair.** The native
command sweep reproduces missing-ifup and extra-ifdown returning usage error 2
after creating routing runtime and publishing its mask. Initialization now runs
after the existing argument checks. Focused old/fixed regressions pass their
expected red/green outcomes in ash/dash; all existing CI shell gates pass.
Exactly the CLI file differs among the 74 previously validated package inputs.
The full native temporary-source sweep passes all twelve advertised commands and
34 invocations, preserving argument/exit behavior and normal pause/resume/restart.
Six worker identities retire; exact original source, startup flag, config/map,
root rules/world/netifd and stopped state restore. The first repaired trial's
uptime-format assertion is corrected without changing product code; both phases
are retained. Rebuilt package/delivery proof remains pending alongside raw
installation and routed dynamic-bypass session acceptance.
Independent native verification passes (`a197f6:0`); the source/CI/native record is
`diagnostics/cli-dispatch-fixed-source-1.1.16-2026-11-03/`. Frozen 1.1.16 delivery
archives remain unchanged and do not include this repair.

**The preceding 1.1.16-r1 status repair remains verified; hold 1.1.15.**
Function reconciliation finds the old pause detector still looking for a legacy
long sleep. Live disabled/waiting trackers instead use a short retry wait, so CLI
and RPC falsely report active/running. RPC also omits upstream's `tracking` field,
and CLI reports intentionally absent paused-WAN objects as routing error (48).
The complete narrow repair passes three red/green regressions in ash/dash and
actual native pause/wait/resume checks. Stale metadata still reports down and does
not bypass routing checks. The intermediate partial source test, complete native
source proof and corrected LuCI version-metadata gate are retained separately.

Full CI shell/UI/packaging and three SDK builds pass; only three backend payloads
change. Packet/routing-engine code and helper/Nping/LuCI contents remain unchanged.
Actual 1.1.15-to-1.1.16 APK installation preserves configuration/comments/hook,
matches ten installed files, passes both WAN-bound probes, retires eight worker
identities and verifies installed CLI/RPC states. The stopped baseline restores
with genuine 1.1.16 packages retained (`5a8c08:0`). SDK, source and APK records are
`diagnostics/sdk-1.1.16-validated-sources-2026-11-03/`,
`diagnostics/paused-status-source-1.1.16-2026-11-03/` and
`diagnostics/status-apk-final-1.1.16-2026-11-03/`.

The 56-file controlled-test bundle includes seventeen exact rollback baselines;
its install/rollback blocks pass both-shell syntax checks (`7da91b:0`). Its exact
1.1.16 guide round trip now passes published 1.0.13 to 1.1.16, rollback and reinstall,
with exact config/comments/hook, both WANs/weights, ten modern source files,
twelve retired workers and restored root rules/world/map/netifd (`796806:0`). The
14-file frozen record is `diagnostics/guide-roundtrip-final-1.1.16-2026-11-03/`.
The unchanged bundle README predates that subsequent execution proof.

The [function/evidence reconciliation](NFT_FUNCTION_AUDIT.md) maps all 142 upstream
declarations/generated helpers to native replacements and the 26 contract groups.
This includes the 141 runtime functions/helpers and the legacy migration callback
found by scanning all fifteen upstream package files.
No literal upstream UCI read is missing from the scanned native modules. That
inventory is not behavioral proof. The newer complete CLI source trial closes
the command-dispatch execution gap; its release-package proof, current raw
installation and the stated dynamic-bypass routed-session limit remain software
acceptance work; finding and repairing the status defects does not close them.
The newer raw record above closes download-preparation and native success/retry
coverage; its local deployment/rollback checks remain separate.
Physical/manual/load acceptance and publication remain open. Nothing is pushed
or published.

**Dynamic-bypass packet contracts and the uncommon-protocol proof gap are now covered.**
The complete extended packet suite passes on unchanged 1.1.15, retaining every
original assertion. Twenty-four both-family dynamic cases cover add/remove,
established WAN/main decisions, WAN-source bypass and refresh/restart/repopulation
with exact skb/conntrack/QoS assertions. Twenty-five cases cover named/numeric
GRE/ESP, protocol 253, wrong-protocol controls and IPv6 hop-by-hop headers. The
final full run proves no saved WAN mark is restored before each protocol case;
both runs are retained. Invalid names preserve preceding rules. The documented
flat native producer API replaces list:set references with a maintained union;
its exact two-family example, rejected-batch preservation, empty unions and
repopulation pass separately. Independent verification passes (`fb39fa:0`);
the 26-file record plus manifest is
`diagnostics/bypass-protocols-final-1.1.15-2026-11-03/` (`283f1d:0`). Exact root
rules, source/config/map/netifd and the stopped baseline remain intact, with both
WANs up. Packages and delivery are unchanged. These packet cases do not prove
GRE/IPsec tunnels or end-to-end dynamic path changes under NAT. Full acceptance
reconciliation, sustained load, physical/manual checks and publication stay open.

**The explicit multi-member fresh-TCP affinity gap is now closed.**
Both-family TCP/443 clients start with two equal-metric, equal-weight eligible
WANs. After weights favor the other eligible WAN 1000:1, twelve distinct fresh
connections per family retain initial affinity and expected conntrack marks.
Actual policy rules, eligibility and cached elements are checked. The full
focused TCP function also passes its prior predicates/lifetime/metric/ICMP cases.
The initial temporary IPv6 alias changes a later ICMP source assertion; the final
test removes both aliases before ICMP. Both phases and their exact three-line
test-only difference are retained. Independent verification passes (`7c07d3:0`);
the 21-file record plus manifest is
`diagnostics/balanced-tcp-final-1.1.15-2026-11-03/` (`81d838:0`). Current source,
configuration/map/netifd/root rules and the stopped baseline retain their exact
state. Package inputs and delivery remain unchanged. Dynamic bypass traffic and
less-common protocol selectors were still open at that checkpoint; their packet
contracts are covered by the newer record above. Broader checklist reconciliation
and physical/manual/release acceptance remain open.

**The delivered-guide roundtrip gap for published 1.0.13 is now closed.**
The exact delivered install/rollback/install blocks pass real APK transactions
on stock 25.12.6, preserving configuration/comments/hook and recovering both WANs,
weights, workers and current source. The rollback removes the modern helper;
all twelve recorded worker identities retire at final cleanup. Exact original
config/map/source/root rules/netifd and APK world bytes restore. Independent
verification passes (`96061a:0`); the 14-file record plus manifest is
`diagnostics/guide-roundtrip-final-1.1.15-2026-11-03/` (`6d45cf:0`). The original
delivery remains byte-identical. A rejected launcher and corrected legacy-set
verification assumption are qualified in that record. Other held rollback
baselines, physical/manual acceptance and production publication remain open.

**The TCP/443 sticky and rule-predicate proof gap is now covered on unchanged 1.1.15.**
Real IPv4/IPv6 TCP streams refresh affinity beyond its timeout, idle entries expire
despite ongoing UDP/443, and the same TCP connection recreates the cache. Fresh
connections follow a new metric tier while established TCP/NAT identity remains
intact. Port lists/ranges, source-device and source/destination CIDR exclusions,
TCP/UDP separation and canonical ICMP selectors pass. The complete native routing
suite passes with the new stream-capable test helper. Raw/source/baseline checks
pass (`f1c7a7:0`); the 19-file record plus manifest is
`diagnostics/tcp-rules-final-1.1.15-2026-11-03/` (`47c5a5:0`). No package or runtime
change is needed, and the delivered archive is byte-identical. The TCP phase uses
one preferred member per tier; retained packet tests cover weighted affinity.
The broad sticky/rule, physical/manual and publication checklist items remain
separate from this specific native proof.

**Special-action software acceptance is now closed on unchanged 1.1.15.**
All 24 direct/fallback, default/unreachable/blackhole, IPv4/IPv6 and LAN/router UDP
combinations pass with exact routing/conntrack mark counters and retained existing
WAN/NAT sessions. The complete extended native routing/NAT suite passes afterward.
An initial test-client failure is not a runtime defect: the LAN capture records
correct ICMP network-unreachable replies with MultiWAN, an output bypass and the
kernel alone. The client must enable the Linux UDP error queue to observe soft
ICMP errors. A separate diagnostic quote-guard rejection is retained and qualified.
Independent raw verification passes (`42d8f3:0`), and the 25-file evidence record
plus manifest is `diagnostics/special-actions-final-1.1.15-2026-11-03/`
(`2437b4:0`). Product files, APKs and the existing 1.1.15 delivery archive are
unchanged. Its SDK snapshot predates these additional tests; all 74 package
inputs still match. Physical/manual acceptance and the other unchecked contract
items remain open.

November 3 preceding candidate: **1.1.15-r1 is now held for the status repair;
1.1.14 remains held.** The installed notification test reproduces stop
aborting on a disabled WAN's absent owned FIB table, retaining nft hooks/runtime.
Cleanup now accepts that specific absence and retains genuine flush failures.
The regression fails before repair (`a51613:1`); ash/dash focused and complete
shell gates, UI and packaging checks pass. Native empty-table checks cover both
IPv4 and IPv6. Three SDKs match all 74 package inputs; only core cleanup payload
changes from 1.1.14 (`785423:0`). Hooks/helper/Nping/LuCI payloads are unchanged.
The 129-file SDK record plus manifest is
`diagnostics/sdk-1.1.15-validated-sources-2026-11-03/` (`551c62:0`).

Actual 1.1.14-to-1.1.15 APK upgrade preserves raw configuration/comments and
both bound WAN probes. Installed hooks pass 22 exact events, tracked/untracked
actions, aliases, empty DEVICE, disabled IPv4/IPv6 interfaces, stopped-service
suppression, clean environment, released lock, background-child survival and
one shutdown event per online WAN. Direct consumer dispatch covers the action
matrix; real service startup/shutdown cover fanout. All 4 unique recorded worker
identities retire. Config/map/source, original WANs and netifd identity restore.

The full packet suite and all routing/NAT assertions now pass against installed
files on stock OpenWrt 25.12.6/kernel 6.12.112/nftables 1.1.6 in private network
namespaces. UCI/netifd inputs remain controlled. The initial routing harness's
five-minute namespace holder expires under CPU emulation; final routing changes
only that holder to a process waiting on its parent's stdin pipe. Assertions and
product files remain unchanged. Initial failure, exact one-line harness delta,
final success and retirement of all three recorded holders are checked
independently. Root ruleset/policy rules, config/map/source remain intact.

Frozen native evidence is `diagnostics/shutdown-final-1.1.15-2026-11-03/`.
The 53-file AArch64 bundle has sixteen exact rollback baselines and both-shell
guide checks. Physical R5S/PPPoE/DSA/load, interactive LuCI, additional provider
topologies, production signing/publication and full parity remain open. Flow
offload stays excluded from packet-driven sticky refresh. Nothing is pushed or
published.

**Previous candidate: 1.1.14 is held for the shutdown repair.**
Hold frozen 1.1.12 and the unreleased 1.1.13 test build. Two installation defects
are now corrected. The init dependency repair command omitted kmod-nft-fib even
though APK/raw installs declared it; the actual-function regression fails before
the fix (`6ae42a:1`) and passes afterward in ash/dash. Native installed functions
also pass missing-package, no-op and failed-install/lock cleanup with a harmless
APK fixture. The actual satisfied-dependency command leaves the APK world unchanged.

The LuCI bootstrap wrote unused local_source=none and committed a valid existing
configuration. The first actual 1.1.12-to-1.1.13 transaction succeeds but its
conffile gate fails (`211c5c:0`, inner result 1). The regression reproduces that
write (`5b7de7:1`). Real UCI in private config/delta directories proves the old
script also commits unrelated pending edits, while the fixed script preserves
raw config/comments and pending changes and still initializes missing globals
(`48f1d3:0`). This direct-script proof does not cover every other OpenWrt hook.

Complete 1.1.14 ash/dash gates, packaging and UI checks pass (`195787:0`,
`ca4361:0`, `59dea2:0`). Three SDKs match all 74 package inputs; only the init
dependency list and LuCI bootstrap payload differ from final 1.1.12 (`8ff69f:0`).
Core, hooks, helper binaries, Nping and UI view payloads are unchanged. The
127-file SDK snapshot is `diagnostics/sdk-1.1.14-validated-sources-2026-11-03/`
(`c49c9d:0`); held 1.1.13 remains frozen separately.

Actual 1.1.13-to-1.1.14 installation now preserves byte-identical configuration
and comments with local_source absent. Three worker identities stay supervised,
both WAN marks commit, and bound pings pass. All three unique workers retire on
stop; the original config/map, source hashes, two WANs and netifd identity
restore (`b5d99e:0`). Capture and independent verification pass (`6b97ec:0`,
`3d03f5:0`). The 22-file native record plus manifest is
`diagnostics/deps-final-1.1.14-2026-11-03/` (`cc5abb:0`). The new 50-file AArch64
bundle includes fifteen exact rollback baselines and both-shell guide checks
(`6499ac:0`). Physical/manual acceptance, production-key CI and full parity remain
open. Nothing has been pushed or published.
Final integrity checks cover current tested sources, all target dictionaries,
615 retained files, exact delivery/rollback bytes and the unchanged original
1.1.12 archive (`7a31b7:0`). The delivered identity/collector scripts also pass
strict exit-code and unchanged stopped-baseline checks (`5eb727:0`).

**November 3: native software offload boundary is now verified.**
Installed 1.1.12 uses the identical current packet engine in disposable namespaces.
Both families return 12/12 ordinary UDP messages and 22/22 messages spanning real
software offload and its removal. OFFLOAD conntrack status and actual flowtable
JSON prove the fast path. Normal counters are 8 ingress/8 core; the offloaded
snapshot records 22 ingress/14 core. Four-second sticky entries expire while
offloaded traffic continues, then reappear for the same flows after removal.
The removal interval records 7 ingress/6 core per family while deletion and
traffic overlap; it does not establish an instantaneous all-packet cutover.
Marks remain 65536/131072. Config/source, both original WANs and netifd identity
restore, and all three test namespaces disappear. Native/capture/independent
checks pass (`30a6f7:0`, `b7916e:0`, `2ac7f1:0`). Twelve files plus manifest are
under `diagnostics/flowtable-1.1.12-2026-11-03/` (`94b370:0`). The incomplete first
fixture is qualified separately. Packet-driven sticky refresh requires offload
disabled; no new offload support or hardware/DSA proof is claimed. The kernel
explains this bypass at https://docs.kernel.org/networking/nf_flowtable.html.

**Previous candidate: 1.1.12.**
An actual-address reproduction shows both-family router-local flows receiving
WAN identity when their addresses appear only in the kernel local table
(`7e5cf6:1`). A native `fib daddr type local` check now assigns unmarked local
traffic the default mark before user policy selection. Incoming WAN marks
remain intact. FIB lookup observes address changes immediately, without adding
local-table replication or route-monitor state. The packet suite now classifies
nonlocal policy destinations before a later test-only DNAT delivers them to its
listeners. Explicit local/peer/no-prefix-route and live address add/remove cases
pass (`2fdec9:0`). Real routing/NAT passes (`27497c:0`). All three SDK builds
match current sources and explicitly require `kmod-nft-fib` (`e8c786:0`);
only the core payload changes, with hooks/helpers/Nping/LuCI unchanged.
The raw installer requests the same module; its ash/dash syntax and feed checks
pass (`845e8b:0`). UI and packaging checks pass (`a7bd56:0`, `224dd3:0`).
The first dash gate ended at ownership without a diagnostic; focused tracing
and the complete shell retry pass (`145405:0`, `5f8c64:0`), with the initial
cause unproven and all logs retained.

Actual 1.1.11-to-1.1.12 installation succeeds and preserves conffiles. Native
nftables 1.1.6 passes eight local/address-change cases, including actual replies,
explicit WAN-cache inspection before local reconnects, high skb bits and the
low QoS conntrack byte (`16cc5042:0`). Incoming WAN reply identity and the prior
special-range controls remain correct. Exact config/map, three original WANs,
network-manager identity and stopped runtime restore (`f23891b0:0`);
independent final archive verification passes (`60cbca:0`). Removed-address
packets are checked before routing/confirmation; this fixture deliberately
disables forwarding, so it does not claim their end-to-end forwarding.
Native fixture and verifier corrections remain qualified separately.

The 44-file AArch64 bundle includes thirteen exact rollback baselines. Frozen
records are workspace `diagnostics/sdk-1.1.12-validated-sources-2026-11-03/` and
`local-bypass-final-1.1.12-2026-11-03/`. Earlier candidates remain unchanged.
Physical/manual acceptance and full parity remain open. Nothing has been pushed
or published.

**November 3: scoped SDK builds preserve every 1.1.12 APK byte.**
Plain ALL/ALL_NONSHARED/ALL_KMODS switches still selected over 1,100 packages:
the SDK freezes modular kernel packages as hidden unconditional defaults. The
shared selector now gates only those default-m symbols, preserves fixed built-in
and target/signing settings, and selects requested packages/dependencies. It is
used by feed CI, the local builder and the fresh-SDK guide. Actual kernel APK
counts fall from 922 to 21 on AArch64, 889 to 47 on ARMv7 and 892 to 31 on
MIPSel. All generated NFT/helper/Nping and AArch64 LuCI APKs are byte-identical
to the original frozen candidate; all product inputs match (`ee4ee7:0`). The
local archive wrapper also stops overwriting target metadata with an archive
link path; each complete target dictionary now matches the matrix. Focused
packaging and workflow configure-shell checks pass (`6e3bca:0`, `84b467:0`).
The first experiment remains qualified under
`diagnostics/sdk-scope-first-inputs-1.1.12-2026-11-03/`; final scope evidence is
`diagnostics/sdk-scope-final-1.1.12-2026-11-03/`. These are package counts, not
production CI timings. The full six-package production-key workflow and public
publication remain unexecuted; product runtime and delivered bundles are unchanged.

**November 3: retained 1.1.12 stock IPv6-disabled validation.**
Actual delivered APK installation, two IPv4 trackers and one monitor pass bound
ping/hostname DNS, real route/default restoration, failover/recovery, fw4 reload,
worker restart and read-only CLI/RPC. The kernel really rejects IPv6 sockets;
the required FIB module is installed. Raw counters record 56/43 intended tracker
packets and zero wrong-source/device packets. Six earlier worker identities
retire; exact configuration/hosts/source, netifd identity, both original WANs and
stopped runtime restore. Native completion is `2dc4ab:0`, capture `3f590b:0` and
independent verification `e0801f:0`. A background cosmetic serial-format ioctl
failed before APK installation; retained evidence distinguishes that failure
from the successful foreground setup and exact post-dependency resume. The
17-file record plus manifest is workspace
`diagnostics/ipv4-disabled-final-1.1.12-2026-11-03/` (`22ebe1:0`). The guest is
retired. No product source or delivered APK changed; custom CONFIG_IPV6=n,
physical/manual acceptance and full parity remain separate.

**Previous candidate: 1.1.11.**
The frozen 1.1.10 candidate remains held.
A new actual packet reproduction assigns a WAN policy mark to limited broadcast
(`96d956:1`). Upstream includes the whole `224.0.0.0/3` range in its bypass;
the NFT base hook previously returned only multicast `/4`. The narrow fix
extends that existing early return to `/3`, covering reserved IPv4 and limited
broadcast. The expanded complete packet suite passes 13 cases on both LAN and
WAN ingress (`60664f:0`), including IPv6 multicast/ND/redirect, unrelated marks
and ordinary boundary policy. Routing/NAT, ash/dash, UI and packaging pass
(`4480c4:0`, `9499c3:0`, `3da666:0`, `f4af2e:0`). Three SDK builds match
current inputs; only the backend core payload changes (`ba4bc1:0`). Native
nftables 1.1.6 reproduces the old broadcast failure, then passes after actual
1.1.10-to-1.1.11 APK installation (`0e8b4e38:0`). Limited broadcast, reserved
IPv4 and multicast keep zero routing bits; the ordinary /3 boundary still uses
WAN1 and all four packets retain their unrelated high mark. Both-family incoming
UDP/sticky/rebuild checks pass. Exact installed hashes, conffiles, map, original
WANs, network-manager identity and stopped runtime restore (`df4c51:0`);
independent archive verification passes (`8a5daf:0`). The 41-file AArch64 bundle
includes twelve rollback baselines. Frozen SDK/native evidence is workspace
`diagnostics/sdk-1.1.11-validated-sources-2026-11-03/` and
`special-traffic-1.1.11-2026-11-03/`. Earlier bundles remain unchanged.
Physical/manual acceptance and full parity remain open. Nothing has been pushed
or published.

**Previous candidate: 1.1.10.**
The earlier frozen 1.1.9 candidate remains held.
A new packet reproduction proves that original-direction WAN traffic can put
remote source addresses into client sticky sets (`5ddd28:1`). Per-family ingress
guards now exclude installed WAN devices from sticky refresh while preserving
their conntrack identity. Both-family packet regressions pass, including rule
rebuild without netifd, failed-snapshot preservation, device replacement and
idempotent rebuilds (`65ee20:0`). Routing/NAT, ash/dash, UI and packaging gates
pass (`f66ad5:0`, `0e5168:0`, `088e61:0`, `6ba7e2:0`). All three SDK builds
match current sources; only the backend core payload changes (`992ebe:0`).
Native OpenWrt/nftables 1.1.6 reproduces both-family pollution in 1.1.9, then
passes after actual 1.1.9-to-1.1.10 APK installation (`737121d8:0`). UDP replies
retain WAN conntrack marks and both sticky sets remain empty before/after rule
rebuild. Exact conffiles, identity map, network-manager identity, three WANs and
stopped runtime restore (`bb1b60:0`); independent raw archive verification passes
(`ffcd07:0`). The 38-file AArch64 bundle includes eleven exact rollback baselines
(`d4392d:0`). Frozen records are workspace
`diagnostics/sticky-ingress-1.1.10-2026-11-02/` and
`sdk-1.1.10-validated-sources-2026-11-02/`. Earlier candidate bundles remain
unchanged. Physical/manual acceptance and full parity remain open. Nothing has
been pushed or published.

**November 3: ordered overlapping-rule checks pass on unchanged 1.1.10.**
The complete packet suite now adds five cases per family and 44 checked packet
identities (`15259a:0`). An earlier default or nonsticky policy prevents later
sticky pollution; the first matching sticky rule owns affinity. A predicate
miss selects the next rule. Combined CIDRs, source device, port lists/ranges,
live reordering, source-device edits and sticky off/on edits pass for fresh and
established flows. A temporary core with the first-match refresh return removed
fails the new nonsticky-overlap assertion, confirming the regression check is
effective (`28b578:0`, expected inner result 1). All 74 package inputs and
delivered APKs remain unchanged. Seven files plus a manifest are retained under
workspace `diagnostics/overlapping-rules-1.1.10-2026-11-03/`. This is WSL
nftables 1.0.2 classification/conntrack evidence; native/hardware scope is not
expanded by it. The frozen SDK record keeps its original test snapshot.

**Previous candidate: 1.1.9.**
The shared external-set check now accepts valid IPv4/IPv6 `typeof` declarations.
The packet regression, all three SDK builds and 15 native staged/installed
type cases pass. Actual 1.1.8-to-1.1.9 APK installation preserves conffiles;
package payload checks limit the runtime change to the backend core. Helpers,
hooks, Nping and LuCI code remain identical to final 1.1.8. Native bundle
checksums and stopped read-only collection pass (`d0e3a186:0`); the separate
35-file AArch64 bundle includes ten rollback baselines. Exact sources and
before/after/installed evidence are frozen under workspace
`diagnostics/sdk-1.1.9-validated-sources-2026-11-02/` and
`native-set-types-1.1.9-2026-11-02/`. See the latest entry in
[NFT_PARITY.md](NFT_PARITY.md) for individual checks.

Further crash-dump analysis and experimental stock netifd patching are skipped
at the user's request. Keep historical evidence private and do not resume that
investigation. No platform fix is validated. Continue ordinary source and
functional verification; physical/manual acceptance and full parity remain open.

**Native RA integration now passes on installed 1.1.9 (`a389da30:0`).** The WAN
gateway is learned from stock odhcpd advertisements, with no static default.
Actual Kea IA_NA/IA_PD and PD-only cases both pass gateway withdrawal/recovery,
committed member removal/reinstatement, unchanged tracker identity, bound router
traffic and routed LAN client replies. PD-only keeps the WAN without a global
address and uses its delegated bridge source. Independent Ethernet PCAP checks
find RA lifetimes 12/0/12 and DHCPv6 replies; saved kernel/service state verifies
routes, membership and WAN mark 65536 (`d08802:0`). The original configuration,
source hashes, three WANs, network-manager identity and stopped baseline restore
(`cf067c58:0`). The nine-file frozen record is workspace
`diagnostics/dhcp6-ra-1.1.9-2026-11-02/`. Its two rejected fixtures are retained
and qualified: zero configured server lifetime became its default, then an
early health sample preceded policy commit. Final cases wait for actual
membership before judging traffic. Other providers/options and physical RA
topologies remain open. No product inputs or candidate APKs changed.

**Current 32-bit resolver coverage now passes on 1.1.9.** Fresh official 25.12.6
ARMv7 and MIPSel full-system guests install the exact final backend/helper/Nping
APKs. Each passes the unchanged current socket suite, family-aware resolution
and numeric metadata conversion, native common assertions, 15 external-set cases,
six DNS-server cases and both-family hostname ping/Nping. The intended DNS wire
sources, helper SHA256, target 32-bit ELF IDs, conffiles and clean two-WAN
baselines pass independent verification (`31f67f:0`). Native captures are
`4ec15e36:0` and `3a58861d:0`. The ten-file frozen record is workspace
`diagnostics/cross32-native-final-1.1.9-2026-11-02/`. The ARM guest uses the
compatible A15 image on an A7 CPU and a private exact-A7 APK whitelist; production
architecture checks are unchanged. This closes the newer resolver's 32-bit
native gap, not physical-board or whole-system acceptance. Product inputs and
delivered APKs are unchanged.

**Current 32-bit service lifecycle also passes on 1.1.9.** Both guests run four
trackers and both monitors with sparse bit-31 mask `0x80000300`. Thirty-two real
routes per family propagate to both policy tables and connected sets, then
withdraw completely. Worker identities remain stable through route changes and
both-family probe failure/recovery; ordinary offline marks are isolated while
bound DNS remains available. Procd restart replaces all six workers, and final
PID/start-time readback proves all twelve earlier identities retired. Repeated
TERM tests pass in both families with no stale workspaces. Configuration, saved
identity map, network-manager identity and the original two-WAN stopped baseline
restore. Independent raw FIB/nft/procd/signal verification passes (`b7715a:0`);
final native captures are `fe1aa806:0` and `af4afef7:0`. The eleven-file frozen
record is `diagnostics/cross32-lifecycle-1.1.9-2026-11-02/`. No package inputs or
delivered APKs changed. The PPPoE profile below adds protocol coverage beyond
the completed VLAN/bridge/static-IPv6 profiles. The user's physical two-PPPoE-WAN
acceptance remains open.

**Actual IPv4 PPPoE integration now passes on installed 1.1.9.** Two stock
rp-pppoe providers negotiate addresses through the real netifd/pppd clients.
Six fresh UDP/443 and four TCP/443 flows retain source affinity. Established
UDP traffic retains a six-second sticky entry after nine seconds. Carrier loss
removes the failed PPP device and policy/sticky membership; new TCP and UDP
flows use the surviving WAN. Reconnection negotiates a different address and
creates a new L3 interface identity. Bound traffic and completed tracking
recover, while 60 uninterrupted UDP replies retain the surviving WAN affinity.
The complete native run exits zero (`7686c232:0`). Independent checks of raw
PPPoE discovery/IPCP packets, NAT wire addresses, replies, FIB/nft/procd state
and configuration hashes pass (`870321:0`). The strengthened verifier also
confirms actual six-second set timeouts and live element expiry (`ca10e2:0`).
Original conffiles, saved identity
map, netifd identity, three WANs and the stopped baseline restore; capture also
passes (`0ee71712:0`). Eight evidence files are frozen under workspace
`diagnostics/pppoe-1.1.9-2026-11-02/`; all 74 package inputs still match their
SDK snapshot, and all 35 delivered candidate files retain their hashes
(`293838:0`). Earlier rejected fixtures remain qualified:
the first omitted the managed LAN bridge, then the forked UDP echo responder
failed to answer a second request despite both requests using the correct WAN.
The final fixture uses a standard unconnected UDP socket. No product sources or
candidate APKs changed. Providers use synthetic local addresses and no PPP
authentication. Physical PPPoE/DSA, other provider options, sustained load and
manual LuCI acceptance remain open.

**Native IPv6 source-routing semantics now pass on 1.1.9.** Real IA_NA plus
IA_PD and PD-only profiles retain all declared source selectors with
`source_routing=1`, reject an unrelated marked source, and retain correct bound
and routed client traffic through RA withdrawal/recovery. Both native profiles
and cleanups exit zero (`78c487:0`); capture/baseline checks also pass
(`550a22b2:0`). Independent raw verification checks RA lifetimes 12/0/12,
DHCPv6 exchanges, source-specific FIB entries, membership, stable trackers and
WAN mark 65536 (`7eeb4e:0`). The unchanged earlier native `source_routing=0`
archive proves selector removal in copied policy defaults, while provider-owned
main routes retain their selectors in both modes. Records are under workspace
`diagnostics/source-routing-1.1.9-2026-11-02/`; the source-routing software gate
is now verified. Product inputs and delivered APKs are unchanged. Physical and
manual acceptance remain open.

The current official mwan3 2.12.5 reference was rechecked November 2. The earlier
October 30 audit already covered the four changes after the cached 2.12.2 tree:
dead route flags, empty RPC integers, delegated-prefix matching and expanded
nexthop normalization. Four focused current regressions pass (`65ed9a:0`), and
ten reference files with exact source fingerprints are frozen under
`diagnostics/mwan3-2.12.5-reference-2026-11-02/` (`5c801e:0`). No additional
product repair was needed for those upstream changes.

**Current IPv6-disabled runtime now passes on installed 1.1.9.** A fresh stock
25.12.6 guest boots with `ipv6.disable=1`, has no `/proc/net/if_inet6` and rejects
IPv6 sockets before installation and after cleanup. Actual final APKs pass two
IPv4 trackers, one IPv4 monitor, current hostname DNS binding, route/default
recovery, failover, fw4 reload, restart and cold/active/stopped CLI/RPC checks.
The full native runtime exits zero (`75ed3cc5:0`). Independent raw-state and
APK-byte verification passes (`e1a652:0`), including correct probe source/device
counters, stable workers before restart and retirement of all six prior worker
identities. Configuration/hosts/runtime hashes, network-manager identity and
the prepared two-WAN baseline restore. The record is workspace
`diagnostics/ipv4-disabled-final-1.1.9-2026-11-02/`. Fourteen evidence files are
frozen; all 74 package inputs still match their SDK snapshot and all 35 delivered
candidate files retain their hashes (`bcc8dc:0`). Truncated index, detached
console and minimal-netcat fixture failures remain qualified; archive transfer
retry passes (`bd110cfb:0`). No product inputs or candidate APKs changed. The
guest is retired.

All historical "IPv4-only kernel" results here use a stock kernel with IPv6
disabled at boot. They do not establish `CONFIG_IPV6=n` compatibility. Linux
6.12 requires compiled IPv6 for `NF_TABLES_INET`; the current backend uses an
`inet` table. The user explicitly selected standard OpenWrt 25.12 images only;
custom kernels built with IPv6 removed are outside the supported scope.
Boot-disabled IPv6 on standard images is covered. Historical evidence must not
imply broader custom-kernel support or complete the whole compatibility matrix.

**Previous candidate: 1.1.8.** The
1.1.7 helper can select IPv6 for a dual-address DNS server hostname during IPv4
tracking, then reject its own bind despite a healthy IPv4 server. The shared
resolver now follows the configured family. Explicit numeric interface address
conversion remains available to Nping, while socket-family checks still block
incompatible traffic. Native final-helper DNS cases, hostname ping and both
Nping families pass (`5e2dd2b8:0`, `66c7f52a:0`); independent archive verification
matches the installed SDK helper (`ad75a1:0`). A rejected first fix and its real
Nping assertion are retained separately. All three backend/helper builds and
focused socket/tracker/CLI/packaging regressions pass. Final SDK verification
confirms unchanged backend/hooks, Nping and LuCI runtime payloads (`3a2430:0`).
An actual stopped-1.0.13 upgrade refuses unknown history (`2445a7b3:0`), then
a real guest reboot clears old conntracks and automatically starts reordered
WAN IDs, completed trackers and bound pings (`9ee20220:0`). Independent archive
checks verify the different kernel boot IDs, three procd workers and restored
baseline (`e26356:0`). The frozen 32-file AArch64 bundle includes nine rollback
baselines and passes native checksums/read-only collection (`06477da7:0`).
Physical/manual acceptance, the platform/topology cases below, production
publication and full parity remain open.

**Bridge-backed PD and routed LAN traffic pass (`15fb8993:0`).** A follow-up
real-server profile declares a netifd-managed bridge and veth port, restricts
the loopback LAN to its original prefix classes, and adds a separate LAN client.
Both IA_NA/IA_PD and PD-only cases pass router probes, bound commands and routed
client traffic. The PD-only source is the bridge address, not loopback. Client
conntrack marks remain 65536 and marked lookups select WAN table 1. Independent
packet/kernel/lease checks pass (`ec02d1:0`). Both fixtures restore the original
WANs, configuration/source hashes and netifd identity, leaving no test-prefix
addresses, routes or rules (`ae382447:0`). No separate route cleanup is needed.
Evidence is in workspace `diagnostics/dhcp6-bridge-1.1.7-2026-11-02/`.

**Actual DHCPv6 server integration now passes on 1.1.7 (`f4a10279:0`).** A fresh
25.12.6 VM uses the signed Kea 3.0.4 package and real odhcp6c/netifd acquisition.
Both IA_NA plus IA_PD and PD-only modes pass completed tracker rounds and bound
command traffic. The PD-only WAN has no global address; tracking and commands
use the delegated LAN source. An independent PCAP parser verifies acquisition
and acknowledged renewal transaction IDs, selected wire sources and replies
(`45ef71:0`). Native readback preserves source/configuration hashes, original
WANs and netifd identity. A separate guarded cleanup retires three exact expired
fixture routes from the loopback LAN and verifies the final baseline
(`ccf73f8c:0`). Evidence is retained in workspace
`diagnostics/dhcp6-acquisition-1.1.7-2026-11-02/`. The provider gateway/return path
are controlled; Router Advertisement interoperability and physical ISP/LAN
behavior remain outside this profile. No product inputs or delivered APKs changed.

**Additional 1.1.7 firewall verification passes (`12cfceaa:0`).** A native client
and ISP in separate namespaces exercise real IPv4/IPv6 forwarding and NAT.
Normal fw4 reload preserves four worker PID/start identities, the applied map,
DNS entries before fresh queries, and both families' WAN/QoS conntracks. Full
ruleset loss is reported as stopped; status queries leave owned routing absent.
Restarting fw4, MultiWAN and dnsmasq-full, then querying DNS, restores both-family
client NAT and DNS sets while preserving the map and connection marks. Final
cleanup restores configuration/source hashes, original WAN state and a clean
stopped baseline. Netifd PID remains unchanged and no new core appears.
Independent readback/baseline verification also passes (`eb811308:0`). The
runtime and frozen 1.1.7 bundle are unchanged; README/INSTALL now restore fw4
before MultiWAN and explain custom-set ownership and DNS repopulation.

The fixture initially hit a separate platform boundary: removing live temporary
network profiles during cleanup produced netifd SIGSEGV core files on
`netifd-2026.02.26~cbb83a18-r2`. After restoring a clean daemon/client baseline,
a control with MultiWAN inactive and a complete rerun explicitly bring those
interfaces down before removing their configuration. Both retain netifd PID
15215 and produce no new core. Subsequent matching-symbol analysis of all four
cores identifies the immediate fault: `interface_update_proto_addr()` calls
`system_del_address()` with a null L3 device while removing an address still
marked enabled. `auditfw4` is down and both IP settings are disabled. The
official SDK rebuild's 147,092-byte `.text` matches the captured executable
exactly. Final four-core assertions pass (`deba34:0`); evidence is in workspace
`diagnostics/netifd-crash-investigation-2026-11-02/`. The event sequence that left
this state remains unresolved. No netifd fix is claimed, and these controls do
not isolate shutdown order as the only cause. The upstream deferred-removal
use-after-free fix has not been demonstrated to repair these null-device cores.
One earlier assertion also incorrectly required every nftables table to stay
absent: a real wan6 hotplug legitimately restored fw4. The corrected ownership
check still requires MultiWAN to remain absent until its explicit restart.
Retained evidence is in workspace `diagnostics/full-ruleset-recovery-2026-11-02/`.

**November 2: 1.1.7 is ready for controlled router testing; production sign-off
and full parity remain open.** An actual pre-stopped published
1.0.13 upgrade to final 1.1.6 leaves a WAN-marked connection alive after its ID
is reassigned (`744f7bc4:1`). Old stop removed the recoverable routing mask and
there was no saved map. The documented running-service 1.1.6 upgrade still has
its passing evidence; this is a separate historical boundary. Version 1.1.7
records package/raw upgrade provenance and refuses startup when ownership is
unknown, requiring reboot rather than guessing a mask or deleting unrelated
state. Focused ash/dash regressions pass, including fresh/image installs,
marker-write failure, retries, known maps and live legacy rules. All three SDK
builds match current sources and APK hooks (`65dbd9:0`); only common/core
payloads changed from final 1.1.6. Running 1.0.13 and final 1.1.6 upgrades pass.
The first batch then hit a fixture-only missing `stat` command; cleanup restored
the exact stopped baseline (`8991fac8:0`). After using available tools, actual
stopped-legacy refusal/recovery and a stopped-modern ID reorder both pass
(`11b402e0:0`). Independent raw checks confirm all four cases, config/source
hashes and clean runtime (`88594b30:0`). The legacy recovery uses the authentic
table captured before stop; an actual reboot was not exercised in that fixture.
The separate final 1.1.8 fixture now exercises real reboot recovery, as recorded
above; the earlier 1.1.7 evidence remains unchanged.

A new 29-file AArch64 bundle has eight exact rollback baselines, a marker-aware
collector and embedded install/rollback commands. Native download/checksum and
stopped-collector preservation checks pass (`9f20dc8f:0`). Final 1.1.6 SDK/source
and earlier bundles stay frozen. Complete route-stress, signed-feed, IPv6 expiry
and HTTP gates recorded below used final 1.1.6 and were not all repeated on
1.1.7. Physical PPPoE/load and interactive LuCI remain manual acceptance gates.

**Retained final 1.1.6 evidence.** The complete staged route-stress gate passes (`704d871d:0`):
256 routes per family, repeated MTU changes, withdrawal/recreation, final
deletion, connected sets, real bound traffic and unchanged monitor PIDs.
Independent native comparisons confirm every saved phase snapshot matches its
main table (`39736411:0`). All three final backend/helper SDK builds match current
sources, APK hashes and modes; the unchanged LuCI 1.1.6 APK is reused from its
verified SDK build (`6c5930:0`). Only tracker and monitor payloads changed since
the frozen 1.1.5 candidate.

Actual published-1.0.13 and immediate-1.1.5 upgrades pass (`0c05e5e9:0`). A real
signed HTTP upgrade of all three packages from 1.1.5 to 1.1.6 passes without
`allow-untrusted` (`ba6e3f62:0`); raw install logs and repository policy confirm
all three Upgrading entries (`18bbe574:0`). Unknown-key rejection, unchanged
system keys and cleanup pass. The installed final packages also pass overlapping
PD expiry/recovery, surviving-source packets, old-default removal and clean
restoration (`18bbe574:0`). Ten actual HTTP dispatch/view assets, administrator
and read-only status/helper access and denied WAN/UCI writes pass (`c84eab:0`);
served assets match the exact reused LuCI APK (`5f19db:0`). The HTTP fixture
initially lacked permission to read its VM identity marker; a temporary
marker-only ACL corrected the fixture. Test role, marker ACL, channels and
configuration are restored (`a5618b0a:0`, `5f07be68:0`).

A separate 26-file AArch64 bundle includes seven rollback baselines, collector,
identity guard and manual router/LuCI instructions. Earlier bundles stay frozen.
The user confirms browser access is disabled, so interactive rendering/editing
remains manual. Physical PPPoE/load and the other topology/history boundaries
below remain open; none is implied by the completed virtual checks.

**November 1 investigation history: general deployment remains on hold.** A native
overlapping-PD test reproduced an IPv6 tracker retaining its expired delegated
source while another delegated prefix, its local address and recovery routes
remain usable. A fresh bound command succeeds; sending source-refresh USR2 to
the same tracker restores real packets and health (`471f1da7:1`, diagnostic
control, independently inspected in `5df2894f:0`). The tracker now checks its
cached IPv6 address before probing and uses the existing metadata refresh path
when a replacement is available. The real tracker-loop regression fails before
this change and passes afterward; focused boundary tests also pass. Native
automatic recovery now passes the complete staged gate (`88a47294:0`), including
fresh surviving-source packets, unchanged tracker identity, old-default removal,
shared-device IPv4 traffic and restored source/configuration hashes. An immediate
route assertion initially sampled unfinished reconciliation; bounded convergence
passes without changing route code. All three initial 1.1.6 SDK builds match that
tracker change, modes and APK hashes (`567cab:0`); helper and LuCI payloads match
1.1.5. Those interim packages are archived and have not been deployed.

The next native route-stress gate fails its initial 256-route-per-family phase
(`5c2bf08a:1`). Both IPv4 tables contain 256 routes, but IPv6 has processed only
133, with matching partial connected-set coverage (`7135a5c8:0`). The monitor
replays ordinary source notifications individually under the shared lock.
A real monitor-loop regression reproduces that behavior (`4ce66a:1`). The working
tree now coalesces queued source bursts through the existing bounded drain and
full reconciliation. Startup/recovery/partial-frame/repeated-TERM regressions
pass (`9dd8eb:0`), as do monitor, lock and snapshot checks. The final native,
build and installation results are recorded above. The archived interim 1.1.6
APKs do not contain this newer monitor change; use the final router-test bundle.
The frozen 1.1.5 bundle does not contain this tracker change. The SDK/source
match statements below describe the frozen 1.1.5 sources, not the newer working
tree. A 35-file snapshot preserves those SDK artifacts and their original
tracker. Physical PPPoE/load and interactive browser acceptance also remain open.

**November 1 update: hold the 1.1.4 installation.** A native IPv4-only kernel
test reproduced deleted non-default routes remaining in both WAN tables
(`c53e8297:1`). The connected set updates correctly. Raw `ip monitor` deletion
notifications retain trailing whitespace, while owned-table snapshots trim it;
the exact-match guard therefore skips deletion. A narrow unreleased shared
sanitizer repair passes new IPv4/IPv6 withdrawal and live-duplicate regressions
(red `f88d7c:1`, green `833577:0`) plus common/snapshot/default-route gates.
The sanitizer repair passes staged native IPv4-only and IPv6 non-default
withdrawal checks (`ba04fdbe:0`, `5dd26d39:0`). A subsequent IPv6 test found
that the event handler also removes a recovery default still declared by
netifd (`5896d73a:1`). The unreleased 1.1.5 source routes default withdrawals
through the existing provider-aware reconciliation; its focused regression
passes (`8e3b1c:0`). Combined native IPv4-only and IPv6 runs now pass
(`b9a71dcb:0`, `b98ba1f7:0`), including real bound traffic through retained
defaults and actual IPv6 static-provider withdrawal. Initial startup failures
were test staging: native OpenWrt cp removes the downloaded monitor's execute
bit, unlike host cp. The harness now sets and checks mode 0755. Static-provider
controls use supported configuration updates and wait for address readiness.
All three final SDK builds match current sources, safe modes and APK hashes;
the backend APK is identical across architectures and native helper payloads
are unchanged from 1.1.4. Full ash/dash and official nftables 1.1.6 packet/routing
gates also pass. Actual upgrades from all six prior versions pass
(`a630cc91:0`). Native private signed-index trust checks pass, but raw install
logs from `56b4431f:0` show all already-installed packages were skipped. That
result does not prove installation. The stronger test first installs verified
1.1.4, then performs actual signed-index upgrades of all three packages to
1.1.5 (`77c36b70:0`). Raw downgrade/upgrade logs, repository policy and installed
source hashes independently confirm that transition (`e451f949:0`).
Current 1.1.4 SDK APKs and its frozen bundle contain neither repair. Earlier
completed results apply only to their recorded cases.

Backend and LuCI source are now 1.1.5. A separate controlled-router-test bundle
has 23 checked files and six rollback baselines. It is ready for a controlled
LAN-connected router test; production sign-off and full parity remain open.
The preceding 1.1.4 candidate's focused repeated-TERM monitor repair,
three SDK builds, source/APK fingerprints, package declarations and full shell
gates pass. Final AArch64 upgrades from all five prior versions, native 32-bit
socket/service/optional-probe checks and delayed-child procd shutdown controls
also pass. The separate 1.1.4 controlled-test bundle has 20 checked files and
five rollback baselines. Earlier bundles stay unchanged. Version 1.1.3 has the
CLI reporting and startup failure repairs described below.
Full shell and focused ash/dash regressions pass. Native stopped/active/post-stop
checks pass (`36e0199e:0`). Native guard/cache-publication/base failures and
successful retries also pass (`ba0f9b55:0`). All three frozen 1.1.3 SDK builds
match their recorded source/APK fingerprints. Final package upgrades from 1.0.13/1.1.0/1.1.1/1.1.2
and installed guard/reporting/cold-start repetitions pass (`9e3f82d2:0`), with
the original clean baseline after every phase. The 1.1.3 test bundle contains
17 checked files and four rollback baselines. Earlier bundles remain unchanged.

The frozen 1.1.1 candidate contains the grouped-route and LuCI diagnostics
repairs. The 1.1.2 source additionally fixes cold CLI mask-cache startup and
inactive hotplug initialization. All three frozen 1.1.2 SDK builds match that source;
staged and installed native cold/start/cleanup checks pass, including rejected
initialization without state publication. Final live upgrades from 1.0.13,
1.1.0 and 1.1.1 pass, each followed by the original clean baseline
(`823d910b:0`). The supplied 1.1.0 and 1.1.1 AArch64 bundles remain unchanged.
Namespace and shell regressions pass
for groups, inline multipath, exact WAN filtering, duplicate gateway merging,
failed member reads and idempotent updates. Native OpenWrt 25.12.6 checks now
also pass both families and dump modes, group/member changes, equivalent
gateways, withdrawal, inline notifications, bound probes and clean shutdown.
The frozen 1.1.1 target builds match their recorded source fingerprints. Native live
upgrades from the actual 1.0.13 APKs and the frozen 1.1.0 APKs pass with the final
backend/helper/LuCI packages, followed by the original stopped-service baseline.
The latter upgrade preserves unchanged WAN-marked sessions; both preserve
configuration, hooks, QoS-only state and an unrelated monitor.
Exact projected weight ratios above the
classic route limit require owned nexthop groups; current code rejects them
before changing the table instead of rounding the weights. Resilient bucket
affinity is not established by these checks.

## Next runtime checks

1. **Optional probe hardware acceptance.** Native tracker rounds now pass for
   Nping ICMP/TCP/UDP, HTTP/HTTPS quality and DNS in both families, plus IPv4
   ARP/arping. Nping 7.95 had independent IPv6 source/filter defects; optional
   `multiwan-nft-nping` 7.992 replaces it. The wrapper now permits opposite-family
   metadata ioctls while rejecting traffic. HTTPing 3.5 uses unbracketed IPv6
   literals in its CLI URLs. DNS timeout/retry options are measured and passed.
   These native checks use controlled IPv6 responders; actual WAN/router
   acceptance remains separate.
2. **More netifd updates.** Actual IPv4 replacement through `notify_proto`
   reproduced stale tracker binding and now passes. Healthy and offline refresh,
   exact recovery source, policy exclusion and recovery after fault removal are
   verified. IPv6 notify_proto replacement now also passes with MultiWAN stopped
   as a control and with routing active: actual new-source probes, healthy state,
   offline policy exclusion, exact recovery selector and recovery after fault
   removal. Native logical alias/device replacement also passes as described
   below. Native delegated-prefix-only checks now also pass: netifd assigns
   a LAN source while the WAN has no global address; renewal, offline
   renumbering, recovery, actual lifetime expiry and a fresh delegation retain
   the tracker identity and correct source/device. Expiry removes eligibility
   and copied routes; shared-device IPv4 remains usable. These are controlled
   protocol lease updates, not DHCPv6 server acquisition or overlapping-prefix
   deprecation proof.
   For the same-prefix VM update, `promote_secondaries=1` was temporarily needed:
   the new address disappeared with its default value even with MultiWAN stopped.
   The control passes with promotion enabled; the phase restores the setting.
   This network handoff behavior needs a separate router/OpenWrt check.
3. **Late extra routing tables.** Startup, late insertion and removal now pass
   in both families in the native VM, after waiting for monitor child readiness.
   The previous late-event failure was a test startup race. Namespace tests
   also verify that genuine read failures preserve live sets. Continue with
   actual VPN/device transitions as part of the manual-interface gate below.
4. **First upgrade without an identity map.** The reproduced live restart race
   is repaired: a separate owned nft table blocks retired family/masked marks
   before purging, remains active through rebuilding, and is removed after the
   new map is committed. The routing suite now keeps old rules live and verifies
   IPv4/IPv6 forwarding, local INPUT and local OUTPUT, preserved unaffected
   sessions and recovery. Native OpenWrt also verifies both-family reassignment,
   guard removal and bound DNS/ping recovery. Missing-map simulation now recovers
   the old mask from live NFT rules, retires that marked namespace once, keeps
   protection through a failed rebuild, preserves QoS-only conntracks and commits
   the new map after recovery. Both-family forwarding/INPUT/OUTPUT namespace
   tests and native failed/successful rebuild tests pass. Native stop-before-
   restart also captures a missing map before removing the old rules. The actual
   published 1.0.13 backend/LuCI APKs now pass a live upgrade to the current
   rebuilt 1.1.0 packages in OpenWrt 25.12.6. Installed old source hashes match
   the user's report. The transaction preserves byte-identical config/comments,
   user hooks and QoS-only conntracks, retires old workers and WAN marks, commits
   identities, removes protection and restores both WANs' health and policy
   membership. It also exercises overlapping IPv6 connected prefixes. An older
   package already stopped with both its rules and saved ownership gone has now
   reproduced stale-mark reuse on final 1.1.6 (`744f7bc4:1`). The 1.1.7 refusal
   path and upgrade marker now pass the cases recorded above. Do not infer
   past masks or equate missing evidence with a fresh install.
5. **Aliases and device replacement.** Repeated MultiWAN CLI down/up passes in
   both families, including preserved pause across metadata updates. Actual
   netifd WAN down/up resumes the same tracker and preserves shared-device IPv6.
   Starting with the backup WAN unavailable creates a waiting tracker; actual
   netifd ifup restores committed eligibility and bound DNS. Actual late IPv4
   and IPv6 family aliases now refresh tracker source, removal pauses tracking,
   and recreation on another device resumes the same PID with new-source/device
   probes, matching policy rules/defaults and removal of the old default. User
   hooks retain the configured logical name. Tests disable the other same-family
   WAN before sharing its device. The tagged VLAN/bridge case below now passes.
   Physical PPPoE/VLAN, arbitrary same-family shared-device ownership and
   overlapping delegated-prefix deprecation still need proof.
6. **Final package integration.** All three frozen 1.1.3 SDK outputs match
   their recorded product fingerprints and APK hashes. Final AArch64 upgrades from 1.0.13,
   1.1.0, 1.1.1 and 1.1.2 pass, as do installed cold reports/use/inactive events,
   stale-cache sparse-mask startup, rejected startup state preservation and
   applied-mask cleanup across an unapplied edit. Guard rejection/retry and
   strict reporting also pass on the final installed APKs. The frozen 1.1.1 upgrades from
   1.0.13 and 1.1.0 pass with those packages. The LuCI helper also passes
   real stopped-service set/rule/route queries without creating runtime state.
   Expanded packet tests passed on official
   nftables 1.1.6; routing/NAT tests passed again. The rebuilt AArch64 running
   upgrade passes with all six workers, preserved conffiles and current installed
   hotplug/tracker hashes. Final alias/status code also installs from the identical
   noarch backend APK and passes those checks. The final route-monitor repair
   installs from its rebuilt SDK APK with current hashes, preserved conffiles,
   registered RPC, six workers and two owned monitor children. The startup repair
   also passes this install gate, waiting for both initial reconciliations to
   finish. Actual LuCI SDK packaging and
   HTTP/RPC checks pass; interactive browser and signed-index integration remain
   separate gates.
7. **Concurrent route changes.** CLI/RPC now report held routing protection
   separately from health and live-service state; native successful/failed
   rebuild and recovery checks pass. Both LuCI status renderers show the warning
   while preserving health cards. Native IPv4/IPv6 alias RPC metadata and UCI
   boolean normalization pass. CLI alias uptime/failure fallback and configured-
   disabled status also pass. Actual IPv4/IPv6 route events during a live ID
   reorder reproduced stale monitor ownership and now pass: events wait for the
   service lock, reload only after a committed map changes, and preserve applied
   IDs before configuration apply. Initial population is also serialized. A new
   worker refuses unmatched unapplied IDs until configuration is applied or
   reverted. Native startup also reproduced lost add/delete events between the
   snapshot and subscription. Subscription now precedes initial reconciliation,
   with socket ownership/family readiness verified; both-family injection tests
   pass, including removal of stale non-default routes and connected elements.
   Native IPv4/IPv6 kernel overflow now also passes after reproducing stale
   routes/sets with 5,559 dropped notifications. Stream replacement and full
   reconciliation retain the supervised parent and applied IDs despite an
   unapplied UCI reorder; repeated-error shell tests pass beyond procd's retry
   limit. Native mask replacement now passes across 0x003f0000, 0x3f000000 and
   noncontiguous 0x55005500: both-family old marks retire, QoS-only state survives,
   new rules and mixed-mark probes work, and bound DNS/ping recover. Native
   queued-route changes across a failed rebuild also pass: source changes
   occur while the service lock and then protection are held; retry removes
   withdrawn main/additional routes, keeps a remaining duplicate source, installs
   late routes/sets and restores both-family bound probes with committed IDs.
   Still verify sustained-load/large-table throughput and browser display on the
   router. Same-device stale defaults now have native IPv4/IPv6 repair proof:
   obsolete gateways/metrics are removed, declared recovery defaults remain in
   place without a delete event and carry bound probes, and actual provider
   withdrawal removes defaults while the link remains up. Unknown or malformed
   provider status stops cleanup. Main/additional-source and owned-table snapshot
   failures now also have native IPv4/IPv6 injection proof: existing FIB routes
   and NFT sets survive nonzero failures and interrupted/truncated dump warnings,
   including a failed owned-table read after provider restoration. Real route
   withdrawal/recovery converges. Shell tests verify monitor resynchronization
   after failed updates, retained duplicate-route set refresh and aggregation of
   interface failures. Sustained concurrent table churn remains open.

## Newly completed local checks

- Installed 1.1.4 now passes actual netifd IPv4/IPv6 VLAN 208 WANs and migration
  to a bridge containing that VLAN (`436e04cd:0`). Fresh tracker packets precede
  helper checks; exact source/device/defaults, ordinary marks, unchanged tracker
  PIDs, removal of old defaults, fw4 reload, probe failure/offline isolation,
  bound recovery traffic and carrier recovery all pass. Original four-WAN
  config/hook/network/firewall bytes, defaults/map and clean stopped baseline
  restore; separate packet/source capture passes `e85842b4:0`. Earlier tests
  sampled unfinished hotplug callbacks or lost the simulated ISP's static IPv6
  gateway during cable loss. Negative/positive provider controls reproduce and
  correct the latter with MultiWAN stopped; only that temporary namespace uses
  `keep_addr_on_down=1`. No product patch was needed. Full evidence is in the
  workspace `diagnostics/vlan-bridge-runtime-2026-11-01/` folder. Physical
  switch/DSA/PPPoE, arbitrary same-family sharing and sustained load remain open.
- Historical 1.0.13 package upgrade exposed retained interval-set metadata:
  `flush table` does not add `auto-merge` to existing sets. Overlapping IPv6
  routes then rejected a connected-set update. Base loading now atomically
  recreates only the four derived connected/custom sets, restores their cached
  prefixes and preserves same-table external DNS sets. Packet regressions cover
  both families, exact-start overlaps, failed reads and failed atomic batches.
  Official nftables 1.1.6 packet/routing tests, all three SDK builds and the
  actual native old-to-new APK transaction pass. Router installation remains
  separate; a local AArch64 candidate includes checksums and old rollback APKs.
- Real IPv4/IPv6 nexthop objects reproduce rejected policy-route replay with
  expanded `nhid` plus `via/dev` attributes. Route mutations now retain object
  identity and omit its incompatible expansion. Namespace tests pass copying,
  marked lookup, actual monitor add/delete handling and stale-route cleanup in
  both expanded and ID-only dump modes. Official nftables 1.1.6 packet/routing
  tests also pass. The exact rebuilt AArch64 APK passes real native monitor
  add/withdrawal and marked lookups in both modes and families, followed by
  the original stopped-service baseline. ID-only defaults then reproduced
  accidental cleanup of a still-live WAN default. Device resolution now reads
  the referenced nexthop when its expansion is absent; lookup failure stops
  cleanup. Native tests also reproduced stale ownership after an object device
  change with compatibility notifications disabled. Workers now subscribe to
  nexthop events as well as their family routes, verify both memberships before
  snapshotting, and reconcile the family on object updates/deletes. Native
  IPv4/IPv6 default ownership, movement between WANs, withdrawal and bound
  probes pass on the exact rebuilt AArch64 APK, followed by the original
  stopped-service baseline. The fixture waits for both initial reconciliations
  before timing object changes; an earlier immediate-start run exceeded its
  unqualified 15-second wait and cannot establish a steady-state event loss.
  Grouped nexthop ownership now has additional namespace/native proof below.
- Cold and repeated `ifup` with `initial_state=offline` now isolate ordinary
  marked traffic and retain helper-only recovery in IPv4 and IPv6. Actual VM
  tests passed, including recovery ping and removal from active policy sets.
- `tests/test-nft-hotplug.sh` verifies state/policy/rule consistency and rollback
  after route, policy or rule installation failures with BusyBox ash and dash.
- All NFT shell regressions, packaging checks and the expanded host packet
  suite passed. Windows Node UI checks and `git diff --check` also passed.
- New address/route/prefix hotplug cases preserve committed health, signal
  source refresh only when needed, and ignore data-only updates. The tracker
  refreshes source/device while retaining committed online/offline state.
- Alias mapping preserves explicit interface names, family boundaries and
  disabled parents. Disabled CLI status skips owned-rule error checks even
  when another active WAN shares the device.
- Retired-mark guards close the reproduced live reconciliation window. Identity
  fixtures verify guard-before-purge ordering, family/mask selection, failed
  installation, failed purge, release retry and old-map preservation. Startup
  now aggregates interface and route failures, propagates connected-set errors
  and reports failed special-action rule installation; a failed rebuild cannot
  release the guard or publish an incomplete map.
- A separate RPC protection flag and CLI/LuCI warning expose incomplete routing
  without changing tracker health or claiming the whole service is stopped.
  RPC link/uptime follows the active family alias, and enabled values use the
  same UCI boolean semantics as routing. Native controls reproduced false
  link/zero uptime/disabled reporting before the repair and pass afterward.

## Integration still open

The same-family shared-device question also has an inherited design limit:
both current upstream `mwan3_route_line_dev` and this implementation choose the
first matching device/table entry. Incoming interface marking also identifies
the Linux L3 device. Consequently, two independent same-family gateways over
one L3 device must not be advertised as established support. Upstream
[issue 15224](https://github.com/openwrt/packages/issues/15224) describes the
routing and incoming-mark ambiguity; the current
[implementation](https://github.com/openwrt/packages/blob/master/net/mwan3/files/lib/mwan3/mwan3.sh)
still returns the first match. This is distinct from the tested IPv4/IPv6
sharing and from separate PPPoE/VLAN L3 devices on one physical port. Native
tests and any deliberate change to this topology contract remain open.

- **Target acceptance.** Final 1.1.6 source, SDK and installed-package checks pass
  for the recorded cases; 1.1.7 upgrade-history protection also passes its native
  transition cases and three-target SDK checks.
  Physical PPPoE failover/recovery and sustained router
  load remain required before production sign-off. Earlier candidate bundles
  stay frozen and do not contain the later repairs.
- Interactive browser validation: local browser use is disabled in Work settings.
  Actual LuCI SDK packaging, login/dispatch/assets over HTTP, rpcd status and
  administrator/read-only safe diagnostics and denied mutations pass. Package
  helper executable permissions and Git checkout modes have regression proof.
- ARMv7 and MIPSel helper execution now has full-system OpenWrt proof. Actual
  packaged helpers pass the complete socket assertions and native common suite.
  Both guests also pass four trackers, both monitors, bit-31 policy routing,
  failure/recovery and restart/stop. Native MIPSel exposed repeated TERM aborting
  monitor cleanup; staged 1.1.4 repairs it and leaves no workspaces. Actual ARMv7
  1.1.4 package installation/runtime checks and installed MIPSel 1.1.4
  revalidation pass. Native optional Nping, arping, HTTP/HTTPS quality and DNS
  checks now also pass on both 32-bit guests. Physical boards and sustained
  load remain separate; the ARM test uses a compatible A15 rootfs on a Cortex-A7
  CPU with the A7 APK explicitly whitelisted in that disposable guest.
  Current 1.1.9 socket/resolver suites, six DNS cases, both-family hostname
  ping/Nping and 15 set-type cases now also pass on both 32-bit guests, as
  recorded above. This newer evidence uses the final 1.1.8/1.1.9 helper payloads.
- Physical PPPoE/DSA integration and remaining malformed/failure cases. Actual
  DHCPv6-server acquisition/renewal now passes in the controlled profile above.
  Controlled overlapping/deprecated-PD expiry and native VLAN/bridge transitions
  pass as recorded above. The later bridge profile adds real delegated LAN
  source binding and routed client marks/replies. Physical prefix-assignment
  topologies and additional Router Advertisement providers/options still need
  acceptance. The controlled 1.1.9 RA profile above now passes real gateway
  acquisition, withdrawal and recovery in both source modes.
- Native private signed-index trust checks pass with a disposable test key;
  actual version-changing upgrades from 1.1.5 to final 1.1.6 also pass with raw
  install proof. Version 1.1.7 passes its local-APK transition gates; the signed
  HTTP transaction was not repeated for that version.
  Production-key CI execution and public feed
  publication remain separate; neither was performed.
- The user's NanoPi R5S and actual PPPoE WANs. A user-run read-only report confirms
  installed 1.0.13 sticky refresh is unreachable for restored marked flows, both
  WANs are online, and TCP-only sticky excludes UDP/443. This is OpenWrt 25.12.5
  with nftables 1.1.6-r2. The available router report covers 1.0.13. The user will run
  supplied commands and share results; direct router access is not configured.

Native dnsmasq-full population now passes in both families, including fw4
reload, DNS restart and MultiWAN stop/start. Explicitly timed sets expire and
repopulate; automatically created untimed sets retain addresses. The install
guide documents that DNS cache TTL does not remove untimed set elements.
Controlled IPv6 transport also proves bound DNS tracking; QEMU's built-in IPv6
DNS proxy remains unavailable in both the bound and unbound control.

## Current disposable environment

The workspace-level `diagnostics/openwrt-vm-console-2026-10-30.py` boots the
official OpenWrt 25.12.6 armsr/armv8 kernel/rootfs and serves diagnostic artifacts
to the guest over its virtual WAN. Its console accepts JSON command objects;
the kernel and package operations remain inside the guest. The phase scripts
refuse to run without a marker created for that disposable VM. The console log
records reproductions, repairs and passes. Do not treat a log containing a
failed phase followed by unrelated passes as a completed gate.

Controller session 60861 is no longer available; host process/listener checks
confirmed its retirement (`f22321:0`). The four cores and matching executable/
libraries were retained locally. A fresh official-image VM was retained as
controller session 2182 for the 1.1.7 DHCPv6 checks. That controller was retired
after its evidence was retained. Reboot-capable controller 99196 later retained
the synthetic VM with actual final 1.1.12 backend/helper/LuCI APKs, Kea 3.0.4,
ip-full, veth, conntrack, tcpdump-mini, socat and Nping 7.992. The earlier
1.1.8/1.1.9 reboot and 35-file bundle/collector checks remain historical. Current
1.1.12 passes the actual APK upgrade, local FIB/address-change, special-range and both-family sticky checks;
the three original WANs, identity map, conffiles, network-manager identity and
globals-only stopped MultiWAN configuration restore. The current 44-file bundle
and delivery archive pass host integrity checks. On the November 3 continuation,
the old handles are missing and the host has no QEMU process. A new IPv6-disabled
controller 49859 passes current 1.1.12 installation/runtime and independent
capture verification, then is deliberately retired (`ab5e18:0`). Frozen evidence
remains available; no earlier controller is assumed live.
Stopping the controller removes its temporary disk; frozen logs and archives
preserve completed evidence.

The final 32-bit guests, controllers 12218 (ARMv7) and 52479 (MIPSel), pass
the final 1.1.9 helper/DNS/set and current service/route/signal gates above.
Both restore exact package/configuration hashes, the original identity map and
two configured IPv4 WANs with the stopped globals-only profile. Their completed
evidence is frozen. Both controllers were deliberately stopped after the final
integrity check; their temporary disks are gone. Earlier 1.1.4 evidence stays unchanged.
No further platform crash investigation is authorized by current task steering.

Current controller 73920 retains a fresh standard 25.12.6 VM with installed
1.1.15 backend/helper/LuCI, two original DHCP WANs and the restored globals-only
stopped routing profile. The native flowtable, held-1.1.13 and final-1.1.14
evidence has been captured independently. Revalidate the live handle before use;
temporary disks are not acceptance evidence by themselves.

The current 1.1.15 installed notification, empty-FIB and stock-kernel packet/routing evidence is frozen. Controller 73920 restores the two-WAN globals-only stopped profile, exact source/configuration/map and original netifd identity. The failed first routing fixture is qualified separately; no stock netifd patch or crash analysis is included.
