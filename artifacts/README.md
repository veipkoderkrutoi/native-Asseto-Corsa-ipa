# Artifacts

## What is here

- `ac_pal_bridge.arm64.o` — a **real** Mach-O 64 ARM64 object (`cputype 0x0100000c`,
  `MH_OBJECT`, 17,424 bytes) built by Zig 0.17.1 for the `aarch64-ios` target. It contains
  the native input-shaping / fixed-step / FFI glue from `core/ac_pal_bridge.c`.
- `NATIVE_OBJECT_MANIFEST.json` — size, SHA-256, exact build command and target triple.

## What is deliberately NOT here

**No `.ipa` file.** This is not an oversight and not a placeholder.

An IPA is a signed ZIP application bundle. Producing one requires:
1. the Apple iPhoneOS SDK and linker (`xcodebuild`),
2. an Apple Developer signing identity and provisioning profile,
3. a macOS host.

None of these exist in the research sandbox (Windows 10 x64; verified absence in
`logs/00_environment.log`). Under the brief's rules a fake IPA, a renamed ZIP, a
browser/WASM build or a remote-streaming wrapper would all be dishonest and are
explicitly prohibited, so none was created.

Run `scripts/build_ios.sh` on a Mac with the prerequisites from `docs/BUILD_IOS.md` to
produce `AC-iOS-Prot.ipa`. That would be the **prototype shell**, not a finished game —
the remaining engineering blockers are in `docs/BLOCKERS.md`.

## Post-relocation note

The project was moved from `C:\OpenCode-Sandbox\ac-ios-port` to
`D:\opencode-sandbox\ac-ios-port`. All verifiers work from the new path:
`python scripts\verify_delivery.py` → 39/39, `python scripts\verify_ios_staticlib.py`
→ real ARM64 objects, `python scripts\check_macho_minos.py` → min iOS 16.0.

## Integrity

Verify the ARM64 object at any time:

```powershell
python scripts\verify_macho.py
python scripts\verify_delivery.py
```
