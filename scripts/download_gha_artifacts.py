#!/usr/bin/env python3
"""Download GHA artifacts as raw bytes (no PowerShell UTF-16 mangling)."""
import base64
import io
import json
import os
import subprocess
import sys
import urllib.request
import zipfile


class NoAuthRedirect(urllib.request.HTTPRedirectHandler):
    """Drop the Authorization header when GitHub redirects to blob storage."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_headers = {k: v for k, v in req.headers.items()
                       if k.lower() != "authorization"}
        return urllib.request.Request(
            newurl, headers=new_headers, origin_req_host=req.origin_req_host,
            unverifiable=True)
from pathlib import Path

REPO = "veipkoderkrutoi/native-Asseto-Corsa-ipa"
RUN = "44185836939"
OUT = Path(__file__).resolve().parent.parent / "phase6" / "gha" / "final"
OUT.mkdir(parents=True, exist_ok=True)


def gh_api(path: str) -> dict:
    token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/{path}",
        headers={"Authorization": f"Bearer {token}",
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "ac-ios-audit"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def download(art_id: int, dest: Path) -> None:
    token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/actions/artifacts/{art_id}/zip",
        headers={"Authorization": f"Bearer {token}", "User-Agent": "ac-ios-audit"})
    opener = urllib.request.build_opener(NoAuthRedirect())
    with opener.open(req, timeout=180) as r:
        data = r.read()
    dest.write_bytes(data)
    print(f"downloaded {dest.name}: {len(data)} bytes, magic={data[:4]!r}")


def main() -> int:
    arts = gh_api(f"actions/runs/{RUN}/artifacts")["artifacts"]
    for art in arts:
        name = art["name"]
        target = OUT / f"{name}.zip"
        download(art["id"], target)
        with zipfile.ZipFile(target) as zf:
            extract_dir = OUT / name
            extract_dir.mkdir(parents=True, exist_ok=True)
            zf.extractall(extract_dir)
            print(f"  extracted {len(zf.namelist())} entries -> {extract_dir}")
            for entry in zf.namelist():
                if entry.lower().endswith(".ipa"):
                    ipa = extract_dir / entry
                    import hashlib
                    print("  IPA:", entry, ipa.stat().st_size)
                    print("  SHA256:", hashlib.sha256(ipa.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
