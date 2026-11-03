# Native nftables behavior parity

This is the acceptance checklist for replacing mwan3's iptables/ipset runtime with native nftables. It records the functional contract, not a claim that the current implementation passes it. Source review alone does not satisfy a packet, process, migration, or integration requirement.

The [function/evidence reconciliation](NFT_FUNCTION_AUDIT.md) accounts for all
142 upstream declarations/generated helpers (141 runtime plus one migration) and
links all 26 contract groups to recorded checks and explicit remaining limits.
The source map is complete; behavioral/hardware acceptance remains separate.

Current 1.1.17-r1 builds and payload verification pass on all three architectures;
only CLI validation changes from 1.1.16. The routing engine remains unchanged.
Exact delivered install/rollback/reinstall passes 1.0.13/1.1.17 (`cd6e66:0`),
preserving raw configuration/comments/hook, 4:1 policy weights and both bound
probes. Modern stages check eleven installed files, including CLI. Packaged
malformed ifup/ifdown return 2 without recreating stopped runtime or changing its
map. Twelve recorded workers retire, and all 28 original targets, world/config/
map/root rules/netifd and original stopped 1.1.16 packages restore. The record is
`diagnostics/guide-roundtrip-final-1.1.17-2026-11-03/`. The 59-file local bundle
includes 18 exact rollback baselines. Physical/manual/load acceptance and
production signing/publication remain open; nothing is pushed or published.

Routed dynamic bypass now passes focused and complete native routing checks
(`64084a:0`). Each run covers twelve LAN/router TCP/UDP combinations, 66 successful
observations and four explicit MASQUERADE state retirements. Fixed IPv4 SNAT and
native IPv6 preserve connection identity while add/remove changes actual FIB
egress; QoS bits and NAT source remain intact. Fresh bypass flows retain main-table
identity after removal, while new flows follow WAN policy. Standard MASQUERADE
cannot preserve state across an egress-device change: the kernel retires it, UDP
retry recovers and new TCP connections succeed. The two earlier failed probes
assume unsupported transparent MASQUERADE continuity; extending the timeout does
not resolve that assumption. The record retains all phases, exact source/fixture
binding, the complete routing pass and unchanged original source/config/map/root
rules/netifd. See `diagnostics/dynamic-routing-native-2026-11-03/`. Physical ISP
source validation, offload, hardware/load and interactive LuCI remain separate.

The final raw-installer journal repair now covers handled local-application
failure as well. Before mutation it saves original file/link state, migration
backup names and provenance. Failure removes the active temporary file and
restores saved paths and boot state; failed requested startup restores the prior
running state when recovery succeeds. An unsuccessful restore retains private
backups and returns failure. Both-shell tests cover main/LuCI/fresh/migration,
symlink, application-interruption, startup and restore-failure cases. They also
expose private staging umask leaking into fresh live directories; the final source
restores the caller's umask after creating private journals.
An SSH-style SIGHUP control also exposes skipped rollback; the final source
handles HUP explicitly and ignores further handled signals during restoration.

All four CI steps pass on final fingerprints. Native old/new rename controls show
the old script retaining the changed CLI, marker and temporary file; the fixed
script restores all 28 files and provenance without replacing running workers.
Bound probes and 4:1 weights survive. A successful retry activates all 26 expected
code/helper hashes; six recorded identities retire at final cleanup. Exact source,
startup/config/map/world/root rules/netifd and the stopped profile restore.
Independent verification passes (`8b0ba8:0`); all three native source phases and
six separate rollback/umask/hangup failure controls are retained under
`diagnostics/raw-rollback-native-2026-11-03/`. This closes handled deployment
rollback in the tested profiles. Power loss/SIGKILL and persistent unwritable
storage require recovery outside automatic cleanup. No new APK or publication
is claimed.

The preceding raw-installer source repair prepares every selected download and file
mode before migration, upgrade-marker publication or live replacement. Native
original code reproduces a second-fetch 404 leaving a replaced init file and
marker; the current regression also exposes premature legacy-name migration.
Both-shell fixtures cover all components, fresh/existing installation, retries,
dependency failure and SIGTERM. Existing syntax/ash/dash plus the new raw CI step
pass. Native all/main/luci/repeat and a failed download while the service is
running pass with five exact 26-code-file/config/probe stages. LuCI-only and the
rejected download retain worker identities. Nine recorded identities retire;
28 original files, startup/config/map/world/root rules/netifd restore. Independent
verification passes (`fa03ce:0`); the record is
`diagnostics/raw-staged-native-2026-11-03/`. The first red fixture's unavailable
stat command is replaced with stock ls; both phases and exact restoration remain
retained. That preparation record does not cover local rollback; the newer journal
record above closes that separate handled-failure check. No new APK is built and
the frozen 1.1.16 bundles remain held.

November 3 current source repair: **hold frozen 1.1.16-r1 for the CLI validation
repair; a new package build is pending.** Native CLI acceptance exposes malformed
ifup/ifdown initializing runtime and publishing the cached mask before returning
usage error 2. Initialization now runs inside each command after its existing
argument checks. A focused regression fails before repair and passes in ash/dash;
the complete existing CI shell gates pass. A reversible native source trial
reproduces both error paths, then passes all twelve advertised commands across
34 actual invocations, with quoted argv/exit/stderr behavior, both internal family
reports, bound IPv4 probes, stable pause/resume workers, replaced restart workers
and stopped read-only reports. The original eleven-file source baseline and
startup/config/map/root rules/world/netifd state restore. Six workers retire.
The first repaired trial has a fixture assertion omitting the normal online
uptime text; its exact one-line correction and failed evidence are retained.
The source trial does not establish new APK coverage. Packet/routing engine,
common helpers, RPC, C helper, Nping and LuCI sources are unchanged.
Independent archive verification passes (`a197f6:0`); evidence is retained under
`diagnostics/cli-dispatch-fixed-source-1.1.16-2026-11-03/`. The focused source record
also verifies that only the CLI payload differs among the 74 SDK package inputs.

November 3 preceding status candidate: **1.1.16-r1 repairs 1.1.15.** Upstream
function reconciliation exposes three
status defects in installed 1.1.15: live disabled/waiting trackers report active,
RPC omits `tracking`, and manual pause prints a routing error for deliberately
removed objects. The shared helper now reads the live tracker's explicit state;
stale metadata without a process stays down. RPC returns `tracking` and a
consistent `running` boolean, using `disabled` for unconfigured tracking. CLI
reports live disabled/waiting pause states before checking absent routing objects,
while stale metadata still permits normal routing checks.

Three focused regressions fail on frozen 1.1.15 and pass in ash/dash. The initial
two-file native source repair still prints routing error (48); the final complete
repair corrects all three layers without restarting workers. Pause/wait/resume
CLI and RPC agree, all recorded workers retire and the exact original 1.1.15
baseline restores. The 69-file source record plus manifest is
`diagnostics/paused-status-source-1.1.16-2026-11-03/` (`2351ea:0`, `af63ab:0`).
Complete existing CI syntax/ash/dash gates, UI and packaging checks pass. The
first full gate exposes a missed LuCI translation-version field; the corrected
1.1.16 retry and failed first log are retained (`e27e8b:0`, `5d14fb:0`, `a7f288:0`).

Three SDK builds match all 74 package inputs. Exactly common status, one CLI
report function and RPC payloads change; helper/Nping/LuCI contents stay identical
(`76d988:0`). Packet/routing-engine code outside the CLI report is byte-identical
to the validated 1.1.15 baseline. The 132-file SDK record plus manifest is
`diagnostics/sdk-1.1.16-validated-sources-2026-11-03/` (`7bb7b6:0`). Actual
1.1.15-to-1.1.16 APK installation preserves config/comments and the user hook,
matches ten installed file hashes, retires old workers, passes both bound WAN
probes and verifies exact installed pause/wait/resume CLI/RPC behavior. Four new
workers stay stable through those transitions; eight total identities retire.
Original config/map/root rules/netifd and the stopped profile restore with genuine
1.1.16 packages retained. Independent verification and the 13-file record plus
manifest are `diagnostics/status-apk-final-1.1.16-2026-11-03/` (`5a8c08:0`, `975d57:0`).

The separate 56-file AArch64 controlled-test bundle has seventeen exact rollback
baselines, known 1.1.15 RPC/source guards and both-shell guide checks (`7da91b:0`).
Its exact literal 1.1.16 install/rollback/reinstall now passes actual local APK
transactions from published 1.0.13 and back. All four stages preserve raw
config/comments/hook, both online WANs and 4:1 weights; modern stages match ten
installed files and pass both bound probes. Twelve worker identities retire;
the exact stopped config/map/root rules/world/netifd baseline restores. Independent
archive verification passes (`796806:0`). The 14-file record plus manifest is
`diagnostics/guide-roundtrip-final-1.1.16-2026-11-03/` (`6eadd5:0`). The delivery
archive is unchanged; its README's unexecuted statement predates this proof.
Source/SDK/APK/guide proof does not close physical R5S/PPPoE/DSA/load,
interactive LuCI, remaining feature reconciliation or production publication.
Flow offload stays excluded from packet-driven sticky refresh. Nothing is pushed.

November 3 dynamic/protocol proof on unchanged **1.1.15-r1** passes the complete
extended packet suite. Its original assertions remain byte-identical to the
validated SDK snapshot. Twenty-four both-family dynamic-bypass cases cover
destination add/remove, established WAN identity, retained main-table decisions,
WAN-source bypass, policy/rule/base refresh and full stop/start/repopulation.
Injected UDP packets reach local listeners through the test delivery NAT; kernel
assertions verify exact skb/conntrack routing bits and unrelated QoS fields.
Twenty-five additional cases cover GRE/ESP names and numeric aliases, protocol
253, wrong-protocol controls and IPv6 hop-by-hop headers. Non-TCP/UDP port options
are ignored. Invalid names reject the batch and preserve preceding rules. The
initial full run passes; the final full run additionally clears private
conntracks before every protocol packet and verifies zero saved WAN bits before
the product hook. Both sources and results are retained. These cases prove
classification, not GRE/IPsec tunnel interoperability or end-to-end dynamic path
changes under NAT.

The [dynamic producer contract](../INSTALL.md#dynamic-bypass-producers) documents
flat native address/prefix unions, external ownership of elements and required
repopulation after a full service restart. Its exact example passes in another
owned namespace: a wrong-family update preserves both preceding snapshots;
empty unions and repopulation also pass. Independent executed-source/result
verification passes (`fb39fa:0`). The 26-file record plus manifest is workspace
`diagnostics/bypass-protocols-final-1.1.15-2026-11-03/` (`283f1d:0`). Both packet
runs and the producer phase preserve root nftables/policy rules. Source,
configuration/map/netifd and the original stopped baseline remain exact; both
WANs stay up. All package inputs and the delivered archive remain unchanged.
No runtime repair or rebuild is needed. Requirement reconciliation, sustained
load, physical/manual acceptance and production publication remain open.

November 3 balanced TCP affinity proof on unchanged **1.1.15-r1** starts actual
IPv4/IPv6 TCP/443 connections with two equal-metric, equal-weight eligible WANs.
It then changes weights to favor the other still-eligible WAN 1000:1, verifies
both installed eligibility marks, weighted policy rules and the initial cached
source/mark element, and opens twelve distinct new connections per family. All
twenty-four retain the initially selected WAN and expected conntrack mark.
Either initial random choice is accepted; there is no random distribution
assertion. The complete focused TCP function also passes its prior lifetime,
metric-change, protocol/port/device/CIDR and canonical ICMP assertions. The first
phase passes balanced TCP but its temporary IPv6 address changes the later ICMP
source selection. The final test removes the two aliases before that check;
the exact three-line fixture change, initial failure and final pass are retained.
Both phases preserve source/config/map/netifd and root nftables/policy rules.
Independent raw/source verification passes (`7c07d3:0`). The 21-file record plus
manifest is workspace `diagnostics/balanced-tcp-final-1.1.15-2026-11-03/`
(`81d838:0`). All package inputs and the delivered archive remain unchanged.
The wider routing/NAT suite passed before this test-only extension; this run
covers the complete focused TCP function. Physical/manual acceptance and the
remaining feature cases remain open.

November 3 delivered-guide proof on unchanged **1.1.15-r1** executes the exact
install block, the exact rollback block with only its printed backup path
substituted, and the install block again. Actual local APK transactions run
published 1.0.13, upgrade to 1.1.15, return to published 1.0.13 and upgrade again.
All four stages preserve raw configuration/comments and the synthetic user hook,
run three supervised workers and restore both IPv4 WANs and 4:1 policy weights.
Modern stages pass both WAN-bound probes and exact nine-file source checks;
legacy stages match the published six-file baseline and remove the separate
socket helper. Twelve unique recorded workers retire at final cleanup. Original
configuration/hook/map, root nftables/policy rules, source, APK world bytes and
netifd identity restore; both original WANs remain up. The first launcher fails
before invoking the fixture because of a positional-argument error. The first
host verifier incorrectly expects modern eligibility sets in legacy 1.0.13;
the final verifier checks its actual weighted rules and modern eligibility sets.
Both qualifications are retained. Independent verification passes (`96061a:0`).
The 14-file evidence record plus manifest is workspace
`diagnostics/guide-roundtrip-final-1.1.15-2026-11-03/` (`6d45cf:0`). All 53 delivery
manifest entries and the original archive remain unchanged. This closes the
literal-guide roundtrip gap for the published 1.0.13 baseline on the disposable
stock 25.12.6 AArch64 VM. Other rollback baselines, physical/manual acceptance,
remaining feature cases and production publication remain separate.

November 3 TCP-specific proof on unchanged **1.1.15-r1** now covers real IPv4/IPv6
TCP/443 connections. Active traffic refreshes affinity; the entry expires while
only UDP/443 continues, then the established TCP connection recreates it. New
connections follow a changed metric tier while existing TCP/NAT sessions retain
their original WAN/conntrack marks. Positive/negative port-list/range, source
device and source/destination CIDR checks pass. Canonical ICMP/IPv6-ICMP selectors
pass real echo traffic with intended WAN marks and ignored non-TCP/UDP port options.
The shared test echo helper now supports concurrent, framed TCP streams; a
both-family smoke test and the complete extended native routing/NAT suite pass.
Independent archive/source/result checks pass (`f1c7a7:0`); the 19-file record plus
manifest is workspace `diagnostics/tcp-rules-final-1.1.15-2026-11-03/`
(`47c5a5:0`). This TCP phase has one preferred member per tier; retained packet
tests cover broader weighted source affinity. All 74 package inputs and the
delivered bundle remain unchanged. Physical/manual and broader acceptance gates
remain open; offload remains excluded from packet-driven refresh.

November 3 special-action acceptance on unchanged **1.1.15-r1** now passes all
24 direct/fallback, default/unreachable/blackhole, IPv4/IPv6 and LAN/router UDP
combinations. Exact skb/conntrack mark counters and established WAN/NAT session
checks pass. The complete extended native routing/NAT suite then passes, including
weighted egress, TCP reply symmetry, offline recovery and identity retirement.
The initial client ignores soft ICMP errors; synthetic LAN capture proves correct
unreachable replies in MultiWAN, output-bypass and kernel-only controls. Enabling
the Linux UDP error queue fixes the test client; no product repair is needed.
The rejected diagnostic quote-guard fixture is qualified separately. Source,
configuration, map, ruleset/rules, netifd and both WANs restore. Independent raw
checks pass (`42d8f3:0`); the 25-file record plus manifest is workspace
`diagnostics/special-actions-final-1.1.15-2026-11-03/` (`2437b4:0`). The SDK snapshot
predates this test-only extension; all 74 package inputs still match and the
delivered bundle is byte-identical. Earlier test inputs remain frozen.

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

November 3 previous candidate: **1.1.14-r1 is held for the shutdown repair;
1.1.12 and the unreleased 1.1.13 test build remain held.** The dependency
repair command now includes the FIB module. LuCI defaults no longer write an
unused option or commit a valid existing configuration; missing globals still
initialize. Both failures have regressions. Full ash/dash, UI and packaging gates
pass (`195787:0`, `59dea2:0`, `ca4361:0`). Three SDKs verify only those two payload
changes relative to 1.1.12, with core/hooks/helper/Nping/view payloads unchanged
(`8ff69f:0`). Actual 1.1.13-to-1.1.14 installation preserves config/comments with
local_source absent, healthy workers and both bound WAN probes. Installed repair
tests and private real-UCI pending-edit preservation pass. Original config/map,
source, WANs, netifd identity and stopped baseline restore; all three unique
worker identities retire (`b5d99e:0`, `6b97ec:0`, independent `3d03f5:0`). The
held 1.1.13 transaction succeeded before failing conffile preservation; it remains
qualified as the real obsolete-bootstrap defect. The private direct-script UCI
test does not cover every OpenWrt package hook. Frozen records are
`diagnostics/sdk-1.1.14-validated-sources-2026-11-03/` (127 files) and
`deps-final-1.1.14-2026-11-03/` (22 files), each plus a manifest. The 50-file
AArch64 candidate retains fifteen rollback baselines (`6499ac:0`). Physical,
manual, production signing/publication and full-parity gates remain open.

November 3 native software flowtable proof on installed 1.1.12 uses the identical
current packet engine. Both families return every 12 normal and 22
offload/removal messages. Actual OFFLOAD tags, flowtable JSON and counters prove
the fast path bypasses the hook: normal 8/8 ingress/core becomes 22/14 during
offload. Four-second affinity expires during active offloaded traffic, then
refreshes for the same connections after removal. The removal interval observes
7 ingress/6 core packets per family while traffic/deletion overlap; it is not
an instantaneous cutover measurement. Routing marks remain correct, namespaces
are removed and the exact original baseline restores. Native/capture/independent
checks pass (`30a6f7:0`, `b7916e:0`, `2ac7f1:0`); the twelve-file record plus
manifest is `diagnostics/flowtable-1.1.12-2026-11-03/`. The first incomplete fixture
is qualified separately. Offload stays excluded from packet-driven sticky
refresh; hardware/DSA/load remain unverified. No firewall setting is changed.

Retained 1.1.12 compatibility record: final 1.1.12 APKs pass a fresh stock
OpenWrt 25.12.6 boot with `ipv6.disable=1` and real IPv6 socket rejection.
Two IPv4 trackers, one monitor, actual bound probes/hostname DNS, real route and
provider-default recovery, failure/recovery, fw4 reload, restart and read-only
CLI/RPC pass. Raw counters record 56/43 intended tracker packets and no wrong
source/device traffic. Exact original configuration/hosts/source, netifd identity,
both WANs and stopped baseline restore; all six earlier worker identities retire.
Completion/capture/independent verification pass (`2dc4ab:0`, `3f590b:0`,
`e0801f:0`). A pre-install background serial-format ioctl failure and successful
foreground setup/post-dependency resume remain qualified in the frozen record
`diagnostics/ipv4-disabled-final-1.1.12-2026-11-03/` (`22ebe1:0`). The guest is
retired. Product sources and delivered APKs are unchanged. Custom CONFIG_IPV6=n
kernels and physical/manual acceptance remain outside this proof.

November 3 SDK scope on 1.1.12: all three exact SDK builds now gate hidden default-m kernel
packages while retaining fixed built-in defaults, dependencies, target settings
and signing configuration. Generated kernel APK counts fall from 922 to 21 on
AArch64, 889 to 47 on ARMv7 and 892 to 31 on MIPSel. All NFT/helper/Nping and
AArch64 LuCI APK bytes match frozen 1.1.12 and product input hashes are unchanged
(`ee4ee7:0`). Feed CI and the fresh-SDK guide use the same selector. Target
metadata now matches each complete matrix record after fixing the local archive
wrapper's variable collision. Packaging and configure-step syntax checks pass
(`6e3bca:0`, `84b467:0`). Initial/qualified and final evidence are respectively
`diagnostics/sdk-scope-first-inputs-1.1.12-2026-11-03/` and
`diagnostics/sdk-scope-final-1.1.12-2026-11-03/`. Package counts do not establish
CI wall time. The production six-package signing/publication workflow remains
unexecuted; these changes do not alter the runtime or delivered bundles.

November 3 previous candidate: **1.1.12-r1; held for dependency-repair and LuCI bootstrap corrections.** Actual IPv4 peer and IPv6 no-prefix-route addresses exist only in the local FIB; their connections incorrectly receive WAN identity (`7e5cf6:1`). An unmarked `fib daddr type local` check now assigns the default mark before user policies, while retaining incoming WAN identity. New address recognition needs no copied local-table state. APK and raw installation explicitly require `kmod-nft-fib`. The full packet suite now classifies nonlocal policy destinations before later test-only DNAT delivers them to listeners; explicit local/address-change tests pass (`2fdec9:0`). Real routing/NAT passes (`27497c:0`). Three SDK builds match current sources; only core payload changes (`e8c786:0`). UI/packaging and raw-installer/feed checks pass (`a7bd56:0`, `224dd3:0`, `845e8b:0`). After a first undiagnosed ownership-stage dash abort, focused tracing and a complete shell retry pass (`145405:0`, `5f8c64:0`); the initial cause remains unproven. Actual 1.1.11-to-1.1.12 APK installation preserves conffiles. Native nftables 1.1.6 passes eight local/address-change cases, actual replies, explicit affinity-cache inspection and unrelated skb/conntrack QoS bits (`16cc5042:0`). Incoming WAN reply identity and special-range controls pass. Exact payload/config/map, network-manager identity, three original WANs and stopped runtime restore (`f23891b0:0`); independent final archive checks pass (`60cbca:0`). Removed-address packets are classified before confirmation with forwarding disabled; their end-to-end forwarding is not claimed by that fixture. Qualified fixture corrections and the genuine upgrade log are retained. The 44-file AArch64 bundle includes thirteen rollback baselines. Frozen evidence is workspace `diagnostics/sdk-1.1.12-validated-sources-2026-11-03/` and `local-bypass-final-1.1.12-2026-11-03/`. Physical/manual acceptance and full parity remain open. No push or publication occurred.

November 3 previous candidate: **1.1.11-r1; held for the router-local bypass repair.** An actual namespace packet reproduction shows limited broadcast receiving WAN policy bits (`96d956:1`). Upstream bypass includes `224.0.0.0/3`; the NFT hook covered only multicast `/4`. The minimal fix extends the existing early return to `/3`, covering reserved IPv4 and limited broadcast. The full packet suite passes 13 cases on both LAN and WAN ingress (`60664f:0`), including IPv6 multicast/ND/redirect, ordinary boundary traffic and unrelated marks. Routing/NAT, ash/dash, UI and packaging pass (`4480c4:0`, `9499c3:0`, `3da666:0`, `f4af2e:0`). Three SDK builds match current inputs, with only the backend core payload changed (`ba4bc1:0`). Native nftables 1.1.6 reproduces the old broadcast failure, then actual 1.1.10-to-1.1.11 APK installation passes limited broadcast/reserved/multicast bypass, ordinary boundary WAN selection and unrelated skb marks (`0e8b4e38:0`). Both-family incoming UDP/sticky/rebuild checks pass. Exact installed hashes, conffiles, map, network-manager identity, three original WANs and stopped runtime restore (`df4c51:0`); independent archive checks pass (`8a5daf:0`). The 41-file AArch64 bundle includes twelve rollback baselines. Frozen records are workspace `diagnostics/sdk-1.1.11-validated-sources-2026-11-03/` and `special-traffic-1.1.11-2026-11-03/`. Older evidence remains labeled with its tested version. Physical/manual acceptance and full parity remain open. No push or publication occurred.

November 3 additional proof on unchanged 1.1.10: the full packet suite passes five ordered-rule cases per family and 44 additional skb/conntrack identities (`15259a:0`). Default/nonsticky first matches prevent later sticky pollution, the first sticky match owns affinity, and a predicate miss selects the next rule. Combined source/destination CIDRs, source device, port lists/ranges, reordering, source-device edits and sticky off/on edits pass for fresh and established flows. A temporary core missing only the first-match refresh return fails the new overlap assertion; the verifier accepts that expected failure (`28b578:0`). All 74 package inputs and delivered APKs remain unchanged. The seven-file record plus manifest is workspace `diagnostics/overlapping-rules-1.1.10-2026-11-03/`. This is WSL nftables 1.0.2 classification/conntrack proof, not additional native or hardware acceptance. The original SDK evidence retains its earlier test snapshot.

November 2 previous candidate: **1.1.10-r1; now held for the special-traffic repair.** A point-to-point WAN reproduction creates an unwanted remote-source sticky entry (`5ddd28:1`). Per-family guards now return WAN ingress before client sticky refresh, retaining the incoming conntrack mark. Both-family packet regressions pass (`65ee20:0`), including established/new inbound flows, user-rule rebuild without netifd, failed snapshots preserving live rules, removal of stale guards after device replacement and repeated rebuilds. Routing/NAT and all CI shell gates pass (`f66ad5:0`, `0e5168:0`); UI/packaging checks pass (`088e61:0`, `6ba7e2:0`). Three SDK builds match current sources, with only the backend core payload changed (`992ebe:0`). Native nftables 1.1.6 reproduces both-family pollution in 1.1.9. Actual final APK upgrade to 1.1.10 then passes both-family UDP replies, correct WAN conntrack marks and empty sticky sets before/after user-rule rebuild (`737121d8:0`). Exact installed hashes, conffiles, identity map, network-manager identity, three original WANs and the stopped runtime restore (`bb1b60:0`); independent raw archive verification passes (`ffcd07:0`). The 38-file AArch64 bundle includes eleven exact rollback baselines (`d4392d:0`). Frozen SDK/native evidence is under workspace `diagnostics/sdk-1.1.10-validated-sources-2026-11-02/` and `sticky-ingress-1.1.10-2026-11-02/`. Older broader integration evidence remains labeled with its actual version. No push or publication occurred. Supported compatibility is standard OpenWrt 25.12 images, including runtime-disabled IPv6; custom `CONFIG_IPV6=n` kernels are outside scope by user instruction. Physical/manual acceptance and full parity remain open.

November 2 previous candidate: unreleased **1.1.9-r1**. Native nftables 1.1.6 preserves `typeof` declarations in both textual and JSON set output. Final 1.1.8 wrongly rejects valid expression-backed address sets (`aa0ea122:0`, recorded failure results). The shared check now asks `nft describe` for the datatype. A regression fails before the repair (`a0d249:1`); the complete packet suite passes afterward (`272c64:0`, WSL nftables 1.0.2), including actual matching and preservation of working rules after invalid input. Native OpenWrt 25.12.6/nftables 1.1.6 passes 15 staged cases (`df8b7b0e:0`) and the same cases after the actual 1.1.8-to-1.1.9 APK upgrade (`f26c5a92:0`). Exact installed hashes, unchanged conffiles, all three WANs up, unchanged network-manager identity and a clean stopped baseline pass (`13c76b8f:0`); independent archive verification passes (`c7b97c:0`). All three SDK builds match current sources. Only the backend core payload changes; hooks, socket helpers, Nping and LuCI runtime payloads remain identical (`b798a9:0`). The 35-file AArch64 bundle includes ten rollback baselines. Native bundle checksums and the stopped read-only collector also pass, preserving source, conffiles and absent runtime (`d0e3a186:0`); final host verification checks all 35 bundle, 119 SDK and four native-evidence files, plus the unchanged 32-file 1.1.8 bundle (`49fc87:0`). SDK sources and native evidence are frozen under workspace `diagnostics/sdk-1.1.9-validated-sources-2026-11-02/` and `native-set-types-1.1.9-2026-11-02/`. Earlier bundles remain unchanged.

Additional native 1.1.9 RA/DHCPv6 verification passes (`a389da30:0`). A stock odhcpd provider advertises the actual gateway; no static default is added. IA_NA plus IA_PD and PD-only operation both pass acquisition, default withdrawal/recovery, committed policy membership and routed LAN client replies while retaining tracker identity. PD-only probes use a delegated bridge address with no global WAN address. Independent raw PCAP/state checks confirm Router Lifetimes 12/0/12, actual DHCPv6 replies, both source modes and WAN mark 65536 (`d08802:0`). Exact source/configuration hashes, original three WANs, network-manager identity and a clean stopped baseline restore (`cf067c58:0`). Rejected provider-setting and premature-policy-sampling fixtures are qualified separately in the nine-file frozen evidence directory `diagnostics/dhcp6-ra-1.1.9-2026-11-02/`. No product inputs or delivered APKs changed. This covers the recorded virtual RA topology; other providers/options and physical RA/prefix-assignment cases remain open.

Current final 1.1.9 helpers also pass the complete unchanged socket/resolver suite on full-system ARMv7 and MIPSel 25.12.6 guests. Both targets pass native common assertions, all 15 set-type cases, six DNS-server cases and both-family hostname ping/Nping. Independent verification checks actual final SDK APKs/helper hashes, target 32-bit ELF machine IDs, intended DNS wire sources and preserved baselines (`31f67f:0`); native captures pass (`4ec15e36:0`, `3a58861d:0`). The ten-file frozen record is `diagnostics/cross32-native-final-1.1.9-2026-11-02/`. The private ARM test uses the compatible A15 rootfs on an A7 CPU and explicitly whitelists the exact A7 APK architecture; production guards remain unchanged. No product inputs or delivered APKs changed. This adds current resolver and external-set coverage, not new physical-board or whole-system acceptance.

Current 1.1.9 also passes full-system 32-bit lifecycle/routing checks. Both guests run four trackers and two monitors with mask `0x80000300`, propagate/withdraw 32 actual routes per family across both policy tables and connected sets, isolate ordinary offline marks, retain bound DNS and recover both failed WANs. All six worker identities stay stable through those transitions. Restart replaces them, and final readback proves all twelve earlier PID/start identities retired. Repeated TERM exits cleanly in both families. Original configuration, saved map, network-manager identity, two WANs and absent runtime/workspaces restore. Independent raw verification passes (`b7715a:0`); final captures pass (`fe1aa806:0`, `af4afef7:0`). Eleven frozen files are under `diagnostics/cross32-lifecycle-1.1.9-2026-11-02/`. Product inputs and delivered APKs are unchanged. The following PPPoE profile adds protocol coverage; physical-router acceptance remains open.

Installed 1.1.9 now passes actual IPv4 PPPoE integration (`7686c232:0`). Two stock local rp-pppoe providers and real netifd/pppd clients negotiate addresses and dynamic L3 devices. Six fresh UDP/443 and four TCP/443 flows retain source affinity. Established UDP retains a six-second sticky entry after nine seconds. Carrier loss removes the failed PPP device and committed policy/sticky membership; fresh TCP and UDP use the surviving WAN. Reconnection negotiates a different address and interface identity, with recovered tracking and bound traffic. Sixty UDP replies remain on the surviving WAN during recovery. Independent raw discovery/IPCP, packet, FIB/nft/procd and hash checks pass (`870321:0`); exact conffiles, saved map, network-manager identity, three WANs and absent runtime/topology restore (`0ee71712:0`). The record is `diagnostics/pppoe-1.1.9-2026-11-02/`. Both rejected preliminary fixtures are qualified: a missing managed bridge and a nonresponding forked UDP echo service. No product sources or APKs changed. Providers are synthetic and use no PPP authentication. Physical PPPoE/DSA, additional provider options, sustained load and manual LuCI remain open.

Native source-routing verification on installed 1.1.9 now closes that software gate (`78c487:0`, independent `7eeb4e:0`). Real IA_NA/IA_PD and PD-only profiles with `source_routing=1` retain every declared source selector in copied defaults, reject unrelated marked sources and recover router/client replies after real RA withdrawal. Exact raw RA/DHCPv6, FIB/nft/procd and baseline evidence is retained under `diagnostics/source-routing-1.1.9-2026-11-02/`; capture also passes (`550a22b2:0`). Comparing identical installed hashes with the unchanged earlier native `source_routing=0` record proves selector removal in copied policy defaults. Provider-owned main routes retain their selectors in both modes. No product sources or APKs changed. The current official mwan3 2.12.5 reference was also rechecked: all four changes after the cached 2.12.2 tree are already covered. Four focused regressions pass (`65ed9a:0`); ten frozen reference files and source fingerprints are under `diagnostics/mwan3-2.12.5-reference-2026-11-02/` (`5c801e:0`).

Current final 1.1.9 also passes a fresh IPv6-disabled stock-kernel profile (`75ed3cc5:0`, independent `e1a652:0`). Actual final APKs run two IPv4 trackers and one monitor, current bound hostname DNS, route/default restoration, failover, fw4 reload, worker restart and read-only CLI/RPC. Raw counters prove the intended probe source/device; saved states prove stable workers before restart, replacements afterward and retirement of all six earlier PID/start identities. Exact configuration/hosts/runtime hashes, network-manager identity and the prepared two-WAN baseline restore. Evidence is under `diagnostics/ipv4-disabled-final-1.1.9-2026-11-02/`; download/console/transfer fixture issues are retained separately and qualified. The guest was retired. No product sources or APKs changed. This uses `ipv6.disable=1` with real unavailable IPv6 sockets, not `CONFIG_IPV6=n`. Linux 6.12's `NF_TABLES_INET` depends on compiled IPv6, and the current backend uses `inet`; custom kernels without that facility are outside the user-selected standard-image scope. Historical "IPv4-only kernel" labels must not imply broader proof.

Further crash-dump analysis and experimental stock netifd patching are skipped at the user's request. The stock network manager exited during live profile removal with MultiWAN stopped; no platform fix has been validated. Physical PPPoE/DSA/load, manual LuCI, remaining topology cases, production signing/publication and full parity remain open.

November 2 previous: unreleased **1.1.8-r1** fixes false IPv4 DNS tracking failures for dual-address server names while preserving Nping's numeric interface conversion and socket-family isolation. The rejected first helper and its native Nping assertion are retained separately. Final native DNS cases, hostname ping and both-family Nping replies pass (`5e2dd2b8:0`, `66c7f52a:0`), with independent payload/fixture verification (`ad75a1:0`). All three SDK builds match current sources; only the helper library payload changes from 1.1.7, while backend/hooks, Nping and LuCI runtime payloads remain identical (`3a2430:0`). An actual stopped-1.0.13 upgrade refuses unknown history (`2445a7b3:0`); a real guest reboot then clears old marks and automatically starts reordered WAN IDs, completed trackers and bound probes (`9ee20220:0`, independent `e26356:0`). The 32-file AArch64 bundle has nine rollback baselines and passes native checksums/read-only collection (`06477da7:0`). Evidence is frozen under workspace `diagnostics/sdk-1.1.8-validated-sources-2026-11-02/`, `dns-server-family-final-1.1.8-2026-11-02/` and `reboot-upgrade-1.1.8-2026-11-02/`. Earlier bundles stay frozen. Physical/manual acceptance, remaining topology/platform cases, production publication and full parity remain open.

November 2 update: unreleased **1.1.7-r1** is ready for controlled router testing. Without old rules or a saved identity map, final 1.1.6 reused a WAN mark after a pre-stopped 1.0.13 upgrade and ID reorder (`744f7bc4:1`). Package and raw installers now record upgrade provenance; unknown ownership stops startup and requires reboot. Focused ash/dash tests, all three SDK builds and actual running-1.0.13/final-1.1.6 upgrades pass. Stopped-legacy refusal/recovered-ownership and stopped-modern reorder pass (`11b402e0:0`); independent raw checks cover all four transitions (`88594b30:0`). The legacy fixture restores authentic captured rules for recovery and does not exercise an actual reboot. A new 29-file AArch64 bundle includes eight rollback baselines; native checksums and stopped collector pass (`9f20dc8f:0`). Earlier bundles stay frozen. Complete signed-feed, route-stress, IPv6 expiry and HTTP gates below used final 1.1.6 and were not all repeated on 1.1.7. Physical/manual acceptance and full parity remain open.

Reference checked on October 30, 2026: official OpenWrt packages `master`, mwan3 **2.12.5**. The cached upstream tree is useful for comparison but predates some current fixes. The initial NFT audit used revision `0d9f296` (NFT 1.0.13). Final **1.1.6-r1** additionally repairs an expired delegated tracker source and ordinary route-notification backlog. Focused regressions, complete native route stress, all three backend/helper SDK builds, published-1.0.13 and immediate-1.1.5 upgrades, a real signed-feed upgrade and installed overlapping-PD recovery pass. The unchanged LuCI 1.1.6 APK is reused from its verified SDK build; actual HTTP assets and administrator/read-only API checks pass. A 26-file AArch64 bundle is ready for controlled router testing. The archived interim 1.1.6 APKs lack the final monitor change. Earlier bundles stay unchanged. Browser access is disabled by the user; interactive LuCI, physical-router acceptance and the other documented topology/history gates remain open. General production sign-off and full parity are unproven.

Primary references: [runtime](https://github.com/openwrt/packages/blob/master/net/mwan3/files/lib/mwan3/mwan3.sh), [common helpers](https://github.com/openwrt/packages/blob/master/net/mwan3/files/lib/mwan3/common.sh), [tracker](https://github.com/openwrt/packages/blob/master/net/mwan3/files/usr/sbin/mwan3track), [route monitor](https://github.com/openwrt/packages/blob/master/net/mwan3/files/usr/sbin/mwan3rtmon), [CLI](https://github.com/openwrt/packages/blob/master/net/mwan3/files/usr/sbin/mwan3), [package/build](https://github.com/openwrt/packages/blob/master/net/mwan3/Makefile), and [LuCI](https://github.com/openwrt/luci/tree/master/applications/luci-app-mwan3).

## Release baseline and parser verification

An additional November 1 native IPv4-only check found a 1.1.4 route-withdrawal
regression: notification whitespace no longer matches normalized owned-table
snapshots, leaving deleted routes installed. The shared sanitizer repair passes
staged native IPv4-only and IPv6 withdrawal checks. Further testing reproduced
removal of a recovery default still declared by netifd. Unreleased 1.1.5 source
uses provider-aware reconciliation for that deletion and passes its focused
regression. Combined native IPv4-only and IPv6 tests now pass, including bound
traffic through retained defaults and actual IPv6 provider withdrawal. Earlier
startup failures came from lost executable permissions during test staging;
the harness now sets and verifies mode 0755. Three final SDK builds, source/APK
fingerprints and full shell/packet/routing gates pass. Actual APK upgrades from
six earlier versions pass (`a630cc91:0`). Native private signed-index
trust checks pass, including unknown-key rejection (`56b4431f:0`), but its raw
install log shows already-installed packages were skipped. Actual installation
now passes as a genuine 1.1.4-to-1.1.5 upgrade (`77c36b70:0`), with raw logs
confirming all three upgrades (`e451f949:0`). A separate 1.1.5 bundle has 23
checked files and six rollback baselines, ready for a controlled LAN-connected
router test. Physical acceptance and remaining parity gates stay open.
Hold the frozen 1.1.4 installation. Its earlier build/packet results do not
cover these newly reproduced failures.

The primary deployment baseline for the repair work is **OpenWrt 25.12.6**. Its [tagged nftables package](https://github.com/openwrt/openwrt/blob/v25.12.6/package/network/utils/nftables/Makefile) uses **nftables 1.1.6-r2**. The 25.12 branch uses **libnftnl 1.3.1**. The default `nftables` provider is `nftables-nojson`; this runtime needs the explicit **`nftables-json`** variant because cleanup and status call `nft -j`. Installation and upgrade must resolve the variant conflict safely.

On October 30, the retained `tests/test-nft-packets.py` suite passed against an official-source build of nftables **1.1.6**, libnftnl **1.3.1**, libmnl **1.0.5**, and JSON support, inside a disposable user/network namespace. The nftables and libnftnl source archives matched OpenWrt's recorded SHA256 hashes. The build used a private prefix and did not install host packages.

This pass proves the tested generated rules and set behavior with that userspace version on the WSL kernel. It covers 100-flow source affinity, skb/conntrack mark preservation, established-flow sticky refresh, failover/recovery membership, three-member equal weighting, logging order, connected-route updates, external-set matching and preservation across routing stop/start, and a shared-device IPv6 mark. APK/musl builds have separate evidence below. The parser test does not prove target kernel/modules, installed router configuration, or physical WAN behavior.

Reproduction script and output: workspace-level `diagnostics/nft116-repair-build-2026-10-30.sh` and `diagnostics/nft116-repair-build-2026-10-30.log`. The log records SHA256 hashes of the three product sources and packet test before execution, and verifies those files remained unchanged through the run. Later source edits require renewed relevant proof. These narrow assertions do not automatically complete the broader checklist below.

Earlier parser work covered nftables 1.0.8/1.1.1. The current release targets OpenWrt 25.12.x; OPKG 23.05/24.10 feeds are frozen. Existing release assets remain available but do not receive these repairs.

## Repair evidence, October 30–November 1, 2026

The following checks passed against the repaired sources. Fixtures replace UCI/netifd/probe output where stated; those tests do not claim full OpenWrt integration.

| Area | Retained evidence | Proven behavior and limits |
| --- | --- | --- |
| Marks and source selection | `tests/test-nft-common.sh` | Mask normalization, capacity, unrelated bits, family/source selection and delegated-prefix fallback with controlled network inputs. |
| Policies and rules | `tests/test-nft-policy.sh`, `tests/test-nft-packets.py` | Family-specific tiers, disabled/stale interfaces, cumulative three-WAN weights, invalid input and transaction rollback. Actual nft packet tests verify sticky affinity, refresh, failover/recovery, logging order and external address sets. |
| Forwarding and session continuity | `tests/test-nft-routing.py` | Real IPv4/IPv6 forwarding and replies, 1:3 weighting, IPv4 SNAT/reverse NAT, TCP on both WANs, incoming backup symmetry, established default/NAT continuity, offline isolation, scoped UDP/ICMP cleanup, same-tuple recovery and surviving backup sessions. Uses disposable namespaces and controlled netifd/UCI data. |
| Routes and cleanup | `tests/test-nft-routes.sh`, `tests/test-nft-route-snapshot.sh`, `tests/test-nft-rtmon.sh`, `tests/test-nft-rtmon-lock.sh`, `tests/test-nft-rtmon-startup.sh`, `tests/test-nft-default-route.sh`, packet/routing suites | Flag sanitization, extra-table monitoring, duplicate-source retention, checked source/owned-table snapshots, interrupted-dump preservation, atomic overlapping-prefix replacement, source-specific IPv6/device-only default restoration, failed-update resynchronization, service-serialized events with committed interface IDs, verified subscription before initial reconciliation, and owned FIB cleanup after configuration removal. |
| Grouped nexthops | `tests/test-nft-nexthop.sh`, routing/monitor/startup suites; workspace `diagnostics/vm-nexthop-groups-2026-10-31.sh` | Complete multipath records, per-WAN projection of groups and inline paths, equivalent gateway merging and exact relative weights. Namespace checks cover failed member reads, safe rejection of an unrepresentable ratio, ordinary replacement, withdrawal and no kernel mutations for unchanged routes. Staged source passes real OpenWrt 25.12.6 IPv4/IPv6 group notifications, member/gateway changes, marked lookups, both compatibility modes, inline notifications, bound probes and cleanup. Matching source fingerprints are present in the rebuilt 1.1.1 APK, whose live upgrade gates also pass. |
| Sticky and conntrack cleanup | `tests/test-nft-cleanup.sh`, packet/routing suites | Nested timed concat JSON, exact family/masked mark selection, all-protocol deletion, actual/partial counts, expiry races and failure reporting. Real packet tests cover active policy membership changes. |
| Tracking and recovery | `tests/test-nft-tracker.sh`, `tests/test-nft-recovery.sh` | Bound wrapper environment/argv, ping/httping/nping/DNS parsing, partial loss, thresholds, IPv6 options, invalid methods, transition scores and helper-only offline bypass. Probe programs and hotplug are controlled fixtures. |
| Native binding and processes | `tests/test-nft-sockopt.sh`, `tests/test-nft-processes.sh` | Actual socket source/device/mark egress for IPv4/IPv6, explicit/failed binds, high/duplicate descriptors, concurrent use, PID identity, lock ownership, real signals and child cleanup. Opposite-family datagram sockets permit metadata ioctls while bind/connect/send/sendto/sendmsg/sendmmsg reject traffic. Native musl Nping verifies the metadata compatibility repair. |
| CLI, RPC and LuCI | `tests/test-nft-cli.sh`, `tests/test-nft-rpc.sh`, `tests/test-nft-diagnostics.sh`, `tests/test-nft-ui.js` | Quoted argv/exit codes, structured family-specific reports, member weights, empty state, diagnostics, validators and read-only permissions. Does not replace browser/rpcd integration. |
| Migration and feed selection | `tests/test-nft-migration.sh`, `tests/test-nft-feed.sh`, `tests/test-nft-packaging.py` | Backup failure preserves configuration, retries are idempotent, exact architecture/release selection rejects unsupported variants, official SDK identity/SHA256 checks reject mismatches. |
| Target package builds | Workspace `diagnostics/sdk-25.12.6-*/build.json`, `build.log`, `*.apk.metadata` | Official OpenWrt 25.12.6 SDK builds passed for `aarch64_generic`, `arm_cortex-a7_neon-vfpv4`, and `mipsel_24kc`. Backend APK is noarch and identical across builds; helper has the exact target architecture and libc/libgcc dependencies. Source and APK hashes are recorded. Final backend/helper compile steps took 1.06-1.13 seconds per target; SDK extraction/setup is additional. |
| Isolated package installation | Workspace `diagnostics/install-nft-apks-2026-10-30.py` and `.log` | AArch64 APKs resolved dependencies from official release feeds and installed into a disposable root containing firewall4. Reinstall preserved modified UCI configuration and user hook. Target scripts were disabled; this does not prove procd/post-install execution, signed feed trust, or physical-router upgrades. |
| Restart identity and process ownership | `tests/test-nft-identity.sh`, `tests/test-nft-lifecycle.sh`, `tests/test-nft-ownership.sh`, routing suite | Saved maps detect removed/reordered/disabled/family-changed interface IDs and changed masks. Scoped guards prevent retired marks from being recreated by old live rules during purge/rebuild. Actual IPv4/IPv6 forwarding, local INPUT/OUTPUT and surviving unaffected sessions pass. Fixtures cover guard/purge/release failures and incomplete-startup refusal. Actual live 1.0.13 migration, stopped-legacy unknown-history refusal and final 1.1.8 recovery through a real reboot pass as recorded above. Process selection requires private, owned child records and PID/start-time identity; an editor of a helper script is excluded. Lifecycle tests also reject a status directory without a live routing hook. |
| Initial offline and event rollback | `tests/test-nft-hotplug.sh`, workspace `diagnostics/vm-initial-offline-2026-10-30.sh` | Cold/repeated offline ifup uses recovery-only rules; warm policy membership follows committed state. Actual VM IPv4/IPv6 marked-route isolation and bound recovery pings pass. Mocked route/policy/rule failures verify rollback. |
| Initially absent optional tables | Expanded packet suite, workspace `diagnostics/vm-late-table-2026-10-30.sh` | An absent table is empty rather than a startup failure; genuine read failures preserve sets. Both-family packet tests and native VM startup/late insertion/removal pass. The phase waits for actual monitor readiness. |
| Netifd source refresh | Hotplug/tracker tests, workspace `diagnostics/vm-address-update-2026-10-30.sh` | Real IPv4 replacement without link cycling refreshes source/routing. Offline refresh retains policy exclusion, updates exact helper recovery source and recovers when DNS fault is removed. Same-prefix VM control temporarily enables address promotion, as described in remaining checks. Separate IPv6 and alias/device evidence follows below. |
| Native optional probes | Workspace `diagnostics/vm-native-probes-2026-10-31.sh`, `vm-nping-binding-2026-10-31.sh` | Actual tracker rounds pass for Nping ICMP/TCP/UDP, HTTP/HTTPS quality and DNS in both families, plus IPv4 ARP/arping. Capture proves ARP egress/source. IPv6 uses controlled reachable UDP/HTTP/HTTPS/DNS responders; the QEMU DNS proxy itself is unavailable over IPv6. Nping 7.992 fixes the 7.95 dependency failures. HTTPing 3.5 requires an unbracketed IPv6 literal in its CLI URL. |
| Native DNS settings and set lifecycle | Workspace `diagnostics/vm-dns-options-2026-10-31.sh`, `vm-dns-sets-2026-10-31.sh` | Response-loss measurements prove BusyBox timeout/retry options; tracker now passes configured values. Actual dnsmasq-full 2.93 populates both address families. Optional timed elements expire and repopulate; untimed sets retain addresses. fw4 reload, DNS restart and routing stop/start preserve external sets. DNS TTL alone does not expire an untimed set. |
| Native RPC registration and status | Workspace `diagnostics/vm-rpc-registration-2026-10-31.sh`, `vm-rpc-status-2026-10-31.sh`, RPC/UI tests | Package callback registers an initially absent RPC object while retaining six workers and conffiles. Actual status reports stopped/running, four online/up WANs, equal family weights and connected networks. Both UI renderers have stopped/transition regressions; browser interaction is still open. |
| LuCI packaging and HTTP access | Packaging/UI tests, workspace `diagnostics/vm-ui-http-check-2026-10-31.py` and actual SDK build | A Linux Git checkout left the diagnostics helper non-executable; the package preparation hook now sets 0755. SDK tests reproduce Git modes and reject group/world writable paths. Actual LuCI login, ten dispatch paths and installed view assets pass over HTTP. Native read-only sessions can execute safe helpers while WAN/UCI mutations are denied. The ACL now grants both file.exec and the narrow command permissions. Interactive browser validation remains open because local browser use is disabled in Work settings. |
| Administrative interface state | Tracker/hotplug tests, workspace `diagnostics/vm-manual-state-2026-10-31.sh` | Repeated manual down remains disabled with netifd still up, metadata updates do not unpause it, and explicit up recovers both families. Missing-device startup retains automatic retry. Signal tests verify that a later down cancels a pending up. Native down/up and source refresh are separate from actual netifd device transitions. |
| Final packaged LuCI/backend | Workspace `diagnostics/vm-final-ui-packages-2026-10-31.sh`, `vm-ui-http-check-2026-10-31.py`, `check-installed-ui-2026-10-31.js` | Corrected SDK packages install the current tested tracker, retain conffiles and six workers, and create executable diagnostics with secure file/directory modes. Actual installed/minified modules parse, ten LuCI routes/assets load, safe read-only helper calls succeed and WAN/UCI writes are denied. The clean UI install avoids directory permissions left by an earlier diagnostic NTFS copy; the builder now reproduces Linux Git modes. |
| Native netifd availability | Workspace `diagnostics/vm-netifd-state-2026-10-31.sh` | Actual WAN down/up pauses and resumes the same tracker while shared-device IPv6 stays online. A cold service with an unavailable backup WAN starts a waiting tracker; real ifup restores policy and bound DNS. The phase waits for both tracker and committed routing state, since those updates are asynchronous. |
| Native IPv6 source refresh | Workspace `diagnostics/vm-ipv6-control-2026-10-31.sh`, `vm-ipv6-update-2026-10-31.sh` | Actual notify_proto address replacement works in the stopped control and active service. Raw-output counters prove tracker probes use the new source. Offline replacement preserves exclusion, changes the exact helper recovery selector, isolates ordinary marks and recovers after fault removal. Shared-device IPv4 remains online. This is address replacement, not a delegated-prefix lease proof. |
| Family aliases and replacement devices | Common/hotplug/route/status tests; workspace `diagnostics/vm-alias-update-2026-10-31.sh`, `vm-ipv6-alias-update-2026-10-31.sh` | Actual late `_4`/`_6` alias creation refreshes the logical tracker source. Alias removal pauses that same tracker; recreation on another device resumes it with observed new-source/device probes, matching lookup rules and defaults, and no stale old default. User hooks receive the configured logical name. The same-family primary WAN is disabled during replacement to avoid ambiguous ownership of one device. This does not prove arbitrary concurrent same-family WAN sharing, PPPoE/VLAN behavior or delegated-prefix lease handling. |
| Tagged VLAN and bridge WANs | Workspace `diagnostics/vm-vlan-bridge-2026-11-01.sh`, `vm-vlan-provider-carrier-2026-11-01.sh`, `vlan-bridge-runtime-2026-11-01/` | Actual installed 1.1.4 passes IPv4/IPv6 VLAN 208 packets, netifd migration to a bridge containing the VLAN, exact tracker source/device refresh without PID changes, ordinary WAN marks, fw4 reload, offline isolation with bound recovery traffic, carrier recovery and restored original four-WAN baseline (`436e04cd:0`, capture `e85842b4:0`). Provider address-retention controls pass with MultiWAN stopped. Checks wait for current-device packets and completed routing transitions; early stale-state samples are retained as fixture failures. Physical switch/DSA/PPPoE and sustained load remain separate. |
| Native identity guard and package | Workspace `diagnostics/vm-reconcile-guard-2026-10-31.sh`, `vm-reconcile-package-2026-10-31.sh` | On OpenWrt 25.12.6/nftables 1.1.6, actual marked ICMP/ICMPv6 controls work before retirement, then cannot recreate purged old marks. A deliberately failed route callback, followed by successful interfaces, retains the guard and old map. Actual UCI reordering/start retries successfully, commits new IDs and removes the guard; bound DNS/IPv6 ping recover. The final SDK backend preserves conffiles and starts six workers. Integration reporting/concurrent route updates remain separate gates. |
| Routing protection and alias reporting | RPC/CLI/UI/status tests; workspace `diagnostics/vm-reconcile-guard-2026-10-31.sh`, `vm-rpc-alias-2026-10-31.sh`, `vm-ipv6-alias-update-2026-10-31.sh` | Native RPC/CLI expose held protection during successful and failed startup, then clear it after recovery while preserving actual tracker health and live-service state. Both LuCI renderers retain health cards and add an incomplete-configuration warning. IPv4/IPv6 RPC aliases report their own link/uptime while the parent is down; CLI uptime also follows the active alias and uses zero after lookup failure. `enabled=yes` reports true; configured-disabled status overrides stale health without changing actual link metadata. Interactive browser display remains unverified. |

The archived 1.1.3 SDK artifacts matched their source and APK fingerprints in all four output
directories. The identical noarch backend APK SHA256 is
`ab5eef3f8441bdf72df25eba65a3a5aececce7f573c404c404e5aa708555cf0c`.
The LuCI APK SHA256 is
`5fcb018b90b5a10d3e70ca42f5e8317f674207c8064ec54fdf4960ecf68366e2`.
All 15 JavaScript/helper/ACL/menu payload hashes match frozen 1.1.2; only its
package metadata version changed. Earlier SDK manifests/logs/metadata remain
archived alongside unchanged candidate bundles. Final installed-package checks
for 1.1.3 pass as recorded below. Current 1.1.4 outputs pass the same fingerprint
checker (`f0f0b3:0`); the new noarch backend SHA256 is
`5141fc6498b656a61e364fe6fa63383bf6dc8caa9946e4c521d52b9ba7a65229`.
The only production source changes since 1.1.3 are monitor cleanup and version
metadata. All three helper binaries and all 16 installed LuCI payload hashes and
modes remain identical (`c374c0:0`). Full shell/syntax checks pass (`52590d:0`).
The repeated-TERM regression fails before the repair and passes afterward.

Official 25.12.6 full-system ARMv7 and MIPSel guests now pass the complete socket
suite against the actual packaged helpers, native common helpers, four trackers,
both route monitors, sparse bit-31 policy routing, offline isolation, bound DNS,
recovery and procd restart/stop. The 1.1.3 MIPSel run exposed stale shutdown
workspaces: a second TERM interrupts cleanup after the first handler resets
signals. Staged 1.1.4 passes repeated signals in both families and the full
lifecycle with no stale workspaces (`82e45bf2:0`). Actual ARMv7 1.1.3-to-1.1.4
installation and the same final gates pass (`077399cd:0`). Installed MIPSel
1.1.4 revalidation also passes (`ed31e330:0`). The MIPSel
upgrade transaction had already preserved conffiles and installed matching
payloads; its first post-install signal fixture lost the injection race to fast
cleanup. The final fixture temporarily stops the owned child to hold that window,
then resumes it after the second TERM. The official ARM guest
uses an A15 rootfs on an emulated Cortex-A7; its private APK whitelist additionally
accepts the exact A7 helper ABI. This is virtual CPU/kernel proof, not board,
PPPoE, sustained-load or physical WAN acceptance. See workspace
`diagnostics/cross32-runtime/README.md` and `openwrt-cross32/*/console.log`.

Final AArch64 1.1.4 upgrades from 1.0.13/1.1.0/1.1.1/1.1.2 pass together with
the original clean baseline after each (`972350a2:0`). The separate frozen-1.1.3
upgrade also passes (`14746737:0`). All target source/APK hashes are pinned.
Configuration/comments, user hooks, matching modern WAN conntracks, QoS-only
state and an unrelated monitor survive. Changed workers retire; unchanged
trackers may stay supervised. Legacy WAN-marked state retires once. Policies,
health, bound DNS, RPC and executable UI helper recover. The real procd stop
control also passes with its owned monitor child SIGSTOPed on MIPSel
(`deeeab16:0`) and AArch64 (`44e677a5:0`), followed by clean baseline restoration.
This falsifies the separate premature-stop hypothesis for these controls;
no additional shutdown change was made.

Actual optional probes now pass on both 32-bit targets: Nping ARP/ICMP/TCP/UDP,
arping, HTTP/HTTPS quality samples and DNS (`72c40c3c:0`, `0fd4194b:0`). The
tracker and target tools execute in the guests. IPv6 HTTP/TLS/UDP/DNS use
controlled loopback responders; IPv4 DNS/HTTPS also exercise external responses.
The responders are stopped after the checks, and original guest configuration
and clean stopped baselines are restored. The 1.1.4 user bundle has 20
checksummed files and rollback APKs for all five prior versions; shell and
PowerShell guide syntax pass (`7950e3:0`, `19519e:0`). Feed publication and the
remaining hardware/integration gates are separate.
All three targets also build the optional `multiwan-nft-nping` package from the
source version/hash used by the official OpenWrt master recipe. Cached-source
Nping compile steps take 44–46 seconds locally; backend/helper compilation is
about one second. SDK extraction/setup and downloads are additional. The
workspace `diagnostics/check-nft-artifacts-2026-10-31.py` checks current source
and APK fingerprints for all three targets and parses workflow YAML.
The expanded optional-table packet assertions also passed against the privately
built official nftables 1.1.6. Actual routing/NAT regressions passed again after
the event and native-probe changes. Native grouped-route source checks pass;
final 1.1.1 package upgrade and HTTP integration results are recorded below.

### Actual OpenWrt ARM64 VM

An official [OpenWrt 25.12.6 armsr/armv8 image](https://downloads.openwrt.org/releases/25.12.6/targets/armsr/armv8/) ran under private QEMU binaries with two virtual WANs. Both kernel/rootfs downloads matched the official SHA256 list. This uses the target musl runtime, BusyBox 1.37.0, kernel 6.12.112, nftables 1.1.6, procd, netifd, ubus, dnsmasq and fw4. No host network interface or physical router was modified.

Workspace evidence lives in `diagnostics/openwrt-vm-25.12.6/console.log` and the retained `diagnostics/vm-*-2026-10-30.sh` phase scripts. The console contains failed reproductions followed by repaired passes; a phase success does not erase an unresolved gate.

Verified in that VM:

- Final 1.1.3 package batch (`9e3f82d2:0`) passes actual upgrades from published 1.0.13 and frozen 1.1.0/1.1.1/1.1.2, verifying baseline fingerprints, preserved configuration/hooks/QoS, retired old workers, unrelated-monitor survival and recovered health/membership. Modern unchanged WAN sessions survive; legacy WAN marks retire once. Four installed changed-file hashes match tested source. Installed guard rejection/retry, strict stopped/active/post-stop reporting and cold/sparse-mask/failure-state checks then pass. Original four-WAN configuration, source hashes and clean stopped-service baseline are verified after every phase. The 1.1.3 bundle has 17 checked files, shell-checked install/rollback blocks and four matching rollback baselines. This is a controlled-test candidate, not full physical or release acceptance.

- Injected guard creation failure on installed 1.1.2 reproduced an unapplied cache (`0x55005500`) beside old live rules/committed map (`0x003f0000`) and a misleading successful start exit (`4ff273e5:1`). Workers, rules and sessions survived; the cache changed incorrectly. Source 1.1.3 now prepares the desired mask without publishing it, reconciles protection first, atomically publishes the mask and restores the previous cache if base replacement fails. Worker definitions follow successful base loading. Native guard/cache-publication/base failures and successful retries all pass (`ba0f9b55:0`), retaining old cache/map/rules and six worker identities, preserving QoS, respecting protected session retirement, and recovering IPv4/IPv6 probes. Original package files and clean baseline are restored after every phase. The `service_started` callback returns the recorded startup result through [OpenWrt's rc.common callback path](https://github.com/openwrt/openwrt/blob/v25.12.6/package/base-files/files/etc/rc.common#L122-L134). Final package repetitions pass as recorded above.

- Worktree 1.1.3 fixes stopped CLI reporting (`vm-cli-reporting-2026-11-01.sh`, `36e0199e:0`). A checked chain inventory identifies the exact owned hook, so foreign chains with the same name cannot make a stopped service appear active; failed inventory reads remain errors. Stopped reports succeed without querying absent derived objects, retain disabled-interface labels and expose actual tracker state. Active policy reporting propagates failed table/member reads, including an earlier failed policy followed by a successful one. Native before/active/after-stop checks inject inventory, table, member, set, rule and individual-interface failures, preserving errors and read-only behavior. Original 1.1.2 files/configuration/hooks/map and the clean baseline are restored. Full shell and focused ash/dash regressions pass; final package proof is recorded above.

- A cold CLI query on frozen 1.1.1 created a mask cache; a subsequent UCI edit to `0x55005500` then started with the old `0x003f0000` (`5df65a65:1`). The 1.1.2 source separates read-only initialization from startup and ignores inactive hotplug before initialization. Focused red/green regressions and the full shell suite pass. Staged native checks (`8723483e:0`, `vm-cold-mask-2026-11-01.sh`) verify absent runtime after CLI reports/bound use/inactive hotplug, current sparse-mask startup despite an old cache, both-family lookup rules and probes, retirement of old WAN conntracks, preserved QoS, and active-mask use/cleanup after an unapplied edit. Original package files/configuration and the clean baseline are restored. SDK builds and current source/APK fingerprints pass for all three targets; installed-package repetitions are separate below.
- A failure-path regression then exposed cache publication before interface-capacity validation in the initial draft. Final initialization validates before creating directories or publishing the mask. Ash/dash regressions and the full shell suite pass; final native staged checks (`12f63290:0`) also prove that rejected cold initialization creates no runtime and rejected warm initialization preserves the applied cache/map. Final builds and source/APK fingerprints pass on all three targets. Superseded draft packages remain archived as evidence and are not the current candidate.
- Final 1.1.2 APK integration (`823d910b:0`) repeats live upgrades from actual 1.0.13 and frozen 1.1.0/1.1.1 packages, preserving configuration/hooks/QoS/unrelated monitors and restoring health/membership. Matching modern WAN conntracks survive; legacy marks retire once. Each phase passes the original four-WAN stopped-service baseline. All four changed installed file hashes then match the final source, and the cold-mask fixture passes in installed mode, including both rejected-startup cases, actual IPv4/IPv6 rules/probes and applied-mask cleanup. The final local bundle has 14 checked files and matching rollback APKs for all three prior versions. This does not close stopped CLI output, physical WAN or full-parity gates.

- Final 1.1.1 APKs pass live upgrades from the actual 1.0.13 packages and the frozen 1.1.0 candidate (`vm-upgrade-1.1.1-2026-11-01.sh`, both profiles, console marker `55ee373b:0`). Both preserve configuration bytes/comments, hooks, QoS-only conntracks and an unrelated monitor, retire old workers, commit identities and restore WAN health/membership. Legacy WAN marks retire once; matching 1.1.0 WAN conntracks survive. Each profile restores the original four-WAN configuration and clean stopped-service baseline. Final LuCI package queries also preserve absent runtime state (`vm-readonly-ui-package-2026-11-01.sh`, `dabd7fa7:0`). Physical PPPoE acceptance remains open.
- Final 1.1.1 LuCI HTTP integration passes actual root/read-only login, ten dispatch paths/assets, stopped-service status, safe helper execution and denied WAN/UCI changes. All ten installed/minified modules parse. Unlike the earlier helper, the final helper leaves routing runtime absent after stopped-service diagnostics. Temporary test credentials/ACL and reverse channels are removed, original rpcd configuration is restored byte-for-byte and the original stopped-service baseline passes (`e4552f67:0`). This is HTTP/RPC validation, not interactive browser validation.

- Actual APK installation/reinstallation with package scripts enabled; modified UCI configuration and user hook survive.
- Running package upgrade retains six supervised workers; fresh backend/helper installation starts all six workers. Startup checks executable/library availability and nft JSON support, so APK's not-yet-committed dependency database does not suppress startup. Changed shared code causes procd to refresh tracker and route-monitor processes.
- Four configured IPv4/IPv6 interface chains, four tracking workers and two route-monitor workers; real service start/restart/stop.
- Real IPv4 and IPv6 route events during live interface reorder: the same old monitor keeps the applied IDs before configuration apply, waits while the service lock is held, and uses the new IDs after release. The former IPv4 monitor corrupted the newly reassigned primary table and sent its marked traffic through the backup WAN. Initial population and events now share the service lock; a pinned committed-map inode controls configuration refresh. Fresh workers reject configuration whose IDs do not match the applied map. Shell tests also cover inherited descriptors, failure cleanup, stopped-state isolation and termination while waiting.
- Native startup injection reproduced a deleted policy route surviving and a replacement route missing after the initial snapshot. The monitor now starts first, verifies its own netlink socket has the required family subscription, and then reconciles routes and connected/custom sets under the service lock. Real IPv4/IPv6 add/delete events remain queued during that snapshot; stale non-default routes and connected elements from before subscription are removed. Startup tests use actual netlink sockets, reserve a separate socket's PID port ID, and cover delayed/wrong subscriptions, child failure, inherited manager descriptors and TERM cleanup. The family groups and bind order were checked against [upstream ipmonitor](https://github.com/iproute2/iproute2/blob/main/ip/ipmonitor.c) and [libnetlink](https://github.com/iproute2/iproute2/blob/main/lib/libnetlink.c). Burst overflow recovery is covered below; sustained-load throughput and stale same-device recovery defaults remain separate checks.
- Native iproute2 6.18.0 overflow reproduced a live monitor retaining withdrawn routes and stale connected elements after 5,559 kernel notification drops. Both IPv4 and IPv6 now recover by retiring the affected child/FIFO, creating a verified fresh subscription, and reconciling through the existing service lock in the same supervised parent. Applied configuration stays cached across an unapplied UCI reorder. The shell fixture covers six consecutive IPv4 losses and two IPv6 losses without consuming procd crash retries, plus owned cleanup. Recovery treats any monitor stderr as an unreliable stream and does not parse locale-specific messages or architecture-specific errno values. Evidence: workspace `diagnostics/vm-rtmon-overflow-2026-10-31.sh`, route batches generated by `prepare-rtmon-overflow-2026-10-31.py`, and the extended startup regression. See [iproute2 6.18 libnetlink](https://github.com/iproute2/iproute2/blob/v6.18.0/lib/libnetlink.c) for its continue-after-ENOBUFS behavior. This proves burst-loss recovery; sustained-load throughput remains a separate check.
- Same-device stale default gateways/metrics reproduced actual wrong-nexthop selection in both families. Cleanup now retains only defaults still present in the source snapshot or declared by the provider, using canonical installed route lines. Native `vm-default-reconcile-2026-10-31.sh` verifies stale removal, no deletion of a still-declared recovery default when main lacks it, actual helper-only offline probes forced through that default, and actual netifd withdrawal while the link remains up. Shell tests also cover multiple source-specific defaults, device-only routes, IPv6 zero-metric normalization, whitespace, malformed/unknown/partial provider data and failed kernel verification. Provider uncertainty stops cleanup rather than being treated as withdrawal. The real routing/NAT suite represents its manually installed routes with an explicit empty netifd declaration; provider integration is exercised separately in the native VM.
- Injected source-dump failures reproduced silent deletion of a still-live additional-table route in both families. Shared collection now checks main, configured additional tables and owned-table inventories before cleanup; absent optional tables remain valid empty inputs. Failed dumps and iproute2's success-with-interruption/truncation warnings preserve existing FIB routes and NFT sets. Native `vm-route-snapshot-2026-10-31.sh` verifies actual kernel/NFT preservation, failure after provider restoration, and convergence after real withdrawal/recovery. These are injected read failures, not a claim of spontaneous kernel dump interruption. Shell tests also cover valid empty-source cleanup, duplicate-route connected-set refresh, aggregated event failures and fresh subscription/full reconciliation after a failed update. Guarded/stopped updates do not restart the stream. Expanded packet tests on nftables 1.1.6 verify set preservation for both warning forms. The warning behavior is documented in [iproute2 6.18 libnetlink](https://github.com/iproute2/iproute2/blob/v6.18.0/lib/libnetlink.c).
- Missing-map simulation reproduced startup skipping protection while previous rules still assigned retired IDs. The runtime now recovers one valid mask from live owned rules, saves a transient `legacy` record and guards all nonzero marks in that namespace before scoped all-protocol retirement. Mixed/unknown masks and failed conntrack dumps stop migration; a failed rebuild retains the old mask and protection until a successful map commit. Expanded routing tests cover actual IPv4/IPv6 forwarding, INPUT/OUTPUT, old WAN/default retirement, preserved QoS-only conntracks and same-session recovery. Native `vm-reconcile-guard-2026-10-31.sh legacy` also verifies failed/successful rebuilds and RPC/CLI protection reporting. The separate historical-package test below now proves a live 1.0.13 upgrade. Version 1.1.7 now refuses a pre-stopped upgrade without ownership evidence; the native refusal and recovery cases are recorded above.
- Native `vm-upgrade-1.0.13-2026-10-31.sh` installs the actual published 1.0.13 backend and LuCI APKs, verifies six installed file hashes against the user's router report, then upgrades to the rebuilt 1.1.0 backend/helper/LuCI APKs. The test uses two IPv4 WANs, 4:1 weights, TCP/443 sticky at 180 seconds and a nonsticky default. Config bytes/comments and the user hook survive; old worker identities retire; WAN-marked conntracks are purged while QoS-only state and an unrelated monitor survive. The new identity map commits, protection disappears, both tracker/committed states become online, both policy members return, and separate sticky refresh, bound backup DNS, RPC and executable UI diagnostics work. Cleanup restores the original four-WAN configuration and stopped-service baseline. This is actual package-script integration on virtual WANs, not physical PPPoE acceptance.
- The historical upgrade exposed old derived sets missing `auto-merge`: flushing a table does not update existing set metadata. Base loading now atomically recreates only the four connected/custom sets with cached elements restored, preserving external DNS sets in the same table. Packet regressions prove cached-prefix retention, same-start IPv4/IPv6 overlap merging and preservation after read or batch failure. Full packet/routing tests pass with official nftables 1.1.6; the native upgrade passes with real overlapping IPv6 connected prefixes.
- Native `vm-live-mask-2026-10-31.sh` verifies capture of missing ownership before stop and actual service transitions from 0x003f0000 through 0x3f000000 and noncontiguous 0x55005500 back to the original mask. Both families retire old conntracks, retain a QoS-only conntrack, install the expected fwmark rules, preserve mixed QoS/WAN marks and carry bound backup DNS/IPv6 ping after each rebuild. This uses virtual WANs; hardware and sustained-load acceptance remain separate.
- Native `vm-failed-rebuild-routes-2026-10-31.sh` verifies actual IPv4/IPv6 main/additional-table changes while a failed rebuild retains protection and the previous committed identity map. Events occur under the manager lock and then with the failed-rebuild guard held. Retry removes accumulated withdrawals from all owned tables, retains a still-live duplicate source, adds late routes, refreshes connected/custom sets, commits new IDs and restores bound backup DNS/IPv6 ping. This proves final convergence regardless of whether a notification was queued or intentionally skipped while guarded; it does not establish a sustained-load latency bound.
- Native `vm-pd-control-2026-10-31.sh` verifies a PD-only WAN with no global WAN address, real netifd LAN assignment, bound global IPv6 probes, lifetime renewal, offline renumbering, recovery after fault removal, actual prefix/address expiry, copied-route withdrawal and a fresh delegation. The tracker PID stays unchanged; unexpected sources/WANs are counted, and shared-device IPv4 DNS still works. Controlled protocol lease updates exercise netifd and kernel lifetime handling; the later 1.1.7 server profile below adds real DHCPv6 acquisition and renewal. Final 1.1.6 also passes controlled overlapping/deprecated-prefix expiry, as recorded above. Slirp's return-path proxy and a provider host route are calibrated with MultiWAN stopped first.
- Native `vm-dhcp6-acquisition-2026-11-02.sh` uses actual 1.1.7 APKs, Kea 3.0.4 and odhcp6c/netifd for IA_NA plus IA_PD and PD-only leases. Both modes pass real source-bound traffic and completed tracker rounds (`f4a10279:0`). Independent PCAP checks match acquisition and renewal transaction IDs and confirm the selected source on the WAN wire (`45ef71:0`). The PD-only WAN has no global address and uses a delegated LAN source. Configuration/source hashes, original WANs and netifd identity restore; a separate guarded cleanup retires only three expired fixture routes on the loopback LAN (`ccf73f8c:0`). The provider gateway and return route are controlled. Router Advertisement interoperability, every physical LAN topology and hardware PPPoE/DSA/load remain outside this profile. Retained workspace evidence is `diagnostics/dhcp6-acquisition-1.1.7-2026-11-02/`.
- Real IPv4/IPv6 nexthop-object routes reproduced rejected replay and stale deletion when kernel dumps include both `nhid` and expanded `via/dev`. Shared route mutations preserve the object ID and omit only its expansion. Namespace copying, marked lookups, monitor add/delete and stale cleanup pass in expanded and ID-only modes; the complete packet/routing suites pass with official nftables 1.1.6. Native `vm-nexthop-2026-10-31.sh` passes actual monitor add/withdrawal and marked lookups for both families and dump modes on the exact rebuilt AArch64 APK, followed by the original stopped-service baseline. All three SDK outputs have matching current source fingerprints. ID-only defaults and multipath-group ownership are not established by these non-default route tests.
- Subsequent grouped-route work joins kernel continuation lines before parsing prefixes and uses canonical route identities for replacement and stale cleanup. It retains a complete single-WAN object, projects mixed groups to each WAN's compatible paths and merges equivalent gateways without rounding relative weights. Ordinary source replacements remove obsolete group projections. Native diagnostics initially reproduced repeated family snapshots and delayed convergence; bounded queue batching and dependency tracking now avoid rebuilding an unrelated family. A 64-message FIFO test produces one fresh snapshot; a partial record restarts the child stream before rebuilding. Dependency state is published only after successful family reconciliation. The final staged-source native phase passes every group/inline/gateway/withdrawal case in both families and dump modes, then restores the frozen APK baseline. Earlier failed phases remain failures. Ratios that cannot fit a classic route after exact reduction are rejected before changing the table; owned subset groups and resilient bucket affinity remain outside this verified coverage.
- Bound backup IPv4 DNS and IPv6 ping through both WANs. Raw-output counters observe helper marks before the MultiWAN nft hook.
- Normal fw4 reload leaves the MultiWAN table unchanged.
- Injected backup DNS failure removes its active policy membership and isolates its ordinary mark. Bound recovery ping remains usable; DNS recovery restores membership. A primary-WAN ICMP conntrack survives throughout.
- Untracked online WANs receive exactly one shutdown notification with the correct DEVICE.
- Startup removes a recorded owned orphan while startup/stop preserve an unrelated `ip monitor route` process.
- A status query after stop no longer makes `/etc/init.d/multiwan-nft running` succeed.
- Real OpenWrt UCI scalar/list recovery settings, duplicate suppression and failure reporting; legacy values remain unchanged.
- Cold and repeated initial-offline ifup isolate ordinary WAN marks in both families, remove the WAN from active policy, and permit explicitly bound recovery ping.

The VM's built-in IPv6 DNS proxy times out both bound and unbound. A controlled
IPv6 DNS responder now proves native bound DNS tracker operation. Both-family
optional probe rounds, actual rpcd status/registration and dnsmasq native-set
lifecycle pass. Real DHCPv6 acquisition, renewal and a delegated bridge client
also pass as recorded in the remaining-evidence notes. Browser interaction, RA
interoperability, physical PPPoE/DSA/load and signed publication remain separate
checks. Stopped historical ownership refusal and actual 1.1.8 reboot recovery
both pass as recorded above.

All NFT shell regressions passed with BusyBox ash. The portable subset also passed with dash; installed scripts passed syntax checks. NFT/QoS UI checks, existing QoS shell regressions, workflow YAML parsing, version synchronization and `git diff --check` passed. The CI matrix runs architecture builds in parallel, caches SDK archives, and revalidates cached files against official metadata before extraction.

Still required: remaining procd/netifd edge cases, manual LuCI interaction,
physical WAN failure/recovery and PPPoE/DSA/load, additional RA/provider topologies,
and signed feed publication. Flow offload must
remain disabled for per-packet sticky refresh. Generic binding requires
dynamically linked programs, as upstream does.

## Configuration contract

The additional 1.1.7 `vm-dhcp6-bridge-2026-11-02.sh` profile passes both real
server lease modes with a netifd-owned bridge and an actual delegated LAN
client (`15fb8993:0`). PD-only tracking uses the bridge address with no global
WAN address or loopback delegation. Client echoes, original source on the WAN,
conntrack mark 65536 and marked table-1 routing pass. Independent PCAP checks
match acquisition and Renew/Reply (`ec02d1:0`), and the original clean baseline
restores without separate route cleanup (`ae382447:0`). Retained evidence is
`diagnostics/dhcp6-bridge-1.1.7-2026-11-02/`; the failed initial fixture lacked
a UCI bridge device and is qualified separately.

The following names are existing configuration inputs. Native implementation may change internal chains and helpers; it must keep the inputs effective, or provide an explicit, reversible migration.

| Section | Inputs to preserve | Required proof |
| --- | --- | --- |
| `globals` | `mmx_mask`, `logging`, `loglevel`, `rt_table_lookup`, `source_routing` | Valid masks, noncontiguous bits, reserved low-byte protection, malformed-mask rejection, logging order, additional-table bypass, source-specific IPv6 routes. |
| `interface` identity | `enabled`, `family`, `initial_state` | Omitted/false enabled is disabled; IPv4 and IPv6 logical WANs may share one L3 device; online/offline startup works with and without health tracking. |
| `interface` probes | `track_ip`, `track_method`, `httping_ssl`, `reliability`, `count`, `size`, `max_ttl`, `timeout` | Family-aware addresses and hostnames, correct binding, reliability across targets, timeout/exit handling, actual method options. |
| `interface` state timing | `interval`, `failure_interval`, `keep_failure_interval`, `recovery_interval`, `down`, `up` | Correct score boundaries, failed/healthy/mixed rounds, recovery, signal interruptions, preserved counters and timestamps. |
| `interface` quality | `check_quality`, `failure_latency`, `recovery_latency`, `failure_loss`, `recovery_loss` | Partial loss, total loss, threshold equality, hysteresis, malformed/empty tool output, fresh values per probe. |
| `interface` reconnect | `flush_conntrack` | Every supported action is either implemented or deliberately migrated; exact family/mark targeting; another WAN's sessions survive. |
| `member` | `interface`, `metric`, `weight` | Lowest eligible tier per family, weighted selection for 1/2/3+ members, disabled/offline references, invalid values, duplicate references. |
| `policy` | `use_member`, `last_resort` | Ordered membership, independent family tiers, default/unreachable/blackhole fallback, atomic transitions. |
| `rule` | `family`, `proto`, `src_ip`, `src_iface`, `src_port`, `dest_ip`, `dest_port`, `sticky`, `timeout`, `ipset`, `logging`, `use_policy` | Ordered first match, address family, IP/CIDR, logical source interface, port lists/ranges, all protocols, named native sets, sticky lifetime, simple and policy actions. |

`globals.local_source` was written by historical LuCI defaults in both projects, but the official runtime and current LuCI globals view do not read it. It is not a missing current mwan3 feature. Version 1.1.14 removes the unnecessary write after actual upgrade and real-UCI tests prove configuration/pending-edit mutation. Existing values remain untouched; router-originated OUTPUT and binding proof remains separate.

## Behavioral acceptance checklist

These are broad integration requirements. Local evidence above proves subsets; an unchecked item still needs its remaining integration or router proof. Earlier audit reproductions prove old failures, not repairs.

- [ ] **Base ruleset and ownership:** IPv4/IPv6 rules install on supported nftables versions; only owned objects are replaced/deleted; a failed generation or validation preserves live state.
- [ ] **Mark allocation:** spread logical interface IDs through the configured mask; reserve special marks; reject excess interfaces; preserve every unrelated skb and conntrack mark bit, including MultiWAN QoS state.
- [ ] **Connection affinity:** new flows use their selected WAN; established flows retain correct routing; incoming WAN sessions and reply traffic remain symmetric.
- [x] **Special actions:** default/main, unreachable, and blackhole behave correctly for new and established flows, including a policy change during an existing NAT session. Native 1.1.15 covers the 24 both-family LAN/router UDP combinations above, exact special marks and retained WAN/NAT identity; the complete extended routing/NAT suite also passes. This is software acceptance in the recorded namespace topology; physical WAN acceptance remains separate.
- [ ] **Connected/custom/dynamic bypass:** connected destinations, extra routing tables, and externally populated native bypass sets avoid WAN selection. Recheck skb routing for restored WAN marks without destroying the WAN identity saved in conntrack.
- [ ] **Special traffic:** IPv4 multicast/reserved/broadcast destinations and IPv6 multicast/neighbor discovery/redirect traffic follow the documented main-stack path rather than arbitrary WAN policy.
- [ ] **Interface lifecycle:** initial setup, repeated ifup, ifdown without DEVICE, probe-only disconnection, recovery, disable/re-enable, device replacement, and delayed netifd startup remain idempotent.
- [ ] **Route synchronization:** copy only the correct WAN default/link-local routes, propagate LAN/VPN routes, sanitize unsupported flags, preserve still-valid duplicate routes, and synchronize untracked WANs as well as tracked WANs.
- [ ] **IPv6 source choice:** direct addresses and prefix-delegation-only WANs obtain a usable source address from the correct upstream prefix; avoid unrelated prefixes and link-local sources for global probes.
- [x] **Source routing:** `source_routing=0` removes source-specific default selectors from copied policy routes; `1` preserves them in copied routes and restored defaults. Current native IA_NA/IA_PD and PD-only FIB/packet evidence is recorded above; provider-owned main routes retain their original selectors in both modes.
- [ ] **Policy selection:** independent family eligibility, metric failover, correct weighted distribution, and safe empty/fallback policies.
- [ ] **Sticky:** initial selection, repeated new flows, established-flow refresh, idle expiry, metric-tier changes, WAN failure/recovery, exact failed-WAN cleanup, rule edits, and multiple overlapping rules remain correct.
- [ ] **Rule matching:** IPv4/IPv6, all protocols, TCP/UDP ports/lists/ranges, source device changes, source/destination CIDRs, logging before marking, and native set type/family validation.
- [ ] **DNS-populated sets:** external set creation, dnsmasq population, family/table selection, firewall reload, MultiWAN restart, and stale element removal have an explicit native lifecycle.
- [ ] **All upstream tracking methods:** ping, arping, httping/HTTPS, nping ICMP/TCP/UDP, and nslookup. Native binding or the generic socket helper must prevent a probe succeeding through another WAN. Reject IPv6 arping.
- [ ] **Tracker state machine:** target reliability, quality thresholds, scores, intervals, paused states, network signals, child termination, process identity, and error retries remain correct.
- [ ] **Recovery probes:** the intended WAN remains probeable while offline; hostnames work as well as literal IPs; ordinary marked traffic does not silently escape the intended failure behavior.
- [ ] **Reconnect actions:** IPv4 and IPv6 cleanup removes only intended connection state, reports actual results, retries real failures, and does not claim success from an empty wrong-family listing.
- [ ] **Service lifecycle:** start/stop/reload preserve ownership, stop known workers, avoid orphan monitors and PID reuse, respect package-script context, and return useful failures.
- [ ] **Notifications:** user script receives ACTION/INTERFACE/DEVICE for enabled interfaces; startup/shutdown duplicate suppression and lock boundaries are correct.
- [ ] **CLI:** start, stop, restart, ifup, ifdown, interfaces, policies, connected, rules, status, internal IPv4/IPv6, and use preserve argument boundaries and exit codes.
- [ ] **Generic `use`:** an arbitrary external networking program runs with the requested family, source, device, and bypass mark, including a backup/offline interface. A message claiming binding or an unbound fallback is insufficient.
- [ ] **RPC/LuCI:** correct family-specific data, JSON-only output, active members/percentages, tracker status, untracked interfaces, diagnostics, and read/write permissions.
- [ ] **Package/raw installer:** installed files and dependencies match runtime needs; config and user hooks survive upgrade; wrapper/runtime architecture and feed metadata agree; retries and rollback are safe.
- [ ] **Firewall coexistence:** normal fw4 reload preserves routing state. Explicit full ruleset flush has documented recovery. Flow offload is excluded from incompatible per-packet behavior or supported through separate verified integration.
- [ ] **Compatibility matrix:** OpenWrt 25.12.x, with primary native validation on 25.12.6 and nftables 1.1.6-r2 plus JSON support; BusyBox ash, stock kernels with IPv6 disabled, IPv6 operation, bridge/VLAN/PPPoE, multiple WANs, and the selected AArch64/ARMv7/MIPSel libc/CPU targets. Custom CONFIG_IPV6=n kernels are excluded by user instruction. Older parser comparisons are historical; 23.05/24.10 support is frozen.

## Additional gaps addressed during parity mapping

These historical gaps were in addition to the original 19 findings. Repairs now cover the listed code paths; use the evidence and limits above to assess verification. Descriptions below record the original failure. Locations use function names so that repairs do not invalidate line numbers.

| Gap | Existing NFT location | Concrete requirement and upstream reference |
| --- | --- | --- |
| Delegated IPv6 source fallback missing | `common.sh`, `multiwan_nft_get_src_ip` | Current upstream `mwan3_get_src_ip` uses `network_get_prefix6`, then kernel prefix matching with `ip -6 address ls to PREFIX scope global`. NFT falls directly to a WAN device address, which can be link-local on a PD-only PPPoE WAN. |
| nslookup method absent | tracker `validate_track_method` and probe switch | Current upstream supports DNS health checks. Adding an unbound nslookup command would create false recovery through another WAN; generic binding is part of the requirement. |
| IPv6 arping accepted | tracker `validate_track_method` | Upstream rejects arping for IPv6. A native implementation must make the same family check. |
| Hostname recovery selectors omitted | core `multiwan_nft_set_tracker_oif_rules` and `multiwan_nft_add_tracker_exception` | UI accepts hostnames; offline selector construction accepts only literal IP regex matches. Resolve the actual family-specific target tuple or otherwise retain correct bound-probe routing. |
| Other skb mark bits lost on restore | `multiwan_nft_generate_base_ruleset` | Current restore assigns only masked ct bits to the entire skb mark. Upstream masked CONNMARK restore preserves unrelated skb bits. Older supported nftables may require constant-per-interface restore rules instead of an OR between two variable expressions. |
| Connected bypass omitted after restoration | base hook after connection-mark save | Upstream rechecks custom/connected/dynamic destinations after storing the WAN identity. NFT only checks while routing bits are zero. Route changes on established flows need an equivalent main-routing override. |
| IPv6 redirect type omitted | base ICMPv6 exemption | Upstream exempts redirect type 137 as well as types 133-136. NFT's initial exemption stops at neighbor advertisement. |
| Still-valid route deleted from policy tables | route monitor `multiwan_nft_rtmon_route_handle` | Current upstream checks a delete against the complete source route set before removing policy copies. If the same route remains in a configured extra table, the NFT monitor must retain it. |
| Omitted enabled value treated inconsistently | core `multiwan_nft_update_dev_to_table` | Startup uses boolean/default-disabled semantics, but device-to-table mapping reads a raw value without a default. Use consistent boolean handling. |
| CLI argument boundaries and exit status lost | CLI dispatch and `use` | Current upstream dispatches quoted argv, puts binding diagnostics on stderr, and propagates the command's status. NFT uses unquoted expansion and unconditional success. |
| HTTP quality/native option parity | tracker + LuCI interface view | Tracker owner is fixing actual native binding and quality parsing. UI must expose quality where supported, and IPv6 URL literals must remain valid. |
| Default/failure mark persistence differs | base hook | Upstream restores all stored routing marks. NFT intentionally re-evaluates default/failure flows. This needs an explicit policy/NAT continuity test rather than treating either code comment as proof of correctness. |

## Native implementation boundaries

The following implementation differences can preserve the behavior contract without reproducing iptables commands:

- One `inet` table can replace separate family tables when every family-sensitive path is guarded correctly.
- Native sets replace ipset. The [dynamic producer contract](../INSTALL.md#dynamic-bypass-producers) replaces legacy IPv4 `list:set` references with a producer-maintained union of addresses/prefixes. Producers must update that union when inputs change and repopulate after a full service restart. Native sets do not automatically follow other set references.
- The low conntrack byte remains reserved for MultiWAN QoS. The default routing mask moves higher, while valid existing custom masks may remain usable.
- Exact per-WAN connection cleanup is safer than upstream's global conntrack flush, but it is a deliberate behavior change. Old `flush_conntrack` actions must not be silently ignored or discarded without documenting the replacement.
- Long nft chain names remove the old 15-character rule-name limitation. This is an improvement, not a reason to change valid configuration names.
- Existing shell configuration, route selection, and process ownership code can be retained. Correct atomic transactions and retained tests are more valuable than replacing all modules solely because the conversion was AI-generated.

Generic socket binding is not iptables-specific. Upstream uses a compiled preload helper for arbitrary programs. If the project retains architecture-independent packages without that helper, native per-tool options alone do not satisfy generic `use` or nslookup parity. A target-built helper, its tests, and a compatible package/feed plan are required for full coverage; `ip vrf exec` introduces different kernel/cgroup requirements and is not an automatic drop-in replacement.

Normal fw4 ruleset generation [flushes only its owned `inet fw4` table](https://github.com/openwrt/firewall4/blob/master/root/usr/share/firewall4/templates/ruleset.uc). The separate MultiWAN table therefore should survive a normal reload. This does not prove recovery after a user explicitly runs `nft flush ruleset`.

Native 1.1.7 now passes that separate recovery gate (`12cfceaa:0`). Normal reload
preserves four worker identities, the applied map, untimed DNS elements before
fresh lookups, WAN/QoS conntracks and real IPv4/IPv6 client NAT. Full flush reports
routing stopped. Restoring fw4, MultiWAN and dnsmasq-full plus fresh lookups
recovers both-family client NAT and recreated DNS sets without a global
conntrack flush. Source/config hashes and original WAN state restore; netifd
PID stays unchanged and no new core appears. Independent raw/baseline checks
pass (`eb811308:0`). After baseline restoration, the fixture brings temporary
interfaces down before removing their definitions and keeps netifd stable.
Matching-symbol analysis maps all four earlier teardown SIGSEGVs to address
deletion through a null netifd L3 device; the earlier state transition and a
general platform fix remain open. Actual hardware acceptance
and other nftables-owning services are outside this specific native profile.

Linux [flowtable documentation](https://docs.kernel.org/networking/nf_flowtable.html) states that offloaded packets bypass hooks after ingress. A refresh rule in prerouting cannot observe every offloaded packet. Verification must account for offload rather than labeling it supported from a normal-path packet test.

## Required evidence before declaring parity complete

1. Retained tests must assert corrected behavior and exercise actual product generators/functions, with meaningful malformed/failure fixtures.
2. Namespace packet tests must cover both families, several WANs, NAT/replies, long-lived and fresh flows, and topology/policy transitions.
3. Process tests must cover real signals, worker shutdown/restart, locking, and stale process identities without mutating the user's router.
4. Packaging must build the actual target artifacts, including any native helper, and install them into an isolated root with correct dependencies and preserved config.
5. Router acceptance must inspect the installed version/configuration and exercise real WAN failover/recovery, DNS, IPv6 PD, fw4 reload, and expected offload mode. Until then, report the hardware gate as unverified.

No checklist item is complete merely because no additional source defect was found. The main implementation agent owns the final requirement-by-requirement verification and evidence updates.
