#!/usr/bin/env python3
"""Overall delivery verification. Exits 0 only if every check passes.

Run from anywhere:  python scripts/verify_delivery.py
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from verify_macho import verify as verify_macho  # noqa: E402

REQUIRED = [
    "README.md",
    "docs/ARCHITECTURE.md", "docs/FEASIBILITY.md", "docs/BUILD_IOS.md",
    "docs/TEST_REPORT.md", "docs/BLOCKERS.md", "docs/FEATURES.md",
    "docs/RESEARCH_SOURCES.md",
    "core/ac_pal_bridge.h", "core/ac_pal_bridge.c", "core/ac_pal_bridge_test.c",
    "rust/Cargo.toml", "rust/ac-ios-pal/src/lib.rs", "rust/ac-ios-runtime/src/lib.rs",
    "ios/main.m", "ios/AppDelegate.m", "ios/GameViewController.m",
    "ios/ios_bridge.m", "ios/Info.plist", "ios/project.yml",
    "scripts/build_native_core.py", "scripts/verify_macho.py",
    "scripts/make_patches.py", "scripts/audit_ipa.py", "scripts/build_ios.sh",
    "patches/0001-ios-native-target.patch",
    "patches/patch_manifest.json",
    "artifacts/ac_pal_bridge.arm64.o", "artifacts/NATIVE_OBJECT_MANIFEST.json",
    "artifacts/README.md",
    "logs/00_environment.log", "logs/01_native_core_build.log",
    "logs/02_rust_tests.log", "logs/03_patches.log",
]

PROTECTED_SUFFIXES = (".kn5", ".knh", ".acd", ".bank", ".fsb", ".dds", ".acreplay")


def main() -> int:
    results: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, ok, detail))

    for rel in REQUIRED:
        p = ROOT / rel
        check(f"exists: {rel}", p.is_file() and p.stat().st_size > 0,
              f"{p.stat().st_size} bytes" if p.is_file() else "missing")

    # ARM64 object structure and hash.
    obj = ROOT / "artifacts/ac_pal_bridge.arm64.o"
    if obj.is_file():
        macho = verify_macho(obj)
        check("ARM64 Mach-O object valid", macho["ok"], macho["magic"])
        manifest = json.loads((ROOT / "artifacts/NATIVE_OBJECT_MANIFEST.json").read_text())
        digest = hashlib.sha256(obj.read_bytes()).hexdigest()
        check("ARM64 object SHA-256 matches manifest", digest == manifest["sha256"], digest[:16])
    else:
        check("ARM64 Mach-O object valid", False, "missing")

    # Patches verified by make_patches.py.
    patch_manifest = json.loads((ROOT / "patches/patch_manifest.json").read_text())
    check("all upstream patches verified", all(f["verified"] for f in patch_manifest["files"]),
          f"{len(patch_manifest['files'])} files")

    # No fake IPA and no protected assets anywhere in the deliverable.
    ipas = [p for p in ROOT.rglob("*.ipa") if "third_party" not in p.parts]
    check("no fake IPA shipped", not ipas, ", ".join(str(p) for p in ipas) or "none")
    protected = [p for p in ROOT.rglob("*")
                 if p.is_file() and "third_party" not in p.parts
                 and p.suffix.lower() in PROTECTED_SUFFIXES]
    check("no protected game assets shipped", not protected,
          ", ".join(str(p) for p in protected[:3]) or "none")

    ok = all(item[1] for item in results)
    print("=== Delivery verification ===")
    for name, passed, detail in results:
        print(f"[{'PASS' if passed else 'FAIL'}] {name}" + (f"  ({detail})" if detail else ""))
    print(f"\n{sum(1 for _, p, _ in results if p)}/{len(results)} checks passed")
    print("RESULT:", "DELIVERY VERIFIED (no IPA - see artifacts/README.md)" if ok
          else "DELIVERY INCOMPLETE")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
