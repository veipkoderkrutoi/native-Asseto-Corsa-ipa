# Phase 7 — first playable content pack (COMPLETE)

## 1. Selected content (all original, no mods)

Source install: `D:\Games\assettocorsa` (AC 1.16.2, 21 tracks, 178 cars).

| Role | Identifier | Notes |
|---|---|---|
| Control track | `magione` | 298 MB main KN5, road circuit |
| Second track | `imola` | 384 MB main KN5, road circuit |
| Control car | `lotus_elise_sc` | 41 MB KN5, 4 LOD, skin 0_racing_green |
| Car 2 | `bmw_m3_e30` | 37.7 MB KN5, 4 LOD |
| Car 3 | `abarth500` | 42.5 MB KN5, 4 LOD |

All cars have `data.acd` + `collider.kn5`; all tracks have `models.ini`.

## 2. Load status — every combination

`scripts/phase7_render_check.py` used the **already-built** upstream `full_frame`
example (no Cargo rebuild), AC_ROOT = original install:

| Car @ Track | Result | Wall | PNG bytes | Files read |
|---|---|---:|---:|---:|
| lotus_elise_sc @ magione | OK | 12.2s | 992,742 | 181 |
| bmw_m3_e30 @ magione | OK | 8.7s | 959,380 | 180 |
| abarth500 @ magione | OK | 8.9s | 1,007,797 | 189 |
| lotus_elise_sc @ imola | OK | 13.4s | 982,759 | 189 |
| bmw_m3_e30 @ imola | OK | 7.0s | 934,769 | 185 |
| abarth500 @ imola | OK | 7.2s | 994,207 | 194 |

Every run produced a real rendered PNG and a kgl log with real draw calls.
Example summary: *"track models: 2 files, 95 textures, 53 materials; car model
4 levels of detail"*.

## 3. Physics / real GameSim — every combination

`rust/ac-ios-runtime/examples/phase7_content_selftest.rs` builds a real
`GameSim` for each pair from the content pack, steps **900 real physics ticks**
(2.7 s at 333 Hz) with throttle + steering injected through the same
`DriverSource` path as the iOS bridge (after the 470-tick spawn sequence):

| Car @ Track | Speed | RPM | Gear | Moved | Wheel spin | Result |
|---|---:|---:|---:|---:|---:|:--:|
| lotus_elise_sc @ magione | 18.11 km/h | 2240 | 2 | 3.04 m | 16.6 rad/s | OK |
| bmw_m3_e30 @ magione | 17.43 km/h | 1852 | 2 | 2.85 m | 16.2 | OK |
| abarth500 @ magione | 11.31 km/h | 1526 | 2 | 1.53 m | 10.4 | OK |
| lotus_elise_sc @ imola | 20.34 km/h | 2516 | 2 | 3.51 m | 18.6 | OK |
| bmw_m3_e30 @ imola | 19.99 km/h | 2093 | 2 | 3.35 m | 18.5 | OK |
| abarth500 @ imola | 13.75 km/h | 1625 | 2 | 1.98 m | 12.5 | OK |

This proves a **real controllable simulation**, not a static scene.

## 4. Content pipeline / safe import

- `scripts/build_content_pack.py` derives the pack from the **275 unique files
  actually read** by the renderer (not a guessed copy): 30 KN5, 52 DDS, 70 FXO,
  67 INI, 21 PNG, 19 Ksanims, 3 ACD, 3 KNH.
- Pack: `content_pack/` — **927.4 MiB** uncompressed, transfer zip **446.6 MiB**.
- `scripts/verify_content_pack.py` re-rendered **all 6 combinations with
  AC_ROOT pointing at the pack only** (original install not used): 6/6 OK.
  The pack is self-contained.
- Import on iOS: user unzips the transfer zip in the Files app into an `AC-ios`
  folder and selects that folder with the existing UIDocumentPicker. The app's
  `ContentLocator` already expects `content/cars/...` and `content/tracks/...`,
  which the pack preserves. No renderer or physics changes were needed.
- `manifest.json` in the pack records SHA-256 of every file.

**No game assets were committed or uploaded**: `content_pack/`, the transfer zip
and per-combination render outputs are git-ignored; `prepush_audit.py` PASS and
`git status` clean of `.kn5/.acd/.dds`.

## 5. Memory (Windows host measurement — NOT iPhone 13 Pro Max)

`scripts/measure_pack_memory.py` sampled `GetProcessMemoryInfo` of the renderer:

| Car @ Track | Peak working set | Peak commit |
|---|---:|---:|
| lotus_elise_sc @ magione | 2039 MB | 2033 MB |
| bmw_m3_e30 @ magione | 2428 MB | 2422 MB |
| lotus_elise_sc @ imola | 2448 MB | 2443 MB |
| bmw_m3_e30 @ imola | 2451 MB | 2447 MB |

Texture quality was **not** reduced. These are host numbers; iPhone memory
behaviour (unified memory, texture compression, Metal heaps) is unmeasured.

Track/car change behaviour: the runner's `full_frame` process is short-lived;
per-session renderer teardown is handled by `ac_ios_render_destroy()` →
`ac_ios_metal_destroy()` → `ac_pal_bridge_shutdown()` in the app. Repeated-load
stability on device remains untested.

## 6. Changed / added files

- New: `scripts/phase7_render_check.py`, `build_content_pack.py`,
  `verify_content_pack.py`, `measure_pack_memory.py`,
  `rust/ac-ios-runtime/examples/phase7_content_selftest.rs`.
- Updated: `.gitignore`, `scripts/prepush_audit.py`, `scripts/list_tracked_files.py`.
- No renderer, physics, input or existing GitHub Actions changes.

## 7. Local test results

- 6/6 render combinations OK (real PNG + kgl log).
- 6/6 pack-only render combinations OK (self-contained pack).
- 6/6 real GameSim physics combinations OK.
- pre-push audit PASS; tracked set 776 files / 35.8 MiB (no game assets).

## 8. iOS IPA readiness

The existing working GitHub Actions workflow is unchanged. Phase 7 adds no
native source changes to the app, so the previously proven unsigned IPA build
remains valid. The content pack is imported separately by the user and is
**never** part of the IPA or CI artifacts. No iPhone device test was performed;
this report does not claim on-device gameplay.
