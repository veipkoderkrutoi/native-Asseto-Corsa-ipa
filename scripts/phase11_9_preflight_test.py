#!/usr/bin/env python3
"""Phase 11.9 regression test for the content dependency manifest.

Checks that every file the REAL renderer read for each supported car/track is
present in the local content pack, and that the manifest covers all combos.
No game assets are committed; only relative paths are tested.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQ = ROOT / "phase11_9/content_requirements.json"
PACK = ROOT / "content_pack"

CARS = ["abarth500", "bmw_m3_e30", "lotus_elise_sc", "ks_nissan_370z",
        "ks_toyota_ae86", "ks_ford_gt40", "bmw_m3_e92_drift", "ks_audi_sport_quattro"]
TRACKS = ["magione", "imola", "trento-bondone"]

failures = 0
data = json.loads(REQ.read_text(encoding="utf-8"))
combos = data["combinations"]
for car in CARS:
    for track in TRACKS:
        key = f"{car}|{track}"
        entry = combos.get(key)
        if not entry or not entry.get("required"):
            print(f"FAIL missing manifest entry: {key}")
            failures += 1
            continue
        missing = [p for p in entry["required"] if not (PACK / p).is_file()]
        if missing:
            print(f"FAIL {key}: {len(missing)} required files missing in pack")
            for p in missing[:5]:
                print("   ", p)
            failures += 1
        else:
            print(f"OK   {key}: {len(entry['required'])} required, "
                  f"{len(entry.get('optional', []))} optional")

union = sorted({p for e in combos.values() for p in e["required"]})
print(f"union required files: {len(union)}")
if any("content/objects3D/cubemap_model.kn5" not in e["required"] for e in combos.values()):
    print("FAIL cubemap_model.kn5 not listed as required")
    failures += 1
driver_path = "content/driver/driver_no_HANS.kn5"
if not (PACK / driver_path).is_file():
    print("FAIL driver_no_HANS.kn5 missing in pack")
    failures += 1
if not any(driver_path in e["required"] for e in combos.values()):
    print("FAIL driver_no_HANS.kn5 not present in dependency manifest")
    failures += 1
# The iOS validator treats content/driver/*.kn5 as optional by path rule even
# when the renderer read it (safe no-driver fallback), so no failure here.

print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures})")
raise SystemExit(1 if failures else 0)
