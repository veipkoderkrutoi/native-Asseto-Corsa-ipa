#!/usr/bin/env python3
"""Register Phase 11.7 content in the PERSONAL local content manifest.

No game assets are committed: content_pack/ is git-ignored. The manifest is
also local only, but kept accurate so pack transfer can be verified.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"
MANIFEST = PACK / "manifest.json"

CARS = [
    "ks_nissan_370z",
    "ks_toyota_ae86",
    "ks_ford_gt40",
    "bmw_m3_e92_drift",
    "ks_audi_sport_quattro",
]
TRACKS = ["trento-bondone"]


def main() -> int:
    if not MANIFEST.is_file():
        raise SystemExit("content_pack/manifest.json missing")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    cars = sorted(set(data.get("cars", [])) | set(CARS))
    tracks = sorted(set(data.get("tracks", [])) | set(TRACKS))

    rels = sorted({p.replace("\\", "/") for c in cars for p in
                   [str(x.relative_to(PACK)) for x in (PACK / "content/cars" / c).rglob("*") if x.is_file()]}
                  | {p.replace("\\", "/") for t in tracks for p in
                     [str(x.relative_to(PACK)) for x in (PACK / "content/tracks" / t).rglob("*") if x.is_file()]})
    known = {f["path"]: f for f in data.get("files", [])}
    total = 0
    files = []
    for rel in rels:
        p = PACK / rel
        if not p.is_file():
            raise SystemExit(f"missing content file: {rel}")
        size = p.stat().st_size
        total += size
        entry = known.get(rel)
        if not entry or entry.get("size") != size:
            entry = {"path": rel, "size": size,
                     "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        files.append(entry)

    data.update({
        "cars": cars,
        "tracks": tracks,
        "files": files,
        "total_bytes": total,
        "phase11_7_added_utc": datetime.now(timezone.utc).isoformat(),
        "phase11_7_note": "5 original AC cars + Trento-Bondone hill climb added locally. "
                          "Trento-Bondone is Hill Climb, NOT a rally stage.",
    })
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"cars={len(cars)} tracks={len(tracks)} files={len(files)} size={total/1024/1024/1024:.2f} GiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
