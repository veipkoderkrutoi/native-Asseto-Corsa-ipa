# Test report

All tests below were **actually executed** on the research host unless marked
"not run". Commands and outputs are in [`../logs/`](../logs/).

## Environment probe

| Check | Result |
|---|---|
| OS | Windows 10 (19045), AMD64 |
| Xcode / xcodebuild / swiftc / clang | **absent** |
| iPhoneOS SDK / codesign / simulator / device | **absent** |
| Apple CI/MCP credentials | none (`list_mcp_resources` → empty) |
| Python | 3.12 (real, functional) |
| Zig | 0.17.1 (`pip install ziglang==0.17.1`) |
| Rust | 1.100.0 stable (`rustup`, installed during this task) |
| AC install | 1.16.2, 178 cars, 21 tracks, 42.7 GB |
| `rustyAC` source | downloaded master (37.9 MB zip), 14 crates |

## 1. Native C bridge — host tests — PASS

```
python -m ziglang cc -std=c11 -O2 -Wall -Wextra core/ac_pal_bridge.c core/ac_pal_bridge_test.c -o build/ac_pal_bridge_test.exe
.\build\ac_pal_bridge_test.exe
→ ac_pal_bridge_test: ALL TESTS PASSED
```

Covered: deadzone/expo curves, gamepad/touch mapping (including clamping of out-of-range
triggers — fixed after a test caught it), fixed-step accumulator determinism and
spiral-of-death guard, full bridge lifecycle with a mock vtable, NULL argument handling.

## 2. Rust PAL + FFI — 8/8 tests PASS

```
cd rust && cargo test --offline
ac-ios-pal:     4 passed (control clamping, scripted input, content paths, sinks)
ac-ios-runtime: 4 passed (vtable layout, boot, full FFI round trip, invalid args)
```

`vtable_layout_matches_c_header` asserts the Rust struct is exactly 5 pointer-sized
fields, matching `AcCoreVTable` in `core/ac_pal_bridge.h`.

## 3. Real ARM64 iOS object — PASS

```
python scripts/build_native_core.py
→ artifacts/ac_pal_bridge.arm64.o  (17,424 bytes)
```

Zig `aarch64-ios` cross-compile succeeded after removing `math.h`/`string.h` dependencies
(builtins + a local zeroing loop). Standalone Mach-O verification
(`python scripts/verify_macho.py`):

| Check | Result |
|---|---|
| magic `0xfeedfacf`, little-endian | PASS |
| cputype `0x100000c` (ARM64) | PASS |
| cpusubtype 0 (ARM64_ALL) | PASS |
| filetype 1 (MH_OBJECT) | PASS |
| 5 load commands, sizes/offsets consistent | PASS (LC_SEGMENT_64, LC_FUNCTION_STARTS, LC_SYMTAB, LC_DYSYMTAB, …) |
| SHA-256 | recorded in `artifacts/NATIVE_OBJECT_MANIFEST.json` |

This is **real native ARM64 machine code**, but an object file is not an app.

## 4. Upstream patches — PASS

```
python scripts/make_patches.py
[OK] rust-toolchain.toml
[OK] crates/rustyac-render/Cargo.toml
[OK] crates/rustyac-game/Cargo.toml
Wrote patches/0001-ios-native-target.patch (2207 bytes)
```

The script re-applies every hunk with exact context to the pristine upstream files and
compares to the expected result (no fuzz, no offsets).

## 5. IPA auditor — self-test

`scripts/audit_ipa.py` was exercised against a synthetic ZIP (bundle + Info.plist +
ARM64 executable + CodeResources) and correctly reports structure; it is used by
`scripts/build_ios.sh`. It has **not** audited a real IPA from this project (none exists).

## Not run / cannot run here

- `scripts/build_ios.sh` — requires macOS/Xcode/signing.
- `cargo check --target aarch64-apple-ios -p rustyac-game --features wgpu` — requires the
  iOS Rust std and macOS; the patch is verified structurally but not compiled upstream.
- Objective-C shell compile — requires iPhoneOS SDK.
- On-device tests: cold start, menu, track load, car spawn, physics, touch, gamepad,
  camera, audio, background/resume. **No device was available.**
- Performance/FPS/thermals — no measurements, none claimed.

## Honest conclusion

The delivered evidence proves: (a) the architecture research is grounded in the actual
upstream source and the user's actual install, (b) the native ARM64 code we wrote
compiles and its tests pass here, (c) the iOS integration design is concrete and the
patches are valid. It does **not** prove a runnable iOS game — that requires the macOS
build and a device, listed in `BLOCKERS.md`.
