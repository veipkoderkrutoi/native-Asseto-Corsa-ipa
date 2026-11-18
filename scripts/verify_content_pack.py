#!/usr/bin/env python3
"""Verify the personal content pack is self-contained.

Runs the real upstream full_frame renderer with AC_ROOT pointing at the pack
(not the original install) for all 6 combinations. If it succeeds, everything
the renderer needs is inside the pack and can be imported on iOS.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"
OUT = ROOT / "phase7" / "pack_verify"
OUT.mkdir(parents=True, exist_ok=True)
EXE = ROOT / "third_party/rustyAC-src/rustyAC-master/target/release/examples/full_frame.exe"

results = []
for track in ["magione", "imola"]:
    for car in ["lotus_elise_sc", "bmw_m3_e30", "abarth500"]:
        name = f"pack__{car}__{track}"
        folder = OUT / name
        folder.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        proc = subprocess.run(
            [str(EXE), "--car", car, "--track", track, "--spawn", "hotlap",
             "--size", "960x540", "--frames", "3", "--out", str(folder), "--name", name],
            env={"AC_ROOT": str(PACK), "PATH": os.environ["PATH"], "CARGO_BUILD_JOBS": "2"},
            capture_output=True, text=True, timeout=300)
        elapsed = time.monotonic() - started
        log = proc.stdout + "\n--- STDERR ---\n" + proc.stderr
        (folder / "render.log").write_text(log, encoding="utf-8", errors="replace")
        png = folder / f"{name}.png"
        ok = proc.returncode == 0 and png.exists()
        print(f"[{'OK' if ok else 'FAIL'}] {car} @ {track} from PACK: {elapsed:.1f}s "
              f"png={png.stat().st_size if png.exists() else 0} B")
        if not ok:
            print("  errors:", [l for l in log.splitlines() if "error" in l.lower()][:5])
        results.append({"car": car, "track": track, "ok": ok,
                        "wall_seconds": round(elapsed, 2),
                        "png_bytes": png.stat().st_size if png.exists() else 0})

(OUT / "pack_verify.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
ok = all(r["ok"] for r in results)
print("RESULT:", "PACK IS SELF-CONTAINED" if ok else "PACK INCOMPLETE")
raise SystemExit(0 if ok else 1)
