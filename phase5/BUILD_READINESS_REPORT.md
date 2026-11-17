# Phase 5 — device bring-up readiness (audit + handoff)

## Status

**No iOS execution claim.** There is no macOS host, Xcode, iPhoneOS SDK, simulator,
Apple device or signing identity in this environment. The work below is a static
audit, concrete integration fixes, a reproducible macOS procedure, and separate
Windows-only performance measurements.

## 1. Xcode integration audit — issues found and fixed

| # | Issue | Impact | Fix |
|---|---|---|---|
| 1 | Rust `.a` listed in `sources` | XcodeGen has **no default build phase for `.a`** (`FileType.swift` lists only frameworks, sources, headers, resources); the library would not be linked | Moved it to `dependencies: - framework: <path>` (Link Binary With Libraries) |
| 2 | SDK frameworks declared as `framework: Metal.framework` | XcodeGen `framework:` is for file/XCFramework paths; SDK frameworks use `sdk:` | Changed to `sdk: Metal.framework`, MetalKit, GameController, QuartzCore, added **UniformTypeIdentifiers** (`UTType.folder` in AppDelegate) |
| 3 | No `-ObjC` linker flag | Needed if a static library contains Objective-C categories | Added `-ObjC` (archive audit found **no** ObjC categories, so harmless) and kept `-lc++` |
| 4 | No renderer resize call | wgpu surface resized but AC renderer's screen targets kept the old size | Added `ac_ios_render_resize()` and call it from `mtkView:drawableSizeWillChange` |
| 5 | No GameController disconnect / app-lifecycle observers | Held input could survive a pad disconnect or backgrounding | Added `GCControllerDidConnectNotification`, `GCControllerDidDisconnectNotification`, `UIApplicationWillResignActiveNotification`, `UIApplicationDidBecomeActiveNotification` observers and transient-input reset |
| 6 | Re-driving a second car/track reused a stale renderer | Renderer loaded KN5 for the previous session | Tear down renderer + Metal chain before opening a new session |
| 7 | `ac_ios_set_metal_layer` undeclared in `ios_bridge.h`, type mismatch (`CAMetalLayer*` vs `void*`) | Potential ObjC compile warning/error | Declared `void ac_ios_set_metal_layer(void *layer)` and aligned implementation; view dealloc now passes NULL |
| 8 | `build_ios.sh` cloned upstream and ran `cargo check` by default | Unnecessary network + rebuild, contrary to reproducibility requirement | Rewritten: reuse the SHA-verified staticlib; `AC_REBUILD_RUST=1` opt-in; jobs limited to 2 |
| 9 | No project preflight | Mistakes would only appear on a Mac | Added `scripts/verify_ios_project.py` (52 checks), `audit_ios_link_inputs.py`, `verify_staticlib_hash.py`, `inspect_ios_archive.py` |

Final iOS staticlib after these fixes: 51,412,568 B, SHA-256
`7f3e71900ea3cc6e8043f96db6ad1c7022adac71d89a0f1f692d82e66173b565`, matching
`artifacts/IOS_STATICLIB_MANIFEST.json`.

Preflight result after fixes: **52/52 PASS** (`phase5/project_preflight.log`).
This validates paths, frameworks, bundle id, signing placeholders, C symbol
declarations, runtime wiring, the object's iOS min version and absence of AC assets.
It does **not** replace an Xcode build.

## 2. Build reproducibility

Single procedure: `bash scripts/build_ios.sh` on macOS (full instructions in
`docs/BUILD_IOS.md`). It:
- requires `AC_TEAM_ID`, `AC_SIGNING_IDENTITY`, `AC_PROFILE_NAME` supplied by the caller
  (no credentials are fabricated or committed);
- verifies the existing `libac_ios_runtime.a` hash against
  `artifacts/IOS_STATICLIB_MANIFEST.json`, and its ARM64 objects + exported symbols;
- runs the project preflight;
- uses `CARGO_BUILD_JOBS=2` and, by default, no Cargo rebuild at all;
- generates `ios/ac-ios-port.xcodeproj` from the checked spec;
- builds/exports with Xcode into `D:\…\build\ios` (derived data, archive, IPA);
- audits the final IPA to ensure no protected AC assets are embedded.

## 3. Runtime readiness audit

- **CAMetalLayer:** strong static reference in `ios_bridge.m`, set from the MTKView layer
  at view load and cleared (NULL) at dealloc.
- **wgpu surface:** `Instance(METAL) → Surface(CoreAnimationLayer) → Adapter →
  Device/Queue → configure`, with format cached in the chain; `ac_ios_metal_resize`
  reconfigures the surface, and `ac_ios_render_resize` resizes AC's screen targets.
- **Drawable/present:** `get_current_texture()` → `create_view` → `renderer.draw` →
  `present_to` → `queue.present`. `Outdated/Lost` triggers reconfigure. No PNG
  readback and no `read_pixels()` in the normal frame loop. `get_current_texture()`
  can block waiting for a drawable; device pacing is untested.
- **GameSim startup/shutdown:** Drive boots the vtable, opens a real session, builds
  Metal + renderer; dealloc tears down renderer, Metal, bridge in that order.
- **Document picker / sandbox:** folder picker with `asCopy:NO`, security-scoped
  bookmark creation/resolution, `LSSupportsOpeningDocumentsInPlace=YES`.
- **Touch:** all controls recomputed from live touches; `touchesCancelled` resets;
  pad connect/disconnect and app lifecycle reset latched edges.
- **Frame loop:** real delta clamped, fixed 333 Hz accumulator, HUD text every 30
  frames, no per-frame logging, no background tasks.

## 4. Performance investigation (Windows ONLY)

Separate, honest measurements at 960×540, real car/track, no kgl log, no PNG write,
no readback in the ordinary timed sections:

| Metric | Value | Source |
|---|---:|---|
| CPU simulation (GameSim, 333 Hz) | **0.336 ms/frame** | `phase5/bench_sim.log`, 600 frames, 5.55 physics steps/frame |
| CPU draw preparation (AC renderer draw call) | **32.990 ms/frame** | `phase5/bench_render.log`, 60 frames, warm pipelines |
| Submit wall time | **32.991 ms/frame** | same |
| GPU execution + queue drain (diagnostic only, single sync AFTER timing) | **303.709 ms/frame amortised** | `phase5/bench_render.log` — not a normal frame time |
| Presentation wait | **not measured** | requires a real iOS CAMetalLayer surface |
| Total normal frame time | **not claimed** | would need device timestamp queries / Xcode GPU capture |

These are Windows host numbers and must not be presented as iPhone performance.

## 5. Unresolved risks (handoff)

1. `xcodegen`/`xcodebuild` were unavailable here: the spec was statically validated
   but never parsed by XcodeGen or compiled by clang. ObjC compile errors remain possible.
2. Rust staticlib contains `_objc_msgSend` (Objective-C runtime, auto-linked on iOS);
   no ObjC categories found, but full link resolution requires Xcode.
3. Rust objects declare min iOS 10.0 while the app/PAL object declare 16.0; ld64 uses
   the highest, but verify in Xcode's link log.
4. `AcRenderer` was never executed with a CAMetalLayer-backed wgpu surface — only
   cross-compiled. Surface lifetime across background/foreground is unverified.
5. Full AC content (~42 GB) must be imported by the user on-device; storage and
   security-scoped bookmark lifetime across app restarts need device testing.
6. Installed AC is 1.16.2 while rustyAC's oracle tools reference 1.16.4; runtime
   content/physics worked on Windows, bit-exact oracle parity is not claimed.
7. No signing identity/profile here; `build_ios.sh` fails fast if they are absent.

## How to actually obtain an IPA (added after the audit)

A free GitHub account is enough to produce a **real unsigned IPA**:
`.github/workflows/build-unsigned-ios.yml` uses GitHub's free macOS runner
(unlimited for public repositories; ~190 min/month on GitHub Free private repos
at $0.062/min), rebuilds the ARM64 library with `jobs=2`, runs the preflight, builds
with `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`, packages `Payload/*.app`
into `AC-iOS-Prot-unsigned.ipa`, audits it with `scripts/audit_unsigned_ipa.py`
(no protected assets, ARM64 executable, correct bundle id) and uploads it as an
artifact. Workflow refs validated by `scripts/verify_workflow_refs.py`.

The unsigned IPA is **not installable as-is**. Install it with free
Sideloadly/AltStore using a free Apple ID (7-day certificate, auto-refresh, no
jailbreak). A $99/year Apple Developer Program is only needed for stable
distribution/TestFlight. Full details: `docs/IPA_ROUTES.md`.

No signing credentials are fabricated or committed; `.gitignore` keeps build
outputs, checkpoints and IPAs out of the repository.

## Deliverables

- Complete build procedure: `docs/BUILD_IOS.md`, `scripts/build_ios.sh`.
- Apple prerequisites: listed in `docs/BUILD_IOS.md` and section 2 above.
- This build-readiness report and `phase5/SHA256_MANIFEST.json`.
- Clean checkpoint: `checkpoint/after_phase5/` (created after final verification).
