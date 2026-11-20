#!/usr/bin/env python3
"""Assemble ONE complete, self-contained AC-iOS content folder.

The result is a drop-in replacement for Documents/AC-iOS: no patches, no
merge ordering, no nested content/content. Every file the Phase 11.9 preflight
manifest marks as required is verified before the folder is declared ready.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "content_pack"
REQ = ROOT / "phase11_9/content_requirements.json"
DEST = Path("C:/Users/User/Desktop/AC-iOS-content-pack/AC-iOS-full/AC-iOS")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    for name in ("content", "system"):
        src = SOURCE / name
        if not src.is_dir():
            raise SystemExit(f"missing source folder: {src}")
        shutil.copytree(src, DEST / name)

    combos = json.loads(REQ.read_text(encoding="utf-8"))["combinations"]
    required = sorted({p for entry in combos.values() for p in entry["required"]})
    missing = [p for p in required if not (DEST / p).is_file()]
    if missing:
        print("FAIL required files missing:")
        for p in missing[:20]:
            print("  ", p)
        raise SystemExit(1)

    files = sorted(p for p in DEST.rglob("*") if p.is_file())
    checksums = []
    total = 0
    for p in files:
        size = p.stat().st_size
        total += size
        checksums.append({"path": p.relative_to(DEST).as_posix(), "size": size,
                          "sha256": sha256(p)})
    report = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "note": "Complete personal AC iOS content pack. User-owned original AC files only. Not for public git/CI.",
        "cars": sorted(p.name for p in (DEST / "content/cars").iterdir() if p.is_dir()),
        "tracks": sorted(p.name for p in (DEST / "content/tracks").iterdir() if p.is_dir()),
        "files": len(files),
        "total_bytes": total,
        "required_preflight_files": len(required),
        "missing_preflight_files": 0,
        "checksums": checksums,
    }
    (DEST / "pack_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (DEST / "README.txt").write_text(
        "AC-iOS COMPLETE CONTENT PACK\n"
        "=============================\n"
        "Copy this whole AC-iOS folder into the app's Documents via Finder/iTunes File Sharing,\n"
        "or select it in the in-app CONTENT -> CHOOSE FOLDER popup.\n"
        "It already contains content/, system/ and pack_report.json. No patches are needed.\n"
        "If Documents/AC-iOS already exists, replace it with this folder (keep IPA backups separately).\n",
        encoding="utf-8")

    print(f"READY: {DEST}")
    print(f"cars={report['cars']}")
    print(f"tracks={report['tracks']}")
    print(f"files={len(files)} size={total/1024/1024/1024:.2f} GiB")
    print(f"preflight required={len(required)} missing=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
