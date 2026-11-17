#!/usr/bin/env python3
"""Apply the verified iOS-target patch to the local rustyAC upstream checkout.

Uses the exact substitutions from make_patches.build_files() so the patched
files are byte-identical to the ones the unified diff produces. Idempotent.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from make_patches import UPSTREAM, build_files  # noqa: E402


def main() -> int:
    if not UPSTREAM.is_dir():
        raise SystemExit(f"upstream checkout missing: {UPSTREAM}")
    for rel, (orig, new) in build_files().items():
        target = UPSTREAM / rel
        current = target.read_text(encoding="utf-8")
        if current == new:
            print(f"[ALREADY] {rel}")
            continue
        if current != orig:
            raise SystemExit(f"{rel}: upstream file changed unexpectedly; refusing to patch")
        target.write_text(new, encoding="utf-8")
        print(f"[PATCHED] {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
