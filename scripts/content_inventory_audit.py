#!/usr/bin/env python3
"""Phase D: audit four DISTINCT content states.

  Discovered  - ID present in the original install
  Imported    - files actually copied into the personal pack
  Compatible  - has KN5 + ACD + collider (car) / models.ini + KN5 (track)
  Load tested - real GameSim/renderer load succeeded (phase7 results)
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AC = Path("D:/Games/assettocorsa")
PACK = ROOT / "content_pack"
RENDER = ROOT / "phase7/render_checks/render_checks.json"
SELFTEST = ROOT / "phase7/content_selftest.json"


def discovered_ids(kind: str) -> list[str]:
    p = AC / "content" / kind
    return sorted(x.name for x in p.iterdir() if x.is_dir())


def compatible_car(car_id: str) -> tuple[bool, str]:
    d = AC / "content/cars" / car_id
    kn5 = any(d.glob("*.kn5"))
    acd = (d / "data.acd").is_file() or (d / "data/car.ini").is_file()
    col = (d / "collider.kn5").is_file()
    return kn5 and acd and col, f"kn5={kn5} acd={acd} collider={col}"


def compatible_track(track_id: str) -> tuple[bool, str]:
    d = AC / "content/tracks" / track_id
    models = (d / "models.ini").is_file()
    kn5 = any(d.glob("*.kn5"))
    return models and kn5, f"models.ini={models} kn5={kn5}"


def imported(kind: str, obj_id: str) -> bool:
    return (PACK / "content" / kind / obj_id).is_dir()


def main() -> int:
    render = json.loads(RENDER.read_text(encoding="utf-8"))
    # Parse the selftest JSON-ish output produced by the Rust example.
    selftest_text = SELFTEST.read_text(encoding="utf-8").strip()
    try:
        selftest = json.loads(selftest_text)
    except Exception:
        selftest = []
    load_ok = set()
    if isinstance(selftest, list):
        for x in selftest:
            if isinstance(x, dict) and x.get("ok"):
                load_ok.add((x["car"], x["track"]))
    render_ok = {(x["car"], x["track"]) for x in render if x["exit_code"] == 0}

    cars = ["lotus_elise_sc", "bmw_m3_e30", "abarth500"]
    tracks = ["magione", "imola"]
    lines = ["# CONTENT INVENTORY (Phase 8 / Phase 7 pack)", "",
             "Four separate states: Discovered / Imported / Compatible / Load tested.", "",
             f"Total cars discovered in original install: {len(discovered_ids('cars'))}",
             f"Total tracks discovered in original install: {len(discovered_ids('tracks'))}", "",
             "## Cars (selected for the first content pack)", "",
             "| Object ID | Discovered | Imported | Compatible | Load tested | Result |",
             "|---|---|---|---|---|---|"]
    for car in cars:
        disc = car in discovered_ids("cars")
        imp = imported("cars", car)
        comp, detail = compatible_car(car)
        tested = any(c == car for c, _ in render_ok) and any(c == car for c, _ in load_ok)
        lines.append(f"| {car} | {disc} | {imp} | {comp} ({detail}) | {tested} | "
                     f"{'OK' if all([disc, imp, comp, tested]) else 'CHECK'} |")
    lines += ["", "## Tracks (selected for the first content pack)", "",
              "| Object ID | Discovered | Imported | Compatible | Load tested | Result |",
              "|---|---|---|---|---|---|"]
    for track in tracks:
        disc = track in discovered_ids("tracks")
        imp = imported("tracks", track)
        comp, detail = compatible_track(track)
        tested = any(t == track for _, t in render_ok) and any(t == track for _, t in load_ok)
        lines.append(f"| {track} | {disc} | {imp} | {comp} ({detail}) | {tested} | "
                     f"{'OK' if all([disc, imp, comp, tested]) else 'CHECK'} |")
    lines += ["", "## Why only 3 cars and 2 tracks appear in the iOS menu", "",
              "The menu lists `<selected root>/content/cars` and `/content/tracks`. "
              "The personal pack built in Phase 7 deliberately contains only the 3 cars "
              "and 2 tracks that were render-tested (275 files actually read by the "
              "renderer). The other 175 cars / 19 tracks were DISCOVERED but NOT IMPORTED "
              "into the pack - they were not filtered by compatibility at runtime; they "
              "were simply never copied. This is expected and documented, not a bug.", "",
              "Physics configs (data.acd) were imported together with the models "
              "(manifest.json in the pack records them).", "",
              "Selecting a track whose files were not imported cannot succeed because "
              "it does not appear in the menu; the earlier crash was NOT a missing-track "
              "selection but a renderer panic (see PHASE8 crash forensics).",
              ""]
    out = ROOT / "phase8/CONTENT_INVENTORY.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines[:30]))
    print(f"\nWrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
