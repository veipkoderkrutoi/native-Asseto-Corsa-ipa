#!/usr/bin/env python3
"""Static preflight of the iOS XcodeGen project (no Apple SDK required).

This does NOT prove the project builds. It checks that every path, framework,
symbol and setting the Xcode build depends on is present and consistent.
"""
from __future__ import annotations

import hashlib
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, bool(ok), detail))


def text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


project = text("ios/project.yml")
header = text("ios/ios_bridge.h")
pal_header = text("core/ac_pal_bridge.h")
app = text("ios/GameViewController.m")
delegate = text("ios/AppDelegate.m")
export = text("ios/exportOptions.plist")
plist = text("ios/Info.plist")

# 1. Every referenced path must exist.
for rel in [
    "ios/main.m", "ios/AppDelegate.m", "ios/GameViewController.m", "ios/ios_bridge.m",
    "ios/AppDelegate.h", "ios/GameViewController.h", "ios/ios_bridge.h",
    "ios/Info.plist", "ios/ac-ios.entitlements", "ios/Assets.xcassets",
    "ios/exportOptions.plist", "core/ac_pal_bridge.c", "core/ac_pal_bridge.h",
    "rust/target/aarch64-apple-ios/release/libac_ios_runtime.a",
]:
    p = ROOT / rel
    check(f"path exists: {rel}", p.exists() and (p.is_dir() or p.stat().st_size > 0))

# 2. Static library must be linked as a dependency, not a source file.
check("Rust staticlib linked as framework dependency",
      "framework: ../rust/target/aarch64-apple-ios/release/libac_ios_runtime.a" in project,
      "XcodeGen has no build phase for .a entries in sources")
sources_part = project.split("dependencies:")[0] if "dependencies:" in project else project
check("no .a in sources",
      re.search(r"^\s*- path:.*\.a\s*$", sources_part, re.M) is None)

# 3. Frameworks explicitly used by Objective-C sources.
for fw in ["Metal", "MetalKit", "GameController", "QuartzCore", "UniformTypeIdentifiers"]:
    check(f"SDK framework: {fw}", f"sdk: {fw}.framework" in project)
check("ObjC linker flag -ObjC", "-ObjC" in project)

# 4. Deployment target consistency with the hand-built ARM64 object.
check("project deployment target 16.0", 'IPHONEOS_DEPLOYMENT_TARGET: "16.0"' in project)
obj = ROOT / "artifacts/ac_pal_bridge.arm64.o"
macho = obj.read_bytes()
ncmds = struct.unpack_from("<I", macho, 16)[0]
pos = 32
minos = None
for _ in range(ncmds):
    cmd, sz = struct.unpack_from("<II", macho, pos)
    if cmd == 0x25 and sz >= 16:
        v = struct.unpack_from("<I", macho, pos + 8)[0]
        minos = f"{v >> 16}.{(v >> 8) & 0xFF}.{v & 0xFF}"
    pos += sz
check("PAL ARM64 object min iOS == 16.0", minos in {"16.0", "16.0.0"},
      f"object minos={minos}")

# 5. Signing / bundle id consistency.
bundle = "com.aciosprototype.ac-ios-port"
check("bundle id in project", bundle in project)
check("bundle id in export options", bundle in export)
check("explicit signing identity setting", "CODE_SIGN_IDENTITY: $(AC_SIGNING_IDENTITY)" in project)
check("no fake credentials", "REPLACE_WITH_YOUR_TEAM_ID" in export and "REPLACE_WITH_YOUR" not in project)

# 6. Required C ABI symbols are declared and used.
symbols = [
    "ac_ios_boot", "ac_ios_install_core_vtable", "ac_ios_set_auto_shifter",
    "ac_ios_metal_init", "ac_ios_metal_resize", "ac_ios_metal_layer",
    "ac_ios_render_init", "ac_ios_render_frame", "ac_ios_render_resize",
    "ac_ios_render_destroy", "ac_pal_bridge_set_controls", "ac_pal_bridge_session",
]
for sym in symbols:
    where = header if sym.startswith("ac_ios_") else pal_header
    check(f"C symbol declared: {sym}", sym in where)

# 7. Runtime wiring in Objective-C.
check("document picker used", "UIDocumentPickerViewController" in delegate)
check("security-scoped bookmark used", "NSURLBookmarkCreationWithSecurityScope" in delegate)
check("touch cancellation handled", "touchesCancelled" in app)
check("GameController connected/disconnected observed",
      "GCControllerDidConnectNotification" in app and "GCControllerDidDisconnectNotification" in app)
check("app lifecycle observed",
      "UIApplicationWillResignActiveNotification" in app and "UIApplicationDidBecomeActiveNotification" in app)
check("no readback in frame loop", "read_pixels" not in app and "PNG" not in app)

# 8. Staticlib contains the required symbols and no protected game assets.
lib = ROOT / "rust/target/aarch64-apple-ios/release/libac_ios_runtime.a"
blob = lib.read_bytes()
for sym in ["ac_ios_boot", "ac_ios_render_init", "ac_ios_render_frame",
            "ac_ios_metal_init", "ac_ios_set_auto_shifter"]:
    check(f"staticlib symbol: {sym}", (sym + "\0").encode() in blob)

protected = [p for p in IOS.rglob("*") if p.is_file() and
             p.suffix.lower() in {".kn5", ".knh", ".acd", ".bank", ".fsb", ".dds"}]
check("no protected AC assets in ios/", not protected)

print("=== iOS project preflight ===")
for name, ok, detail in results:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" ({detail})" if detail else ""))
count = sum(1 for _, ok, _ in results if ok)
print(f"\n{count}/{len(results)} checks passed")
bad = [n for n, ok, _ in results if not ok]
print("RESULT:", "BUILD PREFLIGHT PASSED (Xcode build still required)" if not bad
      else f"BUILD PREFLIGHT FAILED: {', '.join(bad)}")
raise SystemExit(0 if not bad else 1)
