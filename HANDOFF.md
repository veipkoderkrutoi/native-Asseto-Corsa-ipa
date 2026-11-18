# HANDOFF — Assetto Corsa iOS Port (NEXT PHASE: UX/Controls)

## ГДЕ ВСЁ НАХОДИТСЯ

- Проект: `D:\opencode-sandbox\ac-ios-port`
- GitHub: `veipkoderkrutoi/native-Asseto-Corsa-ipa`, ветка `main`
- Рабочий стол: `C:\Users\User\Desktop\AC-iOS-content-pack`
  - `AC-iOS-Prot-unsigned.ipa` — **сборка NEXT PHASE (новый UI)**, CI `44368896612` success, SHA-256 `21b58d2d4f53cd9cde6dfcf2924728d15838e09b8152c6bc27fb672b71b2e3ac`, 4,317,357 B, аудит PASS.
- `AC-iOS-Prot-unsigned-Phase8.2-WORKING-backup.ipa` — предыдущая рабочая, SHA `6765c9c0…`. НЕ удалять, пока новый UI не подтверждён на iPhone.
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

**Phase 8.2 IPA ПОДТВЕРЖДЕНА РАБОТАЮЩЕЙ на iPhone** (пользователь видел реальную
AC-сцену, машина едет, телеметрия/камеры работают). Скриншот:
`phase8/iphone_scene_2026-11-18.png`.

## NEXT PHASE (UX/Controls) — сделано локально, IPA в процессе

- `ios/GameViewController.m` переписан: видимый аналоговый руль, GAS/BRAKE
  педали, GEAR+/-, HANDBRAKE, CAMERA, MENU; компактное меню 32% ширины;
  HUD и отдельная выключаемая debug-панель (FPS, render ms, Metal features).
- Инверсия: в FFI/физике знака нет (`feed.rs:43 positive = right`); источник —
  старый абсолютный touch-X без нейтрали. Новый руль — относительный drag.
- Камера: `render.rs::camera_next()` теперь вызывает upstream `f1()` — доступен
  настоящий cockpit с оригинальным 3D-рулём.
- Графика: `render.rs` теперь берёт `RaceLook::of(race.ini)` (sun/weather/
  sun_animation/groove) как Windows full_frame — раньше было захардкожено
  `sun_angle=0`, `weather=""`, из-за чего не применялась AC-погода.
- Локально: sampler 10/10, lib 37, iOS cargo check PASS, C-тесты PASS,
  verify_ios_project 52/52, prepush audit PASS.
- Отчёт `phase9/NEXT_PHASE_REPORT.md`, патч `patches/next_phase/`,
  чекпоинты `checkpoint/before_next_phase/`, `checkpoint/after_next_phase/`.
- **Новый UI на iPhone ещё не проверен** — нужно поставить новую IPA.

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

1. Phase 8.2: ✅ `d5ace5a`, CI `44359519473` success, IPA на столе.
2. NEXT PHASE: закоммитить, собрать новую IPA, проверить touch/меню/HUD/cockpit/графику на iPhone. Старую рабочую IPA НЕ удалять до успеха новой.
2. Пользователь переустанавливает IPA → машина/трасса → Drive.
3. Если сцена появилась → закрыть Phase 8.2. Если новая ошибка → точный текст + `crash pull`, отдельный issue.

## ОТЧЁТЫ И АРТЕФАКТЫ

- `phase8/PHASE8_REPORT.md` — forensics (panic, не OOM)
- `phase8/PHASE8_1_REPORT.md`, `phase8/PHASE8_2_REPORT.md`
- `phase8/phase8_2_audit.log` — аудит всех точек создания sampler
- `phase8/CONTENT_INVENTORY.md`, `phase7/PHASE7_REPORT.md`
- `patches/phase8_1/`, `patches/phase8_2/`
- `checkpoint/after_phase8_1/`, `checkpoint/after_phase8_2/`
