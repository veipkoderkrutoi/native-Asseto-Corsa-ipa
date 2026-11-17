#!/usr/bin/env python3
"""Validate the free-GitHub-Actions workflow before the first real run."""
from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
workflow = ROOT / ".github/workflows/build-unsigned-ios.yml"
data = yaml.safe_load(workflow.read_text(encoding="utf-8"))
job = data["jobs"]["build-unsigned"]
steps = job["steps"]
runs = " ".join(step.get("run", "") for step in steps)
refs = sorted(set(re.findall(r"scripts/[A-Za-z0-9_./-]+\.py", runs)))

names = [s.get("name", "") for s in steps]
rust_i = next(i for i, n in enumerate(names) if "static library" in n)
xcode_i = next(i for i, n in enumerate(names) if "UNSIGNED .app" in n)

checks = [
    ("runner is macos-15-intel", job["runs-on"] == "macos-15-intel"),
    ("least-privilege permissions", data.get("permissions") == {"contents": "read"}),
    ("all referenced scripts exist", bool(refs) and all((ROOT / r).is_file() for r in refs)),
    ("Rust step precedes Xcode step", rust_i < xcode_i),
    ("no backgrounded build commands", not re.search(r"&\s*$", runs, re.M)),
    ("xcodebuild log captured with tee", "tee build/ios/xcodebuild.log" in runs),
    ("toolchain and disk recorded", "df -h ." in runs and "xcodebuild -version" in runs),
    ("IPA artifact retention 7 days", any(
        s.get("with", {}).get("retention-days") == 7 and
        "unsigned" in str(s.get("with", {}).get("name", "")).lower() for s in steps)),
    ("log artifact uploaded always", any(
        "upload-artifact" in str(s.get("uses", "")) and s.get("if") == "always()"
        for s in steps)),
    ("no signing secrets required", "AC_TEAM_ID" not in runs),
    ("Cargo jobs limited to 2", any(
        s.get("env", {}).get("CARGO_BUILD_JOBS") == "2" for s in steps)),
]
print("runner:", job["runs-on"], "| steps:", len(steps))
print("script refs:", refs)
for name, ok in checks:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
ok = all(item[1] for item in checks)
print("RESULT:", "WORKFLOW PRE-FLIGHT PASSED" if ok else "WORKFLOW PRE-FLIGHT FAILED")
raise SystemExit(0 if ok else 1)
