# Copyright (C) 2026 CoelhoFZ
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

"""gen_winmm_stubs.py - generates the winmm proxy forwarding stubs.

Reads reconstructed/winmm_exports.txt (real winmm.dll exports from the
owner's PC, extracted with a PE parser - format 'ORDINAL<TAB>name') and
generates 4 artifacts in proxy/:

  winmm_stubs.h   - decl of ResolveAllWinmmStubs (the only one used by dllmain)
  winmm_stubs.S   - trampolines in PURE ASSEMBLY + global pointers
  winmm_stubs.cpp - resolvers (GetProcAddress) + ResolveAllWinmmStubs
  winmm.def       - export list with ordinals for the linker (LIBRARY winmm)

WHY ASSEMBLY (and not C naked):
  1. windows.h/mmsystem.h ALREADY declare all 180 exports with real
     signatures (e.g. `LRESULT WINAPI CloseDriver(HDRVR, LPARAM, LPARAM)`).
     Our `void CloseDriver(void)` would clash -> compile error.
  2. Under `__attribute__((naked))` GCC does NOT accept the "m"/"r"
     constraints (materializing the address would generate code, which is
     forbidden in naked).
  The .S avoids both: no C declaration, and the `jmp *g_real_<name>(%rip)`
  references the global pointer directly.

How the trampoline preserves the arguments:
- x64: all args go in RCX/RDX/R8/R9 + stack (shadow space). A
  `jmp *g_real_%rip` touches neither registers nor stack.
- ARM64 (Windows on ARM): args in X0-X7 + stack. The veneer loads the
  pointer into IP0/IP1 (X16/X17 - ABI scratch, clobberable by the caller)
  and does `br` - a tail-branch that also preserves everything.
ONE format forwards ANY winmm signature (waveOut*, mci*, time*, mixer*...)
on both architectures.

Usage: python3 proxy/gen_winmm_stubs.py
"""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent          # .../unlocker-CoelhoFZ/proxy
RECON = (ROOT.parent / "reconstructed" / "winmm_exports.txt")
DEF_FILE = (ROOT / "winmm.def")


def load_names() -> list[tuple[int, str]]:
    """Loads (ordinal, name).

    Preferred source: reconstructed/winmm_exports.txt ('ORDINAL<TAB>name'),
    extracted from the real winmm of the owner's PC. Fallback (VPS without
    the dump): parses the ALREADY GENERATED proxy/winmm.def - the same
    name@ordinal list that produced the current artifacts, so the round-trip
    is stable."""
    items: list[tuple[int, str]]
    if RECON.exists():
        items = _load_recon()
    elif DEF_FILE.exists():
        print("warning: winmm_exports.txt missing - using fallback winmm.def")
        items = _load_def()
    else:
        raise SystemExit(
            f"neither {RECON} nor {DEF_FILE} exists - run it first on a machine with the dump"
        )
    # Dedup by name (same guarantee as the original format).
    seen: set[str] = set()
    out: list[tuple[int, str]] = []
    for ordinal, n in items:
        if n not in seen:
            seen.add(n)
            out.append((ordinal, n))
    return out


def _load_recon() -> list[tuple[int, str]]:
    items: list[tuple[int, str]] = []
    for raw in RECON.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit():
            ordinal, name = int(parts[0]), parts[1]
        else:
            name = parts[-1]
            ordinal = 0
        if not name.replace("_", "a").isalnum() or name[0].isdigit():
            raise SystemExit(f"invalid name in winmm_exports.txt: {name!r}")
        items.append((ordinal, name))
    return items


def _load_def() -> list[tuple[int, str]]:
    items: list[tuple[int, str]] = []
    for raw in DEF_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.upper().startswith("LIBRARY") \
                or line.upper().startswith("EXPORTS"):
            continue
        parts = line.split()
        if not parts:
            continue
        if len(parts) >= 3 and parts[1].startswith("@"):
            ordinal, name = int(parts[1][1:]), parts[0]
        else:
            name, ordinal = parts[0], 0
        if not name.replace("_", "a").isalnum() or name[0].isdigit():
            raise SystemExit(f"invalid name in winmm.def: {name!r}")
        items.append((ordinal, name))
    return items


# Copyright notice emitted by every generator call, identical to the header
# the published files carry (full text of the license in ../LICENSE).
COPYRIGHT = [
    "// Copyright (C) 2026 CoelhoFZ",
    "// SPDX-License-Identifier: GPL-3.0-only",
    "// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).",
    "",
]
COPYRIGHT_SEMI = [
    "; Copyright (C) 2026 CoelhoFZ",
    "; SPDX-License-Identifier: GPL-3.0-only",
    "; This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).",
    "",
]


def gen_header(names: list[tuple[int, str]]) -> str:
    return (
        "\n".join(COPYRIGHT) + "\n"
        "#pragma once\n"
        "// Generated by gen_winmm_stubs.py - DO NOT edit manually.\n"
        "// Only symbol dllmain.cpp needs: the exports resolver.\n"
        "// (the trampolines live in winmm_stubs.S, with no C declarations so\n"
        "// they don't clash with the real mmsystem.h signatures)\n"
        "#include <windows.h>\n"
        "\n"
        "// Resolves every export against the real winmm (System32).\n"
        "// Returns false if any GetProcAddress fails.\n"
        "bool ResolveAllWinmmStubs(HMODULE realWinmm);\n"
        "\n"
    )


def gen_asm(names: list[tuple[int, str]]) -> str:
    """Pure assembly: 1 trampoline per export (dual-arch via the preprocessor)
    and the global pointers g_real_<name> in .data.

    TOOLCHAIN NOTES:
    - g++ compiles .S (uppercase) THROUGH the C preprocessor; `#` comments
      would become "invalid preprocessing directive" -> use `//` or `/* */`.
    - Do NOT use `.section .note.GNU-stack` (ELF-only; invalid in PE/COFF).
    - standalone asm uses plain `%rip` (no `%%`).
    - Dual-arch: #if defined(__aarch64__) selects the AArch64 veneer;
      otherwise (x86-64) uses a RIP-relative indirect jmp."""
    out = COPYRIGHT + [
        "// Generated by gen_winmm_stubs.py - DO NOT edit manually.",
        "// Forwarding trampolines to the real winmm + global pointers.",
        "// The tail-branch touches no ARGUMENT registers and no stack ->",
        "// it preserves any winmm signature on both architectures.",
        "// `//` comments (not `#`): the .S goes through the C preprocessor.",
        "",
        "    .data",
    ]
    for _, n in names:
        out += [
            f"    .globl g_real_{n}",
            "    .p2align 3",
            f"g_real_{n}:",
            "    .quad 0",
        ]
    out += [
        "",
        "    .text",
    ]
    for _, n in names:
        out += [
            "#if defined(__aarch64__)",
            f"    .globl {n}",
            "    .p2align 2",
            f"{n}:",
            f"    adrp x16, g_real_{n}",
            f"    ldr  x17, [x16, :lo12:g_real_{n}]",
            "    br   x17",
            "#elif defined(__x86_64__)",
            f"    .globl {n}",
            f"{n}:",
            f"    jmp *g_real_{n}(%rip)",
            "#else",
            f"#error \"winmm_stubs.S: unsupported architecture\"",
            "#endif",
        ]
    out += [""]
    return "\n".join(out)


def gen_cpp(names: list[tuple[int, str]]) -> str:
    out = COPYRIGHT + [
        "// Generated by gen_winmm_stubs.py - DO NOT edit manually.",
        "// Resolvers: point each g_real_<name> (defined in the .S) to the",
        "// matching export of the real winmm via GetProcAddress.",
        "#include \"winmm_stubs.h\"",
        "",
        "// Pointers defined in winmm_stubs.S (globals, link-time).",
        "extern \"C\" {",
    ]
    for _, n in names:
        out.append(f"    extern void* g_real_{n};")
    out += [
        "}",
        "",
        "#define DEFINE_RESOLVER(name)                                                \\",
        "  static bool Resolve_##name(HMODULE m) {                                    \\",
        "    g_real_##name = reinterpret_cast<void*>(GetProcAddress(m, #name));       \\",
        "    return g_real_##name != nullptr;                                         \\",
        "  }",
        "",
    ]
    for _, n in names:
        out.append(f"DEFINE_RESOLVER({n})")
    out += [
        "",
        "#undef DEFINE_RESOLVER",
        "",
        "bool ResolveAllWinmmStubs(HMODULE realWinmm) {",
        "    if (realWinmm == nullptr) return false;",
        "    bool allOk = true;",
    ]
    for _, n in names:
        out.append(f"    allOk = Resolve_{n}(realWinmm) && allOk;")
    out += [
        "    return allOk;",
        "}",
        "",
    ]
    return "\n".join(out)


def gen_def(names: list[tuple[int, str]]) -> str:
    """Emits the .def with `Name @Ordinal` (the real winmm exports by ordinal
    with base 2; legacy games may import winmm by ordinal, so we replicate
    that)."""
    out = COPYRIGHT_SEMI + [
        "; Generated by gen_winmm_stubs.py - DO NOT edit manually.",
        "; Proxy winmm.dll exports (forwarding to the real winmm in System32).",
        "; The game imports winmm legitimately; the fake in the app directory wins",
        "; the DLL search and chains everything to the real one. Ordinals = real winmm (base 2).",
        "",
        "LIBRARY winmm",
        "EXPORTS",
    ]
    for ordinal, n in names:
        if ordinal > 0:
            out.append(f"    {n} @{ordinal}")
        else:
            out.append(f"    {n}")
    out.append("")
    return "\n".join(out)


def main() -> None:
    names = load_names()
    print(f"names: {len(names)}")
    (ROOT / "winmm_stubs.h").write_text(gen_header(names), encoding="utf-8")
    (ROOT / "winmm_stubs.S").write_text(gen_asm(names), encoding="utf-8")
    (ROOT / "winmm_stubs.cpp").write_text(gen_cpp(names), encoding="utf-8")
    (ROOT / "winmm.def").write_text(gen_def(names), encoding="utf-8")
    print("generated: winmm_stubs.h, winmm_stubs.S, winmm_stubs.cpp, winmm.def")


if __name__ == "__main__":
    main()
