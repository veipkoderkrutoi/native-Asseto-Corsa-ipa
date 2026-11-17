# Remaining blockers

Ordered by impact. "Environment" blockers are properties of this sandbox; "engineering"
blockers are real work needed even on a Mac.

| ID | Blocker | Type | Impact | What is needed |
|---|---|---|---|---|
| **B1** | No macOS host, Xcode, iPhoneOS SDK, codesign identity, simulator or device in this sandbox | Environment | **No IPA can be linked or signed here.** | Run `scripts/build_ios.sh` on a Mac with an Apple Developer account. This is the single reason no IPA is in `artifacts/`. |
| **B2** | wgpu Metal chain is implemented and compiles for iOS ARM64, but has never executed | Verification | Track rendering (priority 3) unproven on a device. | Run `ac_ios_metal_init()` on an iPhone with a real CAMetalLayer, then a one-frame smoke test. `Kgl::open()`'s iOS VULKAN fallback is bypassed because `give_device` is always called first. |
| **B3** | `rustyac-audio` supports Windows FMOD and browser FMOD-JS only | Engineering | No sound (priority 7). | Integrate FMOD's iOS SDK (license + binary) or write a CoreAudio sink fed by the portable DSP in `rustyac-audio`. |
| **B4** | `rustyac-game` gates audio/conditions/race_cars/physics_thread/shm/steam to `windows` | Engineering | Session setup and telemetry helpers unavailable on iOS. | Add a small iOS session module (race.ini/assists.ini parsing already portable in `rustyac-content`) and a GCD physics thread. |
| **B5** | ~~Real physics not linked into the iOS runtime~~ | **RESOLVED** | Real `rustyac_game::sim` + `rustyac-physics` is now linked into `libac_ios_runtime.a`; a real 900-tick session with real AC content was verified on Windows and the crate builds for iOS ARM64. | Device run still needed (covered by B8). |
| **B6** | Content import of a ~42.7 GB install into an app sandbox | Engineering / device | User may be unable to supply content on-device. | Validate Files-app folder import + security-scoped bookmark lifetime on a real device; consider selective per-car/track import. |
| **B7** | GPL-3.0 distribution obligations | Legal | Cannot ship closed-source binary without complying. | Provide source offer + license notices with any distributed IPA; do not bundle Kunos content. |
| **B8** | No device-level verification of any gameplay behaviour | Verification | "Runs" is unproven. | Sideload a built IPA and run: cold start, menu, track load, car spawn, physics, touch, gamepad, camera, audio, background/resume; capture `ror`-style trace logs. |

## Explicitly not attempted (per the brief's rules)

- No DRM bypass, no modification of AC's protection, no use of `steam_api` cracks.
- No fake IPA, no placeholder bundle renamed `.ipa`, no browser/WebAssembly build
  presented as native, no remote/streamed game.
- No protected game asset copied into the deliverable (`scripts/audit_ipa.py` enforces
  this on built IPAs).
- No whole-subsystem rewrite: physics/content/renderer come from rustyAC; the new code is
  only the platform layer and glue.
