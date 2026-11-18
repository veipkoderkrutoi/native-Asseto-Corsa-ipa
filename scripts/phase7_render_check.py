#!/usr/bin/env python3
"""Render 6 car/track combinations with the real upstream full_frame example.

Uses the ALREADY BUILT binary (no Cargo rebuild), captures per-combination
loader logs and the exact list of game files read (from the .files output).
"""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "phase7" / "render_checks"
OUT.mkdir(parents=True, exist_ok=True)
EXE = (ROOT / "third_party/rustyAC-src/rustyAC-master/target/release/examples/full_frame.exe")
AC = Path("D:/Games/assettocorsa")
CARS = ["lotus_elise_sc", "bmw_m3_e30", "abarth500"]
TRACKS = ["magione", "imola"]

results = []
for track in TRACKS:
    for car in CARS:
        name = f"{car}__{track}"
        folder = OUT / name
        folder.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        proc = subprocess.run(
            [str(EXE), "--car", car, "--track", track, "--spawn", "hotlap",
             "--size", "960x540", "--frames", "3",
             "--out", str(folder), "--name", name],
            env={"AC_ROOT": str(AC), "PATH": __import__("os").environ["PATH"],
                 "CARGO_BUILD_JOBS": "2"},
            capture_output=True, text=True, timeout=300)
        elapsed = time.monotonic() - started
        log = proc.stdout + "\n--- STDERR ---\n" + proc.stderr
        (folder / "render.log").write_text(log, encoding="utf-8", errors="replace")
        summary = next((l for l in proc.stdout.splitlines() if name in l and "x 540" in l), "")
        files_path = folder / f"{name}.files"
        files = files_path.read_text(encoding="utf-8", errors="replace").splitlines() if files_path.exists() else []
        png = folder / f"{name}.png"
        entry = {
            "car": car, "track": track, "exit_code": proc.returncode,
            "wall_seconds": round(elapsed, 2),
            "summary": summary,
            "png_bytes": png.stat().st_size if png.exists() else 0,
            "files_read": files,
            "error_lines": [l for l in log.splitlines() if "error" in l.lower()][:10],
        }
        results.append(entry)
        print(f"[{'OK' if proc.returncode == 0 else 'FAIL'}] {car} @ {track}: "
              f"{elapsed:.1f}s, png={entry['png_bytes']} B, files={len(files)}")
        if proc.returncode != 0:
            print("  first error:", entry["error_lines"][:3])

(OUT / "render_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
print(f"\nWrote {OUT / 'render_checks.json'}")
