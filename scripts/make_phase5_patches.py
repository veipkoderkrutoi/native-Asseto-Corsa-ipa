#!/usr/bin/env python3
"""Record Phase 5 build-readiness changes as an exact unified diff."""
import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "patches" / "phase5"
OUT.mkdir(parents=True, exist_ok=True)

EDITS = {
    "ios/project.yml": [
        ("    dependencies:\n      # XcodeGen does not assign a build phase",
         "    dependencies:\n      # XcodeGen does not assign a build phase"),
        ("      - framework: Metal.framework\n        embed: false\n      - framework: MetalKit.framework\n        embed: false\n      - framework: GameController.framework\n        embed: false\n      - framework: QuartzCore.framework\n        embed: false",
         "      - sdk: Metal.framework\n      - sdk: MetalKit.framework\n      - sdk: GameController.framework\n      - sdk: QuartzCore.framework\n      - sdk: UniformTypeIdentifiers.framework"),
        ('      OTHER_LDFLAGS:\n        - "-lc++"',
         '      OTHER_LDFLAGS:\n        - "-ObjC"\n        - "-lc++"'),
    ],
}

diffs = []
for rel, edits in EDITS.items():
    text = (ROOT / rel).read_text(encoding="utf-8")
    for old, new in edits:
        if old == new:
            continue
        if new not in text:
            raise SystemExit(f"{rel}: change not present: {old[:50]!r}")
        diffs.append("".join(difflib.unified_diff(
            old.splitlines(keepends=True), new.splitlines(keepends=True),
            fromfile="a/" + rel, tofile="b/" + rel, n=2)))
        print("[RECORDED]", rel)

target = OUT / "0001-build-readiness.patch"
target.write_text("".join(diffs), encoding="utf-8")
print(f"Wrote {target} ({target.stat().st_size} bytes)")
print("Rewritten files: ios/project.yml, scripts/build_ios.sh, docs/BUILD_IOS.md")
print("New: scripts/verify_ios_project.py, scripts/verify_staticlib_hash.py, "
      "scripts/audit_ios_link_inputs.py, examples/bench_sim.rs, phase5/*")
