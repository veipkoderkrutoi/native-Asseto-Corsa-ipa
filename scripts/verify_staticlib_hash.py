#!/usr/bin/env python3
"""Verify the shipped iOS ARM64 staticlib against its SHA-256 manifest."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT / "artifacts/IOS_STATICLIB_MANIFEST.json").read_text())
lib = ROOT / manifest["artifact"]
actual = hashlib.sha256(lib.read_bytes()).hexdigest()
expected = manifest["sha256"]
print(f"library: {lib.relative_to(ROOT)}")
print(f"size: {lib.stat().st_size} (manifest {manifest['size_bytes']})")
print(f"sha256: {actual}")
print(f"expected: {expected}")
ok = actual == expected and lib.stat().st_size == manifest["size_bytes"]
print("RESULT:", "STATICLIB MATCHES MANIFEST" if ok else "MISMATCH - rebuild or restore the library")
raise SystemExit(0 if ok else 1)
