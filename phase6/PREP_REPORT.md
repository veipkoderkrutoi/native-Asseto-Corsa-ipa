# Phase 6.1 — preparation for the first real GitHub Actions execution

**No success is claimed.** No repository has been published and no workflow has been
triggered from this environment. This is only the pre-push preparation and the
handoff for inspecting a real run.

## 1. Pre-push audit (`scripts/prepush_audit.py`, log: `prepush_audit.log`)

- Git binary: **absent** on this host; no `.git` directory → **no Git history exists yet**.
  The audit therefore checks the file tree that would be committed under the current
  `.gitignore` rules.
- Prospective tracked set after trimming vendored rustyAC docs/tools/web/packaging:
  **742 files, 34.4 MiB** (was 1,385 files / 71.0 MiB before trimming; exact list in
  `phase6/TRACKED_FILES.txt`). Files were only excluded from Git, not deleted locally.
- Credentials / tokens / private keys / Apple IDs / app-specific passwords:
  **none found**.
- Proprietary game resources (`.kn5`, `.acd`, `.bank`, `.fsb`, `.dds`, `.ksanim`,
  `.acreplay`): **none found** in the prospective tracked set.
- Informational-only findings: local Windows username paths in historic logs and
  documentation (`C:\Users\User`, `D:\Games\assettocorsa`), SHA/commit hex strings,
  and rendered screenshots (`.png/.jpg`) used as evidence. None are secrets or
  game assets.
- Required sources and all three rustyAC license files present; no accidental
  `target/`, `build/` or `checkpoint/` files in the tracked set.
- Result: **PRE-PUSH AUDIT PASSED**.

## 2. Third-party licenses

Documented in `docs/THIRD_PARTY.md`: rustyAC game/physics/render are
GPL-3.0-or-later, several helper crates MIT OR Apache-2.0, ODE port BSD-3-Clause;
license texts verified in `third_party/rustyAC-src/rustyAC-master/LICENSE-*`.

## 3. Workflow hardening (`scripts/verify_workflow_refs.py`: 11/11 PASS)

- `permissions: contents: read` only (least privilege).
- `runs-on: macos-15`, Xcode/iPhoneOS SDK versions and `df -h .` recorded into
  `build/ios/toolchain.txt`.
- Full `xcodebuild` output captured with `tee build/ios/xcodebuild.log`.
- Both logs and the IPA uploaded with **7-day retention**.
- Cargo cache added to avoid full rebuilds on repeat runs; `CARGO_BUILD_JOBS=2`.
- No signing secrets required for the unsigned artifact.
- Verified step order: **Rust build finishes before Xcode starts**; no backgrounded
  build commands, no parallel matrix.

## 4. Runner disk space

GitHub documentation (checked 2026-11-17): standard `macos-15` runner has **14 GB SSD**
(3-core M1, 7 GB RAM). Our measured local iOS release Rust output is **459.7 MB**;
Xcode derived data for this small app should fit comfortably. The workflow records
the actual `df -h .` on the runner in the log artifact.

## 5. Checkpoint

`checkpoint/after_phase5/` preserved (20 files, including the verified staticlib and
SHA-256 manifest).

## 6. After the user publishes and triggers

Use `scripts/fetch_gha_result.py` with `GITHUB_REPOSITORY`, `GITHUB_RUN_ID` and a
`GITHUB_TOKEN` (artifacts/logs need auth). It will:
- print job/step conclusions, Xcode and iPhoneOS SDK versions from the toolchain log;
- download `AC-iOS-build-logs`, extract the complete `xcodebuild.log`;
- print the **first compiler/linker error with ±10 lines of context**;
- download the unsigned IPA, compute and print its SHA-256;
- write `phase6/gha/gha_result.json`.

Only a real successful run with a downloaded, audited IPA counts. If it fails, report
the first meaningful error and its context before changing anything else.
