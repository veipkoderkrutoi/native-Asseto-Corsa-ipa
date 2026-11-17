#!/usr/bin/env python3
"""Create a clean SHA-256 manifest of the Phase 5 deliverables."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    "ios/project.yml", "ios/Info.plist", "ios/exportOptions.plist",
    "ios/ac-ios.entitlements", "ios/main.m", "ios/AppDelegate.h", "ios/AppDelegate.m",
    "ios/GameViewController.h", "ios/GameViewController.m", "ios/ios_bridge.h",
    "ios/ios_bridge.m", "core/ac_pal_bridge.h", "core/ac_pal_bridge.c",
    "rust/ac-ios-runtime/src/lib.rs", "rust/ac-ios-runtime/src/metal.rs",
    "rust/ac-ios-runtime/src/render.rs", "rust/ac-ios-runtime/Cargo.toml",
    "rust/ac-ios-runtime/examples/bench_sim.rs",
    "rust/ac-ios-runtime/examples/bench_render.rs",
    "rust/target/aarch64-apple-ios/release/libac_ios_runtime.a",
    "artifacts/ac_pal_bridge.arm64.o", "artifacts/IOS_STATICLIB_MANIFEST.json",
    "artifacts/NATIVE_OBJECT_MANIFEST.json",
    "scripts/build_ios.sh", "scripts/verify_ios_project.py",
    "scripts/verify_staticlib_hash.py", "scripts/inspect_ios_archive.py",
    "scripts/audit_ios_link_inputs.py", "scripts/audit_ipa.py",
    "phase5/BUILD_READINESS_REPORT.md", "docs/BUILD_IOS.md",
    "phase3/shots/magione_lotus.png",
    "docs/IPA_ROUTES.md",
    ".github/workflows/build-unsigned-ios.yml",
    "scripts/audit_unsigned_ipa.py",
    "scripts/verify_workflow_refs.py",
    "scripts/prepush_audit.py", "scripts/fetch_gha_result.py",
    "docs/THIRD_PARTY.md",
    "phase6/PREP_REPORT.md",
]

manifest = {
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "purpose": "Phase 5 device bring-up readiness; no IPA was built on this host",
    "files": {},
}
for rel in FILES:
    p = ROOT / rel
    if not p.is_file():
        raise SystemExit(f"missing deliverable: {rel}")
    manifest["files"][rel] = {
        "size": p.stat().st_size,
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
    }

out = ROOT / "phase5" / "SHA256_MANIFEST.json"
out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {out} with {len(FILES)} files")
