# Phase 6.1 — FIRST REAL GITHUB ACTIONS RUN: SUCCESS

**Confirmed by an actual GitHub Actions run**, not local verification.
- Repository: `veipkoderkrutoi/native-Asseto-Corsa-ipa` (public)
- Successful run: **#8, id `44185836939`**, commit `6d3b000`
  https://github.com/veipkoderkrutoi/native-Asseto-Corsa-ipa/actions/runs/44185836939
- Conclusion: **success**, all 16 job steps green, including
  `Build UNSIGNED .app with the iPhoneOS SDK` and `Package Payload into a real (unsigned) IPA`.

## Toolchain actually used on the runner (from `toolchain.txt`)

| Item | Value |
|---|---|
| Xcode | **16.4**, build **16F6** |
| iPhoneOS SDK | **18.5** |
| Runner | macOS X64 (`macos-15-intel`) |
| Runner disk | 325 GiB total, **108 GiB available** (14 GB warning did not bite) |
| Cargo jobs | 2 |

## Corrected errors (each from the FIRST error in the real log)

| Run | First error | Fix |
|---|---|---|
| #2 | `The job was not acquired by Runner of type hosted` (arm64 capacity) | `macos-15` → `macos-15-intel` |
| #3 | `couldn't find file .../packaging/version_res.rs` (rustyac-game build script) | restored `packaging/` in the repo |
| #4 | `ios_bridge.m:19: cast of C pointer 'void *' to 'CAMetalLayer *' requires a bridged cast` | `(__bridge CAMetalLayer *)layer` |
| #5 | `NSURLBookmarkCreationWithSecurityScope unavailable on iOS`, `UTType.folder not found` | bookmark options `0`, `[UTType typeWithIdentifier:@"public.folder"]` |
| #7 | `GameViewController.m:66 implicit conversion ... requires bridged cast`, `monospaceSystemFontOfSize` unknown, `ac_ios_set_content_root`/`ac_ios_set_input` undeclared | `__bridge void *`, `systemFontOfSize:`, C prototypes in `ios_bridge.h` |

No broad refactors; each change addressed one confirmed error.

## The resulting unsigned IPA

- Path: `phase6/gha/final/AC-iOS-Prot-unsigned/AC-iOS-Prot-unsigned.ipa`
- Size: **4,292,669 bytes**
- **SHA-256: `a447e0356eb90101e12b8147744cae66aebcb646045fab371b13345f2670cbb4`**
- Embedded executable: `ac-ios-port`, **Mach-O 64 LE (cputype ARM64)**, 11,584,840 bytes
- Bundle id: `com.aciosprototype.ac-ios-port`
- Artifacts uploaded with **7-day retention**: `AC-iOS-Prot-unsigned`, `AC-iOS-build-logs`.

`scripts/audit_unsigned_ipa.py`: 9/9 checks PASS — real `.app` bundle, Info.plist,
ARM64 executable, min iOS 16, **no protected AC assets**, no embedded IPA.

## Honest scope

- This IPA is **unsigned**: it cannot be installed on a stock iPhone until
  re-signed with Sideloadly/AltStore using a free Apple ID (7-day certificate).
- No device test has been performed. A successful Xcode build and a structurally
  valid IPA do **not** prove launch, rendering, input or gameplay on an iPhone.
- The static library inside was compiled by the runner from source (Cargo cache
  reused where possible); the full `xcodebuild.log` is saved in
  `phase6/gha/final/AC-iOS-build-logs/xcodebuild.log`.
