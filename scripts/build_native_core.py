#!/usr/bin/env python3
"""Reproduce the host tests and the genuine ARM64 iOS object build.

Works on Windows/macOS/Linux with `pip install ziglang==0.17.1`.
Usage: python scripts/build_native_core.py
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
ARTIFACTS = ROOT / "artifacts"
LOGS = ROOT / "logs"
ZIG = [sys.executable, "-m", "ziglang", "cc"]


def run(command: list[str], log: list[str]) -> int:
    line = "$ " + " ".join(str(c) for c in command)
    log.append(line)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    log.append(result.stdout.rstrip())
    if result.stderr.strip():
        log.append("[stderr] " + result.stderr.rstrip())
    log.append(f"[exit {result.returncode}]")
    print(line)
    print(result.stdout.rstrip())
    if result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)
    return result.returncode


def main() -> int:
    for directory in (BUILD, ARTIFACTS, LOGS):
        directory.mkdir(parents=True, exist_ok=True)
    log: list[str] = [f"# Native core build — {datetime.now(timezone.utc).isoformat()}", ""]
    log.append(f"python: {sys.version}")
    log.append(f"zig version: {subprocess.run([sys.executable, '-m', 'ziglang', 'version'], capture_output=True, text=True).stdout.strip()}")
    log.append("")

    host_exe = BUILD / ("ac_pal_bridge_test.exe" if sys.platform == "win32" else "ac_pal_bridge_test")
    if run(ZIG + ["-std=c11", "-O2", "-Wall", "-Wextra",
                  "core/ac_pal_bridge.c", "core/ac_pal_bridge_test.c",
                  "-o", str(host_exe.relative_to(ROOT))], log) != 0:
        return 1
    if run([str(host_exe)], log) != 0:
        return 1

    obj = ARTIFACTS / "ac_pal_bridge.arm64.o"
    if run(ZIG + ["-target", "aarch64-ios", "-O2", "-std=c11", "-Wall", "-Wextra",
                  "-c", "core/ac_pal_bridge.c", "-o", str(obj.relative_to(ROOT))], log) != 0:
        return 1

    # Zig 0.17 emits a malformed 16-byte LC_BUILD_VERSION; replace it in place
    # with a valid LC_VERSION_MIN_IPHONEOS 16.0 so it matches ios/project.yml.
    fix = subprocess.run([sys.executable, str(ROOT / "scripts/fix_macho_minos.py"), str(obj)],
                         cwd=ROOT, capture_output=True, text=True)
    log.append(fix.stdout.rstrip())
    print(fix.stdout.rstrip())
    if fix.returncode != 0:
        return 1

    verify = subprocess.run([sys.executable, str(ROOT / "scripts/verify_macho.py"), str(obj)],
                            cwd=ROOT, capture_output=True, text=True)
    log.append(verify.stdout.rstrip())
    print(verify.stdout.rstrip())
    if verify.returncode != 0:
        return 1

    manifest = {
        "artifact": str(obj.relative_to(ROOT)).replace("\\", "/"),
        "size": obj.stat().st_size,
        "sha256": hashlib.sha256(obj.read_bytes()).hexdigest(),
        "target": "aarch64-apple-ios (Mach-O 64, cputype 0x0100000c)",
        "toolchain": "zig 0.17.1 (pip ziglang) cross-compiler",
        "build_command": "python -m ziglang cc -target aarch64-ios -O2 -std=c11 -Wall -Wextra "
                         "-c core/ac_pal_bridge.c -o artifacts/ac_pal_bridge.arm64.o",
        "note": "Object file only. Linking into an IPA requires Xcode/iPhoneOS SDK on macOS.",
    }
    (ARTIFACTS / "NATIVE_OBJECT_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (LOGS / "01_native_core_build.log").write_text("\n".join(log) + "\n")
    print(f"Wrote {manifest['artifact']} ({manifest['size']} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
