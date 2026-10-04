// dllmain.cpp - GDK shim entrypoint (XGameCore.GDK.dll).
//
// HARDENED (--harden): deep anti-debug + self-check (CRC32) BEFORE
// installing the hook; embedded config (no INI on disk); after installing the
// hook the module is REMOVED from the loader list (PEB unlink) - the DLL stays
// mapped and functional but does not show up in Get-Process.Modules /
// Module32First / dumps that enumerate via LDR.
//
// dev (--release/--debug): reads unlock-CoelhoFZ.ini next to the DLL and
// allows the NOHOOK diagnostic bypass.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <intrin.h>   // intrinsics (on x64: __readgsqword)

#include <cstring>
#include <cwchar>

#include "unlock_coelho_fz_impl.h"
#include "hook_api_impl.h"
#include "enc_strings.h"
#include "target_process.h"
#include "dev_flags.h"

namespace {

// Encrypted INI name (dev-only; the plaintext "unlock-CoelhoFZ.ini" does not
// exist in the binary). Persistent static buffer (used via strcpy).
const char* IniName() {
    static char buf[32];
    if (buf[0] == '\0')
        std::strcpy(buf, enc::dec(enc::kIniName, enc::kIniNameLen, 0x5A));
    return buf;
}

#if defined(HARDENED)
// The payload anti-tamper (blob CRC + per-build key) lives in the 2-stage
// packer (proxy/stub_loader.cpp + proxy/mapper_dllmain.cpp) - the
// shim no longer needs a self-check on disk (there is not even a file to
// patch: it is the encrypted BLOB2).

// ---- deep anti-debug (harden only): debugger/RE tool present -> hook
// does NOT install (silent; the game runs vanilla). Independent layers:
//   1. IsDebuggerPresent (classic API)
//   2. NtQueryInformationProcess ProcessDebugPort(7)/ProcessDebugFlags(31)
//      via GetProcAddress (does not depend on a visible import table)
//   3. direct PEB (immune to API hooks): BeingDebugged(+0x02) and
//      NtGlobalFlag(+0xBC, bits 0x70 = heap debug flags)
//   4. Hardware breakpoints (DR0..DR3) on the current thread
//   5. rdtsc timing: single-step under a debugger inflates the loop delta
//   6. Process scan: common RE tools running
// Cycle counter: TSC on x64, CNTVCT_EL0 on ARM64 (multiplied by 64 so it
// stays in the same "cycles" magnitude that the TimingSuspect threshold
// expects; it is a timing heuristic, it does not need to be the SAME clock).
uint64_t Rdtsc() {
#if defined(__x86_64__) || defined(_M_X64)
    uint32_t lo = 0, hi = 0;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    return (static_cast<uint64_t>(hi) << 32) | lo;
#elif defined(__aarch64__) || defined(_M_ARM64)
    uint64_t v = 0;
    __asm__ __volatile__("mrs %0, cntvct_el0" : "=r"(v));
    return v * 64u;
#else
#error "shim/dllmain.cpp: unsupported architecture (Rdtsc)"
#endif
}
bool TimingSuspect() {
    const uint64_t t0 = Rdtsc();
    volatile uint64_t acc = 0;
    for (int i = 0; i < 256; ++i) acc += static_cast<uint64_t>(i);
    const uint64_t delta = Rdtsc() - t0;
    (void)acc;
    // loop of 256 iterations ~ 1000-3000 cycles; > 50000 = debug stepping.
    return delta > 50000u;
}
bool ReToolRunning() {
    static const wchar_t* kTools[] = {
        L"x64dbg.exe", L"x32dbg.exe", L"x96dbg.exe", L"ollydbg.exe",
        L"ollyice.exe", L"immunitydebugger.exe", L"windbg.exe",
        L"windbgx.exe", L"ida.exe", L"ida64.exe", L"idaq.exe",
        L"idaq64.exe", L"cheatengine.exe", L"cheatengine-x86_64.exe",
        L"processhacker.exe", L"procexp.exe", L"procmon.exe",
        L"frida.exe", L"frida-server.exe", L"dnspy.exe",
        L"ghidraRun.exe", L"radare2.exe", L"x64minimal.exe",
    };
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return false;
    PROCESSENTRY32W pe = {};
    pe.dwSize = sizeof(pe);
    bool found = false;
    if (Process32FirstW(snap, &pe)) {
        do {
            for (const wchar_t* t : kTools) {
                if (_wcsicmp(pe.szExeFile, t) == 0) {
                    found = true;
                    break;
                }
            }
        } while (!found && Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}
bool DebuggerPresentDeep() {
    if (IsDebuggerPresent()) return true;
    // CheckRemoteDebuggerPresent (debugger from another process on the same machine).
    BOOL remote = FALSE;
    if (CheckRemoteDebuggerPresent(GetCurrentProcess(), &remote) && remote)
        return true;
    // NtQueryInformationProcess via ntdll directly (encrypted names).
    HMODULE nt = GetModuleHandleA(enc::dec(enc::kNtdll, enc::kNtdllLen, 0x5A));
    if (nt != nullptr) {
        typedef LONG(NTAPI* NtQIP_t)(HANDLE, ULONG, PVOID, ULONG, PULONG);
        NtQIP_t fn = reinterpret_cast<NtQIP_t>(GetProcAddress(
            nt, enc::dec(enc::kNtQuery, enc::kNtQueryLen, 0x5A)));
        if (fn != nullptr) {
            DWORD port = 0;
            ULONG r = 0;
            if (fn(GetCurrentProcess(), 7, &port, sizeof(port), &r) == 0 &&
                port != 0)
                return true;
            DWORD flags = 0;
            if (fn(GetCurrentProcess(), 31, &flags, sizeof(flags), &r) == 0 &&
                (flags & 1u) == 0)
                return true;
        }
    }
    // direct PEB (TEB+0x60 on both archs: GS on x64, TPIDR_EL0 on ARM64)
    // - does not go through an API, immune to hooks.
    uintptr_t peb = 0;
#if defined(__x86_64__) || defined(_M_X64)
    peb = __readgsqword(0x60);
#elif defined(__aarch64__) || defined(_M_ARM64)
    {
        uintptr_t teb = 0;
        __asm__ __volatile__("mrs %0, tpidr_el0" : "=r"(teb));
        if (teb != 0) peb = *reinterpret_cast<const uintptr_t*>(teb + 0x60);
    }
#endif
    if (peb == 0) return false;
    if (*reinterpret_cast<const uint8_t*>(peb + 0x02) != 0) return true;
    const uint32_t gflags = *reinterpret_cast<const uint32_t*>(peb + 0xBC);
    if ((gflags & 0x70u) != 0) return true;  // heap debug flags
#if defined(__x86_64__) || defined(_M_X64)
    // Hardware breakpoints on the current thread (DR0..DR3: not present in the CONTEXT
    // of ARM64; there the equivalent check would be arch-specific DebugRegs -
    // out of scope, the other layers cover it).
    CONTEXT ctx;
    std::memset(&ctx, 0, sizeof(ctx));
    ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (GetThreadContext(GetCurrentThread(), &ctx)) {
        if (ctx.Dr0 != 0 || ctx.Dr1 != 0 || ctx.Dr2 != 0 || ctx.Dr3 != 0)
            return true;
    }
#endif
    if (TimingSuspect()) return true;
    if (ReToolRunning()) return true;
    return false;
}

#endif  // HARDENED

}  // namespace

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID lpReserved) {
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(hinst);

    // TARGET PROCESS GATE (defense in depth - the proxy already blocks before
    // decrypting/mapping this): if the host is not Minecraft Bedrock,
    // it exits INERT, before anti-debug, config, hook and crash handler. That
    // way not even the debugger scan cost exists in a third-party process.
    // See common/target_process.h.
    if (!targetproc::IsMinecraftTarget()) return TRUE;

#if defined(HARDENED)
    // Watchdog kill-switch (the mapper passes it through via lpReserved): if
    // winmm.dll is patched after load, the hook stops lying
    // "owned" (passthrough) - see SetHookKillFlag.
    if (lpReserved != nullptr)
        SetHookKillFlag(static_cast<volatile LONG*>(lpReserved));

    // Anti-debug (2nd layer - the packer already checked before decrypting):
    // under a debugger the unlocker turns itself off silently (game runs vanilla).
    if (DebuggerPresentDeep()) return TRUE;

    // Embedded config (encrypted constant) - no INI on disk.
    UnlockCoelhoFZGDKInterfaceImpl::instance().init_embedded();
#elif defined(LITE)
    // --lite: embedded config (no INI on disk) but WITHOUT anti-debug/packer.
    // (void)lpReserved: the shim runs as winmm static code in lite.
    (void)lpReserved;
    UnlockCoelhoFZGDKInterfaceImpl::instance().init_embedded();
#else
    // ini path = same directory as the DLL + "unlock-CoelhoFZ.ini".
    char ini_path[MAX_PATH];
    if (!GetModuleFileNameA(hinst, ini_path, MAX_PATH)) {
        UnlockCoelhoFZGDKInterfaceImpl::instance().init(IniName());
        return TRUE;
    }
    char* slash = std::strrchr(ini_path, '\\');
    if (slash != nullptr) {
        std::strcpy(slash + 1, IniName());
    } else {
        std::strcpy(ini_path, IniName());
    }
    UnlockCoelhoFZGDKInterfaceImpl::instance().init(ini_path);
#endif

    // REAL unlock mechanism: hooks the QueryApiImpl of xgameruntime and
    // returns the XPackage/XStore interfaces with the license slots
    // answering "owned" (magic 0x539/0x1337). Without it the game queries the
    // real Store license and sees "not paid".
    SetUnlockProductId(UnlockCoelhoFZGDKInterfaceImpl::instance().product_id());
    InstallCrashHandler();

#if defined(HARDENED)
    // In harden the hook is ALWAYS installed (there is no file-based bypass).
    // The module does NOT need a PEB-unlink: the payload is not even registered
    // in the loader (manually mapped) - it is born invisible.
    InstallQueryApiImplHook();
#elif defined(LITE)
    // --lite: hook always installed (no file-based bypass).
    InstallQueryApiImplHook();
#else
    // Diagnostic BYPASS (dev only): with the NOHOOK flag (dev folder,
    // COELHOFZ_DEV_DIR or %TEMP%), the hook is NOT installed (the DLL loads
    // normally, the game runs vanilla). Without the flag, it installs.
    if (!devflag::Exists("NOHOOK")) {
        InstallQueryApiImplHook();
    }
#endif
    return TRUE;
}
