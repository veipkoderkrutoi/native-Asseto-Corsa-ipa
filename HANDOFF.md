# HANDOFF — AC iOS Port (Prepared for /compact)

## 0. ГДЕ ВСЁ

- Project: `D:\opencode-sandbox\ac-ios-port`
- Git mirror (has `.git`): `D:\opencode-sandbox\gha-repo`
- GitHub: `veipkoderkrutoi/native-Asseto-Corsa-ipa`, branch `main`
- HEAD: `2e1af91` (pushed). Previous: `72cf4c8`, `559cc2a`, `fed9d27`, `143dfce`.
- Release: `v0.11.7-phase11.7` — unsigned IPA asset.
- Desktop: `C:\Users\User\Desktop\AC-iOS-content-pack`
- Original AC install (READ ONLY): `D:\Games\assettocorsa` (AC 1.16.2)
- iPhone: 13 Pro Max, iOS 27.0, bundle `com.aciosprototype.ac-ios-port.GUM74PUV3G`

## 1. ТЕКУЩИЙ РАБОЧИЙ АРТЕФАКТ

### IPA (код последний раз менялся в Phase 11.9)
`C:\Users\User\Desktop\AC-iOS-content-pack\AC-iOS-Prot-unsigned.ipa`
- Size **4,537,673 B**
- SHA-256 `5874bde2c837b70cd60c38beaa1b9c8dd0d664ecc9cbf46bfaa69fde01767f4a`
- CI run `44715522637` success (`macos-26-intel`)
- Audit: `UNSIGNED IPA STRUCTURALLY VALID`
- В release asset тот же SHA (проверено скачиванием обратно).
- Backup IPA files рядом: `*-Pre11.9-WORKING-backup.ipa`, `*-Pre11.8-…`, `*-PrePhase11.7-…` и др. НЕ удалять.

### ПОЛНЫЙ_CONTENT ПАК (собран Phase 11.10) — ГЛАВНОЕ
`C:\Users\User\Desktop\AC-iOS-content-pack\AC-iOS-full\AC-iOS`
- 1.94 GiB, 1864 files, 8 cars / 3 tracks, 216 shaders/win.
- 454 required Preflight files → **0 missing**.
- `pack_report.json` = size+SHA-256 каждого файла; `README.txt` внутри.
- Это drop-in замена `Documents/AC-iOS`: копировать ЦЕЛУЮ папку `AC-iOS` через Finder/iTunes File Sharing. **Никаких patch-merge больше не делать.**
- Собрано скриптом `scripts/build_full_ios_pack.py` (в git, commit `2e1af91`).

Мелкие патчи桌上 всё ещё есть (`system-fix.zip`, `driver-fix.zip`, `content-dependencies-fix.zip`, `content-assets-fix-11.10.zip`) — они подмножества полного пака, **больше не нужны**, если скопирован `AC-iOS-full`.

## 2. ЧТО УЖЕ РАБОТАЕТ / ИСТОРИЯ ФИКСОВ

- Phase 8.1: sampler layout/descriptor consistency (`kgl_wgpu.rs`, pure helpers). НЕ откатывать.
- Phase 8.2: anisotropy vs filtering, `SamplerConfig`, aniso=1 on NonFiltering. НЕ откатывать.
- Phase 9: AVAudioEngine diagnostic synth (NOT original FMOD banks), AC visual `RaceLook` from race.ini, camera `f1()` (cockpit).
- Phase 10: Jetsam fix — CPU BC fallback capped at 1 MP/texture + downsample + mips in `texture_fallback.rs`. **НЕ увеличивать лимит.**
- Phase 11: AC-styled UI, Time Attack on REAL AC lap timer (`LapView`), FPS limiter (Auto/30/40/45/60) via `MTKView.preferredFramesPerSecond`, thermal `ProcessInfo.thermalState` serious/critical→30. Physics stays 333 Hz fixed-step, FPS cap does NOT slow GameSim.
- Phase 11.7: functional menu (zero-frame bug fixed), import popup with real UIDocumentPicker, +5 DLC cars + Trento-Bondone.
- Phase 11.8: `content/driver` import + safe missing-driver fallback (`driver.rs` → `Ok(None)`), `[CONTENT]` logs, closable error overlay.
- Phase 11.9: complete dependency manifest + **Content Preflight Validator** (`ACContentValidator`, `ios/content_requirements.json`, 24 combos, 454 required paths) + manifest-driven incremental importer. Preflight BLOCKS Drive with exact missing list. NEVER disable/downgrade it.
- Phase 11.10: all 39 reported missing assets verified present in local pack; full pack rebuilt. Driver_60 remains optional.

### Известные ограничения (честно)
-Audio — синтезированный diagnostic sound, не оригинальные FMOD banks.
- Trento-Bondone = **Hill Climb / A2B**, НЕ rally stage.
- Race mode: COMING LATER (нет AI).
- Auto FPS = stable 60 cap, not adaptive thermal beyond serious/critical→30.
- Nissan log has nonfatal `CANNOT FIND DigitalLed mesh:GEO_LEDS_WATER_0` ( dashboards mesh inside car KN5, not external file; render exit 0 ).

## 3. ПРАВИЛА (НЕ НАРУШАТЬ)

1. CARGO_BUILD_JOBS=2 всегда. Artifacts on `D:`.
2. НЕ добавлять `.kn5/.acd/.bank/.dds/.fsb/.ipa/.zip` в Git/CI/release. `prepush_audit.py` MUST PASS.
3. `content_pack/`, `checkpoint/`, `phase10/crash_forensics/` git-ignored, не трогать.
4. НЕ отключать wgpu validation, catch_unwind panic diagnostics, Preflight validator, Phase 10 memory fix.
5. НЕ имитировать реальный device test. Пока пользователь не нажал Drive и не показал результат — писать NOT CONFIRMED.
6. При новой ошибке missing resource: НЕ добавлять файл точечно — пересобрать полный пак скриптом `build_full_ios_pack.py` после обновления `content_requirements.json` (источник: `full_frame --files` + `files_of_picture`, пример `crates/rustyac-web/examples/generate_dependency_manifest.rs`, скрипт `scripts/phase11_9_build_requirements.py`).
7. iPhone file system case-sensitive; проверять точный регистр путей.

## 4. ИНСТРУМЕНТЫ

```
# Git/GH
D:\tools\git\cmd\git.exe
D:\tools\gh\bin\gh.exe
repo: veipkoderkrutoi/native-Asseto-Corsa-ipa

# Cargo
%USERPROFILE%\.cargo\bin\cargo.exe
$env:CARGO_BUILD_JOBS='2'

# Tests
cargo test -p rustyac-render --features backend-wgpu --lib --offline   # 44 pass, 2 ignored
cargo test -p ac-ios-runtime --lib --offline                          # 9 pass
cargo check -p ac-ios-runtime --target aarch64-apple-ios
python scripts/verify_ios_project.py        # 52/52
python scripts/prepush_audit.py             # PASS
python scripts/phase11_9_preflight_test.py  # PASS
python scripts/phase11_10_validate.py       # PASS

# Rebuild the full pack
python scripts/build_full_ios_pack.py

# Device
python -m pymobiledevice3 crash ls
python -m pymobiledevice3 crash pull OUT --match ac-ios-port
python -m pymobiledevice3 syslog live --process-name ac-ios-port > log.txt
python -m pymobiledevice3 developer dvt screenshot out.png
python -m pymobiledevice3 developer core-device list-processes
```
Synthetic HID taps (`universal-hid-service tap`) DO NOT reach UIKit — просить пользователя нажать вручную.

## 5. СЛЕДУЮЩИЙ ШАГ

1. Пользователь копирует `AC-iOS-full\AC-iOS` в app Documents (заменяет старую папку), запускает IPA `5874bde2…`, жмёт DRIVE.
2. Если Preflight PASS и сцена грузится — зафиксировать успех, обновить отчёты.
3. Если Preflight FAIL с новыми путями — обновить dependency manifest через реальные `full_frame --files`, скопировать原文件 в `content_pack`, **пересобрать полный пак** `build_full_ios_pack.py`, не делать точечный патч.
4. Если crash — вытащить crash report/syslog, классифицировать (Jetsam/panic/EXC_BAD_ACCESS), НЕ guessing.

## 6. ОТЧЁТЫ / АРТЕФАКТЫ

- `phase8/PHASE8_1_REPORT.md`, `PHASE8_2_REPORT.md`, `PHASE8_REPORT.md`
- `phase9/PHASE9_GLOWUP_REPORT.md`, `NEXT_PHASE_REPORT.md`
- `phase10/PHASE10_REPORT.md`, `phase10/crash_forensics/` (local only)
- `phase11/PHASE11_REPORT.md`, `UI_REPORT.md`, `TIME_ATTACK_REPORT.md`, `PERFORMANCE_REPORT.md`
- `phase11_7/PHASE11_7_REPORT.md`, `phase11_8/PHASE11_8_REPORT.md`,
  `phase11_9/PHASE11_9_REPORT.md`, `phase11_10/PHASE11_10_REPORT.md`
- Patches: `patches/phase8_1`, `phase8_2`, `phase9`, `phase9_glowup`, `phase10`, `phase11`, `phase11_7`, `phase11_8`, `phase11_9`, `phase11_10`
- Checkpoints: `checkpoint/before_phase9`, `before_phase10`, `before_phase11`, `before_phase11_7`, `before_phase11_8`, `before_phase11_9`, `before_phase11_10`, `after_phase11_*`
- Content instructions for other agents: `docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md`
