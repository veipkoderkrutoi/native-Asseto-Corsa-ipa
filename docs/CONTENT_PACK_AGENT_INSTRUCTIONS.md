# Инструкция для ИИ-агента: как собрать Content Pack для AC iOS

Назначение: подготовить **локальный** контент-пак из легальной установки Assetto Corsa
пользователя для Imported Folder flow в iOS-порте. **Ни один игровой файл не должен
попасть в публичный GitHub, CI-артефакты или кэш.**

## 0. Правила безопасности

1. Never commit/copy into repo: `*.kn5`, `*.acd`, `*.bank`, `*.dds`,`*.fsb`,
   `*.acreplay`, KN5-текстуры, полный `content/` из игры.
2. Working dir всегда на `D:`; `CARGO_BUILD_JOBS=2` для всех cargo команд.
3. Оригинальную установку `D:\Games\assettocorsa` **не изменять** — только читать.
4. Публиковать можно только IPA, исходники, отчёты и эту инструкцию.

## 1. Источники и пути

- Игра: `D:\Games\assettocorsa`
- Локальный пак: `D:\opencode-sandbox\ac-ios-port\content_pack\content`
- Manifest: `content_pack\manifest.json` (локальный, не в Git)
- Готовый архив для переноса: `content_pack_transfer_<phase>.zip` на `D:`

## 2. Найти точные имена папок

Не угадывай имена. Перечисли реальные каталоги:

```powershell
Get-ChildItem 'D:\Games\assettocorsa\content\cars' -Directory | Select-Object -ExpandProperty Name
Get-ChildItem 'D:\Games\assettocorsa\content\tracks' -Directory | Select-Object -ExpandProperty Name
```

Для конкретной модели сверь `ui/ui_car.json` → поле `name`/`brand`/`class`.
Файл AC содержит сырые переносы строк в строках — strict JSON может упасть;
читай `name` регуляркой `"name"\s*:\s*"([^"]+)"`.

Примеры точных соответствий Phase 11.7:

| Запрос | Папка |
|---|---|
| Nissan 370Z Nismo | `ks_nissan_370z` |
| Toyota AE86 (не drift/tuned) | `ks_toyota_ae86` |
| Ford GT40 | `ks_ford_gt40` |
| BMW M3 E92 drift | `bmw_m3_e92_drift` |
| Audi Sport quattro (не S1/rally) | `ks_audi_sport_quattro` |

## 3. Копировать ВСЁ дерево машины/трассы

Копируй **целую папку**.car рекурсивно — это сохранит:
`*.kn5` + LOD, `collider.kn5`, `data.acd`, `sfx/*.bank`, `ui/*`, текстуры,
`skins/`, `animations/`, tyre shadows.

```powershell
$src='D:\Games\assettocorsa\content\cars\<folder>'
$dst='D:\opencode-sandbox\ac-ios-port\content_pack\content\cars\<folder>'
Copy-Item $src $dst -Recurse -Force
```

Для трассы — так же в `content_pack\content\tracks\<folder>` ( geom + `data/` +
`ui/` + `map.png` + текстуры ). Не копируй только `.kn5`.

## 3b. ОБЯЗАТЕЛЬНО: system/shaders/win

`rustyac-render/src/shader.rs:263` загружает шейдеры из
`<content root>/system/shaders/win`. Без `ksSky_*` реальный рендерер падает с
`the shader kssky is not in .../system/shaders/win` ещё до первого кадра.

Скопируй **полностью** `system/` из игры в `content_pack/system/`
(cfg + data + shaders/win, ~23 MiB, 216 файлов). Проверка:

```powershell
Test-Path 'content_pack\system\shaders\win\ksSky_ps.fxo'   # must be True
Test-Path 'content_pack\system\shaders\win\ksSky_vs.fxo'   # must be True
```

Импортер в приложении тоже копирует `system/` — но только если он есть в
выбранной папке. Если интегратор собирает кастомный pack, не забудь `system/`.

### Hotfix для уже импортированного контента

Если на устройстве уже есть `Documents/AC-iOS/content` и нет необходимости переливать
весь пак, достаточно 작은 патча `system-fix.zip` (~0.95 MiB): он содержит
только `system/cfg`, `system/data` и `system/shaders/win` (включая `ksSky`).
Распаковать на iPhone и скопировать папку `system` в
`Documents/AC-iOS/system` рядом с существующей `content`. Существующие
машины/трассы не трогать.

## 4. Обновить manifest

Локальный manifest должен отражать реальное содержимое. Используй
`scripts/add_phase11_7_content.py` как шаблон: он добавляет cars/tracks,
пересчитывает `size`/`sha256` и `total_bytes`, не удаляя старый контент.

```powershell
cd D:\opencode-sandbox\ac-ios-port
python scripts\add_phase11_7_content.py
```

## 5. Проверить реальную загрузку (обязательно)

Существующий Windows-бинарник upstream `full_frame.exe` уже собран:

```powershell
python scripts\phase11_7_render_check.py
```

Критерий: `exit_code == 0` и ненулевой PNG для каждой комбинации. Скрипт пишет
`phase11_7\render_checks\render_checks.json`. Это доказывает, что rustyAC реально
загружает машину/трассу, а папка просто не пустая.

Дополнительная проверка полноты: у каждой машины должны быть `*.kn5`,
`data.acd`, `sfx/*.bank`, `ui/ui_car.json`, 4 `tyre_*_shadow.png`.

## 6. Собрать архив для iPhone

Только на `D:` и **не в Git**:

```powershell
cd D:\opencode-sandbox\ac-ios-port
python -c "import zipfile,pathlib; root=pathlib.Path('content_pack').resolve(); out=pathlib.Path('content_pack_transfer_new.zip'); z=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=1); [z.write(p,str(p.relative_to(root.parent))) for p in sorted(root.rglob('*')) if p.is_file()]; z.close(); print(out.stat().st_size)"
```

На iPhone: распаковать архив через «Файлы» → в приложении DRIVE-меню
CONTENT → CHOOSE FOLDER → выбрать распакованную папку `content_pack`
(внутри есть `content/cars` и `content/tracks`). Popup копирует файлы в
`Documents/AC-iOS/content/…` и обновляет списки без переустановки IPA.

## 7. Что НЕ делать

- Не называть Trento-Bondone «rally stage» — это **Hill Climb / A2B**.
- Не подменять точные версии машин соседними (AE86 drift, M3 E92 non-drift,
  Sport quattro S1 E2) — проверяй `ui_car.json`.
- Не скачивать моды и не увеличивай лимит текстур Phase 10 (1 MP/texture).
- Не заявлять успех на iPhone без реального нажатия Drive и проверки памяти/FPS.

## 8. Формат отчёта

- список добавленных папок и реальных имён из `ui_car.json`;
-результаты проверки `full_frame` (exit code + PNG bytes) для каждой машины/трассы;
- новые размеры manifest (cars/tracks/files/total_bytes);
- путь к архиву и SHA-256;
- что не удалось импортировать и почему (если DLC отсутствует);
- подтверждение, что игровые ассеты не попали в Git/CI.
