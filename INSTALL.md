# Install Guide

Current MultiWAN NFT builds target OpenWrt 25.12.x (25.12.6 SDK). OPKG 23.05
and 24.10 releases are frozen; their existing release assets are not overwritten.

## Supported native feeds

NFT 1.1.17-r1 is published in all three signed architecture feeds. Hosted
compatibility/build checks and a stock 25.12.6 production-key VM upgrade pass.
QoS remains 1.0.60; its runtime/LuCI contents, permissions, package hooks and
dependencies match the previous published packages. Physical R5S/provider/DSA,
interactive LuCI and sustained combined load still need user validation.

| CPU family | Exact OpenWrt package architecture | SDK target |
| --- | --- | --- |
| AArch64 | `aarch64_generic` | rockchip/armv8 |
| ARMv7 | `arm_cortex-a7_neon-vfpv4` | ipq40xx/generic |
| MIPSel | `mipsel_24kc` | ramips/mt7621 |

These are specific ABI variants, not every ARMv7 or MIPSel CPU. Check
`DISTRIB_ARCH` in `/etc/openwrt_release` or run `apk --print-arch`. Unsupported
variants must use a matching SDK source build; do not force a foreign package.
The three feed jobs run in parallel. The socket helper is one small C source
file; SDK preparation and optional Nping add most of the extra target work.
The feed builder gates the SDK's hidden modular-package defaults instead of
repackaging every available kernel module. Earlier NFT-only 25.12.6 builds reduced kernel
APK packaging from 922 to 21 on AArch64, 889 to 47 on ARMv7 and 892 to 31 on
MIPSel. Required dependencies and target/signing settings are retained; every
candidate APK remains byte-identical. These are package counts, not CI timing
measurements. The combined NFT/QoS feed also selects the transitive kernel
dependencies from SDK package metadata. SDK extraction, feed setup and first
source downloads are additional.

## Optional probe programs

Ping and BusyBox DNS tracking need no optional probe package. For Nping,
install `multiwan-nft-nping` from the matching architecture feed. This optional
package builds only Nping 7.992, using the source version and hash from the
[OpenWrt package recipe](https://github.com/openwrt/packages/blob/master/net/nmap/Makefile).
The OpenWrt 25.12 Nping 7.95 package has broken IPv6 source/filter handling;
IPv6 Nping tracking requires 7.992 or newer. IPv4 can still use the old package.

`multiwan-nft-nping` replaces `nping` or `nping-ssl` when explicitly installed.
It omits Nping's SSL mode and the rest of the Nmap suite. HTTP/HTTPS tracking
uses the separate `httping` package; ARP tracking uses `iputils-arping`.
The optional probe is built for each feed, but is not a backend dependency.
Its source archive is cached between feed builds.

## Router install or upgrade

Run from SSH:

```sh
uclient-fetch -O /tmp/setup-multiwan-feed.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/setup-feed.sh
sh /tmp/setup-multiwan-feed.sh install
```

The helper chooses the architecture feed, installs its signing key, updates
indexes, and installs backend/UI packages. It replaces the former noarch feed
entry, so use it again when upgrading. Modes are `setup`, `install`, `main`,
`luci`, and `remove`.

For an existing NFT installation, run this focused upgrade from LAN after saving
a configuration backup. It switches the former noarch feed and selects the NFT
backend, UI and required socket helper:

```sh
uclient-fetch -O /tmp/setup-multiwan-feed.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/setup-feed.sh
sh /tmp/setup-multiwan-feed.sh setup
apk add --upgrade multiwan-nft luci-app-multiwan-nft
/etc/init.d/multiwan-nft restart
multiwan-nft status
```

`multiwan-nft` automatically requires `multiwan-nft-sockopt` for the selected
CPU, plus `ip-full`, `nftables-json`, `kmod-nft-fib`, `jshn`, `rpcd`, and `conntrack`. Existing
UCI configuration and `/etc/multiwan-nft.user` are conffiles. Back them up before
upgrading a router used for remote access.

Router-owned destinations use a kernel route lookup before WAN policies. New
unmarked local connections use the default routing path, including peer-only
IPv4 and IPv6 no-prefix-route addresses. Address additions/removals affect new
connections immediately. Incoming WAN connections retain their reply identity.

For a manual APK feed URL, substitute the exact architecture:

```text
https://github.com/mrep1c/openwrt-multiwan/releases/download/apk-25.12-ARCHITECTURE/packages.adb
```

Install the matching `mrep1c-openwrt-multiwan-apk.pem` from that same release
under `/etc/apk/keys/` first. The source `.git` URL is not an APK index.

New release URLs become usable only after the build workflow publishes signed
assets. A local source change or local SDK test is not a published feed.

## First upgrade without saved interface identities

When a running NFT installation has no saved interface map, the new runtime
recovers its mark mask from the existing MultiWAN rules. It blocks and retires
connections carrying that old routing namespace before reusing WAN IDs. This
includes main/default marks, so existing connections may need to reconnect once.
Connections carrying only unrelated mark bits are preserved.

The recovered mask remains saved if rebuilding fails; retrying uses that mask
until the new configuration commits. A normal stop with the repaired code also
captures missing ownership before removing the old rules. Mixed or unrecognized
live masks stop migration before connection deletion.

An older package already stopped with both its rules and identity history gone
has no recoverable ownership evidence. From 1.1.7, package and raw upgrades record
the previous installation before replacing its files. If neither live rules nor
a saved map can identify its marks, startup refuses to reuse WAN IDs and logs a
reboot requirement. Reboot the router to clear the old kernel connections and
the volatile upgrade marker together. Do not remove the marker manually or flush
unrelated conntracks. This conservative requirement also applies to a previously
installed package that never ran and therefore has no ownership history.
Ordinary restarts and stopped-service upgrades with a saved map keep unaffected
connection identities. A fresh install or image staging does not set the marker.

## Source SDK build

```sh
echo "src-git multiwan https://github.com/mrep1c/openwrt-multiwan.git" >> feeds.conf.default
./scripts/feeds update multiwan
./scripts/feeds install -p multiwan multiwan-nft multiwan-nft-sockopt multiwan-nft-nping luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
python3 feeds/multiwan/scripts/configure-openwrt-sdk.py . \
  multiwan-nft multiwan-nft-sockopt multiwan-nft-nping \
  luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
make defconfig
python3 feeds/multiwan/scripts/configure-openwrt-sdk.py . \
  multiwan-nft multiwan-nft-sockopt multiwan-nft-nping \
  luci-app-multiwan-nft multiwan-qos luci-app-multiwan-qos
make defconfig
make package/feeds/multiwan/multiwan-nft/compile V=s
```

Run this in a fresh SDK. The selection script resets other package selections,
preserves target/signing settings and includes required kernel dependencies.
The second pass uses the package metadata generated by the first `make defconfig`.
Use `make menuconfig` afterward to add other packages. Full firmware buildroots
use their normal configuration flow instead of this SDK-specific script.

Use the SDK for the router's exact release and target. The backend scripts are
`all`; the helper uses the SDK's target architecture. No prebuilt helper from
another SDK is copied into a noarch package.

## Raw development installer

The raw installer copies scripts but requires the target-built helper package
from a configured feed. It does not compile C on the router:

```sh
sh install.sh main
START_SERVICES=1 sh install.sh main
```

Use package installation for normal upgrades. The raw path preserves existing
configuration/user hooks and migrates old mwan3 filenames with backups.
It prepares all selected downloads and their permissions in a private temporary
directory before migrating configuration, recording upgrade provenance or
replacing live files. Download-preparation failures leave those files unchanged;
dependencies use the package manager's own transactions. Local file-application
changes are journaled before replacement. Handled errors and HUP/INT/TERM restore
prior files, migrated filenames, backup files and upgrade provenance. Failed
requested startup also attempts to restore the prior enabled/running state.
If restoration itself fails, the installer returns failure and prints the private
backup directory for recovery. Power loss and SIGKILL cannot run this cleanup.
Private staging permissions do not change the caller's umask for live directories.

## Native destination sets

A rule's historical `ipset` UCI option now names an address set in
`inet multiwan_nft`. Missing sets are created for the rule family; an unspecified
family creates IPv4 first. Use separate named rules/sets for both families.
Existing address sets may use `type ipv4_addr` / `type ipv6_addr` or an address
expression such as `typeof ip daddr` / `typeof ip6 daddr`. Their declared
datatype must match the rule family. Service, mark and compound sets are rejected.
With dnsmasq-full, an IPv4 example is:

```text
nftset=/youtube.com/4#inet#multiwan_nft#youtube
```

Use `6#` with an IPv6 set/rule. Legacy dnsmasq `ipset=` does not populate nft
sets. External set elements survive MultiWAN stop/start. An explicit full nft
ruleset flush removes them; follow the [full ruleset recovery procedure](#firewall-recovery-after-a-full-ruleset-flush).

Automatically created external sets have no element expiry. DNS cache TTL alone
does not remove their addresses. For a bounded lifetime, create the set with a
timeout before referencing it in a rule, for example:

```sh
nft add set inet multiwan_nft youtube '{ type ipv4_addr; flags interval,timeout; timeout 1h; auto-merge; }'
```

Choose the timeout for the application and query DNS again after expiry to
repopulate it. MultiWAN preserves the existing set definition and elements.
The table must already exist when creating the set. The timeout is a set policy,
not the TTL of each DNS answer.

## Firewall recovery after a full ruleset flush

Normal fw4 reload preserves the separate MultiWAN table. An explicit full
ruleset flush removes fw4 filtering/NAT, MultiWAN hooks and external sets.
Tracker probes can still work through their dedicated routing rules while
MultiWAN correctly reports that routing is stopped.

Use a LAN or console connection. Continue only after each command succeeds.
Restore the firewall first:

```sh
/etc/init.d/firewall restart
```

Restore any separately managed MultiWAN-table set definitions through their
owner, including their address family, interval flags and timeouts. Missing
rule sets otherwise receive the documented untimed defaults. Then rebuild
MultiWAN routing:

```sh
/etc/init.d/multiwan-nft restart
multiwan-nft status
```

If DNS-populated sets are used, restart the nftset-capable DNS service after
those sets exist. For dnsmasq-full:

```sh
/etc/init.d/dnsmasq restart
```

Trigger fresh lookups for the configured domains and verify their set elements.
Restore any additional nftables tables through their owning services as well.
Keep existing conntrack state. With unchanged interface identities and mask,
the routing rebuild preserves WAN and unrelated QoS marks; configured failure
and recovery purges still apply. Full ruleset loss can interrupt traffic until
the firewall and routing are restored.

## Dynamic bypass producers

The service creates `inet multiwan_nft` sets `multiwan_nft_dynamic_v4` and
`multiwan_nft_dynamic_v6`. They contain IPv4 and IPv6 addresses or prefixes,
respectively. Use only the family sets present on the router. Producers own the
elements; MultiWAN owns the set definitions and lifetime.

The old mwan3 IPv4 `list:set` API contains references to other ipsets. Native
dynamic sets contain addresses, not set names. A migrated producer must publish
the union of those referenced addresses/prefixes and update that union whenever
its inputs change. Remove duplicate and overlapping prefixes before publishing.
MultiWAN does not automatically follow references to other native sets. Assign
one producer to maintain the complete union so producers do not erase each
other's entries.

Replace the complete snapshot in one nftables transaction. For example, after
the service has started, a producer with these synthetic destinations can use:

```sh
nft -f - <<'NFT'
flush set inet multiwan_nft multiwan_nft_dynamic_v4
flush set inet multiwan_nft multiwan_nft_dynamic_v6
add element inet multiwan_nft multiwan_nft_dynamic_v4 { 198.18.10.0/24, 198.18.20.25 }
add element inet multiwan_nft multiwan_nft_dynamic_v6 { 2001:db8:100::/64 }
NFT
```

Omit the IPv6 commands when its set is absent. Check the transaction's exit
status; a rejected batch leaves the preceding snapshot in place. An empty union
needs only the corresponding flush command. Prepare the complete batch before
applying it, rather than flushing a live set and filling it with separate calls.

Destination members use main-table routing, including packets whose saved WAN
mark was restored. The WAN identity in conntrack remains available. A matching
source arriving on a WAN bypasses that WAN's ingress classification. Removing
a destination lets fresh flows follow policy again; an existing main-table
connection retains its saved main-table decision. Changing paths can still
interrupt a connection whose NAT source is unsuitable for the new path.
Linux MASQUERADE also retires the old conntrack when its egress device changes.
UDP may need a retry; an established TCP connection needs reconnection. Native
tests verify this boundary separately from fixed-SNAT and IPv6 continuity.

Policy/rule refresh and base-rule reload retain dynamic elements. A full service
stop removes the owned dynamic sets, and start creates empty sets. The producer
must republish after restart or full ruleset recovery. DNS-populated rule sets
have a separate lifecycle; their persistence does not preserve dynamic bypass
members automatically.

## Verification

```sh
apk info -e multiwan-nft multiwan-nft-sockopt luci-app-multiwan-nft
/etc/init.d/multiwan-nft status
nft -j list table inet multiwan_nft
multiwan-nft status
```

Check WAN failover/recovery and IPv6 on the actual router before deploying
remotely. Keep flow offload disabled for packet-driven sticky refresh. Generic
`use` and probes follow upstream's dynamic-linker binding model; static or
setuid binaries do not participate in LD_PRELOAD binding.

Failure events automatically purge only the failed WAN's connection marks.
`flush_conntrack` selects an additional purge during a real offline-to-online
recovery (`ifup` and/or `connected`). Legacy `always` keeps the former migration's
`ifup` meaning; `never` adds no recovery purge. Legacy values are interpreted
without rewriting the configuration. This replaces historical global conntrack
flushes with scoped cleanup; other WANs' sessions remain intact.

Live interface-ID or routing-mask changes temporarily block affected old marks
while their connections are purged and routing is rebuilt. If startup fails,
those marks remain blocked. Correct the logged error and start the service
again; stopping the service removes its temporary guard and routing rules.
CLI and LuCI status views warn while this protection is held. A WAN can still
show Online when its health checks work while affected connections are blocked.

To remove the services, remove the LuCI/backend packages with `apk del`, then
run `sh setup-feed.sh remove` to remove feed entries. Package-manager dependency
tracking handles the helper; do not delete a native library manually.
