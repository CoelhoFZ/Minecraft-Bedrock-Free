// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

#pragma once
// mapper_params.h - stub -> mapper parameter channel (via DllMain lpReserved;
// the blob CRT passes the 3rd argument through untouched).
//
// The mapper is NOT registered in the loader (manually mapped) - it cannot
// call GetModuleFileNameA(own hinst) nor find winmm.dll on its own.
// The stub (which knows its own path) delivers here what the mapper needs
// to re-read the file and find BLOB2 (payload).

#include <windows.h>

struct MapperParams {
    char     winmm_path[MAX_PATH];  // winmm.dll path (with the overlay)
    uint32_t size1;                 // blob1 size (the mapper itself)
    uint32_t size2;                 // blob2 size (payload)
    uint32_t magic;                 // trailer magic (validated in the stub)
    volatile LONG* kill_flag;       // watchdog kill-switch (stub -> payload)
    uint8_t*  mapped_payload;       // filled by the mapper: base of the mapped
                                    // payload (for the in-memory watchdog CRC)
};
