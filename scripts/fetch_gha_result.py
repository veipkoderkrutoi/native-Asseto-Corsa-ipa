#!/usr/bin/env python3
"""Inspect a real GitHub Actions run once the repository is public and triggered.

Usage:
  GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=12345 \
  GITHUB_TOKEN=ghp_... python3 scripts/fetch_gha_result.py

Without GITHUB_TOKEN, public run metadata/jobs are readable but artifacts and
job logs cannot be downloaded. Nothing is claimed until a real run is inspected.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import zipfile
from io import BytesIO
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "phase6" / "gha"
OUT.mkdir(parents=True, exist_ok=True)
API = "https://api.github.com"


def api(path: str, token: str | None) -> dict:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "ac-ios-port-audit"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(API + path, headers=headers)
    with urlopen(req, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def download(url: str, token: str | None) -> bytes:
    headers = {"User-Agent": "ac-ios-port-audit"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=120) as response:
        return response.read()


def first_error(log: str) -> str:
    lines = log.splitlines()
    pattern = re.compile(r"error:|fatal error:|Undefined symbols|LD :|clang: error|xcodebuild: error",
                         re.I)
    for i, line in enumerate(lines):
        if pattern.search(line):
            start, end = max(0, i - 10), min(len(lines), i + 11)
            return "\n".join(f"{n+1:5}: {lines[n]}" for n in range(start, end))
    return "NO COMPILER/LINKER ERROR LINE FOUND IN LOG"


def main() -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    token = os.environ.get("GITHUB_TOKEN") or None
    if not repo or not run_id:
        raise SystemExit("set GITHUB_REPOSITORY=owner/repo and GITHUB_RUN_ID=<id>")

    run = api(f"/repos/{repo}/actions/runs/{run_id}", token)
    jobs = api(f"/repos/{repo}/actions/runs/{run_id}/jobs?per_page=100", token)
    print("run:", run.get("html_url"))
    print("status:", run.get("status"), "conclusion:", run.get("conclusion"))
    print("head_sha:", run.get("head_sha"))
    for job in jobs.get("jobs", []):
        print(f"job {job['name']}: {job.get('status')} / {job.get('conclusion')}")
        for step in job.get("steps", []):
            print(f"  - {step.get('name')}: {step.get('conclusion')}")

    report = {"run": run, "jobs": jobs, "artifacts": [], "ipa": None,
              "first_error_context": None}
    if token:
        artifacts = api(f"/repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100", token)
        for art in artifacts.get("artifacts", []):
            print("artifact:", art["name"], art["size"], "bytes")
            report["artifacts"].append({"name": art["name"], "size": art["size"]})
            blob = download(art["archive_download_url"], token)
            target = OUT / f"{art['name']}.zip"
            target.write_bytes(blob)
            if art["name"].startswith("AC-iOS-build-logs"):
                with zipfile.ZipFile(BytesIO(blob)) as zf:
                    for name in zf.namelist():
                        if name.endswith("xcodebuild.log"):
                            log = zf.read(name).decode("utf-8", errors="replace")
                            (OUT / "xcodebuild.log").write_text(log, encoding="utf-8")
                            report["first_error_context"] = first_error(log)
            if art["name"].startswith("AC-iOS-Prot"):
                with zipfile.ZipFile(BytesIO(blob)) as zf:
                    for name in zf.namelist():
                        if name.endswith(".ipa"):
                            payload = zf.read(name)
                            ipa = OUT / "AC-iOS-Prot-unsigned.ipa"
                            ipa.write_bytes(payload)
                            report["ipa"] = {
                                "path": str(ipa),
                                "size": len(payload),
                                "sha256": hashlib.sha256(payload).hexdigest(),
                            }
    else:
        print("NOTE: GITHUB_TOKEN not set; artifacts/logs not downloaded.")

    (OUT / "gha_result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if report["first_error_context"]:
        print("\n--- FIRST MEANINGFUL ERROR ---\n" + report["first_error_context"])
    if report["ipa"]:
        print("\nIPA SHA-256:", report["ipa"]["sha256"])
    ok = run.get("conclusion") == "success"
    print("RESULT:", "REAL GITHUB ACTIONS RUN SUCCEEDED" if ok else
          "REAL RUN NOT SUCCESSFUL - report the first error, do not claim success")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
