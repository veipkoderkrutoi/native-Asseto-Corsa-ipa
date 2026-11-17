#!/usr/bin/env python3
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = p.read_bytes()
print("magic", d[:8])
off = 8
for i in range(8):
    if off + 60 > len(d):
        break
    h = d[off:off+60]
    name = h[0:16].decode("ascii", "replace").strip()
    size = int(h[48:58].decode("ascii", "replace").strip())
    body = d[off+60:off+60+size]
    print(i, repr(name), size, body[:12].hex())
    off += 60 + size + (size % 2)
