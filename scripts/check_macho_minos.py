#!/usr/bin/env python3
"""Print LC_BUILD_VERSION minos/sdk of the ARM64 object for Xcode alignment."""
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 else \
    Path(__file__).resolve().parent.parent / "artifacts" / "ac_pal_bridge.arm64.o"
data = path.read_bytes()
ncmds = struct.unpack_from("<I", data, 16)[0]
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, off)
    if cmd == 0x2E:  # LC_BUILD_VERSION
        platform, minos = struct.unpack_from("<II", data, off + 8)
        sdk = struct.unpack_from("<I", data, off + 16)[0] if size >= 20 else 0
        ntools = struct.unpack_from("<I", data, off + 20)[0] if size >= 24 else 0
        def ver(v):
            return f"{v >> 16}.{(v >> 8) & 0xFF}.{v & 0xFF}"
        print(f"cmdsize={size} platform={platform} minos={ver(minos)} "
              f"sdk={ver(sdk) if sdk else 'n/a'} tools={ntools}")
    elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS (legacy, 16 bytes)
        version, sdk = struct.unpack_from("<II", data, off + 8)
        def ver2(v):
            return f"{v >> 16}.{(v >> 8) & 0xFF}.{v & 0xFF}"
        print(f"cmdsize={size} platform=iOS(min) minos={ver2(version)} "
              f"sdk={ver2(sdk) if sdk else 'n/a'}")
    off += size
