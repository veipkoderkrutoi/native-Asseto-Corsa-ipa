#!/usr/bin/env python3
"""Measure peak process memory while loading track + car from the content pack.

Windows host only. Uses GetProcessMemoryInfo via ctypes on the child process;
reports PeakWorkingSetSize / PrivateUsage. This is a HOST measurement, not an
iPhone number.
"""
from __future__ import annotations

import ctypes
import json
import os
import subprocess
import time
from ctypes import wintypes
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "content_pack"
OUT = ROOT / "phase7" / "memory"
OUT.mkdir(parents=True, exist_ok=True)
EXE = ROOT / "third_party/rustyAC-src/rustyAC-master/target/release/examples/full_frame.exe"

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010


class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t)]


k32 = ctypes.windll.kernel32


def peak_memory_mb(pid: int) -> tuple[float, float]:
    handle = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return (0.0, 0.0)
    try:
        counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        ok = ctypes.windll.psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb)
        if not ok:
            return (0.0, 0.0)
        return (counters.PeakWorkingSetSize / 1024 / 1024,
                counters.PeakPagefileUsage / 1024 / 1024)
    finally:
        k32.CloseHandle(handle)


results = []
for track in ["magione", "imola"]:
    for car in ["lotus_elise_sc", "bmw_m3_e30"]:
        name = f"mem__{car}__{track}"
        folder = OUT / name
        folder.mkdir(parents=True, exist_ok=True)
        proc = subprocess.Popen(
            [str(EXE), "--car", car, "--track", track, "--spawn", "hotlap",
             "--size", "960x540", "--frames", "8", "--out", str(folder), "--name", name],
            env={"AC_ROOT": str(PACK), "PATH": os.environ["PATH"], "CARGO_BUILD_JOBS": "2"},
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        peak_ws = peak_pf = 0.0
        while proc.poll() is None:
            ws, pf = peak_memory_mb(proc.pid)
            peak_ws = max(peak_ws, ws)
            peak_pf = max(peak_pf, pf)
            time.sleep(0.05)
        proc.wait(timeout=60)
        entry = {"car": car, "track": track, "peak_working_set_mb": round(peak_ws, 1),
                 "peak_pagefile_mb": round(peak_pf, 1), "exit_code": proc.returncode}
        results.append(entry)
        print(f"{car} @ {track}: peak WS {peak_ws:.0f} MB, peak commit {peak_pf:.0f} MB")

(OUT / "memory.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
print("NOTE: host measurement; not iPhone 13 Pro Max numbers.")
