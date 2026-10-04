// hook_api_impl.cpp - QueryApiImpl HOOK FOR xgameruntime.dll
//
// ============================================================================
// REAL UNLOCK MECHANISM (complete reverse engineering)
// ============================================================================
// The game (Minecraft Bedrock) obtains the GDK interfaces by calling
// xgameruntime!QueryApiImpl(riid, arg2, ppv). The unlocker does NOT
// replace xgameruntime - it hooks this export and returns a WRAPPER object
// (REAL object at [0x18] with the original vtable intact) whose license
// slots answer "owned" (magic 0x539/0x1337):
//
//   xgameruntime!QueryApiImpl  --detour-->  relay page -> handler
//        |-> handler calls the ORIGINAL via trampoline (saved prologue + jmp)
//        |-> if iid == XPackage {AF406016-...}:
//        |      wrapper with slots 1,2 (AddRef/Release OWNED), 4 (RetFalse),
//        |      11 (GetProductId fwd real) + forwarders to the real one
//        |-> if iid == XStore {0DD112AC-...}:
//        |      wrapper with slots 1,2 (OWNED), 8 (unconditional 0x1337 mask),
//        |      15 (enumerate with FABRICATED item + cb - the game passes the
//        |      0x1337 marker as list and expects the item), 19 (skip if
//        |      arg2==0x1337) + forwarders to the real one
//        |-> CACHE of 1 wrapper per real object (wrapperCache 0x36d28).
//        |-> XStore wrapper vtable with 84 slots (0-83) - live dump of the
//        |      original rva 0x30658: slots 60-83 (69/70 = RetTrue/
//        |      RetFalse of the "anonymous" path license) were
//        |      MISSING in the rebuild (had only 60) -> the game read NULL
//        |      past the allocation -> CFG crash 7DF51FDF0000 with
//        |      rcx=wrapper (FIXED 2026-08-14).
//
// Magic values (extracted by RE):
//   0x539  = "1337" in leet - valid license marker
//   0x1337 = fabricated "owned" when the real query fails
//   0x101  = state flag in the license struct
// ============================================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "gdk_interfaces.h"
#include "enc_strings.h"
#include "dev_flags.h"
#include "hook_detour.h"

// ============================================================================
// BUILD MODES (build.sh): --release (dev, full diagnostics) and
// --harden (protected distribution). Under HARDENED:
//   * EVERY diagnostic becomes a no-op: HOOK_LOG/DLOG discard the arguments
//     at compile time -> the binary contains NO log string at all;
//   * ThunkLog/LogIid/CrashVeh/slot-tracking are compiled out;
//   * per-file bypasses (NWRAP/NTHUNK) do not exist;
//   * the REAL object is stored in the wrapper XORed with a per-process key
//     (the emitted forwarder does the xor on the fly - the classic signature
//     "mov rcx,[rcx+0x18]" no longer appears in the clear);
//   * magics and critical strings are obfuscated (XOR) / encrypted (enc_strings.h).
// ============================================================================

// Kill-switch (hardening) - defined in the public section at the end of the
// file, declared here so the handler (anonymous namespace) can read it.
extern volatile LONG* g_hookKillFlag;

// ---- diagnostics: log to %TEMP%\\coelhofz_hook.log (compiled out in harden) ----
#if !defined(HARDENED)
void HookLog(const char* msg) {
    char tmp[MAX_PATH];
    if (GetTempPathA(MAX_PATH, tmp) == 0) return;
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%scoelhofz_hook.log", tmp);
    FILE* f = fopen(path, "a");
    if (f != nullptr) {
        fprintf(f, "[%lu] %s\n", GetTickCount(), msg);
        fclose(f);
    }
}
void DbgLogf(const char* fmt, ...) {
    char b[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof(b), fmt, ap);
    va_end(ap);
    HookLog(b);
}
#endif

// ---- opaque predicate (used by the handler and by hook_detour.cpp) ----
// Always FALSE at runtime, it only pollutes the flow graph for RE.
static volatile uint32_t g_opaqueSeed = 0x5A5A5A5Au;
bool OpaqueAlwaysFalse() {
    const uint32_t x = g_opaqueSeed ^ 0x5A5A5A5Au;
    return ((x * x + 1u) & 2u) != 0u;
}

// ---- relay page (allocated by hook_detour.cpp at install time) ----
uint8_t* g_relayPage = nullptr;

#if defined(__aarch64__) || defined(_M_ARM64)
// Real prologue bytes of QueryApiImpl (ARM64), measured at install time by
// the Internal (hook_api_impl.cpp) and reused when the trampoline is built by
// hook_detour.cpp. No ARM64 dump of the real binary yet: heuristic by
// instruction class + full word log to calibrate an exact constant in the
// next iterations.
uint8_t  g_prologueBytes[32] = {0};
uint32_t g_trampWords        = 0;
#endif

namespace {

// ---- Magic constants (from RE) ----
// Obfuscated: each value is the XOR of two immediates (0x539/0x1337/0x101/
// 0x89245302 never appear as literals in the disassembly).
constexpr uint32_t kMagicOwned   = 0xa3b1799d ^ 0xa3b17ca4;  // = 0x539 ("1337")
constexpr uint64_t kMagicOwned64 = 0x1c80317f ^ 0x1c802248;  // = 0x1337 ("owned")
constexpr uint16_t kStateFlag    = 0x06671ad1 ^ 0x06671bd0;  // = 0x101
constexpr int32_t  kErrXbox      = 0xbdd640fb ^ 0x34f213f9;  // = 0x89245302

// ---- real QueryApiImpl signature: (riid, arg2, ppv) ----
using QueryApiImplFn = int32_t(WINAPI*)(const Guid128*, void*, void**);

QueryApiImplFn g_origQueryApiImpl = nullptr;  // trampoline (prologue + jmp)


// ---- original slots saved before the override (XStore mask-fail) ----
using Slot3Fn = int32_t(WINAPI*)(void*, void*, void*);
using Slot4Fn = int32_t(WINAPI*)(void*, void*, void*, void*);
Slot3Fn g_xstore_orig_slot8  = nullptr;
Slot3Fn g_xstore_orig_slot10 = nullptr;
Slot3Fn g_xstore_orig_slot19 = nullptr;
Slot3Fn g_xstore_orig_slot21 = nullptr;
Slot3Fn g_xstore_orig_slot23 = nullptr;
Slot4Fn g_xstore_orig_slot15 = nullptr;  // slot 15 real (enumerate 0xd4770)
Slot3Fn g_xpackage_orig_slot11 = nullptr;  // real XPackage slot 11 (GetProductId)

// ---- cloned vtables (cache - do not clone the same object twice) ----
void** g_clonedXPackage = nullptr;
void** g_clonedXStore   = nullptr;
// ---- ORIGINAL vtables (saved before the clone) ----
// The clone swaps the game object's vtable pointer. When a thunk calls a
// REAL method passing `self` (the object with the cloned vtable), any
// INTERNAL virtual call the real method makes on `self` would be routed
// through our thunks. The original (wrapper) does not have that problem: the
// real object sits at wrapper->[0x18] with the ORIGINAL vtable intact. We
// keep the original vtable to temporarily restore it during the real calls.
void** g_xpackage_orig_vtable = nullptr;
void** g_xstore_orig_vtable   = nullptr;

// ---- ProductId (set by dllmain after reading the ini; encrypted fallback) ----
char g_productId[64] = "";

// wrapper->[0x18] = REAL object XORed with a per-process key (obfuscation).
// The real plaintext never stays in the wrapper: the emitted forwarder does
// the xor on the fly, so the signature "mov rcx,[rcx+0x18]" (what gave away
// the ORIGINAL's wrapper during RE) no longer exists in the clear.
//
// WARNING (bug 2026-08-14): the forwarder's `xor rcx, imm32` SIGN-EXTENDS
// the immediate to 64 bits (48 81 F1). If the key has bit 31 set, the high
// bits of rcx become 0xFFFFFFFF and the forwarder jumps to garbage (crash in
// the 1st forwarder called). That is why ALL the points (CreateWrapper,
// RealOf and the emitted forwarder) use the SAME sign-extended key
// (RealKey64) - xor is symmetric, so it recovers the exact pointer for any
// key value.
// Cheap per-process entropy tick: TSC on x64, CNTVCT on ARM64.
#if defined(__x86_64__) || defined(_M_X64)
inline uint32_t SeedTick() {
    return static_cast<uint32_t>(__builtin_ia32_rdtsc());
}
#elif defined(__aarch64__) || defined(_M_ARM64)
inline uint32_t SeedTick() {
    uint64_t v = 0;
    __asm__ __volatile__("mrs %0, cntvct_el0" : "=r"(v));
    return static_cast<uint32_t>(v);
}
#else
#error "hook_api_impl.cpp: unsupported architecture (SeedTick)"
#endif

static uint32_t g_realKey = 0;
static uint32_t RealKey() {
    if (g_realKey == 0) {
        volatile uint32_t seed = 0;
        // &0x7FFFFFFF + |=1: keeps bit31 clear (the ARM64 decoding uses a
        // rotated-inverted shift by the key and requires a clear high bit;
        // on x64 the symmetry via RealKey64/sign-extension stays valid either
        // way) and guarantees the low 16 bits are non-zero (single-byte pattern).
        uint32_t k = SeedTick() ^
                     GetTickCount() ^
                     static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&seed)) ^
                     0x9E3779B9u;
        g_realKey = k != 0 ? k : 0x6D2B79F5u;
    }
    return g_realKey;
}
// 64-bit key = sign-extension of the `xor rcx, imm32` immediate (same as
// what the CPU does in the emitted forwarder).
static uintptr_t RealKey64() {
    return static_cast<uintptr_t>(static_cast<intptr_t>(static_cast<int32_t>(RealKey())));
}
static void* RealOf(void* self) {
    const uintptr_t v = reinterpret_cast<uintptr_t>(reinterpret_cast<void**>(self)[3]);
#if defined(__x86_64__) || defined(_M_X64)
    return reinterpret_cast<void*>(v ^ RealKey64());
#elif defined(__aarch64__) || defined(_M_ARM64)
    // ARM64: the wrapper stores the real pointer in plaintext (the forwarder
    // has no immediate decode, see EmitForwarder).
    return reinterpret_cast<void*>(v);
#endif
}

#if defined(__aarch64__) || defined(_M_ARM64)
// Emits ADRP+ADD pointing to an ABSOLUTE address known at emission time
// (the counters live in the same page as the generated code).
static void EmitAdrpAdd(uint8_t* at, uint32_t rd, uintptr_t target) {
    const int64_t page_delta =
        static_cast<int64_t>(target >> 12) -
        static_cast<int64_t>(reinterpret_cast<uintptr_t>(at) >> 12);
    const uint32_t imm21 = static_cast<uint32_t>(page_delta) & 0x1FFFFFu;
    const uint32_t immlo = imm21 & 0x3u;
    const uint32_t immhi = imm21 >> 2;
    *reinterpret_cast<uint32_t*>(at) =
        0x90000000u | (immlo << 29) | (immhi << 5) | rd;
    const uint32_t lo12 = static_cast<uint32_t>(target & 0xFFFu);
    *reinterpret_cast<uint32_t*>(at + 4) =
        0x91000000u | (lo12 << 10) | (rd << 5) | rd;
}
#endif

// ============================================================================
// Crash diagnostics: VectoredExceptionHandler that logs the EXACT crash
// (failure code + RIP + stack) to coelhofz_hook.log, to find the guilty slot.
// It also dumps the bytes AROUND the return addresses (game call site) to
// %TEMP%\coelhofz_retN.bin for disassembly, to find the slot that was called.
// ============================================================================
// forwarder slot-tracking (declared here for the VEH and EmitForwarder):
// the forwarder bumps a per-slot counter (inc [mem] - clobbers no register).
// the VEH logs which slots were called and how many times.
struct NativeConfig;
struct NativeSingleton;
static NativeSingleton* EnsureSingleton();
static NativeConfig* EnsureNativeConfig();
#if !defined(HARDENED)
static volatile uint32_t* g_lastSlotPtr = nullptr;
static volatile uint32_t* g_slotCountPtr = nullptr;  // 64 counters (per slot)
#endif
#if defined(HARDENED)
static void DumpBytesAround(uintptr_t, int) {}
#else
static void DumpBytesAround(uintptr_t addr, int idx) {
    if (addr < 0x7ff000000000ULL || addr > 0x7fff00000000ULL) return;
    char tmp[MAX_PATH];
    if (GetTempPathA(MAX_PATH, tmp) == 0) return;
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%scoelhofz_ret%d.bin", tmp, idx);
    FILE* f = fopen(path, "wb");
    if (f == nullptr) return;
    fwrite(reinterpret_cast<const void*>(addr - 0x100), 1, 0x120, f);
    fclose(f);
}
#endif

static LONG WINAPI CrashVeh(EXCEPTION_POINTERS* ep) {
#if defined(HARDENED)
    (void)ep;
    return EXCEPTION_CONTINUE_SEARCH;  // no diagnostics under harden
#else
    const uint32_t code = static_cast<uint32_t>(ep->ExceptionRecord->ExceptionCode);
    if (code != 0xc0000409 && code != 0xc0000005 && code != 0xc0000374)
        return EXCEPTION_CONTINUE_SEARCH;
    auto* er = ep->ExceptionRecord;
    auto* ctx = ep->ContextRecord;
#if defined(__x86_64__) || defined(_M_X64)
    char b[512];
    snprintf(b, sizeof(b),
             "CRASH: code=%08X rip=%p info0=%llX info1=%llX lastSlot=%u",
             code, reinterpret_cast<void*>(ctx->Rip),
             static_cast<unsigned long long>(er->NumberParameters > 0 ? er->ExceptionInformation[0] : 0),
             static_cast<unsigned long long>(er->NumberParameters > 1 ? er->ExceptionInformation[1] : 0),
             g_lastSlotPtr != nullptr ? *g_lastSlotPtr : 0xffffffffu);
    HookLog(b);
    // REGS (call-site diagnostics: the crash is an indirect call via CFG with
    // target ~0 - rax is the target, rcx/rdx/r8/r9 are the args of the call
    // that crashed).
    {
        char rb[256];
        snprintf(rb, sizeof(rb),
                 "REGS: rax=%llX rcx=%llX rdx=%llX r8=%llX r9=%llX "
                 "r10=%llX r11=%llX rsp=%llX rbp=%llX rsi=%llX rdi=%llX rbx=%llX",
                 static_cast<unsigned long long>(ctx->Rax),
                 static_cast<unsigned long long>(ctx->Rcx),
                 static_cast<unsigned long long>(ctx->Rdx),
                 static_cast<unsigned long long>(ctx->R8),
                 static_cast<unsigned long long>(ctx->R9),
                 static_cast<unsigned long long>(ctx->R10),
                 static_cast<unsigned long long>(ctx->R11),
                 static_cast<unsigned long long>(ctx->Rsp),
                 static_cast<unsigned long long>(ctx->Rbp),
                 static_cast<unsigned long long>(ctx->Rsi),
                 static_cast<unsigned long long>(ctx->Rdi),
                 static_cast<unsigned long long>(ctx->Rbx));
        HookLog(rb);
    }
    // pointers of our config/singleton on the stack (the game holds the
    // wrapper and reads config[0x10] - if one of these shows up near the
    // crash, that is the link).
    {
        auto* sp = reinterpret_cast<uint64_t*>(ctx->Rsp);
        uint64_t cfg = reinterpret_cast<uint64_t>(EnsureNativeConfig());
        uint64_t sing = reinterpret_cast<uint64_t>(EnsureSingleton());
        char pb[512];
        int po = 0;
        for (int i = 0; i < 40; ++i) {
            uint64_t v = sp[i];
            if (v == cfg || v == sing) {
                int n = snprintf(pb + po, sizeof(pb) - po, " stack[%d]=%s%llX", i,
                                 v == cfg ? "CFG " : "SING ",
                                 static_cast<unsigned long long>(v));
                if (n < 0) break;
                po += n;
                if (po >= static_cast<int>(sizeof(pb)) - 24) break;
            }
        }
        if (po > 0) HookLog(pb);
    }
    if (g_slotCountPtr != nullptr) {
        char sc[512];
        int o = 0;
        for (int i = 0; i < 64; ++i) {
            uint32_t c = const_cast<uint32_t*>(g_slotCountPtr)[i];
            if (c != 0) {
                int n = snprintf(sc + o, sizeof(sc) - o, " slot%d=%u", i, c);
                if (n < 0) break;
                o += n;
                if (o >= static_cast<int>(sizeof(sc)) - 20) break;
            }
        }
        if (o > 0) HookLog(sc);
    }
    // stack dump (40 qwords above Rsp) - the return addresses reveal the
    // call chain (thunk -> forwarder -> real method).
    auto* sp = reinterpret_cast<uint64_t*>(ctx->Rsp);
    char sb[2048];
    int off = 0;
    int dumped = 0;
    for (int i = 0; i < 40; ++i) {
        int n = snprintf(sb + off, sizeof(sb) - off, " %llX",
                         static_cast<unsigned long long>(sp[i]));
        if (n < 0) break;
        off += n;
        if (off >= static_cast<int>(sizeof(sb)) - 24) break;
        if (dumped < 6 && sp[i] >= 0x7ff000000000ULL && sp[i] <= 0x7fff00000000ULL) {
            DumpBytesAround(sp[i], dumped);
            ++dumped;
        }
    }
    HookLog(sb);
    // context diagnostics (game function on the "anonymous" path): the crash
    // is a hash-lookup at ctx+0x188 - dump the context object (rbp+0xf8)
    // and the map to see if they are valid pointers or garbage. Safe read via
    // VirtualQuery (MinGW has no __try/__except), it validates the region
    // before reading.
    auto IsReadable = [](uint64_t a, uint32_t len) -> bool {
        if (a < 0x10000 || a + len > 0x7fffffffffffULL) return false;
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery(reinterpret_cast<LPCVOID>(a), &mbi, sizeof(mbi)) == 0)
            return false;
        return mbi.State == MEM_COMMIT &&
               (mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE |
                               PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE)) != 0;
    };
    if (ctx->Rbp >= 0x10000 && IsReadable(ctx->Rbp, 0x100)) {
        uint64_t ctxp = *reinterpret_cast<uint64_t*>(ctx->Rbp + 0xf8);
        char cb[512];
        int co = 0;
        co += snprintf(cb + co, sizeof(cb) - co, "CTX: rbp=%llX ctx=%llX",
                       static_cast<unsigned long long>(ctx->Rbp),
                       static_cast<unsigned long long>(ctxp));
        if (IsReadable(ctxp, 0x200)) {
            auto* cq = reinterpret_cast<uint64_t*>(ctxp);
            for (int i = 0; i < 0x40; i += 8) {
                if (co < static_cast<int>(sizeof(cb)) - 24) {
                    co += snprintf(cb + co, sizeof(cb) - co, " [%X]=%llX",
                                   i, static_cast<unsigned long long>(cq[i / 8]));
                }
            }
        } else {
            if (co < static_cast<int>(sizeof(cb)) - 24)
                co += snprintf(cb + co, sizeof(cb) - co, " (ctx unreadable)");
        }
        HookLog(cb);
    }
#elif defined(__aarch64__) || defined(_M_ARM64)
    // Minimal dump (the full x64 one depends on the x64 CONTEXT layout):
    // Pc/Sp/Lr/X0..X3 + slot-tracking - enough initial signal to calibrate
    // the prologue heuristic when the first tester runs the dev release.
    {
        char b[600];
        snprintf(b, sizeof(b),
                 "CRASH: code=%08X pc=%p lr=%p sp=%p info0=%llX info1=%llX "
                 "lastSlot=%u",
                 code, reinterpret_cast<void*>(ctx->Pc),
                 reinterpret_cast<void*>(ctx->Lr),
                 reinterpret_cast<void*>(ctx->Sp),
                 static_cast<unsigned long long>(er->NumberParameters > 0
                                                      ? er->ExceptionInformation[0]
                                                      : 0),
                 static_cast<unsigned long long>(er->NumberParameters > 1
                                                      ? er->ExceptionInformation[1]
                                                      : 0),
                 g_lastSlotPtr != nullptr ? *g_lastSlotPtr : 0xffffffffu);
        HookLog(b);
        char rb[256];
        snprintf(rb, sizeof(rb),
                 "REGS: x0=%llX x1=%llX x2=%llX x3=%llX fp=%llX",
                 static_cast<unsigned long long>(ctx->X0),
                 static_cast<unsigned long long>(ctx->X1),
                 static_cast<unsigned long long>(ctx->X2),
                 static_cast<unsigned long long>(ctx->X3),
                 static_cast<unsigned long long>(ctx->Fp));
        HookLog(rb);
    }
#endif
    return EXCEPTION_CONTINUE_SEARCH;
#endif
}

// ============================================================================
// Fake thunks - mirror the functions of the original wrapper (stub RVAs)
// ============================================================================

// diagnostics: logs the 1st call of each thunk (and every 100th) to learn
// which slot the game REALLY queries for the license
static unsigned g_cRetFalse = 0, g_cRetTrue = 0, g_cNoop = 0, g_cWriteMagic = 0,
                g_cFillLicense = 0, g_cAsyncMagic = 0, g_cWriteZero = 0,
                g_cEntitlements = 0, g_cMask8 = 0, g_cMask10 = 0,
                g_cSkip1337 = 0, g_cMask21 = 0, g_cOwnedSet = 0, g_cCount31 = 0,
                g_cEnumerate = 0, g_cGetProductId = 0;
static void ThunkLog(const char* name, unsigned* c, const char* detail = nullptr) {
#if defined(HARDENED)
    (void)name; (void)c; (void)detail;  // compiled out under harden
#else
    ++*c;
    if (*c == 1 || *c % 100 == 0) {
        char b[200];
        if (detail != nullptr)
            snprintf(b, sizeof(b), "thunk: %s CALLED (x%u) - %s", name, *c, detail);
        else
            snprintf(b, sizeof(b), "thunk: %s CALLED (x%u)", name, *c);
        HookLog(b);
    }
#endif
}

// 0x4de0: returns false (non-trial / feature disabled)
int32_t WINAPI Thunk_RetFalse(void*) {
    ThunkLog("RetFalse(slot4 XPackage)", &g_cRetFalse);
    return 0;
}

// 0x4e50: returns true (owned)
int32_t WINAPI Thunk_RetTrue(void*) {
    ThunkLog("RetTrue(owned)", &g_cRetTrue);
    return 1;
}

// CLONE AddRef/Release: self refcount (constant), the REAL object is NEVER
// released by the game. In the clone, self IS the real object - using self[1]
// as refcount would corrupt real data, so we do not touch the object.
// Release never returns 0 (the object stays alive on purpose, the game
// process is short-lived). This avoids the use-after-free (the game calls
// Release on slot 2 EARLY and then accesses the object - confirmed:
// lastSlot=2 in the crash with the real Release).
int32_t WINAPI Thunk_AddRef(void*) { return 2; }
int32_t WINAPI Thunk_Release(void*) { return 1; }

// 0x4e10: no-op (returns 0 - safer than the original's garbage)
int32_t WINAPI Thunk_Noop(void*) {
    ThunkLog("Noop(slot6)", &g_cNoop);
    return 0;
}

// 0x4df0: *arg7 = 0x539, returns S_OK (the original reads the out at
// [rsp+0x38] = 7th arg).
// FIX 2026-08-13: [rsp+0x38] at entry = arg7 (not arg11).
int32_t WINAPI Thunk_WriteMagic(void*, void*, void*, void*, void*, void*,
                                uint64_t* out) {
    ThunkLog("WriteMagic(slot5, out=0x539)", &g_cWriteMagic);
    if (out != nullptr) *out = kMagicOwned;
    return 0;
}

// 0x4e20: license struct {q0=q1=q2=0x539, word@0x18=0x101}
void WINAPI Thunk_FillLicense(void*, void*, void* out) {
    ThunkLog("FillLicense(slot7, struct 0x539/0x101)", &g_cFillLicense);
    if (out == nullptr) return;
    auto* q = static_cast<uint64_t*>(out);
    q[0] = q[1] = q[2] = kMagicOwned;
    reinterpret_cast<uint16_t*>(out)[0x18 / 2] = kStateFlag;
}

// 0x4e60: cb (arg4), ctx (arg3), out (arg5): *out = 0x539, then cb(ctx),
// returns S_OK.
// FIX 2026-08-13: the original's out is the 5th arg ([rsp+0x28]), not the 9th.
int32_t WINAPI Thunk_AsyncMagic(void*, void*, void* ctx, void* cb,
                                uint64_t* out) {
    ThunkLog("AsyncMagic(slot9, cb+0x539)", &g_cAsyncMagic);
    if (cb != nullptr && out != nullptr) {
        *out = kMagicOwned;
        reinterpret_cast<void(WINAPI*)(void*)>(cb)(ctx);
    }
    return 0;
}

// 0x4f30: *arg5 = 0, returns S_OK (the original reads [rsp+0x28] = 5th arg,
// not the 9th)
int32_t WINAPI Thunk_WriteZero(void*, void*, void*, void*, uint32_t* out) {
    ThunkLog("WriteZero(slot12, *out=0)", &g_cWriteZero);
    if (out != nullptr) *out = 0;
    return 0;
}

// ---- fake entitlement + item (mirror of 0x4f50: cb(ctx, item, 0)) ----
struct FakeEntitlement {
    const char* kind;
    const char* id;
    const char* skuId;
    int64_t     expirationDate;  // 0 = never expires -> "owner"
};
struct FakeEntItem {
    uint32_t type;
    void*    data;
};

// 0x4f50: ORIGINAL's QueryEntitlementsAsync: iterates the config entitlement
// list (listA - EMPTY for Minecraft, confirmed in the live process) and calls
// cb(ctx, item, 0) per item. With the empty list the original returns S_OK
// WITHOUT calling the callback. Fabricating 1 entitlement here was a
// DIVERGENCE (the game saw a nonexistent entitlement and showed "Desbloquear"
// in the UI). Empty = identical to the original with an empty config.
int32_t WINAPI Thunk_FakeQueryEntitlementsAsync(void*, void*, int type,
                                                void* ctx, void* cb) {
    char b[192];
    DLOG("type=%d cb=%p ctx=%p (empty listA -> S_OK without cb)", type, cb, ctx);
    ThunkLog("FakeQueryEntitlements(slot13)", &g_cEntitlements);
    (void)ctx; (void)cb;
    return 0;
}

// 0x4ea0 (slot 11): GetProductId. RE verified: the original reads
// config->[0x10] (this->[0x10]->[0x10]). If NULL (the REAL case - the INI
// ProductId lives at config->[0x18], NOT [0x10]), it FORWARDS to the real
// slot 11 (jmp real_vt[11]) returning the game's REAL ProductId. It only
// fabricates (memcpy from config->[0x10]) when that field exists. Reproducing
// the forward is essential: fabricating "9NBLGGH2JHXJ" hardcoded diverged
// from the real one.
int32_t WINAPI Thunk_GetProductId(void* self, size_t size, char* buffer) {
    if (g_xpackage_orig_slot11 != nullptr) {
        int32_t hr = g_xpackage_orig_slot11(
            RealOf(self), reinterpret_cast<void*>(static_cast<uintptr_t>(size)), buffer);
        DLOG("fwd real hr=%08X buf=%s", static_cast<uint32_t>(hr),
             (buffer != nullptr && hr == 0) ? buffer : "(n/a)");
        ThunkLog("GetProductId(slot11)", &g_cGetProductId);
        return hr;
    }
    ThunkLog("GetProductId(slot11, fallback ini)", &g_cGetProductId);
    const size_t len = std::strlen(g_productId);
    if (buffer == nullptr || len + 1 > size) return 0x8007007a;
    std::memcpy(buffer, g_productId, len + 1);
    return 0;
}

// XStore slot 3: in the ORIGINAL (0x4dd0) it is a PURE FORWARDER
// (mov rcx,[rcx+0x18], jmp real_vt[3]) - the game gets the REAL result. In
// the wrapper it is the default forwarder (switch default). In the clone it
// was the real method with rcx=cloned object (internal calls land in the
// thunks - CRASHES on the "anonymous" path).

// WRAPPER: the game holds a WRAPPER object, and the REAL object sits at
// [0x18] with the ORIGINAL vtable intact. Forwarders preserve the real
// behavior (INTERNAL virtual calls land in the REAL methods). The CLONE
// crashes because the real methods, called with rcx=cloned object, make
// internal calls that land in our thunks with the wrong signature (crash on
// the "anonymous" path after the 2nd XStore query - validated 2026-08-13).

// ---- mask-owned (replays the OBSERVABLE behavior of the original
// 0x6290/0x62e0):
// In the ORIGINAL wrapper the real slot 8 FAILS (store does not pay) and the
// mask fabricates 0x1337. In the CLONE the real slot 8 SUCCEEDS (its internal
// virtual calls land in the real methods, which report owned via our license
// thunks) - so calling the real one would return the real handle (does NOT
// unlock - observed). To replay the original's observable behavior, the mask
// fabricates 0x1337 ALWAYS, without calling the real one:
//   [arg2+0x20]=0 (dword), *arg3=0x1337 (qword), always returns S_OK.
int32_t WINAPI XStoreMaskSlot8(void*, void* arg2, void* arg3) {
    ThunkLog("XStoreMaskSlot8(slot8, 0x1337 unconditional)", &g_cMask8);
    if (arg2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg2) + 0x20) = 0;
    if (arg3 != nullptr) *reinterpret_cast<uint64_t*>(arg3) = kMagicOwned64;
    return 0;
}
int32_t WINAPI XStoreMaskSlot10(void*, void* arg2, void* arg3) {
    ThunkLog("XStoreMaskSlot10(slot10, 0x1337 unconditional)", &g_cMask10);
    if (arg2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg2) + 0x20) = 0;
    if (arg3 != nullptr) *reinterpret_cast<uint64_t*>(arg3) = kMagicOwned64;
    return 0;
}

// 0x6930/0x6b10 (slots 19/23): if arg2 == 0x1337 (marker fabricated by the
// mask), returns S_OK WITHOUT calling the real one (the real one would break
// with the fake handle). Otherwise it forwards to the real slot.
int32_t WINAPI XStoreSkipIf1337_19(void* self, void* arg2, void* arg3) {
    if (reinterpret_cast<uintptr_t>(arg2) == kMagicOwned64) {
        ThunkLog("XStoreSkipIf1337(slot19, arg2==0x1337 -> S_OK)", &g_cSkip1337);
        return 0;
    }
    return g_xstore_orig_slot19(RealOf(self), arg2, arg3);
}
int32_t WINAPI XStoreSkipIf1337_23(void* self, void* arg2, void* arg3) {
    if (reinterpret_cast<uintptr_t>(arg2) == kMagicOwned64) {
        ThunkLog("XStoreSkipIf1337(slot23, arg2==0x1337 -> S_OK)", &g_cSkip1337);
        return 0;
    }
    return g_xstore_orig_slot23(RealOf(self), arg2, arg3);
}

// 0x6ac0 (slot 21): conditional mask - calls the real one and fabricates
// 0x1337 if (arg3 != null) && (hr != 0 || *arg3 == 0). Returns the real hr
// when it does not fabricate, S_OK when it fabricates.
int32_t WINAPI XStoreMaskSlot21(void* self, void* arg2, void* arg3) {
    int32_t hr = g_xstore_orig_slot21 != nullptr
        ? g_xstore_orig_slot21(RealOf(self), arg2, arg3) : 0;
    DLOG("hr_real=%08X *arg3=%llu", static_cast<uint32_t>(hr),
         (arg3 != nullptr) ? *reinterpret_cast<uint64_t*>(arg3) : 0ULL);
    ThunkLog("XStoreMaskSlot21(slot21)", &g_cMask21);
    if (arg3 != nullptr && (hr != 0 || *reinterpret_cast<uint64_t*>(arg3) == 0)) {
        if (arg2 != nullptr)
            *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg2) + 0x20) = 0;
        *reinterpret_cast<uint64_t*>(arg3) = kMagicOwned64;
        return 0;
    }
    return hr;
}

// forward decls (defined in the constants block below)
static const char* ItemBrand();
static const char* ItemMagic();
static const char* ItemOffer();
static const char* ItemUrl();

// 0x6b40 (slots 25/27): RE verified: [arg2+0x20]=0, memcpy(arg3,"0010",5),
// [arg3+8]=1, S_OK. The offerId "0010" memcpy was MISSING in the rebuild.
int32_t WINAPI XStoreOwnedSet(void*, void* arg2, void* arg3) {
    ThunkLog("XStoreOwnedSet(slot25/27)", &g_cOwnedSet);
    if (arg2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg2) + 0x20) = 0;
    if (arg3 != nullptr) {
        std::memcpy(arg3, ItemOffer(), 5);  // "0010\0" (offerId, cifrado)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg3) + 8) = 1;
    }
    return 0;
}

// REAL SLOT 15 (0xd4770 = the storeimpl function that crashed): signature
// (self, list, arg3, callback) - EXACTLY 4 args (verified in the disasm: the
// prologue uses [entry_rsp+8/+0x18/+0x20] as scratch to save rbx/rsi/rdi, it
// does not read args 5+). Real behavior: validates list[+0x4c], iterates
// 0xd0-byte items from list[+0x18] up to list[+0x20], calling
// callback(item, arg3) for each (the callback returns bool: 0 = stop). The
// ORIGINAL (wrapper 0x6350) IGNORES 'list' and iterates the object's internal
// list (self->[0x10]) - which in our clone is EMPTY (the real store answers
// "not paid"). So, on the 0x1337 marker path we fabricate ONE "owned" item
// (0xd0 bytes, mirroring the 0x6350 offsets) and call cb(item, arg3) once.
// A valid list (non-0x1337) is forwarded to the real one.
//
// Store item strings of the project (brand "CoelhoFZ"). The expected
// "owned" signature is type=2 (Durable), flags 1, kind=5 and the magic "1337".

static const char* const kItemKind   = "Game";   // ProductKind (the game compares it to recognize the full game)
static const char* const kItemLocale = "en-US";
static const char* const kItemCur    = "USD";
// Brand/magic/offer encrypted (enc_strings.h) - persistent buffers (the game
// keeps the pointers of the fabricated items). Plaintext does not exist in
// the binary.
static const char* ItemBrand() {
    static char buf[16];
    if (buf[0] == '\0')
        std::strcpy(buf, enc::dec(enc::kItemBrand, enc::kItemBrandLen, 0x5A));
    return buf;
}
static const char* ItemMagic() {
    static char buf[8];
    if (buf[0] == '\0')
        std::strcpy(buf, enc::dec(enc::kItemMagic, enc::kItemMagicLen, 0x5A));
    return buf;
}
static const char* ItemOffer() {
    static char buf[8];
    if (buf[0] == '\0')
        std::strcpy(buf, enc::dec(enc::kItemOffer, enc::kItemOfferLen, 0x5A));
    return buf;
}
// entitlement image - encrypted (enc_strings.h): the plaintext does not
// exist in the binary. Persistent buffer (the game keeps the pointer of the
// fabricated item).
static const char* ItemUrl() {
    static char buf[64];
    if (buf[0] == '\0')
        std::strcpy(buf, enc::dec(enc::kItemUrl, enc::kItemUrlLen, 0x5A));
    return buf;
}

static void* NewZero(size_t n) {
    return HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, n);
}

// Writes a string inline into the item (MSVC-style SSO: bytes at the offset
// itself, no pointer) - used in the price struct (item[0x38..0x8f]), where
// the game callback does strlen(&item[0x60]) directly.
static void WriteInline(char* dst, const char* s) {
    std::strcpy(dst, s);
}

// Game callback dump (for RE): the shim runs INSIDE the game process...
// (compiled out under harden).
#if defined(HARDENED)
static void DumpCallbackBytes(const void*) {}
#else
static void DumpCallbackBytes(const void* fn) {
    if (fn == nullptr) return;
    char tmp[MAX_PATH];
    if (GetTempPathA(MAX_PATH, tmp) == 0) return;
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%scoelhofz_cb.bin", tmp);
    // do not overwrite if it exists (the callback is the same across repeated calls)
    FILE* probe = fopen(path, "rb");
    if (probe != nullptr) { fclose(probe); return; }
    FILE* f = fopen(path, "wb");
    if (f == nullptr) return;
    fwrite(fn, 1, 4096, f);
    fclose(f);
    HookLog("dump: game callback saved (4096 bytes)");
}
#endif

int32_t WINAPI XStoreEnumerateSlot15(void* self, void* list, void* arg3,
                                     void* callback) {
    char b[192];
    DLOG("list=%p arg3=%p cb=%p (config EMPTY -> S_OK without cb)", list, arg3, callback);
    ThunkLog("XStoreEnumerate(slot15)", &g_cEnumerate);
    DumpCallbackBytes(callback);
    // PROVEN CONFIGURATION (runs 1-8 of the 17:45-20:30 log - game alive for
    // 100 min): the enumerate FABRICATES the "owned" item (full RE layout) and
    // calls the game callback ONCE. The game passes the 0x1337 marker (from
    // mask8) as 'list' and EXPECTS the item - with an empty S_OK the marker
    // path breaks. It is the only combo (unconditional mask8 + enumerate with
    // item) that ran stable in the good era.

    // ---- fabricates the "owned" item (0xd0 bytes, heap - the game keeps the
    // ptr). EXACT item layout of the original (0x6350 - complete RE): ----
    //   [0x00]=kind "Durable"  [0x08]=productId  [0x10]=brand  [0x18]=locale
    //   [0x20]=productId       [0x28]=image URL  [0x30]=type=2 (Durable)
    //   [0x38..0x8f]=price {1337.0f x3, "USD", "1337" x3 inline}
    //   [0x90]=1 [0x91]=1 [0x94]=1 [0x98]=str obj [0xa0]=1 [0xa8]=core
    //   [0xb0]=1 [0xb8]=obj [0xc0]=1 [0xc8]=obj
    auto* item = static_cast<uint8_t*>(NewZero(0xd0));
    if (item == nullptr) return kErrXbox;
    *reinterpret_cast<const char**>(item + 0x00) = kItemKind;   // kind
    *reinterpret_cast<const char**>(item + 0x08) = g_productId; // id
    *reinterpret_cast<const char**>(item + 0x10) = ItemBrand();
    *reinterpret_cast<const char**>(item + 0x18) = kItemLocale;
    *reinterpret_cast<const char**>(item + 0x20) = g_productId; // skuId
    *reinterpret_cast<const char**>(item + 0x28) = ItemUrl();   // imagem
    *reinterpret_cast<uint32_t*>(item + 0x30) = 2;   // type = Durable/owned
    // price struct (mirror of 0x6350: 3 floats 1337.0 + "USD" + "1337" x3)
    // FIX 2026-08-13 (disasm 0x6350): the original's price struct has the
    // "1337" INLINE at 0x50/0x60/0x70 (the game callback does
    // strlen(&item[0x60]) - it used to sit at 0x58/0x68/0x78 and the game
    // read EMPTY). Layout: [0x38]=1337.0f [0x3c]=1337.0f [0x40]=1337.0f
    // [0x44]=gap [0x48]="USD" ptr [0x50]="1337" [0x58]=zeros [0x60]="1337"
    // [0x68]=zeros [0x70]="1337" [0x78]=zeros [0x88]=0.
    *reinterpret_cast<float*>(item + 0x38) = 1337.0f;
    *reinterpret_cast<float*>(item + 0x3c) = 1337.0f;
    *reinterpret_cast<float*>(item + 0x40) = 1337.0f;
    *reinterpret_cast<const char**>(item + 0x48) = kItemCur;   // "USD"
    WriteInline(reinterpret_cast<char*>(item + 0x50), ItemMagic());  // "1337"
    WriteInline(reinterpret_cast<char*>(item + 0x60), ItemMagic());  // "1337"
    WriteInline(reinterpret_cast<char*>(item + 0x70), ItemMagic());  // "1337"
    item[0x90] = 1;
    item[0x91] = 1;
    *reinterpret_cast<uint32_t*>(item + 0x94) = 1;
    *reinterpret_cast<uint32_t*>(item + 0xa0) = 1;
    *reinterpret_cast<uint32_t*>(item + 0xb0) = 1;
    *reinterpret_cast<uint32_t*>(item + 0xc0) = 1;
    // string objects (ptr -> alloc with the string ptr at [0]): all valid so
    // the game callback does not crash on strlen(NULL).
    auto* s98 = static_cast<uint8_t*>(NewZero(0x20));
    *reinterpret_cast<void**>(item + 0x98) = s98;
    if (s98 != nullptr) *reinterpret_cast<const char**>(s98 + 0x00) = ItemBrand();
    auto* core = static_cast<uint8_t*>(NewZero(0x110));
    *reinterpret_cast<void**>(item + 0xa8) = core;
    auto* sB8 = static_cast<uint8_t*>(NewZero(0x20));
    *reinterpret_cast<void**>(item + 0xb8) = sB8;
    if (sB8 != nullptr) {
        *reinterpret_cast<const char**>(sB8 + 0x00) = ItemUrl();
        *reinterpret_cast<const char**>(sB8 + 0x10) = ItemBrand();
        *reinterpret_cast<const char**>(sB8 + 0x18) = kItemKind;
    }
    auto* sC8 = static_cast<uint8_t*>(NewZero(0x40));
    *reinterpret_cast<void**>(item + 0xc8) = sC8;
    if (sC8 != nullptr) {
        *reinterpret_cast<const char**>(sC8 + 0x00) = ItemUrl();
        *reinterpret_cast<const char**>(sC8 + 0x10) = ItemBrand();
        *reinterpret_cast<const char**>(sC8 + 0x18) = kItemKind;
        *reinterpret_cast<const char**>(sC8 + 0x20) = ItemUrl();
        *reinterpret_cast<const char**>(sC8 + 0x30) = ItemBrand();
        *reinterpret_cast<const char**>(sC8 + 0x38) = kItemKind;
    }
    if (core != nullptr) {
        // ---- core = product (0x110 bytes) - EXACT mirror of 0x6350: ----
        //   [0]=offerId "0010"  [8]=productId  [0x10]=brand  [0x18]=locale
        //   [0x20..0x77]=price  [0x79]=1  [0xa0]=1  [0xa8]/[0xb0]=brand
        //   [0xb8]=1  [0xc0]/[0xc8]=5  [0xd0]=1  [0xd8]=str obj {[0]="0010"}
        //   [0xe0]=1  [0xe8]=obj  [0xf0]=1  [0xf8]=sC8  [0x100]=1
        //   [0x108]=str obj {[0]=brand}
        *reinterpret_cast<const char**>(core + 0x00) = ItemOffer();
        *reinterpret_cast<const char**>(core + 0x08) = g_productId;
        *reinterpret_cast<const char**>(core + 0x10) = ItemBrand();
        *reinterpret_cast<const char**>(core + 0x18) = kItemLocale;
        // FIX 2026-08-13 (disasm 0x6350): same price struct, the core's
        // inline "1337" sits at 0x38/0x48/0x58 (the game callback does
        // strlen(&core[0x48]) - it used to sit at 0x40/0x50/0x60 and the
        // game read EMPTY).
        *reinterpret_cast<float*>(core + 0x20) = 1337.0f;
        *reinterpret_cast<float*>(core + 0x24) = 1337.0f;
        *reinterpret_cast<float*>(core + 0x28) = 1337.0f;
        *reinterpret_cast<const char**>(core + 0x30) = kItemCur;   // "USD"
        WriteInline(reinterpret_cast<char*>(core + 0x38), ItemMagic());  // "1337"
        WriteInline(reinterpret_cast<char*>(core + 0x48), ItemMagic());  // "1337"
        WriteInline(reinterpret_cast<char*>(core + 0x58), ItemMagic());  // "1337"
        core[0x79] = 1;
        *reinterpret_cast<uint32_t*>(core + 0xa0) = 1;
        *reinterpret_cast<const char**>(core + 0xa8) = ItemBrand();
        *reinterpret_cast<const char**>(core + 0xb0) = ItemBrand();
        core[0xb8] = 1;
        *reinterpret_cast<uint64_t*>(core + 0xc0) = 5;  // kind
        *reinterpret_cast<uint64_t*>(core + 0xc8) = 5;
        *reinterpret_cast<uint32_t*>(core + 0xd0) = 1;
        auto* sD8 = static_cast<uint8_t*>(NewZero(8));
        *reinterpret_cast<void**>(core + 0xd8) = sD8;
        if (sD8 != nullptr) *reinterpret_cast<const char**>(sD8) = ItemOffer();
        *reinterpret_cast<uint32_t*>(core + 0xe0) = 1;
        auto* sE8 = static_cast<uint8_t*>(NewZero(0x20));
        *reinterpret_cast<void**>(core + 0xe8) = sE8;
        if (sE8 != nullptr) {
            *reinterpret_cast<const char**>(sE8 + 0x00) = ItemUrl();
            *reinterpret_cast<const char**>(sE8 + 0x10) = ItemBrand();
            *reinterpret_cast<const char**>(sE8 + 0x18) = kItemKind;
        }
        *reinterpret_cast<uint32_t*>(core + 0xf0) = 1;
        *reinterpret_cast<void**>(core + 0xf8) = sC8;  // mesmo obj do item[0xc8]
        *reinterpret_cast<uint32_t*>(core + 0x100) = 1;
        auto* s108 = static_cast<uint8_t*>(NewZero(0x68));
        *reinterpret_cast<void**>(core + 0x108) = s108;
        if (s108 != nullptr) *reinterpret_cast<const char**>(s108) = ItemBrand();
    }

    // diagnostics: dump of the critical fields of the fabricated item
    // (confirms the price struct is correct - item[0x60] and core[0x48] must
    // be "1337", not empty). (compiled out under harden)
#if !defined(HARDENED)
    {
        const char* s00 = *reinterpret_cast<const char**>(item + 0x00);
        const char* s08 = *reinterpret_cast<const char**>(item + 0x08);
        const char* s20 = *reinterpret_cast<const char**>(item + 0x20);
        const char* s60 = reinterpret_cast<const char*>(item + 0x60);
        const char* c00 = (core != nullptr)
            ? *reinterpret_cast<const char**>(core + 0x00) : nullptr;
        const char* c48 = (core != nullptr)
            ? reinterpret_cast<const char*>(core + 0x48) : nullptr;
        char db[320];
        snprintf(db, sizeof(db),
                 "item: [0]=%s [8]=%s [0x20]=%s [0x60]=%s | core[0]=%s core[0x48]=%s",
                 s00 ? s00 : "(null)", s08 ? s08 : "(null)",
                 s20 ? s20 : "(null)", s60,
                 c00 ? c00 : "(null)", c48 ? c48 : "(null)");
        HookLog(db);
    }
#endif

    // ---- calls the game callback: cb(item, arg3) -> bool (0 = stop) ----
    using CbFn = bool(WINAPI*)(void*, void*);
    auto cb = reinterpret_cast<CbFn>(callback);
    const bool cont = cb(item, arg3);
    DLOG("slot15: cb(%p, %p) -> %d", item, arg3, (int)cont);
    return 0;
}

// 0x6ea0 (slot 31): RE verified - the original returns *arg3 = count of the
// config list A (EMPTY = 0), it does NOT fabricate 1. [arg2+0x20]=0, *arg3=0,
// S_OK. Fabricating count=1 was a DIVERGENCE (the game saw 1 nonexistent
// entitlement).
int32_t WINAPI XStoreCountSlot31(void* /*self*/, void* arg2, void* arg3) {
    ThunkLog("XStoreCount(slot31, count=0 empty config)", &g_cCount31);
    if (arg3 == nullptr) return kErrXbox;
    if (arg2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(arg2) + 0x20) = 0;
    *reinterpret_cast<uint32_t*>(arg3) = 0;  // count = 0 (empty config list)
    return 0;
}

// ============================================================================
// CUSTOM SLOTS OF THE ORIGINAL (slots 20/26/29/32) - the link of the "anonymous" path
// ============================================================================
// The ORIGINAL's wrapper builds a NATIVE config (ProductId at [0x18], listA at
// [0x20]/[0x28], SKU at [0x38]) and the custom slots 20/26/29/32 read that
// config to build the license structures. Complete RE (stub_full.bin disassembly):
//
//   slot 20 (0x6950) / slot 26 (0x6b80): iterates the config listA looking for
//     a match with arg3 (strcmp). On hit: [arg4+0x20]=0 and calls the callback
//     (*0x10)(arg4) - answers "owned" by itself. On miss (empty listA = the
//     Minecraft case): FORWARDS to the real slot (fwd vt[0xa0]/vt[0xd0]).
//   slot 29 (0x6d00): forwards to the real slot 29 (vt[0xe8]). If arg3 != NULL
//     it builds the product struct {0x10001 at [0x12], config ProductId at
//     [0x18], strings} - the game reads those fields on the anonymous path.
//   slot 32 (0x6ed0): iterates count times building 0x60-byte items with
//     SKU[i] (config[0x38]) and listA[i] (config[0x20]).
//
// The config is built by the handler (CreateWrapper) in the original's layout:
//   wrapper[0x08]=singleton, wrapper[0x10]=config, wrapper[0x18]=real.

// wrapper native config (mirror of the live dump 0x...DA6F0):
//   [0x18] = ProductId (ptr to an ASCII string)
//   [0x20] = listA.begin (ptr to an array of const char*)
//   [0x28] = listA.end
//   [0x38] = SKU (ptr to an array of const char*)
struct NativeConfig {
    uint8_t  pad0[0x18];
    const char* productId;   // [0x18]
    const char** listABegin; // [0x20]
    const char** listAEnd;   // [0x28]
    uint8_t  pad1[0x8];      // [0x30]
    const char** sku;        // [0x38]
};

// wrapper singleton (mirror of the original 0x36d08): wide path buffer.
// The original uses wrapper[0x08]=singleton and wrapper[0x10]=singleton[0x18].
// In Minecraft the singleton is practically empty - we build a valid minimum.
struct NativeSingleton {
    uint8_t  pad[0x18];
    void*    config;         // [0x18] = pointer to the config (like the original)
};

// config listA: EMPTY for Minecraft (confirmed live on 2026-08-14:
// the config dump shows config[0x20]=NULL [0x28]=NULL). The array points
// to the "" string (terminator) - a valid empty span.
static const char* kEmptyStorage[1] = {""};
static const char** const kEmptyList = kEmptyStorage;

// builds the config + singleton (once) in the original's layout. Returns the
// config. The singleton (with [0x18]=config) is reachable via EnsureSingleton().
static NativeSingleton* g_nativeSingleton = nullptr;
static NativeConfig* EnsureNativeConfig() {
    static NativeConfig* s_config = nullptr;
    if (s_config != nullptr) return s_config;
    auto* cfg = static_cast<NativeConfig*>(
        HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(NativeConfig)));
    auto* sing = static_cast<NativeSingleton*>(
        HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(NativeSingleton)));
    if (cfg == nullptr || sing == nullptr) {
        if (cfg != nullptr) HeapFree(GetProcessHeap(), 0, cfg);
        if (sing != nullptr) HeapFree(GetProcessHeap(), 0, sing);
        return nullptr;
    }
    cfg->productId = g_productId;              // [0x18]
    cfg->listABegin = kEmptyList;              // [0x20] (empty - like the original)
    cfg->listAEnd = kEmptyList;                // [0x28] (empty = 0 items)
    cfg->sku = nullptr;                        // [0x38] (NULL like the original)
    sing->config = cfg;                        // singleton[0x18] = config
    s_config = cfg;
    g_nativeSingleton = sing;
    return cfg;
}
static NativeSingleton* EnsureSingleton() {
    if (g_nativeSingleton != nullptr) return g_nativeSingleton;
    EnsureNativeConfig();
    return g_nativeSingleton;
}

// XStore slot 20: iterates the config listA looking for a match (strcmp) with
// arg3. On hit it sets [arg4+0x20]=0, calls the callback (*0x10)(arg4) and
// returns S_OK. On miss (empty listA = Minecraft) it forwards to the real
// slot 20.
using XStoreSlot20Fn = int32_t(WINAPI*)(void*, void*, void*, void*);
static XStoreSlot20Fn g_xstore_orig_slot20 = nullptr;
static XStoreSlot20Fn g_xstore_orig_slot26 = nullptr;
using XStoreSlot29Fn = int32_t(WINAPI*)(void*, void*, void*);
static XStoreSlot29Fn g_xstore_orig_slot29 = nullptr;

int32_t WINAPI XStoreIterSlot20(void* self, void* a2, void* a3, void* a4) {
    // mirror of the original: if arg3 or arg4 is NULL, forwards to the real one
    if (a3 == nullptr || a4 == nullptr) {
        if (g_xstore_orig_slot20 != nullptr)
            return g_xstore_orig_slot20(RealOf(self), a2, a3, a4);
        return kErrXbox;
    }
    NativeConfig* cfg = EnsureNativeConfig();
    // iterates listA (empty for Minecraft -> forwards to the real one, like the original)
    if (cfg != nullptr && cfg->listABegin != nullptr && cfg->listAEnd != nullptr) {
        for (const char** it = cfg->listABegin; it < cfg->listAEnd; ++it) {
            const char* item = *it;
            if (item != nullptr &&
                reinterpret_cast<const char*>(a3) != nullptr &&
                std::strcmp(reinterpret_cast<const char*>(a3), item) == 0) {
                if (a4 != nullptr) {
                    *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(a4) + 0x20) = 0;
                    // calls *0x10(a4) = object callback (mirror of the original)
                    auto cb = *reinterpret_cast<void(WINAPI**)(void*)>(
                        static_cast<uint8_t*>(a4) + 0x10);
                    if (cb != nullptr) cb(a4);
                }
                ThunkLog("XStoreIter(slot20, match in listA -> cb)", &g_cOwnedSet);
                return 0;
            }
        }
    }
    // no match (empty listA): forwards to the real slot 20 (like the original)
    if (g_xstore_orig_slot20 != nullptr)
        return g_xstore_orig_slot20(RealOf(self), a2, a3, a4);
    return kErrXbox;
}

// slot 26: same as 20, but forwards to the real slot 26 (fwd vt[0xd0])
int32_t WINAPI XStoreIterSlot26(void* self, void* a2, void* a3, void* a4) {
    if (a3 == nullptr || a4 == nullptr) {
        if (g_xstore_orig_slot26 != nullptr)
            return g_xstore_orig_slot26(RealOf(self), a2, a3, a4);
        return kErrXbox;
    }
    NativeConfig* cfg = EnsureNativeConfig();
    if (cfg != nullptr && cfg->listABegin != nullptr && cfg->listAEnd != nullptr) {
        for (const char** it = cfg->listABegin; it < cfg->listAEnd; ++it) {
            const char* item = *it;
            if (item != nullptr &&
                reinterpret_cast<const char*>(a3) != nullptr &&
                std::strcmp(reinterpret_cast<const char*>(a3), item) == 0) {
                if (a4 != nullptr) {
                    *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(a4) + 0x20) = 0;
                    auto cb = *reinterpret_cast<void(WINAPI**)(void*)>(
                        static_cast<uint8_t*>(a4) + 0x10);
                    if (cb != nullptr) cb(a4);
                }
                ThunkLog("XStoreIter(slot26, match in listA -> cb)", &g_cOwnedSet);
                return 0;
            }
        }
    }
    if (g_xstore_orig_slot26 != nullptr)
        return g_xstore_orig_slot26(RealOf(self), a2, a3, a4);
    return kErrXbox;
}

// slot 29 (0x6d00): forwards to the real slot 29 (vt[0xe8]) with rcx=real.
// If arg3 != NULL it builds the product struct with the config ProductId. The
// game, on the anonymous path, reads those fields (mirror of the disassembly:
// [0x12]=0x10001, [0x18]=ProductId, [0x60]=string object).
int32_t WINAPI XStoreStructSlot29(void* self, void* a2, void* a3) {
    int32_t hr = -1;
    if (g_xstore_orig_slot29 != nullptr)
        hr = g_xstore_orig_slot29(RealOf(self), a2, a3);
    if (a3 == nullptr) return hr;
    // builds the struct in the original's layout (mirror of the 0x6d00 disassembly):
    NativeConfig* cfg = EnsureNativeConfig();
    auto* out = static_cast<uint8_t*>(a3);
    if (a2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(a2) + 0x20) = 0;
    *reinterpret_cast<uint32_t*>(out + 0x12) = 0x10001;  // product flag
    // [0x18] = ProductId (ptr)
    if (cfg != nullptr)
        *reinterpret_cast<const char**>(out + 0x18) = cfg->productId;
    // [0x60] = string object with the ProductId (the game does strlen on it)
    auto* s60 = static_cast<uint8_t*>(NewZero(0x20));
    if (s60 != nullptr) {
        *reinterpret_cast<void**>(out + 0x60) = s60;
        if (cfg != nullptr)
            *reinterpret_cast<const char**>(s60) = cfg->productId;
    }
    return 0;
}

// slot 32 (0x6ed0): builds an array of 0x60-byte items (count items) with
// SKU[i] (config[0x38]) and listA[i] (config[0x20]) - mirror of the original.
// With an empty config (Minecraft) and count=0 it returns 0x89245302 like the
// original.
using XStoreSlot32Fn = int32_t(WINAPI*)(void*, void*, uint32_t, void*);
int32_t WINAPI XStoreArraySlot32(void* self, void* a2, uint32_t count, void* a4) {
    if (count == 0 || a4 == nullptr) return kErrXbox;  // 0x89245302 (original)
    NativeConfig* cfg = EnsureNativeConfig();
    auto* arr = static_cast<uint8_t*>(a4);
    if (a2 != nullptr)
        *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(a2) + 0x20) = 0;
    const char** sku = cfg != nullptr ? cfg->sku : nullptr;
    const char** listA = cfg != nullptr ? cfg->listABegin : nullptr;
    for (uint32_t i = 0; i < count; ++i) {
        uint8_t* item = arr + static_cast<size_t>(i) * 0x60;
        // [0x52]=1 (owned), [0x58]=string builder ptr
        item[0x52] = 1;
        // SKU[i] -> string field at offset 0x12
        if (sku != nullptr && sku[i] != nullptr) {
            auto* s = static_cast<uint8_t*>(NewZero(0x20));
            if (s != nullptr) {
                *reinterpret_cast<void**>(item + 0x12) = s;
                *reinterpret_cast<const char**>(s) = sku[i];
            }
        }
        // listA[i] -> string field (ProductId) in the item
        if (listA != nullptr && listA[i] != nullptr) {
            auto* s = static_cast<uint8_t*>(NewZero(0x20));
            if (s != nullptr) {
                *reinterpret_cast<void**>(item) = s;
                *reinterpret_cast<const char**>(s) = listA[i];
            }
        }
    }
    return 0;
}

// ============================================================================
// WRAPPER (the architecture that WORKS - validated in the 20:15 run "license active")
// ============================================================================
// The game holds a WRAPPER object, and the REAL object sits at wrapper->[0x18]
// with the ORIGINAL vtable intact. All NON-license slots are FORWARDERS
// (mov rcx,[rcx+0x18], jmp real_vt[slot]) - they preserve the real behavior
// and, crucially, the INTERNAL virtual calls of the real methods land in the
// REAL methods (not in the thunks). The CLONE (vtable swapped on the real
// object) CRASHES: the real methods called with rcx=cloned object make
// internal calls that land in our thunks with the wrong signature (c0000005
// on the "anonymous" path after the 2nd XStore query - tested 2026-08-13 with
// the minimal set and the full set).
//
// The 20:15 run (per-query wrapper, mask8 "owned=fabricated", enumerate with
// item, no GetProductId, no config) REACHED mask8 WITHOUT crashing - proof
// that the wrapper reaches the license check. The later wrapper crashes were:
// (1) EmitForwarder with p+=13 (14 real bytes) - fixed; (2) Release
// use-after-free (the real Release freed the object) - fixed with a
// self-refcount AddRef/Release; (3) enumerate with a FABRICATED item - the
// game saw a nonexistent entitlement and showed "Desbloquear".
//
// The unlock (observed in the logs): mask8 -> 0x1337 + enumerate -> EMPTY. In
// the wrapper the real slot 8 FAILS (store does not pay) - mask8 fabricates
// 0x1337 (the original does the SAME: it fabricates when the real one fails.
// Here we always fabricate to be safe). Enumerate (slot 15) = S_OK with no
// items (config list A empty). XPackage entitlements (slot 13) = S_OK with no
// items (same).

// ---- slot-tracking (only for the VEH: lastSlot/slotCount) ----
uint8_t* g_fwdPage = nullptr;  // executable page for the forwarders + slot-tracking
uint32_t g_fwdUsed = 0;        // cursor of bytes already used in the page

static bool EnsureFwdPage() {
    if (g_fwdPage != nullptr) return true;
    g_fwdPage = static_cast<uint8_t*>(VirtualAlloc(
        nullptr, 0x5000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (g_fwdPage == nullptr) return false;
#if !defined(HARDENED)
    g_lastSlotPtr = reinterpret_cast<volatile uint32_t*>(g_fwdPage + 0x4000);
    *g_lastSlotPtr = 0xffffffff;
    g_slotCountPtr = reinterpret_cast<volatile uint32_t*>(g_fwdPage + 0x4100);
    for (int i = 0; i < 64; ++i)
        const_cast<uint32_t*>(g_slotCountPtr)[i] = 0;
#endif
    return true;
}

// pure forwarder (identical to the original): mov rcx,[rcx+0x18], mov rax,[rcx],
// jmp [rax+slot*8]. It does NOT clobber xmm (high slots pass struct/float in
// xmm0-7). 14 bytes (4+3+3+4) - mind the cursor advance. It also stores the
// slot in a global (mov [rip+rel32],imm32 - memory only, never a register) so
// the VEH can log the LAST forwarded slot before the crash.
// ============================================================================
// EmitForwarder - emits the forwarding code into the RWX page.
//
// BOTH archs load the real object from wrapper[0x18], take its vt[0] and jump
// to vt[slot]. The difference:
//   x64   : real^RealKey at [0x18], decode with an embedded xor-immediate,
//           RIP-relative tracking (10B).
//   ARM64 : real in PLAINTEXT (there is no cheap immediate decode without
//           using x10-x15 as scratch + a literal instruction), so the
//           "decode" simply becomes NOT encrypting. Tracking via absolute
//           ADRP/ADD.
// ============================================================================
static uint8_t* EmitForwarder(uint8_t* p, uint32_t slot) {
#if defined(__aarch64__) || defined(_M_ARM64)
#if !defined(HARDENED)
    if (g_lastSlotPtr != nullptr) {
        // adrp+add -> x16 = &lastSlot; movz w14 = slot; str w14,[x16]
        EmitAdrpAdd(p, 16, reinterpret_cast<uintptr_t>(g_lastSlotPtr));
        *reinterpret_cast<uint32_t*>(p + 8)  = 0x52800000u | (slot << 5) | 14;
        *reinterpret_cast<uint32_t*>(p + 12) = 0xB900020Eu;  // str w14,[x16]
        // adrp+add -> x15 = &slotCount[slot]; (*++); via ldr/add/str
        EmitAdrpAdd(p + 16, 15,
                    reinterpret_cast<uintptr_t>(g_slotCountPtr) + slot * 4);
        *reinterpret_cast<uint32_t*>(p + 24) = 0xB94001EDu;  // ldr w13,[x15]
        *reinterpret_cast<uint32_t*>(p + 28) = 0x1100026Du;  // add w13,w13,#1
        *reinterpret_cast<uint32_t*>(p + 32) = 0xB90001EDu;  // str w13,[x15]
        p += 36;
    }
#endif
    // core forwarding (16B):
    *reinterpret_cast<uint32_t*>(p + 0)  = 0xF9400C11u;  // ldr x17,[x0,#0x18]
    *reinterpret_cast<uint32_t*>(p + 4)  = 0xF9400230u;  // ldr x16,[x17]
    *reinterpret_cast<uint32_t*>(p + 8)  =               // ldr x17,[x16,#(slot*8)]
        0xF9400000u | ((slot << 10) & 0x3FF000u) | (16 << 5) | 17;
    *reinterpret_cast<uint32_t*>(p + 12) = 0xD61F0220u;  // br x17
    return p + 16;
#else
    *p++ = 0x48; *p++ = 0x8B; *p++ = 0x49; *p++ = 0x18;  // mov rcx,[rcx+0x18]
    // xor rcx, imm32  (48 81 F1) with the per-process key: the real one at
    // [0x18] is XORed - the real object's plaintext does not appear in the
    // wrapper.
    *p++ = 0x48; *p++ = 0x81; *p++ = 0xF1;
    *reinterpret_cast<uint32_t*>(p) = RealKey();
    p += 4;
    *p++ = 0x48; *p++ = 0x8B; *p++ = 0x01;                // mov rax,[rcx]
    *p++ = 0x48; *p++ = 0xFF; *p++ = 0xA0;                // jmp [rax+disp32]
    *reinterpret_cast<uint32_t*>(p) = slot * 8;
    return p + 4;
#endif
}

#if !defined(HARDENED)
// ---- slot 3 diagnostics (GetServiceContext?): forwards to the real one and
// dumps the returned context object (the crash is a hash-lookup at ctx+0x188
// on the "anonymous" path - we want to see whether the context is valid or
// garbage).
Slot3Fn g_xstore_orig_slot3 = nullptr;

static void DumpCtxField(uint64_t ptr, int off, const char* label) {
    char b[128];
    if (ptr < 0x10000 || ptr + 0x200 > 0x7fffffffffffULL) {
        snprintf(b, sizeof(b), "slot3 %s: invalid ctx", label);
        HookLog(b);
        return;
    }
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(reinterpret_cast<LPCVOID>(ptr), &mbi, sizeof(mbi)) == 0 ||
        mbi.State != MEM_COMMIT) {
        snprintf(b, sizeof(b), "slot3 %s: ctx+%X unreadable", label, off);
        HookLog(b);
        return;
    }
    uint64_t v = 0;
    if (off >= 0 && off + 8 <= 0x200) {
        v = *reinterpret_cast<uint64_t*>(ptr + off);
        snprintf(b, sizeof(b), "slot3 %s: ctx=%p [%X]=%llX", label,
                 reinterpret_cast<void*>(ptr), off,
                 static_cast<unsigned long long>(v));
        HookLog(b);
    }
}

int32_t WINAPI XStoreSlot3Dump(void* self, void* a2, void* a3) {
    int32_t hr = -1;
    if (g_xstore_orig_slot3 != nullptr)
        hr = g_xstore_orig_slot3(RealOf(self), a2, a3);
    char b[192];
    snprintf(b, sizeof(b),
             "XStoreSlot3 fwd: hr=%08X a2=%p a3=%p self=%p real=%p",
             static_cast<uint32_t>(hr), a2, a3, self, RealOf(self));
    HookLog(b);
    // real[1] = real object refcount (confirms the AddRef anchor on wrap)
    {
        void* rp = RealOf(self);
        if (rp != nullptr && reinterpret_cast<uintptr_t>(rp) >= 0x10000) {
            uint64_t rc = *reinterpret_cast<const uint64_t*>(
                reinterpret_cast<const uint8_t*>(rp) + 8);
            char rb[96];
            snprintf(rb, sizeof(rb), "slot3 real[1] (refcount)=%llu",
                     static_cast<unsigned long long>(rc));
            HookLog(rb);
        }
    }
    // a3 = out (context): dumps the map (the crash is the hash-lookup at ctx+0x188)
    uint64_t ctxp = reinterpret_cast<uint64_t>(a3);
    DumpCtxField(ctxp, 0x178, "a3");
    DumpCtxField(ctxp, 0x188, "a3");
    DumpCtxField(ctxp, 0x1a0, "a3");
    // dumps the map table (16 bytes/entry) and the sentinel
    if (ctxp >= 0x10000 && ctxp + 0x200 < 0x7fffffffffffULL) {
        uint64_t table = 0, sent = 0;
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery(reinterpret_cast<LPCVOID>(ctxp), &mbi, sizeof(mbi)) != 0 &&
            mbi.State == MEM_COMMIT) {
            table = *reinterpret_cast<uint64_t*>(ctxp + 0x188);
            sent = *reinterpret_cast<uint64_t*>(ctxp + 0x178);
            char tb[512];
            int to = 0;
            to += snprintf(tb + to, sizeof(tb) - to, "slot3 map: sent=%llX table=%llX",
                           static_cast<unsigned long long>(sent),
                           static_cast<unsigned long long>(table));
            if (table >= 0x10000 && table + 0x80 < 0x7fffffffffffULL) {
                MEMORY_BASIC_INFORMATION mbi2;
                if (VirtualQuery(reinterpret_cast<LPCVOID>(table), &mbi2, sizeof(mbi2)) != 0 &&
                    mbi2.State == MEM_COMMIT) {
                    auto* tq = reinterpret_cast<uint64_t*>(table);
                    for (int i = 0; i < 8; ++i) {
                        if (to < static_cast<int>(sizeof(tb)) - 24)
                            to += snprintf(tb + to, sizeof(tb) - to, " [%d]=%llX", i,
                                           static_cast<unsigned long long>(tq[i]));
                    }
                } else {
                    if (to < static_cast<int>(sizeof(tb)) - 24)
                        to += snprintf(tb + to, sizeof(tb) - to, " (table unreadable)");
                }
            }
            HookLog(tb);
        }
    }
    return hr;
}
#endif  // !HARDENED (slot3 diagnostics)

struct WrapperTables {
    void** xstoreVt;    // 60 slots
    void** xpackageVt;  // 44 slots
};
WrapperTables g_wrapperTables = {nullptr, nullptr};

// XStore slot 80 (0x74C0): *arg3 = 0, returns S_OK (mirror of the original's
// `33 C0 4D 85 C0 74 03 41 89 00 C3` - writes 0 into the 3rd arg).
int32_t WINAPI XStoreWriteZeroTail(void*, void*, void* arg3) {
    if (arg3 != nullptr) *reinterpret_cast<uint32_t*>(arg3) = 0;
    return 0;
}
// XStore slot 81 (0x74D0): always 0x89245302 (mirror of `B8 02 53 24 89 C3`)
int32_t WINAPI XStoreErrXboxTail(void*) { return kErrXbox; }

// Builds the custom XStore vtable (84 slots - live dump of the ORIGINAL:
// vtable rva 0x30658, slots 0-83, NULL at 84) and saves the real slots.
// Called ONCE (the first time a real XStore object shows up).
// IMPORTANT (2026-08-14): the ORIGINAL vtable has 84 slots, ours had 60. On
// the "anonymous" path the game calls slots 60-83 (69/70 = license
// RetTrue/RetFalse) and with 60 slots it read NULL past the allocation
// -> CFG crash 7DF51FDF0000 with rcx=wrapper (REGX confirmed).
constexpr uint32_t kXStoreVtSlots = 84;
bool BuildXStoreWrapper(void** realVt) {
    if (g_wrapperTables.xstoreVt != nullptr) return true;
    if (!EnsureFwdPage()) return false;
    uint8_t* p = g_fwdPage + g_fwdUsed;
    g_wrapperTables.xstoreVt = static_cast<void**>(VirtualAlloc(
        nullptr, (kXStoreVtSlots + 1) * sizeof(void*), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (g_wrapperTables.xstoreVt == nullptr) return false;

    if (realVt != nullptr) {
        g_xstore_orig_slot19 = reinterpret_cast<Slot3Fn>(realVt[19]);
        g_xstore_orig_slot21 = reinterpret_cast<Slot3Fn>(realVt[21]);
        g_xstore_orig_slot23 = reinterpret_cast<Slot3Fn>(realVt[23]);
#if !defined(HARDENED)
        g_xstore_orig_slot3 = reinterpret_cast<Slot3Fn>(realVt[3]);
#endif
        g_xstore_orig_slot20 = reinterpret_cast<XStoreSlot20Fn>(realVt[20]);
        g_xstore_orig_slot26 = reinterpret_cast<XStoreSlot20Fn>(realVt[26]);
        g_xstore_orig_slot29 = reinterpret_cast<XStoreSlot29Fn>(realVt[29]);
    }

    // diagnostic BYPASS (dev only): with the NTHUNK flag (dev folder,
    // COELHOFZ_DEV_DIR or %TEMP%), the wrapper keeps ONLY forwarders.
#if !defined(HARDENED)
    const bool noThunks = devflag::Exists("NTHUNK");
#else
    const bool noThunks = false;
#endif
    for (uint32_t i = 0; i < kXStoreVtSlots; ++i) {
        void* t;
        if (noThunks) {
            t = reinterpret_cast<void*>(p);
            p = EmitForwarder(p, i);
        } else {
        switch (i) {
            // Custom slots (mirror of the ORIGINAL vtable 0x30658, 84 slots):
            //   1/2 = AddRef/Release OWNED (self refcount)
            //   8/10 = 0x1337 mask, 15 = enumerate, 16 = RetFalse,
            //   19/23 = skip if 0x1337, 20/26 = iterates listA (fwd fallback),
            //   21 = conditional mask, 22 = RetTrue, 25/27 = ownedset "0010",
            //   29 = fwd real + struct, 31 = count, 32 = array,
            //   69 = RetTrue, 70 = RetFalse (license answers of the anonymous
            //   path), 80 = *arg3=0, 81 = kErrXbox. Rest = FORWARDERS.
            case 1:  t = reinterpret_cast<void*>(&Thunk_AddRef); break;
            case 2:  t = reinterpret_cast<void*>(&Thunk_Release); break;
            case 8:  t = reinterpret_cast<void*>(&XStoreMaskSlot8); break;
            case 15: t = reinterpret_cast<void*>(&XStoreEnumerateSlot15); break;
            case 16: t = reinterpret_cast<void*>(&Thunk_RetFalse); break;
            case 19: t = reinterpret_cast<void*>(&XStoreSkipIf1337_19); break;
            case 20: t = reinterpret_cast<void*>(&XStoreIterSlot20); break;
            case 21: t = reinterpret_cast<void*>(&XStoreMaskSlot21); break;
            case 22: t = reinterpret_cast<void*>(&Thunk_RetTrue); break;
            case 23: t = reinterpret_cast<void*>(&XStoreSkipIf1337_23); break;
            case 25: t = reinterpret_cast<void*>(&XStoreOwnedSet); break;
            case 26: t = reinterpret_cast<void*>(&XStoreIterSlot26); break;
            case 27: t = reinterpret_cast<void*>(&XStoreOwnedSet); break;
            case 29: t = reinterpret_cast<void*>(&XStoreStructSlot29); break;
            case 31: t = reinterpret_cast<void*>(&XStoreCountSlot31); break;
            case 32: t = reinterpret_cast<void*>(&XStoreArraySlot32); break;
            // 60-68, 71-79, 82-83 = forwarders in the ORIGINAL (default below)
            case 69: t = reinterpret_cast<void*>(&Thunk_RetTrue); break;
            case 70: t = reinterpret_cast<void*>(&Thunk_RetFalse); break;
            case 80: t = reinterpret_cast<void*>(&XStoreWriteZeroTail); break;
            case 81: t = reinterpret_cast<void*>(&XStoreErrXboxTail); break;
            default:
                t = reinterpret_cast<void*>(p);
                p = EmitForwarder(p, i);
                break;
        }
        }
        g_wrapperTables.xstoreVt[i] = t;
    }
    g_wrapperTables.xstoreVt[kXStoreVtSlots] = nullptr;  // sentinel (like the original)
    g_fwdUsed = static_cast<uint32_t>(p - g_fwdPage);
    return true;
}

// Builds the custom XPackage vtable (44 slots) and saves the real slot 11.
bool BuildXPackageWrapper(void** realVt) {
    if (g_wrapperTables.xpackageVt != nullptr) return true;
    if (!EnsureFwdPage()) return false;
    uint8_t* p = g_fwdPage + g_fwdUsed;
    g_wrapperTables.xpackageVt = static_cast<void**>(VirtualAlloc(
        nullptr, 45 * sizeof(void*), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (g_wrapperTables.xpackageVt == nullptr) return false;

    if (realVt != nullptr)
        g_xpackage_orig_slot11 = reinterpret_cast<Slot3Fn>(realVt[11]);

    for (uint32_t i = 0; i < 44; ++i) {
        void* t;
        // PROVEN SET (runs 1-11): 4 (RetFalse) and 11 (GetProductId ->
        // fwd real). 1/2 (AddRef/Release) = OWNED (self refcount). The rest
        // are FORWARDERS (the ORIGINAL vtable has 44 slots - rva 0x30418 -
        // and the remaining slots 5-43 are custom/forwarders of the stub.
        // Forwarders to the real one preserve the behavior in both).
        switch (i) {
            case 1:  t = reinterpret_cast<void*>(&Thunk_AddRef); break;
            case 2:  t = reinterpret_cast<void*>(&Thunk_Release); break;
            case 4:  t = reinterpret_cast<void*>(&Thunk_RetFalse); break;
            case 11: t = reinterpret_cast<void*>(&Thunk_GetProductId); break;
            default:
                t = reinterpret_cast<void*>(p);
                p = EmitForwarder(p, i);
                break;
        }
        g_wrapperTables.xpackageVt[i] = t;
    }
    g_fwdUsed = static_cast<uint32_t>(p - g_fwdPage);
    return true;
}

// Creates the wrapper: [0x00]=vtable, [0x08]=self refcount (AddRef/Release)
// and [0x18]=REAL object (used by the forwarders). The real object is NEVER
// released by the game (Release never reaches 0).
//
// Mirrors the [0x08..0x58] fields of the REAL object into the wrapper
// (HYPOTHESIS: the game reads fields of the object it holds - the wrapper -
// beyond the vtable. Zeroed fields gave a state different from the real one
// and the game fell into the "anonymous" path. The ORIGINAL's wrapper has
// data at [0x40..0x58] - here we copy it from the real one).
void* CreateWrapper(void** vt, void* real) {
    // ORIGINAL wrapper layout (handler 0x7AA0 + live dump 2026-08-14):
    //   [0x00] = vtable
    //   [0x08] = singleton (paths buffer)
    //   [0x10] = config (ProductId at [0x18], listA at [0x20]/[0x28], SKU at
    //            [0x38]) - the custom slots 20/26/29/31/32 read self[0x10]
    //   [0x18] = REAL object (used by the forwarders)
    // PER-QUERY (1 wrapper per query, no cache) like the era that worked.
    // AddRef/Release = thunks with self refcount (constant return - the real
    // object is NEVER released by the game [Release use-after-free]).
    auto* w = static_cast<void**>(
        HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 0x60));
    if (w == nullptr) return nullptr;
    w[0] = vt;                  // wrapper vtable
    // builds the config + singleton in the ORIGINAL's layout (handler 0x7AA0):
    //   wrapper[0x08] = singleton (wide path buffer)
    //   wrapper[0x10] = singleton[0x18] (config)
    //   wrapper[0x18] = real
    // The game reads wrapper[0x08] and wrapper[0x10] on the "anonymous" path
    // (the crash stack shows the wrapper + the "anonymous" string). With NULL
    // the game gets garbage and crashes in the license map hash-lookup.
    NativeSingleton* sing = EnsureSingleton();
    if (sing != nullptr) {
        w[1] = sing;            // [0x08] = singleton
        w[2] = sing->config;    // [0x10] = singleton[0x18] = config
    }
    // [0x18] = real. x64: XORed with the per-process key (the forwarder
    // decodes via xor-immediate). ARM64: plaintext (the emitted forwarder does
    // not decode an immediate, see EmitForwarder).
#if defined(__x86_64__) || defined(_M_X64)
    w[3] = reinterpret_cast<void*>(
        reinterpret_cast<uintptr_t>(real) ^ RealKey64());
#else
    w[3] = real;
#endif
    return w;
}

// ============================================================================
// Hook handler
// ============================================================================

// diagnostics: logs the FIRST occurrence of each unique iid + every 100
// calls (to map WHICH interface the game uses for the license check without
// losing rare interfaces between throttle windows)
#if !defined(HARDENED)
static unsigned g_iidCalls = 0;
static uint64_t g_seenIids[64];  // FNV-1a 64 hash of 64 unique iids
static unsigned g_nSeenIids = 0;
static bool IsNewIid(const Guid128* iid) {
    if (iid == nullptr) return false;
    const auto* g = reinterpret_cast<const uint8_t*>(iid);
    uint64_t h = 0xcbf29ce484222325ULL;
    for (int i = 0; i < 16; ++i) {
        h ^= g[i];
        h *= 0x100000001b3ULL;
    }
    for (unsigned i = 0; i < g_nSeenIids; ++i) {
        if (g_seenIids[i] == h) return false;
    }
    if (g_nSeenIids < 64) g_seenIids[g_nSeenIids++] = h;
    return true;
}
static void LogIid(const Guid128* iid, int32_t hr, void* obj, const char* tag) {
    ++g_iidCalls;
    const bool first = IsNewIid(iid);
    if (!first && g_iidCalls % 100 != 0) return;
    char b[256];
    if (iid != nullptr) {
        const auto* g = reinterpret_cast<const uint8_t*>(iid);
        void** vt = obj != nullptr ? *reinterpret_cast<void***>(obj) : nullptr;
        snprintf(b, sizeof(b),
                 "hook: %s%s iid=%02X%02X%02X%02X-%02X%02X-%02X%02X-"
                 "%02X%02X-%02X%02X%02X%02X%02X%02X hr=%08X obj=%p vt0=%p (x%u)",
                 tag, first ? " [NOVO]" : "", g[0], g[1], g[2], g[3], g[4],
                 g[5], g[6], g[7], g[8], g[9], g[10], g[11], g[12], g[13],
                 g[14], g[15], static_cast<uint32_t>(hr), obj,
                 vt != nullptr ? vt[0] : nullptr, g_iidCalls);
    } else {
        snprintf(b, sizeof(b), "hook: %s iid=NULL hr=%08X obj=%p (x%u)",
                 tag, static_cast<uint32_t>(hr), obj, g_iidCalls);
    }
    HookLog(b);
}
#endif  // !HARDENED (iid diagnostics)

// ---- wrapperCache (mirror of the original 0x36d28): 1 wrapper PER REAL OBJECT ----
// The game queries XStore/XPackage twice with the SAME real object (the log
// shows 2 queries of the same pointer). The original returns the SAME wrapper
// (cache). Without the cache, the game gets 2 DIFFERENT wrappers and the
// internal state (config, refcount) becomes inconsistent -> the license map
// "anonymous" hash-lookup reads garbage (crash 7DF51FDF0000 right after the
// 2nd wrap).
struct WrapperCacheEntry {
    void* real;      // real object (key)
    void* wrapper;   // returned wrapper
};
static WrapperCacheEntry g_wrapperCache[16];
static int g_wrapperCacheN = 0;

static void* CachedOrCreateWrapper(void** vt, void* real) {
    for (int i = 0; i < g_wrapperCacheN; ++i) {
        if (g_wrapperCache[i].real == real)
            return g_wrapperCache[i].wrapper;
    }
    void* w = CreateWrapper(vt, real);
    if (w != nullptr && g_wrapperCacheN < 16) {
        g_wrapperCache[g_wrapperCacheN].real = real;
        g_wrapperCache[g_wrapperCacheN].wrapper = w;
        ++g_wrapperCacheN;
    }
    return w;
}

int32_t WINAPI QueryApiImplHook(const Guid128* iid, void* arg2, void** ppv) {
    // 0) Kill-switch (hardening): if set by the stub watchdog (tamper on
    // winmm), the hook becomes passthrough - it does not lie "owned".
    if (g_hookKillFlag != nullptr && *g_hookKillFlag != 0)
        return g_origQueryApiImpl(iid, arg2, ppv);
    // 1) Calls the original first (the real result decides the rest).
    const int32_t hr = g_origQueryApiImpl(iid, arg2, ppv);
#if !defined(HARDENED)
    LogIid(iid, hr, hr == 0 && ppv != nullptr ? *ppv : nullptr, "QueryApiImpl");
#endif
    if (hr != 0 || ppv == nullptr || *ppv == nullptr) return hr;
    if (OpaqueAlwaysFalse()) return hr;  // opaque predicate (never branches)

#if !defined(HARDENED)
    // diagnostic BYPASS (dev only): with the NWRAP flag (dev folder,
    // COELHOFZ_DEV_DIR or %TEMP%), the hook runs BUT does not wrap (it
    // returns the real object).
    if (devflag::Exists("NWRAP")) {
        return hr;
    }
#endif

    // 2) If the game asked for XPackage/XStore, returns a WRAPPER (real
    //    object at [0x18] with the original vtable intact. The game calls the
    //    wrapper vtable: license slots = "owned" thunks, the rest = forwarders
    //    to the real one).
    //    CACHE of 1 wrapper per interface (like the ORIGINAL's wrapperCache -
    //    live dump 0x36d28): the game queries XStore twice and gets the SAME
    //    wrapper. AddRef/Release of slots 1/2 = FORWARDERS to the real one
    //    (like the original) - that is why we ANCHOR the real object with an
    //    AddRef on the 1st query: the game makes balanced AddRef/Release
    //    pairs on the real object, which NEVER reaches 0 (use-after-free
    //    confirmed without the anchor: lastSlot=2 -> refcount hit zero ->
    //    "anonymous" hash-lookup on freed memory).
    if (iid != nullptr && *iid == kIidXPackage) {
        void* real = *ppv;
        void** rvt = *reinterpret_cast<void***>(real);
        if (BuildXPackageWrapper(rvt) && g_wrapperTables.xpackageVt != nullptr) {
            void* cached = CachedOrCreateWrapper(g_wrapperTables.xpackageVt, real);
            if (cached != nullptr) *ppv = cached;
            DLOG("hook: XPackage WRAPPED (active license) w=%p real=%p cacheN=%d",
                 *ppv, real, g_wrapperCacheN);
        } else {
            HOOK_LOG("hook: XPackage NOT wrapped (alloc/build failed)");
        }
    } else if (iid != nullptr && *iid == kIidXStore) {
        void* real = *ppv;
        void** rvt = *reinterpret_cast<void***>(real);
        if (BuildXStoreWrapper(rvt) && g_wrapperTables.xstoreVt != nullptr) {
            void* cached = CachedOrCreateWrapper(g_wrapperTables.xstoreVt, real);
            if (cached != nullptr) *ppv = cached;
            DLOG("hook: XStore WRAPPED (active license) w=%p real=%p cacheN=%d",
                 *ppv, real, g_wrapperCacheN);
        } else {
            HOOK_LOG("hook: XStore NOT wrapped (alloc/build failed)");
        }
    }
    return hr;
}

// verbose=false (retry mode): logs only on the 1st attempt and every 250
// (throttle) - it avoids unbounded log growth if xgameruntime never loads or
// the prologue never matches. The SUCCESS log always goes out (it only
// happens once).
bool InstallQueryApiImplHookInternal(bool verbose) {
    HMODULE mod = GetModuleHandleA(
        enc::dec(enc::kXgameruntime, enc::kXgameruntimeLen, 0x5A));
    if (mod == nullptr) {
        if (verbose)
            HOOK_LOG("install: xgameruntime not loaded yet (waiting)");
        return false;
    }
    if (verbose)
        DLOG("install: xgameruntime em 0x%p", reinterpret_cast<void*>(mod));

    // By name first, fallback to ordinal 5 (QueryApiImpl is export index 4,
    // base 1 - confirmed via objdump of the real binary).
    auto* proc = reinterpret_cast<uint8_t*>(reinterpret_cast<uintptr_t>(
        GetProcAddress(mod, enc::dec(enc::kQueryApiImpl, enc::kQueryApiImplLen, 0x5A))));
    if (proc == nullptr) {
        if (verbose)
            HOOK_LOG("install: name 'QueryApiImpl' not found; trying ordinal 5");
        proc = reinterpret_cast<uint8_t*>(
            reinterpret_cast<uintptr_t>(GetProcAddress(mod,
                                                       reinterpret_cast<LPCSTR>(5))));
    }
    if (proc == nullptr) {
        if (verbose) HOOK_LOG("install: GetProcAddress failed (name + ordinal 5)");
        return false;
    }
    if (verbose)
        DLOG("install: QueryApiImpl em 0x%p", reinterpret_cast<void*>(proc));

#if defined(__x86_64__) || defined(_M_X64)
    if (std::memcmp(proc, kQueryApiPrologue, 5) != 0) {
        if (verbose)
            DLOG("install: prologue does NOT match: %02X %02X %02X %02X %02X",
                 proc[0], proc[1], proc[2], proc[3], proc[4]);
        return false;
    }
#elif defined(__aarch64__) || defined(_M_ARM64)
    // ARM64: real binary dump still pending. Heuristic v1: word 0 must be a
    // classic frame-setup (top byte A9=STP signed X-pair, AD=STP Q-pair,
    // D1=SUB-SP imm). We copy up to 8 words while the sequence keeps being
    // frame-setup. Every read goes to the log (DLOG) - when the first tester
    // runs the dev release, we calibrate an exact constant array in place of
    // the heuristic.
    {
        auto w_at = [&](uint32_t i) {
            uint32_t w;
            std::memcpy(&w, proc + i * 4, 4);
            return w;
        };        auto IsFrameSetup = [](uint32_t w) {            const uint8_t top = static_cast<uint8_t>(w >> 24);
            return top == 0xA9 || top == 0xAD || top == 0xD1;
        };
        if (!IsFrameSetup(w_at(0))) {
            if (verbose)
                DLOG("install: arm64 prologue NOT recognized (w0=%08X)",
                     w_at(0));
            return false;
        }
        g_trampWords = 0;
        while (g_trampWords < 8 && IsFrameSetup(w_at(g_trampWords))) {
            std::memcpy(g_prologueBytes + g_trampWords * 4,
                        proc + g_trampWords * 4, 4);
            ++g_trampWords;
        }
        if (verbose) {
            DLOG("install: prologue arm64 (%u words):",
                 static_cast<unsigned>(g_trampWords));
            for (uint32_t i = 0; i < g_trampWords; ++i) {
                DLOG("install:   [%u]=%08X", static_cast<unsigned>(i),
                     w_at(i));
            }
        }
    }
#endif
    if (verbose) HOOK_LOG("install: prologue OK, applying patch...");
    // The relay page is allocated NEAR xgameruntime (E9 rel32 range).
    if (!InstallPatch(proc, reinterpret_cast<void*>(&QueryApiImplHook),
                      reinterpret_cast<uint8_t*>(mod))) {
        if (verbose) HOOK_LOG("install: InstallPatch FAILED");
        return false;
    }
    g_origQueryApiImpl = reinterpret_cast<QueryApiImplFn>(g_relayPage + 0x20);
    HOOK_LOG("install: HOOK INSTALLED");
    return true;
}

// If xgameruntime is not loaded yet (late load), retries in the background
// UNTIL it succeeds (the poll is cheap: Sleep 200ms + GetModuleHandle, which
// does not take the loader lock - safe inside DllMain). It dies with the
// process. Throttled log: 1st attempt + every 250 (~50s) - the log only
// grows on transitions, never in a loop.
DWORD WINAPI RetryThreadMain(void*) {
    uint32_t loops = 0;      // poll iterations (200ms)
    uint32_t installs = 0;   // REAL install attempts (module present)
    bool loadMissLogged = false;
    while (g_origQueryApiImpl == nullptr) {
        Sleep(200);
        ++loops;
        // FORCES the xgameruntime load (the game only loads it late): this
        // way the hook gets in BEFORE the game obtains the GDK interfaces (if
        // we wait for the natural load, the game has already called
        // QueryApiImpl and taken the real objects before our hook).
        // LoadLibraryW returns fast on failure (module still unavailable) -
        // the game also loads it on its own, and the loop catches it either
        // way.
        if (LoadLibraryA(enc::dec(enc::kXgameruntime, enc::kXgameruntimeLen, 0x5A)) == nullptr) {
            if (!loadMissLogged) {
                loadMissLogged = true;
                HOOK_LOG("install: LoadLibraryW(xgameruntime) not available yet");
            }
            continue;
        }
        // the install counter only goes up with the module PRESENT: installs==1 =
        // first real attempt, always logs verbose (diagnostics).
        ++installs;
        InstallQueryApiImplHookInternal(installs == 1 || installs % 250 == 0);
    }
    return 0;
}

}  // namespace

// ============================================================================
// Public API
// ============================================================================

// Watchdog kill-switch (hardening) - outside the anonymous namespace so
// dllmain can call it with -fvisibility=hidden.
volatile LONG* g_hookKillFlag = nullptr;
void SetHookKillFlag(volatile LONG* flag) { g_hookKillFlag = flag; }

bool InstallCrashHandler() {
#if defined(HARDENED)
    return true;  // no VEH under harden (it logs nothing)
#else
    static bool done = false;
    if (done) return true;
    AddVectoredExceptionHandler(1, &CrashVeh);
    done = true;
    return true;
#endif
}

bool InstallQueryApiImplHook() {
    HOOK_LOG("install: InstallQueryApiImplHook() called");
    if (g_origQueryApiImpl != nullptr) return true;  // already installed
    if (InstallQueryApiImplHookInternal(true)) return true;

    // xgameruntime not loaded yet: schedules the background retry
    // (persists until it installs or the process dies).
    HANDLE t = CreateThread(nullptr, 0, &RetryThreadMain, nullptr, 0, nullptr);
    if (t != nullptr) CloseHandle(t);
    return false;
}

void SetUnlockProductId(const char* pid) {
    if (pid != nullptr && pid[0] != '\0') {
        std::strncpy(g_productId, pid, sizeof(g_productId) - 1);
        g_productId[sizeof(g_productId) - 1] = '\0';
    } else {
        // encrypted fallback (the plaintext "9NBLGGH2JHXJ" does not exist in the binary)
        std::strncpy(g_productId,
                     enc::dec(enc::kProdIdDef, enc::kProdIdDefLen, 0x5A),
                     sizeof(g_productId) - 1);
        g_productId[sizeof(g_productId) - 1] = '\0';
    }
}
