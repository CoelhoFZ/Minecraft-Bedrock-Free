// dev_flags.h - diagnostic bypasses for the dev builds (--release/--debug).
// Under --harden the call sites are compiled out (there is no bypass in the
// distribution binary).
//
// The flag is an empty file with the bypass name (NTHUNK, NWRAP, NOHOOK).
// The base folder comes from the COELHOFZ_DEV_DIR environment variable. If it
// is not defined, the base folder is the user's %TEMP%.
#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstring>

namespace devflag {

inline bool Exists(const char* name) {
    char base[MAX_PATH];
    DWORD n = GetEnvironmentVariableA("COELHOFZ_DEV_DIR", base, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        if (GetTempPathA(MAX_PATH, base) == 0) return false;
    }
    const size_t len = std::strlen(base);
    if (len == 0 || len + std::strlen(name) + 1 >= MAX_PATH) return false;
    if (base[len - 1] != '\\' && base[len - 1] != '/') std::strcat(base, "\\");
    std::strcat(base, name);
    return GetFileAttributesA(base) != INVALID_FILE_ATTRIBUTES;
}

}  // namespace devflag
