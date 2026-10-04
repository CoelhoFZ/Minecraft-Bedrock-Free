# unlocker-CoelhoFZ

Native C++ implementation of the Minecraft Bedrock unlock mechanism
(Windows), for x86-64 and ARM64. The game queries the license through the GDK
and the unlocker intercepts that query, answering "owned". No game file is
changed on disk.

This directory contains the SOURCE of the binary distributed by the installer of
the [CoelhoFZ/Minecraft-Bedrock-Free](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free) project.

- License: GNU General Public License v3 (GPLv3), full text in `LICENSE`
- Copyright (C) 2026 CoelhoFZ

## Requirements

- Linux (or WSL) with:
  - `g++-mingw-w64-x86-64` (x64 build)
  - `python3` (generators and packer)
- For the ARM64 build: llvm-mingw (see below)

## Build

```bash
./build.sh                  # release (dev build, full diagnostics)
./build.sh --debug          # release with -O0 -g
./build.sh --harden         # protected distribution (no log, with packer)
./build.sh --lite           # lightweight distribution (embedded config, no packer)
```

Architectures (one build can produce both):

```bash
./build.sh --arch=x64
./build.sh --arch=arm64     # requires llvm-mingw in ~/.local/opt/llvm-mingw
./build.sh --arch=both      # default
```

What comes out in `dist/`:

| Mode | Output |
|---|---|
| `--release` / `--debug` | `winmm.dll` (proxy) + `XGameCore.GDK.dll` (shim) + `unlock-CoelhoFZ.ini` |
| `--harden` | only `winmm.dll` (the payload and the mapper are encrypted inside it) |
| `--lite` | `winmm.dll` + `XGameCore.GDK.dll` (no INI on disk) |

How `--harden` works (2-stage packer): the shim becomes the encrypted BLOB2,
the mapper becomes the encrypted BLOB1 (ChaCha20 with a per-build key) and
both are appended as an overlay at the end of `winmm.dll`. The stub self-CRC
uses a 2-pass build: it computes the CRC of `.text`, writes the constant and
recompiles, with `.text` identical in both passes (the build verifies that
equality).

## Tests

INI parser (runs natively, no Windows needed):

```bash
g++ -std=c++17 -Icommon tests/ini_test.cpp common/simple_ini.cpp -o ini_test
./ini_test
```

`build.sh` also runs `tools/check_exports.py`, which compares the proxy
exports with the real system winmm when the
`reconstructed/winmm_exports.txt` dump exists (the dump is generated on a
Windows machine).

## Layout

| Path | What it is |
|---|---|
| `proxy/` | `winmm.dll`: proxy that exports the real winmm API and loads the unlock chain |
| `shim/` | the GDK shim (`QueryApiImpl` hook + license wrappers) |
| `common/` | shared utilities (INI, ChaCha20, encrypted strings, process gate) |
| `tools/` | generators and the 2-stage packer |
| `tests/` | native tests |
| `resource/` | build resources (VERSIONINFO, config INI) |

## How it works (summary)

1. The game imports `winmm.dll`, so the proxy enters the process as the app
   winmm and chains the calls to the real `winmmbase.dll`.
2. The shim installs a 5-byte detour (`E9 rel32`) on the `QueryApiImpl` export
   of `xgameruntime.dll`. The detour uses a relay page allocated near the
   module, with a prologue trampoline and the handler pointer never stored in
   clear text.
3. When the game asks for the `XStore`/`XPackage` interfaces, the handler
   returns a wrapper (the real object stays at `[0x18]`, with the original
   vtable intact) whose license slots answer "owned". All other slots are pure
   forwarders.
4. In `--harden` the payload does not exist as a PE on disk: it is encrypted
   (ChaCha20, per-build key) inside the `winmm.dll` overlay and is mapped
   manually. The stub validates the CRC of its own code and the payload
   validates the CRC at load. Critical strings are XOR-encrypted and the winmm
   import table does not list the packer APIs (resolved by hash at runtime).

## Dev test

Copy `dist/winmm.dll` (plus `dist/XGameCore.GDK.dll` and `unlock-CoelhoFZ.ini`
in the dev modes) into the same folder as the game executable, exactly as the
installer does. The diagnostic log goes to `%TEMP%\coelhofz_hook.log`.

## Diagnostic bypasses (dev builds)

The `--release` and `--debug` modes have three file flags for debugging.
Create an empty file with the flag name in the folder pointed to by the
`COELHOFZ_DEV_DIR` environment variable. If the variable does not exist, the
base folder is the user `%TEMP%`.

| Flag | Effect |
|---|---|
| `NTHUNK` | the wrapper keeps ONLY forwarders (does not answer "owned") |
| `NWRAP` | the hook runs but returns the real object (no wrapper) |
| `NOHOOK` | the hook is not even installed (the game runs vanilla) |

## Notice

This project does not contain or distribute any Minecraft files. It only
changes the result of the license query inside the game process memory. Use at
your own risk.

## License

GPLv3. You can use, study, modify and redistribute this code, as long as
derivative works stay under the same license. Redistribution in a closed
product is not allowed.