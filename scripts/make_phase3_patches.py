#!/usr/bin/env python3
"""Record Phase 3 visual-slice changes as an exact unified diff."""
from __future__ import annotations

import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "patches" / "phase3"
OUT.mkdir(parents=True, exist_ok=True)

EDITS: dict[str, list[tuple[str, str]]] = {
    "rust/ac-ios-runtime/Cargo.toml": [(
        'rustyac-render = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-render", features = ["backend-wgpu"] }',
        'rustyac-render = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-render", features = ["backend-wgpu"] }\n'
        '# Enables rustyac_game::render::ac (AcRenderer) with the wgpu/kgl backend.\n'
        'rustyac-game = { path = "../../third_party/rustyAC-src/rustyAC-master/crates/rustyac-game", features = ["wgpu"] }',
    )],
    "core/ac_pal_bridge.h": [(
        "void ac_pal_bridge_snapshot(float out[16]);",
        "void ac_pal_bridge_snapshot(float out[16]);\n\n"
        "/// Opaque live session handle for the native renderer (NULL when no session).\n"
        "void *ac_pal_bridge_session(void);",
    )],
    "core/ac_pal_bridge.c": [(
        "void ac_pal_bridge_snapshot(float out[16]) {",
        "void *ac_pal_bridge_session(void) {\n    return g_session;\n}\n\n"
        "void ac_pal_bridge_snapshot(float out[16]) {",
    )],
    "rust/ac-ios-runtime/src/lib.rs": [
        ("#[cfg(target_os = \"ios\")]\nmod metal;",
         "#[cfg(target_os = \"ios\")]\nmod metal;\n#[cfg(target_os = \"ios\")]\nmod render;"),
        ("/// A real rustyAC session plus the control values the native bridge writes.\nstruct RealSession {",
         "/// A real rustyAC session plus the control values the native bridge writes.\npub(crate) struct RealSession {"),
    ],
}


def main() -> None:
    diffs = []
    for rel, edits in EDITS.items():
        text = (ROOT / rel).read_text(encoding="utf-8")
        for old, new in edits:
            if new not in text:
                raise SystemExit(f"{rel}: new text missing, change not applied")
            diffs.append("".join(difflib.unified_diff(
                old.splitlines(keepends=True), new.splitlines(keepends=True),
                fromfile="a/" + rel, tofile="b/" + rel, n=2)))
            print(f"[RECORDED] {rel}")
    target = OUT / "0001-first-visible-drive.patch"
    target.write_text("".join(diffs), encoding="utf-8")
    print(f"Wrote {target} ({target.stat().st_size} bytes)")
    print("New files (full sources in checkpoint): rust/ac-ios-runtime/src/render.rs, "
          "phase3/PHASE3_VISUAL_REPORT.md")


if __name__ == "__main__":
    main()
