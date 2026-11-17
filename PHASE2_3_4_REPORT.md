# Phase 2/3/4 — real engine integration, iOS binding fixes, cross-check

## Main criterion: MET (real physics session, real AC resources)

`rust/ac-ios-runtime` no longer contains a mock/null core. It now depends on the actual
upstream `rustyac-game`, `rustyac-physics` and `rustyac-content` crates and builds a real
`GameSim` with a real car and track from the user's install.

Exact evidence (`phase2/real_session_test.log`), real engine + real content:
```
ac_ios: real session ready: lotus_elise_sc @ magione (track loaded: true)
ac_ios: BEFORE speed_kmh=0.000 rpm=0.0 gear=1 steps=0
ac_ios: AFTER  speed_kmh=17.566 rpm=2172.0 gear=2 steps=900
test result: ok. 1 passed
```
`900 × 3 ms = 2.7 s` of real `rustyac-physics` ticks at full throttle; speed, rpm and gear
came from `CarView::capture(&sim, 0.0)` after each real step. The snapshot passed to the
renderer is this real state: `[0] speed_kmh [1] rpm [2] gear [3] gas [4] brake [5] steer
[6] steps [7] track-loaded`.

## Classification (as requested)

| Category | Items |
|---|---|
| **Implemented and verified** | Real `GameSim` session from `AC_ROOT`; car/track discovery via upstream `find_car_data`/`find_track`; real 900-tick physics run with measured speed/rpm/gear change; real-state snapshot; `GameSim::step` at upstream DT 0.003 s; C↔Rust vtable round trip; full Windows baseline (Phase 1) |
| **Implemented but not verified** | iOS shell changes: `UIDocumentPicker` folder selection, security-scoped bookmark creation/resolution, touch reset on finger-up, new telemetry display, `ac_ios_metal_layer` rename, `ios_bindings` declaration fix — all source-only, no iPhoneOS SDK here. The wgpu/Metal chain is also implemented and compiled for iOS ARM64, but has never run on an iPhone |
| **Verified only on Windows** | All `cargo test` runs, real launcher/session GUI and screenshots, direct `rustyac.exe` run log, original build, host C bridge tests |
| **Verified on iOS ARM64** | `cargo check --target aarch64-apple-ios -p ac-ios-pal` (PASS); `-p ac-ios-runtime` (PASS — includes real `rustyac-game`, `rustyac-physics`, `rustyac-ode`, `rustyac-content`, `rustyac-gui`, `rustyac-net`, and the new `metal` module); **release `cargo build --target aarch64-apple-ios -p ac-ios-runtime` (PASS)** → `libac_ios_runtime.a`, 49,881,176 B, SHA-256 `1BB422CD…CC5445`, containing **687 real ARM64 Mach-O objects** (verified by `scripts/verify_ios_staticlib.py`; includes rustyAC engine, wgpu Metal backend and renderer). The **complete wgpu chain** — `Instance(METAL) → Surface(CoreAnimationLayer) → Adapter → Device/Queue → surface.configure → Kgl::give_device → Kgl::init` — is type-checked and compiled for `aarch64-apple-ios` (`phase4/check_metal_chain.log`, exit 0) |
| **Blocked by missing Apple SDK** | Linking that static library into an IPA; *executing* the Metal chain on an iPhone (no CAMetalLayer exists here); on-device run, camera/audio/touch tests; Xcode project build and codesign |
| **Not implemented** | Real KN5 track/car rendering on iOS, AC sound on iOS, gamepad FFB, session types other than the single-car hotlap spawn |

## Phase 3 fixes actually made

- `ios/AppDelegate.h/.m`: `UIDocumentPickerViewController` for folders
  (`UTType.folder`, `asCopy:NO`), correct `NSURLBookmarkCreationWithSecurityScope`
  creation, resolution with `NSURLBookmarkResolutionWithSecurityScope`, explicit
  `startAccessingSecurityScopedResource`, stale-bookmark refresh, notification
  `ACiOSRootDidChangeNotification` consumed by the view controller.
- `ios/GameViewController.m`: "Choose AC folder" button; rescan on folder change;
  **all touch state is reset then recomputed from live touches** on began/moved/ended/
  cancelled, so a lifted finger releases the pedal; HUD now prints the real snapshot.
- `rust/ac-ios-pal/src/lib.rs`: renamed `ac_ios_metal_device` → `ac_ios_metal_layer`
  to match the ObjC implementation (both now return the CAMetalLayer pointer).
- `core/ac_pal_bridge.c`: fixed-step clock changed from 1 kHz to rustyAC's real
  **333.33 Hz** (`sim::DT = 0.003`), guard 12 steps; host test updated accordingly.

## Honest limitations / remaining defects

1. **Metal chain is implemented and compiled, but never executed.** `rust/ac-ios-runtime/src/metal.rs`
   builds the full `Instance → Surface → Adapter → Device/Queue → Kgl` chain from the
   CAMetalLayer pointer and is wired into `GameViewController` (`driveTapped`, resize,
   dealloc). It has **not** run on a device: no iPhoneOS SDK / simulator / device here,
   so no runtime claim is made. Correctness of the UIKit layer lifetime still needs a
   real device test.
2. **Min-iOS mismatch fixed.** `scripts/fix_macho_minos.py` replaces Zig 0.17's malformed
   16-byte `LC_BUILD_VERSION` in-place with a valid `LC_VERSION_MIN_IPHONEOS` 16.0
   (`scripts/check_macho_minos.py` confirms min iOS 16.0.0). The fix is part of
   `scripts/build_native_core.py`, so rebuilds reproduce it. On macOS the final object
   should still be compiled with Xcode clang; the Zig object is a host-side ARM64
   codegen proof.
3. **Version mismatch (Phase 0)** — installed 1.16.2 (`acs.exe` PE `0x5a37e319`,
   launcher `0.17.1222.5071`) vs upstream 1.16.4 expectations (`0x5a55e7a8`,
   `0.18.115.5097`); real YEBIS post-processing is disabled by rustyAC at runtime.
   Content/physics work; bit-exact oracle parity is NOT claimed.

## Continuation (after the relocation to D:)

The whole project was moved from `C:\OpenCode-Sandbox\ac-ios-port` to
`D:\opencode-sandbox\ac-ios-port` (5,607 files, robocopy exit 1 = successful copy
and source removal). The OpenCode session working directory was moved too.
`verify_delivery.py` still passes **39/39** and the real-engine host test still passes
from the new path (`logs/05_tests_after_move.log`).

Additional work in this continuation:
- `scripts/fix_macho_minos.py` — real in-place fix of the ARM64 object's iOS min version
  to 16.0; integrated into `scripts/build_native_core.py`; hash updated in
  `artifacts/NATIVE_OBJECT_MANIFEST.json`.
- Fixed a genuine defect in our own upstream patch: the TOML `[target...]` sections
  were inserted mid-`[dependencies]` and swallowed `png`/`jpeg-decoder`, making
  `backend-wgpu` unresolvable. The patch generator now places them at EOF and a
  multi-hunk-safe verifier confirms every hunk (`scripts/restore_upstream_manifest.py`,
  `scripts/apply_ios_patch_to_upstream.py`).
- Added `rust/ac-ios-runtime/src/metal.rs` with the real wgpu/Metal chain and wired it
  to `GameViewController` + `ios_bridge.h`. It compiles cleanly for
  `aarch64-apple-ios` (`phase4/check_metal_chain.exit = 0`).
- Final host test run after all changes: `logs/07_final_tests.exit = 0` (8/8 tests).
- Final iOS ARM64 release staticlib with the Metal chain: `phase4/build_staticlib_final.exit = 0`,
  687 ARM64 objects, SHA-256 `1BB422CD0DBF615E9CD2C5F876B71F3C83BEAA6E8B676E795C0E81C381CC5445`.
- `docs/BLOCKERS.md` / `docs/FEATURES.md` / `docs/FEASIBILITY.md` / `artifacts/README.md`
  updated to match the verified status and the new D: path.

## Artifacts / logs

- `phase1/` — build.log, run_direct.log/err, 5 screenshots, Phase 0/1 report.
- `phase2/` — cargo_test.log, real_session_test.log.
- `phase4/` — iOS target install log, PAL/runtime check logs, staticlib build log.
- `patches/phase2/0001-real-rustyac-engine-integration.patch` — exact change records.
- `checkpoint/phase2_real_engine/` — snapshot of all modified sources + the iOS staticlib.
- `scripts/verify_ios_staticlib.py`, `scripts/check_macho_minos.py` — new verifiers.

## Reproduction

```powershell
$env:AC_ROOT="D:\Games\assettocorsa"
cd D:\opencode-sandbox\ac-ios-port\rust
cargo test --offline -p ac-ios-runtime real_session_loads_ac_content_and_moves_the_car -- --nocapture
cargo check --target aarch64-apple-ios -p ac-ios-runtime
cargo build --release --target aarch64-apple-ios -p ac-ios-runtime
cd ..; python scripts\verify_ios_staticlib.py
```
