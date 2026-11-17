# Phase 4 — first playable controls (real input → real GameSim)

## Success criterion

**Met at the engine level on Windows; compiled for iOS ARM64; never run on an iPhone.**

The real Lotus Elise SC on Magione can now be driven with throttle, brake, steering,
gear selection, handbrake and camera requests. Every value reaches the real
`rustyac_game::sim::GameSim` via `CarControls` and is verified by deterministic
telemetry sequences.

## Input path (no visual-only controls)

`UIKit/GameController → ACIosInputState → ac_pal_bridge_set_controls() →
AcCoreVTable::session_set_ext_input → CarControls → GameSim::step()`

- **Touch:** steering pad (left half), throttle/brake zones (right half),
  buttons `Gear +`, `Gear -`, `Handbrake` (hold), `Camera`, `Gearbox: AUTO/MANUAL`.
  All touch state is recomputed from live touches, so releasing a finger releases
  the control (`recomputeTouchControls`).
- **GameController:** extended pad = left stick steering, RT throttle, LT brake,
  **A gear up, X gear down, B handbrake, Y camera** (matches AC's own XInput layout).
  Micro pad = dpad steering, A throttle, X brake, A+X gear up; camera via touch button.
  Held pad buttons are edge-detected so a shift is requested once, not every frame.
- Gear requests are **one-shot in the C bridge**: OR-ed until the next physics step,
  then consumed exactly once (`ac_bridge_step`).
- `auto_shifter` is selectable before session creation (`ac_ios_set_auto_shifter`),
  so manual paddles really reach the transmission.

## Deterministic telemetry evidence

`phase4/control_sequence_test.log` — real `GameSim`, real AC content:
```
BEFORE speed_kmh=0.000 rpm=0.0 gear=1 steps=0
AFTER  speed_kmh=17.742 rpm=2193.3 gear=2 steps=900
POSE before=(24.027,5.431,206.864) after=(22.606,5.406,204.394)
WHEELS mean spin 0.000 -> 16.210 rad/s
STEER snapshot at step 580: steer_control=0.350 steer_deg=177.450
BRAKE speed 17.742 -> 0.008 km/h
GEAR manual gear 1 -> 3, speed 7.740 km/h
```
- throttle → RPM 0→2193 and speed 0→17.7 km/h ✅
- brake → 17.7→0.008 km/h ✅
- steering → wheel angle 177.45°, position changes ✅
- manual gear-up → transmission 1→3 ✅
- wheel rotation follows real movement (16.21 rad/s) ✅

Note: rustyAC's `SpawnSequence` ignores devices for its first 470 physics ticks
(real AC settling + engaging first gear). All test inputs are applied after that.

## HUD

Shows **live** values only: speed km/h, RPM, gear, throttle, brake, steering,
physics-step count, track-loaded flag, measured draw time. Data comes from
`ac_pal_bridge_snapshot()` → `CarView::capture(&sim, …)` after real steps.

## Frame loop / lifetime

- Real frame delta from `CFAbsoluteTimeGetCurrent()`, clamped to 100 ms; the native
  bridge clamps again and runs a fixed 333.33 Hz accumulator (max 12 steps/frame).
- Simulation steps and rendering both read the same live `GameSim` session.
- Resize: `mtkView:drawableSizeWillChange` → `ac_ios_metal_resize`.
- Shutdown: `ac_ios_render_destroy` → `ac_ios_metal_destroy` → `ac_pal_bridge_shutdown`.
- HUD text updates every 30 frames, no per-frame logging, no background tasks.

## Performance (Windows ONLY — not iPhone performance)

`rust/ac-ios-runtime/examples/bench_render.rs`, 960×540, 60 frames, real AC renderer,
**no kgl log, no PNG in the timed section**, one GPU sync after timing:
```
cpu_draw_mean_ms=26.446
submit_wall_mean_ms=26.446
total_with_gpu_sync_mean_ms=253.086
```
The 253 ms figure is the single end-of-run synchronisation amortised over 60 frames
(it includes all queued GPU work on this Windows host). These numbers must NOT be
read as iPhone performance — no Apple hardware was available.

## Verification

- `cargo test --offline`: 8/8 (`logs/11_phase4_final_tests.log`).
- `cargo check --target aarch64-apple-ios -p ac-ios-runtime`: exit 0 (`phase4/ios_check.log`).
- `python scripts/verify_delivery.py`: 39/39.
- C bridge host tests: ALL PASSED (`phase4/native_core.log`) — includes one-shot
  gear/camera request consumption.

## Honest limitations

- No iOS execution, no device, no Xcode/iPhoneOS SDK: touch/gamepad/HUD/Metal
  behaviour on an iPhone is unverified. Cross-compilation is not a runtime test.
- No audio, multiplayer, opponents, YEBIS, reflections or elaborate menus (by scope).
- Camera switching currently cycles AC's drivable cameras; no cockpit/track camera UI.
- `steer_deg=177.45` is upstream's raw steering-wheel angle convention, not a bug.
