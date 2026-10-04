#!/usr/bin/env python3
"""check_exports.py - winmm proxy exports parity test.

Why it exists: if the GAME starts importing a winmm function the proxy does
not export, Windows refuses to load the DLL ("Bad Image" 0xc000007b or
similar) and the user only finds out on their own machine. This test kills
that class of breakage BEFORE deploy by comparing three sources:

  1. proxy/winmm.def                        - exports the proxy PROMISES;
  2. reconstructed/winmm_exports.txt        - exports of the REAL system winmm
     ('ORDINAL<TAB>name', one per line). Ideal source of truth: it is the
     same file gen_winmm_stubs.py consumes;
  3. --dll <path> (optional)                - exports of a COMPILED winmm.dll,
     read with objdump (x86_64-w64-mingw32-objdump or llvm-objdump on PATH).

Rules:
  - REAL - DEF empty   => OK (everything the system has, the proxy exports).
  - REAL - DEF missing => ERROR (exit 1): a new game import would break the
    proxy. Lists the missing ones to regenerate with gen_winmm_stubs.py.
  - DEF - REAL extra   => WARNING (does not fail): an extra export in the
    proxy is harmless.
  - DEF - DLL (with --dll) missing => ERROR: the .def promised something the
    linker did not produce (typo in the def, function removed from the
    sources).

Usage:
  python3 tools/check_exports.py                       # def vs real (if a dump exists)
  python3 tools/check_exports.py --dll dist/winmm.dll  # + validates the compiled binary
"""
from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent          # unlocker-CoelhoFZ/
PROXY = ROOT / "proxy"
DEF_FILE = PROXY / "winmm.def"
RECON = ROOT.parent / "reconstructed" / "winmm_exports.txt"     # ../reconstructed/


def load_def_names() -> list[str]:
    """Names exported according to proxy/winmm.def (EXPORTS section)."""
    names: list[str] = []
    in_exports = False
    for raw in DEF_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split(";")[0].strip()
        if not line:
            continue
        if line.upper() == "EXPORTS":
            in_exports = True
            continue
        if not in_exports:
            continue
        if re.match(r"^[A-Za-z]", line):
            # 'name' ou 'name @ordinal' ou 'name=other'
            name = re.split(r"[\s=@]+", line)[0]
            if name:
                names.append(name)
    return names


def load_real_exports() -> dict[str, int] | None:
    """Real system winmm exports (ORDINAL<TAB>name), if the dump exists."""
    if not RECON.exists():
        return None
    real: dict[str, int] = {}
    for raw in RECON.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise SystemExit(f"invalid format in {RECON}: {line!r} (expected 'ORDINAL<TAB>name')")
        real[parts[1].strip()] = int(parts[0].strip())
    return real


def load_dll_exports(dll: pathlib.Path) -> set[str]:
    """Exports of a compiled PE, via objdump -p (mingw or llvm)."""
    objdump = shutil.which("x86_64-w64-mingw32-objdump") or shutil.which("llvm-objdump") or shutil.which("objdump")
    if not objdump:
        raise SystemExit("objdump not found (install binutils-mingw-w64 or llvm)")
    out = subprocess.run([objdump, "-p", str(dll)], capture_output=True, text=True, check=True).stdout
    names: set[str] = set()
    # Export table lines: "  [   0] mciExecute" / "[  1/123] foo" vary
    # between binutils; the stable marker is the "Export Address Table"/
    # "[Ordinal/Name Pointer]" section. We grab any '<num>] <ident>' line.
    for line in out.splitlines():
        m = re.match(r"\s*\[\s*\d+\]\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
        if m:
            names.add(m.group(1))
    if not names:
        raise SystemExit(f"no exports read from {dll} - objdump did not understand the PE? ({objdump})")
    return names


def main() -> int:
    ap = argparse.ArgumentParser(description="winmm proxy exports parity")
    ap.add_argument("--dll", type=pathlib.Path, help="compiled winmm.dll to validate against the .def")
    args = ap.parse_args()

    def_names = load_def_names()
    print(f"[def] {len(def_names)} exports promised in proxy/winmm.def")
    if not def_names:
        print("ERROR: winmm.def has no exports - corrupted file?")
        return 1

    rc = 0

    real = load_real_exports()
    if real is None:
        print("[real] WARNING: reconstructed/winmm_exports.txt missing - skipping comparison")
        print("       against the real winmm (run on a machine that has the system dump).")
    else:
        missing = sorted(set(real) - set(def_names))
        extra = sorted(set(def_names) - set(real))
        if missing:
            print(f"[real] ERROR: {len(missing)} REAL winmm export(s) missing from the proxy:")
            for n in missing:
                print(f"  - {n} (ordinal {real[n]})")
            print("  Regenerate the stubs: python3 proxy/gen_winmm_stubs.py && rebuild.")
            rc = 1
        else:
            print(f"[real] OK: proxy covers all {len(real)} real winmm exports")
        if extra:
            print(f"[real] WARNING: {len(extra)} export(s) in the proxy that do not exist in the real winmm:")
            for n in extra:
                print(f"  - {n}")
            print("  (harmless: their GetProcAddress would fail silently, but")
            print("   check whether it is a leftover from an old region).")

    if args.dll:
        if not args.dll.exists():
            print(f"[dll] ERROR: {args.dll} does not exist")
            return 1
        dll_names = load_dll_exports(args.dll)
        missing_dll = sorted(set(def_names) - dll_names)
        if missing_dll:
            print(f"[dll] ERROR: {len(missing_dll)} .def export(s) MISSING from the compiled binary:")
            for n in missing_dll:
                print(f"  - {n}")
            rc = 1
        else:
            print(f"[dll] OK: binary exports all {len(def_names)} .def names "
                  f"({len(dll_names)} total exports)")

    if rc == 0:
        print("check_exports: OK")
    else:
        print("check_exports: FAILED")
    return rc


if __name__ == "__main__":
    sys.exit(main())
