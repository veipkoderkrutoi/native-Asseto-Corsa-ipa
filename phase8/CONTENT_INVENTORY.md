# CONTENT INVENTORY (Phase 8 / Phase 7 pack)

Four separate states: Discovered / Imported / Compatible / Load tested.

Total cars discovered in original install: 178
Total tracks discovered in original install: 21

## Cars (selected for the first content pack)

| Object ID | Discovered | Imported | Compatible | Load tested | Result |
|---|---|---|---|---|---|
| lotus_elise_sc | True | True | True (kn5=True acd=True collider=True) | True | OK |
| bmw_m3_e30 | True | True | True (kn5=True acd=True collider=True) | True | OK |
| abarth500 | True | True | True (kn5=True acd=True collider=True) | True | OK |

## Tracks (selected for the first content pack)

| Object ID | Discovered | Imported | Compatible | Load tested | Result |
|---|---|---|---|---|---|
| magione | True | True | True (models.ini=True kn5=True) | True | OK |
| imola | True | True | True (models.ini=True kn5=True) | True | OK |

## Why only 3 cars and 2 tracks appear in the iOS menu

The menu lists `<selected root>/content/cars` and `/content/tracks`. The personal pack built in Phase 7 deliberately contains only the 3 cars and 2 tracks that were render-tested (275 files actually read by the renderer). The other 175 cars / 19 tracks were DISCOVERED but NOT IMPORTED into the pack - they were not filtered by compatibility at runtime; they were simply never copied. This is expected and documented, not a bug.

Physics configs (data.acd) were imported together with the models (manifest.json in the pack records them).

Selecting a track whose files were not imported cannot succeed because it does not appear in the menu; the earlier crash was NOT a missing-track selection but a renderer panic (see PHASE8 crash forensics).
