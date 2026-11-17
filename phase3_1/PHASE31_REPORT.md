# Phase 3.1 — release artifact integration

## Result

The Phase 3 render module is now inside the real iOS ARM64 static library.

- Rebuild: `cargo build --release --target aarch64-apple-ios -p ac-ios-runtime`
  — **exit 0**, incremental 48.69 s (`build_staticlib.exit/.log`), jobs limited to 2
  via `rust/.cargo/config.toml`, all artifacts on D:.
- `libac_ios_runtime.a`: **51,407,784 bytes**, SHA-256
  `d317ccc74bd4d23968ba77f22d3eccb29ef0bc4e499b1ed9bf0ba6ee6573b99b`.
- Manifest: `artifacts/IOS_STATICLIB_MANIFEST.json`.

## Archive inspection (not just file size / cargo check)

`python scripts/inspect_ios_archive.py`:
- 694 archive members, **693 Mach-O 64 objects, all 693 ARM64**.
- Object families present: `ac_ios_runtime` (12), `rustyac_render` (16),
  `rustyac_game` (16), `rustyac_physics` (16), `wgpu` (56), Metal/objc2/raw-window-metal.
- All new exported C symbols found in the archive: `ac_ios_render_init`,
  `ac_ios_render_frame`, `ac_ios_render_last_draw_ms`, `ac_ios_metal_init`,
  `ac_ios_boot`, `ac_ios_core_session_create`.

## C / Objective-C integration check

| Symbol | Header | ObjC caller | Rust implementation |
|---|---|---|---|
| `ac_ios_render_init` | YES | YES | YES |
| `ac_ios_render_frame` | YES | YES | YES |
| `ac_ios_render_last_draw_ms` | YES | YES | YES |
| `ac_ios_render_destroy` | YES | YES | YES |
| `ac_ios_metal_init` | YES | YES | YES |
| `ac_pal_bridge_session` | YES (C) | YES | C-only by design |

## Tests

- `cargo test --offline`: **8/8** (`logs/09_phase31_tests.log`).
- `python scripts/verify_delivery.py`: **39/39**, no fake IPA, no protected assets.

## Native linking limitations (explicit)

- No Xcode / iPhoneOS SDK / linker / codesign identity / simulator / device here.
- The static library cannot be linked into an IPA in this environment.
- `ld64` would have to resolve UIKit, MetalKit, GameController, QuartzCore and the
  Objective-C runtime; only the wgpu/Metal Rust side is verified as ARM64 code here.
- Therefore no claim is made that the iOS app launches or renders on a device.
