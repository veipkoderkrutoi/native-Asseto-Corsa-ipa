# Hotfix 11.8 — missing driver asset

## 1. Cause (confirmed, not guessed)

- File exists in the user's install:
  `D:\Games\assettocorsa\content\driver\driver_no_HANS.kn5` (14,463,596 B),
  and also in the local pack `content_pack/content/driver/`.
- It is requested by `rustyac-render/src/driver.rs:185`: the car's
  `data/driver3d.ini [MODEL] NAME` selects `content/driver/<NAME>_B.kn5`, then
  the full `<NAME>.kn5`; `Kn5Io::load` at line 222 failed with
  `No such file or directory`.
- **The importer never copied `content/driver`** (it copied only `content/cars`,
  `content/tracks`, and since 11.7 `system/`). The iPhone's
  `Documents/AC-iOS/content/driver` therefore did not exist.
- Case sensitivity is fine: exact spelling `driver_no_HANS.kn5` matches on both
  Windows and iOS; content root was resolved from the app Documents URL.
- Additional gap found: the new cars use `driver_60.kn5` and `driver_80.kn5`,
  which were also absent from the old pack, plus 31 driver/crew skin textures.

## 2. Asset fix

- Complete `content/driver` from the user's install copied into the local pack
  (43 files, incl. `driver_no_HANS.kn5/_B`, `driver_60`, `driver_80`).
- 31 missing `content/texture/driver_*` and `crew_*` files copied.
- Manifest regenerated: 1,858 files, 43 driver files, total ~1.94 GiB.
- Small device patch created (no full re-import needed):
  `C:\Users\User\Desktop\AC-iOS-content-pack\driver-fix.zip` — 31.18 MiB, 57 files,
  containing `content/driver` (6 model files) + the 31 skin textures.

## 3. Importer fix (`ios/ACImportPopup.m`)

- Now also copies shared folders: `content/driver`, `content/texture`,
  `content/fonts`, `content/objects3D`, `content/weather` (with progress),
  alongside `system/` and the selected cars/tracks.
- Import result counts shared folders and warns in plain language if the source
  has no `content/driver`.
- Existing cars/tracks are never deleted.

## 4. Renderer error handling (`rustyac-render/src/driver.rs`)

- New tested pure helper `driver_candidate_files()` builds AC's candidate order
  (`_B` then full, or full only for HR).
- If **none** of the candidates exists, the renderer now logs
  `[RENDERER] Driver asset load result: missing — … continuing without a 3D driver`
  and returns `Ok(None)` — the same safe fallback rustyAC already uses when a car
  has no `driver3d.ini`. Car, track, physics, audio and the rest of the scene
  still load; no fake driver geometry is created.
- If a candidate exists it is loaded exactly as before.
- Regression tests added: `low_detail_model_falls_back_to_full_model`,
  `high_detail_only_tries_the_full_model`.

## 5. Diagnostics / overlay

`ios/GameViewController.m` now logs before renderer init (with container UUID
replaced by `~`):
```
[CONTENT] Content root: ~/Documents/AC-iOS
[CONTENT] Driver directory: ~/Documents/AC-iOS/content/driver (exists: true/false)
[CONTENT] Requested driver: resolved by renderer from the car's driver3d.ini; verifying driver_no_HANS.kn5
[CONTENT] Driver file exists: true/false
[CONTENT] Driver file size: ...
[RENDERER] Driver asset load result: OK/FAILED — ...
```
If `content/driver` is missing, DRIVE stops early with a clear message instead
of a generic renderer panic. The message overlay has a working `✕` close button
and no longer blocks the UI indefinitely.

## 6. Tests

```text
cargo test -p rustyac-render --features backend-wgpu --lib --offline
  → 44 passed; 0 failed; 2 ignored (46 total, +2 new driver tests)
cargo test -p ac-ios-runtime --lib --offline → 9 passed; 0 failed
cargo check -p ac-ios-runtime --target aarch64-apple-ios → PASS
python scripts/verify_ios_project.py → 52/52
python scripts/prepush_audit.py → PASS
```

Phase 10 memory fix untouched: BC 1 MP cap, downsampling and mip generation
are unchanged.

## 7. Device validation

The error was reported from the real iPhone. The fix is locally verified but
**REAL DEVICE DRIVE VALIDATION: NOT CONFIRMED** for this build.

## Build / artifacts

- Checkpoint before: `checkpoint/before_phase11_8/`
- Patch: `patches/phase11_8/`
- Commit / CI / IPA: filled in after CI.
