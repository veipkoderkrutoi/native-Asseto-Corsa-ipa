# Phase 11 — Performance report

## FPS limiter implementation

MTKView owns the display link. The limiter sets
`MTKView.preferredFramesPerSecond` from the persisted setting through tested
helpers (`fps_cap_for_index`, `thermal_limited_cap`):

- Auto → stable 60 FPS cap (never forced 120 on ProMotion);
- 30 / 40 / 45 / 60 explicit values;
- `ProcessInfo.thermalState` (public API) serious/critical → cap 30 unless the
  user already chose a lower cap.

## Physics independence

Physics still runs through `ac_pal_bridge_run_frame(delta)` with rustyAC's own
fixed-step accumulator (333 Hz, max 12 steps/frame). The FPS cap changes only
render scheduling; it does **not** scale `delta` artificially, change GameSim,
or sleep the main thread. Delta is clamped at 0.1 s on resume as before.

Audio is updated from the same real telemetry each render callback frame and
runs on its own AVAudioEngine thread; it is not blocked by the FPS cap.

## Diagnostics (optional, default OFF)

FPS (smoothed), frame time, physics update time, render draw time, memory
footprint (`mach_task_basic_info.phys_footprint`), selected/effective FPS cap,
thermal state, texture load counters, Metal feature mask and audio status.

## Memory

No new GPU textures are allocated by the UI. Menu screens are ordinary UIKit
views built once; no model or KN5 is loaded when switching screens. Phase 10
BC fallback cap (1 MP/texture) is unchanged.

## Measurements

The user previously observed roughly 60 FPS on the Phase 10 build. No numeric
post-change measurement exists yet — it must be read from the new diagnostics
panel after the iPhone test. This report makes no performance claim beyond the
implemented controls.
