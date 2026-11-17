#!/usr/bin/env python3
"""Restore all iOS-patched upstream files from the pristine downloaded zip."""
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ZIP = ROOT / "third_party" / "rustyAC-master.zip"
BASE = ROOT / "third_party" / "rustyAC-src" / "rustyAC-master"
MEMBERS = [
    "rust-toolchain.toml",
    "crates/rustyac-render/Cargo.toml",
    "crates/rustyac-game/Cargo.toml",
]

with zipfile.ZipFile(ZIP) as zf:
    for rel in MEMBERS:
        target = BASE / rel
        target.write_bytes(zf.read("rustyAC-master/" + rel))
        print(f"restored {rel}")
