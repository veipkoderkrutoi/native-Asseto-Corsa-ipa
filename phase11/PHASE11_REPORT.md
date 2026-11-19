# Phase 11 — Assetto Corsa Mobile Experience

## Scope

Real native iOS port preserved: rustyAC GameSim, real AC renderer, real content
import, audio, touch controls, Phase 8.1/8.2 sampler fixes and Phase 10 memory
budget are unchanged. This phase adds the UI shell, game modes and FPS control.

Checkpoint before: `checkpoint/before_phase11/` (includes working Phase 10 IPA).

## Screens implemented

- **Home** — AC-styled graphite/red header, selected vehicle card, selected
  track card, current mode, Personal Best, large central DRIVE button and
  GARAGE / TRACKS / GAME MODES / SETTINGS / CONTENT buttons.
- **Garage** — compact car list (folders from `content/cars`), checkmark for the
  selected car, SELECT VEHICLE confirmation.
- **Tracks** — compact track list (`content/tracks`) and SELECT TRACK.
- **Game modes** — Practice, Time Attack, Hotlap, Free Drive selectable;
  Race explicitly shown as COMING LATER (no fake AI).
- **Settings** — real, persisted controls for Graphics/Audio/Controls/Gameplay.
- **In-race** — HUD (speed/rpm/gear), Time Attack panel, touch wheel/pedals,
  gear/handbrake/camera/menu buttons, optional diagnostics.

## What actually works

- All menu buttons navigate; selection writes to `ACSettings` and is reflected
  on Home immediately and after relaunch.
- DRIVE closes the menu without resetting the session; MENU returns to Home
  and pauses timing without recreating GameSim.
- Settings values are applied to the corresponding subsystems:
  FPS cap → `MTKView.preferredFramesPerSecond`; volumes/mute → audio FFI;
  sensitivity/deadzone/button scale → touch controls; auto shifter → bridge;
  diagnostics/HUD visibility → overlays.
- Time Attack/Hotlap use the **real AC lap timer** from `CarView::capture`.

## Files

- `ios/GameViewController.m` — all screens, HUD, timing panel, FPS/thermal.
- `ios/ACSettings.h/.m` — persistence + per car/track PB records.
- `ios/ACTiming.h/.m` — monotonic timing state machine, real lap integration.
- `ios/ios_bridge.h/.m` — lap-state/formatting/memory FFI wrappers.
- `rust/ac-ios-runtime/src/phase11.rs` — tested pure helpers + FFI.
- `rust/ac-ios-runtime/src/lib.rs` — `ac_ios_core_lap_state`.
- `ios/project.yml` — new sources.

## Tests / verification

See `phase11/TIME_ATTACK_REPORT.md` and `phase11/PERFORMANCE_REPORT.md`.

## Limitations

- No genuine per-car preview image is shipped: the installed AC content has no
  preview/icon files for these cars, and rendering a 3D showroom would add a
  second heavy scene. Home uses honest typographic identification instead of
  invented artwork. Architecture remains open for a future preview renderer.
- Race mode is not implemented (architecture prepared only).
- Auto FPS is a stable system refresh cap, not adaptive thermal control;
  thermal serious/critical forces 30 FPS through a public API only.
- All real-device claims remain pending user verification.

## Build / artifacts

- Patch: `patches/phase11/`
- Checkpoints: `checkpoint/phase11_1/` … `checkpoint/phase11_4/`,
  final `checkpoint/after_phase11/`
- Commit / CI / IPA: filled in after CI.
