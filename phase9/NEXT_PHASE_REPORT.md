# NEXT PHASE — Gameplay UX, Controls & Visual Polish

## 0. Зафиксированное рабочее состояние

- Git до изменений: `42f7b39` (main), рабочее дерево чистое.
- Чекпоинт: `checkpoint/before_next_phase/` (включая рабочую IPA Phase 8.2
  `AC-iOS-Prot-unsigned-WORKING-Phase8.2.ipa`, SHA `6765c9c0…`).
- Загрузка контента не менялась: Files/File Sharing → `Documents/AC-iOS`,
  `content/cars` и `content/tracks`, выбор в меню, `ac_pal_bridge_open_session()`.
- Подтверждено пользователем: **реальная AC-сцена на iPhone работает**, машина
  движется, телеметрия и камеры работают. Скриншот:
  `phase8/iphone_scene_2026-11-18.png`.
- Phase 8.1/8.2 sampler-логика не тронута.

## 1. Исходные проблемы (по скриншоту)

1. Интерфейс — отладочная панель: синие текстовые ссылки, чёрный прямоугольник
   списка на ~45% ширины, жёлтые строки диагностики поверх кнопок.
2. Нет видимых органов управления: руление «по координате пальца в левой
   половине экрана», педали — невидимые зоны, нет обратной связи.
3. Нет отдельного HUD и отдельной debug-панели.
4. Камера циклировала только `next_drivable()` — настоящий cockpit с оригинальным
   салоном/рулём был недостижим.
5. Картинка отличалась от Windows-референса (`phase7/render_checks/…`):
   чёрная земля, плоские цвета, отсутствие деревьев.

## 2. Touch-управление (приоритет №1) — сделано

Новый `ios/GameViewController.m`:

- `ACWheelControl` — большой видимый руль (150–158 pt) снизу слева. Аналоговое
  управление **относительно точки касания**, плавное изменение угла, визуальный
  поворот на ~150°, возврат в нейтраль при отпускании (настраивается в Settings).
- `ACPedalControl` — две отдельные крупные педали (64×126 pt) снизу справа:
  BRAKE (внутренняя) и GAS (внешняя). Значение 0..1 от вертикального положения
  пальца, заполнение педали цветом, сброс в 0 на `touchesEnded`,
  `touchesCancelled`, потере фокуса и смене геймпада.
- Отдельные крупные кнопки: GEAR -, GEAR +, HANDBRAKE, CAMERA, MENU, AUTO/MANUAL.
- Все inputs читаются напрямую из control'ов в `pollInput()`; при открытом меню
  steer/throttle/brake принудительно 0 — случайного «зажатого газа» быть не может.
- GameController-ветка сохранена без изменений (left stick / RT / LT / A / X / B / Y).

Проверка полного цикла требует реального устройства — запрограммированные
переходы (нажал→отпустил, руль+газ одновременно, сброс при cancel) реализованы
в самих UIControl, но **физическое подтверждение на iPhone пока не получено**.

## 3. Инверсия управления — трассировка и результат

Путь значения: `ACWheelControl`/GameController → `ACIosInputState.steer` →
`ac_ios_set_input` / `ac_pal_bridge_set_controls` → `ac_bridge_step` →
`ac_ios_core_session_set_input` → `CarControls.steer` → физика.

- `ios_bridge.m:22` — только копирование структуры, знак не меняется.
- `core/ac_pal_bridge.c:160-177,183` — прямое присваивание, `ac_input_curve`
  симметрична (deadzone через `copysign`, expo нечётная), знак не меняется.
- `rust/ac-ios-runtime/src/lib.rs:226` — `clamp(-1,1)`, знак не меняется.
- `rustyac-physics/src/car/feed.rs:43` — **«steer, -1..1, positive = right»**.
- GameController `xAxis.value` положителен вправо (документация Apple) — тоже
  совпадает с AC.

**Вывод:** в FFI/Rust/физике инверсии знака нет. Источник ощущения инверсии —
старый UI: `touchesMoved` вычислял steer из **абсолютной координаты X в левой
половине экрана** без точки отсчёта. Касание «по центру» левой половины сразу
давало `steer ≈ 0…+1` (вправо), а Руль был невидим — пользователь не видел
нейтрального положения. Новый `ACWheelControl` использует относительный drag и
визуальный нейтральный центр: влево → отрицательный steer, вправо → положительный.
Знак НЕ подменялся наугад; добавлены C-тесты `test_touch` на знак
(`left < 0`, `right > 0`, `neutral == 0`).

## 4. 3D-руль в салоне — причина и исправление

- KN5 проверены: `bmw_m3_e30.kn5` содержит `STEER_HR`, `steerL`, `steerR`,
  `DIR_steerL/R`; `abarth500.kn5` содержит `STEER_LR`, `STEER_HR`;
  `lotus_elise_sc/LOD_001.kn5` содержит `CAR_cockpit_low` (руль в составе
  салонного меша оригинальной модели). Фальшивая геометрия не создавалась.
- Причина «руль не виден»: `camera_next()` вызывал `DrivingCamera::next_drivable()`,
  который ходит только по chase/chase2/bonnet/bumper/dash и **никогда не
  выбирает `CameraMode::Cockpit`**. В upstream есть `f1()` — полный цикл AC,
  после dash переходящий в cockpit.
- Исправлено: `rust/ac-ios-runtime/src/render.rs::camera_next()` теперь вызывает
  `state.camera.f1()`. Оригинальный interior mesh и руль отображаются штатным
  AC-рендерером. Виртуальный touch-руль — отдельный UIControl и от 3D-руля не
  зависит.

## 5. Меню и HUD — сделано

- Компактная панель слева: `MIN(300, ширина * 0.32)` — в пределах требований
  30–35%. Кнопки Import AC folder / Controls / Settings / **DRIVE** снормальным
  стилем (не синие ссылки). Списки Cars/Tracks — в компактной таблице внутри
  панели, с выделением выбранного.
- DRIVE закрывает меню; кнопка MENU открывает его снова **без пересоздания
  сессии** и без перезапуска рендерера.
- HUD: полупрозрачная панель по центру вверху — Speed (km/h), RPM, Gear.
- Диагностика (сессия, сцена, трек, physics steps, FPS, render ms,
  Metal features, gas/brake/steer) вынесена в отдельную панель, **по умолчанию
  выключена**, включается в Settings. Наложений текста нет.

## 6. Графика — диагностика и исправление

Сравнение: `phase7/render_checks/lotus_elise_sc__magione/...png` (Windows,
full_frame) против скриншота с iPhone.

Причина найдена в `rust/ac-ios-runtime/src/render.rs`: iOS-путь хардкодил
`sun_angle: 0.0`, `weather: String::new()`, `sun_animation: None`, `groove: None`.
В upstream `AcRenderer::new` при пустом `weather` **не вызывает**
`SkyBox::update_clouds_generation` и `Graphics::apply_custom_weather`
(`rustyac-game/src/render/ac.rs:1283–1288`), а стандартное солнце AC — `-16°`
(`RaceLook::of`, `ac.rs:326–336`). Отсюда плоское небо и тёмные материалы.

Исправление (без фейкового освещения и без удаления текстур): как в desktop и
Windows full_frame, читаем `cfg/race.ini` через `IniReader::load_race` и
передаём `RaceLook::of(race_reader)` → sun_angle, weather, sun_animation, groove,
session_type. Оригинальные DDS/KN5-текстуры и материалы остаются на месте.

В debug-панель добавлена маска `Metal features 0x…`, чтобы на устройстве можно
было подтвердить наличие `TEXTURE_COMPRESSION_BC` / `FLOAT32_FILTERABLE` и
при необходимости разобрать BC-загрузку отдельно (это не подтверждённая
причина, а следующий диагностический шаг).

## 7. Производительность

- Никаких тяжёлых UI-анимаций, таймеров и аллокаций в кадре; HUD обновляется
  10 раз/с, диагностика — в том же темпе и только при включении.
- `FPS` (сглаженный) и `render ms` (`ac_ios_render_last_draw_ms`) показываются
  в debug-панели. Фактические значения с iPhone будут получены после установки
  новой IPA; **сейчас их нет**.

## 8. Затронутые файлы

- `ios/GameViewController.m` — почти полностью переписан UI-слой (без изменений
  в session/render FFI и загрузке контента).
- `rust/ac-ios-runtime/src/render.rs` — camera `f1()`, AC race.ini look.
- `core/ac_pal_bridge_test.c` — sign-тесты touch input.
- Регрессионные тесты Phase 8.1/8.2 и sampler-логика не изменены.

## 9. Результаты локальных проверок

```text
cargo test -p rustyac-render --features backend-wgpu --lib sampler_validation_tests
→ 10 passed; 0 failed

cargo test -p rustyac-render --features backend-wgpu --lib
→ 37 passed; 0 failed; 2 ignored

cargo check -p ac-ios-runtime --target aarch64-apple-ios
→ Finished, EXIT=0

python scripts/build_native_core.py + build/ac_pal_bridge_test.exe
→ ac_pal_bridge_test: ALL TESTS PASSED

python scripts/verify_ios_project.py → 52/52, BUILD PREFLIGHT PASSED
python scripts/prepush_audit.py → PRE-PUSH AUDIT PASSED
```

`CARGO_BUILD_JOBS=2` использовался во всех cargo-командах.

## 10. Состояние реального устройства

- **Phase 8.2 IPA на iPhone работает** — подтверждено пользователем,
  скриншот реальной сцены есть.
- **Новый UI/управление/графика на iPhone ещё не проверены** — новая IPA должна
  быть собрана в CI, затем пользователь устанавливает её и проверяет:
  руль, педали, gear/handbrake/camera, меню, HUD, cockpit, картинку, FPS.
- Скриншоты нового меню/HUD будут добавлены после теста устройства.

## Артефакты

- Патч: `patches/next_phase/`
- Чекпоинт до изменений: `checkpoint/before_next_phase/`
- Чекпоинт после: `checkpoint/after_next_phase/`
- Скриншот исходного состояния: `phase8/iphone_scene_2026-11-18.png`
