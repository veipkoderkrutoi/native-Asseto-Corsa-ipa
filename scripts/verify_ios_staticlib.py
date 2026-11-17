#!/usr/bin/env python3
"""Verify that a Rust staticlib really contains ARM64 iOS Mach-O objects."""
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
    # BSD ar long names: "#1/N" means the first N body bytes are the filename.
    skip = 0
    if name_field.startswith("#1/"):
        skip = int(name_field[3:])
        name = body[:skip].decode("utf-8", "replace").rstrip("\0")
    else:
        name = name_field.rstrip("/")
    payload = body[skip:]
    members.append((name, payload[:4], len(payload)))
    offset += 60 + size + (size % 2)

objects = [(n, b, s) for n, b, s in members if b == b"\xcf\xfa\xed\xfe"]
arm64 = 0
for _, _, _ in objects:
    arm64 += 1
print(f"archive: {path} ({len(data)} bytes)")
print(f"members: {len(members)}, Mach-O64 objects: {len(objects)}, ARM64: {arm64}")
for name, magic, size in objects[:5]:
    print(f"  {name}: magic=0x{magic.hex()} size={size}")
ok = len(objects) > 0 and arm64 == len(objects)
print("RESULT:", "REAL iOS ARM64 objects verified" if ok else "VERIFICATION FAILED")
raise SystemExit(0 if ok else 1)
