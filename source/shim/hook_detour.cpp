// hook_detour.cpp - detour on the QueryApiImpl export of xgameruntime.dll.
//
// The patch installation machinery lives here (relay page + trampoline).
// The handler and the license wrappers live in hook_api_impl.cpp and talk
// to this module through hook_detour.h (log macros, opaque predicate, expected
// prologue and the g_relayPage page).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdint>
#include <cstring>

#include "hook_detour.h"

namespace {

// ============================================================================
// Detour (E9 rel32 -> adjacent relay page; trampoline with the saved prologue)
// ============================================================================

// Prologue of the real QueryApiImpl (verified by RE on the binary - the bytes
// appear identical in the live process):
//   48 89 5C 24 08    mov [rsp+8],  rbx
//   48 89 6C 24 10    mov [rsp+10h], rbp
//   48 89 74 24 18    mov [rsp+18h], rsi
//   ...
// The patch is a CLEAN 5-byte E9 rel32 - it does not leave the 12-byte
// "48 B8 imm64 FF E0" signature that would give the hook away to a pattern
// scan. The relay page is
// allocated NEAR the target module (within +/-2GB, the rel32 range) and the
// relay entry does NOT store the handler pointer in the clear: mov r11,
// handler^key; xor r11, key; jmp r11 (random key PER PROCESS, 31 bits
// - the imm32 sign-extension is zero). Even a memory scan looking for the
// mov/jmp pattern does not find the handler: the stored imm64 is obfuscated.
// The distinctive pattern lives in an ANONYMOUS page (looks like heap/JIT -
// the process uses v8), not in the game's .text.

// Relay XOR key (per process, 31 bits so the imm32 of `xor r11, imm`
// does not sign-extend garbage into the high 32 bits of the pointer).
uint64_t RelayKey() {
    static volatile uint64_t key = 0;
    if (key == 0) {
        LARGE_INTEGER pc{};
        QueryPerformanceCounter(&pc);
        uint64_t k = static_cast<uint64_t>(GetCurrentProcessId()) ^
                     static_cast<uint64_t>(GetTickCount()) ^
                     static_cast<uint64_t>(pc.QuadPart);
        k &= 0x7FFFFFFFull;
        if (k == 0) k = 0x539u;
        key = k;
    }
    return key;
}

// Allocates the relay page NEAR the target module (E9 rel32 range): tries
// above and below, stepping 64KB at a time up to ~2GB. VirtualAlloc with a
// hint returns NULL if the address is taken - the loop only finds free
// regions. A single call at install time (tens of ms in the worst case).
uint8_t* AllocNearModule(uint8_t* module_base, size_t size) {
    constexpr intptr_t kStep = 0x10000;
    constexpr intptr_t kMax = 0x7FF00000;  // ~2GB - 1MB (rel32 slack)
    for (intptr_t d = kStep; d < kMax; d += kStep) {
        uint8_t* up = reinterpret_cast<uint8_t*>(
            reinterpret_cast<uintptr_t>(module_base) + static_cast<uintptr_t>(d));
        uint8_t* p = static_cast<uint8_t*>(
            VirtualAlloc(up, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
        if (p != nullptr) return p;
        uint8_t* down = reinterpret_cast<uint8_t*>(
            reinterpret_cast<uintptr_t>(module_base) - static_cast<uintptr_t>(d));
        p = static_cast<uint8_t*>(
            VirtualAlloc(down, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
        if (p != nullptr) return p;
    }
    return nullptr;
}

#if defined(__aarch64__) || defined(_M_ARM64)
// ARM64 body of InstallPatch:
//   detour @entry : br #off26          (4B, ±128MB range to the relay)
//   relay[0x08]   : quad handler       (literal of the initial load)
//   relay[0x00]   : ldr x17,Lit; br x17
//   relay[0x20]   : TRAMPOLINE = REAL prologue copied + ldr x17/TailLit;br
//   relay[0x40]   : TailLit = quad(entry + trampWords*4)  (back to the orig)
//   rest          : PRNG junk (anti-signature)
// Everything inside ONE page: no proximity requirement to return.
static bool InstallPatchArm64(uint8_t* entry, void* handler,
                              uint8_t* module_base) {
    constexpr uint32_t kPageSize = 0x1000;
    if (g_trampWords == 0 || g_trampWords > 8) return false;

    uint8_t* page = AllocNearModule(module_base, kPageSize);
    if (page == nullptr) {
        HOOK_LOG("install: AllocNearModule(relay) FAILED");
        return false;
    }
    const int32_t br_delta = static_cast<int32_t>(
        (reinterpret_cast<intptr_t>(page) - reinterpret_cast<intptr_t>(entry)) >>
        2);
    constexpr int32_t kBMax = 0x2000000;  // ±128MB
    if (br_delta > kBMax || br_delta < -kBMax) {
        HOOK_LOG("install: relay out of br±128MB range");
        VirtualFree(page, 0, MEM_RELEASE);
        return false;
    }

    // Load-literal: LDR Xt,label = 0x58000000 | imm19<<5 | Rt (imm19 = delta/4)
    auto emit_ldr_lit = [&](uint8_t* at, uint32_t rt, const void* lit_addr) {
        const int64_t dwords =
            (reinterpret_cast<intptr_t>(lit_addr) -
             reinterpret_cast<intptr_t>(at)) >> 2;
        *reinterpret_cast<uint32_t*>(at) =
            0x58000000u | (static_cast<uint32_t>(dwords & 0x1FFFFF) << 5) | rt;
    };

    // [0x00] stub -> handler
    emit_ldr_lit(page, 17, page + 0x08);
    *reinterpret_cast<uint32_t*>(page + 4) = 0xD61F0220u;  // br x17
    *reinterpret_cast<uint64_t*>(page + 0x08) = reinterpret_cast<uint64_t>(handler);

    // [0x20] trampoline: REAL prologue + tail back to entry+N*4
    uint8_t* t = page + 0x20;
    std::memcpy(t, g_prologueBytes, g_trampWords * 4);
    t += g_trampWords * 4;
    emit_ldr_lit(t, 17, page + 0x40);
    *reinterpret_cast<uint32_t*>(t + 4) = 0xD61F0220u;              // br x17
    *reinterpret_cast<uint64_t*>(page + 0x40) = reinterpret_cast<uint64_t>(
        entry + g_trampWords * 4);

    // pseudo-random junk in the rest (same philosophy as x64)
    uint32_t seed = static_cast<uint32_t>(GetCurrentProcessId()) ^ 0x6D2B79F5u;
    for (uint32_t i = 0x48; i < kPageSize; ++i) {
        seed = seed * 1664525u + 1013904223u;
        page[i] = static_cast<uint8_t>(seed >> 24);
    }
    FlushInstructionCache(GetCurrentProcess(), page, kPageSize);

    DWORD old = 0;
    if (!VirtualProtect(page, kPageSize, PAGE_EXECUTE_READ, &old)) {
        VirtualFree(page, 0, MEM_RELEASE);
        return false;
    }

    // Detour: B (unconditional) = 0x14000000 | off26
    if (!VirtualProtect(entry, 4, PAGE_EXECUTE_READWRITE, &old)) {
        DLOG("install: VirtualProtect(entry) FAILED (err=%lu)", GetLastError());
        VirtualFree(page, 0, MEM_RELEASE);
        return false;
    }
    *reinterpret_cast<uint32_t*>(entry) =
        0x14000000u | (static_cast<uint32_t>(br_delta) & 0x03FFFFFFu);
    VirtualProtect(entry, 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), entry, 4);

    g_relayPage = page;
    return true;
}
#endif

}  // namespace

bool InstallPatch(uint8_t* entry, void* handler, uint8_t* module_base) {
#if defined(__aarch64__) || defined(_M_ARM64)
    // Prologue already validated/measured by the Internal (g_trampWords/g_prologueBytes).
    if (g_trampWords == 0 || g_trampWords > 8) {
        HOOK_LOG("install: invalid arm64 prologue (trampWords out of range)");
        return false;
    }
    return InstallPatchArm64(entry, handler, module_base);
#elif defined(__x86_64__) || defined(_M_X64)
    if (OpaqueAlwaysFalse()) return false;  // opaque predicate (never branches)
    if (std::memcmp(entry, kQueryApiPrologue, sizeof(kQueryApiPrologue)) != 0)
        return false;

    constexpr uint32_t kPageSize = 0x1000;
    uint8_t* page = AllocNearModule(module_base, kPageSize);
    if (page == nullptr) {
        HOOK_LOG("install: AllocNearModule(relay) FAILED");
        return false;
    }

    // Handler pointer NEVER stored in the clear (anti memory scan):
    //   mov r11, handler^key; xor r11, key; jmp r11   (20 bytes)
    const uint64_t key = RelayKey();
    const uint64_t enc = reinterpret_cast<uint64_t>(handler) ^ key;
    page[0] = 0x49; page[1] = 0xBB;                       // mov r11, imm64
    *reinterpret_cast<uint64_t*>(page + 2) = enc;
    page[10] = 0x49; page[11] = 0x81; page[12] = 0xF3;    // xor r11, imm32
    *reinterpret_cast<uint32_t*>(page + 13) = static_cast<uint32_t>(key);
    page[17] = 0x41; page[18] = 0xFF; page[19] = 0xE3;    // jmp r11

    // +0x20: trampoline = relocated prologue (5B) + mov r11, (entry+5)^key;
    // xor r11, key; jmp r11. The E9 only overwrites the first 5 bytes; the rest
    // of the original prologue stays intact at entry+5 (the handler calls the
    // original through this trampoline).
    uint8_t* const tramp = page + 0x20;
    std::memcpy(tramp, kQueryApiPrologue, kDetourLen);
    const uint64_t enc2 =
        reinterpret_cast<uint64_t>(entry + kDetourLen) ^ key;
    tramp[5] = 0x49; tramp[6] = 0xBB;
    *reinterpret_cast<uint64_t*>(tramp + 7) = enc2;
    tramp[15] = 0x49; tramp[16] = 0x81; tramp[17] = 0xF3;
    *reinterpret_cast<uint32_t*>(tramp + 18) = static_cast<uint32_t>(key);
    tramp[22] = 0x41; tramp[23] = 0xFF; tramp[24] = 0xE3;

    // Pseudo-random junk in the rest of the page (looks like heap/JIT, not a
    // clean relay page - avoids the "footprint" of an anonymous page full of code).
    uint32_t seed = static_cast<uint32_t>(GetCurrentProcessId()) ^ 0x6D2B79F5u;
    for (uint32_t i = 0x40; i < kPageSize; ++i) {
        seed = seed * 1664525u + 1013904223u;
        page[i] = static_cast<uint8_t>(seed >> 24);
    }
    FlushInstructionCache(GetCurrentProcess(), page, 0x40);

    // RW -> RX (an anonymous RWX page draws attention from memory scanners).
    DWORD old = 0;
    if (!VirtualProtect(page, kPageSize, PAGE_EXECUTE_READ, &old)) {
        VirtualFree(page, 0, MEM_RELEASE);
        return false;
    }

    // Patch: E9 rel32 (entry -> relay). 5 bytes, clean.
    const int32_t rel = static_cast<int32_t>(
        reinterpret_cast<intptr_t>(page) - reinterpret_cast<intptr_t>(entry + 5));
    uint8_t detour[kDetourLen] = {0xE9, 0, 0, 0, 0};
    std::memcpy(detour + 1, &rel, sizeof(rel));

    if (!VirtualProtect(entry, kDetourLen, PAGE_EXECUTE_READWRITE, &old)) {
        DLOG("install: VirtualProtect(entry) FAILED (err=%lu)", GetLastError());
        VirtualFree(page, 0, MEM_RELEASE);
        return false;
    }
    std::memcpy(entry, detour, kDetourLen);
    VirtualProtect(entry, kDetourLen, old, &old);
    FlushInstructionCache(GetCurrentProcess(), entry, kDetourLen);

    g_relayPage = page;
    return true;
#else
#error "InstallPatch: unsupported architecture"
#endif
}
