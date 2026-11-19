#!/usr/bin/env python3
"""Pre-push audit: credentials, PII, game assets, licenses, repo size, caches.

No git binary / git history exists on this host, so this audits the file tree
that WOULD be committed under the current .gitignore rules.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "phase6"
OUT.mkdir(parents=True, exist_ok=True)

IGNORE_DIRS = {
    "rust/target", "third_party/rustyAC-src/rustyAC-master/target",
    "third_party/rustyAC-src/rustyAC-master/docs",
    "third_party/rustyAC-src/rustyAC-master/things",
    "third_party/rustyAC-src/rustyAC-master/tools",
    "third_party/rustyAC-src/rustyAC-master/web",
    "third_party/rustyAC-src/rustyAC-master/server",
    "third_party/rustyAC-src/rustyAC-master/.github",
    "build", "checkpoint", "__pycache__", ".git",
    "content_pack", "ac_ios_content", "phase7/render_checks",
    "phase7/pack_verify", "phase7/memory", "phase8/binary", "phase8/device_crashes",
    # Raw device syslog contains other apps' Apple IDs / PII: keep local only.
    "phase10/crash_forensics",
}
IGNORE_GLOBS = ["*.zip", "*.ipa", "*.xcarchive", "*.pyc", ".DS_Store",
                "artifacts/libac_ios_runtime.a"]

CREDENTIAL_PATTERNS = [
    (r"gh[pousr]_[A-Za-z0-9]{20,}", "GitHub token"),
    (r"github_pat_[A-Za-z0-9_]{20,}", "GitHub fine-grained token"),
    (r"AKIA[0-9A-Z]{16}", "AWS access key"),
    (r"AIza[0-9A-Za-z_-]{35}", "Google API key"),
    (r"sk-[A-Za-z0-9]{32,}", "OpenAI-style key"),
    (r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", "private key"),
    (r"(?i)app[ _-]?specific[ _-]?password\s*[:=]\s*\S+", "app-specific password"),
    (r"(?i)(apple[ _-]?id|email)\s*[:=]\s*[\w.+-]+@[\w.-]+", "Apple ID / email"),
]
PII_PATTERNS = [
    (r"C:\\Users\\User", "local Windows username path"),
    (r"D:\\Games\\assettocorsa", "local game install path"),
]
# Actual protected game resources (models, archives, banks, textures).
PROTECTED_SUFFIXES = {".kn5", ".knh", ".acd", ".bank", ".fsb", ".dds",
                      ".acreplay", ".ksanim"}
# Screenshots are evidence, not game resources; reported informationally only.
SCREENSHOT_SUFFIXES = {".png", ".jpg", ".jpeg"}

TEXT_SUFFIXES = {".md", ".txt", ".py", ".rs", ".c", ".h", ".m", ".mm", ".yml",
                 ".yaml", ".json", ".sh", ".toml", ".plist", ".config", ".entitlements",
                 ".log", ".wgsl", ".gitignore"}


def ignored(rel: str) -> bool:
    p = rel.replace("\\", "/")
    for d in IGNORE_DIRS:
        if p == d or p.startswith(d + "/"):
            return True
    return any(fnmatch.fnmatch(Path(p).name, g) for g in IGNORE_GLOBS)


def main() -> None:
    files = []
    for p in ROOT.rglob("*"):
        if not p.is_file():
            continue
        rel = str(p.relative_to(ROOT))
        if ignored(rel):
            continue
        files.append((rel, p))

    total = sum(p.stat().st_size for _, p in files)
    print(f"prospective tracked files: {len(files)}")
    print(f"prospective tracked size: {total/1024/1024:.1f} MiB")

    findings = []
    for rel, p in files:
        if p.suffix.lower() in PROTECTED_SUFFIXES:
            findings.append(("PROTECTED-ASSET", rel, p.suffix))
        elif p.suffix.lower() in SCREENSHOT_SUFFIXES:
            findings.append(("SCREENSHOT", rel, "informational: rendered/UI evidence, not a game asset"))
        if p.stat().st_size > 100 * 1024 * 1024:
            findings.append(("FILE>100MiB", rel, f"{p.stat().st_size/1024/1024:.1f} MiB"))
        if p.suffix.lower() in TEXT_SUFFIXES:
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for pattern, label in CREDENTIAL_PATTERNS:
                for match in re.finditer(pattern, text):
                    findings.append((label, rel, f"line {text[:match.start()].count(chr(10))+1}"))
            for pattern, label in PII_PATTERNS:
                if re.search(pattern, text):
                    findings.append((label, rel, "informational"))

    print("\n--- findings ---")
    for kind, rel, detail in findings:
        print(f"[{kind}] {rel} {detail}")

    # Required sources / licenses / caches.
    required = [
        ".github/workflows/build-unsigned-ios.yml", "ios/project.yml", "ios/Info.plist",
        "ios/main.m", "ios/AppDelegate.m", "ios/GameViewController.m", "ios/ios_bridge.m",
        "core/ac_pal_bridge.c", "core/ac_pal_bridge.h",
        "rust/Cargo.toml", "rust/ac-ios-runtime/src/lib.rs",
        "rust/ac-ios-runtime/src/metal.rs", "rust/ac-ios-runtime/src/render.rs",
        "third_party/rustyAC-src/rustyAC-master/crates/rustyac-game/src/lib.rs",
        "third_party/rustyAC-src/rustyAC-master/crates/rustyac-physics/src/lib.rs",
        "third_party/rustyAC-src/rustyAC-master/crates/rustyac-content/src/lib.rs",
        "third_party/rustyAC-src/rustyAC-master/LICENSE-GPL",
        "third_party/rustyAC-src/rustyAC-master/LICENSE-MIT",
        "third_party/rustyAC-src/rustyAC-master/LICENSE-APACHE",
    ]
    missing = [r for r in required if not (ROOT / r).is_file()]
    print("\n--- required files ---")
    print("missing:", missing or "none")

    cache_hits = [rel for rel, _ in files if "target/" in rel.replace("\\", "/")
                  or rel.startswith("checkpoint/") or rel.startswith("build/")]
    print("accidental caches in tracked set:", cache_hits or "none")

    report = {
        "git_repo": (ROOT / ".git").exists(),
        "git_binary_available": False,
        "prospective_tracked_files": len(files),
        "prospective_tracked_mib": round(total / 1024 / 1024, 1),
        "findings": [{"kind": k, "path": r, "detail": d} for k, r, d in findings],
        "missing_required": missing,
        "accidental_caches": cache_hits,
    }
    (OUT / "prepush_audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    ok = not [f for f in findings if f[0] in {"PROTECTED-ASSET", "FILE>100MiB",
                                              "GitHub token", "private key",
                                              "Apple ID / email", "AWS access key"}]
    ok = ok and not missing and not cache_hits
    print("\nRESULT:", "PRE-PUSH AUDIT PASSED" if ok else "PRE-PUSH AUDIT NEEDS ATTENTION")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
