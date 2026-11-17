#!/usr/bin/env python3
"""Structural audit of an IPA. No Apple SDK needed; pure Python stdlib.

Usage: python scripts/audit_ipa.py path/to/app.ipa

This does NOT prove the app launches. It only verifies on-disk structure,
ARM64 Mach-O slice, bundle metadata, a code signature blob and the absence of
protected Assetto Corsa assets in the package.
"""
from __future__ import annotations

import plistlib
import struct
import sys
import zipfile
from pathlib import Path

PROTECTED_SUFFIXES = (".kn5", ".knh", ".acd", ".bank", ".fsb", ".dds", ".acreplay")


def macho_slices(data: bytes) -> list[dict]:
    """Return (cputype, cpusubtype, offset, size) for Mach-O slices (fat or thin)."""
    magic = data[:4]
    slices = []
    if magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):  # FAT_MAGIC
        nfat = struct.unpack_from(">I", data, 4)[0]
        for i in range(nfat):
            off = 8 + i * 20
            cputype, cpusub, offset, size, _ = struct.unpack_from(">iiIII", data, off)
            slices.append({"cputype": hex(cputype & 0xFFFFFFFF), "cpusubtype": cpusub,
                           "offset": offset, "size": size})
    elif magic == b"\xcf\xfa\xed\xfe":  # MH_MAGIC_64, little endian
        cputype, cpusub = struct.unpack_from("<ii", data, 4)
        slices.append({"cputype": hex(cputype & 0xFFFFFFFF), "cpusubtype": cpusub,
                       "offset": 0, "size": len(data)})
    return slices


def audit(path: Path) -> dict:
    checks: dict[str, bool] = {}
    info: dict = {}

    if not path.is_file():
        raise SystemExit(f"IPA not found: {path}")
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        apps = [n for n in names if n.startswith("Payload/") and n.endswith(".app/")]
        checks["has_app_bundle"] = bool(apps)
        if not apps:
            return {"checks": checks, "info": info, "ok": False}
        app = apps[0]
        info["app_bundle"] = app

        plist_path = app + "Info.plist"
        checks["has_info_plist"] = plist_path in names
        if checks["has_info_plist"]:
            plist = plistlib.loads(zf.read(plist_path))
            info["bundle_id"] = plist.get("CFBundleIdentifier")
            info["min_os"] = plist.get("MinimumOSVersion")
            info["executable"] = plist.get("CFBundleExecutable")
            checks["has_bundle_id"] = bool(info["bundle_id"])
            checks["declares_arm64"] = "arm64" in plist.get("UIRequiredDeviceCapabilities", [])

            exe = app + (info["executable"] or "")
            checks["has_main_executable"] = exe in names
            if checks["has_main_executable"]:
                slices = macho_slices(zf.read(exe))
                info["mach_o_slices"] = slices
                checks["arm64_slice"] = any(s["cputype"] == "0x100000c" for s in slices)

            signature = [n for n in names if n.endswith("CodeResources")] + \
                        [n for n in names if "_CodeSignature/CodeSignature" in n]
            checks["code_signature_present"] = bool(signature)
            info["signature_files"] = signature[:5]

        bundled_assets = [n for n in names if n.lower().endswith(PROTECTED_SUFFIXES)]
        info["protected_assets_found"] = bundled_assets[:10]
        checks["no_protected_game_assets"] = not bundled_assets
        info["file_count"] = len(names)

    return {"checks": checks, "info": info, "ok": all(checks.values())}


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("artifacts/AC-iOS-Prot.ipa")
    result = audit(path)
    for key, value in result["info"].items():
        print(f"{key}: {value}")
    print("--- checks ---")
    for key, value in result["checks"].items():
        print(f"[{'PASS' if value else 'FAIL'}] {key}")
    print("RESULT:", "STRUCTURALLY VALID IPA (launch not proven)" if result["ok"]
          else "IPA AUDIT FAILED")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
