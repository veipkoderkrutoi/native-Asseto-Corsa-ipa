#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

p = Path(sys.argv[1]) if len(sys.argv) > 1 else \
    Path(__file__).resolve().parent.parent / "artifacts" / "ac_pal_bridge.arm64.o"
d = p.read_bytes()
n = struct.unpack_from("<I", d, 16)[0]
off = 32
for i in range(n):
    cmd, size = struct.unpack_from("<II", d, off)
    print(f"{i}: cmd=0x{cmd:08x} size={size} bytes={d[off:off+min(size,28)].hex()}")
    off += size
