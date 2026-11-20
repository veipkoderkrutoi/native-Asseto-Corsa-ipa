#!/usr/bin/env python3
"""Phase 11.10 validator: real file-existence checks for the five affected
cars, driven by the Phase 11.9 dependency manifest (no hardcoded PASS)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"
REQ = json.loads((ROOT / "phase11_9/content_requirements.json").read_text(encoding="utf-8"))["combinations"]
INV = [l.strip() for l in (ROOT / "phase11_10/missing_inventory.txt").read_text(encoding="utf-8").splitlines() if l.strip()]

CARS = ["ks_toyota_ae86", "ks_nissan_370z", "ks_ford_gt40",
        "ks_audi_sport_quattro", "bmw_m3_e92_drift"]
TRACKS = ["magione", "imola", "trento-bondone"]

failures = 0
for car in CARS:
    total_missing = []
    for track in TRACKS:
        entry = REQ.get(f"{car}|{track}")
        if not entry:
            failures += 1
            print(f"FAIL {car}|{track}: no manifest entry")
            continue
        missing = [p for p in entry["required"] if not (PACK / p).is_file()]
        total_missing.extend(missing)
    if total_missing:
        failures += 1
        print(f"FAIL {car}: {len(set(total_missing))} required files missing")
        for p in sorted(set(total_missing))[:8]:
            print("   ", p)
    else:
        print(f"PASS {car}: all required resources present for {len(TRACKS)} tracks")

missing_inventory = [p for p in INV if not (PACK / p).is_file()]
if missing_inventory:
    failures += 1
    print("FAIL inventory:", missing_inventory)
else:
    print(f"PASS inventory: all {len(INV)} reported files present in local pack")

print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures})")
raise SystemExit(1 if failures else 0)
