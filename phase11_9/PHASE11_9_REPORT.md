# Phase 11.9 — Complete content dependency audit

## 1. Current failure — exact cause

`Documents/AC-iOS/content/objects3D/cubemap_model.kn5: No such file or directory`.

- The file **does** exist in the original install
  (`D:\Games\assettocorsa\content\objects3D\cubemap_model.kn5`) and in the local
  pack. It is **not** in `driver-fix.zip`.
- It is requested by `rustyac-render/src/cubemap.rs:140-147`:
  `load_static_cubemap_model()` prefers a track-local model and otherwise loads
  `<game>/content/objects3D/cubemap_model.kn5`. It is required for the sky.
- The real systemic cause: the importer copied only a hand-written whitelist of
  folders (`cars`, `tracks`, later `system`, `driver`, `texture`…). Any resource
  the renderer needs from another folder (here `objects3D`) was missed. Fixing
  files one by one could never finish.

## 2. Complete dependency audit

Two complementary sources were used, both from the vendored engine:

1. `rustyac-web::content::files_of_picture(root, car, track, layout)` — the
   planned superset (shaders, cfg, textures, objects3D, fonts, GUI, driver,
   skins, sfx, weather, car and track folders).
2. `full_frame --files` — the files the **real renderer actually reads** for a
   drive. Generated with
   `scripts/phase11_9_build_requirements.py` via a new host example
   `crates/rustyac-web/examples/generate_dependency_manifest.rs`.

Result: **24 combinations** (8 cars × 3 tracks), all loaded successfully with
the real engine (24/24 OK, zero failures):
- required union: **454 files**
- optional/planned superset: ~1,000 extra files per combo
- 6 required font files were missing from the local pack and were copied.
- `content/requirements.json` (relative paths only, 1.48 MB) is shipped in the
  app bundle; no game assets are committed or uploaded.

## 3. Content Preflight Validator (new)

`ios/ACContentValidator.h/.m`:

- loads `content_requirements.json` from the bundle;
- for the selected `car|track`, checks every required path under the resolved
  content root with `NSFileManager`;
- classifies `content/driver/*.kn5` as **optional** (renderer has a safe
  no-driver fallback), everything else actually read is **required**;
- logs:
  `[PREFLIGHT] Selected car/track`, `Required resources`, `Existing resources`,
  `Missing resources`, full relative path for each missing dependency, and
  `Validation result: PASS/FAIL`.

`driveTapped` now validates **before** creating a GameSim session. On FAIL it
shows a compact, closable panel:
`CONTENT VALIDATION FAILED — Missing N required of M checked resources` with a
scrollable list of every missing path. DRIVE is not attempted. On PASS the
existing session start runs unchanged. The panel has a working CLOSE button and
never covers the menu permanently.

## 4. Importer fixed once and properly

`ios/ACImportPopup.m`:

- still copies the selected cars/tracks and `system/`;
- now also copies shared folders `driver`, `texture`, `fonts`, `objects3D`,
  `weather`;
- additionally walks the **dependency manifest** and copies every required file
  that is missing or whose size differs — idempotent, so a second import only
  adds what is absent (no 1.9 GB re-copy, no damage to existing content);
- supports the case where the user selected a `content` folder directly;
- logs `[PREFLIGHT] Importer added N manifest dependencies`.

## 5. Resource fallback

- `content/objects3D/cubemap_model.kn5` is required for the sky; no fake model is
  substituted. The validator catches it before DRIVE and shows the exact path.
- `content/driver/*.kn5` remains optional thanks to the Phase 11.8 fallback in
  `driver.rs` (`Ok(None)` + `[RENDERER] Driver asset load result: missing …`).
- Original assets were not modified; protected files are not in Git/CI.

## 6. Incremental content patch

`C:\Users\User\Desktop\AC-iOS-content-pack\content-dependencies-fix.zip`
— **45,602,601 B (43.5 MiB), 228 files**: every *shared* required dependency
(objects3D, fonts, driver, texture, system, weather…) from the manifest.
Drop it onto the device, unzip, merge into `Documents/AC-iOS/` — this adds
`content/objects3D/cubemap_model.kn5` and all other shared resources without
re-uploading cars/tracks.

## 7. Tests

```text
scripts/phase11_9_build_requirements.py → 24/24 combos OK, 0 failures
scripts/phase11_9_preflight_test.py     → PASS (454 required files, all combos)
cargo test -p rustyac-render --features backend-wgpu --lib --offline
  → 44 passed; 0 failed; 2 ignored
cargo test -p ac-ios-runtime --lib --offline → 9 passed; 0 failed
cargo check -p ac-ios-runtime --target aarch64-apple-ios → PASS
python scripts/verify_ios_project.py → 52/52
python scripts/prepush_audit.py → PASS
```

Case-sensitivity was checked: exact lowercase/uppercase names match between
Windows, manifest, pack and iOS paths. Phase 10 memory fix untouched.

## 8. Device validation

The `cubemap_model.kn5` error was observed on the real iPhone by the user.
This build's validator and importer are locally verified but:

**REAL DEVICE DRIVE VALIDATION: NOT CONFIRMED** for this build.

## Build / artifacts

- Checkpoint before: `checkpoint/before_phase11_9/`
- Patch: `patches/phase11_9/`
- Manifest: `phase11_9/content_requirements.json` (also `ios/content_requirements.json`)
- Commit / CI / IPA: filled in after CI.
