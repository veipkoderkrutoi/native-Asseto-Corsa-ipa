# Phase 11.7 — Functional UI + Content Expansion

## 1. Functional UI audit

- Main menu: DRIVE, GARAGE, TRACKS, GAME MODES, SETTINGS, CONTENT — all wired.
- Garage / Tracks / Modes: rows selectable, checkmarks reflect real selection,
  SELECT / BACK buttons work. Selection is saved via `ACSettings` and passed
  to `ac_pal_bridge_open_session(root, car, track)` verbatim (folder name), so
  the engine receives exactly what the UI shows.
- Settings: FPS cap, game mode, units, HUD, diagnostics, gearbox, pedal layout,
  mute, master/engine/effects sliders, steering sensitivity/deadzone, button
  scale and reset-layout all call real subsystems and persist.
- In-race MENU pauses timing, zeroes controls and returns Home without
  destroying GameSim; camera/gear/handbrake remain functional.
- No decorative-only buttons remain; Race is honestly marked COMING LATER.

## 2. Import popup

New `ios/ACImportPopup.h/.m`: AC-styled modal with title
`IMPORT ASSETTO CORSA CONTENT`, subtitle, explanation, progress bar and
CANCEL / CHOOSE FOLDER buttons. States: Ready → Folder Selected → Importing →
Completed / Failed. CHOOSE FOLDER presents a real `UIDocumentPickerViewController`
for `public.folder`. The picked security-scoped URL is kept active for the whole
copy, validated (`content/cars` + `content/tracks`, or `cars` + `tracks`,
including the `AC-iOS` subfolder and `content` root), then files are copied
one-by-one into `Documents/AC-iOS/content/…` on a background queue with
progress on the main thread. Cancellation, bad structure and copy errors are
reported in plain language. On success, counts of imported cars/tracks are
shown and the in-app lists refresh immediately. Nothing is downloaded and the
original game folder is never modified.

## 3. Content expansion (local pack only, no assets in Git)

Source install: `D:\Games\assettocorsa`, unchanged.
Local pack: `content_pack/content` (git-ignored), manifest updated by
`scripts/add_phase11_7_content.py`.

### Added cars (exact versions verified via ui/ui_car.json)

| Folder | Real name | Verification |
|---|---|---|
| `ks_nissan_370z` | Nissan 370Z Nismo | Japanese Pack content present, real 5× KN5 + data.acd + bank |
| `ks_toyota_ae86` | Toyota AE86 | standard version (NOT drift/tuned), real files |
| `ks_ford_gt40` | Ford GT40 | Dream Pack 2 content present, real files |
| `bmw_m3_e92_drift` | BMW M3 E92 drift | drift version (NOT plain E92) |
| `ks_audi_sport_quattro` | Audi Sport quattro | standard (NOT S1 E2 / rally) |

No requested car was unavailable; no mods or downloads were used.

### Added track

`trento-bondone` — verified in the local install. It is an **A2B Hill Climb**,
NOT a rally stage. No genuine rally special stage exists in the local install,
so this is the documented alternative. Geometry, `data/`, `ui/ui_track.json`,
`map.png` and textures were copied.

### Integrity / real-engine load

All 5 new cars have 5 KN5 files, `data.acd`, an `.sfx/*.bank`, `ui/ui_car.json`
and 4 tyre shadows. Trento-Bondone has its KN5, 9 data files and UI metadata.

`scripts/phase11_7_render_check.py` ran the real upstream `full_frame` example:

```text
[OK] ks_nissan_370z__magione         png 973994 B
[OK] ks_toyota_ae86__magione         png 959496 B
[OK] ks_ford_gt40__magione           png 995205 B
[OK] bmw_m3_e92_drift__magione       png 973944 B
[OK] ks_audi_sport_quattro__magione  png 946916 B
[OK] lotus_elise_sc__trento-bondone  png 996460 B
```

Original 3 cars and 2 tracks preserved; pack now has 8 cars / 3 tracks / 837
files (~1.66 GiB). Logs: `phase11_7/render_checks/`.

## 4. Garage / browser

Garage reads real folder names from the imported content root. Names come from
`ui/ui_car.json` via a lenient regex (AC writes raw newlines, strict JSON fails).
Thumbnails come from the user's own `ui/dlc_preview.png`, `ui/preview.png` or
`logo.png`, downscaled to 84×48 and cached. No full KN5 is loaded for cards.
Track list uses `ui/ui_track.json`; Trento-Bondone is labeled `(Hill Climb)`.
After import, caches are cleared and lists refresh without reinstalling.

## 5. Memory / performance safety

Phase 10 BC fallback, 1 MP texture cap, downsampling and mip generation are
unchanged. FPS limiter and 333 Hz physics independence are unchanged. No new
GPU resources are created by menu screens or thumbnails; only small UI images
are cached. No all-cars-at-once load.

## 6. Tests / verification

```text
python scripts/phase11_7_render_check.py → 6/6 OK (real AC engine)
python scripts/add_phase11_7_content.py → 8 cars, 3 tracks, 837 files
python scripts/verify_ios_project.py → 52/52 PASS
python scripts/prepush_audit.py → PASS
cargo tests (Phase 8–11): 42 + 9 PASS
```

## 7. Device validation

The popup, copied content and new cars/tracks have **not yet been exercised on
the iPhone**. Real-device validation: **NOT CONFIRMED**.

## Build / artifacts

- Commit `179adc3` (feature), CI `44597749846` — **SUCCESS** on `macos-26-intel`.
- IPA: `C:\Users\User\Desktop\AC-iOS-content-pack\AC-iOS-Prot-unsigned.ipa`
  - Size **4,358,164 B**, SHA-256
    `e7b16ae0b79c7f4bec87735ba59333f167d2ba9a2d28deb376541783181534f0`
  - audit: `UNSIGNED IPA STRUCTURALLY VALID`
- Previous Phase 11 build preserved as
  `AC-iOS-Prot-unsigned-PrePhase11.7-WORKING-backup.ipa` (`d34ca0cf…`).
- Updated local Content Pack:
  `D:\opencode-sandbox\ac-ios-port\content_pack\content` (8 cars, 3 tracks).
- Checkpoint before: `checkpoint/before_phase11_7/`; after: `checkpoint/after_phase11_7/`
- Patch: `patches/phase11_7/`
