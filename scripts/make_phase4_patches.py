#!/usr/bin/env python3
"""Record Phase 4 controls changes as an exact unified diff."""
import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "patches" / "phase4"
OUT.mkdir(parents=True, exist_ok=True)

EDITS = {
    "core/ac_pal_bridge.h": [
        ("void ac_pal_bridge_set_input(float steer, float throttle, float brake);",
         "void ac_pal_bridge_set_input(float steer, float throttle, float brake);\n\n"
         "/* Sets the full control state for the next physics steps. gear_up/gear_down/\n"
         " * camera_next are ONE-SHOT requests: the bridge consumes them on the next\n"
         " * simulation step so a held button cannot repeat shifts every 3 ms. */\n"
         "void ac_pal_bridge_set_controls(float steer, float throttle, float brake,\n"
         "                                float handbrake, int gear_up, int gear_down,\n"
         "                                int camera_next);"),
    ],
    "core/ac_pal_bridge.c": [
        ("    g_vt.session_set_input(g_session, g_steer, g_throttle, g_brake);\n        g_vt.session_step(g_session, dt);",
         "    g_vt.session_set_input(g_session, g_steer, g_throttle, g_brake);\n"
         "        if (g_vt.session_set_ext_input) {\n"
         "            g_vt.session_set_ext_input(g_session, g_handbrake,\n"
         "                                       g_gear_up_pending, g_gear_dn_pending,\n"
         "                                       g_camera_pending);\n"
         "        }\n"
         "        /* Consume one-shot requests exactly once, regardless of step count. */\n"
         "        g_gear_up_pending = g_gear_dn_pending = g_camera_pending = 0;\n"
         "        g_vt.session_step(g_session, dt);"),
    ],
    "rust/ac-ios-runtime/src/lib.rs": [
        ("    pub session_step: Option<unsafe extern \"C\" fn(*mut c_void, c_double)>,",
         "    pub session_set_ext_input: Option<\n"
         "        unsafe extern \"C\" fn(*mut c_void, f32, c_int, c_int, c_int),\n"
         "    >,\n"
         "    pub session_step: Option<unsafe extern \"C\" fn(*mut c_void, c_double)>,"),
        ("    setup.auto_shifter = true;",
         "    setup.auto_shifter = AUTO_SHIFTER.load(Ordering::Relaxed);"),
    ],
    "ios/ios_bridge.h": [
        ("int  ac_ios_install_core_vtable(void);",
         "int  ac_ios_install_core_vtable(void);\n"
         "/* Set BEFORE creating a session: 1 = automatic gearbox, 0 = manual paddles. */\n"
         "void ac_ios_set_auto_shifter(int enabled);"),
    ],
}

diffs = []
for rel, edits in EDITS.items():
    text = (ROOT / rel).read_text(encoding="utf-8")
    for old, new in edits:
        if new not in text:
            raise SystemExit(f"{rel}: change not present")
        diffs.append("".join(difflib.unified_diff(
            old.splitlines(keepends=True), new.splitlines(keepends=True),
            fromfile="a/" + rel, tofile="b/" + rel, n=2)))
        print("[RECORDED]", rel)

target = OUT / "0001-playable-controls.patch"
target.write_text("".join(diffs), encoding="utf-8")
print(f"Wrote {target} ({target.stat().st_size} bytes)")
print("New files: rust/ac-ios-runtime/examples/bench_render.rs, "
      "phase4/PHASE4_CONTROLS_REPORT.md")
