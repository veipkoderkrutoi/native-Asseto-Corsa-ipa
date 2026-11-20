# Phase 11.10 — Complete missing assets repair

## 1. Inventory audit (39 reported paths)

Every one of the 39 reported resources exists **both** in the original install
`D:\Games\assettocorsa` and in the local Content Pack. Exact case and directory
names match; no file was missing from the source game. Full per-path sizes and
presence are in `phase11_10/inventory_audit.json`.

Two files were absent from **all previous transfer patches** and therefore
could never have reached the iPhone through them:
- `content/cars/ks_ford_gt40/animations/car_door_R.ksanim`
- `content/cars/ks_audi_sport_quattro/animations/car_door_L.ksanim`

The other 37 were present in `content-dependencies-fix.zip` / `driver-fix.zip`;
the user's device state evidently did not include them (which is exactly what
Preflight reported). No original file was modified, and no substitute DDS/font/
animation was created.

## 2. Why the validator reported them (manifest investigation)

All 39 paths are **already** in the Phase 11.9 required union:
`python` check → `39 of 39 present in required union`. The manifest was built
from the real renderer's `full_frame --files` logs, so the dependencies were
correctly identified; the failure was purely delivery to the device. No
requirement was downgraded and Preflight validation remains fully enabled.
`content/driver/driver_60.kn5` and `_B` keep their optional classification
(the 3D-driver fallback in `driver.rs` is unchanged).

## 3. Per-car results (real file existence checks)

`scripts/phase11_10_validate.py` checks every required path from the Phase 11.9
manifest for all three tracks:

```text
PASS ks_toyota_ae86: all required resources present for 3 tracks
PASS ks_nissan_370z: all required resources present for 3 tracks
PASS ks_ford_gt40: all required resources present for 3 tracks
PASS ks_audi_sport_quattro: all required resources present for 3 tracks
PASS bmw_m3_e92_drift: all required resources present for 3 tracks
PASS inventory: all 39 reported files present in local pack
RESULT: PASS
```

## 4. Real rendering verification (not just existence)

The upstream `full_frame` renderer was run with `AC_ROOT` pointing at the
**local Content Pack** for all five affected cars on Magione:

```text
ks_toyota_ae86       exit=0  png=406127 B
ks_nissan_370z       exit=0  png=414389 B
ks_ford_gt40         exit=0  png=419194 B
ks_audi_sport_quattro exit=0 png=402220 B
bmw_m3_e92_drift     exit=0  png=412767 B
```

This exercises DDS decoding, font atlases/metadata, KSANIM animations and
driver textures from the pack. One non-fatal upstream message remains in the
Nissan log: `ERROR: CANNOT FIND DigitalLed mesh:GEO_LEDS_WATER_0`
(`rustyac-render/src/digital.rs:881`) — a dashboard mesh reference inside the
car's own KN5 configuration, not a missing external file; rendering completes
with exit 0 and a valid PNG. It is documented, not hidden.

## 5. Incremental patch

`C:\Users\User\Desktop\AC-iOS-content-pack\content-assets-fix-11.10.zip`

- Size: **11,467,807 B (10.94 MiB)**
- SHA-256: **`011d36c13e8cbaea2f4e44c673b3ad4d1e4a24c80de909f729ffd8c128332e87`**
- 39 unique files + `MANIFEST.json` (relative path, size, SHA-256 per file)
- No nested `content/content/`, no duplicates, all checksums verified from the ZIP
- Safe to merge into an existing `Documents/AC-iOS/content`; nothing is deleted

The manifest/checksum list is also at `phase11_10/content_assets_fix_manifest.json`.

## 6. Code changes / IPA

None required: the validator, importer, dependency manifest and Phase 10 memory
protections already work correctly. The current IPA remains valid
(SHA `5874bde2c837b70cd60c38beaa1b9c8dd0d664ecc9cbf46bfaa69fde01767f4a`).
No new IPA was built, per the instruction to build one only if code changes are
necessary.

## 7. Device validation

The reported failures came from the real iPhone Preflight. The new patch has
**not yet been applied/tested on the device**:

**REAL DEVICE PREFLIGHT VALIDATION: NOT CONFIRMED.**

After applying the patch, all five cars should show `CONTENT VALIDATION PASSED`.
