#!/usr/bin/env python3
"""Print the exact file set that .gitignore would let into the repository."""
import fnmatch
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IGNORE_DIRS = {"rust/target", "third_party/rustyAC-src/rustyAC-master/target",
               "third_party/rustyAC-src/rustyAC-master/docs",
               "third_party/rustyAC-src/rustyAC-master/things",
               "third_party/rustyAC-src/rustyAC-master/tools",
               "third_party/rustyAC-src/rustyAC-master/web",
               "third_party/rustyAC-src/rustyAC-master/server",
               "third_party/rustyAC-src/rustyAC-master/.github",
               "build", "checkpoint", "__pycache__", ".git"}
IGNORE_GLOBS = ["*.zip", "*.ipa", "*.xcarchive", "*.pyc", ".DS_Store",
                "artifacts/libac_ios_runtime.a"]

files = []
for p in ROOT.rglob("*"):
    if not p.is_file():
        continue
    rel = str(p.relative_to(ROOT)).replace(os.sep, "/")
    if any(rel == d or rel.startswith(d + "/") for d in IGNORE_DIRS):
        continue
    if any(fnmatch.fnmatch(p.name, g) for g in IGNORE_GLOBS):
        continue
    files.append((rel, p.stat().st_size))

files.sort()
out = ROOT / "phase6" / "TRACKED_FILES.txt"
out.write_text("\n".join(f"{size:>10}  {rel}" for rel, size in files) + "\n", encoding="utf-8")
total = sum(size for _, size in files)
print(f"{len(files)} files, {total/1048576:.1f} MiB -> {out}")
print("\nTop-level directories and sizes (MiB):")
sizes = {}
for rel, size in files:
    top = rel.split("/")[0] if "/" in rel else "(root files)"
    sizes[top] = sizes.get(top, 0) + size
for top, size in sorted(sizes.items(), key=lambda x: -x[1]):
    print(f"  {top}: {size/1048576:.1f}")
print("\nLargest tracked files:")
for rel, size in sorted(files, key=lambda x: -x[1])[:10]:
    print(f"  {size/1048576:7.1f}  {rel}")
