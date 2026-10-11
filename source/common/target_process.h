// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

#pragma once
// target_process.h - TARGET PROCESS gate.
//
// Why it exists: winmm.dll is loaded by the HOST loader (classic import
// hijack) in ANY exe of the folder where the file sits. In a process that is
// not Minecraft the whole chain (mapper + payload + hook + popup) has no
// target at all: it loads xgameruntime.dll in a third-party process, patches
// an export of it and even exposes our binary. Here a strange process gets
// ONLY the transparent proxy (forward to the 180 exports of the real winmm):
// audio and timers stay intact and nothing else happens.
//
// Accepted identity (either of the two signals suffices):
//   1. package identity whose family starts with "microsoft.minecraft" -
//      covers retail (Microsoft.MinecraftUWP), Preview (MinecraftWindowsBeta)
//      and Education (MinecraftEducationEdition);
//   2. main module with basename "minecraft.windows.exe" - covers the install
//      that runs without a package identity visible in the process.
//
// Deliberately LEFT OUT: Java (MinecraftLauncher.exe, the Windows launcher),
// Roblox and any other exe. If a legitimate target one day does not match
// either signal, the symptom is "unlock does not kick in" and the fix is to
// ADD a signal here, never to loosen what already exists.
//
// Strings: both literals live encrypted in enc_strings.h (tools/gen_xor.py)
// and are decrypted at runtime - no new plaintext in the binary.

#include <windows.h>

#include "enc_strings.h"

// VPS mingw-w64 does not ship <appmodel.h>; the symbol exists in the
// kernel32 import lib (confirmed by nm), so we declare the prototype here.
#ifndef MBU_APPMODEL_DECL
#define MBU_APPMODEL_DECL
extern "C" __declspec(dllimport) LONG WINAPI GetCurrentPackageFullName(
    UINT32* packageFullNameLength, PWSTR packageFullName);
#endif

namespace targetproc {

// Minecraft Bedrock package family prefix (lowercase).
inline const char* PkgPrefix() {
    return enc::dec(enc::kPkgPrefix, enc::kPkgPrefixLen, 0x5A);
}

// Game executable basename (lowercase).
inline const char* GameExe() {
    return enc::dec(enc::kGameExe, enc::kGameExeLen, 0x5A);
}

inline char LowerAscii(char c) {
    return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + 32) : c;
}

// does s start with prefix (prefix ALREADY lowercase)?
inline bool StartsWithCI(const char* s, const char* prefix) {
    for (; *prefix; ++s, ++prefix) {
        if (*s == '\0') return false;
        if (LowerAscii(*s) != *prefix) return false;
    }
    return true;
}

// s == low (low ALREADY lowercase)?
inline bool EqualsCI(const char* s, const char* low) {
    for (; *low; ++s, ++low) {
        if (*s == '\0') return false;
        if (LowerAscii(*s) != *low) return false;
    }
    return *s == '\0';
}

// Basename of a wide path -> buf in lowercase ASCII (no allocation).
// Returns false if it does not fit in cap (then the caller decides nothing).
inline bool BaseNameLowerA(const wchar_t* path, char* buf, size_t cap) {
    const wchar_t* last = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') last = p + 1;
    size_t i = 0;
    for (; last[i]; ++i) {
        if (i + 1 >= cap) return false;
        wchar_t c = last[i];
        buf[i] = (c > 127) ? '?' : LowerAscii(static_cast<char>(c));
    }
    buf[i] = '\0';
    return true;
}

// 1) Process package identity. APPMODEL_ERROR_NO_PACKAGE (15700) when the
// exe was not launched as a packaged app - then it falls to signal 2.
inline bool HasMinecraftPackage() {
    UINT32 len = 0;
    if (GetCurrentPackageFullName(&len, nullptr) != ERROR_INSUFFICIENT_BUFFER)
        return false;
    if (len > 256) return false;
    wchar_t name[256];
    if (GetCurrentPackageFullName(&len, name) != ERROR_SUCCESS) return false;
    char low[256];
    if (!BaseNameLowerA(name, low, sizeof(low))) return false;
    return StartsWithCI(low, PkgPrefix());
}

// 2) Main module basename (the host exe, not our DLL).
inline bool IsGameExeName() {
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exe, MAX_PATH) == 0) return false;
    char low[MAX_PATH];
    if (!BaseNameLowerA(exe, low, sizeof(low))) return false;
    return EqualsCI(low, GameExe());
}

// Verdict. When unsure = false (strange process): not acting is always safer
// than acting, because the real target matches one of the two signals above
// in any install.
inline bool IsMinecraftTarget() {
    return HasMinecraftPackage() || IsGameExeName();
}

}  // namespace targetproc
