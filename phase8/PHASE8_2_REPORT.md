# Phase 8.2 — sampler anisotropy validation на iOS Metal

## 1. Точная причина новой ошибки

Сообщение с устройства:

```text
invalid filter mode for anisotropic clamp: nearest when anisotropic clamp is not 1 (it's 4)
```

Проверено **не по последней версии**, а по исходникам именно используемой версии
`wgpu-core 30.0.1` (зафиксирована в `Cargo.toml` как `wgpu = "=30.0.1"`):

- `wgpu-core-30.0.1/src/device/resource.rs:2288–2316` — если `anisotropy_clamp != 1`,
  то `min_filter`, `mag_filter` **и** `mipmap_filter` обязаны быть `Linear`;
  иначе `CreateSamplerError::InvalidFilterModeWithAnisotropy` /
  `InvalidMipmapFilterModeWithAnisotropy`.
- `wgpu-core-30.0.1/src/device/resource.rs:2353` — флаг `sampler.filtering` =
  `min_filter == Linear || mag_filter == Linear`.
- `wgpu-core-30.0.1/src/device/resource.rs:3145–3165` — проверка bind group:
  `Filtering` → comparison=false, фильтрация не проверяется;
  `NonFiltering` → фильтрация обязательно false;
  `Comparison` → comparison=true, фильтрация не проверяется.

Конфликт в `kgl_wgpu.rs` до исправления (Phase 8.1 сохранял Nearest на iOS):

| Устройство | `kind` | min/mag/mip | anisotropy | Результат |
|---|---|---|---|---|
| iOS Metal, `filterable=false` | 0 (anisotropic) | Nearest/Nearest/Nearest | **4** (`max_anisotropy` из AC) | ❌ ошибка Phase 8.2 |
| Windows, `filterable=true` | 0 | Linear/Linear/Linear | 4 | ✅ |

То есть Phase 8.1 forced Nearest для всех sampler на iOS, но `kind == 0`
продолжал получать `anisotropy_clamp = max_anisotropy.clamp(1,16)` → 4.
Нельзя просто поставить Linear глобально: на iOS layout = `NonFiltering`
(нет `FLOAT32_FILTERABLE`, `kgl_wgpu.rs:1487–1506`), и Linear снова вызовет
ошибку Phase 8.1 `expects filtering = false`. Правильное решение — **anisotropy=1
на NonFiltering-пути**, а Linear оставить только для filterable-устройств.

## 2. Все найденные места создания sampler

Аудит сохранён в `phase8/phase8_2_audit.log`.

| Место (после правки) | Тип | Layout | min/mag/mip | aniso | compare | Статус |
|---|---|---|---|---|---|---|
| `kgl_wgpu.rs:630` default plain | NonFiltering (iOS) / Filtering (Win) | из `sampler_filtering_type` | Nearest×3 / Linear×3 | 1 | None | ✅ |
| `kgl_wgpu.rs:631` default comparison | Comparison | Comparison | Linear/Linear/Nearest | 1 | Never | ✅ (поведение PCF сохранено) |
| `kgl_wgpu.rs:849` per-slot plain | NonFiltering / Filtering | из `sampler_filtering_type` | Nearest×3 / Linear×3 | **1 на iOS**, 4 на Win | None | ✅ исправлено |
| `kgl_wgpu.rs:850` per-slot comparison | Comparison | Comparison | как plain (kind 3 — Linear) | 1 | Less (kind 3) / Never | ✅ |
| `kgl_wgpu.rs:1304` blit (cubemap) | Filtering | auto (`layout: None`), WGSL `sampler` | Linear/Linear/Nearest | 1 (default) | None | ✅ не тронут |
| `kgl_wgpu.rs:1826` blit (present) | Filtering | auto (`layout: None`), WGSL `sampler` | Linear/Linear/Nearest | 1 (default) | None | ✅ не тронут |

Оба blit-sampler валидны: `anisotropy_clamp = 1`, значит требование «все Linear
при aniso≠1» не применяется; `filtering=true, comparison=false` соответствует
автоматическому `Filtering`-binding из WGSL.

## 3. Исходные и исправленные значения

** Per-slot `create_sampler` (строка ~830):**

```rust
// БЫЛО (Phase 8.1):
let filter = sampler_filter_mode(kind, filterable);       // iOS kind0 → Nearest
let mip = if filter == Nearest || kind == 3 { Nearest } else { Linear };
let anisotropy = if kind == 0 { max_anisotropy.clamp(1, 16) as u16 } else { 1 }; // → 4
// → Nearest + aniso 4 = validation error

// СТАЛО:
let plain_cfg = sampler_config(kind, filterable, max_anisotropy, false);
let comparison_cfg = sampler_config(kind, filterable, max_anisotropy, true);
let plain = device.create_sampler(&sampler_descriptor(plain_cfg, address));
let comparison = device.create_sampler(&sampler_descriptor(comparison_cfg, address));
```

Новые чистые функции в `kgl_wgpu.rs`:

- `SamplerConfig` (поля `mag_filter`, `min_filter`, `mipmap_filter`,
  `anisotropy_clamp`, `compare`, `binding_type`) + `is_wgpu_valid()`;
- `sampler_mipmap_mode(kind, filter)`;
- `sampler_anisotropy_clamp(kind, filterable, requested)` → `1`, если
  `!filterable || kind != 0`, иначе `requested.clamp(1,16)`;
- `sampler_config(kind, filterable, requested, comparison)` — единственный
  источник истины для descriptor и binding type;
- `default_sampler_config(filterable, comparison)`;
- `sampler_descriptor(config, address)` — descriptor, который реально
  передаётся в `create_sampler`.

Phase 8.1 (`sampler_filtering_type`, `sampler_filter_mode`, их использование в
`program()`) **полностью сохранён**. Дополнительно устранена латентная
несовместимость: plain-сэмплер `kind 3` на iOS теперь тоже Nearest (Comparison-
ветка по-прежнему Linear) — этот вариант пойман в тесте 6.

## 4. Как обеспечивается соответствие Bind Group Layout

Layout в `program()` (`kgl_wgpu.rs:1500`):

```rust
ty: wgpu::BindingType::Sampler(sampler_filtering_type(filterable, s.comparison))
```

Descriptor строится из `sampler_config(...)` → тот же `filterable`, тот же
`comparison`, тот же `sampler_filtering_type`. Инварианты:

- `NonFiltering` → `is_filtering() == false` ( все три Nearest ) и `aniso == 1`;
- `Filtering` → comparison == false, `aniso` может быть 4 только при всех Linear;
- `Comparison` → `compare.is_some()`, отдельный WGSL `sampler_comparison`,
  `aniso == 1`, PCF-поведение не изменено.

`debug_assert!(cfg.is_wgpu_valid())` на месте создания — страховка от будущего
дрейфа; wgpu validation не отключалась, catch_unwind не трогался.

## 5. Добавленные regression tests

`mod sampler_validation_tests` расширен с 4 до **10** тестов. Новые:

1. `non_filtering_config_is_nearest_with_anisotropy_one` — все kind и requested
   [1,2,4,8,16] → Nearest×3 + aniso 1 + валидный descriptor.
2. `filtering_config_is_linear_with_anisotropy_four` — Linear×3 + aniso 4.
3. `non_filtering_with_anisotropy_four_is_rejected` — bad-config (Nearest+4)
   отклоняется `is_wgpu_valid()`; хелпер никогда её не порождает.
4. `default_samplers_match_binding_and_anisotropy` — оба default-сэмплера.
5. `comparison_samplers_are_separate_and_valid` — Binding Type, compare
   (Less/Never), aniso 1, сохранение Linear для kind 3.
6. `every_category_has_consistent_layout_and_descriptor` — полная матрица
   kind × filterable × comparison × requested, проверка layout == descriptor
   и всех инвариантов wgpu 30.0.1.

Тесты проверяют **фактические поля `wgpu::SamplerDescriptor`**, возвращаемые
`sampler_descriptor()` — той же функцией, которой пользуется `create_sampler`.

## 6. Результаты проверок

```text
cargo test -p rustyac-render --features backend-wgpu --lib sampler_validation_tests
→ running 10 tests; 10 passed; 0 failed

cargo test -p rustyac-render --features backend-wgpu --lib
→ 37 passed; 0 failed; 2 ignored

cargo check -p ac-ios-runtime --target aarch64-apple-ios
→ Finished `dev` profile, EXIT=0
```

`CARGO_BUILD_JOBS=2` использовался во всех командах.

## 7. Затронутые части рендерера

Не изменено: физика, AC-материалы, текстуры, mipmaps, WGSL, gameplay,
GameViewController, workflow (кроме ранее сделанного `macos-26-intel`).
Изменён только `kgl_wgpu.rs`: pure-хелперы, default sampler, `create_sampler`,
тесты. Blit-sampler не тронуты (уже валидны).

## 8. Реальный iPhone

**НЕ подтверждено.** Previous IPA из CI `44353393244` (Phase 8.1) дала ошибку
анизотропии. Новая IPA собрана в CI **`44359519473` — SUCCESS** на
`macos-26-intel` (коммит `d5ace5a`, все шаги зелёные, включая сборку ARM64
staticlib, Xcode project, `.app` и упаковку).

Файл на столе:
`C:\Users\User\Desktop\AC-iOS-content-pack\AC-iOS-Prot-unsigned.ipa`
- SHA-256: `6765c9c0ba869336db15b53489c81707199282329b6340c58a8e295c5256280f`
  (отличается от Phase 8.1 `deb5da36...` — это действительно новая сборка)
- Размер: 4,301,011 B
- `scripts/audit_unsigned_ipa.py`: `UNSIGNED IPA STRUCTURALLY VALID`

Дальше пользователь должен: переустановить IPA → выбрать машину/трассу → Drive.
Только после появления сцены можно считать Phase 8.2 закрытой. Если появится
следующая ошибка — зафиксировать отдельно.

## Артефакты

- Патч: `patches/phase8_2/`
- Чекпоинт: `checkpoint/after_phase8_2/`
- Аудит: `phase8/phase8_2_audit.log`, лог CI `phase8/gha_phase82.log`
- Обновлён: `HANDOFF.md`
