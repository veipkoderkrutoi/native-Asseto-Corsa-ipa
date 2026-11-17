# Architecture report

## 1. The original Assetto Corsa (user's install, inspected locally)

`D:\Games\assettocorsa` — Assetto Corsa **1.16.2** (`changelog.txt`), Steam app 244210,
≈42.7 GB, 33,994 files, **178 cars**, **21 tracks**.

Key top-level binaries:

| File | Size | Role |
|---|---:|---|
| `acs.exe` | 22.8 MB | x64 game (the target of rustyAC's oracles) |
| `acs_x86.exe` | 21.9 MB | 32-bit build |
| `AssettoCorsa.exe` | 5.4 MB | .NET launcher |
| `fmod.dll` / `fmod64.dll`, `fmodstudio*.dll` | 1.4–1.8 MB | FMOD audio runtime |
| `libcef.dll`, `AC.CEF3.dll` | 49 MB | embedded browser in launcher |
| `SlimDX.dll`, `d3dcompiler_*.dll` | — | Direct3D 11 / managed graphics |
| `python33.zip` | 7.1 MB | in-game Python app API |
| `steam_api*.dll` | — | Steamworks |

Content layout actually present:

```
content/cars/<car_id>/   <car_id>.kn5, LOD_*.kn5, data.acd, collider.kn5,
                         *.knh, skins/, texture/, ui/, sfx/
content/tracks/<track>/  <track>.kn5, models.ini, data/, ai/, ui/, map.png
```

So the load chain the port must support is: `models.ini`/`data.acd` (INI + packed INI)
→ `KN5` mesh/material/texture hierarchy → D3D11 shaders → physics parameters from
`data.acd`.

**Why a direct port of the original is impossible:** `acs.exe` is a closed-source
x64 Windows PE that depends on D3D11, FMOD, MSVCR120, Win32 messages, XInput/DirectInput
and Steamworks. iOS has none of those. There is no source, and reverse-engineering the
whole engine is out of scope for this task.

## 2. Open projects

### 2.1 rustyAC — `thesupersupersigma/rustyAC` (master, 2026-11-17)

Apache/GPL mixed licensing (game + physics **GPL-3.0-or-later**; small libs
MIT/Apache-2.0; ODE port BSD-3-Clause). ~52 MB repository, 14 workspace crates.

Claim: a 1:1, *bit-exact* rewrite of AC 1.16 in Rust: physics, collisions, renderer,
sound, AI, HUD, launcher, multiplayer, shared memory, Python apps. It runs on Windows
(D3D11) and in the browser (WebAssembly, WebGPU). It loads all content from the
player's own install and ships none of it.

Verification method (from its README) is unusually strong and is the main reason to
trust it as a base: test tools load the original `acs.exe` **into the same process** and
run its own functions side by side with the Rust port, comparing every value bit for
bit; D3D11 calls and pixels are compared on Microsoft WARP; FMOD calls are logged and
compared.

Workspace crates (from `Cargo.toml` / `crates/`):

```
rustyac-math      AC's own sinf/cosf/powf (MSVCR120 bit compatibility)
rustyac-ode       ODE 0.13.1 ported to Rust (contact/collision)
rustyac-physics   tyres, suspension, drivetrain, aero, electronics, damage
rustyac-content   INI/data.acd reader, KN5 models, materials, textures
rustyac-dxbc      compiled shader reading + WGSL translation
rustyac-render    AC's renderer; D3D11 backend + `backend-wgpu` ("kgl on wgpu")
rustyac-gui       widgets, HUD, menus
rustyac-game      sim, input, AI, referee, cameras, session, replay
rustyac-audio     AC's FMOD banks, DSP plug-ins (Windows / WASM only today)
rustyac-net       acServer client + WebSocket gateway
rustyac-python    AC's Python app API
rustyac-launcher  AC's own launcher
rustyac-web       browser build (wasm-bindgen, WebGPU/WebGL2)
```

**Decisive finding for iOS:** `crates/rustyac-render/Cargo.toml` already has a
`backend-wgpu` feature (`kgl_wgpu.rs`), and `kgl_wgpu.rs` exposes
`Kgl::give_device(device, queue, features)` / `Kgl::with_device(...)` so the host can
supply its own wgpu device. The browser already runs this path on WebGPU. wgpu 30 has a
Metal backend, so the same renderer can be hosted by a `CAMetalLayer` on iOS.

Caveat found in source: `Kgl::open()` on non-wasm defaults to `Backends::VULKAN` on
iOS, which will fail. The iOS runtime must always call `give_device()` first with a
Metal-backed device. `rustyac-game`'s `render::ac` module is compiled only on
`wasm32` or with its `wgpu` feature — hence the patch in `patches/`.

Also: `rustyac-game/src/lib.rs` gates `audio`, `conditions`, `race_cars`,
`physics_thread`, `shm`, `steam`, etc. to `windows`. On iOS the portable remainder is
`sim`, `input`, `referee`, `replay`, `telemetry`, `render::ac` (with `wgpu`). The iOS
shell therefore must supply session/condition setup, window, input and audio itself.

### 2.2 openASC — `openASC-project/openASC` (main, 2026-11-08)

MIT, Rust edition 2024 / rust-version 1.87, wgpu 30 + winit 0.30. Status explicitly
"research prototype", original physics parity **not established**. Subsystem crates:
`asc-kn5`, `asc-acd`, `asc-config`, `asc-texture`, `asc-scene`, `asc-render`,
`asc-ground`, `asc-vehicle`, `asc-physics`, `asc-session`, `asc-app`.

Its value here is complementary: a clean, bounded KN5 reader, ACD reader, typed
surfaces, BVH ground queries and a wgpu material pipeline — all with no Windows-only
dependencies. It is a useful reference/fallback for content decoding and for the
Metal/wgpu surface path, but not a feature-complete game.

### 2.3 Rejected alternatives

| Option | Why rejected |
|---|---|
| Wrap/stream the Windows game | Explicitly forbidden by the brief (no remote streaming). |
| Run rustyAC's WASM build inside iOS | Explicitly forbidden (browser build ≠ native port); also no WebGPU on iOS WebKit. |
| Port `acs.exe` binary directly | x64 Windows PE, closed source, illegal to redistribute, wrong ABI. |
| Start from openASC alone | No physics parity, no sound, no AI, no full game; years behind rustyAC. |

## 3. Chosen base and target architecture

**Decision:** rustyAC is the simulation and rendering base; openASC is a reference for
content decoding and cross-platform wgpu patterns; all device/UI/audio/lifecycle glue is
new iOS code.

```
┌────────────────────────────── iOS app (new code) ──────────────────────────────┐
│ UIKit AppDelegate  │ GameViewController (MTKView) │ touch + GameController      │
│ Files-app bookmark │ menu (cars/tracks)           │ camera cycle                │
└──────────┬─────────────────────────┬─────────────────────────┬──────────────────┘
           │ ac_ios_install_core_vtable │ touches/pad → C bridge │ CAMetalLayer
           ▼                             ▼                         ▼
┌──────────────────────┐  ┌────────────────────────┐  ┌──────────────────────────┐
│ core/ac_pal_bridge.c │  │ rust/ac-ios-runtime    │  │ wgpu Metal device        │
│ (ARM64 object)       │◄─┤ AcCoreVTable FFI       │  │ Kgl::give_device()       │
│ fixed-step, curves   │  │ opaque AcSession       │  │ rustyac-render/backend   │
└──────────┬───────────┘  └───────────┬────────────┘  │ -wgpu (patched)          │
           │                          │               └────────────┬─────────────┘
           │        ┌─────────────────┴───────────────┐            │
           └───────►│ rustyac-physics / rustyac-ode   │◄───────────┘
                    │ rustyac-content / rustyac-game  │
                    │ rustyac-gui / rustyac-net       │
                    └──────────────────┬──────────────┘
                                       │ content paths at runtime
                                       ▼
                       user's legal AC install (never bundled)
```

### Port steps (ordered, matching the brief's priorities)

1. **Launch** — UIKit app + MetalKit view, app lifecycle and background/resume handling.
   *Implemented in source, not yet compiled on macOS.*
2. **Menu** — enumerate `content/cars` and `content/tracks` from the imported root,
   select car/track/session. *Implemented in `ios/GameViewController.m`.*
3. **Track rendering** — create wgpu Metal device from `CAMetalLayer`, call
   `Kgl::give_device`, mount `rustyac-render` with `backend-wgpu`, feed `models.ini`
   through `rustyac-content`. *Blocked: needs macOS build + surface integration.*
4. **Car loading** — `rustyac-content` KN5/ACD loaders are platform-agnostic Rust;
   wired via the session. *Blocked on the same link step.*
5. **Physics** — `rustyac-physics` + `rustyac-ode` compile to `aarch64-apple-ios`
   in principle; driven by the 1 kHz fixed-step clock in `core/ac_pal_bridge.c`.
   *Blocked on linking; no device verification.*
6. **Touch + gamepad** — `GameViewController` maps touch halves and GCController
   extended/micro gamepads into the C bridge; deadzone/expo/1 kHz scheduling are
   native ARM64 code and host-tested. *Input plumbing implemented; device test pending.*
7. **Camera + sound** — camera cycling is in the shell; audio is the hardest gap:
   `rustyac-audio` is Windows/WASM-only (FMOD), so an iOS CoreAudio adapter with the
   portable DSP is needed. *See `BLOCKERS.md` B3.*

## 4. Filesystem and content model

- iOS app sandbox cannot read `D:\…`; the user imports a folder via the Files app.
  `AppDelegate` stores a security-scoped bookmark and calls
  `startAccessingSecurityScopedResource`.
- **No protected asset is copied into the bundle.** `scripts/audit_ipa.py` fails the
  build if any `.kn5/.knh/.acd/.bank/.fsb/.dds/.acreplay` file is found in the IPA.
- A full AC install is ~42.7 GB; the actual on-device storage budget and the
  Files-app folder-import workflow need device validation.

## 5. Threading and timing

- Native bridge: 1 kHz fixed-step accumulator with a 34-step guard (covers a 60 Hz
  frame plus jitter), clamps pathological deltas to 250 ms on resume.
- Rust simulation must run off the UI thread (rustyAC already has a Windows physics
  thread; the iOS equivalent still needs a GCD/Dispatch queue).
- Rendering on the MTKView delegate thread; wgpu resource lifetime on device changes
  (app background/resume) must be handled — untested.
