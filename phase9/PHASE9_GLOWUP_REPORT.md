# Phase 9 — Glow Up: Graphics Restoration, Audio, UI Polish

## 00. Preservation / initial state

- Branch `main`, commit before changes `d7ec0ce`, working tree clean.
- `HANDOFF.md` and previous reports read; Phase 8.1/8.2 sampler fixes intact.
- New checkpoint: `checkpoint/before_phase9/` including the working IPA
  `AC-iOS-Prot-unsigned-WORKING-NextPhase.ipa` (SHA `21b58d2d…`).
- `CARGO_BUILD_JOBS=2` used everywhere; artifacts stay on `D:`.
- No dependency/toolchain/workflow upgrade. No AC assets added to Git.

## 01. Initial technical audit (before fixes)

### Renderer execution path
`ios/GameViewController.m::drawInMTKView` → `ac_pal_bridge_run_frame` →
`rust/ac-ios-runtime/src/render.rs::ac_ios_render_frame` →
`AcRenderer::draw` → `present_to(CAMetalLayer)`. Scene built once in
`ac_ios_render_init` from the live `GameSim` + real KN5 track/car.

### Texture pipeline
`rustyac-render/src/texture.rs::KglTexture::from_file_bytes` →
`texture_fallback::create` → `dds(...)` → `upload(...)` →
`kgl_wgpu.rs::Kgl::create_texture`.

**Evidence of the real bug:** `kgl_wgpu.rs:1353`
```rust
if f.is_compressed() && !self.features.contains(wgpu::Features::TEXTURE_COMPRESSION_BC) {
    return Err("the adapter has no block-compressed textures".into());
}
```
and `texture.rs:126-133`: on `Err` the `KglTexture` is left with
`shader_resource_view: None` and only `println!`s an error. On iOS Metal there
is no `TEXTURE_COMPRESSION_BC`, so every BC (DXT) texture in the KN5 files
became an empty texture — black asphalt, missing trees/scenery. This is a
**loaded resource that never reached the GPU**, not a color or lighting tweak.

### Material / shader / lighting path
`model.rs` loads KN5 materials and calls `ResourceStore::get_texture` for every
texture slot; WGSL translated from DXBC in `rustyac-dxbc::wgsl`. Lighting uses
`RaceLook` / `SkyBox::update_clouds_generation` / `apply_custom_weather`.
Previous phase already fixed `sun_angle`/`weather` to come from `race.ini`.

### Audio audit
- No audio engine existed: `ios_bridge.m::ac_ios_audio_set` only stored floats;
  `suspend`/`resume` were empty TODOs.
- No `rodio`/`cpal`/FMOD in Cargo dependencies.
- Original AC install **does** contain per-car FMOD banks
  (`content/cars/<car>/sfx/<car>.bank`, e.g. 27 MB for Lotus) and they are in
  the user's personal content pack. No FMOD iOS SDK is available in this
  project, and banks are proprietary → **no claim of original AC audio**.
- Conclusion: implement a clearly labelled *diagnostic synthesized* audio path
  driven by real telemetry, with legal/technical limits documented.

## 02. Graphics fixes implemented

1. **`crates/rustyac-render/src/texture_fallback.rs`**
   - New `decode_bc(kind, w, h, data)` — CPU decoder for DXT1/BC1, DXT3/BC2,
     DXT5/BC3, ATI1/BC4, ATI2/BC5, preserving RGBA and alpha.
   - New `upload_decompressed_bc(...)` — uploads the decoded original texels as
     `Rgba8Unorm` (or `Rgba8UnormSrgb` for sRGB BC variants) when the adapter
     lacks `TEXTURE_COMPRESSION_BC`. No texture is dropped or replaced by a
     flat color. BC6/BC7 still return an explicit error (not silently ignored).
   - `dds(...)` now takes this path on iOS/Metal instead of failing.
2. **`crates/rustyac-render/src/texture.rs`**
   - Added bounded atomic counters `TEXTURE_STATS { loaded, failed,
     cpu_decoded_bc }` and `note_texture_*()` helpers; success/failure paths now
     increment them. No per-frame logs.
3. **`rust/ac-ios-runtime/src/render.rs`**
   - New FFI `ac_ios_texture_stats(loaded, failed, cpu_decoded_bc)`.
4. Existing sampler logic (Phase 8.1/8.2) untouched; wgpu validation on.

### Color-space configuration (documented, not guessed)
BC1/2/3 sRGB variants (DXGI 72/75/78) decode to the same 8-bit RGBA values and
upload as `Rgba8UnormSrgb`; non-sRGB BC variants upload as `Rgba8Unorm`. Normal
maps are non-color data and keep the format established by upstream AC
(`Rgba8Unorm`). The final drawable format is chosen by Metal/wgpu; no global
gamma/brightness changes were made. Optional albedo/color-space debug modes were
**not** implemented in this window; the texture counters are the available
diagnostic.

## 03. Audio implementation

### Architecture
`ios/ios_bridge.m` — one `AVAudioEngine` + `AVAudioSourceNode` (mono Float32,
48 kHz), `AVAudioSessionCategoryPlayback | MixWithOthers` so other apps are not
silenced. No Rust audio dependency, no second engine, no file I/O or allocation
in the render callback.

- Telemetry published from the main thread into `_Atomic` floats via
  `ac_ios_audio_set_state(rpm, throttle, brake, speed, gear)`.
- Render callback synthesizes: RPM-linked 4-cylinder engine tone (silenced below
  50 rpm), throttle-dependent gain, speed-linked road/wind noise, brake noise;
  soft-clipped with `v/(1+|v|)`. Separate master/engine/effects gains + mute.
- Interruption, route change, background (`suspend`) and foreground (`resume`)
  handled. Initialization failure is non-fatal and logged; no renderer coupling.

### FFI (`ios/ios_bridge.h`)
`ac_ios_audio_init`, `ac_ios_audio_shutdown`, `ac_ios_audio_set_state`,
`ac_ios_audio_set_volumes`, `ac_ios_audio_set_mute`, `ac_ios_audio_status`,
`ac_ios_texture_stats`. All documented in the header.

### Honest source labeling
This is **diagnostic synthesized audio**, not original AC FMOD playback. UI
label: “Audio: diagnostic synth (not original AC FMOD banks)”. No bank files are
decoded, copied, published, or claimed compatible. Gear-change, tire squeal
slip, collision, environment ambience and original per-car engine samples are
**not implemented** (no supported source/event).

## 04. UI / controls / HUD work

- Settings panel gained master/engine/effects sliders and a mute toggle, wired
  to the FFI above. Audio status text is clearly labeled.
- Optional diagnostics panel now also shows: texture loaded/failed/CPU-decoded
  counts and a full audio status line (init/running/failures/rpm/throttle/
  brake/speed/gains/mute). Still **off by default**.
- `ios/project.yml`: linked `AVFoundation.framework` and `AudioToolbox.framework`.
- Menu, touch controls, GameController path, camera switching, content import
  and Drive flow were preserved.

## 05. Files and functions modified

- `ios/GameViewController.m` — audio settings UI, wiring, diagnostics fields.
- `ios/ios_bridge.m` — full audio engine implementation and audio FFI.
- `ios/ios_bridge.h` — new FFI declarations.
- `ios/project.yml` — AVFoundation/AudioToolbox frameworks.
- `third_party/.../rustyac-render/src/texture_fallback.rs` — BC decoder +
  fallback upload + 3 unit tests.
- `third_party/.../rustyac-render/src/texture.rs` — texture counters.
- `rust/ac-ios-runtime/src/render.rs` — texture stats FFI.

## 06. Tests (local)

```text
cargo test -p rustyac-render --features backend-wgpu --lib --offline
→ running 42 tests; 40 passed; 0 failed; 2 ignored
  (includes 10 sampler regression tests + 3 new BC decoder tests)

cargo check -p ac-ios-runtime --target aarch64-apple-ios
→ Finished `dev` profile, EXIT=0

python scripts/verify_ios_project.py → 52/52, BUILD PREFLIGHT PASSED
python scripts/prepush_audit.py → PRE-PUSH AUDIT PASSED
```

`CARGO_BUILD_JOBS=2` in all cargo commands. No wgpu validation disabled, no
sampler logic weakened, no test removed.

## 07. Performance / memory

- Audio callback: no allocations, no locks, no file I/O, one LCG noise source
  and two sines per sample; bounded gains. Audio engine initialized once per
  Drive, shutdown on dealloc.
- Texture decoding happens **once at load**, not per frame; decoded levels are
  uploaded as RGBA8 and the original compressed bytes are freed afterward.
  Textures are cached by upstream `ResourceStore`.
- FPS, render ms (from real `ac_ios_render_last_draw_ms`) and texture/audio
  counters are visible in the optional diagnostics panel. **No numeric device
  measurements are claimed yet** — they require the new IPA on the iPhone.

## 08. Remaining limitations

- Original AC FMOD bank playback is not implemented (no licensed iOS SDK);
  the synthesized audio must not be represented as original AC sound.
- Gear/tire-slip/collision/ambient sound categories are absent.
- BC6/BC7 DDS textures still fail with an explicit diagnostic.
- Albedo/color-space visualization modes are not implemented.
- Before/after device screenshots, audible confirmation, FPS values and
  texture-counter values are pending real-device testing.

## 09. Device validation

Phase 8.2 scene was previously confirmed working by the user. This Phase 9
build has **not yet been tested on the iPhone** — no claim of audible audio,
fixed textures or improved FPS is made until the user installs the new IPA
and checks the diagnostics panel.

## Build / artifacts

- Commit: **`e401f33`** (pushed to `main`).
- GitHub Actions run: **`44516784090`** — **SUCCESS** on `macos-26-intel`;
  all steps green, including the Objective-C build with AVAudioEngine.
- IPA: `C:\Users\User\Desktop\AC-iOS-content-pack\AC-iOS-Prot-unsigned.ipa`
  - Size: **4,321,440 B**
  - SHA-256: **`1a1f017ea4013ce5e779bad3e8115f22d40e048d2b3cad699fc39f009ca61343`**
  - `scripts/audit_unsigned_ipa.py`: **UNSIGNED IPA STRUCTURALLY VALID**
- Previous working build preserved as
  `AC-iOS-Prot-unsigned-PrePhase9-WORKING-backup.ipa` (SHA `21b58d2d…`), and the
  older Phase 8.2 build as `...-Phase8.2-WORKING-backup.ipa` (`6765c9c0…`).
- Patch: `patches/phase9_glowup/`
- Checkpoint before changes: `checkpoint/before_phase9/`; after changes:
  `checkpoint/after_phase9_glowup/`
- CI log: `phase9/gha_phase9.log`
