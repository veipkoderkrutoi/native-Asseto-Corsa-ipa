# Phase 0 + Phase 1 — audited facts and real Windows baseline

Status: **PASS with a documented version caveat.** All claims below are backed by files in
this folder.

## Phase 0 — version / compatibility audit

| Item | Installed (user's copy) | rustyAC expectation | Verdict |
|---|---|---|---|
| `changelog.txt` | **1.16.2** | README says 1.16 (oracle tools: 1.16.4) | mismatch in point release |
| `acs.exe` PE TimeDateStamp | **0x5a37e319** (2017-12-18) | `tools/car_oracle/src/acs.rs:20` `EXPECTED_TIMESTAMP = 0x5a55e7a8` (1.16.4) | **different build** |
| launcher `AssettoCorsa.exe` version | **0.17.1222.5071** | `rustyac-launcher/src/setup.rs:15` `LAUNCHER_VERSION = "0.18.115.5097"` | **different build** |
| YEBIS filmic table @0x527cc0 | not present | expected by post-processing | **observed runtime degradation** |

Observed in the real run log (`run_direct.log:55`):
```
yebis: no filmic table at 0x527cc0 (not acs.exe 1.16?); post-processing without YEBIS
```

**Conclusion:** compatibility is **not proven bit-exact** for this install. The oracle
tools (which map `acs.exe` functions side by side) target a different PE build and were
not used. However, content loading, car physics, session setup and rendering with real
AC resources were empirically verified below. Post-processing is degraded (no YEBIS).

## Phase 1 — real Windows baseline (no iOS changes)

Environment: `AC_ROOT=D:\Games\assettocorsa`, upstream master untouched apart from the
previously verified iOS patch which was **not applied** to this tree.

### Build — PASS
```
cargo build --release -p rustyac-launcher -p rustyac-game
Finished `release` profile [optimized] target(s) in 4m 21s
```
Artifacts: `target/release/rustyac-launcher.exe` (1,610,752 B),
`target/release/rustyac.exe` (12,057,088 B). Full log: `build.log`, exit: `build.exit`.

### Real launcher and session — PASS (observed, not inferred)
1. Game detection: launcher UI loaded from the install (language screen, player profile,
   News/Stats/Career, AC Channel). Screenshot `screenshots/01_launcher_loaded.png`.
2. Car list: `SELECT CAR` opened brand grid (ABARTH, ALFA ROMEO, AUDI, BMW, CHEVROLET,
   FERRARI, FORD, KTM, LOTUS, …) — all from `D:\Games\assettocorsa`. Screenshot `02_…`.
3. Track list: `SELECT TRACK` showed Laguna Seca, Magione, Monza 1966 Full/Junior/Road
   Course. Screenshot `03_track_list.png`.
4. Car + track loaded: HUD showed `Lotus Elise SC` / `magione`, tyre SM, session Time
   Attack 30 min, air 26 °C, asphalt 34 °C, grip 100 %. Real 3D scene with the car,
   shadows, track and environment rendered. Screenshot `04_real_session_...png`.
5. Session started: `TIME ATTACK START!`, then live cockpit view with ideal line and
   trackside objects. Screenshot `05_real_driving_cockpit.png`.
6. **Real car state change under control:** holding `Up` (GAS binding confirmed in
   `cfg/controls.ini:24` as `0x26 ; Up`) moved the car; lap timer advanced to `71.140"`,
   tachometer needles moved, scenery changed from grid to the "100" board straight.
   `C` changed camera to cockpit, proving keyboard events reach the game.

Exact verified command line (from `Win32_Process`):
```
rustyac.exe --documents <target/release> --out-dir <target/release/out> \
  --car lotus_elise_sc --track magione
```

### Direct-run log — PASS
`run_direct.log` (31,746 B) + `run_direct.err` show real loads:
- conditions from `target/release/cfg/race.ini`, aids from `assists.ini`,
  bindings from `controls.ini`;
- `maths: MSVCR120.dll, the runtime Assetto Corsa itself uses` — uses the real AC DLL;
- real asset loads: `D:/Games/assettocorsa/content/texture/...`, pit crew `.ksanim`,
  `cubemap_model.kn5`, weather `4_mid_clear`, AC fonts;
- only real warning: shared-memory conflict because the launcher-started game was still
  running (expected), plus the YEBIS mismatch above.

### Errors / diagnostics encountered
- First game window appeared black and "Not responding" for ~8 s during heavy asset
  loading; it recovered on its own into a full 3D scene — not a crash.
- `Up` alone appeared to do nothing until the session actually started (`TIME ATTACK
  START!`); the pre-start state ignores driving input. No code defect concluded.
- Shared-memory warning is caused by two concurrent rustyAC processes, not content.

## Classification

- **Implemented and verified (Windows):** build, game detection, car list, track list,
  car/track/scene load, session start, camera change, real throttle-driven motion.
- **Verified only on Windows:** everything above; there is no iOS build here.
- **Known degraded:** YEBIS post-processing disabled due to 1.16.2 vs 1.16.4 binary.
- **Not done in Phase 1:** any iOS integration (by design — phase order respected).
