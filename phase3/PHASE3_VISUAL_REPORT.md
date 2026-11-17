# Phase 3 — first visible drive (real AC car on real AC track)

## Definition of success

**Met on the Windows host with the real engine; compiled for iOS ARM64, not executed on a device.**

`phase3/shots/magione_lotus.png` is a real rendered frame: a green Lotus Elise SC on
Magione, with real AC road, kerbs, grass, trees, buildings, pit structures, shadows
and the car's own 3D model/textures. It was produced by rustyAC's own renderer from
the user's installed game content — not by a mock scene.

## 1. Research / compatibility (before implementation)

- Vendored tree: `third_party/rustyAC-src/rustyAC-master` (downloaded 2026-11-17).
- Current upstream head checked via GitHub API: `65a06b0ab87e2b88a2337badb9b79046c88016c3`
  (2026-11-17 14:45 UTC); newer commits are `docs(csp)`-only.
- Byte-identical comparison of key files (local SHA-256 prefix = upstream prefix):

| File | Local | Upstream master |
|---|---|---|
| `crates/rustyac-web/src/gpu.rs` | `1C931E95804E` | `1C931E95804E` |
| `crates/rustyac-web/src/shader.wgsl` | `674E946E87D8` | `674E946E87D8` |
| `Cargo.toml` | `B74596132ECE` | `B74596132ECE` |
| `crates/rustyac-web/Cargo.toml` | `135FE6E626F7` | `135FE6E626F7` |

**Decision: do NOT replace the vendored repository.** The renderer code is current, and
the working Phase 2 integration stays intact.

Renderer findings:
- `rustyac-web/src/gpu.rs` (preview `Gpu`) is **wasm-only**, private, and tied to
  `web_sys::HtmlCanvasElement` — not reusable natively without a rewrite.
- The **full renderer path is native-capable**: `rustyac-web/examples/full_frame.rs`
  creates a `GameSim`-driven `Session` and `AcRenderer`, draws N frames offscreen with
  wgpu and writes a real PNG. It uses KN5 geometry, 95 track textures, 53 materials
  and all 4 LODs of the car. This is the renderer we reuse — no scene code was invented.
- `AcRenderer::give_device` / `Kgl::give_device` is the device-injection point that
  connects our existing `metal.rs` chain to the same renderer on iOS.

## 2. What was implemented (minimum visual slice)

Files (all under `rust/ac-ios-runtime/src/`):
- `render.rs` (new) — `ac_ios_render_init` builds `AcOptions`, creates the real
  `AcRenderer`, calls upstream `load_track()` / `load_car_info()` / `finish_loading()`;
  `ac_ios_render_frame` captures `CarView` from the live `GameSim`, computes a real
  chase `CameraFrame` via `DrivingCamera::chase().update(...)`, calls `renderer.draw()`
  and `present_to()` into the CAMetalLayer's current wgpu texture, then
  `queue.present()`. Real CPU draw timings are exported via
  `ac_ios_render_last_draw_ms` / `ac_ios_render_stats`.
- `metal.rs` — now only creates the wgpu Instance/Surface/Adapter/Device/Queue and
  calls `Kgl::give_device()`; `AcRenderer::new()` performs `Kgl::init()` so the
  renderer owns its kgl state (no double-init, no VULKAN fallback).
- `lib.rs` — exposes the live session through `with_session()` and extends the
  visualization snapshot with real body position, wheel angular speed and steer angle.
- `core/ac_pal_bridge.{h,c}` — `ac_pal_bridge_session()` gives the renderer the live
  opaque handle.
- `ios/ios_bridge.h`, `ios/GameViewController.m` — Drive now runs
  `ac_ios_metal_init()` → `ac_ios_render_init()`; every MTKView frame calls
  `ac_ios_render_frame()`; HUD shows real speed/RPM/gear plus measured draw time.

No audio, multiplayer, post-processing, reflections, FFB or new menus were added.

## 3. Windows validation (real rendering)

Command (AC_ROOT set to the installed game):
```
cargo run --release -p rustyac-web --example full_frame --features wgpu -- \
  --car lotus_elise_sc --track magione --spawn hotlap --size 960x540 --frames 3 \
  --out phase3/shots --name magione_lotus
```
Exit 0. Evidence:
- `phase3/shots/magione_lotus.png` (992,742 B) — actual scene, viewed and confirmed.
- `magione_lotus.kgllog` (445,796 B; 15,645 kgl log lines) — real D3D/wgpu command log.
- `magione_lotus.files` (7,563 B) — every AC file read by that frame.
- Log summary: `track models: 2 files, 95 textures, 53 materials`,
  `car model …/lotus_elise_sc: 4 levels of detail, skin 0_racing_green`.

Exact identifiers: **car `lotus_elise_sc`** (Lotus Elise SC, skin `0_racing_green`),
**track `magione`**, spawn `hotlap`, session type hotlap.

## 4. Evidence that GameSim controls the car and wheels

`phase3/real_car_pose_test.log` (real `GameSim`, real AC content, 900 ticks = 2.7 s,
with a 120-tick steering input):
```
real session ready: lotus_elise_sc @ magione (track loaded: true)
BEFORE speed_kmh=0.000 rpm=0.0 gear=1 steps=0
AFTER  speed_kmh=18.338 rpm=2265.1 gear=2 steps=900
POSE before=(24.027,5.431,206.864) after=(22.911,5.407,203.928)
WHEELS mean spin 0.000 -> 16.844 rad/s, steer_deg 0.000 -> 177.450
```
The same values are written into the 16-float snapshot the renderer/HUD consumes.

## 5. iOS ARM64 cross-check

- `cargo check --target aarch64-apple-ios -p ac-ios-runtime` — **exit 0**
  (`phase3/ios_render_check.log`). This includes the real `AcRenderer`, real rustyAC
  physics/ODE/content, wgpu Metal backend and the new render module.
- Cargo parallelism limited to 2 (`rust/.cargo/config.toml`, `[build] jobs = 2`),
  target dir on D:.

**A successful cross-compilation is NOT proof of rendering on an iPhone.** The iOS
renderer has never run: no Xcode, iPhoneOS SDK, simulator or device exists here.

## 6. Performance measurement (Windows, offscreen full renderer)

Differential wall-clock of the same native example (cached build, same car/track/size):
- 3 frames: 10,552.9 ms (`phase3/perf3.exit`)
- 60 frames: 17,050.7 ms (`phase3/perf60.exit`)
- `(17050.7 - 10552.9) / 57 ≈ 114 ms/frame` at 960x540.

This includes kgl command logging (249k lines), pixel readback and PNG writing, so it
is an upper bound, not a pure GPU frame time. The in-app `ac_ios_render_*` counters
report CPU draw-call time separately once an iOS build runs.

## 7. Remaining rendering limitations

1. No iPhone execution — Metal surface lifetime, CAMetalLayer resize and
   `present_to()` on iOS are unverified at runtime.
2. No GUI/HUD overlay from AC (`HudInfo { hidden: true }`); speed/RPM/gear come from
   the real `CarView` through our own HUD text.
3. No post-processing parity (YEBIS already disabled for this AC build); no mirrors,
   shadows settings UI, or advanced camera modes (only `DrivingCamera::chase()`).
4. The renderer loads only the player's single car (no opponents/traffic).
5. `full_frame` uses a fixed 1/60 s loop; vsync/presentation pacing on iOS is untested.
6. Real AC content is never bundled: the user must import a legal install.
