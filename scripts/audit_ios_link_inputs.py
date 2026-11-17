#!/usr/bin/env python3
"""Audit the iOS staticlib for linker-relevant facts (no Apple SDK required)."""
import struct
from pathlib import Path

path = Path("rust/target/aarch64-apple-ios/release/libac_ios_runtime.a")
data = path.read_bytes()
assert data[:8] == b"!<arch>\n"

off = 8
objects = []
while off + 60 <= len(data):
    hdr = data[off:off + 60]
    name_field = hdr[0:16].decode("ascii", "replace").strip()
    size = int(hdr[48:58].decode("ascii", "replace").strip())
    body = data[off + 60:off + 60 + size]
    skip = int(name_field[3:]) if name_field.startswith("#1/") else 0
    name = (body[:skip].decode("utf-8", "replace").rstrip("\0") if skip
            else name_field.rstrip("/"))
    payload = body[skip:]
    if payload[:4] == b"\xcf\xfa\xed\xfe":
        objects.append((name, payload))
    off += 60 + size + (size % 2)

print(f"objects: {len(objects)}")

# min OS / SDK from LC_BUILD_VERSION or LC_VERSION_MIN_IPHONEOS.
versions = {}
for name, obj in objects:
    ncmds = struct.unpack_from("<I", obj, 16)[0]
    pos = 32
    for _ in range(ncmds):
        cmd, sz = struct.unpack_from("<II", obj, pos)
        if cmd == 0x2E and sz >= 20:
            platform, minos, sdk = struct.unpack_from("<III", obj, pos + 8)
            key = f"platform={platform}"
            versions.setdefault(key, set()).add(minos)
        elif cmd == 0x25 and sz >= 16:
            minos, sdk = struct.unpack_from("<II", obj, pos + 8)
            versions.setdefault("LC_VERSION_MIN_IPHONEOS", set()).add(minos)
        pos += sz
for k, vals in versions.items():
    pretty = sorted({f"{v>>16}.{(v>>8)&0xff}.{v&0xff}" for v in vals})
    print(f"min version {k}: {pretty[:6]}")

# Symbol-table string regions: look for Objective-C categories/classes.
blob = b"".join(obj for _, obj in objects)
for needle in [b"_OBJC_$_CATEGORY", b"_OBJC_CLASS_$_", b"_objc_msgSend",
               b"_OBJC_METACLASS_$_", b"___cxa_throw"]:
    print(f"{needle.decode()} present: {needle in blob}")

# Required C ABI symbols from our code.
for sym in [b"ac_ios_boot\0", b"ac_ios_core_session_create\0", b"ac_ios_render_init\0",
            b"ac_ios_render_frame\0", b"ac_ios_metal_init\0", b"ac_ios_set_auto_shifter\0"]:
    print(f"symbol {sym[:-1].decode()}: {sym in blob}")
