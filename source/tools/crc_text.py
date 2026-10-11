# Copyright (C) 2026 CoelhoFZ
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

"""crc_text.py - CRC32 of the .text block of a PE (for the shim self-check).

build.sh --harden uses it in two passes:
  1. links the shim with -DEXPECTED_CRC32=0
  2. computes the CRC of the generated .text and relinks with
     -DEXPECTED_CRC32=<value>

Since the value only lives in .rdata/.data (outside .text), the .text does
not change between the two passes -> the CRC is stable. At runtime the shim
recomputes the CRC of its own .text (applying the inverse relocations) and
compares: a patched binary (any byte of code changed) does NOT install the
hook.

Usage: python3 tools/crc_text.py <dll>
"""
import struct
import sys
import zlib


def crc_text(path: str) -> int:
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"MZ":
        sys.exit("not a PE")
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        sys.exit("PE signature not found")
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    sec_off = e_lfanew + 24 + opt_size
    for i in range(nsec):
        off = sec_off + i * 40
        name = data[off:off + 8].rstrip(b"\0").decode(errors="replace")
        if name != ".text":
            continue
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        raw = data[rawptr:rawptr + rawsize]
        return zlib.crc32(raw) & 0xFFFFFFFF
    sys.exit("no .text section")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: crc_text.py <dll>")
    print("0x%08X" % crc_text(sys.argv[1]))
