# Complete iOS build instructions (macOS only)

This project has **never** been built with Xcode in the research environment (Windows,
no Apple SDK). The procedure below is prepared for a Mac with an Apple Developer account.

## Apple tools and prerequisites

- macOS 14+ with **Xcode 16+** (`xcodebuild`, iPhoneOS SDK, Command Line Tools).
- `xcodegen` (`brew install xcodegen`).
- Rust via rustup with the `aarch64-apple-ios` target (only needed if
  `AC_REBUILD_RUST=1`; the verified static library is shipped).
- `python3` for the preflight/verification scripts.
- An **Apple Development signing identity**, the corresponding **Team ID** and an
  explicitly provided **provisioning profile** for
  `com.aciosprototype.ac-ios-port`, installed in the caller's keychain.
- A legally owned Assetto Corsa install for on-device testing. The app bundles no
  game assets.

No credentials or certificates are generated or stored by this repository.

## One reproducible command

```bash
export AC_TEAM_ID="YOURTEAMID"
export AC_SIGNING_IDENTITY="Apple Development: Your Name (YOURTEAMID)"
export AC_PROFILE_NAME="AC iOS Prototype Development"

cd /path/to/ac-ios-port
bash scripts/build_ios.sh
```

Optional environment:

| Variable | Meaning |
|---|---|
| `AC_REBUILD_RUST=1` | Rebuild the ARM64 Rust staticlib (default: reuse and hash-verify the shipped one) |
| `AC_SKIP_EXPORT=1` | Stop after producing the signed `.app` |
| `CARGO_BUILD_JOBS=2` | Cargo parallelism (default already 2 via `rust/.cargo/config.toml`) |
| `PYTHON` | Python executable (default `python3`) |

The script performs, in order:
1. preflight (`verify_ios_project.py`, `audit_ios_link_inputs.py`,
   `verify_staticlib_hash.py`);
2. optional Cargo rebuild with jobs limited to 2;
3. archive symbol/object verification (`inspect_ios_archive.py`);
4. `xcodegen generate --spec ios/project.yml --project ios`;
5. `xcodebuild build` into `build/ios/DerivedData` (D: drive on Windows-hosted copy);
6. `xcodebuild archive` + `exportArchive` using `ios/exportOptions.plist` with the
   explicitly supplied team/profile;
7. `audit_ipa.py` on the produced `artifacts/AC-iOS-Prot.ipa`.

All build products remain under the project directory (`build/ios`, `artifacts`,
`rust/target`). No protected AC files are copied into the bundle; the audit fails if
any appear.

## Manual inspection on the Mac (optional)

```bash
python3 scripts/verify_ios_project.py
python3 scripts/verify_staticlib_hash.py
python3 scripts/inspect_ios_archive.py
xcodegen generate --spec ios/project.yml --project ios
open ios/ac-ios-port.xcodeproj
```

In Xcode verify: deployment target iOS 16.0, arm64 only, the static library appears
under **Link Binary With Libraries**, and the frameworks Metal/MetalKit/GameController/
QuartzCore/UniformTypeIdentifiers are linked.

## Honest limitation

A successful `xcodebuild`, IPA export, or even an on-device launch is **not** claimed
here. The research host had no Xcode/iPhoneOS SDK/device. This document is a handoff
for a real Mac build and iPhone bring-up.
