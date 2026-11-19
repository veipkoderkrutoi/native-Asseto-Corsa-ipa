#!/usr/bin/env python3
"""Phase 11.7: verify the newly imported AC cars/track with the REAL upstream
full_frame example (no Cargo rebuild).  Exit code 0 and a real PNG prove the
existing AC engine can load the content, not just that folders were copied.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "phase11_7" / "render_checks"
OUT.mkdir(parents=True, exist_ok=True)
EXE = ROOT / "third_party/rustyAC-src/rustyAC-master/target/release/examples/full_frame.exe"
AC = Path("D:/Games/assettocorsa")

COMBOS = [
    ("ks_nissan_370z", "magione"),
    ("ks_toyota_ae86", "magione"),
    ("ks_ford_gt40", "magione"),
    ("bmw_m3_e92_drift", "magione"),
    ("ks_audi_sport_quattro", "magione"),
    ("lotus_elise_sc", "trento-bondone"),
]

results = []
for car, track in COMBOS:
    name = f"{car}__{track}"
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    proc = subprocess.run(
        [str(EXE), "--car", car, "--track", track, "--spawn", "hotlap",
         "--size", "960x540", "--frames", "2", "--out", str(folder), "--name", name],
        env={"AC_ROOT": str(AC), "PATH": os.environ["PATH"], "CARGO_BUILD_JOBS": "2"},
        capture_output=True, text=True, timeout=600)
    elapsed = time.monotonic() - started
    log = proc.stdout + "\n--- STDERR ---\n" + proc.stderr
    (folder / "render.log").write_text(log, encoding="utf-8", errors="replace")
    png = folder / f"{name}.png"
    results.append({
        "car": car, "track": track, "exit_code": proc.returncode,
        "wall_seconds": round(elapsed, 2),
        "png_bytes": png.stat().st_size if png.exists() else 0,
        "error_lines": [l for l in log.splitlines() if "error" in l.lower()][:10],
    })
    print(f"[{'OK' if proc.returncode == 0 else 'FAIL'}] {name}: {elapsed:.1f}s "
          f"png={results[-1]['png_bytes']} B", flush=True)

(OUT / "render_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {OUT / 'render_checks.json'}")
