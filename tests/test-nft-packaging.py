#!/usr/bin/env python3
"""Verify SDK identity/hash checks and native package architecture declarations."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
targets = json.loads((repo / "scripts/openwrt-apk-targets.json").read_text())
assert {item["architecture"] for item in targets} == {"aarch64_generic", "arm_cortex-a7_neon-vfpv4", "mipsel_24kc"}
assert len({(item["target"], item["subtarget"]) for item in targets}) == len(targets)
script = repo / "scripts/download-openwrt-sdk.py"
archive = b"verified SDK fixture"

def execute(output, wrong_arch=False, wrong_hash=False):
    digest = "0" * 64 if wrong_hash else hashlib.sha256(archive).hexdigest()
    responses = [json.dumps({"arch_packages": "wrong" if wrong_arch else "aarch64_generic"}).encode(),
                 f"{digest}  openwrt-sdk-25.12.6-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst\n".encode(), archive]
    def fetch(url, timeout):
        assert url.startswith("https://downloads.openwrt.org/releases/25.12.6/targets/rockchip/armv8/")
        assert timeout in (60, 120)
        return io.BytesIO(responses.pop(0))
    arguments = [str(script), "25.12.6", "rockchip", "armv8", "aarch64_generic", str(output)]
    with patch.object(sys, "argv", arguments), patch("urllib.request.urlopen", fetch), redirect_stdout(io.StringIO()):
        runpy.run_path(str(script), run_name="__main__")

with tempfile.TemporaryDirectory() as temporary:
    output = Path(temporary) / "sdk.zst"
    execute(output)
    assert output.read_bytes() == archive
    # A cached SDK still passes current official metadata and hash validation.
    try:
        execute(output)
        raise AssertionError("Cached download did not exit after verification")
    except SystemExit as status:
        assert status.code == 0
    output.unlink()
    for options in ({"wrong_arch": True}, {"wrong_hash": True}):
        try:
            execute(output, **options)
            raise AssertionError("Invalid SDK accepted")
        except SystemExit:
            assert not output.exists(), "Rejected SDK left an installable archive"

with tempfile.TemporaryDirectory() as temporary:
    sdk = Path(temporary)
    (sdk / "rules.mk").touch()
    (sdk / "feeds.conf.default").touch()
    (sdk / "staging_dir/host").mkdir(parents=True)
    settings = sdk / "Config-build.in"
    original_settings = ('config TARGET_BOARD\n\tstring\n\tdefault "rockchip"\n\n'
                         'config PACKAGE_kmod-unused\n\ttristate\n\tdefault m\n\n'
                         'config PACKAGE_kmod-explicit\n\ttristate\n\tdefault m\n\n'
                         'config PACKAGE_kmod-base\n\ttristate\n\tdefault m\n\n'
                         'config PACKAGE_kmod-leaf\n\ttristate\n\tdefault m\n\n'
                         'config PACKAGE_kmod-required\n\tbool\n\tdefault y\n\n'
                         'config SIGNED_PACKAGES\n\tbool\n\tdefault y\n')
    settings.write_text(original_settings)
    config = sdk / ".config"
    retained = 'CONFIG_TARGET_BOARD="rockchip"\nCONFIG_SIGNED_PACKAGES=y\nCONFIG_TARGET_CFLAGS="-Os -pipe"\n'
    config.write_text(retained + "CONFIG_ALL=y\nCONFIG_ALL_KMODS=y\n# CONFIG_ALL_NONSHARED is not set\n"
                      "CONFIG_PACKAGE_unrelated=m\n# CONFIG_PACKAGE_old is not set\n")
    configure = [sys.executable, str(repo / "scripts/configure-openwrt-sdk.py"), str(sdk)]
    subprocess.run([*configure, "multiwan-nft", "multiwan-nft-sockopt", "kmod-explicit"], check=True)
    expected = retained + "# CONFIG_ALL is not set\n# CONFIG_ALL_NONSHARED is not set\n# CONFIG_ALL_KMODS is not set\n" + \
        "CONFIG_PACKAGE_multiwan-nft=m\nCONFIG_PACKAGE_multiwan-nft-sockopt=m\nCONFIG_PACKAGE_kmod-explicit=m\n"
    assert config.read_text() == expected, "Package selection changed SDK target/signing settings"
    expected_settings = original_settings
    for name in ("unused", "base", "leaf"):
        expected_settings = expected_settings.replace(f'config PACKAGE_kmod-{name}\n\ttristate\n\tdefault m\n', f'config PACKAGE_kmod-{name}\n\ttristate\n\tdefault m if ALL_KMODS\n')
    assert settings.read_text() == expected_settings, "SDK target/signing or built-in defaults changed"
    subprocess.run([*configure, "multiwan-nft", "multiwan-nft-sockopt", "kmod-explicit"], check=True)
    assert config.read_text() == expected and settings.read_text() == expected_settings, "Package selection is not idempotent"
    (sdk / "tmp").mkdir()
    (sdk / "tmp/.packageinfo").write_text('Package: multiwan-nft\nDepends: +IPV6:kmod-leaf\n\n'
                                        'Package: kmod-leaf\nDepends: +kmod-base\n\n'
                                        'Package: kmod-base\nDepends: +kmod-leaf\n')
    expected += "CONFIG_PACKAGE_kmod-base=m\nCONFIG_PACKAGE_kmod-leaf=m\n"
    for name in ("base", "leaf"):
        expected_settings = expected_settings.replace(f'config PACKAGE_kmod-{name}\n\ttristate\n\tdefault m if ALL_KMODS\n', f'config PACKAGE_kmod-{name}\n\ttristate\n\tdefault m\n')
    for _ in range(2):
        subprocess.run([*configure, "multiwan-nft", "multiwan-nft-sockopt", "kmod-explicit"], check=True)
        assert config.read_text() == expected and settings.read_text() == expected_settings, "Transitive module dependencies were lost or unrelated defaults changed"
    for invalid in ("../escape", "bad=name", "two packages", ""):
        result = subprocess.run([*configure, invalid], capture_output=True, text=True)
        assert result.returncode != 0 and config.read_text() == expected and settings.read_text() == expected_settings
    (sdk / "rules.mk").unlink()
    result = subprocess.run([*configure, "multiwan-nft"], capture_output=True, text=True)
    assert result.returncode != 0 and config.read_text() == expected and settings.read_text() == expected_settings

makefile = (repo / "multiwan-nft/Makefile").read_text()
backend = makefile.split("define Package/multiwan-nft\n", 1)[1].split("endef", 1)[0]
helper = makefile.split("define Package/multiwan-nft-sockopt\n", 1)[1].split("endef", 1)[0]
assert "PKGARCH:=all" in backend and "PKGARCH:=all" not in helper
assert "+multiwan-nft-sockopt" in backend and "+nftables-json" in backend
assert "+kmod-nft-fib" in backend
assert "+libgcc" in helper
assert "$(TARGET_CC)" in makefile and "-fPIC -shared" in makefile
probe = (repo / "multiwan-nft-nping/Makefile").read_text()
assert "PKGARCH:=all" not in probe and "PROVIDES:=nping" in probe
assert "REPLACES:=nping nping-ssl" in probe and "CONFLICTS:=nping nping-ssl" in probe
assert "PKG_HASH:=0c12660eddbf7eabeff6996cb0c044a4eadf2bb0c6fbcb340d6cf72b1caee402" in probe
assert "build-nping" in probe and "--without-openssl" in probe
with tempfile.TemporaryDirectory() as temporary:
    sdk = Path(temporary)
    (sdk / "rules.mk").touch()
    (sdk / "feeds/luci").mkdir(parents=True)
    # The real LuCI framework invokes this package-specific preparation hook.
    (sdk / "feeds/luci/luci.mk").write_text("check:\n\t$(Build/Prepare/luci-app-multiwan-nft)\n")
    helper = sdk / "build/root/usr/libexec/luci-multiwan-nft"
    helper.parent.mkdir(parents=True)
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o644)
    subprocess.run(["make", "--no-print-directory", "-f", str(repo / "luci-app-multiwan-nft/Makefile"),
                    "TOPDIR=" + str(sdk), "PKG_BUILD_DIR=" + str(sdk / "build"), "check"],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert helper.stat().st_mode & 0o777 == 0o755, "LuCI diagnostics helper must be executable after a normal Git checkout"
print("NFT packaging checks passed: SDK identity/hash rejection, scoped selection, target/signing preservation, native dependencies and helper modes.")
