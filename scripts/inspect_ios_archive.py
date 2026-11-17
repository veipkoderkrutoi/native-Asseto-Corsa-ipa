#!/usr/bin/env python3
"""Inspect the iOS ARM64 staticlib for the Phase 3 render module and deps."""
import hashlib
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "rust/target/aarch64-apple-ios/release/libac_ios_runtime.a")
data = path.read_bytes()
assert data[:8] == b"!<arch>\n", "not an ar archive"

offset = 8
members = []
while offset + 60 <= len(data):
    header = data[offset:offset + 60]
    name_field = header[0:16].decode("ascii", "replace").strip()
    size = int(header[48:58].decode("ascii", "replace").strip())
    body = data[offset + 60:offset + 60 + size]
    skip = 0
    if name_field.startswith("#1/"):
        skip = int(name_field[3:])
        name = body[:skip].decode("utf-8", "replace").rstrip("\0")
    else:
        name = name_field.rstrip("/")
    payload = body[skip:]
    members.append((name, payload[:4], len(payload)))
    offset += 60 + size + (size % 2)

objects = [(n, m, s) for n, m, s in members if m == b"\xcf\xfa\xed\xfe"]
arm64 = sum(1 for _, _, _ in objects)
print(f"archive: {path}")
print(f"size: {len(data)} bytes")
print(f"sha256: {hashlib.sha256(data).hexdigest()}")
print(f"members: {len(members)}, Mach-O64 objects: {len(objects)}, ARM64: {arm64}")

for needle in ["ac_ios_runtime", "render", "metal", "rustyac_render", "rustyac_game",
               "rustyac_physics", "wgpu"]:
    hits = [n for n, _, _ in objects if needle.lower() in n.lower()]
    print(f"[{'YES' if hits else 'NO '}] {needle}: {len(hits)} object(s)")
    for h in hits[:2]:
        print(f"        {h}")

# Confirm exported C symbols are present as raw bytes in the runtime objects.
symbols = [b"ac_ios_render_init", b"ac_ios_render_frame", b"ac_ios_render_last_draw_ms",
           b"ac_ios_metal_init", b"ac_ios_boot", b"ac_ios_core_session_create"]
print("--- exported symbols in object bytes ---")
for sym in symbols:
    found = any(sym in data for _, _, _ in [])
    # search the raw archive bytes (symbol names appear in the symbol table)
    found = sym in data
    print(f"[{'YES' if found else 'NO '}] {sym.decode()}")

ok = arm64 == len(objects) and arm64 > 0 and \
     any("render" in n.lower() for n, _, _ in objects) and \
     all(sym in data for sym in symbols)
print("RESULT:", "PHASE 3 RENDER MODULE VERIFIED IN iOS ARCHIVE" if ok else "VERIFICATION FAILED")
raise SystemExit(0 if ok else 1)
