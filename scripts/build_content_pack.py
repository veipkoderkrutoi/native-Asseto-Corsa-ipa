#!/usr/bin/env python3
"""Build a PERSONAL Assetto Corsa content pack from the user's own install.

The pack contains ONLY the files that the real renderer actually read during
the 6 verified car/track combinations (see phase7/render_checks.json).
It is written to a LOCAL directory that is git-ignored and NEVER uploaded to
GitHub Actions artifacts/cache or committed. The user transfers it to the
iPhone with the Files app and selects its folder in the app's document picker.

Usage:
  python scripts/build_content_pack.py
  python scripts/build_content_pack.py --ac-root D:\\Games\\assettocorsa
  python scripts/build_content_pack.py --zip        # also make a transfer zip
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"          # git-ignored, personal, never committed
CHECKS = ROOT / "phase7/render_checks/render_checks.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ac-root", default="D:/Games/assettocorsa")
    parser.add_argument("--zip", action="store_true")
    args = parser.parse_args()

    ac = Path(args.ac_root)
    if not ac.is_dir():
        raise SystemExit(f"AC install not found: {ac}")
    checks = json.loads(CHECKS.read_text(encoding="utf-8"))
    if not all(c["exit_code"] == 0 for c in checks):
        raise SystemExit("some render checks failed; regenerate the file list first")

    files = sorted({f.replace("\\", "/") for c in checks for f in c["files_read"]})
    manifest = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "source_install": str(ac),
        "note": "Personal content pack. Game assets are NOT redistributed. "
                "Derived from files actually read by rustyAC's renderer.",
        "cars": sorted({c["car"] for c in checks}),
        "tracks": sorted({c["track"] for c in checks}),
        "files": [],
    }
    if PACK.exists():
        shutil.rmtree(PACK)
    total = 0
    # rustyAC's ShaderManager loads <game>/system/shaders/win at renderer init
    # (rustyac-render/src/shader.rs:263). The "files actually read" list from a
    # given car/track set is not enough for newly added cars/tracks, so include
    # the complete system/ tree (cfg, data, all shaders).
    for system_file in sorted((ac / "system").rglob("*")):
        if system_file.is_file():
            rel = system_file.relative_to(ac).as_posix()
            if rel not in files:
                files.append(rel)
    files = sorted(set(files))
    for rel in files:
        src = ac / rel
        if not src.is_file():
            raise SystemExit(f"referenced game file missing: {src}")
        dst = PACK / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        size = src.stat().st_size
        total += size
        manifest["files"].append({
            "path": rel,
            "size": size,
            "sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
        })
    manifest["total_bytes"] = total
    (PACK / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"pack: {PACK}")
    print(f"cars: {manifest['cars']}")
    print(f"tracks: {manifest['tracks']}")
    print(f"files: {len(files)}, size: {total/1024/1024:.1f} MiB")

    if args.zip:
        zip_path = ROOT / "content_pack_transfer.zip"
        if zip_path.exists():
            zip_path.unlink()
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for p in PACK.rglob("*"):
                if p.is_file():
                    zf.write(p, p.relative_to(PACK))
        print(f"transfer zip: {zip_path} ({zip_path.stat().st_size/1024/1024:.1f} MiB)")
        print("Transfer via Files app -> unzip in AC-ios folder -> select that folder in the app.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
