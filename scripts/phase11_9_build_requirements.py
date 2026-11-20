#!/usr/bin/env python3
"""Phase 11.9: build the exact content requirements manifest.

`files_of_picture` is a planned superset; `full_frame --files` logs the files
the REAL rustyAC renderer actually reads. Required = actually read, optional =
planned but not read. Only relative paths are stored (no game assets).
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "phase11_9"
EXE = ROOT / "third_party/rustyAC-src/rustyAC-master/target/release/examples/full_frame.exe"
AC = Path("D:/Games/assettocorsa")
CARS = ["abarth500", "bmw_m3_e30", "lotus_elise_sc", "ks_nissan_370z",
        "ks_toyota_ae86", "ks_ford_gt40", "bmw_m3_e92_drift", "ks_audi_sport_quattro"]
TRACKS = ["magione", "imola", "trento-bondone"]

planned = json.loads((OUT / "dependency_manifest.json").read_text(encoding="utf-8"))["combinations"]
required: dict[str, list[str]] = {}
failures = []

for car in CARS:
    for track in TRACKS:
        key = f"{car}|{track}"
        name = f"{car}__{track}"
        folder = OUT / "render_checks" / name
        folder.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        proc = subprocess.run(
            [str(EXE), "--car", car, "--track", track, "--spawn", "hotlap",
             "--size", "640x360", "--frames", "1", "--out", str(folder), "--name", name],
            env={"AC_ROOT": str(AC), "PATH": os.environ["PATH"], "CARGO_BUILD_JOBS": "2"},
            capture_output=True, text=True, timeout=600)
        files_path = folder / f"{name}.files"
        read = []
        if files_path.is_file():
            read = sorted({ln.strip().replace("\\", "/") for ln in
                           files_path.read_text(encoding="utf-8", errors="replace").splitlines()
                           if ln.strip()})
        if proc.returncode != 0 or not read:
            failures.append({"key": key, "code": proc.returncode, "stderr": proc.stderr[-500:]})
            print(f"[FAIL] {key} rc={proc.returncode} files={len(read)}")
        else:
            print(f"[OK]   {key} files={len(read)} in {time.monotonic()-started:.1f}s", flush=True)
        required[key] = read

manifest = {
    "note": "Required = files actually read by rustyAC's real full_frame renderer; optional = planned superset. Relative paths only.",
    "combinations": {
        key: {
            "required": required.get(key, []),
            "optional": sorted(set(planned.get(key, [])) - set(required.get(key, []))),
        }
        for key in sorted(set(planned) | set(required))
    },
    "failures": failures,
}
path = OUT / "content_requirements.json"
path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {path} ({path.stat().st_size} bytes), failures={len(failures)}")
