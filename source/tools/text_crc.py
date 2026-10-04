#!/usr/bin/env python3
"""text_crc.py - CRC32 of the .text section of a PE.

Used in the stub self-CRC two-pass (build.sh --harden): after pass 1 with the
placeholder constant, it computes the .text CRC of winmm.dll and
pack_payload.py set-crc writes the (masked) constant into stub_cfg.h. Pass 2
rebuilds with the real constant - the .text does NOT change (the constant
lives in .rdata/.data via volatile), so the CRC is identical.

Usage: python3 tools/text_crc.py <pe>
"""

import struct
import sys
import zlib


def text_crc(path):
    data = open(path, 'rb').read()
    if len(data) < 0x40 or data[:2] != b'MZ':
        raise SystemExit('not a PE: %s' % path)
    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b'PE\x00\x00':
        raise SystemExit('no PE signature: %s' % path)
    num_sec = struct.unpack_from('<H', data, e_lfanew + 6)[0]
    opt_sz = struct.unpack_from('<H', data, e_lfanew + 20)[0]
    sec_off = e_lfanew + 24 + opt_sz
    for i in range(num_sec):
        off = sec_off + i * 40
        chars = struct.unpack_from('<I', data, off + 36)[0]
        if chars & 0x20:  # IMAGE_SCN_CNT_CODE
            raw = struct.unpack_from('<I', data, off + 20)[0]
            sz = struct.unpack_from('<I', data, off + 16)[0]
            if sz == 0:
                raise SystemExit('empty .text section')
            return zlib.crc32(data[raw:raw + sz]) & 0xFFFFFFFF
    raise SystemExit('no code section: %s' % path)


if __name__ == '__main__':
    print('0x%08X' % text_crc(sys.argv[1]))
