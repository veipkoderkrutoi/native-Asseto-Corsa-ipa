# HANDOFF — Assetto Corsa iOS Port (Phase 8.2, after /compact)

## ГДЕ ВСЁ НАХОДИТСЯ

- Проект: `D:\opencode-sandbox\ac-ios-port`
- GitHub: `veipkoderkrutoi/native-Asseto-Corsa-ipa`, ветка `main`
- Рабочий стол: `C:\Users\User\Desktop\AC-iOS-content-pack`
  - `AC-iOS-Prot-unsigned.ipa` — **сборка Phase 8.2**, CI `44359519473` success, SHA-256 `6765c9c0ba869336db15b53489c81707199282329b6340c58a8e295c5256280f`, 4,301,011 B, аудит структуры PASS. Старая Phase 8.1 была `deb5da36...`.
  - `AC-iOS\` — папка контента (3 машины + 2 трассы, 927 МиБ)
- Оригинальная игра: `D:\Games\assettocorsa` (AC 1.16.2)
- CI-репозиторий-зеркало для коммитов: `D:\opencode-sandbox\gha-repo` (`.git` там)

## ЧТО РАБОТАЕТ

- Нативный iOS ARM64 staticlib `libac_ios_runtime.a`, wgpu/Metal, реальный AC-рендерер
- rustyAC GameSim с реальной физикой (333 Гц), 3 машины + 2 трассы
- Touch + GameController, камера, HUD с реальной телеметрией
- catch_unwind в `ac_ios_render_init` — panic показывает текст в UI вместо SIGABRT
- Memory instrumentation (`meminfo.rs`), `[MEMORY]` события в syslog
- GitHub Actions собирает IPA (раннер `macos-26-intel`)
- Контент импортируется через Files-app document picker или iTunes/Finder File Sharing

## ХРОНОЛОГИЯ ОШИБОК

1. **Phase 8.1** (исправлено, коммит `9d43650`, CI `44353393244` success):
   `Sampler binding 0 expects filtering = false but given a sampler with filtering = true`.
   Причина: layout `NonFiltering` (нет `FLOAT32_FILTERABLE` на Metal), sampler — Linear.
   Фикс: `sampler_filtering_type()` / `sampler_filter_mode()`, iOS → Nearest.

2. **Phase 8.2** (исправлено, новая IPA собрана и лежит на столе):
   `invalid filter mode for anisotropic clamp: nearest when anisotropic clamp is not 1 (it's 4)`.
   Причина: на iOS `kind 0` получал Nearest (из 8.1) + `anisotropy_clamp=4`.
   wgpu-core 30.0.1 `device/resource.rs:2288–2316`: aniso≠1 ⇒ все 3 фильтра Linear.
   Нельзя ставить Linear глобально — снова сломается Phase 8.1.
   Фикс: единый `SamplerConfig` + `sampler_config()` / `sampler_descriptor()`;
   на NonFiltering-пути aniso принудительно 1; Linear остаётся только на
   `filterable`-устройствах. 10/10 regression-тестов PASS, полный lib 37 PASS,
   ARM64 `cargo check` PASS. Отчёт `phase8/PHASE8_2_REPORT.md`.

**НЕ ПРОВЕРЕНО НА iPhone после Phase 8.2** — пользователь должен переустановить
новую IPA и нажать Drive.

## ПРАВИЛО ИЗ ИСТОЧНИКОВ wgpu 30.0.1 (не последней версии!)

- `wgpu-core-30.0.1/src/device/resource.rs:2288–2316` — aniso != 1 ⇒ min/mag/mipmap все Linear.
- Там же `:2353` — `sampler.filtering = min==Linear || mag==Linear`.
- Там же `:3145–3165` — `Filtering` → cmp=false; `NonFiltering` → filtering=false; `Comparison` → cmp=true.

## ИНСТРУМЕНТЫ

- `python -m pymobiledevice3 crash ls` / `crash pull DIR --match ac-ios-port`
- `python -m pymobiledevice3 syslog live --process-name ac-ios-port > log.txt`
- `python -m pymobiledevice3 developer dvt screenshot out.png`
- `python -m pymobiledevice3 developer core-device list-processes`
- `python -m pymobiledevice3 developer dvt launch <bundleID>`
- Bundle id на девайсе: `com.aciosprototype.ac-ios-port.GUM74PUV3G`
- Синтетические HID-тапы через `universal-hid-service tap X Y` НЕ долетают до UIKit
- GitHub CLI: `D:\tools\gh\bin\gh.exe`, git: `D:\tools\git\cmd\git.exe`
- Cargo: `%USERPROFILE%\.cargo\bin\cargo.exe`, всегда `CARGO_BUILD_JOBS=2`
- Команда тестов: `cargo test -p rustyac-render --features backend-wgpu --lib sampler_validation_tests`

## ВАЖНЫЕ ПРАВИЛА

- НЕ добавлять игровые ресурсы в Git/CI (pre-push аудит `scripts/prepush_audit.py` PASS)
- НЕ удалять старые чекпоинты
- НЕ менять workflow без нужды (сейчас `macos-26-intel` — работает)
- НЕ выдавать успех на iPhone без реального теста
- catch_unwind и wgpu validation НЕ отключать
- phase8.1-хелперы `sampler_filtering_type` / `sampler_filter_mode` НЕ откатывать

## СЛЕДУЮЩИЙ ШАГ

1. ✅ Закоммичено (`d5ace5a`), CI `44359519473` success, артефакт скачан, аудит структуры PASS, IPA на столе (старая Phase 8.1 заменена новой — это правильно).
2. Пользователь переустанавливает IPA → машина/трасса → Drive.
3. Если сцена появилась → закрыть Phase 8.2. Если новая ошибка → точный текст + `crash pull`, отдельный issue.

## ОТЧЁТЫ И АРТЕФАКТЫ

- `phase8/PHASE8_REPORT.md` — forensics (panic, не OOM)
- `phase8/PHASE8_1_REPORT.md`, `phase8/PHASE8_2_REPORT.md`
- `phase8/phase8_2_audit.log` — аудит всех точек создания sampler
- `phase8/CONTENT_INVENTORY.md`, `phase7/PHASE7_REPORT.md`
- `patches/phase8_1/`, `patches/phase8_2/`
- `checkpoint/after_phase8_1/`, `checkpoint/after_phase8_2/`
