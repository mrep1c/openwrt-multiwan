#!/usr/bin/env python3
"""Fetch the official SDK matching a declared package architecture and verify it."""
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request

release, target, subtarget, architecture, destination = sys.argv[1:]
base = f"https://downloads.openwrt.org/releases/{release}/targets/{target}/{subtarget}/"
with urllib.request.urlopen(base + "profiles.json", timeout=60) as response:
    profile = json.load(response)
if profile.get("arch_packages") != architecture:
    raise SystemExit(f"SDK architecture mismatch: {profile.get('arch_packages')} != {architecture}")
with urllib.request.urlopen(base + "sha256sums", timeout=60) as response:
    checksums = response.read().decode()
pattern = re.compile(r"^([0-9a-f]{64})\s+\*?(openwrt-sdk-" + re.escape(release + "-" + target + "-" + subtarget) + r"_\S+\.Linux-x86_64\.tar\.(?:zst|xz))$", re.M)
matches = pattern.findall(checksums)
if len(matches) != 1:
    raise SystemExit(f"Expected one official SDK, found {len(matches)}")
expected, filename = matches[0]
output = Path(destination)
output.parent.mkdir(parents=True, exist_ok=True)
if output.exists():
    cached = hashlib.sha256()
    with output.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            cached.update(chunk)
    if cached.hexdigest() == expected:
        print(f"Verified cached {filename}: {expected}", flush=True)
        raise SystemExit(0)
digest = hashlib.sha256()
downloaded = 0
with urllib.request.urlopen(base + filename, timeout=120) as response, output.open("wb") as stream:
    for chunk in iter(lambda: response.read(1024 * 1024), b""):
        stream.write(chunk)
        digest.update(chunk)
        downloaded += len(chunk)
        if downloaded % (64 * 1024 * 1024) == 0:
            print(f"Downloading {filename}: {downloaded // (1024 * 1024)} MiB", flush=True)
if digest.hexdigest() != expected:
    output.unlink()
    raise SystemExit("SDK SHA256 mismatch")
print(f"Verified {filename}: {expected}")
