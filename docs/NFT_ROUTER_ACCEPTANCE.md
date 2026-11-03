# Router acceptance for NFT 1.1.17

The signed feeds and controlled software checks pass. Physical WAN/provider/DSA,
interactive LuCI and sustained NFT/QoS load require router results. These checks
record those results; the collector does not declare a pass automatically.

Use a LAN SSH connection and save a configuration backup. Follow the
[install guide](../INSTALL.md#router-install-or-upgrade), including the one-time
switch from the old noarch feed. Verify `multiwan-nft` and its LuCI package are
1.1.17-r1. QoS remains 1.0.60. Keep flow offload disabled for sticky refresh.

## Collect a healthy report

Run on the router as root:

```sh
uclient-fetch -O /tmp/collect-nft-audit.sh https://raw.githubusercontent.com/mrep1c/openwrt-multiwan/main/scripts/collect-nft-audit.sh
sh /tmp/collect-nft-audit.sh > /tmp/nft-healthy.txt 2>&1
multiwan-nft status
```

The collector only reads state and waits ten seconds between NFT snapshots.
It sends no test traffic and changes no configuration, services, routes or rules.
Reports include selected MultiWAN settings, addresses, routing state, logs, worker
PIDs, file hashes, listening sockets, system load, qdisc counters and QoS DSCP
rules when available. Long command output is abbreviated. Missing optional tools
and absent tables are recorded, not treated as proof of a product failure.

Review reports before sharing: they contain network addresses and recent logs.
Do not share a configuration backup or the complete AdGuard Home YAML file.

## WAN failure and recovery

Keep SSH connected through LAN. Test one ISP link at a time:

1. Check that both WANs are online and the expected policy members are present.
2. Disconnect only the first ISP link. Wait for its configured tracking threshold
   and confirm the CLI reports that WAN offline.
3. Check that new LAN connections and DNS lookups work through the surviving WAN.
   Existing sessions on the failed public address may need to reconnect.
4. Collect the offline report:

   ```sh
   sh /tmp/collect-nft-audit.sh > /tmp/nft-wan1-down.txt 2>&1
   ```

5. Reconnect the link, wait for online status and collect recovery:

   ```sh
   sh /tmp/collect-nft-audit.sh > /tmp/nft-wan1-recovered.txt 2>&1
   ```

6. Repeat for the other ISP link using `nft-wan2-down.txt` and
   `nft-wan2-recovered.txt`. Record actual interface names and whether new
   connections and DNS recovered. Do not change WAN identity/order during this test.

## Sticky and QoS checks

For the reported TCP/443 rule, keep one TCP/443 connection transmitting beyond
its configured sticky timeout (180 seconds in the original report). While that
connection continues, open fresh connections matching the same sticky rule from
the same client and collect another report. The sticky entry should keep being
refreshed and eligible new connections should retain that WAN. Browsing alone
does not prove established-flow refresh. UDP/443 does not match a TCP-only rule.

With both services enabled, repeat your usual download/upload and latency test
on each WAN. Record workload, duration, throughput and latency, then collect a
report during load. Compare with your previous QoS behavior. Queue counters must
advance on the intended WAN/IFB; an unchanged package or a counter snapshot alone
does not establish sustained performance or correct classification.

## AdGuard Home and LuCI

Check DNS from a LAN client while healthy, during each WAN outage and after
recovery. Confirm expected blocking in AdGuard Home's query log. The original
router report uses ping tracking; that does not rely on DNS health checks.
If tracking is changed to `nslookup`, DNS interception must not redirect a
WAN-specific probe to the local resolver and hide an upstream failure.

Domain-based WAN rules need their named native NFT sets populated. AdGuard Home's
legacy ipset integration does not populate those sets; native nftset support is
tracked in [upstream issue 5136](https://github.com/AdguardTeam/AdGuardHome/issues/5136).
Check the actual DNS path before changing ports or forwarding: avoid resolver
loops. Ordinary IP/port rules do not require DNS-populated sets.

In LuCI, check Overview/Status, Diagnostics and Troubleshooting against the CLI
in healthy, offline and recovered states. Run a diagnostic for each WAN. Check
Globals, Interface, Member, Policy, Rule and Notify for blank pages or JavaScript
errors. Save/apply a reversible logging change, reload to confirm persistence,
then restore its previous value. Confirm WAN health afterward.

## Share results

Copy the report files from the router to your computer, for example in PowerShell:

```powershell
scp -O root@ROUTER_LAN_IP:/tmp/nft-healthy.txt .
```

Repeat with each report filename. Share the reports plus any upgrade errors,
which physical link was disconnected, DNS results, sticky observations, LuCI
failures and load measurements. This is the remaining hardware evidence; the
synthetic checks do not replace it.
