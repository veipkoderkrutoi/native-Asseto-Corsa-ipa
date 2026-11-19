# HANDOFF — Assetto Corsa iOS Port (Phase 11.7 Functional UI + Content)

GitHub:
- Latest release: `v0.11.7-phase11.7` — unsigned IPA + release notes:
  https://github.com/veipkoderkrutoi/native-Asseto-Corsa-ipa/releases/tag/v0.11.7-phase11.7
- Content pack instructions for other agents:
  `docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md`
- README обновлён под текущее состояние (старый текст про «нет IPA» удалён).

## ГДЕ ВСЁ НАХОДИТСЯ

- Проект: `D:\opencode-sandbox\ac-ios-port`
- GitHub: `veipkoderkrutoi/native-Asseto-Corsa-ipa`, ветка `main`
- Рабочий стол: `C:\Users\User\Desktop\AC-iOS-content-pack`
  - `AC-iOS-Prot-unsigned.ipa` — **сборка Phase 10 (Jetsam fix)**, CI `44548143436` success, SHA-256 `f4cd29aabcc713d83c124a2b3729a5298d82bde3444e3a3f11d4ea4ca9172d6e`, 4,321,713 B, аудит PASS.
  - `AC-iOS-Prot-unsigned-PrePhase10-WORKING-backup.ipa` — предыдущая Phase 9, SHA `1a1f017e…`.
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

## PHASE 9 GLOW UP — сделано локально

- ГРАФИКА: на iOS Metal нет `TEXTURE_COMPRESSION_BC`; `kgl_wgpu.rs::create_texture`
  возвращал ошибку, а `texture.rs` молча давал пустую текстуру → чёрная земля и
 _missing trees_. Добавлен CPU-декодер DXT1/3/5 (и BC4/5) в `texture_fallback.rs`
  с загрузкой оригинальных texels как RGBA8/RGBA8-SRGB. Счётчики
  `TEXTURE_STATS` + FFI `ac_ios_texture_stats`.
- АУДИО: FMOD-банки есть в контенте, но FMOD iOS SDK недоступен — **не заявляем**
  original audio. Реализован AVAudioEngine + AVAudioSourceNode с синтезированным
  звуком, управляемым РЕАЛЬНОЙ телеметрией (rpm/throttle/brake/speed/gear),
  atomic FFI, громкость/mute, interruption/background handling. Всё помечено
  как diagnostic synth.
- UI: слайдеры master/engine/effects + mute в Settings; диагностика показывает
  audio status и texture counters. `project.yml` линкует AVFoundation/AudioToolbox.
- Тесты: 42 lib (40 pass, 2 ignored), iOS cargo check PASS, verify 52/52,
  prepush PASS. Отчёт `phase9/PHASE9_GLOWUP_REPORT.md`, патч
  `patches/phase9_glowup/`, чекпоинт `checkpoint/before_phase9/` и `after_phase9_glowup/`.
- Новая IPA собрана (см. выше); предыдущая рабочая сохранена как
  `AC-iOS-Prot-unsigned-PrePhase9-WORKING-backup.ipa`.
- **Новая IPA ещё не проверена на iPhone** — аудио/графику нужно слушать/смотреть
  после установки. В Settings→Diagnostics видны texture counters и audio status.

## PHASE 10 — JETSAM FIX

- Реальный вылет на iPhone (3 нажатия Drive, полный syslog):
  `memorystatus: killing_specific_process pid … [ac-ios-port] (per-process-limit 100 5s)
  3163044KB`, exit `domain:jetsam(1) code:per-process-limit(7)`. **Не panic, не SIGABRT, не wgpu, не аудио.**
- Причина: Phase 9 CPU-декод BC → RGBA8 без ограничения памяти; imola ~3.68 GB
  декодированных текстур при лимите ~3 GB.
- Фикс: `texture_fallback.rs` — `BC_FALLBACK_MAX_PIXELS = 1024*1024`,
  `bc_fallback_target()`, `downsample_rgba()`, `rgba_with_mips_format()`;
  декод только level 0 + downscale + mip. Крупные текстуры displaying
  в уменьшенном разрешении (честно залогировано). Регрессия: 44 теста,
  42 PASS / 2 ignored; iOS cargo check PASS; verify 52/52; prepush PASS.
- Отчёт `phase10/PHASE10_REPORT.md`, патч `patches/phase10/`, чекпоинты
  `checkpoint/before_phase10/`, `after_phase10/`.
- Raw syslog с PII в `phase10/crash_forensics/` — НЕ коммитить (audit исключает).
- **REAL DEVICE DRIVE VALIDATION: NOT CONFIRMED** — нужно поставить новую IPA.

## PHASE 11 — MOBILE EXPERIENCE

- Новый UI: Home/Garage/Tracks/Game Modes/Settings + in-race HUD и timing panel.
  Стиль AC: графит/чёрный, красный акцент, безопасные области respecting.
- Игровые режимы: Practice/Time Attack/Hotlap/Free Drive выбираемы; Race — COMING LATER.
- **Time Attack:** использует РЕАЛЬНЫй AC lap timer (`LapView.current_ms/last_ms/best_ms/laps/valid/cuts`)
  через `ac_ios_core_lap_state`; текущий круг — monotonic `mach_absolute_time`.
  PB хранится пер car|track в NSUserDefaults, принимается tested Rust rule.
- **FPS limiter:** Auto/30/40/45/60 → `MTKView.preferredFramesPerSecond`; физика
  НЕ замедляется (333 Hz fixed step). Thermal serious/critical → 30 через публичный API.
- Settings: FPS, аудио, sensitivity/deadzone, button scale, pedal layout, HUD,
  diagnostics, game mode, units, auto shifter — всё сохраняется и применяется.
- Новые файлы: `ios/ACSettings.{h,m}`, `ios/ACTiming.{h,m}`, `rust/.../phase11.rs`.
- Тесты: rustyac-render 42 PASS, ac-ios-runtime 9 PASS, iOS check PASS, verify 52/52,
  prepush PASS. REPORTs: `phase11/*.md`. Патч `patches/phase11/`.
- IPA Phase 11 готова: CI `44560868971` success, SHA `d34ca0cf…`, 4,346,470 B.
  BUILD FIX: `phys_footprint` взят из `task_vm_info` (не `mach_task_basic_info`).
- **REAL DEVICE VALIDATION: NOT CONFIRMED** — нужна установка IPA и проверка
  меню/Time Attack/FPS cap/звука. Старая IPA сохранена как PrePhase11 backup.

## PHASE 11.7 — FUNCTIONAL UI + CONTENT

- Все кнопки菜单/настроек/гаража/трасс работают; выбор передаётся в GameSim
  folder name'ом (одинаковый ID в UI и `ac_pal_bridge_open_session`).
- Новый `ACImportPopup`: модальный AC-стиль, UIDocumentPicker для папки,
  валидация `content/cars` + `content/tracks` (или `cars`/`tracks`, в т.ч.
  AC-iOS подпапка), security-scoped access, копирование файл-за-файлом с
  прогрессом, состояния Ready/Selected/Importing/Completed/Failed.
- Контент-пак (LOCAL, git-ignored): +5 машин (ks_nissan_370z, ks_toyota_ae86,
  ks_ford_gt40, bmw_m3_e92_drift, ks_audi_sport_quattro) + трасса
  trento-bondone (**Hill Climb, НЕ rally stage**). Итого 8 машин / 3 трассы /
  837 файлов / ~1.66 GiB. Все DLC присутствовали локально, скачиваний нет.
- Реальный `full_frame` load: 6/6 OK (5 новых машин @ magione + lotus @ trento).
- Garage показывает РЕАЛЬНЫЕ имена из ui_car.json и превью из пользовательского
  контента (84×48, кэш), без загрузки KN5 ради карточек.
- IPA: CI `44569542332` success, SHA `472307943e…`, 4,358,287 B; старая IPA
  сохранена как `AC-iOS-Prot-unsigned-PrePhase11.7-WORKING-backup.ipa`.
- **REAL DEVICE VALIDATION: NOT CONFIRMED** — popup/импорт/новый контент нужно
  проверить на iPhone.

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
