# Research sources and evidence

All network research was done on 2026-11-17 via the GitHub REST API and raw file fetches
(the web search integration returned HTTP 402, so the GitHub API was used directly).

## Primary sources

### rustyAC — https://github.com/thesupersupersigma/rustyAC
- Repo API: https://api.github.com/repos/thesupersupersigma/rustyAC
- README: https://raw.githubusercontent.com/thesupersupersigma/rustyAC/master/README.md
- Workspace `Cargo.toml`, `rust-toolchain.toml` (pins 1.97.0), 14 crates under `crates/`.
- `crates/rustyac-render/Cargo.toml` — confirms `wgpu =30.0.1` with `dx12/vulkan/wgsl`
  features and `backend-wgpu = ["wgpu", "dep:png", "dep:jpeg-decoder"]`.
- `crates/rustyac-render/src/kgl_wgpu.rs` — `Kgl::give_device()` (line ~413),
  `Kgl::with_device()` (~448), non-wasm `open()` falling back to VULKAN (~423–429).
- `crates/rustyac-game/Cargo.toml` — Windows-only dep block; wasm target block with
  `rustyac-render` + `backend-wgpu`; `wgpu` feature = `rustyac-render/backend-wgpu`.
- `crates/rustyac-game/src/lib.rs` — cfg gates: `audio` (windows or wasm), `render::ac`
  (wasm or `feature = "wgpu"`), and windows-only `conditions`, `race_cars`, `shm`, etc.
- `crates/rustyac-audio/Cargo.toml` — description says it loads the player's own FMOD
  Studio 1.08.12 DLLs; only wasm-bindgen dependency for the browser FMOD JS build.
- Full source downloaded to `third_party/rustyAC-src/rustyAC-master` (zip 37,903,987 B).
- License: GPL-3.0-or-later (game/physics), MIT OR Apache-2.0 (small libs), BSD-3 (ODE).

### openASC — https://github.com/openASC-project/openASC
- Repo API: https://api.github.com/repos/openASC-project/openASC
- README: https://raw.githubusercontent.com/openASC-project/openASC/main/README.md
- MIT; Rust edition 2024 / rust-version 1.87; wgpu 30.0.1 + winit 0.30.13.
- Self-describes as "native Rust/wgpu keyboard-driving prototype… Original physics
  parity is not established"; audio/FFB/networking remain future stages.
- Useful crates: `asc-kn5`, `asc-acd`, `asc-config`, `asc-texture`, `asc-scene`,
  `asc-render`, `asc-ground`, `asc-vehicle`, `asc-physics`, `asc-session`, `asc-app`.

### Local game install
- `D:\Games\assettocorsa\changelog.txt` → first line `1.16.2`.
- `CONFIG.ini` → Steam AppId 244210.
- 33,994 files / 42,685,423,471 bytes; `content/cars` 178 dirs, `content/tracks` 21 dirs.
- Sample: `content/cars/bmw_m3_e30/bmw_m3_e30.kn5` (39.5 MB), `data.acd` (179 KB),
  `collider.kn5`; `content/tracks/drift/drift.kn5` (188 MB), `models.ini`.

## Toolchain facts
- `python -m ziglang version` → 0.17.1. `zig cc -target aarch64-ios` produces valid
  Mach-O objects but ships no `math.h`/`string.h`; the bridge avoids both via builtins.
- `rustup` installed stable 1.100.0 during this task; `cargo test --offline` passes.

## Interpretation
rustyAC is the only candidate with proven bit-exact physics/AI/audio behaviour relative
to `acs.exe` 1.16, and its renderer already has a wgpu path — making a Metal-based iOS
route plausible. openASC is valuable as a clean content-decoding reference but is not a
feature-complete engine. No published native iOS AC port was found; the browser build is
explicitly not acceptable under the brief's rules.
