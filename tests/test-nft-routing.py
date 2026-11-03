#!/usr/bin/env python3
"""Real routing/NAT regressions; every network object lives in new namespaces."""
import collections
import errno
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time


def echo_server(label, host, port, ready):
    def echo_tcp(connection, peer):
        try:
            with connection, connection.makefile("rb") as stream:
                for _ in stream:
                    connection.sendall((json.dumps({"wan": label, "source": peer[0]}) + "\n").encode())
        except OSError:
            pass

    family = socket.AF_INET6 if ":" in host else socket.AF_INET
    udp = socket.socket(family, socket.SOCK_DGRAM)
    tcp = socket.socket(family, socket.SOCK_STREAM)
    udp.bind((host, int(port)))
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind((host, int(port)))
    tcp.listen(8)
    Path(ready).touch()
    while True:
        for incoming in select.select([udp, tcp], [], [])[0]:
            if incoming is udp:
                _, peer = udp.recvfrom(4096)
                udp.sendto(json.dumps({"wan": label, "source": peer[0]}).encode(), peer)
            else:
                connection, peer = tcp.accept()
                threading.Thread(target=echo_tcp, args=(connection, peer), daemon=True).start()


def exchange(connection, address=None):
    try:
        if address:
            connection.sendto(b"echo", address)
        elif connection.type == socket.SOCK_STREAM:
            connection.sendall(b"echo\n")
            with connection.makefile("rb") as stream:
                return {"ok": True, **json.loads(stream.readline())}
        else:
            connection.sendall(b"echo")
        reply = json.loads(connection.recv(4096))
        return {"ok": True, **reply}
    except (OSError, ValueError) as error:
        return {"ok": False, "errno": getattr(error, "errno", None)}


if len(sys.argv) > 1 and sys.argv[1] == "--echo":
    echo_server(*sys.argv[2:])
    raise SystemExit
if len(sys.argv) > 1 and sys.argv[1] == "--request":
    protocol, target, port, count, source, start_port = sys.argv[2:]
    results = []
    for offset in range(int(count)):
        with socket.socket(socket.AF_INET6 if ":" in target else socket.AF_INET, socket.SOCK_DGRAM if protocol == "udp" else socket.SOCK_STREAM) as connection:
            # Initial IPv6 neighbor discovery can exceed one second on loaded CI.
            connection.settimeout(3)
            if protocol == "udp":
                # Linux IP_RECVERR / IPV6_RECVERR exposes soft ICMP route errors.
                connection.setsockopt(socket.IPPROTO_IPV6 if ":" in target else socket.IPPROTO_IP,
                                      25 if ":" in target else 11, 1)
            connection.bind((source, int(start_port) + offset))
            connection.connect((target, int(port)))
            results.append(exchange(connection))
    print(json.dumps(results), flush=True)
    raise SystemExit
if len(sys.argv) > 1 and sys.argv[1] == "--session":
    target, source, *options = sys.argv[2:]
    protocol = options[0] if options else "udp"
    port = int(options[1]) if len(options) > 1 else 45000
    assert len(options) <= 2 and protocol in ("tcp", "udp")
    with socket.socket(socket.AF_INET6 if ":" in target else socket.AF_INET, socket.SOCK_STREAM if protocol == "tcp" else socket.SOCK_DGRAM) as connection:
        connection.settimeout(3)
        connection.bind((source, 0))
        connection.connect((target, port))
        print(json.dumps({"port": connection.getsockname()[1], **exchange(connection)}), flush=True)
        for command in sys.stdin:
            if command.strip() == "exchange":
                print(json.dumps(exchange(connection)), flush=True)
    raise SystemExit
if "--isolated" not in sys.argv:
    environment = {**os.environ, "NFT_ROUTING_PARENT_NETNS": os.readlink("/proc/self/ns/net")}
    raise SystemExit(subprocess.call(["unshare", "-Urn", sys.executable, __file__, "--isolated", *sys.argv[1:]], env=environment))
parent_namespace = os.environ.get("NFT_ROUTING_PARENT_NETNS")
assert parent_namespace and parent_namespace != os.readlink("/proc/self/ns/net"), "Refusing network mutation without a fresh namespace"

REPO = Path(sys.argv[-1]).resolve()
CORE = REPO / "multiwan-nft/files/lib/multiwan-nft/multiwan_nft.sh"
COMMON = CORE.with_name("common.sh")
BODY = "\n".join(CORE.read_text().splitlines()[5:])
SCRIPT = str(Path(__file__).resolve())
required = ("ip", "nft", "unshare", "nsenter", "busybox", "conntrack", "ping")
assert all(shutil.which(tool) for tool in required), "Required runtimes: " + ", ".join(required)
temporary = tempfile.TemporaryDirectory(prefix="multiwan-nft-routing-")
STATE = Path(temporary.name)
children = []
namespaces = {}
CONFIG = {
    "wan1:family": "ipv4", "wan2:family": "ipv4", "wan1:enabled": "1", "wan2:enabled": "1",
    "m1:interface": "wan1", "m2:interface": "wan2", "m1:metric": "1", "m2:metric": "1",
    "m1:weight": "1", "m2:weight": "3", "forward:family": "ipv4", "forward:proto": "all",
    "forward:src_ip": "10.10.0.0/24", "forward:sticky": "0", "forward:use_policy": "balanced",
    "wan1v6:family": "ipv6", "wan2v6:family": "ipv6", "wan1v6:enabled": "1", "wan2v6:enabled": "1",
    "m1v6:interface": "wan1v6", "m2v6:interface": "wan2v6", "m1v6:metric": "1", "m2v6:metric": "1",
    "m1v6:weight": "1", "m2v6:weight": "3", "forward6:family": "ipv6", "forward6:proto": "all",
    "forward6:src_ip": "2001:db8:10::/64", "forward6:sticky": "0", "forward6:use_policy": "balanced",
}
next_port = 10000
INTERFACES = ["wan1", "wan2", "wan1v6", "wan2v6"]


def run(arguments, **kwargs):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=20, **kwargs)
    if result.returncode:
        raise AssertionError(f"{arguments}: {result.stderr}{result.stdout}")
    return result.stdout


def peer_command(name, *command):
    return ["nsenter", "-t", str(namespaces[name].pid), "-n", "--", *command]


def child(arguments, **kwargs):
    process = subprocess.Popen(arguments, text=True, **kwargs)
    children.append(process)
    return process


def receive(process):
    assert select.select([process.stdout], [], [], 4)[0], "Client did not produce its bounded response"
    line = process.stdout.readline()
    assert line, "Client exited before responding"
    return json.loads(line)


def shell(body):
    cases = "\n".join(f"{shlex.quote(key)}) export \"$1={value}\" ;;" for key, value in CONFIG.items())
    text = f"""
. {shlex.quote(str(COMMON))}
{BODY}
MULTIWAN_NFT_STATUS_DIR={shlex.quote(str(STATE))}
MULTIWAN_NFT_STATUS_NFT_LOG_DIR="$MULTIWAN_NFT_STATUS_DIR/nft_log"
MULTIWAN_NFT_CONNTRACK_MAP="$MULTIWAN_NFT_STATUS_DIR/saved_conntrack_map"
NO_IPV6=0
IP4='{shutil.which("ip")} -4'
IP6='{shutil.which("ip")} -6'
config_load() {{ :; }}
config_get() {{ case "$2:$3" in {cases}
    *) export "$1=${{4:-}}" ;; esac; }}
config_get_bool() {{ config_get "$@"; }}
config_foreach() {{
    local callback="$1" type="$2" name
    shift 2
    case "$type" in
        interface) for name in {' '.join(INTERFACES)}; do "$callback" "$name" "$@"; done ;;
        policy) "$callback" balanced "$@" ;;
        rule) "$callback" forward "$@"; "$callback" forward6 "$@" ;;
    esac
}}
config_list_foreach() {{
    local section="$1" option="$2" callback="$3"
    shift 3
    case "$section:$option" in
        balanced:use_member) for name in m1 m2 m1v6 m2v6; do "$callback" "$name" "$@"; done ;;
        wan1:track_ip) "$callback" 192.0.2.2 "$@" ;;
        wan2:track_ip) "$callback" 198.51.100.2 "$@" ;;
        wan1v6:track_ip) "$callback" 2001:db8:1::2 "$@" ;;
        wan2v6:track_ip) "$callback" 2001:db8:2::2 "$@" ;;
    esac
}}
network_get_device() {{ export "$1=${{2%v6}}"; }}
network_get_ipaddr() {{ case "$2" in wan1) export "$1=192.0.2.1" ;; wan2) export "$1=198.51.100.1" ;; esac; }}
network_get_ipaddr6() {{ case "$2" in wan1v6) export "$1=2001:db8:1::1" ;; wan2v6) export "$1=2001:db8:2::1" ;; esac; }}
network_flush_cache() {{ :; }}
# These routes are installed directly, with no netifd-owned recovery defaults.
ubus() {{
    case "$*" in
        '-S call network.interface.wan1 status'|'-S call network.interface.wan2 status'|'-S call network.interface.wan1v6 status'|'-S call network.interface.wan2v6 status')
            printf '%s\\n' '{{"route":[]}}' ;;
        *) return 1 ;;
    esac
}}
json_load() {{ [ "$1" = '{{"route":[]}}' ]; }}
json_get_type() {{ [ "$2" = route ] && export "$1=array"; }}
json_select() {{ [ "$1" = route ] || [ "$1" = .. ]; }}
json_get_var() {{ export "$1="; }}
json_get_keys() {{ export "$1="; }}
LOG() {{ printf '%s\\n' "$*" >&2; }}
multiwan_nft_init || exit 1
multiwan_nft_update_iface_to_table
{body}
"""
    return run(["busybox", "ash"], input=text)


def online(*names):
    (STATE / "iface_state").mkdir(exist_ok=True)
    for name in ("wan1", "wan2", "wan1v6", "wan2v6"):
        (STATE / "iface_state" / name).write_text("online" if name in names else "offline")


def choose(wan):
    CONFIG["m1:metric"], CONFIG["m2:metric"] = ("1", "2") if wan == "wan1" else ("2", "1")
    CONFIG["m1v6:metric"], CONFIG["m2v6:metric"] = CONFIG["m1:metric"], CONFIG["m2:metric"]
    shell("multiwan_nft_set_policies_nft || exit 1")


def requests(name, protocol, target, port, count=1, source="10.10.0.2"):
    global next_port
    start_port = next_port
    next_port += count
    # A reused UDP port would still identify an old conntrack, not a new flow.
    command = [sys.executable, SCRIPT, "--request", protocol, target, str(port), str(count), source, str(start_port)]
    return json.loads(run(peer_command(name, *command) if name else command))


def server(name, label, host, port):
    ready = STATE / (label + "-ready")
    command = [sys.executable, SCRIPT, "--echo", label, host, str(port), str(ready)]
    process = child(peer_command(name, *command) if name else command)
    deadline = time.monotonic() + 3
    while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.01)
    assert ready.exists(), "Echo server failed to bind: " + label
    return process


def session(expected, target="203.0.113.9", source="10.10.0.2", protocol="udp", port=45000):
    process = child(peer_command("lan", sys.executable, SCRIPT, "--session", target, source, protocol, str(port)), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    initial = receive(process)
    assert initial["ok"] and initial["wan"] == expected, initial
    return process, initial["port"]


def repeat(process):
    process.stdin.write("exchange\n")
    process.stdin.flush()
    return receive(process)


def conntracks(mark, family="ipv4", protocol="udp"):
    return run(["conntrack", "-L", "-f", family, "-p", protocol, "-m", f"{mark}/0x3f0000"])


def has_port(document, port):
    return f"src=10.10.0.2 dst=203.0.113.9 sport={port} dport=45000 " in document


def tcp_rules():
    saved = CONFIG.copy()
    streams = []
    servers = []
    aliases = []

    def cache(family, rule):
        state = json.loads(run(["nft", "-j", "list", "set", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_{rule}"]))
        return next(item["set"].get("elem", []) for item in state["nftables"] if "set" in item)

    try:
        choose("wan2")
        for family, rule, target, source, prefix in (
            ("ipv4", "forward", "203.0.113.9", "10.10.0.2", "203.0.113.0/24"),
            ("ipv6", "forward6", "2001:db8:ffff::9", "2001:db8:10::2", "2001:db8:ffff::/64"),
        ):
            CONFIG.update({rule + ":proto": "tcp", rule + ":src_iface": "lan", rule + ":dest_ip": prefix,
                           rule + ":src_port": f"9,{next_port}:{next_port + 1}", rule + ":dest_port": "443,45000:45001"})
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            replies = requests("lan", "tcp", target, 45000, 3, source)
            expected = ["wan2", "wan2", "wan1"] if family == "ipv4" else ["wan2v6", "wan2v6", "wan1v6"]
            assert all(reply["ok"] for reply in replies) and [reply["wan"] for reply in replies] == expected, replies
            CONFIG[rule + ":src_port"] = ""
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            udp = requests("lan", "udp", target, 45000, source=source)[0]
            assert udp["ok"] and udp["wan"] == expected[-1], udp
            CONFIG[rule + ":src_iface"] = "wan1"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            wrong_device = requests("lan", "tcp", target, 45000, source=source)[0]
            assert wrong_device["ok"] and wrong_device["wan"] == expected[-1], wrong_device
            CONFIG[rule + ":src_iface"] = "lan"
            CONFIG[rule + ":dest_port"] = "443"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            wrong_port = requests("lan", "tcp", target, 45000, source=source)[0]
            assert wrong_port["ok"] and wrong_port["wan"] == expected[-1], wrong_port
            CONFIG[rule + ":dest_port"] = "443,45000:45001"
            CONFIG[rule + ":dest_ip"] = "198.18.0.0/24" if family == "ipv4" else "2001:db8:eeee::/64"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            wrong_prefix = requests("lan", "tcp", target, 45000, source=source)[0]
            assert wrong_prefix["ok"] and wrong_prefix["wan"] == expected[-1], wrong_prefix
            CONFIG[rule + ":dest_ip"] = prefix
            CONFIG[rule + ":src_ip"] = "198.18.0.0/24" if family == "ipv4" else "2001:db8:eeee::/64"
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            wrong_source = requests("lan", "tcp", target, 45000, source=source)[0]
            assert wrong_source["ok"] and wrong_source["wan"] == expected[-1], wrong_source
            CONFIG.update({rule + ":src_ip": saved[rule + ":src_ip"], rule + ":dest_port": "443", rule + ":sticky": "1", rule + ":timeout": "3"})
            print("TCP_PREDICATE " + json.dumps({"family": family, "ports": [reply["wan"] for reply in replies],
                  "udp": udp, "wrong_device": wrong_device, "wrong_port": wrong_port, "wrong_prefix": wrong_prefix,
                  "wrong_source": wrong_source}), flush=True)
        for wan in ("wan1", "wan2"):
            servers.append(server(wan, wan + "_443", "203.0.113.9", 443))
            servers.append(server(wan, wan + "v6_443", "2001:db8:ffff::9", 443))
        shell("multiwan_nft_set_user_rules_nft || exit 1")
        for family, rule, target, source, wan, mark in (
            ("ipv4", "forward", "203.0.113.9", "10.10.0.2", "wan2_443", "0x20000"),
            ("ipv6", "forward6", "2001:db8:ffff::9", "2001:db8:10::2", "wan2v6_443", "0x40000"),
        ):
            process, port = session(wan, target, source, "tcp", 443)
            streams.append((process, port, family, rule, wan, mark))
            assert cache(family, rule)
        for _ in range(6):
            time.sleep(0.7)
            for process, port, family, rule, wan, mark in streams:
                assert repeat(process)["wan"] == wan and cache(family, rule)
                assert f"sport={port} dport=443 " in conntracks(mark, family, "tcp")
        for _ in range(4):
            time.sleep(1)
            for family, target, source, expected in (("ipv4", "203.0.113.9", "10.10.0.2", "wan1_443"),
                                                      ("ipv6", "2001:db8:ffff::9", "2001:db8:10::2", "wan1v6_443")):
                reply = requests("lan", "udp", target, 443, source=source)[0]
                assert reply["ok"] and reply["wan"] == expected, reply
        for process, port, family, rule, wan, mark in streams:
            assert not cache(family, rule), "Idle TCP affinity did not expire"
            assert repeat(process)["wan"] == wan and cache(family, rule), "Established TCP did not recreate expired affinity"
        choose("wan1")
        for process, port, family, rule, wan, mark in streams:
            target, source = ("203.0.113.9", "10.10.0.2") if family == "ipv4" else ("2001:db8:ffff::9", "2001:db8:10::2")
            fresh = requests("lan", "tcp", target, 443, source=source)[0]
            assert fresh["ok"] and fresh["wan"] == ("wan1_443" if family == "ipv4" else "wan1v6_443"), fresh
            assert repeat(process)["wan"] == wan and f"sport={port} dport=443 " in conntracks(mark, family, "tcp")
            print("TCP_STICKY " + json.dumps({"family": family, "port": 443, "udp443_excluded": True, "active_refresh": True, "idle_expiry": True,
                  "established_recreation": True, "new_tier": fresh, "established_wan": wan}), flush=True)
        for member in ("m1", "m2", "m1v6", "m2v6"):
            CONFIG.update({member + ":metric": "1", member + ":weight": "1"})
        for rule in ("forward", "forward6"):
            CONFIG[rule + ":timeout"] = "60"
        shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_user_rules_nft || exit 1")
        for family, flag, rule, target, address, source, labels, marks, members in (
            ("ipv4", "-4", "forward", "203.0.113.9", "10.10.0.3/32", "10.10.0.3", ("wan1_443", "wan2_443"), (65536, 131072), ("m1", "m2")),
            ("ipv6", "-6", "forward6", "2001:db8:ffff::9", "2001:db8:10::3/128", "2001:db8:10::3", ("wan1v6_443", "wan2v6_443"), (196608, 262144), ("m1v6", "m2v6")),
        ):
            command = ["ip", flag, "addr", "add", address, "dev", "peer-lan"] + (["nodad"] if flag == "-6" else [])
            run(peer_command("lan", *command))
            aliases.append((flag, address))
            state = json.loads(run(["nft", "-j", "list", "set", "inet", "multiwan_nft", f"multiwan_nft_policy_balanced_members_{family}"]))
            eligible = next(item["set"]["elem"] for item in state["nftables"] if "set" in item)
            assert set(eligible) == set(marks), eligible
            initial = requests("lan", "tcp", target, 443, source=source)[0]
            assert initial["ok"] and initial["wan"] in labels, initial
            selected = labels.index(initial["wan"])
            mark = marks[selected]
            # Make a new random choice strongly favor the other still-eligible WAN.
            weights = [1000, 1000]
            weights[selected] = 1
            CONFIG.update({members[index] + ":weight": str(weight) for index, weight in enumerate(weights)})
            shell("multiwan_nft_set_policies_nft || exit 1")
            state = json.loads(run(["nft", "-j", "list", "table", "inet", "multiwan_nft"]))["nftables"]
            eligible = next(item["set"]["elem"] for item in state if item.get("set", {}).get("name") == f"multiwan_nft_policy_balanced_members_{family}")
            assert set(eligible) == set(marks), eligible
            rules = [item["rule"] for item in state if item.get("rule", {}).get("chain") == "multiwan_nft_policy_balanced"]
            for index, label in enumerate(labels):
                assert any(rule.get("comment") == f"{label.removesuffix('_443')} {weights[index]} 1001" for rule in rules)
            run(["nft", "get", "element", "inet", "multiwan_nft", f"multiwan_nft_sticky_{family}_{rule}", f"{{ {source} . {mark} }}"])
            start_port = next_port
            replies = requests("lan", "tcp", target, 443, 12, source)
            assert all(reply["ok"] and reply["wan"] == initial["wan"] for reply in replies), replies
            document = conntracks(hex(mark), family, "tcp")
            for port in range(start_port, start_port + len(replies)):
                assert f"src={source} dst={target} sport={port} dport=443 " in document, document
            print("TCP_BALANCED " + json.dumps({"family": family, "source": source, "initial_wan": initial["wan"],
                  "eligible_marks": eligible, "weights": weights, "mark": mark, "fresh_wans": [reply["wan"] for reply in replies],
                  "distinct_source_ports": len(replies), "cached_before_new_flows": True}), flush=True)
        for flag, address in aliases:
            run(peer_command("lan", "ip", flag, "addr", "del", address, "dev", "peer-lan"))
        aliases.clear()
        choose("wan2")
        for family, rule, protocol, flag, target, source, mark in (
            ("ipv4", "forward", "icmp", "-4", "203.0.113.9", "10.10.0.2", "0x20000"),
            ("ipv6", "forward6", "ipv6-icmp", "-6", "2001:db8:ffff::9", "2001:db8:10::2", "0x40000"),
        ):
            CONFIG.update({rule + ":proto": protocol, rule + ":sticky": "0", rule + ":src_port": "7", rule + ":dest_port": "9"})
            shell("multiwan_nft_set_user_rules_nft || exit 1")
            run(peer_command("lan", "ping", flag, "-n", "-c", "1", "-W", "2", target))
            document = conntracks(mark, family, "icmp" if family == "ipv4" else "icmpv6")
            assert f"src={source} dst={target} " in document, document
            print("RULE_ICMP " + json.dumps({"family": family, "protocol": protocol, "mark": mark, "ports_ignored": True}), flush=True)
        print("PASS TCP predicates, UDP exclusion, active/idle sticky lifecycle and metric changes preserve established IPv4/IPv6 TCP/NAT sessions.", flush=True)
    finally:
        for flag, address in aliases:
            run(peer_command("lan", "ip", flag, "addr", "del", address, "dev", "peer-lan"))
        for process, *_ in streams:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=2)
        for process in servers:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=2)
        run(["conntrack", "-F"])
        CONFIG.clear()
        CONFIG.update(saved)
        online(*INTERFACES)
        shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_user_rules_nft || exit 1")


def dynamic_routing():
    saved = CONFIG.copy()
    # One endpoint behind both providers keeps TCP state when only egress changes.
    holder = child(["unshare", "-n", "cat"], stdin=subprocess.PIPE)
    namespaces["world"] = holder
    deadline = time.monotonic() + 3
    while os.readlink(f"/proc/{holder.pid}/ns/net") == os.readlink("/proc/self/ns/net") and time.monotonic() < deadline:
        assert holder.poll() is None
        time.sleep(0.01)
    assert os.readlink(f"/proc/{holder.pid}/ns/net") != os.readlink("/proc/self/ns/net")
    run(peer_command("world", "ip", "link", "set", "lo", "up"))
    for index, name in enumerate(("wan1", "wan2"), 1):
        edge, uplink = "world-" + name, "uplink-" + name
        run(["ip", "link", "add", edge, "type", "veth", "peer", "name", uplink])
        run(["ip", "link", "set", edge, "netns", str(holder.pid)])
        run(["ip", "link", "set", uplink, "netns", str(namespaces[name].pid)])
        for namespace, device, suffix in (("world", edge, "1"), (name, uplink, "2")):
            run(peer_command(namespace, "ip", "link", "set", device, "up"))
            run(peer_command(namespace, "ip", "addr", "add", f"172.16.{index}.{suffix}/30", "dev", device))
            run(peer_command(namespace, "ip", "-6", "addr", "add", f"2001:db8:10{index}::{suffix}/64", "dev", device, "nodad"))
        run(peer_command(name, "sysctl", "-qw", "net.ipv4.ip_forward=1", "net.ipv6.conf.all.forwarding=1", "net.ipv4.conf.all.rp_filter=0", "net.ipv4.conf.default.rp_filter=0"))
        run(peer_command(name, "ip", "route", "add", "203.0.113.10/32", "via", f"172.16.{index}.1"))
        run(peer_command(name, "ip", "-6", "route", "add", "2001:db8:ffff::10/128", "via", f"2001:db8:10{index}::1"))
        run(peer_command("world", "ip", "route", "add", ("192.0.2.1/32" if index == 1 else "198.51.100.1/32"), "via", f"172.16.{index}.2"))
    run(peer_command("world", "ip", "addr", "add", "203.0.113.10/32", "dev", "lo"))
    run(peer_command("world", "ip", "-6", "addr", "add", "2001:db8:ffff::10/128", "dev", "lo", "nodad"))
    run(peer_command("world", "ip", "-6", "route", "add", "2001:db8:10::/64", "via", "2001:db8:102::2"))
    server("world", "world4", "203.0.113.10", 45000)
    server("world", "world6", "2001:db8:ffff::10", 45000)
    rules = []
    for family, target, wan_mark in (("ip", "203.0.113.10", 0x20000), ("ip6", "2001:db8:ffff::10", 0x40000)):
        for label, device, routing, connection in (("wan", "wan2", wan_mark, wan_mark),
                                                  ("override", "wan1", 0x3f0000, wan_mark),
                                                  ("main", "wan1", 0x3f0000, 0x3f0000)):
            rules.append(f'{family} daddr {target} oifname "{device}" meta mark == {routing | 64} ct mark == {connection | 64} counter comment "{family}-{label}"')
    run(["nft", "-f", "-"], input="""
table inet routing_dynamic_observe {
    chain before {
        type filter hook prerouting priority -151;
        iifname "lan" ip daddr 203.0.113.10 meta mark set meta mark | 64 ct mark set ct mark | 64
        iifname "lan" ip6 daddr 2001:db8:ffff::10 meta mark set meta mark | 64 ct mark set ct mark | 64
    }
    chain output {
        type route hook output priority -151;
        ip daddr 203.0.113.10 meta mark set meta mark | 64 ct mark set ct mark | 64
        ip6 daddr 2001:db8:ffff::10 meta mark set meta mark | 64 ct mark set ct mark | 64
    }
    chain after {
        type filter hook postrouting priority filter;
""" + "\n".join(rules) + "\n    }\n}\n")
    choose("wan2")
    for family, target, lan_source, router_source, wan_mark, nat_mode in (
        ("ipv4", "203.0.113.10", "10.10.0.2", "10.10.0.1", 0x20000, "snat"),
        ("ipv4", "203.0.113.10", "10.10.0.2", "10.10.0.1", 0x20000, "masquerade"),
        ("ipv6", "2001:db8:ffff::10", "2001:db8:10::2", "2001:db8:10::1", 0x40000, "none"),
    ):
        if family == "ipv4":
            rules = ['flush chain ip routing_test_nat postrouting']
            for device, address in (("wan1", "192.0.2.1"), ("wan2", "198.51.100.1")):
                action = "snat to " + address if nat_mode == "snat" else "masquerade"
                rules.append(f'add rule ip routing_test_nat postrouting ip saddr 10.10.0.0/24 oifname "{device}" {action}')
            run(["nft", "-f", "-"], input="\n".join(rules) + "\n")
        version = "ip" if family == "ipv4" else "ip6"
        dynamic_set = "multiwan_nft_dynamic_v4" if family == "ipv4" else "multiwan_nft_dynamic_v6"
        for origin, source in (("lan", lan_source), ("router", router_source)):
            for protocol in ("udp", "tcp"):
                streams = []

                def counters():
                    document = json.loads(run(["nft", "-j", "list", "chain", "inet", "routing_dynamic_observe", "after"]))
                    return {item["rule"]["comment"]: next(expression["counter"]["packets"] for expression in item["rule"]["expr"] if "counter" in expression)
                            for item in document["nftables"] if "rule" in item}

                def check(process, port, label, expected_source, mark, identity=None, initial=None, before=None):
                    before = counters() if before is None else before
                    reply = repeat(process) if initial is None else initial
                    after = counters()
                    assert reply["ok"] and reply["source"] == expected_source, (family, origin, protocol, label, reply, before, after)
                    assert after[version + "-" + label] > before[version + "-" + label], (label, before, after)
                    entry = run(["conntrack", "-L", "-f", family, "-p", protocol, "--orig-src", source, "--orig-dst", target,
                                 "--sport", str(port), "--dport", "45000", "-o", "extended,id"])
                    assert len(entry.splitlines()) == 1 and f"mark={mark | 64} " in entry, entry
                    current_id = re.search(r"\bid=(\d+)", entry).group(1)
                    assert identity is None or current_id == identity, (identity, entry)
                    assert f"src={target} dst={expected_source} " in entry, entry
                    print("DYNAMIC_ROUTING " + json.dumps({"family": family, "nat": nat_mode, "origin": origin, "protocol": protocol,
                          "stage": label, "port": port, "reply": reply, "conntrack": entry.strip(), "counter": after[version + "-" + label]}), flush=True)
                    return current_id

                def start(label, expected_source, mark):
                    command = [sys.executable, SCRIPT, "--session", target, source, protocol, "45000"]
                    before = counters()
                    process = child(peer_command("lan", *command) if origin == "lan" else command,
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                    streams.append(process)
                    initial = receive(process)
                    identity = check(process, initial["port"], label, expected_source, mark, initial=initial, before=before)
                    return process, initial["port"], identity

                original_source = "198.51.100.1" if family == "ipv4" else source
                main_source = "192.0.2.1" if family == "ipv4" else source
                try:
                    established, old_port, old_id = start("wan", original_source, wan_mark)
                    run(["nft", "add", "element", "inet", "multiwan_nft", dynamic_set, "{", target, "}"])
                    if nat_mode == "masquerade":
                        # Linux nf_nat_oif_changed kills MASQUERADE state on egress change.
                        before = counters()
                        reply = repeat(established)
                        after = counters()
                        remaining = run(["conntrack", "-L", "-f", family, "-p", protocol, "--orig-src", source, "--orig-dst", target,
                                         "--sport", str(old_port), "--dport", "45000", "-o", "extended,id"])
                        assert not reply["ok"] and after[version + "-override"] > before[version + "-override"], (reply, before, after)
                        assert not re.search(r"\bid=" + old_id + r"\b", remaining), remaining
                        print("DYNAMIC_MASQUERADE " + json.dumps({"family": family, "origin": origin, "protocol": protocol,
                              "old_id": old_id, "reply": reply, "remaining": remaining.strip(), "counter": after[version + "-override"]}), flush=True)
                        if protocol == "udp":
                            check(established, old_port, "main", main_source, 0x3f0000)
                    else:
                        check(established, old_port, "override", original_source, wan_mark, old_id)
                    bypassed, main_port, main_id = start("main", main_source, 0x3f0000)
                    run(["nft", "delete", "element", "inet", "multiwan_nft", dynamic_set, "{", target, "}"])
                    if nat_mode != "masquerade":
                        check(established, old_port, "wan", original_source, wan_mark, old_id)
                    check(bypassed, main_port, "main", main_source, 0x3f0000, main_id)
                    start("wan", original_source, wan_mark)
                finally:
                    for process in streams:
                        process.stdin.close()
                        process.wait(timeout=4)
    run(["nft", "delete", "table", "inet", "routing_dynamic_observe"])
    CONFIG.clear()
    CONFIG.update(saved)
    shell("multiwan_nft_set_policies_nft || exit 1")
    print("PASS dynamic bypass add/remove: LAN/router TCP/UDP, fixed-SNAT/IPv6 continuity, MASQUERADE egress retirement/recovery, exact FIB/marks/QoS and retained fresh-main identity.", flush=True)


def special_actions():
    saved = CONFIG.copy()
    sessions = []
    rates = {}
    try:
        choose("wan2")
        for family, target, source, wan, mark in (
            ("ipv4", "203.0.113.9", "10.10.0.2", "wan2", "0x20000"),
            ("ipv6", "2001:db8:ffff::9", "2001:db8:10::2", "wan2v6", "0x40000"),
        ):
            process, port = session(wan, target, source)
            sessions.append((process, port, family, wan, mark))
        # Test rejection independently of the kernel's ICMP rate limiter.
        for name in ("ipv4/icmp_ratelimit", "ipv6/icmp/ratelimit"):
            path = Path("/proc/sys/net/" + name)
            rates[path] = path.read_text()
            path.write_text("0")
        for selector in ("direct", "fallback"):
            for action, mark in (("default", "0x3f0000"), ("unreachable", "0x3e0000"), ("blackhole", "0x3d0000")):
                online(*INTERFACES if selector == "direct" else ())
                CONFIG["balanced:last_resort"] = action
                for rule in ("forward", "forward6"):
                    CONFIG[rule + ":use_policy"] = action if selector == "direct" else "balanced"
                shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_user_rules_nft || exit 1")
                for family, target, lan_source, router_source in (
                    ("ipv4", "203.0.113.9", "10.10.0.2", "10.10.0.1"),
                    ("ipv6", "2001:db8:ffff::9", "2001:db8:10::2", "2001:db8:10::1"),
                ):
                    for origin, name, source in (("lan", "lan", lan_source), ("router", None, router_source)):
                        comment = f"special_{selector}_{action}_{family}_{origin}"
                        run(["nft", "add", "rule", "inet", "multiwan_nft", "multiwan_nft_hook",
                             f'meta nfproto {family} udp sport {next_port} udp dport 45000 meta mark & 0x3f0000 == {mark} ct mark & 0x3f0000 == {mark} counter comment "{comment}"'])
                        result = requests(name, "udp", target, 45000, source=source)[0]
                        if action == "default":
                            assert result["ok"] and result["wan"] == ("wan1" if family == "ipv4" else "wan1v6"), result
                        else:
                            expected_error = errno.ENETUNREACH if action == "unreachable" else (errno.EINVAL if origin == "router" else None)
                            assert not result["ok"] and result["errno"] == expected_error, (comment, result, expected_error)
                        state = json.loads(run(["nft", "-j", "list", "chain", "inet", "multiwan_nft", "multiwan_nft_hook"]))
                        counter = next(statement["counter"]["packets"] for item in state["nftables"]
                                       if item.get("rule", {}).get("comment") == comment
                                       for statement in item["rule"]["expr"] if "counter" in statement)
                        assert counter == 1, (comment, counter)
                        for process, port, session_family, wan, session_mark in sessions:
                            reply = repeat(process)
                            assert reply["ok"] and reply["wan"] == wan, (comment, reply)
                            assert f"sport={port} dport=45000 " in conntracks(session_mark, session_family)
                        print("SPECIAL_ACTION " + json.dumps({"selector": selector, "action": action, "family": family,
                              "origin": origin, "result": result, "marked_packets": counter, "existing_sessions": "wan2/wan2v6 retained"}), flush=True)
        print("PASS direct/fallback default, unreachable and blackhole for new LAN/router IPv4/IPv6 flows; established WAN/NAT identity survives policy edits.", flush=True)
    finally:
        for process, *_ in sessions:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=2)
        run(["conntrack", "-F"])
        for path, value in rates.items():
            path.write_text(value)
        CONFIG.clear()
        CONFIG.update(saved)
        online(*INTERFACES)
        shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_user_rules_nft || exit 1")


try:
    Path("/proc/sys/net/ipv4/ip_forward").write_text("1")
    Path("/proc/sys/net/ipv6/conf/all/forwarding").write_text("1")
    Path("/proc/sys/net/ipv4/conf/all/rp_filter").write_text("0")
    Path("/proc/sys/net/ipv4/conf/default/rp_filter").write_text("0")
    run(["ip", "link", "set", "lo", "up"])
    own_namespace = os.readlink("/proc/self/ns/net")
    for name in ("lan", "wan1", "wan2"):
        holder = child(["unshare", "-n", "sleep", "300"])
        namespaces[name] = holder
        deadline = time.monotonic() + 3
        while os.readlink(f"/proc/{holder.pid}/ns/net") == own_namespace and time.monotonic() < deadline:
            assert holder.poll() is None
            time.sleep(0.01)
        assert os.readlink(f"/proc/{holder.pid}/ns/net") != own_namespace
        run(["ip", "link", "add", name, "type", "veth", "peer", "name", "peer-" + name])
        run(["ip", "link", "set", "peer-" + name, "netns", str(holder.pid)])
        run(["ip", "link", "set", name, "up"])
        run(peer_command(name, "ip", "link", "set", "lo", "up"))
        run(peer_command(name, "ip", "link", "set", "peer-" + name, "up"))
    for name, network in (("lan", "10.10.0"), ("wan1", "192.0.2"), ("wan2", "198.51.100")):
        subnet = {"lan": "10", "wan1": "1", "wan2": "2"}[name]
        run(["ip", "addr", "add", network + ".1/24", "dev", name])
        run(peer_command(name, "ip", "addr", "add", network + ".2/24", "dev", "peer-" + name))
        run(["ip", "-6", "addr", "add", f"2001:db8:{subnet}::1/64", "dev", name, "nodad"])
        run(peer_command(name, "ip", "-6", "addr", "add", f"2001:db8:{subnet}::2/64", "dev", "peer-" + name, "nodad"))
        if name == "lan":
            run(peer_command(name, "ip", "route", "add", "default", "via", network + ".1"))
            run(peer_command(name, "ip", "-6", "route", "add", "default", "via", "2001:db8:10::1"))
        else:
            run(peer_command(name, "ip", "addr", "add", "203.0.113.9/32", "dev", "lo"))
            run(peer_command(name, "ip", "-6", "addr", "add", "2001:db8:ffff::9/128", "dev", "lo", "nodad"))
            run(peer_command(name, "ip", "-6", "route", "add", "2001:db8:10::/64", "via", f"2001:db8:{subnet}::1"))
            server(name, name, "203.0.113.9", 45000)
            server(name, name + "v6", "2001:db8:ffff::9", 45000)
    run(["ip", "route", "add", "default", "via", "192.0.2.2", "dev", "wan1", "metric", "10"])
    run(["ip", "route", "add", "default", "via", "198.51.100.2", "dev", "wan2", "metric", "20"])
    run(["ip", "-6", "route", "add", "default", "via", "2001:db8:1::2", "dev", "wan1", "metric", "10"])
    run(["ip", "-6", "route", "add", "default", "via", "2001:db8:2::2", "dev", "wan2", "metric", "20"])
    online("wan1", "wan2", "wan1v6", "wan2v6")
    shell("""
multiwan_nft_reconcile_conntrack_map || exit 1
multiwan_nft_load_base_ruleset || exit 1
for name in wan1 wan2 wan1v6 wan2v6; do
    multiwan_nft_create_iface_nft "$name" "${name%v6}" || exit 1
    multiwan_nft_create_iface_rules "$name" "${name%v6}" || exit 1
    multiwan_nft_create_iface_route "$name" || exit 1
done
multiwan_nft_set_connected_ipv4 || exit 1
multiwan_nft_set_connected_ipv6 || exit 1
multiwan_nft_set_general_rules || exit 1
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
multiwan_nft_commit_conntrack_map || exit 1
""")
    for table, gateway in (("1", "192.0.2.2"), ("2", "198.51.100.2")):
        assert gateway in run(["ip", "route", "show", "table", table, "default"])
        assert "10.10.0.0/24" in run(["ip", "route", "show", "table", table])
    compatibility = Path("/proc/sys/net/ipv4/nexthop_compat_mode")
    previous_compatibility = compatibility.read_text()
    for flag, interface, table, gateway, prefix, target, source, mark, nhid in (
        ("-4", "wan2", "2", "198.51.100.2", "198.18.190.0/24", "198.18.190.9", "10.10.0.2", "0x20000", "71"),
        ("-6", "wan2v6", "4", "2001:db8:2::2", "2001:db8:190::/64", "2001:db8:190::9", "2001:db8:10::2", "0x40000", "72"),
    ):
        run(["ip", flag, "nexthop", "add", "id", nhid, "via", gateway, "dev", "wan2"])
        run(["ip", flag, "route", "add", prefix, "nhid", nhid])
        for expanded in ("1", "0"):
            compatibility.write_text(expanded)
            original = run(["ip", flag, "route", "show", "exact", prefix])
            event = original.rstrip("\n")
            assert f"nhid {nhid}" in original
            assert ("via " in original) == (expanded == "1"), original
            shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            route = run(["ip", flag, "route", "get", target, "from", source, "iif", "lan", "mark", mark])
            assert "dev wan2" in route and f"via {gateway}" in route, route
            monitor = f"eval \"$(sed -n '/^multiwan_nft_add_all_routes()/,/^main()/p' {shlex.quote(str(CORE.parents[2] / 'usr/sbin/multiwan-nft-rtmon'))} | sed '$d')\"\n"
            family = "ipv4" if flag == "-4" else "ipv6"
            run(["ip", flag, "route", "del", prefix])
            event_output = shell("exec 2>&1\n" + monitor + f"multiwan_nft_rtmon_route_handle {shlex.quote('Deleted ' + event)} {family} || exit 1")
            remaining = run(["ip", flag, "route", "show", "table", table, "exact", prefix]).strip()
            assert not remaining, (flag, expanded, original, remaining, event_output)
            run(["ip", flag, "route", "add", prefix, "nhid", nhid])
            shell(monitor + f"multiwan_nft_rtmon_route_handle {shlex.quote(event)} {family} || exit 1")
            assert f"nhid {nhid}" in run(["ip", flag, "route", "show", "table", table, "exact", prefix])
        compatibility.write_text("1")
        run(["ip", flag, "route", "del", prefix])
        shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
        assert not run(["ip", flag, "route", "show", "table", table, "exact", prefix]).strip()
        run(["ip", flag, "nexthop", "del", "id", nhid])
    compatibility.write_text(previous_compatibility)
    print("PASS actual IPv4/IPv6 nexthop objects in expanded/ID-only modes, policy lookup and stale-route removal.", flush=True)
    for flag, interface, table, other_table, gateway, nhid in (
        ("-4", "wan2", "2", "1", "198.51.100.2", "81"),
        ("-6", "wan2v6", "4", "3", "2001:db8:2::2", "82"),
    ):
        run(["ip", flag, "nexthop", "add", "id", nhid, "via", gateway, "dev", "wan2"])
        run(["ip", flag, "route", "add", "default", "nhid", nhid, "metric", "99"])
        for expanded in ("1", "0"):
            compatibility.write_text(expanded)
            shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            owned = run(["ip", flag, "route", "show", "table", table, "default"])
            assert f"nhid {nhid}" in owned, (flag, expanded, owned)
            shell(f"multiwan_nft_create_iface_route {'wan1' if flag == '-4' else 'wan1v6'} || exit 1")
            assert f"nhid {nhid}" not in run(["ip", flag, "route", "show", "table", other_table, "default"])
        run(["ip", flag, "route", "del", "default", "nhid", nhid, "metric", "99"])
        shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
        assert f"nhid {nhid}" not in run(["ip", flag, "route", "show", "table", table, "default"])
        run(["ip", flag, "nexthop", "del", "id", nhid])
    compatibility.write_text(previous_compatibility)
    print("PASS nexthop-object defaults retain exact WAN ownership with expanded and ID-only dumps.", flush=True)
    for flag, interfaces, tables, gateways, prefix, target, source, marks in (
        ("-4", ("wan1", "wan2"), ("1", "2"), ("192.0.2.2", "198.51.100.2", "198.51.100.3"),
         "198.18.191.0/24", "198.18.191.9", "10.10.0.2", ("0x10000", "0x20000")),
        ("-6", ("wan1v6", "wan2v6"), ("3", "4"), ("2001:db8:1::2", "2001:db8:2::2", "2001:db8:2::3"),
         "2001:db8:191::/64", "2001:db8:191::9", "2001:db8:10::2", ("0x30000", "0x40000")),
    ):
        for nhid, gateway, device in (("91", gateways[1], "wan2"), ("92", gateways[2], "wan2"), ("93", gateways[0], "wan1")):
            run(["ip", flag, "nexthop", "add", "id", nhid, "via", gateway, "dev", device])
        run(["ip", "nexthop", "add", "id", "94", "group", "91/92,3"])
        for expanded in ("1", "0"):
            compatibility.write_text(expanded)
            run(["ip", "nexthop", "replace", "id", "94", "group", "91/92,3"])
            for destination in (prefix, "default"):
                run(["ip", flag, "route", "add", destination, "nhid", "94", "metric", "99"])
            for interface in interfaces:
                shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            preserved = [run(["ip", flag, "route", "show", "table", table]) for table in tables]
            family_ip = "IP4" if flag == "-4" else "IP6"
            shell(f"""
failed_group_member() {{
    [ "$*" != '{flag} nexthop get id 92' ] || return 1
    {shlex.quote(shutil.which('ip'))} "$@"
}}
{family_ip}='failed_group_member {flag}'
if multiwan_nft_create_iface_route {interfaces[0]}; then exit 1; fi
""")
            assert preserved == [run(["ip", flag, "route", "show", "table", table]) for table in tables], "Failed group read mutated routes"
            owned = run(["ip", flag, "route", "show", "table", tables[1]])
            assert "nhid 94" in owned and prefix in owned, (flag, expanded, owned)
            assert "nhid 94" not in run(["ip", flag, "route", "show", "table", tables[0]])
            # A group spanning WANs must not override the WAN selected by its packet mark.
            run(["ip", "nexthop", "replace", "id", "94", "group", "91/92,3/93,2"])
            for interface in interfaces:
                shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            for index in (0, 1):
                owned = run(["ip", flag, "route", "show", "table", tables[index], "exact", prefix])
                assert owned and "nhid 94" not in owned, (flag, expanded, owned)
                assert f"dev wan{2-index}" not in owned, (flag, expanded, owned)
                defaults = run(["ip", flag, "route", "show", "table", tables[index], "default"])
                assert "metric 99" in defaults and "nhid 94" not in defaults and f"dev wan{2-index}" not in defaults, defaults
                if index == 1:
                    assert "weight 1" in owned and "weight 3" in owned, owned
                for port in range(19001, 19009):
                    lookup = run(["ip", flag, "route", "get", target, "from", source, "iif", "lan", "mark", marks[index],
                                  "ipproto", "udp", "sport", str(port), "dport", "45000"])
                    assert f"dev wan{index+1}" in lookup and f"table {tables[index]}" in lookup, lookup
            run(["ip", flag, "nexthop", "replace", "id", "92", "via", gateways[1], "dev", "wan2"])
            for interface in interfaces:
                shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            duplicate = run(["ip", flag, "route", "show", "table", tables[1], "exact", prefix])
            assert duplicate and "nhid 94" not in duplicate and "dev wan2" in duplicate, duplicate
            run(["ip", flag, "nexthop", "add", "id", "95", "via", gateways[2], "dev", "wan2"])
            run(["ip", "nexthop", "replace", "id", "94", "group", "91,256/92,256/93/95"])
            preserved = [run(["ip", flag, "route", "show", "table", table]) for table in tables]
            shell(f"if multiwan_nft_create_iface_route {interfaces[1]}; then exit 1; fi")
            assert preserved == [run(["ip", flag, "route", "show", "table", table]) for table in tables], "Inexact weight projection mutated routes"
            run(["ip", "nexthop", "replace", "id", "94", "group", "91/92,3/93,2"])
            run(["ip", flag, "nexthop", "del", "id", "95"])
            run(["ip", flag, "nexthop", "replace", "id", "92", "via", gateways[2], "dev", "wan2"])
            for interface in interfaces:
                shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            with socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, socket.NETLINK_ROUTE) as observer:
                observer.bind((0, 0x80000440))
                for interface in interfaces:
                    shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
                assert not select.select([observer], [], [], 0)[0], "Unchanged groups emitted route/nexthop mutations"
            run(["ip", flag, "route", "replace", prefix, "via", gateways[0], "dev", "wan1", "metric", "99"])
            ordinary = run(["ip", flag, "-o", "route", "show", "exact", prefix]).strip()
            family = "ipv4" if flag == "-4" else "ipv6"
            shell(monitor + f"RTMON_NEXTHOPS_ACTIVE=1\nmultiwan_nft_rtmon_route_handle {shlex.quote(ordinary)} {family} || exit 1")
            assert not run(["ip", flag, "route", "show", "table", tables[1], "exact", prefix]).strip(), "Ordinary replacement retained another WAN's group projection"
            assert "dev wan1" in run(["ip", flag, "route", "show", "table", tables[0], "exact", prefix])
            run(["ip", flag, "route", "replace", prefix, "nhid", "94", "metric", "99"])
            grouped = run(["ip", flag, "-o", "route", "show", "exact", prefix]).strip()
            shell(monitor + f"multiwan_nft_rtmon_route_handle {shlex.quote(grouped)} {family} || exit 1")
            for destination in (prefix, "default"):
                run(["ip", flag, "route", "del", destination, "nhid", "94", "metric", "99"])
            for interface in interfaces:
                shell(f"multiwan_nft_create_iface_route {interface} || exit 1")
            for table in tables:
                assert not run(["ip", flag, "route", "show", "table", table, "exact", prefix]).strip()
        run(["ip", flag, "route", "add", prefix, "metric", "99", "nexthop", "via", gateways[0], "dev", "wan1", "weight", "2",
             "nexthop", "via", gateways[1], "dev", "wan2", "weight", "1", "nexthop", "via", gateways[2], "dev", "wan2", "weight", "3"])
        event = run(["ip", flag, "-o", "route", "show", "exact", prefix]).strip()
        family = "ipv4" if flag == "-4" else "ipv6"
        shell(monitor + f"multiwan_nft_rtmon_route_handle {shlex.quote(event)} {family} || exit 1")
        for index in (0, 1):
            owned = run(["ip", flag, "route", "show", "table", tables[index], "exact", prefix])
            assert owned and f"dev wan{2-index}" not in owned, owned
        run(["ip", flag, "route", "del", prefix])
        shell(monitor + f"multiwan_nft_rtmon_route_handle {shlex.quote('Deleted ' + event)} {family} || exit 1")
        for table in tables:
            assert not run(["ip", flag, "route", "show", "table", table, "exact", prefix]).strip()
        for nhid in ("94", "93", "92", "91"):
            run(["ip", flag, "nexthop", "del", "id", nhid])
    compatibility.write_text(previous_compatibility)
    print("PASS IPv4/IPv6 nexthop groups: single-WAN identity, mixed-WAN isolation/weights and withdrawal in both dump modes.", flush=True)
    run(["nft", "-f", "-"], input="""
table ip routing_test_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        ip saddr 10.10.0.0/24 oifname { "wan1", "wan2" } masquerade
    }
}
table inet routing_test_observe {
    chain postrouting {
        type filter hook postrouting priority filter;
        tcp sport 45001 oifname "wan2" ct mark & 0x3f0000 == 0x20000 counter comment "incoming_backup_reply"
        ip6 saddr 2001:db8:2::1 tcp sport 45001 oifname "wan2" ct mark & 0x3f0000 == 0x40000 counter comment "incoming_backup_reply6"
    }
}
""")
    tcp_rules()
    special_actions()
    dynamic_routing()
    result = requests("lan", "udp", "203.0.113.9", 45000, 400)
    assert all(reply["ok"] for reply in result), result
    counts = collections.Counter(reply["wan"] for reply in result)
    assert 50 <= counts["wan1"] <= 150 and counts["wan2"] == 400 - counts["wan1"], counts
    assert all(reply["source"] == ("192.0.2.1" if reply["wan"] == "wan1" else "198.51.100.1") for reply in result)
    print("PASS real UDP forwarding, weighted WAN egress, masquerade and reverse NAT:", dict(counts), flush=True)

    result6 = requests("lan", "udp", "2001:db8:ffff::9", 45000, 200, source="2001:db8:10::2")
    counts6 = collections.Counter(reply.get("wan") for reply in result6)
    assert all(reply["ok"] and reply["source"] == "2001:db8:10::2" for reply in result6), [reply for reply in result6 if not reply["ok"] or reply.get("source") != "2001:db8:10::2"]
    assert 20 <= counts6["wan1v6"] <= 80 and counts6["wan2v6"] == 200 - counts6["wan1v6"], counts6
    print("PASS real IPv6 forwarding and replies through weighted IP6 policy tables without NAT66:", dict(counts6), flush=True)

    for name in ("wan1", "wan2"):
        choose(name)
        reply = requests("lan", "tcp", "203.0.113.9", 45000)[0]
        assert reply["ok"] and reply["wan"] == name, reply
        reply6 = requests("lan", "tcp", "2001:db8:ffff::9", 45000, source="2001:db8:10::2")[0]
        assert reply6["ok"] and reply6["wan"] == name + "v6", reply6
    print("PASS real TCP echo and SNAT replies through both policy tables.", flush=True)

    choose("wan1")
    server(None, "router", "0.0.0.0", 45001)
    reply = requests("wan2", "tcp", "198.51.100.1", 45001, source="203.0.113.9")[0]
    assert reply["ok"] and reply["source"] == "203.0.113.9", reply
    observer = json.loads(run(["nft", "-j", "list", "chain", "inet", "routing_test_observe", "postrouting"]))
    observed = {item["rule"]["comment"]: next(statement["counter"]["packets"] for statement in item["rule"]["expr"] if "counter" in statement)
                for item in observer["nftables"] if "rule" in item}
    assert observed["incoming_backup_reply"] > 0, (observed, run(["conntrack", "-L", "-f", "ipv4", "-p", "tcp"]))
    print("PASS incoming backup-WAN TCP connection replies through backup despite primary main default and populated connected sets.", flush=True)

    server(None, "router6", "2001:db8:2::1", 45001)
    reply6 = requests("wan2", "tcp", "2001:db8:2::1", 45001, source="2001:db8:ffff::9")[0]
    assert reply6["ok"] and reply6["source"] == "2001:db8:ffff::9", reply6
    observer = json.loads(run(["nft", "-j", "list", "chain", "inet", "routing_test_observe", "postrouting"]))
    observed = {item["rule"]["comment"]: next(statement["counter"]["packets"] for statement in item["rule"]["expr"] if "counter" in statement)
                for item in observer["nftables"] if "rule" in item}
    assert observed["incoming_backup_reply6"] > 0, observed
    print("PASS incoming backup-WAN IPv6 TCP symmetry with populated connected sets and preferred primary default.", flush=True)

    CONFIG["forward:use_policy"] = "default"
    shell("multiwan_nft_set_user_rules_nft || exit 1")
    fallback, fallback_port = session("wan1")
    assert has_port(conntracks("0x3f0000"), fallback_port)
    CONFIG["forward:use_policy"] = "balanced"
    choose("wan2")
    shell("multiwan_nft_set_user_rules_nft || exit 1")
    assert repeat(fallback)["wan"] == "wan1", "Existing main-table NAT flow moved to a new policy WAN"
    assert requests("lan", "udp", "203.0.113.9", 45000)[0]["wan"] == "wan2"
    print("PASS established main/default NAT affinity survives transition while fresh flows follow new policy.", flush=True)

    choose("wan2")
    backup, backup_port = session("wan2")
    backup6, backup_port6 = session("wan2v6", "2001:db8:ffff::9", "2001:db8:10::2")
    run(peer_command("lan", "ping", "-4", "-n", "-c", "1", "-W", "1", "203.0.113.9"))
    run(peer_command("lan", "ping", "-6", "-n", "-c", "1", "-W", "1", "2001:db8:ffff::9"))
    choose("wan1")
    primary, primary_port = session("wan1")
    primary6, primary_port6 = session("wan1v6", "2001:db8:ffff::9", "2001:db8:10::2")
    run(peer_command("lan", "ping", "-4", "-n", "-c", "1", "-W", "1", "203.0.113.9"))
    run(peer_command("lan", "ping", "-6", "-n", "-c", "1", "-W", "1", "2001:db8:ffff::9"))
    assert repeat(backup)["wan"] == "wan2", "Policy tier change moved an established backup session"
    assert has_port(conntracks("0x10000"), primary_port)
    assert has_port(conntracks("0x20000"), backup_port)
    assert "type=8" in conntracks("0x10000", protocol="icmp")
    assert "type=8" in conntracks("0x20000", protocol="icmp")
    assert "type=128" in conntracks("0x30000", "ipv6", "icmpv6")
    assert "type=128" in conntracks("0x40000", "ipv6", "icmpv6")
    online("wan2", "wan2v6")
    shell("multiwan_nft_set_policies_nft || exit 1\nmultiwan_nft_set_tracker_oif_rules wan1 wan1 || exit 1\nmultiwan_nft_set_tracker_oif_rules wan1v6 wan1 || exit 1")
    assert not repeat(primary)["ok"], "Offline marked session escaped isolation before purge"
    assert repeat(backup)["wan"] == "wan2"
    assert not repeat(primary6)["ok"]
    assert repeat(backup6)["wan"] == "wan2v6"
    reply = requests("lan", "udp", "203.0.113.9", 45000, 20)
    assert all(item["ok"] and item["wan"] == "wan2" for item in reply), reply
    shell("multiwan_nft_flush_conntrack_iface wan1 || exit 1")
    assert not has_port(conntracks("0x10000"), primary_port)
    assert has_port(conntracks("0x20000"), backup_port)
    assert not conntracks("0x10000", protocol="icmp").strip(), "Failed-WAN ICMP conntrack survived scoped purge"
    assert "type=8" in conntracks("0x20000", protocol="icmp"), "Another WAN's ICMP conntrack was purged"
    recovered = repeat(primary)
    if not recovered["ok"]:
        recovered = repeat(primary)
    assert recovered["ok"] and recovered["wan"] == "wan2" and recovered["source"] == "198.51.100.1", recovered
    assert repeat(backup)["wan"] == "wan2"
    shell("multiwan_nft_flush_conntrack_iface wan1v6 || exit 1")
    assert not conntracks("0x30000", "ipv6", "icmpv6").strip(), "Failed-WAN ICMPv6 conntrack survived scoped purge"
    assert "type=128" in conntracks("0x40000", "ipv6", "icmpv6"), "Another WAN's ICMPv6 conntrack was purged"
    recovered6 = repeat(primary6)
    if not recovered6["ok"]:
        recovered6 = repeat(primary6)
    assert recovered6["ok"] and recovered6["wan"] == "wan2v6", recovered6
    assert repeat(backup6)["wan"] == "wan2v6"
    assert f"sport={backup_port6} dport=45000 " in conntracks("0x40000", "ipv6")
    print("PASS IPv6 offline isolation, scoped UDP/ICMPv6 purge, same-tuple recovery, and surviving backup IPv6 sessions.", flush=True)
    print("PASS offline isolation, new-flow failover, real scoped UDP/ICMP purge, same-tuple UDP recovery, and surviving backup sessions.", flush=True)
    server(None, "retired-router4", "198.51.100.1", 45002)
    assert requests("wan2", "udp", "198.51.100.1", 45002, source="203.0.113.9")[0]["ok"]
    assert requests("wan2", "udp", "2001:db8:2::1", 45001, source="2001:db8:ffff::9")[0]["ok"]
    assert requests(None, "udp", "203.0.113.9", 45000, source="10.10.0.1")[0]["wan"] == "wan2"
    assert requests(None, "udp", "2001:db8:ffff::9", 45000, source="2001:db8:10::1")[0]["wan"] == "wan2v6"
    INTERFACES = ["wan2", "wan1", "wan1v6", "wan2v6"]
    online("wan1", "wan2", "wan1v6", "wan2v6")
    shell("multiwan_nft_reconcile_conntrack_map || exit 1")
    pending = requests("lan", "udp", "203.0.113.9", 45000, 2)
    assert all(not item["ok"] for item in pending), "Old live policy recreated a retired WAN mark after reconciliation"
    assert not requests("wan2", "udp", "198.51.100.1", 45002, source="203.0.113.9")[0]["ok"], "Local INPUT confirmed a retired mark"
    assert not requests(None, "udp", "203.0.113.9", 45000, source="10.10.0.1")[0]["ok"], "Local OUTPUT confirmed a retired mark"
    assert not conntracks("0x10000").strip() and not conntracks("0x20000").strip(), "A retired mark was confirmed during ID reassignment"
    assert repeat(backup6)["wan"] == "wan2v6", "Reconciliation blocked an unchanged IPv6 WAN"
    assert not has_port(conntracks("0x20000"), backup_port), "A retired WAN2 ID survived before reuse by WAN1"
    assert f"src=2001:db8:10::2 dst=2001:db8:ffff::9 sport={backup_port6} dport=45000 " in conntracks("0x40000", "ipv6"), "Reorder purged an unaffected IPv6 WAN"
    rebuild_rules = """
multiwan_nft_load_base_ruleset || exit 1
for name in wan1 wan2 wan1v6 wan2v6; do
    multiwan_nft_create_iface_nft "$name" "${name%v6}" || exit 1
    multiwan_nft_create_iface_rules "$name" "${name%v6}" || exit 1
    multiwan_nft_create_iface_route "$name" || exit 1
done
multiwan_nft_set_connected_ipv4 || exit 1
multiwan_nft_set_connected_ipv6 || exit 1
multiwan_nft_set_general_rules || exit 1
multiwan_nft_set_policies_nft || exit 1
multiwan_nft_set_user_rules_nft || exit 1
multiwan_nft_commit_conntrack_map || exit 1
"""
    shell(rebuild_rules)
    reassigned = repeat(backup)
    assert reassigned["ok"] and reassigned["wan"] == "wan1" and reassigned["source"] == "192.0.2.1", reassigned
    assert repeat(backup6)["wan"] == "wan2v6", "Restart moved an unchanged IPv6 conntrack to the current policy WAN"
    assert repeat(fallback)["wan"] == "wan1", "Restart invalidated an unchanged main/default connection"
    assert "multiwan_nft_reconcile" not in run(["nft", "list", "tables"]), "Successful rebuild retained a retired-mark guard"
    print("PASS live IPv4 ID reassignment blocks old forwarded/INPUT/OUTPUT marks; unaffected IPv6/default sessions survive.", flush=True)
    stable4, stable_port4 = session("wan1")
    INTERFACES = ["wan2", "wan1", "wan2v6", "wan1v6"]
    shell("multiwan_nft_reconcile_conntrack_map || exit 1")
    assert not requests("lan", "udp", "2001:db8:ffff::9", 45000, source="2001:db8:10::2")[0]["ok"], "Old IPv6 forward policy recreated a retired mark"
    assert not requests("wan2", "udp", "2001:db8:2::1", 45001, source="2001:db8:ffff::9")[0]["ok"], "IPv6 INPUT confirmed a retired mark"
    assert not requests(None, "udp", "2001:db8:ffff::9", 45000, source="2001:db8:10::1")[0]["ok"], "IPv6 OUTPUT confirmed a retired mark"
    assert not conntracks("0x30000", "ipv6").strip() and not conntracks("0x40000", "ipv6").strip(), "Retired IPv6 marks survived reassignment"
    assert repeat(stable4)["wan"] == "wan1" and has_port(conntracks("0x20000"), stable_port4), "IPv6 reassignment disrupted an unchanged IPv4 session"
    shell(rebuild_rules)
    assert repeat(backup6)["wan"] == "wan1v6", "IPv6 session did not recover through its new policy identity"
    assert repeat(stable4)["wan"] == "wan1"
    assert "multiwan_nft_reconcile" not in run(["nft", "list", "tables"])
    print("PASS live IPv6 ID reassignment blocks forwarded/INPUT/OUTPUT marks and preserves unchanged IPv4 sessions.", flush=True)
    qos_session, qos_port = session("wan1")
    run(["conntrack", "-U", "-f", "ipv4", "-p", "udp", "--orig-src", "10.10.0.2", "--orig-dst", "203.0.113.9",
         "--sport", str(qos_port), "--dport", "45000", "--mark", "64", "--timeout", "300"])
    unrelated = ["conntrack", "-L", "-f", "ipv4", "-p", "udp", "-m", "64/0xffffffff"]
    assert has_port(run(unrelated), qos_port)
    (STATE / "saved_conntrack_map").unlink()
    shell("multiwan_nft_reconcile_conntrack_map || exit 1")
    assert (STATE / "saved_conntrack_map").read_text().splitlines() == ["0x003f0000", "legacy"]
    for family in ("ipv4", "ipv6"):
        for mark in ("0x10000", "0x20000", "0x30000", "0x40000", "0x3f0000"):
            assert not conntracks(mark, family).strip(), "Unknown legacy routing mark survived retirement"
    assert has_port(run(unrelated), qos_port), "Legacy migration purged a QoS-only conntrack"
    assert not requests("lan", "udp", "203.0.113.9", 45000)[0]["ok"], "Old live IPv4 rules confirmed an unknown legacy mark"
    assert not requests("lan", "udp", "2001:db8:ffff::9", 45000, source="2001:db8:10::2")[0]["ok"], "Old live IPv6 rules confirmed an unknown legacy mark"
    assert not requests("wan2", "udp", "198.51.100.1", 45002, source="203.0.113.9")[0]["ok"], "Legacy IPv4 INPUT confirmed a retired mark"
    assert not requests("wan2", "udp", "2001:db8:2::1", 45001, source="2001:db8:ffff::9")[0]["ok"], "Legacy IPv6 INPUT confirmed a retired mark"
    assert not requests(None, "udp", "203.0.113.9", 45000, source="10.10.0.1")[0]["ok"], "Legacy IPv4 OUTPUT confirmed a retired mark"
    assert not requests(None, "udp", "2001:db8:ffff::9", 45000, source="2001:db8:10::1")[0]["ok"], "Legacy IPv6 OUTPUT confirmed a retired mark"
    shell(rebuild_rules)
    assert repeat(backup)["wan"] == "wan1" and repeat(backup6)["wan"] == "wan1v6"
    assert repeat(fallback)["wan"] == "wan1" and has_port(conntracks("0x20000"), fallback_port)
    assert has_port(run(unrelated), qos_port), "Legacy rebuild removed a conntrack outside its mark namespace"
    assert "multiwan_nft_reconcile" not in run(["nft", "list", "tables"])
    assert "legacy" not in (STATE / "saved_conntrack_map").read_text().splitlines()
    print("PASS missing-map upgrade retires both-family WAN/default marks, blocks old rules, preserves QoS-only state and recovers actual sessions.", flush=True)
    run(["ip", "rule", "add", "pref", "900", "lookup", "main"])
    shell("config_foreach() { :; }\nmultiwan_nft_cleanup_owned_tables || exit 1")
    rules4 = run(["ip", "-4", "rule", "list"])
    rules6 = run(["ip", "-6", "rule", "list"])
    assert "900:" in rules4, "Cleanup removed an unowned rule"
    assert not any(f"{offset + interface}:" in rules4 + rules6 for interface in range(1, 5) for offset in (1000, 2000, 3000))
    for family, table in (("-4", "1"), ("-4", "2"), ("-6", "3"), ("-6", "4")):
        assert not run(["ip", family, "route", "show", "table", table]).strip()
    print("PASS owned FIB cleanup survives removed configuration and preserves an unrelated routing rule.", flush=True)
    print("NFT routing/NAT regressions passed; host/router network namespaces unchanged.", flush=True)
finally:
    for process in reversed(children):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    temporary.cleanup()
