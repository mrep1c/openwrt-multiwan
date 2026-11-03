#!/usr/bin/env python3
"""Select feed packages without changing SDK target or signing settings."""
from pathlib import Path
import re
import sys

if len(sys.argv) < 3:
    raise SystemExit("Usage: configure-openwrt-sdk.py SDK_DIR PACKAGE...")
sdk = Path(sys.argv[1])
packages = sys.argv[2:]
if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+_.-]*", name) for name in packages):
    raise SystemExit("Invalid package name")
if not ((sdk / "rules.mk").is_file() and (sdk / "feeds.conf.default").is_file()
        and (sdk / "Config-build.in").is_file()
        and (sdk / "staging_dir/host").is_dir()):
    raise SystemExit("Not an extracted OpenWrt SDK")
metadata = sdk / "tmp/.packageinfo"
if metadata.is_file():
    dependencies = {}
    for name, body in re.findall(r"(?ms)^Package: ([A-Za-z0-9+_.-]+)\n(.*?)(?=^Package: |\Z)", metadata.read_text()):
        field = re.search(r"(?m)^Depends: (.*)$", body)
        dependencies[name] = [word.rsplit(":", 1)[-1].lstrip("+") for word in field[1].split() if word.startswith("+")] if field else []
    required = set(packages)
    pending = list(packages)
    while pending:
        for name in dependencies.get(pending.pop(), []):
            if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+_.-]*", name) and name not in required:
                required.add(name)
                pending.append(name)
    # Hidden SDK module symbols lack the transitive selects in a full buildroot.
    packages += sorted(name for name in required if name.startswith("kmod-") and name not in packages)
settings = sdk / "Config-build.in"
# SDK module defaults are hidden symbols, so .config alone cannot disable them.
settings.write_text(re.sub(r"(?m)^(config PACKAGE_(kmod-[A-Za-z0-9+_.-]+)\n\ttristate\n\tdefault m)(?: if ALL_KMODS)?$",
                           lambda match: match[1] if match[2] in packages else match[1] + " if ALL_KMODS", settings.read_text()))
config = sdk / ".config"
lines = config.read_text().splitlines() if config.exists() else []
# SDK defaults otherwise select unrelated kernel modules through CONFIG_ALL.
lines = [line for line in lines if not re.match(
    r"(?:# )?CONFIG_(?:ALL(?:_NONSHARED|_KMODS)?(?:=| is not set$)|PACKAGE_)", line)]
lines += [f"# CONFIG_{name} is not set" for name in ("ALL", "ALL_NONSHARED", "ALL_KMODS")]
lines += [f"CONFIG_PACKAGE_{name}=m" for name in packages]
config.write_text("\n".join(lines) + "\n")
