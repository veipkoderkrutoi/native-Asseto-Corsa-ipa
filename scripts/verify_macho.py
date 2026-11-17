#!/usr/bin/env python3
"""Standalone verifier for the generated ARM64 iOS Mach-O object.

Checks the 64-bit little-endian Mach-O header, ARM64 cputype, MH_OBJECT
filetype and walks the load commands. No Apple SDK or external tools needed.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0
MH_OBJECT = 0x1

LOAD_COMMANDS = {
    0x2: "LC_SYMTAB",
    0xB: "LC_DYSYMTAB",
    0x19: "LC_SEGMENT_64",
    0x29: "LC_BUILD_VERSION",
    0x32: "LC_FUNCTION_STARTS",
    0x26: "LC_LINKER_OPTION",
    0x2A: "LC_DYLD_EXPORTS_TRIE",
    0x2B: "LC_DYLD_CHAINED_FIXUPS",
}


def verify(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 32:
        raise SystemExit(f"{path}: too short to be a Mach-O 64 header")

    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = \
        struct.unpack_from("<IiiIIIII", data, 0)

    checks = {
        "magic_64": magic == MH_MAGIC_64,
        "little_endian": data[:4] == b"\xcf\xfa\xed\xfe",
        "cputype_arm64": cputype == CPU_TYPE_ARM64,
        "cpusubtype_all": cpusub == CPU_SUBTYPE_ARM64_ALL,
        "filetype_object": filetype == MH_OBJECT,
        "header_fits": 32 + sizeofcmds <= len(data),
    }

    cmds = []
    off = 32
    for _ in range(ncmds):
        if off + 8 > len(data):
            checks["load_commands_fit"] = False
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        cmds.append({"cmd": LOAD_COMMANDS.get(cmd, hex(cmd)), "cmdsize": cmdsize})
        if cmdsize < 8:
            checks["load_command_sizes"] = False
            break
        off += cmdsize
    else:
        checks["load_commands_fit"] = off == 32 + sizeofcmds
        checks["load_command_sizes"] = True

    return {
        "path": str(path),
        "size": len(data),
        "magic": hex(magic),
        "cputype": hex(cputype & 0xFFFFFFFF),
        "cpusubtype": cpusub,
        "filetype": filetype,
        "ncmds": ncmds,
        "sizeofcmds": sizeofcmds,
        "flags": hex(flags),
        "load_commands": cmds,
        "checks": checks,
        "ok": all(checks.values()),
    }


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent.parent / "artifacts" / "ac_pal_bridge.arm64.o"
    result = verify(path)
    for key, value in result.items():
        if key != "checks":
            print(f"{key}: {value}")
    print("--- checks ---")
    for key, value in result["checks"].items():
        print(f"[{'PASS' if value else 'FAIL'}] {key}")
    print("RESULT:", "ARM64 Mach-O object verified" if result["ok"] else "VERIFICATION FAILED")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
