#!/usr/bin/env python3
"""Packet regressions using actual generated rules in a disposable net namespace."""
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout


if "--isolated" not in sys.argv:
    raise SystemExit(subprocess.call([
        "unshare", "-Urn", sys.executable, __file__, "--isolated", *sys.argv[1:]
    ]))

REPO = Path(sys.argv[-1]).resolve()
CORE = REPO / "multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
COMMON = CORE.with_name("common.sh")
BODY = "\n".join(CORE.read_text().splitlines()[5:])
MASK = 0x3F0000
TEMP = tempfile.TemporaryDirectory(prefix="multiwan-nft-audit-")
STATE = Path(TEMP.name)
CONFIG = {}
RULE_ORDER = ("test",)


def nft(*args):
    return run(["nft", *args])


def shell(body):
    values = []
    for key, value in CONFIG.items():
        values.append(f"{shlex.quote(key)}) export \"$1={value}\" ;;")
    prelude = f"""
. {shlex.quote(str(COMMON))}
{BODY}
MULTIWAN_NFT_STATUS_DIR={shlex.quote(str(STATE))}
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="$MULTIWAN_NFT_STATUS_DIR/nft_log"
IP4={shlex.quote(shutil.which("ip") + " -4")}
IP6={shlex.quote(shutil.which("ip") + " -6")}
multiwan_nft_iface_tbl=' wan1=1 wan2=2 wan3=3 '
NO_IPV6=0
config_load() {{ :; }}
LOG() {{ printf '%s\\n' "$*" >&2; }}
config_get() {{
    case "$2:$3" in
        {' '.join(values)}
        *) export "$1=${{4:-}}" ;;
    esac
}}
config_get_bool() {{ config_get "$@"; }}
network_get_device() {{ export "$1=$2"; }}
config_foreach() {{
    local callback="$1" type="$2" section
    shift 2
    case "$type" in
        interface) for section in wan1 wan2 wan3; do "$callback" "$section" "$@"; done ;;
        policy) "$callback" balanced "$@" ;;
        rule) for section in {' '.join(shlex.quote(name) for name in RULE_ORDER)}; do "$callback" "$section" "$@"; done ;;
    esac
}}
config_list_foreach() {{
    local section="$1" option="$2" callback="$3" member
    shift 3
    if [ "$section:$option" = balanced:use_member ]; then
        for member in m1 m2 m3; do "$callback" "$member" "$@"; done
    fi
}}
multiwan_nft_init || exit 1
{body}
"""
    result = subprocess.run(["busybox", "ash"], input=prelude, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr + result.stdout)
    return result.stdout


def config(sticky=1, timeout=30, metrics=(1, 1, 1)):
    CONFIG.clear()
    CONFIG.update({
        "test:family": "ipv4", "test:proto": "udp", "test:use_policy": "balanced",
        "test:sticky": str(sticky), "test:timeout": str(timeout),
        "test:logging": "1", "globals:logging": "1",
    })
    for i, metric in enumerate(metrics, 1):
        CONFIG.update({f"wan{i}:family": "ipv4", f"wan{i}:enabled": "1", f"m{i}:interface": f"wan{i}",
                       f"m{i}:weight": "1", f"m{i}:metric": str(metric)})


def set_online(names):
    (STATE / "iface_state").mkdir(exist_ok=True)
    for name in ("wan1", "wan2", "wan3"):
        (STATE / "iface_state" / name).write_text("online" if name in names else "offline")


def delivery_rules():
    # Classify nonlocal destinations before delivering test packets to the local listeners.
    nft("add", "table", "inet", "audit_delivery")
    nft("add", "chain", "inet", "audit_delivery", "deliver", "{ type nat hook prerouting priority -100; }")
    nft("add", "rule", "inet", "audit_delivery", "deliver", "ip daddr 198.51.100.200 udp dport 4444 dnat ip to 192.0.2.1")
    nft("add", "rule", "inet", "audit_delivery", "deliver", "ip6 daddr 2001:db8:99::200 udp dport 4444 dnat ip6 to 2001:db8:1::1")


def setup():
    nft("flush", "ruleset")
    set_online(("wan1", "wan2", "wan3"))
    shell("""
multiwan_nft_load_base_ruleset || exit 1
for iface in wan1 wan2 wan3; do multiwan_nft_create_iface_nft "$iface" "$iface" || exit 1; done
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
""")
    delivery_rules()
    for i in (1, 2, 3):
        nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
            f"ip saddr 192.0.2.2 meta mark & {MASK} == {i << 16} counter comment \"audit_wan{i}\"")


def counts():
    data = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
    found = {}
    for item in data["nftables"]:
        rule = item.get("rule", {})
        comment = rule.get("comment", "")
        if comment.startswith("audit_wan"):
            found[comment] = next(expr["counter"]["packets"] for expr in rule["expr"] if "counter" in expr)
    return found


def entries(family="ipv4", rule="test"):
    return json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_{rule}"))["nftables"][1]["set"].get("elem", [])


# A live upgrade must refresh old set metadata without losing bypass data.
config()
run(["nft", "-f", "-"], input="""
table inet multiwan_nft {
 set multiwan_nft_custom_v4 { type ipv4_addr; flags interval; elements = { 198.18.0.0/24 }; }
 set multiwan_nft_connected_v4 { type ipv4_addr; flags interval; elements = { 192.0.2.0/24 }; }
 set multiwan_nft_custom_v6 { type ipv6_addr; flags interval; elements = { 2001:db8:aa::/64 }; }
 set multiwan_nft_connected_v6 { type ipv6_addr; flags interval; elements = { fdb1:3d5f:f9bd::/64 }; }
 set external_dns { type ipv4_addr; flags interval; elements = { 203.0.113.9 }; }
}
""")
external_before = nft("-s", "list", "set", "inet", "multiwan_nft", "external_dns")
shell("multiwan_nft_load_base_ruleset || exit 1")
for name, prefix in (
    ("custom_v4", "198.18.0.0/24"), ("connected_v4", "192.0.2.0/24"),
    ("custom_v6", "2001:db8:aa::/64"), ("connected_v6", "fdb1:3d5f:f9bd::/64"),
):
    definition = nft("-s", "list", "set", "inet", "multiwan_nft", "multiwan_nft_" + name)
    assert "auto-merge" in definition and prefix in definition, definition
assert nft("-s", "list", "set", "inet", "multiwan_nft", "external_dns") == external_before
before_bad_base = nft("-s", "list", "table", "inet", "multiwan_nft")
for failure in ("batch", "snapshot"):
    shell("NFT_TEST_FAILURE=" + failure + "\n" + """
reject_base() {
    case "$NFT_TEST_FAILURE:$1" in
        batch:-f) { cat; printf '\\ninvalid_base_command\\n'; } | nft "$@" ;;
        snapshot:-s) return 1 ;;
        *) nft "$@" ;;
    esac
}
NFT=reject_base
if multiwan_nft_load_base_ruleset; then exit 1; fi
""")
    assert nft("-s", "list", "table", "inet", "multiwan_nft") == before_bad_base
shell("""
mock4() { printf '198.18.0.0/16 dev lo\\n198.18.0.0/24 dev lo\\n'; }
mock6() { printf 'fdb1:3d5f:f9bd::/60 dev lo\\nfdb1:3d5f:f9bd::/64 dev lo\\n'; }
IP4=mock4 IP6=mock6
multiwan_nft_set_connected_ipv4 && multiwan_nft_set_connected_ipv6 || exit 1
""")
assert "198.18.0.0/16" in nft("-s", "list", "set", "inet", "multiwan_nft", "multiwan_nft_connected_v4")
assert "fdb1:3d5f:f9bd::/60" in nft("-s", "list", "set", "inet", "multiwan_nft", "multiwan_nft_connected_v6")
assert nft("-s", "list", "set", "inet", "multiwan_nft", "external_dns") == external_before
nft("delete", "table", "inet", "multiwan_nft")
print("PASS legacy derived-set metadata upgrade, retained bypass/DNS data, both-family overlaps and atomic failure.")

run(["ip", "link", "set", "lo", "up"])
run(["ip", "link", "add", "audit-lan", "type", "veth", "peer", "name", "audit-client"])
run(["ip", "addr", "add", "192.0.2.1/24", "dev", "audit-lan"])
for device in ("audit-lan", "audit-client"):
    run(["ip", "link", "set", device, "up"])
for device in ("wan1", "wan2", "wan3"):
    run(["ip", "link", "add", device, "type", "dummy"])
    run(["ip", "link", "set", device, "up"])
listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
listener.bind(("192.0.2.1", 4444))
packet_socket = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
packet_socket.bind(("audit-client", 0))
destination_mac = bytes.fromhex(json.loads(run(["ip", "-j", "link", "show", "audit-lan"]))[0]["address"].replace(":", ""))
source_mac = bytes.fromhex(json.loads(run(["ip", "-j", "link", "show", "audit-client"]))[0]["address"].replace(":", ""))


def send(port, source_address="192.0.2.2", destination_address="198.51.100.200", receive=True):
    udp = struct.pack("!HHHH", port, 4444, 9, 0) + b"x"
    header = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), port, 0, 64, 17, 0,
                         socket.inet_aton(source_address), socket.inet_aton(destination_address))
    words = sum(struct.unpack("!10H", header))
    words = (words & 65535) + (words >> 16)
    checksum = (~((words & 65535) + (words >> 16))) & 65535
    header = header[:10] + struct.pack("!H", checksum) + header[12:]
    packet_socket.send(destination_mac + source_mac + b"\x08\x00" + header + udp)
    if receive:
        listener.settimeout(1)
        listener.recvfrom(65535)


config(timeout=30, metrics=(1, 1, 2))
setup()
assert "S test (balanced)" in shell("multiwan_nft_report_rules_v4")
assert not shell("multiwan_nft_report_rules_v6").strip()
nft("add", "table", "inet", "audit_pre")
nft("add", "chain", "inet", "audit_pre", "before", "{ type filter hook prerouting priority -151; }")
nft("add", "rule", "inet", "audit_pre", "before", "ip saddr 192.0.2.2 meta mark set 0x80000000 ct mark set ct mark | 0x2e")
nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
    "ip saddr 192.0.2.2 meta mark & 0x80000000 != 0 ct mark & 0xff == 0x2e ct mark & 0x3f0000 != 0 counter comment \"audit_qos_preserved\"")
for port in range(9000, 9100):
    send(port)
nominal = counts()
assert sorted(nominal.values()) == [0, 0, 100], nominal
print("PASS sticky affinity across 100 fresh flows on", run(["nft", "--version"]).strip(), nominal)
rules = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
qos_counter = next(item["rule"] for item in rules["nftables"] if item.get("rule", {}).get("comment") == "audit_qos_preserved")
assert next(expr["counter"]["packets"] for expr in qos_counter["expr"] if "counter" in expr) == 100
print("PASS skb mark and conntrack QoS byte preserved alongside routing bits.")

config(timeout=2)
setup()
send(10000)
assert entries(), "initial packet did not create sticky entry"
initial = entries()
for _ in range(7):
    time.sleep(0.4)
    send(10000)
after = entries()
assert after, "sticky entry expired during established traffic"
assert sum(counts().values()) == 8, counts()
print("PASS established traffic refreshes sticky timeout.")

config(timeout=30, metrics=(1, 2, 2))
setup()
send(11000)
set_online(("wan2", "wan3"))
shell("multiwan_nft_set_policies_nft || exit 1")
nft("flush", "set", "inet", "multiwan_nft", "multiwan_nft_sticky_ipv4_test")
lookup_chain = nft("list", "chain", "inet", "multiwan_nft", "multiwan_nft_rule_test")
for port in range(11001, 11065):
    send(port)
backup_counts = counts()
assert sorted((backup_counts["audit_wan2"], backup_counts["audit_wan3"])) == [0, 64], backup_counts
assert backup_counts["audit_wan1"] == 1, backup_counts
set_online(("wan1", "wan2", "wan3"))
shell("multiwan_nft_set_policies_nft || exit 1")
send(11065)
assert counts()["audit_wan1"] == 2, counts()
print("PASS sticky failover and recovery follow atomic active policy membership.")

config(sticky=0)
CONFIG["wan1:enabled"] = "0"
setup()
for port in range(9100, 9200):
    send(port)
assert counts()["audit_wan1"] == 0, counts()
assert counts()["audit_wan2"] + counts()["audit_wan3"] == 100, counts()
before_invalid = nft("-s", "list", "table", "inet", "multiwan_nft")
CONFIG["m2:weight"] = "0"
shell("if multiwan_nft_set_policies_nft; then exit 1; fi")
assert nft("-s", "list", "table", "inet", "multiwan_nft") == before_invalid
print("PASS disabled stale-online WAN excluded; invalid policy preserves live rules and eligibility.")

config(sticky=0)
setup()
for port in range(20000, 26000):
    send(port)
balance_counts = counts()
assert all(abs(value - 2000) < 300 for value in balance_counts.values()), balance_counts
print("PASS three-WAN equal weighting across 6000 fresh flows:", balance_counts)

logging_chain = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules"))
log_rule = next(item["rule"] for item in logging_chain["nftables"] if "rule" in item and
                any("log" in expr for expr in item["rule"]["expr"]))
nft("insert", "rule", "inet", "multiwan_nft", "multiwan_nft_rules", "position", str(log_rule["handle"]),
    "meta nfproto ipv4 meta l4proto udp meta mark & 0x3f0000 == 0 counter comment \"audit_log_match\"")
send(26001)
rules = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules"))
log_counter = next(item["rule"] for item in rules["nftables"] if item.get("rule", {}).get("comment") == "audit_log_match")
assert next(expr["counter"]["packets"] for expr in log_counter["expr"] if "counter" in expr) == 1
print("PASS logging predicate matches before policy assigns routing mark.")

config(sticky=0)
setup()
rtmon_body = "\n".join((REPO / "multiwan-nft/files/usr/sbin/multiwan-nft-rtmon").read_text().splitlines()[7:])
shell("MULTIWAN_NFT_RTMON_LIBRARY_ONLY=1\n" + rtmon_body + """
multiwan_nft_update_dev_to_table() { :; }
multiwan_nft_route_line_dev() { unset "$1"; }
config_foreach() { :; }
multiwan_nft_rtmon_route_handle '198.18.0.0/24 dev audit-lan' ipv4
""")
connected = json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", "multiwan_nft_connected_v4"))
assert connected["nftables"][1]["set"].get("elem"), connected
print("PASS route monitor populates connected IPv4 set.")
shell("""
mock_routes() { printf '198.18.1.0/24 dev audit-lan\\n198.18.0.0/16 dev audit-lan\\n'; }
IP4=mock_routes
multiwan_nft_set_connected_ipv4 || exit 1
""")
overlapping = nft("-s", "list", "set", "inet", "multiwan_nft", "multiwan_nft_connected_v4")
assert "198.18.0.0/16" in overlapping, overlapping
shell("IP4=false\nif multiwan_nft_set_connected_ipv4; then exit 1; fi")
assert nft("-s", "list", "set", "inet", "multiwan_nft", "multiwan_nft_connected_v4") == overlapping
print("PASS overlapping route prefixes merge; failed route reads preserve connected sets.")

for family, flag, prefix in (("ipv4", "-4", "192.0.5.0/24"), ("ipv6", "-6", "2001:db8:220::/64")):
    setname = "multiwan_nft_custom_" + ("v4" if family == "ipv4" else "v6")
    refresh = f"multiwan_nft_replace_network_set {setname} {family} 220 || exit 1"
    shell(refresh)
    assert "elem" not in json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", setname))["nftables"][1]["set"]
    run(["ip", flag, "route", "add", "table", "220", prefix, "dev", "lo"])
    shell(refresh)
    populated = nft("-s", "list", "set", "inet", "multiwan_nft", setname)
    assert prefix in populated, populated
    variable = "IP4" if family == "ipv4" else "IP6"
    shell(f"{variable}=false\nif multiwan_nft_replace_network_set {setname} {family} 220; then exit 1; fi")
    assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == populated
    for warning in ("Dump was interrupted and may be inconsistent.", "Message truncated"):
        shell(f"partial_routes() {{ printf '%s\\n' '192.0.8.0/24 dev lo'; printf '%s\\n' '{warning}' >&2; }}\n"
              f"{variable}=partial_routes\nif multiwan_nft_replace_network_set {setname} {family} 220; then exit 1; fi")
        assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == populated
    shell(f"if multiwan_nft_replace_network_set {setname} {family} invalid_table_name; then exit 1; fi")
    assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == populated
    run(["ip", flag, "route", "del", "table", "220", prefix, "dev", "lo"])
    shell(refresh)
    assert prefix not in nft("-s", "list", "set", "inet", "multiwan_nft", setname)
print("PASS absent optional tables, late routes/removal, failed and interrupted reads preserve both-family sets.")

config(sticky=0)
CONFIG["test:ipset"] = "youtube"
CONFIG["test:family"] = "any"
setup()
nft("add", "element", "inet", "multiwan_nft", "youtube", "{ 198.51.100.200 }")
send(27000)
assert sum(counts().values()) == 1, counts()
shell("multiwan_nft_prepare_external_set youtube6 ipv6 || exit 1")
shell("if multiwan_nft_prepare_external_set youtube ipv6; then exit 1; fi")
shell("if multiwan_nft_prepare_external_set multiwan_nft_reserved ipv4; then exit 1; fi")
for setname, family, expression, element in (
    ("expression4", "ipv4", "ip daddr", "198.51.100.200"),
    ("expression6", "ipv6", "ip6 saddr", "2001:db8::1"),
    ("connection4", "ipv4", "ct original ip daddr", "198.51.100.200"),
    ("connection6", "ipv6", "ct reply ip6 saddr", "2001:db8::1"),
):
    nft("add", "set", "inet", "multiwan_nft", setname,
        "{ typeof " + expression + "; elements = { " + element + " }; }")
    existing = nft("-s", "list", "set", "inet", "multiwan_nft", setname)
    shell(f"multiwan_nft_prepare_external_set {setname} {family} || exit 1")
    opposite = "ipv6" if family == "ipv4" else "ipv4"
    shell(f"result=0; multiwan_nft_prepare_external_set {setname} {opposite} || result=$?; [ \"$result\" -eq 2 ]")
    assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == existing
for setname, definition in (
    ("service_set", "type inet_service; elements = { 443 };"),
    ("mark_set", "typeof meta mark; elements = { 1 };"),
    ("compound_set", "typeof ip daddr . tcp dport; elements = { 192.0.2.1 . 443 };"),
):
    nft("add", "set", "inet", "multiwan_nft", setname, "{ " + definition + " }")
    existing = nft("-s", "list", "set", "inet", "multiwan_nft", setname)
    shell(f"if multiwan_nft_prepare_external_set {setname} ipv4; then exit 1; fi")
    assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == existing
CONFIG["test:ipset"] = "expression4"
shell("multiwan_nft_set_user_rules_nft || exit 1")
previous_packets = sum(counts().values())
send(27002)
assert sum(counts().values()) == previous_packets + 1, counts()
previous_rules = nft("-s", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules")
CONFIG["test:ipset"] = "compound_set"
shell("if multiwan_nft_set_user_rules_nft; then exit 1; fi")
assert nft("-s", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules") == previous_rules
CONFIG["test:ipset"] = "youtube"
shell("multiwan_nft_set_user_rules_nft || exit 1")
print("PASS expression-backed IPv4/IPv6 sets, exact family status, non-address rejection, packet matching and failed-rule preservation.")
before_stop = json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", "youtube"))["nftables"][1]["set"]["elem"]
shell("multiwan_nft_unload_ruleset || exit 1")
assert "hook " not in nft("list", "table", "inet", "multiwan_nft")
assert json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", "youtube"))["nftables"][1]["set"]["elem"] == before_stop
shell("""
multiwan_nft_load_base_ruleset || exit 1
for iface in wan1 wan2 wan3; do multiwan_nft_create_iface_nft "$iface" "$iface" || exit 1; done
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
""")
assert json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", "youtube"))["nftables"][1]["set"]["elem"] == before_stop
send(27001)
print("PASS native external set creation, family validation, matching, and preservation across routing stop/start.")

config(sticky=0)
CONFIG["wan2:family"] = "ipv6"
nft("flush", "ruleset")
shell("""
multiwan_nft_load_base_ruleset || exit 1
multiwan_nft_create_iface_nft wan1 audit-lan || exit 1
multiwan_nft_create_iface_nft wan2 audit-lan || exit 1
""")
nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
    "meta nfproto ipv6 meta mark & 0x3f0000 == 0x20000 counter comment \"audit_correct_family\"")
run(["ip", "-6", "addr", "add", "2001:db8:1::1/64", "dev", "audit-lan", "nodad"])
listener6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
listener6.bind(("2001:db8:1::1", 4444))
def send6(port, source_address="2001:db8:1::2", destination_address="2001:db8:99::200", receive=True, icmp_type=None):
    src6 = socket.inet_pton(socket.AF_INET6, source_address)
    dst6 = socket.inet_pton(socket.AF_INET6, destination_address)
    protocol = 17 if icmp_type is None else 58
    if icmp_type is None:
        udp6 = struct.pack("!HHHH", port, 4444, 9, 0) + b"x"
    else:
        control_body = {133: b"\0" * 4, 134: b"\0" * 12,
                        135: b"\0" * 4 + dst6, 136: b"\0" * 4 + dst6,
                        137: b"\0" * 4 + dst6 + dst6}[icmp_type]
        udp6 = struct.pack("!BBH", icmp_type, 0, 0) + control_body
    pseudo = src6 + dst6 + struct.pack("!I3xB", len(udp6), protocol) + udp6
    pseudo += b"\0" * (len(pseudo) % 2)
    checksum_sum = sum(struct.unpack(f"!{len(pseudo) // 2}H", pseudo))
    while checksum_sum >> 16:
        checksum_sum = (checksum_sum & 65535) + (checksum_sum >> 16)
    checksum6 = (~checksum_sum) & 65535 or 65535
    checksum_offset = 6 if icmp_type is None else 2
    udp6 = udp6[:checksum_offset] + struct.pack("!H", checksum6) + udp6[checksum_offset + 2:]
    header6 = struct.pack("!IHBB16s16s", 6 << 28, len(udp6), protocol, 64 if icmp_type is None else 255, src6, dst6)
    packet_socket.send(destination_mac + source_mac + b"\x86\xdd" + header6 + udp6)
    if receive:
        listener6.settimeout(1)
        listener6.recvfrom(65535)

send6(30000, destination_address="2001:db8:1::1")
ipv6_rules = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
wrong_family = next(item["rule"] for item in ipv6_rules["nftables"]
                    if item.get("rule", {}).get("comment") == "audit_correct_family")
assert next(expr["counter"]["packets"] for expr in wrong_family["expr"] if "counter" in expr) == 1
print("PASS shared-device IPv6 ingress receives IPv6 interface mark.")

# A remote source outside the WAN prefix reaches the router's connected address.
nft("add", "element", "inet", "multiwan_nft", "multiwan_nft_connected_v6", "{ 2001:db8:1::/64 }")
nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
    "meta nfproto ipv6 ct mark & 0x3f0000 == 0x20000 meta mark & 0x3f0000 == 0x3f0000 counter comment \"audit_reply_identity\"")
send6(30001, "2001:db8:2::2", "2001:db8:1::1")
ipv6_rules = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
identity = next(item["rule"] for item in ipv6_rules["nftables"]
                if item.get("rule", {}).get("comment") == "audit_reply_identity")
assert next(expr["counter"]["packets"] for expr in identity["expr"] if "counter" in expr) == 1
print("PASS connected override follows conntrack save and preserves incoming WAN identity.")

# Point-to-point WANs have local host addresses outside their connected peer set.
config()
CONFIG["test:family"] = "any"
CONFIG["wan2:family"] = "ipv6"
setup()
for family, previous, local in (
    ("-4", "192.0.2.1/24", "192.0.2.1/32"),
    ("-6", "2001:db8:1::1/64", "2001:db8:1::1/128"),
):
    run(["ip", family, "addr", "del", previous, "dev", "audit-lan"])
    run(["ip", family, "addr", "add", local, "dev", "audit-lan", "nodad"])
run(["ip", "route", "add", "192.0.2.254/32", "dev", "audit-lan"])
run(["ip", "route", "add", "default", "via", "192.0.2.254", "dev", "audit-lan"])
run(["ip", "-6", "route", "add", "default", "dev", "audit-lan"])
nft("add", "element", "inet", "multiwan_nft", "multiwan_nft_connected_v4", "{ 192.0.2.254 }")
shell("multiwan_nft_create_iface_nft wan1 audit-lan && multiwan_nft_create_iface_nft wan2 audit-lan || exit 1")
for family, mark in (("ipv4", 0x10000), ("ipv6", 0x20000)):
    nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
        f'meta nfproto {family} ct mark & {MASK} == {mark} counter comment "audit_incoming_{family}"')
for phase in range(2):
    if phase:
        shell("network_get_device() { return 1; }; multiwan_nft_set_user_rules_nft || exit 1")
    for send_packet, source, destination in ((send, "203.0.113.77", "192.0.2.1"), (send6, "2001:db8:2::77", "2001:db8:1::1")):
        send_packet(42000 + phase, source, destination)
        send_packet(42000 + phase, source, destination)
    state = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
    for family in ("ipv4", "ipv6"):
        identity = next(item["rule"] for item in state["nftables"]
                        if item.get("rule", {}).get("comment") == f"audit_incoming_{family}")
        assert next(expr["counter"]["packets"] for expr in identity["expr"] if "counter" in expr) == 2 * (phase + 1)
        assert not entries(family), f"{family} WAN-originated traffic populated client sticky affinity"
print("PASS both-family WAN ingress keeps conntrack identity without sticky pollution, including rule rebuild without netifd.")

before_snapshot_failure = nft("-s", "list", "table", "inet", "multiwan_nft")
shell("""
reject_snapshot() {
    if [ "$*" = 'list table inet multiwan_nft' ]; then
        [ ! -e "$MULTIWAN_NFT_STATUS_DIR/snapshot-seen" ] || return 1
        touch "$MULTIWAN_NFT_STATUS_DIR/snapshot-seen"
    fi
    nft "$@"
}
NFT=reject_snapshot
if multiwan_nft_set_user_rules_nft; then exit 1; fi
""")
assert nft("-s", "list", "table", "inet", "multiwan_nft") == before_snapshot_failure
shell("multiwan_nft_create_iface_nft wan1 wan1 && multiwan_nft_delete_iface_nft wan2 || exit 1")
guards = nft("list", "chain", "inet", "multiwan_nft", "multiwan_nft_sticky_refresh")
assert 'iifname "audit-lan"' not in guards and "sticky_ingress_wan2" not in guards, guards
assert guards.count("sticky_ingress_wan1") == 1, guards
shell("multiwan_nft_create_iface_nft wan1 wan1 && multiwan_nft_set_user_rules_nft || exit 1")
assert nft("list", "chain", "inet", "multiwan_nft", "multiwan_nft_sticky_refresh").count("sticky_ingress_wan1") == 1
send(42010, "203.0.113.77")
send6(42010, "2001:db8:2::77")
assert entries() and entries("ipv6"), "Former WAN device cannot create client sticky affinity"
print("PASS failed snapshots preserve live rules, device replacement removes stale ingress guards, repeated rebuilds stay idempotent.")

for family, send_packet, expected_mark in (("ipv4", send, 0x10000), ("ipv6", send6, 0x20000)):
    for index, case in enumerate(("default", "nonsticky", "sticky", "first-miss", "selective")):
        config(metrics=(1, 2, 3))
        CONFIG["wan2:family"] = "ipv6"
        CONFIG["test:family"] = family
        RULE_ORDER = ("first", "second", "test")
        for rule in ("first", "second"):
            CONFIG.update({f"{rule}:family": family, f"{rule}:proto": "udp",
                           f"{rule}:use_policy": "balanced", f"{rule}:sticky": "1",
                           f"{rule}:timeout": "30"})
        port = 43000 + index * 30
        sticky_rules = ("first", "second", "test")
        owner = "first"
        if case in ("default", "nonsticky"):
            CONFIG["first:sticky"] = "0"
            sticky_rules = ("second", "test")
            owner = None
        if case == "default":
            CONFIG["first:use_policy"] = "default"
        if case == "first-miss":
            CONFIG["first:src_port"] = str(port + 100)
            owner = "second"
        if case == "selective":
            CONFIG.update({"first:src_port": f"9,{port}:{port + 20}", "first:dest_port": "443,4444",
                           "first:src_iface": "audit-lan",
                           "first:src_ip": "192.0.2.0/24" if family == "ipv4" else "2001:db8:1::/64",
                           "first:dest_ip": "198.51.100.200/32" if family == "ipv4" else "2001:db8:99::200/128"})
        setup()
        mark = MASK if case == "default" else expected_mark
        nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
            f'meta nfproto {family} meta mark & {MASK} == {mark} ct mark & {MASK} == {mark} counter comment "audit_rule_order"')
        for source_port in (port, port, port + 1):
            send_packet(source_port)
        for rule in sticky_rules:
            assert bool(entries(family, rule)) == (rule == owner), (family, case, rule, owner)
        observed = 3
        if case == "selective":
            RULE_ORDER = ("second", "first", "test")
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            nft("flush", "set", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_first")
            for source_port in (port, port + 2):
                send_packet(source_port)
            observed += 2
            assert entries(family, "second") and not entries(family, "first") and not entries(family)

            RULE_ORDER = ("first", "second", "test")
            CONFIG["first:src_iface"] = "wan1"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            nft("flush", "set", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_second")
            for source_port in (port, port + 3):
                send_packet(source_port)
            observed += 2
            assert entries(family, "second") and not entries(family, "first") and not entries(family)

            CONFIG["first:src_iface"] = "audit-lan"
            CONFIG["first:sticky"] = "0"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            nft("flush", "set", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_second")
            send_packet(port + 4)
            observed += 1
            assert all(not entries(family, rule) for rule in sticky_rules)
            CONFIG["first:sticky"] = "1"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            for source_port in (port + 4, port + 5):
                send_packet(source_port)
            observed += 2
            assert entries(family, "first") and not entries(family, "second") and not entries(family)
        state = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
        counter = next(item["rule"] for item in state["nftables"] if item.get("rule", {}).get("comment") == "audit_rule_order")
        assert next(expr["counter"]["packets"] for expr in counter["expr"] if "counter" in expr) == observed, (family, case)
    print(f"PASS {family} overlapping first-match rules, full predicates, reorder/source-device edits and sticky toggles preserve skb/conntrack identity.")

for ingress in ("LAN", "WAN"):
    config()
    RULE_ORDER = ("test",)
    CONFIG["test:family"] = "any"
    CONFIG["test:proto"] = "all"
    CONFIG["wan2:family"] = "ipv6"
    setup()
    if ingress == "WAN":
        shell("multiwan_nft_create_iface_nft wan1 audit-lan && multiwan_nft_create_iface_nft wan2 audit-lan || exit 1")
    nft("add", "table", "inet", "special_probe")
    nft("add", "chain", "inet", "special_probe", "before", "{ type filter hook prerouting priority -151; }")
    nft("add", "chain", "inet", "special_probe", "after", "{ type filter hook prerouting priority -149; }")
    nft("add", "rule", "inet", "special_probe", "before", "meta mark set 0x80000000")
    cases = [("ipv4", destination, None, bypass) for destination, bypass in (
        ("224.0.0.1", True), ("239.255.255.250", True), ("240.0.0.1", True),
        ("255.255.255.254", True), ("255.255.255.255", True), ("223.255.255.254", False))]
    cases += [("ipv6", "ff02::1", None, True), ("ipv6", "2001:db8:9::9", None, False)]
    cases += [("ipv6", "2001:db8:1::1", kind, True) for kind in range(133, 138)]
    for index, (family, destination, kind, bypass) in enumerate(cases):
        source = "192.0.2.2" if family == "ipv4" else "fe80::2" if kind is not None else "2001:db8:1::2"
        match = f'{"ip" if family == "ipv4" else "ip6"} saddr {source} {"ip" if family == "ipv4" else "ip6"} daddr {destination}'
        if kind is not None:
            match += f" icmpv6 type {kind}"
        nft("add", "rule", "inet", "special_probe", "after", f'{match} counter comment "special_seen_{index}"')
        condition = "== 0" if bypass else "!= 0"
        nft("add", "rule", "inet", "special_probe", "after",
            f'{match} meta mark & {MASK} {condition} meta mark & 0x80000000 != 0 counter comment "special_correct_{index}"')
        if family == "ipv4":
            send(46000 + index, source, destination, receive=False)
        else:
            send6(46000 + index, source, destination, receive=False, icmp_type=kind)
        for attempt in range(20):
            state = json.loads(nft("-j", "list", "chain", "inet", "special_probe", "after"))
            packets = {item["rule"]["comment"]: next(expr["counter"]["packets"] for expr in item["rule"]["expr"] if "counter" in expr)
                       for item in state["nftables"] if "rule" in item}
            if packets[f"special_seen_{index}"]:
                break
            time.sleep(0.01)
        assert packets[f"special_seen_{index}"] == 1, (ingress, destination, kind, packets)
        assert packets[f"special_correct_{index}"] == 1, (ingress, destination, kind, bypass, packets)
    print(f"PASS {ingress} IPv4 multicast/reserved/limited-broadcast and IPv6 multicast/ND/redirect bypass, ordinary boundary policy and unrelated skb mark.")

# Local addresses can be absent from the main table on point-to-point or no-prefix-route links.
run(["ip", "addr", "del", "192.0.2.1/32", "dev", "audit-lan"])
run(["ip", "addr", "add", "192.0.2.1", "peer", "192.0.2.254/32", "dev", "audit-lan"])
run(["ip", "route", "replace", "default", "via", "192.0.2.254", "dev", "audit-lan"])
run(["ip", "-6", "addr", "del", "2001:db8:1::1/128", "dev", "audit-lan"])
run(["ip", "-6", "addr", "add", "2001:db8:1::1/128", "dev", "audit-lan", "nodad", "noprefixroute"])
config(sticky=0, metrics=(1, 2, 3))
RULE_ORDER = ("test",)
CONFIG["test:family"] = "any"
CONFIG["wan2:family"] = "ipv6"
setup()
shell("multiwan_nft_set_connected_ipv4 && multiwan_nft_set_connected_ipv6 || exit 1")
for family, destination in (("ipv4", "192.0.2.1"), ("ipv6", "2001:db8:1::1")):
    nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
        f'meta nfproto {family} {"ip" if family == "ipv4" else "ip6"} daddr {destination} meta mark & {MASK} == {MASK} ct mark & {MASK} == {MASK} counter comment "own_default_{family}"')
send(48000, destination_address="192.0.2.1")
send6(48000, destination_address="2001:db8:1::1")
state = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
local_counts = {item["rule"]["comment"]: next(expr["counter"]["packets"] for expr in item["rule"]["expr"] if "counter" in expr)
                for item in state["nftables"] if item.get("rule", {}).get("comment", "").startswith("own_default_")}
assert local_counts == {"own_default_ipv4": 1, "own_default_ipv6": 1}, local_counts
for family, flag, source, destination, send_packet in (
    ("ipv4", "-4", "192.0.2.2", "198.18.10.1", send),
    ("ipv6", "-6", "2001:db8:1::2", "2001:db8:10::1", send6),
):
    address = destination + ("/32" if family == "ipv4" else "/128")
    arguments = ["nodad", "noprefixroute"] if family == "ipv6" else []
    run(["ip", flag, "addr", "add", address, "dev", "lo", *arguments])
    nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
        f'meta nfproto {family} {"ip" if family == "ipv4" else "ip6"} daddr {destination} meta mark & {MASK} == {MASK} ct mark & {MASK} == {MASK} counter comment "new_local_{family}"')
    send_packet(48001, source, destination, receive=False)
    run(["ip", flag, "addr", "del", address, "dev", "lo"])
    mark = 0x10000 if family == "ipv4" else 0x20000
    nft("add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
        f'meta nfproto {family} {"ip" if family == "ipv4" else "ip6"} daddr {destination} meta mark & {MASK} == {mark} ct mark & {MASK} == {mark} counter comment "retired_local_{family}"')
    send_packet(48002, source, destination, receive=False)
state = json.loads(nft("-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"))
local_changes = {item["rule"]["comment"]: next(expr["counter"]["packets"] for expr in item["rule"]["expr"] if "counter" in expr)
                 for item in state["nftables"] if item.get("rule", {}).get("comment", "").startswith(("new_local_", "retired_local_"))}
assert local_changes == {"new_local_ipv4": 1, "retired_local_ipv4": 1, "new_local_ipv6": 1, "retired_local_ipv6": 1}, local_changes
print("PASS both-family router-local FIB bypass, peer/no-prefix-route addresses, live local addition/removal and incoming WAN identity preserved.")

def probe_packet(label, match, mark, connection_mark, send_packet, fresh=False):
    if fresh:
        nft("add", "rule", "inet", "audit_probe", "before", f'{match} ct mark & {MASK} == 0 counter comment "fresh_{label}"')
    nft("add", "rule", "inet", "audit_probe", "after", f'{match} counter comment "seen_{label}"')
    nft("add", "rule", "inet", "audit_probe", "after",
        f'{match} meta mark == {0x8000002E | mark} ct mark == {0x4000002E | connection_mark} counter comment "correct_{label}"')
    send_packet()
    for _ in range(20):
        state = json.loads(nft("-j", "list", "chain", "inet", "audit_probe", "after"))
        counters = {item["rule"]["comment"]: next(expr["counter"]["packets"] for expr in item["rule"]["expr"] if "counter" in expr)
                    for item in state["nftables"] if "rule" in item}
        if counters[f"seen_{label}"]:
            break
        time.sleep(0.01)
    assert counters[f"seen_{label}"] == counters[f"correct_{label}"] == 1, (label, counters)
    if fresh:
        state = json.loads(nft("-j", "list", "chain", "inet", "audit_probe", "before"))
        rule = next(item["rule"] for item in state["nftables"] if item.get("rule", {}).get("comment") == "fresh_" + label)
        assert next(expr["counter"]["packets"] for expr in rule["expr"] if "counter" in expr) == 1, label


def setup_probe():
    nft("add", "table", "inet", "audit_probe")
    nft("add", "chain", "inet", "audit_probe", "before", "{ type filter hook prerouting priority -151; }")
    nft("add", "chain", "inet", "audit_probe", "after", "{ type filter hook prerouting priority -149; }")
    nft("add", "rule", "inet", "audit_probe", "before", 'iifname "audit-lan" meta mark set 0x8000002e ct mark set ct mark or 0x4000002e')


def dynamic_bypass():
    global RULE_ORDER
    config(sticky=0, metrics=(1, 2, 3))
    RULE_ORDER = ("test",)
    CONFIG.update({"test:family": "any", "wan2:family": "ipv6"})
    setup()
    setup_probe()
    for family, suffix, source, target, prefix, local, remote, mark, send_packet in (
        ("ipv4", "v4", "192.0.2.2", "198.51.100.200", "198.51.100.0/24", "192.0.2.1", "203.0.113.77", 0x10000, send),
        ("ipv6", "v6", "2001:db8:1::2", "2001:db8:99::200", "2001:db8:99::/64", "2001:db8:1::1", "2001:db8:2::77", 0x20000, send6),
    ):
        setname = "multiwan_nft_dynamic_" + suffix
        address = "ip" if family == "ipv4" else "ip6"
        serial = 0

        def packet(case, port, expected, saved, sender=source, destination=target):
            nonlocal serial
            label = f"dynamic_{suffix}_{serial}"
            serial += 1
            match = f'{address} saddr {sender} {address} daddr {destination} udp sport {port} udp dport 4444'
            probe_packet(label, match, expected, saved, lambda: send_packet(port, sender, destination))
            print("DYNAMIC_BYPASS " + json.dumps({"family": family, "case": case, "skb_mark": expected,
                  "ct_mark": saved, "packets": 1, "qos_preserved": True}), flush=True)

        packet("absent", 59000, mark, mark)
        nft("add", "element", "inet", "multiwan_nft", setname, "{ " + prefix + " }")
        packet("established_add", 59000, MASK, mark)
        packet("fresh_add", 59001, MASK, MASK)
        before = nft("-s", "list", "set", "inet", "multiwan_nft", setname)
        shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_user_rules_nft || exit 1")
        assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == before
        packet("rule_refresh", 59002, MASK, MASK)
        shell("""
multiwan_nft_load_base_ruleset || exit 1
for iface in wan1 wan2 wan3; do multiwan_nft_create_iface_nft "$iface" "$iface" || exit 1; done
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
""")
        assert nft("-s", "list", "set", "inet", "multiwan_nft", setname) == before
        packet("base_reload", 59003, MASK, MASK)
        nft("delete", "element", "inet", "multiwan_nft", setname, "{ " + prefix + " }")
        packet("established_remove", 59000, mark, mark)
        packet("existing_main_retained", 59001, MASK, MASK)
        packet("fresh_remove", 59004, mark, mark)
        interface = "wan1" if family == "ipv4" else "wan2"
        shell(f"multiwan_nft_create_iface_nft {interface} audit-lan || exit 1")
        nft("add", "element", "inet", "multiwan_nft", setname, "{ " + remote + " }")
        packet("wan_source_add", 59005, MASK, MASK, remote, local)
        nft("delete", "element", "inet", "multiwan_nft", setname, "{ " + remote + " }")
        packet("wan_source_remove", 59006, mark, mark, remote, local)
        shell(f"multiwan_nft_create_iface_nft {interface} {interface} || exit 1")
        nft("add", "element", "inet", "multiwan_nft", setname, "{ " + prefix + " }")
    shell("multiwan_nft_unload_ruleset || exit 1")
    assert subprocess.run(["nft", "list", "table", "inet", "multiwan_nft"], capture_output=True).returncode != 0
    shell("""
multiwan_nft_load_base_ruleset || exit 1
for iface in wan1 wan2 wan3; do multiwan_nft_create_iface_nft "$iface" "$iface" || exit 1; done
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
""")
    for suffix in ("v4", "v6"):
        state = json.loads(nft("-j", "list", "set", "inet", "multiwan_nft", "multiwan_nft_dynamic_" + suffix))
        assert all(not item["set"].get("elem") for item in state["nftables"] if "set" in item)
    for family, suffix, source, target, prefix, mark, send_packet in (
        ("ipv4", "v4", "192.0.2.2", "198.51.100.200", "198.51.100.0/24", 0x10000, send),
        ("ipv6", "v6", "2001:db8:1::2", "2001:db8:99::200", "2001:db8:99::/64", 0x20000, send6),
    ):
        for populated in (False, True):
            if populated:
                nft("add", "element", "inet", "multiwan_nft", "multiwan_nft_dynamic_" + suffix, "{ " + prefix + " }")
            port = 59101 if populated else 59100
            expected = MASK if populated else mark
            address = "ip" if family == "ipv4" else "ip6"
            match = f'{address} saddr {source} {address} daddr {target} udp sport {port} udp dport 4444'
            probe_packet(f"restart_{suffix}_{populated}", match, expected, expected, lambda: send_packet(port, source, target))
            print("DYNAMIC_BYPASS " + json.dumps({"family": family, "case": "restart_repopulated" if populated else "restart_empty",
                  "skb_mark": expected, "ct_mark": expected, "packets": 1, "qos_preserved": True}), flush=True)
    print("DYNAMIC_LIFECYCLE " + json.dumps({"rule_refresh_retained": True, "base_reload_retained": True,
          "stop_removed": True, "start_empty": True, "producer_repopulation_required": True}), flush=True)


def send_protocol(family, protocol, hop_options=False):
    def ipv4_packet(source, destination, number, payload):
        header = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), 1, 0, 64, number, 0,
                             socket.inet_aton(source), socket.inet_aton(destination))
        total = sum(struct.unpack("!10H", header))
        while total >> 16:
            total = (total & 65535) + (total >> 16)
        return header[:10] + struct.pack("!H", (~total) & 65535) + header[12:] + payload

    if protocol == 47:
        payload = struct.pack("!HH", 0, 0x0800) + ipv4_packet("198.18.1.1", "198.18.1.2", 253, b"gre-test")
    elif protocol == 50:
        payload = struct.pack("!II", 0x12345678, 1) + b"synthetic-esp-payload"
    else:
        payload = b"experimental-protocol-test"
    if family == "ipv4":
        frame = b"\x08\x00" + ipv4_packet("192.0.2.2", "198.51.100.200", protocol, payload)
    else:
        if hop_options:
            payload = struct.pack("!BB6s", protocol, 0, b"\0" * 6) + payload
        frame = b"\x86\xdd" + struct.pack("!IHBB16s16s", 6 << 28, len(payload), 0 if hop_options else protocol, 64,
                    socket.inet_pton(socket.AF_INET6, "2001:db8:1::2"), socket.inet_pton(socket.AF_INET6, "2001:db8:99::200")) + payload
    packet_socket.send(destination_mac + source_mac + frame)


def protocol_selectors():
    global RULE_ORDER
    config(sticky=0, metrics=(1, 2, 3))
    RULE_ORDER = ("test",)
    CONFIG.update({"test:family": "any", "wan2:family": "ipv6", "test:src_port": "7", "test:dest_port": "9"})
    setup()
    setup_probe()
    for selector, protocol, other in (("gre", 47, 50), ("47", 47, 50), ("esp", 50, 47), ("50", 50, 47), ("253", 253, 47)):
        CONFIG["test:proto"] = selector
        shell("multiwan_nft_set_user_rules_nft || exit 1")
        for family, mark in (("ipv4", 0x10000), ("ipv6", 0x20000)):
            cases = [("match", protocol, mark, False), ("mismatch", other, 0, False)]
            if family == "ipv6":
                cases.append(("hop_options", protocol, mark, True))
            for case, actual, selected, hop_options in cases:
                run(["conntrack", "-F"])
                label = f"protocol_{family}_{selector}_{case}"
                address, source, target = ("ip", "192.0.2.2", "198.51.100.200") if family == "ipv4" else ("ip6", "2001:db8:1::2", "2001:db8:99::200")
                match = f'{address} saddr {source} {address} daddr {target} meta l4proto {actual}'
                probe_packet(label, match, selected, selected, lambda: send_protocol(family, actual, hop_options), fresh=True)
                print("PROTOCOL_SELECTOR " + json.dumps({"family": family, "selector": selector, "protocol": actual,
                      "case": case, "skb_mark": selected, "ct_mark": selected, "ports_ignored": True,
                      "packets": 1, "qos_preserved": True, "no_restored_wan_mark": True}), flush=True)
    previous = nft("-s", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules")
    CONFIG["test:proto"] = "invalid_protocol_name"
    shell("if multiwan_nft_set_user_rules_nft; then exit 1; fi")
    assert nft("-s", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_rules") == previous
    print("PROTOCOL_REJECT " + json.dumps({"invalid_name_rejected": True, "previous_rules_retained": True}), flush=True)


dynamic_bypass()
protocol_selectors()
print("NFT packet regressions passed inside disposable user/network namespace.")
