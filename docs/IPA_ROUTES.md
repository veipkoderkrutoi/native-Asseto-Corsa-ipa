# How to actually get an IPA — free and paid routes

Short answer: **you do not need a local Mac or a paid Apple account to produce a
real IPA.** You need a macOS runner once, and you need *some* Apple signing identity
only when you install it on a device.

## Facts (checked 2026-11-17)

- GitHub-hosted **standard macOS runners are free and unlimited in public
  repositories** (`macos-15`, `macos-latest`, M1/Intel, Xcode + iPhoneOS SDK
  preinstalled). In a private repository on GitHub Free you get $12/month of
  included compute; a macOS minute costs $0.062 → about **190 minutes/month**,
  enough for several builds.
- An **unsigned IPA is a real IPA**: it is a ZIP with `Payload/<App>.app`, produced
  by a real `xcodebuild` against the iPhoneOS SDK. It simply cannot be installed on
  a stock iPhone until it is signed.
- **Sideloadly** (Windows/macOS, free) and **AltStore/AltStore PAL** accept a
  **free Apple ID**: apps are valid for **7 days** and can be auto-refreshed.
  A paid Apple Developer Program ($99/year) gives 1-year validity and TestFlight.
- No jailbreak, no DRM circumvention, and no AC assets are involved in the build.

## Route A — free GitHub Actions → unsigned IPA → free Apple ID sideload (recommended)

1. Create a **public GitHub repository** (private also works within the free
   monthly minutes) and push this project. `.gitignore` already excludes
   `rust/target/`, build outputs, checkpoints and IPAs, so the upload stays small.
2. In the repo: **Actions → "Build unsigned iOS IPA (free GitHub account)" →
   Run workflow**. The workflow (`.github/workflows/build-unsigned-ios.yml`):
   - installs the `aarch64-apple-ios` Rust target;
   - builds the real ARM64 static library with `CARGO_BUILD_JOBS=2`;
   - runs the project preflight and archive/symbol checks;
   - installs XcodeGen, generates the Xcode project;
   - runs `xcodebuild -sdk iphoneos` with `CODE_SIGNING_ALLOWED=NO`;
   - zips `Payload/*.app` into `AC-iOS-Prot-unsigned.ipa`;
   - audits it (`scripts/audit_unsigned_ipa.py`) and uploads it as an artifact
     (3-day retention, well within the 500 MB free artifact allowance).
3. Download the IPA and install it with **Sideloadly** on Windows or macOS:
   - install the web version of iTunes/iCloud on Windows if needed;
   - drag the IPA in, enter your **free Apple ID** (app-specific password if 2FA);
   - Sideloadly signs with your personal team and installs over USB/Wi-Fi;
   - enable its auto-refresh daemon so the 7-day certificate is renewed.
   AltStore is the macOS alternative with the same free-Apple-ID flow.
4. On the iPhone: **Settings → General → VPN & Device Management → trust your
   developer profile**, then launch the app.

**Limitation:** free personal-team certificates last 7 days and Apple limits the
number of sideloaded apps/devices. This is fine for a bring-up test, not for
distribution.

## Route B — signed IPA in CI with a paid Apple Developer account ($99/year)

1. Enroll in the Apple Developer Program, create an App ID
   `com.aciosprototype.ac-ios-port`, a Development certificate and a development
   provisioning profile containing your test device UDID.
2. Export the certificate (`.p12`) and profile (`.mobileprovision`) from Keychain
   on a Mac, base64-encode them and store as GitHub Actions secrets together with
   their passwords and your Team ID.
3. Use the existing `scripts/build_ios.sh` on a macOS runner (or adapt the workflow
   to call it). It produces a **development-signed** IPA via
   `xcodebuild archive/exportArchive` with the explicitly supplied identity.
   Certificates stay as secrets; nothing is fabricated or committed.
4. Optional: distribute through **TestFlight** with an App Store distribution
   profile.

## Route C — you own a Mac

`bash scripts/build_ios.sh` with `AC_TEAM_ID`, `AC_SIGNING_IDENTITY`,
`AC_PROFILE_NAME`. Same as Route B but local. See `docs/BUILD_IOS.md`.

## Alternatives to GitHub Actions

- **Bitrise** has free macOS build minutes (small monthly allowance) — similar
  unsigned-artifact flow, but GitHub's public-repo runners are the cheapest.
- **Self-hosted Mac / Mac-in-the-cloud** (MacStadium etc.) works but costs money.
- **GitLab/CircleCI** shared macOS runners are generally paid or limited.
- Building iOS apps on Windows/Linux directly is **not** realistic: linking
  UIKit/MetalKit/GameController requires Apple's SDK and `ld64`.

## What still needs to happen after you get the IPA

The unsigned/sideloaded IPA is a real build, but **launch and gameplay on an
iPhone are unverified**. The first device test must check: cold start, folder
import, car/track load, rendering, touch/gamepad, physics, and background/resume.
Report any crash logs; that is the bring-up loop.
