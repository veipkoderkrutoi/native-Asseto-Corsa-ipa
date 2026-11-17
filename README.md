# Assetto Corsa → native iOS (ARM64): research & prototype

**Date:** 2026-11-17
**Research host:** Windows 10 x64, PowerShell, Python 3.12, Zig 0.17.1, Rust 1.100.0
**Game path used:** `D:\Games\assettocorsa` (the `/d games assetocorsa` path from the brief)

## Bottom line

A **fully functional native iOS port cannot be produced in this environment and was not
faked.** There is no macOS host, no Xcode, no iPhoneOS SDK, no code-signing identity,
no simulator and no device here. Per the brief's rules, no fake IPA, no browser build and
no remote-streaming wrapper was created.

What *was* produced:

1. A grounded architecture study of the original game and of the two open projects
   (`rustyAC`, `openASC`) — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
2. A selection of the most promising base and a concrete iOS integration design.
3. **Real native ARM64 code**: `artifacts/ac_pal_bridge.arm64.o` — a verified Mach-O 64
   object, cputype `0x0100000c`, built with Zig's `aarch64-ios` target. This is genuine
   code that links into an iOS app; it is *not* a placeholder.
4. Host-verified C bridge unit-test suite and Rust PAL/FFI crates
   (**8 Rust tests pass**) — see [`docs/TEST_REPORT.md`](docs/TEST_REPORT.md).
5. Real, verified unified-diff patches for upstream rustyAC's iOS target.
6. The iOS app shell source (UIKit / MetalKit / GameController / touch), a reproducible
   macOS build script, an IPA auditor and complete build instructions.
7. An honest list of remaining blockers — see [`docs/BLOCKERS.md`](docs/BLOCKERS.md).

**No IPA is included.** Why, precisely: building an IPA requires Apple's linker and SDK
plus a signing identity; neither exists here. [`artifacts/README.md`](artifacts/README.md)
explains this and lists the exact gap.

## What is implemented vs not

See [`docs/FEATURES.md`](docs/FEATURES.md). In short: app shell, menu, content discovery,
touch + gamepad input plumbing, camera selection, fixed-step scheduling, native ARM64
object and FFI chain are implemented. **Real track rendering, real car loading, real
physics and sound on iOS are not** — they require linking rustyAC on macOS, which is the
primary blocker.

## Quick verification on this host

```powershell
cd D:\opencode-sandbox\ac-ios-port
python scripts\build_native_core.py      # host tests + real ARM64 object + Mach-O check
python scripts\make_patches.py           # regenerate and verify upstream patches
cd rust; %USERPROFILE%\.cargo\bin\cargo.exe test --offline
python scripts\verify_delivery.py        # overall delivery check
```

## Repository layout

```
core/           Native C bridge (ARM64-built): input shaping, fixed-step clock, FFI vtable
rust/           ac-ios-pal (traits + host doubles) and ac-ios-runtime (C ABI)
ios/            UIKit/MetalKit app shell, XcodeGen project, signing templates
patches/        Verified unified diffs against rustyAC master + applied copies
scripts/        Reproducible build, verification, patch and IPA-audit scripts
docs/           Architecture, feasibility, build, test, blockers, features, sources
artifacts/      Verified ARM64 Mach-O object + manifest (NO IPA)
third_party/    Downloaded rustyAC master source (reference; not redistributed)
logs/           Real compile/test/verification logs from this session
```

## Legal

No Assetto Corsa binaries, cars, tracks, textures, audio or other protected assets are
included in this deliverable. The app resolves all content at runtime from a directory
the user imports from their own legal copy. rustyAC is GPL-3.0-or-later; openASC is MIT.
See [`docs/RESEARCH_SOURCES.md`](docs/RESEARCH_SOURCES.md).
