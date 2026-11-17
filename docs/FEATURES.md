# Implemented / not implemented

Status values: **Source** = written, compiles where testable, not built into an IPA here;
**Verified here** = compiled and tested on this host; **Partial** = scaffolding exists but
key behaviour missing; **Not implemented** = no code yet.

| Brief priority | Status | What exists | What is missing |
|---|---|---|---|
| App launch | Source (iOS) / Verified (core) | UIKit `AppDelegate`, `main.m`, MetalKit view, Info.plist, XcodeGen project, build/export script | macOS build, signing, device launch |
| Menu load | Source | Car/track enumeration from the imported AC root, table UI, Drive button, session description export | Session/session-type selection (practice/hotlap/…), AC launcher theme |
| Track rendering | **Real on Windows / compiled for iOS** | Real `AcRenderer` loads actual KN5 track (95 textures, 53 materials) and car (4 LODs) and drew `phase3/shots/magione_lotus.png`; wgpu Metal chain + render module compiled for iOS ARM64 | Never executed on an iPhone; no AC GUI/HUD overlay, no post-processing parity |
| Car loading | **Real on Windows / compiled for iOS** | Real `lotus_elise_sc` KN5 + skin `0_racing_green` loaded by upstream `AcRenderer::load_car_info`; real GameSim pose/wheel data proven | Device validation |
| Physics | **Real engine verified on Windows + compiled for iOS ARM64** | Real `GameSim` + `rustyac-physics`/`rustyac-ode` in the runtime; 333.33 Hz fixed-step clock, input curves, FFI; real 900-tick drive measured 0→17.6 km/h | iOS physics dispatch thread, device test |
| Touch control | Real input verified at engine level; Source (iOS) | Steering pad, pedals, gear +/-, handbrake, camera, gearbox toggle; one-shot consumption tested in C; deterministic throttle/brake/steer/gear telemetry in Rust | On-device touch test |
| Gamepad | Real input verified at engine level; Source (iOS) | GCController extended pad: stick/RT/LT, A gear up, X gear down, B handbrake, Y camera, with edge detection | MFi device test, force feedback (no iOS equivalent) |
| Camera | Source wired to real camera | `ac_ios_render_frame` uses AC's `DrivingCamera::chase()`; camera request cycles `next_drivable()` on the real renderer | On-device camera view test |
| Sound | **Not implemented (blocker B3)** | `AudioSink` trait + state recording bridge | FMOD-iOS or CoreAudio adapter, real engine/road/wind sound |
| Filesystem / content | Verified (trait) + Source (iOS) | Security-scoped bookmark, `ContentLocator` with AC layout tests | Device validation of folder import and large content |
| Background / resume | Source | `applicationWillResignActive`/`DidBecomeActive` hooks, delta clamp in bridge | Metal/wgpu resource rebuild on resume |
| Verification tooling | Verified here | Mach-O verifier, IPA structural auditor, patch applier, delivery verifier, real logs | Device-side trace capture |

## Deliverables checklist from the brief

| Requested | Delivered |
|---|---|
| Source code of changes | Yes — `core/`, `rust/`, `ios/`, `patches/`, `scripts/` |
| Architecture report | Yes — `docs/ARCHITECTURE.md`, `docs/FEASIBILITY.md` |
| Build instructions | Yes — `docs/BUILD_IOS.md`, `scripts/build_ios.sh` |
| Real IPA if build succeeded | **No** — build impossible in this sandbox; see `artifacts/README.md` and B1 |
| Compilation logs | Yes — `logs/` (Zig host + ARM64, Rust tests, patches, environment) |
| Test results | Yes — `docs/TEST_REPORT.md` |
| Implemented / not implemented | This file |
