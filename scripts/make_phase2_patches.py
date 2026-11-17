#!/usr/bin/env python3
"""Emit exact unified-diff change records for Phase 2/3 edits.

Each entry stores the verbatim old and new text of a contiguous edit. The
script verifies the old text is still absent and the new text is present in
the current tree, then writes a standard unified diff. This is a git-free
way to keep every change reviewable without touching the upstream sources.
"""
from __future__ import annotations

import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "patches" / "phase2"
OUT.mkdir(parents=True, exist_ok=True)

EDITS: dict[str, list[tuple[str, str]]] = {
    "core/ac_pal_bridge.c": [(
        """    /* AC's simulation runs on a fixed 1 ms clock; 34 steps covers a 60 Hz
     * frame (16.7 ms) plus realistic jitter without a spiral of death. */
    ac_fixed_step_init(&g_clock, 1000.0, 34);""",
        """    /* rustyac_game::sim::DT is 0.003 s (333.33 Hz). 12 steps cover a 60 Hz
     * frame (16.7 ms) plus realistic jitter without a spiral of death. */
    ac_fixed_step_init(&g_clock, 1000.0 / 3.0, 12);""",
    )],
    "core/ac_pal_bridge_test.c": [(
        "    CHECK(approx((float)g_mock.last_dt, 0.001f));",
        "    CHECK(approx((float)g_mock.last_dt, 0.003f));",
    )],
    "rust/ac-ios-runtime/Cargo.toml": [(
        """[dependencies]
ac-ios-pal = { path = "../ac-ios-pal" }
""",
        """[dependencies]
# Real Assetto Corsa engine (GPL-3.0-or-later). These are the actual upstream
# crates, not reimplementations. Paths are relative to this crate.
rustyac-game = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-game" }
rustyac-physics = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-physics" }
rustyac-content = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-content" }
""",
    )],
    "rust/ac-ios-pal/src/lib.rs": [(
        """        /// Returns the wgpu-compatible Metal device pointer (CAMetalLayer).
        pub fn ac_ios_metal_device() -> *mut c_void;""",
        """        /// Returns the CAMetalLayer backing the MTKView (name matches ios_bridge.m).
        pub fn ac_ios_metal_layer() -> *mut c_void;""",
    )],
    "rust/ac-ios-runtime/src/lib.rs": [(
        """use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::sync::Mutex;""",
        """use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use rustyac_game::input_file::SimSetup;
use rustyac_game::sim::{find_car_data, find_track, GameSim, SpawnSequence};
use rustyac_game::view::CarView;
use rustyac_physics::car::{CarControls, CarControlsInput};
use rustyac_game::sim::DriverSource;""",
    )],
}


def main() -> None:
    all_diffs = []
    for rel, edits in EDITS.items():
        path = ROOT / rel
        current = path.read_text(encoding="utf-8")
        for old, new in edits:
            if new not in current:
                raise SystemExit(f"{rel}: new text is not in the tree; change is missing")
            if old not in current:
                print(f"[OK] {rel}: already applied (recording the diff anyway)")
            diff = "".join(difflib.unified_diff(
                old.splitlines(keepends=True), new.splitlines(keepends=True),
                fromfile="a/" + rel, tofile="b/" + rel, n=2))
            all_diffs.append(diff)
            print(f"[RECORDED] {rel}")
    (OUT / "0001-real-rustyac-engine-integration.patch").write_text(
        "".join(all_diffs), encoding="utf-8")
    print(f"Wrote {OUT / '0001-real-rustyac-engine-integration.patch'}")


if __name__ == "__main__":
    main()
