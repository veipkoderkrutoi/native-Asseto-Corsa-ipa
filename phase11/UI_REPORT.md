# Phase 11 — UI report

## Visual direction

Graphite/near-black surfaces, red AC-style accent, thin bright-red section
headers, uppercase technical labels, square-ish 4pt corner radius, no large
gradients, no giant opaque cards. Layout is manual and safe-area aware for
landscape iPhone 13 Pro Max (Dynamic Island / status area and Home Indicator).

## Functional checklist

| Element | Behaviour |
|---|---|
| DRIVE | Creates real GameSim session + real renderer, hides menu, starts timing |
| GARAGE | Shows installed cars from `content/cars`, selection persisted |
| TRACKS | Shows installed tracks from `content/tracks`, selection persisted |
| GAME MODES | Mode selection persisted; Race marked COMING LATER |
| SETTINGS | Opens functional settings screen; BACK returns Home |
| CONTENT | Invokes existing document picker / File Sharing flow |
| MENU (in race) | Pauses timing, zeroes inputs, returns Home, no session reset |
| HUD | Speed/RPM/Gear from real telemetry, toggleable |
| Timing panel | Current/Best/Last/Laps from real AC lap timer |
| Diagnostics | Optional, includes FPS, frame/physics/render time, memory, cap, thermal, texture counters, audio status |

## Settings details

Graphics: FPS limit (Auto/30/40/45/60), diagnostics toggle, HUD toggle.
Audio: master/engine/effects sliders + mute (existing AVAudioEngine backend).
Controls: steering sensitivity and deadzone, button scale, pedal layout, reset
layout, auto-shifter. Gameplay: game mode and units.

All values are validated on load (range-clamped) and saved through
`NSUserDefaults` under `ac-ios-port.settings.v1`; missing/corrupt dictionaries
fall back to safe defaults.

## Notes

The old debug-style blue-link menu and overlapping yellow diagnostics are gone.
No decorative-only buttons were added. Car previews are honest typographic
cards because the user's content contains no usable preview images — see
`PHASE11_REPORT.md`.
