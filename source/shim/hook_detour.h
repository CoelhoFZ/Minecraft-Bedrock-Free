// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

// hook_detour.h - internal interface between hook_api_impl.cpp and hook_detour.cpp.
#pragma once

#include <cstdint>

// Expected prologue of the real QueryApiImpl on x64 (verified by RE: the bytes
// appear identical in the live process):
//   48 89 5C 24 08    mov [rsp+8],  rbx
//   48 89 6C 24 10    mov [rsp+10h], rbp
//   48 89 74 24 18    mov [rsp+18h], rsi
inline constexpr uint8_t kQueryApiPrologue[15] = {
    0x48, 0x89, 0x5C, 0x24, 0x08,
    0x48, 0x89, 0x6C, 0x24, 0x10,
    0x48, 0x89, 0x74, 0x24, 0x18,
};
inline constexpr uint32_t kDetourLen = 5;  // E9 rel32

// Diagnostics: turns into a no-op under HARDENED (arguments discarded).
#if defined(HARDENED)
#define HOOK_LOG(...) ((void)0)
#define DLOG(...)     ((void)0)
#else
void HookLog(const char* msg);
void DbgLogf(const char* fmt, ...);
#define HOOK_LOG(...) HookLog(__VA_ARGS__)
#define DLOG(...)     DbgLogf(__VA_ARGS__)
#endif

// Opaque predicate (always false) used in the installation path.
bool OpaqueAlwaysFalse();

// Applies the detour (entry -> relay -> handler). The trampoline lives at
// g_relayPage + 0x20 and the relay does NOT store the handler in the clear.
bool InstallPatch(uint8_t* entry, void* handler, uint8_t* module_base);

// Relay page + trampoline (allocated by InstallPatch).
extern uint8_t* g_relayPage;

#if defined(__aarch64__) || defined(_M_ARM64)
// Prologue measured at install time (ARM64) - reused when building the trampoline.
extern uint8_t  g_prologueBytes[32];
extern uint32_t g_trampWords;
#endif
