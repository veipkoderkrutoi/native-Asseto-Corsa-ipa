#!/usr/bin/env bash
#
# Reproducible macOS build of the native iOS prototype.
# NOT executed on the research host (Windows, no Xcode/iPhoneOS SDK/signing).
#
# Required environment:
#   AC_TEAM_ID            Apple Developer Team ID
#   AC_SIGNING_IDENTITY   e.g. "Apple Development: Your Name (TEAMID)"
#   AC_PROFILE_NAME       provisioning profile name for com.aciosprototype.ac-ios-port
#
# Optional:
#   AC_REBUILD_RUST=1     rebuild the ARM64 staticlib (default: reuse verified artifact)
#   AC_SKIP_EXPORT=1      stop after building the .app (no archive/export)
#   PYTHON                python3 by default
#
# The script NEVER creates credentials. Signing requires certificates and a
# provisioning profile installed in the caller's keychain.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PYTHON="${PYTHON:-python3}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "This script requires macOS."
command -v xcodebuild >/dev/null || fail "xcodebuild not found; install Xcode."
command -v xcodegen  >/dev/null || fail "xcodegen not found: brew install xcodegen"
command -v rustup    >/dev/null || fail "rustup not found; install the Rust iOS target"
command -v "$PYTHON" >/dev/null || fail "python3 not found"
: "${AC_TEAM_ID:?set AC_TEAM_ID}"
: "${AC_SIGNING_IDENTITY:?set AC_SIGNING_IDENTITY}"
: "${AC_PROFILE_NAME:?set AC_PROFILE_NAME}"

export AC_TEAM_ID AC_SIGNING_IDENTITY AC_PROFILE_NAME
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"   # strict parallelism limit
LIB="$ROOT/rust/target/aarch64-apple-ios/release/libac_ios_runtime.a"

echo "== 1/7 Preflight (no Apple credentials fabricated) =="
"$PYTHON" "$ROOT/scripts/verify_ios_project.py"
"$PYTHON" "$ROOT/scripts/audit_ios_link_inputs.py"
"$PYTHON" "$ROOT/scripts/verify_staticlib_hash.py"

echo "== 2/7 Rust iOS target / optional rebuild =="
if [[ "${AC_REBUILD_RUST:-0}" == "1" ]]; then
  rustup target add aarch64-apple-ios
  (cd "$ROOT/rust" && cargo build --release --target aarch64-apple-ios -p ac-ios-runtime)
else
  echo "Reusing the verified staticlib; set AC_REBUILD_RUST=1 to rebuild it."
fi
[[ -f "$LIB" ]] || fail "staticlib missing: $LIB"
"$PYTHON" "$ROOT/scripts/verify_staticlib_hash.py" || \
  fail "staticlib hash changed; rerun with AC_REBUILD_RUST=1 and update the manifest"

echo "== 3/7 Verify exported C symbols in the archive =="
"$PYTHON" "$ROOT/scripts/inspect_ios_archive.py" "$LIB"

echo "== 4/7 Generate the Xcode project (deterministic spec) =="
mkdir -p "$ROOT/build/ios"
(cd "$ROOT" && xcodegen generate --spec ios/project.yml --project ios)

echo "== 5/7 Build the signed .app into D: derived data =="
DERIVED="$ROOT/build/ios/DerivedData"
mkdir -p "$DERIVED"
xcodebuild -project "$ROOT/ios/ac-ios-port.xcodeproj" \
  -scheme ac-ios-port -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$AC_TEAM_ID" \
  CODE_SIGN_IDENTITY="$AC_SIGNING_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$AC_PROFILE_NAME" \
  build

APP="$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name 'ac-ios-port.app' | head -n 1)"
[[ -n "$APP" ]] || fail "xcodebuild produced no .app"
echo "APP: $APP"

if [[ "${AC_SKIP_EXPORT:-0}" == "1" ]]; then
  echo "AC_SKIP_EXPORT=1: stopping after the .app build."
  exit 0
fi

echo "== 6/7 Archive + export IPA (explicit development identity) =="
ARCHIVE="$ROOT/build/ios/ac-ios-port.xcarchive"
rm -rf "$ARCHIVE" "$ROOT/build/ios/export"
xcodebuild -project "$ROOT/ios/ac-ios-port.xcodeproj" \
  -scheme ac-ios-port -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$AC_TEAM_ID" \
  CODE_SIGN_IDENTITY="$AC_SIGNING_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$AC_PROFILE_NAME" \
  archive

sed -e "s/REPLACE_WITH_YOUR_TEAM_ID/$AC_TEAM_ID/" \
    -e "s/REPLACE_WITH_YOUR_PROVISIONING_PROFILE_NAME/$AC_PROFILE_NAME/" \
    "$ROOT/ios/exportOptions.plist" > "$ROOT/build/ios/exportOptions.plist"

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/build/ios/exportOptions.plist" \
  -exportPath "$ROOT/build/ios/export"

IPA="$(find "$ROOT/build/ios/export" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || fail "xcodebuild produced no IPA"
mkdir -p "$ROOT/artifacts"
cp "$IPA" "$ROOT/artifacts/AC-iOS-Prot.ipa"

echo "== 7/7 Verify the IPA structure and absence of protected assets =="
"$PYTHON" "$ROOT/scripts/audit_ipa.py" "$ROOT/artifacts/AC-iOS-Prot.ipa"
echo "DONE: $ROOT/artifacts/AC-iOS-Prot.ipa"
echo "NOTE: an Xcode build + IPA do NOT prove launch or gameplay on an iPhone."
