# Assetto Corsa — native iOS port (ARM64)

Real Assetto Corsa on iPhone: **rustyAC GameSim (333 Hz physics) + the real
rustyAC/wgpu/Metal renderer**, driven by a native UIKit shell. The user imports
their own legal AC content; no protected game assets are stored in this repo.

## Status

- Real car/track loading, physics, telemetry, cameras and audio work on iPhone.
- Phase 8.1/8.2 sampler validation fixes and Phase 10 Jetsam memory fix are in.
- Phase 11/11.7: AC-styled mobile menu, Garage/Tracks/Game Modes, Time Attack
  on the **real AC lap timer**, FPS limiter (Auto/30/40/45/60), import popup
  with real folder picker, and a 5-car + hill-climb content expansion.
- Unsigned IPA is built in GitHub Actions on `macos-26-intel`; see Releases.
- Latest unsigned IPA (Phase 11.7): SHA-256
  `0546201c9bca33084a6c8095258ac8edfd0c55cd7a0a3a46a7375d3190ea4171`.

## Where things are

| Path | Purpose |
|---|---|
| `ios/` | UIKit/MetalKit app shell, import popup, settings, timing |
| `rust/ac-ios-runtime/` | C ABI: real GameSim, renderer, audio FFI, Phase 11 helpers |
| `core/` | native C bridge (fixed-step clock, input shaping) |
| `third_party/rustyAC-src/` | vendored GPL rustyAC engine |
| `patches/` | upstream patches (Phase 8.1/8.2, 9, 10, 11, 11.7) |
| `phase8/`–`phase11_7/` | forensic and phase reports |
| `docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md` | **how to build a content pack** |
| `checkpoint/` | working-state checkpoints |

## Build

```powershell
# host tests
python scripts\build_native_core.py
python scripts\verify_ios_project.py
python scripts\prepush_audit.py

# Rust (CARGO_BUILD_JOBS=2)
$env:CARGO_BUILD_JOBS='2'
cd rust
cargo test -p ac-ios-runtime --lib --offline
cargo check -p ac-ios-runtime --target aarch64-apple-ios
cd ..\third_party\rustyAC-src\rustyAC-master
cargo test -p rustyac-render --features backend-wgpu --lib --offline
```

The real unsigned IPA is produced by `.github/workflows/build-unsigned-ios.yml`
(`macos-26-intel`). No protected assets are part of the build.

## Content

The app reads content from `Documents/AC-iOS/content/{cars,tracks}` on the
device. Copy your own AC `content` folder there with the Files app, Finder/
iTunes File Sharing, or the in-app CONTENT → CHOOSE FOLDER popup.

To prepare/expand a content pack on a host with a legal AC install, follow
[`docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md`](docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md).
The content pack stays local on `D:` and is never committed or uploaded.

## Legal

No Assetto Corsa cars, tracks, textures, audio banks or archives are included.
The app resolves everything at runtime from user-owned files. rustyAC is
GPL-3.0-or-later. The IPA is unsigned and must be re-signed by the user.
