#!/usr/bin/env python3
"""Run the raw installer with redirected filesystem paths and controlled downloads."""
from pathlib import Path
import json
import os
import re
import signal
import stat
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parent.parent
installer = (repo / "scripts/install-nft.sh").read_text()
main = {
    "etc/config/multiwan-nft": 0o644, "etc/init.d/multiwan-nft": 0o755,
    "etc/multiwan-nft.user": 0o755, "etc/hotplug.d/iface/15-multiwan-nft": 0o644,
    "etc/hotplug.d/iface/16-multiwan-nft-user": 0o644,
    **{"lib/multiwan-nft/" + name: 0o644 for name in ("common.sh", "multiwan_nft.sh", "process-lock.sh")},
    "usr/libexec/rpcd/multiwan_nft": 0o755,
    **{"usr/sbin/" + name: 0o755 for name in ("multiwan-nft", "multiwan-nft-track", "multiwan-nft-rtmon")},
}
luci = {
    "usr/libexec/luci-multiwan-nft": 0o755,
    "usr/share/luci/menu.d/luci-app-multiwan-nft.json": 0o644,
    "usr/share/rpcd/acl.d/luci-app-multiwan-nft.json": 0o644,
    "www/luci-static/resources/view/status/include/90_multiwan_nft.js": 0o644,
    "www/luci-static/resources/view/multiwan-nft/multiwan-nft.css": 0o644,
    **{"www/luci-static/resources/view/multiwan-nft/network/" + name + ".js": 0o644
       for name in ("globals", "interface", "member", "notify", "policy", "rule")},
    **{"www/luci-static/resources/view/multiwan-nft/status/" + name + ".js": 0o644
       for name in ("detail", "diagnostics", "overview", "troubleshooting")},
}
assert len(main) == 12 and len(luci) == 15


def snapshot(root):
    return {str(path.relative_to(root)): ("symlink", os.readlink(path)) if path.is_symlink() else (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
            for directory in ("etc", "lib", "usr", "www", "var")
            for path in (root / directory).rglob("*") if path.is_file() or path.is_symlink()}


def run_case(shell, component, failure="", legacy=False, interrupt=False, package_failure=False, fresh=False,
             move_failure="", initial_running=False, initial_enabled=True, symlink_init=False, activation_failure=False,
             restore_failure=False, apply_interrupt=False, interrupt_signal=signal.SIGTERM):
    with tempfile.TemporaryDirectory(prefix="nft-install-test-") as temporary:
        work = Path(temporary)
        root, bin_dir, source = work / "root", work / "bin", work / "source"
        for path in (root / "tmp", root / "var/run", bin_dir, source):
            path.mkdir(parents=True)
        service = b'''#!/bin/sh
printf '%s %s\\n' "${0##*/}" "$*" >> "$INSTALL_SERVICE_LOG"
[ "${0##*/}" = multiwan-nft ] || exit 0
case "$1" in
    enabled) test -f "$INSTALL_STATE.enabled" ;;
    running) test -f "$INSTALL_STATE.running" ;;
    enable) : > "$INSTALL_STATE.enabled" ;;
    disable) rm -f "$INSTALL_STATE.enabled" ;;
    stop) rm -f "$INSTALL_STATE.running" ;;
    start|restart)
        if [ "$INSTALL_ACTIVATION_FAILURE" = 1 ] && ! grep -q '^# Old init revision.' "$0"; then exit 7; fi
        : > "$INSTALL_STATE.running" ;;
esac
'''
        payloads = {}
        for path, mode in {**main, **luci}.items():
            installed = root / path
            if not fresh:
                installed.parent.mkdir(parents=True, exist_ok=True)
                installed.write_bytes(service.replace(b"#!/bin/sh\n", b"#!/bin/sh\n# Old init revision.\n") if path == "etc/init.d/multiwan-nft" else ("old " + path + "\n").encode())
                installed.chmod(mode)
            relative = ("multiwan-nft/files/" + path if path in main else
                        "luci-app-multiwan-nft/htdocs/" + path.removeprefix("www/") if path.startswith("www/") else
                        "luci-app-multiwan-nft/root/" + path)
            data = service if path == "etc/init.d/multiwan-nft" else ("new " + path + "\n").encode()
            payloads[path] = data
            target = source / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        for name in ("rpcd", "uhttpd"):
            target = root / "etc/init.d" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(service)
            target.chmod(0o755)
        if legacy:
            for path, data in (("etc/config/mwan3", b"legacy config\n"), ("etc/mwan3.user", b"legacy hook\n")):
                (root / path).write_bytes(data)
        if symlink_init:
            path = root / "etc/init.d/multiwan-nft"
            target = work / "old-init-target"
            path.rename(target)
            path.symlink_to(target)
        for name, enabled in (("enabled", initial_enabled and not fresh), ("running", initial_running)):
            if enabled:
                (work / ("state." + name)).touch()
        before = snapshot(root)
        # Only absolute system paths are redirected; source URL paths stay intact.
        body = re.sub(r"(?<![A-Za-z0-9_./:-])/(etc|lib|usr|www|var|tmp)/", lambda match: str(root) + match[0], installer)
        if move_failure:
            # BusyBox can prefer built-in applets over PATH fixtures.
            body = body.replace("set -u\n", 'set -u\nmv() { "$INSTALL_MV" "$@"; }\n', 1)
        if restore_failure:
            body = body.replace("set -u\n", 'set -u\ncp() { "$INSTALL_CP" "$@"; }\n', 1)
        script = work / "install.sh"
        script.write_text(body)
        fetch = bin_dir / "uclient-fetch"
        fetch.write_text('''#!/usr/bin/python3
from pathlib import Path
import json, os, sys, time
out, url = sys.argv[2:4]
assert sys.argv[1] == '-O' and url.startswith('fixture://raw/')
relative = url.removeprefix('fixture://raw/')
with open(os.environ['INSTALL_FETCH_LOG'], 'a') as stream:
    stream.write(json.dumps(relative) + '\\n')
if os.environ.get('INSTALL_INTERRUPT') == '1':
    Path(os.environ['INSTALL_READY']).touch()
    time.sleep(0.3)
if relative == os.environ.get('INSTALL_FAILURE'):
    Path(out).write_bytes(b'partial download')
    raise SystemExit(1)
Path(out).write_bytes((Path(os.environ['INSTALL_SOURCE']) / relative).read_bytes())
''')
        fetch.chmod(0o755)
        apk = bin_dir / "apk"
        apk.write_text('#!/bin/sh\n[ "$INSTALL_PACKAGE_FAILURE" = 0 ] || exit 1\nexit 0\n')
        apk.chmod(0o755)
        move = bin_dir / "mv"
        move.write_text('''#!/bin/sh
if [ -n "$INSTALL_MOVE_FAILURE" ] && [ "$#" = 2 ] && [ "$2" = "$INSTALL_MOVE_FAILURE" ] && [ ! -e "$INSTALL_MOVE_FAILED" ]; then
    : > "$INSTALL_MOVE_FAILED"
    if [ "$INSTALL_APPLY_INTERRUPT" = 1 ]; then
        : > "$INSTALL_READY"
        sleep 0.3
        exec /bin/mv "$@"
    fi
    echo 'fixture move failure' >&2
    exit 1
fi
exec /bin/mv "$@"
''')
        move.chmod(0o755)
        copy = bin_dir / "cp"
        copy.write_text('''#!/bin/sh
if [ "$1" = -pP ] && [ "$3" = "$INSTALL_RESTORE_FAILURE" ]; then
    case "$2" in */rollback/*) echo 'fixture restore failure' >&2; exit 1 ;; esac
fi
exec /bin/cp "$@"
''')
        copy.chmod(0o755)
        environment = {**os.environ, "PATH": str(bin_dir) + ":" + os.environ["PATH"], "RAW_BASE": "fixture://raw",
                       "START_SERVICES": "1" if activation_failure else "0", "INSTALL_SERVICE_LOG": str(work / "service.log"),
                       "INSTALL_FETCH_LOG": str(work / "fetch.log"), "INSTALL_SOURCE": str(source),
                       "INSTALL_FAILURE": failure, "INSTALL_INTERRUPT": "1" if interrupt else "0",
                       "INSTALL_READY": str(work / "ready"), "INSTALL_PACKAGE_FAILURE": "1" if package_failure else "0",
                       "INSTALL_MOVE_FAILURE": str(root / move_failure) if move_failure else "", "INSTALL_MOVE_FAILED": str(work / "move-failed"),
                       "INSTALL_MV": str(move),
                       "INSTALL_CP": str(copy), "INSTALL_RESTORE_FAILURE": str(root / "etc/init.d/multiwan-nft") if restore_failure else "",
                       "INSTALL_APPLY_INTERRUPT": "1" if apply_interrupt else "0",
                       "INSTALL_STATE": str(work / "state"), "INSTALL_ACTIVATION_FAILURE": "1" if activation_failure else "0"}
        process = subprocess.Popen([*shell, str(script), component], env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, umask=0o022)
        if interrupt or apply_interrupt:
            deadline = time.monotonic() + 5
            while not (work / "ready").exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            assert (work / "ready").exists(), "Downloader never reached the controlled interruption"
            process.send_signal(interrupt_signal)
        stdout, stderr = process.communicate(timeout=15)
        after = snapshot(root)
        if failure or interrupt or package_failure or move_failure or activation_failure:
            assert process.returncode != 0, (shell, component, stdout, stderr)
            if failure:
                assert ("failed to download " + failure).encode() in stderr, (stdout, stderr)
            if move_failure:
                assert (work / "move-failed").exists(), (stdout, stderr)
                if not apply_interrupt:
                    assert b"fixture move failure" in stderr, (stdout, stderr)
            problem = "Failed application changed installed files/configuration" if move_failure or activation_failure else "Failed preparation changed installed files/configuration"
            differences = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
            if restore_failure:
                assert b"Rollback incomplete; backups retained at" in stderr and b"fixture restore failure" in stderr
                assert differences == ["etc/init.d/multiwan-nft"], differences
                retained = list((root / "tmp").glob("multiwan-nft-install.*"))
                assert len(retained) == 1 and stat.S_IMODE(retained[0].stat().st_mode) == 0o700
                assert (retained[0] / ("rollback" + str(root / "etc/init.d/multiwan-nft"))).read_bytes() == before["etc/init.d/multiwan-nft"][0]
            else:
                assert after == before, (shell, component, problem, differences)
            if not move_failure and not activation_failure:
                assert not (work / "service.log").exists(), "Failed preparation executed a service action"
            assert (work / "state.running").exists() == initial_running
            assert (work / "state.enabled").exists() == (initial_enabled and not fresh)
            if symlink_init:
                assert (work / "old-init-target").read_bytes() == service.replace(b"#!/bin/sh\n", b"#!/bin/sh\n# Old init revision.\n")
        else:
            assert process.returncode == 0, (shell, component, stdout, stderr)
            selected = {**main, **luci} if component == "all" else main if component == "main" else luci
            for path, mode in selected.items():
                if fresh:
                    parent = (root / path).parent
                    while parent != root:
                        assert stat.S_IMODE(parent.stat().st_mode) == 0o755, (parent.relative_to(root), "Private staging umask leaked into live directories")
                        parent = parent.parent
                if path in ("etc/config/multiwan-nft", "etc/multiwan-nft.user") and path in before:
                    expected = b"legacy config\n" if legacy and path.startswith("etc/config/") else b"legacy hook\n" if legacy else before[path][0]
                    assert after[path][0] == expected
                else:
                    assert after[path] == (payloads[path], mode), (path, after[path])
            if component == "luci":
                assert all(after[path] == before[path] for path in main)
            if legacy:
                assert not (root / "etc/config/mwan3").exists() and not (root / "etc/mwan3.user").exists()
                for path in ("etc/config/mwan3", "etc/mwan3.user", "etc/config/multiwan-nft", "etc/multiwan-nft.user"):
                    assert after[path + ".pre-multiwan-rename"] == before[path], path
            again = subprocess.run([*shell, str(script), component], env=environment, capture_output=True, timeout=15, umask=0o022)
            expected_retry = dict(after)
            if fresh and component != "luci":
                expected_retry["var/run/multiwan-nft-upgrade-pending"] = (b"", 0o600)
            assert again.returncode == 0 and snapshot(root) == expected_retry, "Successful retry changed installed payload/configuration"
        assert not (root / "tmp/multiwan-nft-raw-install.lock").exists()
        if not restore_failure:
            assert not list((root / "tmp").iterdir()), "Installer leaked its lock or staging directory"


for shell in (["busybox", "ash"], ["dash"]):
    run_case(shell, "main", legacy=True, move_failure="etc/hotplug.d/iface/16-multiwan-nft-user")
    run_case(shell, "main", legacy=True, move_failure="etc/multiwan-nft.user")
    run_case(shell, "all", legacy=True, move_failure="www/luci-static/resources/view/multiwan-nft/status/troubleshooting.js", initial_running=True, initial_enabled=False)
    run_case(shell, "luci", move_failure="www/luci-static/resources/view/multiwan-nft/status/troubleshooting.js", initial_running=True)
    run_case(shell, "main", fresh=True, move_failure="usr/sbin/multiwan-nft-rtmon")
    run_case(shell, "all", fresh=True, move_failure="www/luci-static/resources/view/multiwan-nft/status/troubleshooting.js")
    run_case(shell, "main", move_failure="etc/hotplug.d/iface/16-multiwan-nft-user", symlink_init=True, initial_running=True)
    run_case(shell, "main", move_failure="etc/hotplug.d/iface/16-multiwan-nft-user", restore_failure=True, initial_running=True)
    run_case(shell, "main", move_failure="etc/hotplug.d/iface/16-multiwan-nft-user", apply_interrupt=True)
    run_case(shell, "main", move_failure="etc/hotplug.d/iface/16-multiwan-nft-user", apply_interrupt=True, interrupt_signal=signal.SIGHUP)
    for running in (False, True):
        run_case(shell, "main", activation_failure=True, initial_running=running, initial_enabled=False)
    for component, failure in (("main", "multiwan-nft/files/etc/hotplug.d/iface/15-multiwan-nft"),
                               ("all", "luci-app-multiwan-nft/htdocs/luci-static/resources/view/multiwan-nft/status/troubleshooting.js"),
                               ("luci", "luci-app-multiwan-nft/root/usr/share/rpcd/acl.d/luci-app-multiwan-nft.json")):
        run_case(shell, component, failure, legacy=component != "luci")
    for component in ("main", "all", "luci"):
        run_case(shell, component, legacy=component != "luci")
    for component in ("main", "all"):
        run_case(shell, component, fresh=True)
    run_case(shell, "main", interrupt=True)
    run_case(shell, "main", package_failure=True)
print("NFT raw-installer tests passed: both shells, all components, failed downloads/dependencies/signals, preserved migration/configuration and repeat installs.")
