#pragma once
// apihash.h - API resolution WITHOUT an import table (PEB walk + FNV-1a hash).
//
// The packer path (stub + miniloader + mapper) resolves ALL the APIs it
// needs at runtime by walking the PEB/LDR and parsing the export tables of
// kernel32.dll - with NO name in the winmm import table. Kills the vector
// "breakpoint on VirtualAlloc/ReadFile and watch the decrypted blob go by":
// winmm.dll no longer lists any of those APIs as imports.
//
// Zero imports here: only memory reads (PEB at GS:[0x60] on x64) and the
// export tables. The API names do not appear in the clear - only FNV-1a
// hashes (case-insensitive) computed at compile-time.

#include <windows.h>
#include <shellapi.h>  // ShellExecuteW (decl) - donation popup getter
#include <cstdint>

namespace apihash {

// FNV-1a 32-bit, case-insensitive (ASCII). constexpr = computed at
// compile-time for the constants; also used at runtime for the names.
constexpr uint32_t H(const char* s) {
    uint32_t h = 2166136261u;
    for (; *s; ++s) {
        char c = *s;
        if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
        h ^= static_cast<uint8_t>(c);
        h *= 16777619u;
    }
    return h;
}

// Hash of the basename of a wide path (e.g.: FullDllName from the LDR), case-insensitive.
inline uint32_t HBase(const wchar_t* path) {
    const wchar_t* last = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') last = p + 1;
    uint32_t h = 2166136261u;
    for (; *last; ++last) {
        wchar_t c = *last;
        if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
        h ^= static_cast<uint8_t>(c);
        h *= 16777619u;
    }
    return h;
}

// PEB (x64: GS:[0x60]; ARM64: TEB at TPIDR_EL0, PEB at TEB+0x60 - MS
// kept the TEB offsets identical between x64 and ARM64).
inline uintptr_t Peb() {
#if defined(__x86_64__) || defined(_M_X64)
    uintptr_t p = 0;
    __asm__ __volatile__("movq %%gs:0x60, %0" : "=r"(p));
    return p;
#elif defined(__aarch64__) || defined(_M_ARM64)
    uintptr_t teb = 0;
    __asm__ __volatile__("mrs %0, tpidr_el0" : "=r"(teb));
    if (teb == 0) return 0;
    return *reinterpret_cast<const uintptr_t*>(teb + 0x60);
#else
#error "apihash.h: unsupported architecture (Peb)"
    return 0;
#endif
}

// Minimal UNICODE_STRING (avoids winternl.h).
struct UStr {
    uint16_t Length;
    uint16_t MaxLength;
    wchar_t* Buffer;
};

// Resolves a function of a module by the HASH of the module basename and the
// HASH of the export name. Returns nullptr if not found (silent failure).
// noinline: a SINGLE copy of the PEB walk + export parse in the binary (if it
// were inline, the compiler would duplicate the loop across the 16 getters ->
// .text bloat).
#if defined(__GNUC__)
__attribute__((noinline))
#endif
inline FARPROC Resolve(uint32_t mod_hash, uint32_t fn_hash) {
    const uintptr_t peb = Peb();
    if (peb == 0) return nullptr;
    // PEB->Ldr at +0x18; LDR_DATA->InMemoryOrderModuleList at +0x20.
    const uintptr_t ldr = *reinterpret_cast<const uintptr_t*>(peb + 0x18);
    if (ldr == 0) return nullptr;
    const LIST_ENTRY* head = reinterpret_cast<const LIST_ENTRY*>(ldr + 0x20);
    for (const LIST_ENTRY* e = head->Flink; e != head; e = e->Flink) {
        // InMemoryOrderLinks -> LDR_DATA_TABLE_ENTRY (back up 0x10).
        const uintptr_t entry = reinterpret_cast<uintptr_t>(e) - 0x10;
        const uintptr_t dll_base = *reinterpret_cast<const uintptr_t*>(entry + 0x30);
        if (dll_base == 0) continue;
        const UStr* name = reinterpret_cast<const UStr*>(entry + 0x48);  // FullDllName
        if (name->Buffer == nullptr || name->Length == 0) continue;
        if (HBase(name->Buffer) != mod_hash) continue;

        // Right module: parse the export table.
        const IMAGE_DOS_HEADER* dos =
            reinterpret_cast<const IMAGE_DOS_HEADER*>(dll_base);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE) continue;
        const IMAGE_NT_HEADERS* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(
            dll_base + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE) continue;
        const IMAGE_DATA_DIRECTORY& dd =
            nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
        if (dd.VirtualAddress == 0 || dd.Size == 0) continue;
        const uint8_t* base = reinterpret_cast<const uint8_t*>(dll_base);
        const IMAGE_EXPORT_DIRECTORY* ed =
            reinterpret_cast<const IMAGE_EXPORT_DIRECTORY*>(base + dd.VirtualAddress);
        const uint32_t n = ed->NumberOfNames;
        for (uint32_t i = 0; i < n; ++i) {
            const uint32_t name_rva = *reinterpret_cast<const uint32_t*>(
                base + ed->AddressOfNames + 4 * i);
            const char* fn = reinterpret_cast<const char*>(base + name_rva);
            if (H(fn) != fn_hash) continue;
            const uint16_t ord = *reinterpret_cast<const uint16_t*>(
                base + ed->AddressOfNameOrdinals + 2 * i);
            const uint32_t fn_rva = *reinterpret_cast<const uint32_t*>(
                base + ed->AddressOfFunctions + 4 * ord);
            return reinterpret_cast<FARPROC>(
                const_cast<uint8_t*>(base) + fn_rva);
        }
        break;  // module found, function not: does not try another module
    }
    return nullptr;
}

// ---- typed getters with cache (resolve once; failure = nullptr) ----
// kernel32.dll
inline decltype(&::GetModuleFileNameA) GetModuleFileNameA() {
    static auto fn = reinterpret_cast<decltype(&::GetModuleFileNameA)>(
        Resolve(H("kernel32.dll"), H("GetModuleFileNameA")));
    return fn;
}
inline decltype(&::CreateFileA) CreateFileA() {
    static auto fn = reinterpret_cast<decltype(&::CreateFileA)>(
        Resolve(H("kernel32.dll"), H("CreateFileA")));
    return fn;
}
inline decltype(&::GetFileSize) GetFileSize() {
    static auto fn = reinterpret_cast<decltype(&::GetFileSize)>(
        Resolve(H("kernel32.dll"), H("GetFileSize")));
    return fn;
}
inline decltype(&::SetFilePointer) SetFilePointer() {
    static auto fn = reinterpret_cast<decltype(&::SetFilePointer)>(
        Resolve(H("kernel32.dll"), H("SetFilePointer")));
    return fn;
}
inline decltype(&::ReadFile) ReadFile() {
    static auto fn = reinterpret_cast<decltype(&::ReadFile)>(
        Resolve(H("kernel32.dll"), H("ReadFile")));
    return fn;
}
inline decltype(&::CloseHandle) CloseHandle() {
    static auto fn = reinterpret_cast<decltype(&::CloseHandle)>(
        Resolve(H("kernel32.dll"), H("CloseHandle")));
    return fn;
}
inline decltype(&::VirtualAlloc) VirtualAlloc() {
    static auto fn = reinterpret_cast<decltype(&::VirtualAlloc)>(
        Resolve(H("kernel32.dll"), H("VirtualAlloc")));
    return fn;
}
inline decltype(&::VirtualFree) VirtualFree() {
    static auto fn = reinterpret_cast<decltype(&::VirtualFree)>(
        Resolve(H("kernel32.dll"), H("VirtualFree")));
    return fn;
}
inline decltype(&::VirtualProtect) VirtualProtect() {
    static auto fn = reinterpret_cast<decltype(&::VirtualProtect)>(
        Resolve(H("kernel32.dll"), H("VirtualProtect")));
    return fn;
}
inline decltype(&::FlushInstructionCache) FlushInstructionCache() {
    static auto fn = reinterpret_cast<decltype(&::FlushInstructionCache)>(
        Resolve(H("kernel32.dll"), H("FlushInstructionCache")));
    return fn;
}
inline decltype(&::GetCurrentProcess) GetCurrentProcess() {
    static auto fn = reinterpret_cast<decltype(&::GetCurrentProcess)>(
        Resolve(H("kernel32.dll"), H("GetCurrentProcess")));
    return fn;
}
inline decltype(&::IsDebuggerPresent) IsDebuggerPresent() {
    static auto fn = reinterpret_cast<decltype(&::IsDebuggerPresent)>(
        Resolve(H("kernel32.dll"), H("IsDebuggerPresent")));
    return fn;
}
inline decltype(&::CreateThread) CreateThread() {
    static auto fn = reinterpret_cast<decltype(&::CreateThread)>(
        Resolve(H("kernel32.dll"), H("CreateThread")));
    return fn;
}
inline decltype(&::Sleep) Sleep() {
    static auto fn = reinterpret_cast<decltype(&::Sleep)>(
        Resolve(H("kernel32.dll"), H("Sleep")));
    return fn;
}
inline decltype(&::GetModuleHandleA) GetModuleHandleA() {
    static auto fn = reinterpret_cast<decltype(&::GetModuleHandleA)>(
        Resolve(H("kernel32.dll"), H("GetModuleHandleA")));
    return fn;
}
inline decltype(&::LoadLibraryA) LoadLibraryA() {
    static auto fn = reinterpret_cast<decltype(&::LoadLibraryA)>(
        Resolve(H("kernel32.dll"), H("LoadLibraryA")));
    return fn;
}
inline decltype(&::GetProcAddress) GetProcAddress() {
    static auto fn = reinterpret_cast<decltype(&::GetProcAddress)>(
        Resolve(H("kernel32.dll"), H("GetProcAddress")));
    return fn;
}

// ---- donation popup getters: hide MessageBox/ShellExecute/Reg/
//      locale/keyboard from the import table (a real winmm would NEVER import
//      that; it was the biggest "tell" that the DLL does UI/URL/registry). ----
inline decltype(&::GetLocaleInfoW) GetLocaleInfoW() {
    static auto fn = reinterpret_cast<decltype(&::GetLocaleInfoW)>(
        Resolve(H("kernel32.dll"), H("GetLocaleInfoW")));
    return fn;
}
inline decltype(&::GetUserDefaultUILanguage) GetUserDefaultUILanguage() {
    static auto fn = reinterpret_cast<decltype(&::GetUserDefaultUILanguage)>(
        Resolve(H("kernel32.dll"), H("GetUserDefaultUILanguage")));
    return fn;
}
inline decltype(&::MessageBoxW) MessageBoxW() {
    static auto fn = reinterpret_cast<decltype(&::MessageBoxW)>(
        Resolve(H("user32.dll"), H("MessageBoxW")));
    return fn;
}
inline decltype(&::GetKeyboardLayout) GetKeyboardLayout() {
    static auto fn = reinterpret_cast<decltype(&::GetKeyboardLayout)>(
        Resolve(H("user32.dll"), H("GetKeyboardLayout")));
    return fn;
}
inline decltype(&::ShellExecuteW) ShellExecuteW() {
    static auto fn = reinterpret_cast<decltype(&::ShellExecuteW)>(
        Resolve(H("shell32.dll"), H("ShellExecuteW")));
    return fn;
}
inline decltype(&::RegOpenKeyExW) RegOpenKeyExW() {
    static auto fn = reinterpret_cast<decltype(&::RegOpenKeyExW)>(
        Resolve(H("advapi32.dll"), H("RegOpenKeyExW")));
    return fn;
}
inline decltype(&::RegQueryValueExW) RegQueryValueExW() {
    static auto fn = reinterpret_cast<decltype(&::RegQueryValueExW)>(
        Resolve(H("advapi32.dll"), H("RegQueryValueExW")));
    return fn;
}
inline decltype(&::RegCreateKeyExW) RegCreateKeyExW() {
    static auto fn = reinterpret_cast<decltype(&::RegCreateKeyExW)>(
        Resolve(H("advapi32.dll"), H("RegCreateKeyExW")));
    return fn;
}
inline decltype(&::RegSetValueExW) RegSetValueExW() {
    static auto fn = reinterpret_cast<decltype(&::RegSetValueExW)>(
        Resolve(H("advapi32.dll"), H("RegSetValueExW")));
    return fn;
}
inline decltype(&::RegCloseKey) RegCloseKey() {
    static auto fn = reinterpret_cast<decltype(&::RegCloseKey)>(
        Resolve(H("advapi32.dll"), H("RegCloseKey")));
    return fn;
}

}  // namespace apihash
