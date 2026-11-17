#!/usr/bin/env python3
"""Generate and verify iOS-target patches for upstream rustyAC.

Reads the pristine upstream files from third_party/rustyAC-src/rustyAC-master,
applies a small set of exact text substitutions, emits unified diffs into
patches/, stores the patched files in patches/applied/, and finally verifies
each diff by re-applying its hunks to the original text.

Run:  python scripts/make_patches.py
"""
from __future__ import annotations

import difflib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = ROOT / "third_party" / "rustyAC-src" / "rustyAC-master"
PATCHES = ROOT / "patches"
APPLIED = PATCHES / "applied"


def edit(original: str, old: str, new: str, label: str) -> str:
    if original.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {original.count(old)}")
    return original.replace(old, new, 1)


def build_files() -> dict[str, tuple[str, str]]:
    """Return {relpath: (original, patched)}."""
    files: dict[str, tuple[str, str]] = {}

    # 1. Pinned toolchain needs the iOS standard library target.
    rel = "rust-toolchain.toml"
    orig = (UPSTREAM / rel).read_text(encoding="utf-8")
    new = edit(
        orig,
        'targets = ["wasm32-unknown-unknown", "wasm32-wasip1"]',
        'targets = ["wasm32-unknown-unknown", "wasm32-wasip1", "aarch64-apple-ios"]',
        rel,
    )
    files[rel] = (orig, new)

    # 2. rustyac-render: wgpu with Metal on iOS, unchanged elsewhere.
    rel = "crates/rustyac-render/Cargo.toml"
    orig = (UPSTREAM / rel).read_text(encoding="utf-8")
    new = edit(
        orig,
        'wgpu = { version = "=30.0.1", default-features = false, features = ["dx12", "vulkan", "wgsl"], optional = true }',
        '# native wgpu: backend features are selected per target at the end of this file',
        rel,
    )
    # Target tables must come AFTER all plain [dependencies] entries: in TOML a
    # [target...] header changes the current table, so placing it mid-section
    # would swallow the following png / jpeg-decoder optional dependencies.
    new = new.rstrip("\n") + '''

# Target-specific wgpu backends: iOS has no DX12/Vulkan, it uses Metal.
# The UIKit host creates the device from a CAMetalLayer and calls Kgl::give_device().
[target.'cfg(not(target_os = "ios"))'.dependencies.wgpu]
version = "=30.0.1"
default-features = false
features = ["dx12", "vulkan", "wgsl"]
optional = true

[target.'cfg(target_os = "ios")'.dependencies.wgpu]
version = "=30.0.1"
default-features = false
features = ["metal", "wgsl"]
optional = true
'''
    files[rel] = (orig, new)

    # 3. rustyac-game: make the renderer available on iOS, like on wasm.
    rel = "crates/rustyac-game/Cargo.toml"
    orig = (UPSTREAM / rel).read_text(encoding="utf-8")
    new = edit(
        orig,
        '''rustyac-render = { path = "../rustyac-render", features = ["backend-wgpu"] }
rustyac-audio = { path = "../rustyac-audio" }
# the clock (std::time::SystemTime panics in a browser)
js-sys = "0.3"''',
        '''rustyac-render = { path = "../rustyac-render", features = ["backend-wgpu"] }
rustyac-audio = { path = "../rustyac-audio" }
# the clock (std::time::SystemTime panics in a browser)
js-sys = "0.3"

# iOS: the portable simulation, AC's input classes and AC's renderer on kgl's
# wgpu/Metal backend. Windows-only parts (window, XInput/DirectInput, shared
# memory, Steam, launcher) stay out; UIKit supplies the window, touch/gamepad
# input and the application lifecycle. The app crate enables the `wgpu`
# feature so `rustyac_game::render::ac` is compiled.
[target.'cfg(target_os = "ios")'.dependencies]
rustyac-render = { path = "../rustyac-render", features = ["backend-wgpu"] }''',
        rel,
    )
    files[rel] = (orig, new)
    return files


HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def apply_diff(original: str, diff: str) -> str:
    """Apply a standard unified diff to `original` (no fuzz, no offsets)."""
    lines = original.splitlines(keepends=True)
    out: list[str] = []
    pos = 0                     # zero-based index into source lines
    seen_hunk = False
    for line in diff.splitlines(keepends=True):
        m = HUNK_RE.match(line)
        if m:
            src_start = int(m.group(1)) - 1
            if not seen_hunk:
                out.extend(lines[:src_start])   # untouched prefix
                pos = src_start
                seen_hunk = True
            elif src_start > pos:
                out.extend(lines[pos:src_start])  # unchanged lines between hunks
                pos = src_start
            elif src_start < pos:
                raise SystemExit(f"hunk source offset {src_start} < current {pos}")
            continue
        if line.startswith("--- ") or line.startswith("+++ ") or line.startswith("@@"):
            continue
        if line.startswith(" "):
            if pos >= len(lines) or lines[pos] != line[1:]:
                raise SystemExit(f"context mismatch at source line {pos + 1}: {line!r}")
            out.append(lines[pos])
            pos += 1
        elif line.startswith("-"):
            if pos >= len(lines) or lines[pos] != line[1:]:
                raise SystemExit(f"deletion mismatch at source line {pos + 1}: {line!r}")
            pos += 1
        elif line.startswith("+"):
            out.append(line[1:])
        elif line.startswith("\\"):
            continue
        else:
            raise SystemExit(f"unexpected diff line: {line!r}")
    if seen_hunk and pos < len(lines):
        out.extend(lines[pos:])                 # untouched suffix
    return "".join(out)


def main() -> None:
    PATCHES.mkdir(parents=True, exist_ok=True)
    APPLIED.mkdir(parents=True, exist_ok=True)
    files = build_files()

    def diff_for(rel: str, orig: str, new: str) -> str:
        return "".join(difflib.unified_diff(
            orig.splitlines(keepends=True),
            new.splitlines(keepends=True),
            fromfile="a/" + rel,
            tofile="b/" + rel,
            n=3,
        ))

    diff_text = "".join(diff_for(rel, orig, new) for rel, (orig, new) in files.items())
    patch_path = PATCHES / "0001-ios-native-target.patch"
    patch_path.write_text(diff_text, encoding="utf-8")

    report = {"upstream": str(UPSTREAM), "patch": patch_path.name, "files": []}
    for rel, (orig, new) in files.items():
        applied = (APPLIED / Path(rel).name)
        applied.write_text(new, encoding="utf-8")
        restored = apply_diff(orig, diff_for(rel, orig, new))
        ok = restored == new
        print(f"[{'OK' if ok else 'FAIL'}] patch applies cleanly: {rel}")
        if not ok:
            raise SystemExit(1)
        report["files"].append({"path": rel, "original_sha256": __import__("hashlib").sha256(orig.encode()).hexdigest(),
                                "patched_sha256": __import__("hashlib").sha256(new.encode()).hexdigest(),
                                "verified": ok})

    (PATCHES / "patch_manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {patch_path} ({len(diff_text)} bytes)")


if __name__ == "__main__":
    main()
