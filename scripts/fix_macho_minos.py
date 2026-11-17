#!/usr/bin/env python3
"""Fix Zig 0.17's malformed iOS min-version load command in-place.

Zig emits a 16-byte LC_BUILD_VERSION (0x2e) whose struct needs 24 bytes, so
platform/minos/sdk read as garbage (platform=16512, minos=0.0.104). We replace
it in place with the legacy but valid 16-byte LC_VERSION_MIN_IPHONEOS (0x25)
carrying iOS 16.0. Because the command size stays 16, no file offsets change.

Usage: python scripts/fix_macho_minos.py [path/to/object.o]
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

LC_VERSION_MIN_IPHONEOS = 0x25
LC_BUILD_VERSION = 0x2E
IOS_16_0 = (16 << 16) | (0 << 8) | 0

DEFAULT = Path(__file__).resolve().parent.parent / "artifacts" / "ac_pal_bridge.arm64.o"


def commands(data: bytearray) -> list[tuple[int, int, int]]:
    """Return (cmd, cmdsize, offset) for each load command."""
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    out = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        out.append((cmd, size, off))
        off += size
    return out


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    data = bytearray(path.read_bytes())
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise SystemExit(f"{path}: not a 64-bit little-endian Mach-O")

    changed = False
    for cmd, size, off in commands(data):
        if cmd == LC_BUILD_VERSION and size == 16:
            # Overwrite the whole 16-byte command: 0x25, 16, version, sdk=0.
            struct.pack_into("<IIII", data, off,
                             LC_VERSION_MIN_IPHONEOS, 16, IOS_16_0, 0)
            changed = True
            print(f"fixed 16-byte LC_BUILD_VERSION at offset {off} -> "
                  f"LC_VERSION_MIN_IPHONEOS 16.0")
        elif cmd == LC_VERSION_MIN_IPHONEOS and size == 16:
            version, sdk = struct.unpack_from("<II", data, off + 8)
            if version != IOS_16_0:
                struct.pack_into("<II", data, off + 8, IOS_16_0, 0)
                changed = True
                print(f"updated LC_VERSION_MIN_IPHONEOS at offset {off} -> 16.0")

    if changed:
        path.write_bytes(data)
    else:
        print("no malformed min-version command found; object unchanged")

    # Verify the result.
    for cmd, size, off in commands(data):
        if cmd == LC_VERSION_MIN_IPHONEOS:
            version, sdk = struct.unpack_from("<II", data, off + 8)
            v = f"{version >> 16}.{(version >> 8) & 0xFF}.{version & 0xFF}"
            print(f"RESULT: min iOS = {v} (load command 0x25, size {size})")
            return 0 if version == IOS_16_0 else 1
    print("RESULT: FAILED - no iOS min-version command")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
