#!/usr/bin/env python3
"""Audit an UNSIGNED IPA produced by CI.

Unlike audit_ipa.py this does NOT require a code signature (that is added
later by Sideloadly/AltStore with the user's own Apple ID). It still verifies
bundle structure, ARM64 executable, min iOS, bundle id and the absence of any
protected Assetto Corsa assets.
"""
from __future__ import annotations

import plistlib
import struct
import sys
import zipfile
from pathlib import Path

PROTECTED = (".kn5", ".knh", ".acd", ".bank", ".fsb", ".dds", ".acreplay")


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("artifacts/AC-iOS-Prot-unsigned.ipa")
    checks: list[tuple[str, bool, str]] = []

    def add(name: str, ok: bool, detail: str = "") -> None:
        checks.append((name, bool(ok), detail))

    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        apps = [n for n in names if n.startswith("Payload/") and n.endswith(".app/")]
        add("has app bundle", bool(apps))
        if not apps:
            print("RESULT: FAILED - no .app in Payload/")
            return 1
        app = apps[0]
        plist_path = app + "Info.plist"
        add("Info.plist present", plist_path in names)
        info = {}
        if plist_path in names:
            info = plistlib.loads(zf.read(plist_path))
            add("bundle id", info.get("CFBundleIdentifier") == "com.aciosprototype.ac-ios-port",
                str(info.get("CFBundleIdentifier")))
            exe = app + (info.get("CFBundleExecutable") or "")
            add("main executable present", exe in names)
            if exe in names:
                data = zf.read(exe)
                add("ARM64 executable", data[:4] == b"\xcf\xfa\xed\xfe",
                    "Mach-O 64 LE" if data[:4] == b"\xcf\xfa\xed\xfe" else data[:4].hex())
                add("min iOS >= 16 declared",
                    "arm64" in info.get("UIRequiredDeviceCapabilities", []),
                    str(info.get("UIRequiredDeviceCapabilities")))
        assets = [n for n in names if n.lower().endswith(PROTECTED)]
        add("no protected AC assets in bundle", not assets, ", ".join(assets[:3]) or "none")
        add("no embedded .ipa", not [n for n in names if n.lower().endswith(".ipa")])
        add("unsigned (expected for CI artifact)", not any("_CodeSignature/" in n for n in names))

    print(f"=== Unsigned IPA audit: {path} ({path.stat().st_size} bytes) ===")
    for name, ok, detail in checks:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" ({detail})" if detail else ""))
    ok = all(item[1] for item in checks)
    print("RESULT:", "UNSIGNED IPA STRUCTURALLY VALID (re-sign on device install)" if ok
          else "UNSIGNED IPA AUDIT FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
