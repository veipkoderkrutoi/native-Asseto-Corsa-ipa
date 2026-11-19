# AC iOS Port — Phase 11.7 (unsigned IPA)

Native ARM64 build for iPhone 13 Pro Max (iOS 16+).

## What is included in the IPA

- Real rustyAC GameSim physics (333 Hz) and the real AC wgpu/Metal renderer.
- Phase 8.1/8.2 sampler validation fixes, Phase 10 Jetsam memory fix.
- AC-styled mobile UI: Home, Garage, Tracks, Game Modes, Settings, in-race HUD.
- Time Attack on the **real AC lap timer** with local per car/track records.
- FPS limiter: Auto / 30 / 40 / 45 / 60, independent of physics.
- Diagnostic synthesized audio driven by real telemetry (NOT original FMOD banks).
- CONTENT popup: real iOS folder picker + import into app-private Documents.
- Garage/thumbs read names and previews from the user's own AC content.

## Artifact

- File: `AC-iOS-Prot-unsigned.ipa`
- Size: 4,359,044 bytes
- SHA-256: `0546201c9bca33084a6c8095258ac8edfd0c55cd7a0a3a46a7375d3190ea4171`
- Structurally verified unsigned IPA; re-sign with Sideloadly before installing.
- Commit: `f8aa63c`, CI run `44600565798` (`macos-26-intel`, success).
- This build fixes the main-menu buttons: all screen containers now receive a
  real frame, so UIKit hit-testing reaches every button.

## Content pack — IMPORTANT

**No Assetto Corsa assets are included in this release or in the repository.**
You must import your own legal AC content. See
[docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md](https://github.com/veipkoderkrutoi/native-Asseto-Corsa-ipa/blob/main/docs/CONTENT_PACK_AGENT_INSTRUCTIONS.md)
for a complete, reproducible guide (exact folder names, whole-folder copy,
manifest update, real-engine verification and transfer archive creation).

On iPhone: CONTENT → CHOOSE FOLDER → select the unpacked `content_pack` folder
(it must contain `content/cars`, `content/tracks` **and `system/shaders/win`**),
or directly your AC root. A pack without `system/shaders/win` will fail with
`the shader kssky is not in .../system/shaders/win`; the importer now rejects
such folders with a clear message instead of letting the renderer fail.
The corrected transfer archive is named `content_pack_transfer_phase11_7_fixed.zip`.

## Known limitations

- Auto FPS uses a stable 60 cap; thermal serious/critical lowers it to 30 via
  the public `ProcessInfo.thermalState` API.
- Race mode is not implemented (marked COMING LATER).
- Trento-Bondone is a Hill Climb / A2B course, not a rally stage.
- Audio is diagnostic synthesized sound, not original AC FMOD banks.
- Real-device validation of this exact build is not claimed by the release;
  test Drive, Time Attack, import and thermals yourself.
