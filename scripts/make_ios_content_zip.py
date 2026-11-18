#!/usr/bin/env python3
"""Repack the content pack as a single iOS-Files-friendly folder.

The app's document picker selects a FOLDER, and it scans <root>/content/cars
and <root>/content/tracks. iOS Files cannot natively expand .zip in-place into
a chosen folder, so we produce a folder named "AC-iOS" that already has the
right layout. Copy that folder to the iPhone via Files (AirDrop / iCloud /
Finder File Sharing) and select it in the app.

Usage:
  python scripts/make_ios_content_zip.py
Output (git-ignored):
  ac_ios_content/AC-iOS/...     <- ready-to-copy folder structure
  AC-iOS.zip                    <- optional convenience zip
"""
from __future__ import annotations

import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"
OUT = ROOT / "ac_ios_content"
DEST = OUT / "AC-iOS"


def main() -> int:
    if not PACK.is_dir():
        raise SystemExit(f"content pack missing: {PACK}")
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True, exist_ok=True)
    # Copy the pack contents under AC-iOS/ preserving content/... + system/...
    for item in PACK.iterdir():
        if item.name == "manifest.json":
            shutil.copy2(item, DEST / item.name)
        elif item.is_dir():
            shutil.copytree(item, DEST / item.name)
    print(f"ready folder: {DEST}")
    print("  cars:", sorted((DEST / 'content/cars').iterdir().__iter__().__next__().name
                            for _ in [0]) if (DEST / 'content/cars').exists() else "MISSING")

    zip_path = ROOT / "AC-iOS.zip"
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for p in DEST.rglob("*"):
            if p.is_file():
                zf.write(p, p.relative_to(OUT))
    print(f"optional zip: {zip_path} ({zip_path.stat().st_size/1024/1024:.1f} MiB)")
    print("On iPhone: unzip to Files > On My iPhone/iPad, then in the app tap "
          "'Choose AC folder' and select the AC-iOS folder.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
