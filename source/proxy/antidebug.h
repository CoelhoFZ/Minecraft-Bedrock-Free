// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

// antidebug.h - anti-debug probes shared between the stub (layer 1) and the
// mapper (layer 2) of the harden packer.
//
// Hardening phase 2 (anti-debug + anti-dump). What each probe covers:
//   1. NtQueryInformationProcess (via ntdll by PEB walk + hash, no import):
//      ProcessDebugPort (7), ProcessDebugObjectHandle (0x1E) and
//      ProcessDebugFlags (0x1F) - catches classic debugger attach (x64dbg,
//      windbg, olly...) even when IsDebuggerPresent/PEB was patched.
//   2. Hardware breakpoints (DR0-DR3 via GetThreadContext on the current thread).
//   3. rdtsc timing around sensitive regions (decryption) - catches
//      single-step (time blows up by orders of magnitude vs. normal execution).
//   4. Analysis tool processes (x64dbg/windbg/IDA/CE/ghidra) by
//      name - short and conservative list; the names live ONLY as FNV hashes
//      (no plaintext in the binary).
//
// Behavior on detection: the CALLER decides - in the stub and in the mapper it
// is always SILENT FAILURE (does not unlock, does not popup, does not crash).
// Never crash a legitimate machine: any probe that fails to resolve an API
// returns "clean" (false negative > false positive).
//
// APIs resolved at runtime (PEB walk) - none enter the import table.

#pragma once

#include <windows.h>
#include <intrin.h>   // __rdtsc, __readgsqword
#include <tlhelp32.h> // PROCESSENTRY32W (tool scan)
#include <cstdint>
#include <cstring>

#include "apihash.h"

namespace antidebug {

// FNV-1a case-insensitive WIDE (same base as apihash::H, for wchar). Used
// to hash the tool names at compile-time (never plaintext).
constexpr uint32_t HW(const wchar_t* s) {
    uint32_t h = 2166136261u;
    for (; *s; ++s) {
        wchar_t c = *s;
        if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
        h ^= static_cast<uint8_t>(c);
        h *= 16777619u;
    }
    return h;
}

// rdtsc: cycle counter (x64). Used for timing sensitive regions.
inline uint64_t Tsc() {
#if defined(__x86_64__) || defined(_M_X64)
    return static_cast<uint64_t>(__rdtsc());
#else
    return 0;
#endif
}

// local getters via PEB walk (each TU gets its own copy - same pattern as
// apihash). Kernel32/ntdll never show up in the winmm/mapper import table.
inline decltype(&::GetCurrentThread) GetCurrentThread() {
    static auto fn = reinterpret_cast<decltype(&::GetCurrentThread)>(
        apihash::Resolve(apihash::H("kernel32.dll"),
                         apihash::H("GetCurrentThread")));
    return fn;
}
inline decltype(&::GetThreadContext) GetThreadContext() {
    static auto fn = reinterpret_cast<decltype(&::GetThreadContext)>(
        apihash::Resolve(apihash::H("kernel32.dll"),
                         apihash::H("GetThreadContext")));
    return fn;
}
inline decltype(&::CreateToolhelp32Snapshot) CreateToolhelp32Snapshot() {
    static auto fn = reinterpret_cast<decltype(&::CreateToolhelp32Snapshot)>(
        apihash::Resolve(apihash::H("kernel32.dll"),
                         apihash::H("CreateToolhelp32Snapshot")));
    return fn;
}
inline decltype(&::Process32FirstW) Process32FirstW() {
    static auto fn = reinterpret_cast<decltype(&::Process32FirstW)>(
        apihash::Resolve(apihash::H("kernel32.dll"),
                         apihash::H("Process32FirstW")));
    return fn;
}
inline decltype(&::Process32NextW) Process32NextW() {
    static auto fn = reinterpret_cast<decltype(&::Process32NextW)>(
        apihash::Resolve(apihash::H("kernel32.dll"),
                         apihash::H("Process32NextW")));
    return fn;
}
inline decltype(&::CloseHandle) CloseHandle() {
    static auto fn = reinterpret_cast<decltype(&::CloseHandle)>(
        apihash::Resolve(apihash::H("kernel32.dll"), apihash::H("CloseHandle")));
    return fn;
}

// NtQueryInformationProcess (ntdll). Minimal declaration (avoids winternl.h).
using NtQueryInfoFn = LONG(NTAPI*)(HANDLE, ULONG, PVOID, ULONG, PULONG);
inline NtQueryInfoFn NtQueryInformationProcess() {
    static auto fn = reinterpret_cast<NtQueryInfoFn>(
        apihash::Resolve(apihash::H("ntdll.dll"),
                         apihash::H("NtQueryInformationProcess")));
    return fn;
}

// Probe 1: NtQueryInformationProcess on the 3 classic classes. IsDebugger-
// Present/PEB is trivial to patch; DebugPort/ObjectHandle/Flags do not lie
// (the kernel is the one answering). Any resolution/call error = clean
// (false negative > false positive - never accuse a clean machine).
inline bool NtDebugProbe() {
    NtQueryInfoFn q = NtQueryInformationProcess();
    if (q == nullptr) return false;
    const HANDLE self_proc = apihash::GetCurrentProcess()();
    if (self_proc == nullptr) return false;

    // ProcessDebugPort (7): != 0 when a debugger is attached.
    ULONG_PTR port = 0;
    if (q(self_proc, 7, &port, sizeof(port), nullptr) == 0 && port != 0)
        return true;

    // ProcessDebugObjectHandle (0x1E): a debug object handle exists
    // only with an active DebugActiveProcess.
    HANDLE dbg_obj = nullptr;
    if (q(self_proc, 0x1E, &dbg_obj, sizeof(dbg_obj), nullptr) == 0 &&
        dbg_obj != nullptr) {
        if (CloseHandle() != nullptr) CloseHandle()(dbg_obj);
        return true;
    }

    // ProcessDebugFlags (0x1F): returns 0 when the process IS debugged
    // (inverted). Any error = assume clean.
    ULONG flags = 0;
    if (q(self_proc, 0x1F, &flags, sizeof(flags), nullptr) == 0 && flags == 0)
        return true;

    return false;
}

// Probe 2: hardware breakpoints (DR0-DR3) on the current thread. Real
// debuggers use DR for BPs without touching the code (invisible to CRC). A
// clean process never has DR set. Failure to read context = clean.
inline bool HardwareBreakpointsProbe() {
    auto gtc = GetThreadContext();
    auto gct = GetCurrentThread();
    if (gtc == nullptr || gct == nullptr) return false;
    CONTEXT ctx;
    std::memset(&ctx, 0, sizeof(ctx));
#if defined(__x86_64__) || defined(_M_X64)
    // On x64 the CONTEXT needs the AMD64 + CONTROL flags together with
    // DEBUG_REGISTERS (GetThreadContext fails with only DEBUG_REGISTERS).
    ctx.ContextFlags = CONTEXT_AMD64 | CONTEXT_CONTROL | CONTEXT_DEBUG_REGISTERS;
#else
    ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
#endif
    if (!gtc(gct(), &ctx)) return false;
    const DWORD64 dr7 = ctx.Dr7;
    // Local/global enables: bits 0..7 of DR7 (L0..G3). If some BP is
    // enabled AND the matching address is not zero -> debugger.
    if (dr7 & 0x00000001u) { if (ctx.Dr0 != 0) return true; }
    if (dr7 & 0x00000004u) { if (ctx.Dr1 != 0) return true; }
    if (dr7 & 0x00000010u) { if (ctx.Dr2 != 0) return true; }
    if (dr7 & 0x00000040u) { if (ctx.Dr3 != 0) return true; }
    if (dr7 & 0x00000002u) { if (ctx.Dr0 != 0) return true; }
    if (dr7 & 0x00000008u) { if (ctx.Dr1 != 0) return true; }
    if (dr7 & 0x00000020u) { if (ctx.Dr2 != 0) return true; }
    if (dr7 & 0x00000080u) { if (ctx.Dr3 != 0) return true; }
    return false;
}

// Probe 3: common analysis tools running (by process name).
// Short and conservative list (only what an RE/copycat would use AGAINST the
// game). The names exist only as compile-time hashes. Enumerates processes
// once; cost ~1ms. API failure = clean.
inline bool AnalysisToolRunning() {
    auto snap = CreateToolhelp32Snapshot();
    auto p32f = Process32FirstW();
    auto p32n = Process32NextW();
    auto close = CloseHandle();
    if (snap == nullptr || p32f == nullptr || p32n == nullptr ||
        close == nullptr)
        return false;

    // FNV-1a hashes (compile-time) of the tool basenames. Ghidra
    // runs as java.exe (too generic to match by name) and stays out.
    static constexpr uint32_t kTools[] = {
        HW(L"x64dbg.exe"), HW(L"x32dbg.exe"), HW(L"x96dbg.exe"),
        HW(L"windbg.exe"), HW(L"windbgx.exe"),
        HW(L"ida.exe"), HW(L"ida64.exe"),
        HW(L"cheatengine-x86_64.exe"), HW(L"cheatengine-i386.exe"),
        HW(L"cheatengine.exe"),
        HW(L"ollydbg.exe"),
    };

    HANDLE h = snap(TH32CS_SNAPPROCESS, 0);
    if (h == INVALID_HANDLE_VALUE) return false;
    PROCESSENTRY32W pe;
    pe.dwSize = sizeof(pe);
    bool found = false;
    for (BOOL ok = p32f(h, &pe); ok; ok = p32n(h, &pe)) {
        const uint32_t hsh = HW(pe.szExeFile);
        for (const uint32_t t : kTools) {
            if (hsh == t) { found = true; break; }
        }
        if (found) break;
    }
    close(h);
    return found;
}

// Default timing budget (cycles): huge slack over normal decryption
// execution (micro/milliseconds) and far below the single-step cost.
constexpr uint64_t kSlowBudgetCycles = 2000000000ull;  // ~0.5-2s on real CPU

// Probe 4: timing of a sensitive region via rdtsc. `start` came from Tsc()
// immediately before the region. Two windows:
//   1. The caller region (e.g.: blob decryption): normal = micro/millise-
//      conds; under single-step it blows up by ORDERS of magnitude.
//   2. If the 1st blew up, it runs a ~400k-iteration micro-window (~1-2M
//      cycles normally):
//        - machine merely busy (preempted in the 1st window): the 2nd is
//          instant -> does NOT flag (false positive avoided);
//        - single-step: the 2nd window ALSO explodes (400k debugger steps
//          cost hundreds of M cycles) -> flags.
// Only flags if BOTH exploded.
inline bool RegionTooSlow(uint64_t start, uint64_t budget_cycles) {
#if defined(__x86_64__) || defined(_M_X64)
    const uint64_t elapsed = Tsc() - start;
    if (elapsed < budget_cycles) return false;
    const uint64_t t0 = Tsc();
    volatile uint64_t sink = 0;
    for (volatile int i = 0; i < 400000; ++i) sink += static_cast<uint64_t>(i);
    (void)sink;
    const uint64_t probe2 = Tsc() - t0;
    // probe2 normal ~1-2M cycles; stepping ~ hundreds of M. Threshold at
    // budget/4 (~5e8 cycles ~ 0.15-0.5s): huge slack vs. normal, clear vs.
    // stepping of 400k instructions.
    return probe2 > (budget_cycles / 4) && elapsed > budget_cycles;
#else
    (void)start; (void)budget_cycles;
    return false;
#endif
}

}  // namespace antidebug
