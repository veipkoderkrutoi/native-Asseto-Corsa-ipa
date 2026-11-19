# Phase 10 — Real iOS crash forensics and fix

## Device / session

- Device: iPhone 14,3 (iPhone 13 Pro Max), iOS **27.0** (24A437).
- Bundle id (verified from installed apps, not assumed):
  `com.aciosprototype.ac-ios-port.GUM74PUV3G`.
- Executable / process name: `ac-ios-port`.
- Reproduction: user pressed **Drive** on the physical device three times;
  syslog was started **before** the press and captured full system logs.
- All raw evidence is in `phase10/crash_forensics/` (kept local; raw syslog
  contains other apps' PII and is excluded from Git by `prepush_audit.py`).

## 1. Exact crash type and signal

From the full system log (`drive_live_fullsyslog.txt`):

```text
19:37:32.286237 kernel: memorystatus: killing_specific_process pid 6866 [ac-ios-port]
  (per-process-limit 100 5s rf:- type:app) 3163044KB - memorystatus_available_pages: 58795
19:37:32.783385 InputUI: [app<com.aciosprototype...>:6866] Process exited:
  <RBSProcessExitContext| specific, status:<RBSProcessExitStatus|
   domain:jetsam(1) code:per-process-limit(7)>>
```

- **Category: D — Jetsam / OOM.**
- **Exit domain: `jetsam(1)`, code `per-process-limit(7)`.**
- There is **no** `EXC_CRASH/SIGABRT`, no Rust panic, no `EXC_BAD_ACCESS`, no
  watchdog termination, no wgpu validation error and no audio exception in the
  logs. The earlier `AVAudioEngine start` seen at 19:34:12 was a correlation in
  time, not the kill reason: the kernel kill line names memory, not audio.
- No `.ips` crash report was produced (Jetsam kills normally produce a
  JetsamEvent later); the RunningBoard exit context is the authoritative proof.
- Peak footprint at kill: **3,163,044 KB ≈ 3.09 GiB**.

## 2. Which Drive stage failed

The process was killed while loading the real scene (track/car textures),
before a stable frame loop. Not during menu, not during GameSim creation.

## 3. Root cause (proved by source + arithmetic)

Phase 9 added a CPU BC decoder because iOS Metal has no
`TEXTURE_COMPRESSION_BC`; `Kgl::create_texture` rejects BC formats and
`KglTexture::from_file_bytes` would otherwise silently produce an empty
texture. The fallback decoded every BC level to **RGBA8**, i.e. 4 bytes/pixel:

- BC1: 8 bytes per 4×4 block → 64 bytes RGBA = **8×** expansion
- BC3: 16 bytes per 4×4 block → 64 bytes RGBA = **4×** expansion

Measured directly from the user's content pack KN5 DDS headers:

| Track | Textures | Estimated RGBA8 VRAM |
|---|---:|---:|
| magione | 84 | ~1,804 MiB |
| imola | 110 | ~3,681 MiB |

The estimated imola total (~3.7 GB) matches the kernel kill at ~3.09 GiB.
So the fix for "black textures" traded a validation error for an OOM.

Files/functions responsible:
- `third_party/.../rustyac-render/src/texture_fallback.rs`
  - `upload_decompressed_bc()` decoded **all** mip levels to full-resolution RGBA8.
- `texture.rs::KglTexture::from_file_bytes` keeps every decoded view in
  `ResourceStore` for the session, so the GPU memory stays resident.

Stack trace: not available as symbolized frames (no crash report for a Jetsam
kill); the kernel + RunningBoard lines are the evidence. Symbolication of an
`.ips` was therefore not applicable. This does not weaken the classification.

## 4. Fix implemented (minimal, no subsystem removed)

`texture_fallback.rs`:

1. `downsample_rgba(src, sw, sh, dw, dh)` — box-average downscale preserving
   alpha; used only for the CPU fallback.
2. `bc_fallback_target(width, height)` — pure, testable cap:
   `BC_FALLBACK_MAX_PIXELS = 1024 * 1024` (4 MiB RGBA8, ~5.3 MiB with mips).
   Aspect ratio is preserved; textures already within budget are untouched.
3. `rgba_with_mips_format(...)` — mip generation with an explicit target format
   (needed for sRGB BC variants).
4. `upload_decompressed_bc()`:
   - **old:** decode every level at full resolution → upload up to 3.7 GB;
   - **new:** decode level 0, cap to ≤1 MP, downscale if needed, rebuild the
     mip chain, upload `Rgba8Unorm` / `Rgba8UnormSrgb`.
   - Each downscale is logged once at load (`BC texture fallback: downscaled …`),
     not per frame: no silent resource loss.

With the cap, 110 textures ≈ 110 × 5.3 MiB ≈ **583 MiB**, far below the
~3 GiB limit. Original compressed AC bytes remain in the user's KN5 files;
nothing was deleted, no material/texture was replaced by a flat color.

Sampler logic from Phase 8.1/8.2, RaceLook lighting, audio, physics, menu and
touch controls were **not changed**.

## 5. Regression tests added

In `bc_decoder_tests`:
- `ios_memory_budget_caps_huge_textures` — 4096×4096→1024×1024,
  4096×2048/2048×4096/2048×2048 stay ≤1 MP (this is the exact OOM guard).
- `downsample_averages_blocks_and_preserves_alpha`.

Existing DXT1/DXT5/short-block tests and all sampler tests preserved.

## 6. Verification

```text
cargo test -p rustyac-render --features backend-wgpu --lib --offline
  → running 44 tests; 42 passed; 0 failed; 2 ignored
cargo check -p ac-ios-runtime --target aarch64-apple-ios → EXIT=0
python scripts/verify_ios_project.py → 52/52, BUILD PREFLIGHT PASSED
python scripts/prepush_audit.py → PRE-PUSH AUDIT PASSED
```

`CARGO_BUILD_JOBS=2` used; wgpu validation still enabled; panic diagnostics and
memory instrumentation untouched.

## 7. Remaining risks

- Images larger than 1 MP are displayed at reduced resolution on iOS (quality
  tradeoff required to stay under the Jetsam limit). This is documented, not
  hidden.
- The synthesized audio still needs an audible device check; it was **not** the
  cause of this crash.
- No numeric post-fix footprint/FPS was measured yet — needs the new IPA.

## 8. Device validation status

**The fixed build has not yet been installed or driven on the iPhone.**
The crash in this report was observed on the Phase 9 IPA and is fully
classified; the fix is locally verified and built, but:

**REAL DEVICE DRIVE VALIDATION: NOT CONFIRMED.**

## Build / artifacts

- Commit / CI run / IPA path / size / SHA-256: filled in after CI.
- Checkpoint before: `checkpoint/before_phase10/`; after: `checkpoint/after_phase10/`
- Patch: `patches/phase10/`
- Evidence: `phase10/crash_forensics/` (local only, PII excluded from commit)
