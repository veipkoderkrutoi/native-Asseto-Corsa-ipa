# Phase 11 — Time Attack report

## Data source (no invented laps)

`rustyac_game::view::LapView` from the live GameSim provides:
`current_ms`, `last_ms`, `best_ms`, `laps`, `on_track`, `valid`, `last_valid`,
`cuts`, `position`. This is AC's own lap timing (transponder-based), not a
guess from car coordinates. Phase 11 adds `ac_ios_core_lap_state()` in
`rust/ac-ios-runtime/src/lib.rs` and an Objective-C wrapper `ac_ios_lap_state()`
reading the live session each frame.

If a track has no timing lines (`on_track == 0`), the UI does not claim Timing
data: `ACTiming::updateWithLap` ignores it. No synthetic start/finish line exists.

## Timer

- Current lap uses `mach_absolute_time()` via `mach_timebase_info` (monotonic,
  independent of frame rate) in `ios/ACTiming.m`.
- Pause/resume accumulate paused duration; app backgrounding pauses timing.
- On `laps` increase, the official lap time is AC's `last_ms` (fallback: the
  monotonic timer only if AC reports none).
- Format MM:SS.mmm (HH:MM:SS.mmm above an hour) comes from tested Rust helper
  `format_lap_time_ms` exposed through `ac_ios_format_lap_ms`.

## Personal Best

`ACSettings` stores one record per `car|track` key with `best`, `last`, `laps`
and `date`. PB acceptance uses the tested Rust rule `should_accept_pb` (lap > 0,
valid, zero cuts, strictly faster). Cars and tracks cannot share records.

## HUD

Time Attack/Hotlap show current time, best, last and lap count alongside the
real speed/RPM/gear HUD. PB events surface as a short on-screen message.

## Tests

```text
cargo test -p ac-ios-runtime --lib --offline
→ 9 passed; 0 failed (5 new Phase 11 tests)
  - formats_lap_times
  - pb_requires_a_clean_valid_lap
  - delta_sign_matches_faster_or_slower
  - fps_caps_and_indexes_round_trip
  - thermal_state_only_caps_when_needed
```

`cargo test -p rustyac-render --features backend-wgpu --lib --offline`
→ 42 passed; 0 failed; 2 ignored (Phase 8–10 regressions intact).

## Status

The timing logic and records are implemented and locally tested. A real lap
completion on the iPhone has **not** been observed yet — no PB value is claimed.
