#!/usr/bin/env bash
# build.sh - builds the unlock-CoelhoFZ DLLs (cross MinGW, Windows x64+arm64).
#
# Usage: ./build.sh [--release|--debug|--harden|--lite] [--arch=x64|arm64|both]
# Output: dist/winmm.dll                 (proxy x64)
#         dist/XGameCore.GDK.dll (+ ini) (shim x64, dev/release only)
#         dist/arm64/{winmm.dll,...}     (same, ARM64 variant when --arch includes arm64)
#
# Modes:
#   --release : full diagnostics (log, slot-tracking, per-file bypasses)
#   --debug   : same + -O0 -g
#   --harden  : protected distribution - -DHARDENED (ZERO diagnostic log/
#               strings, bypasses removed, obfuscation, anti-debug),
#               full strip, no RTTI/exceptions/unwind, gc-sections.
#               (x64 variant only for now; arm64 skips with a warning until
#               the packer is validated on PE ARM64.)
#   --lite    : distribution WITHOUT packer/mapper/anti-debug (embedded
#               config, encrypted strings, no INI) - the shape the AV does NOT
#               detect.
#
# Architectures:
#   x64   : GCC MinGW (x86_64-w64-mingw32-g++)  - exactly as before.
#   arm64 : llvm-mingw (aarch64-w64-mingw32-clang++). Download from
#           https://github.com/mstorsjo/llvm-mingw/releases (ucrt/ubuntu
#           variant matching the host) and extract to
#           ~/.local/opt/llvm-mingw (or point LLVM_MINGW=/path).
#           Produces native binaries for Windows-on-ARM PCs (Snapdragon).
#
# HARDEN (x64) - 2-stage packer (no readable PE on disk):
#   1. payload.dll (the shim) -> encrypted          -> BLOB2 (build/payload.bin)
#   2. mapper.dll  (loader2)  -> encrypted (ChaCha20, per-build key)
#                                                   -> BLOB1 (build/mapper.bin)
#   3. winmm.dll = proxy + stub (layer 1) + overlay [BLOB2][BLOB1][12B trailer]
#   4. two-pass of the stub self-CRC: pass 1 (placeholder constant) computes
#      the .text CRC, set-crc writes it masked into stub_cfg.h, pass 2 rebuilds
#      with the real constant (the .text does not change -> identical CRC,
#      verified).
#
# Toolchains: sudo apt install gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64
set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
MODE=""
ARCH="both"
for arg in "$@"; do
  case "$arg" in
    --release|--debug|--harden|--lite) MODE="$arg" ;;
    --arch=*) ARCH="${arg#--arch=}" ;;
    *)
      echo "ERROR: unknown argument: $arg"
      echo "usage: ./build.sh [--release|--debug|--harden|--lite] [--arch=x64|arm64|both]"
      exit 1
      ;;
  esac
done
if [ -z "$MODE" ]; then MODE="--release"; fi
case "$ARCH" in
  x64|arm64|both) ;;
  *) echo "ERROR: invalid --arch: $ARCH (use x64|arm64|both)"; exit 1 ;;
esac

LLVM_MINGW="${LLVM_MINGW:-$HOME/.local/opt/llvm-mingw/bin}"

SHIM_SRCS="shim/dllmain.cpp shim/unlock_coelho_fz_impl.cpp shim/gdk_impls.cpp shim/hook_api_impl.cpp shim/hook_detour.cpp common/simple_ini.cpp"

# Flags per mode (identical for both compilers; both are GNU drivers).
COMMON_FLAGS="-std=c++17 -Icommon -static-libgcc -static-libstdc++ -Wl,--subsystem,windows"
STRIP_COMMENT=0
case "$MODE" in
  --debug)  FLAGS="$COMMON_FLAGS -O0 -g -D_DEBUG" ;;
  --harden) # Anti-RE (x64): no log (-DHARDENED), no RTTI/exceptions/unwind,
            # no symbols, fno-ident removes the compiler signature.
            FLAGS="$COMMON_FLAGS -O2 -DHARDENED -fno-ident -fvisibility=hidden -fno-rtti -fno-exceptions"
            # -fno-threadsafe-statics: no __cxa_guard_* guard (the local
            # statics are init-once in DllMain/main thread, no race).
            FLAGS="$FLAGS -fno-threadsafe-statics"
            FLAGS="$FLAGS -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections"
            FLAGS="$FLAGS -Wl,--gc-sections -Wl,--strip-all -Wl,--no-insert-timestamp"
            STRIP_COMMENT=1
            ;;
  --lite)   FLAGS="$COMMON_FLAGS -O2 -DLITE -fno-ident" ;;
  *)        FLAGS="$COMMON_FLAGS -O2" ;;
esac

build_one() {
  # $1=tag  $2=CXX  $3=WINDRES  $4=OBJCOPY  $5=OUTDIR
  local tag="$1" CXX="$2" WINDRES="$3" OBJCOPY="$4" OUT="$5"
  echo ""
  echo "================ [$tag] ===================="
  if ! command -v "$CXX" >/dev/null 2>&1; then
    echo "ERROR: compiler $CXX not found."
    if [ "$tag" = "arm64" ]; then
      echo "Install llvm-mingw (aarch64): https://github.com/mstorsjo/llvm-mingw/releases"
      echo "and extract to ~/.local/opt/llvm-mingw (or export LLVM_MINGW=/path/to/bin)"
    else
      echo "sudo apt install g++-mingw-w64-x86-64"
    fi
    return 1
  fi

  mkdir -p "$OUT"
  # Cleans the outdir (avoids deploying a stale artifact from a previous build).
  rm -f "$OUT"/*.dll "$OUT"/*.ini

  # VERSIONINFO: under harden there is NO resource (empty rc gives 'no resources', it does not even link).
  local RES_S="" RES_P=""
  if [ "$MODE" != "--harden" ]; then
    echo "==> VERSIONINFO (windres)"
    "$WINDRES" -O coff -o "build/${tag}_shim_res.o" resource/shim_res.rc
    "$WINDRES" -O coff -o "build/${tag}_proxy_res.o" resource/proxy_res.rc
    RES_S="build/${tag}_shim_res.o"
    RES_P="build/${tag}_proxy_res.o"
  fi

  local PROXY_EXTRA=""
  if [ "$MODE" = "--harden" ]; then
    PROXY_EXTRA="proxy/stub_loader.cpp -Ibuild"
  fi

  build_winmm() {
    "$CXX" $FLAGS -shared -o "$OUT/winmm.dll" \
      proxy/dllmain.cpp $PROXY_EXTRA proxy/winmm_stubs.cpp proxy/winmm_stubs.S \
      -Wl,proxy/winmm.def $RES_P
    if [ "$STRIP_COMMENT" = "1" ]; then
      "$OBJCOPY" --remove-section=.comment "$OUT/winmm.dll" 2>/dev/null || true
    fi
  }

  if [ "$MODE" = "--harden" ]; then
    echo "==> payload (BLOB2: shim, 1 pass)"
    "$CXX" $FLAGS -shared -Wl,--exclude-all-symbols -o "build/${tag}_payload.dll" $SHIM_SRCS $RES_S
    "$OBJCOPY" --remove-section=.comment "build/${tag}_payload.dll" 2>/dev/null || true
    echo "==> pack_payload gen (PER-BUILD key for the payload)"
    python3 tools/pack_payload.py gen --shim "build/${tag}_payload.dll" \
      --key build/payload_key.h --blob build/payload.bin
    echo "==> mapper (BLOB1: encrypted loader2, per-build ChaCha20)"
    "$CXX" $FLAGS -shared -Wl,--exclude-all-symbols -o "build/${tag}_mapper.dll" \
      proxy/mapper_dllmain.cpp -Ibuild
    "$OBJCOPY" --remove-section=.comment "build/${tag}_mapper.dll" 2>/dev/null || true
    echo "==> pack_payload gen-mapper (PER-BUILD key for the mapper + magic)"
    python3 tools/pack_payload.py gen-mapper --shim "build/${tag}_mapper.dll" \
      --key build/stub_cfg.h --blob build/mapper.bin --magic build/magic.bin

    echo "==> winmm.dll (2-stage packer)"
    build_winmm
    local CRC1 CRC2
    python3 tools/pack_payload.py append --winmm "$OUT/winmm.dll" \
      --blob2 build/payload.bin --blob1 build/mapper.bin --magic build/magic.bin
    CRC1=$(python3 tools/text_crc.py "$OUT/winmm.dll")
    echo "==> .text CRC (pass 1): $CRC1"
    python3 tools/pack_payload.py set-crc --key build/stub_cfg.h --crc "$CRC1"
    echo "==> rebuild winmm (pass 2, real constant)"
    build_winmm
    python3 tools/pack_payload.py append --winmm "$OUT/winmm.dll" \
      --blob2 build/payload.bin --blob1 build/mapper.bin --magic build/magic.bin
    CRC2=$(python3 tools/text_crc.py "$OUT/winmm.dll")
    echo "==> .text CRC (pass 2): $CRC2"
    if [ "$CRC1" != "$CRC2" ]; then
      echo "ERROR: .text changed between pass 1 and pass 2 - inconsistent self-CRC!"
      return 1
    fi
    echo "==> two-pass OK (consistent self-CRC)"
    # harden: only winmm goes to the outdir (payload+mapper encrypted in the overlay).
    rm -f "$OUT/XGameCore.GDK.dll" "$OUT/unlock-CoelhoFZ.ini"
  else
    echo "==> XGameCore.GDK.dll (GDK shim: QueryApiImpl hook + wrapper)"
    "$CXX" $FLAGS -shared -Wl,--exclude-all-symbols \
      -o "$OUT/XGameCore.GDK.dll" $SHIM_SRCS $RES_S

    echo "==> winmm.dll (proxy)"
    build_winmm

    # INI: dev/release only (harden/lite use embedded config - nothing on disk).
    if [ "$MODE" != "--lite" ]; then
      echo "==> unlock-CoelhoFZ.ini (config in dev/release only)"
      cp resource/unlock-CoelhoFZ.ini "$OUT/unlock-CoelhoFZ.ini"
    else
      rm -f "$OUT/unlock-CoelhoFZ.ini"
    fi
  fi

  echo "[$tag] OK:"
  ls -la "$OUT/"
}

mkdir -p build

# ================================ x64 ======================================
# Same toolchain/code as always (GCC MinGW) - zero regression for the path
# that already runs on users' PCs today.
if [ "$ARCH" = "x64" ] || [ "$ARCH" = "both" ]; then
  if [ "$MODE" = "--harden" ]; then
    build_one x64 x86_64-w64-mingw32-g++ x86_64-w64-mingw32-windres \
              x86_64-w64-mingw32-objcopy dist
  else
    build_one x64 x86_64-w64-mingw32-g++ x86_64-w64-mingw32-windres \
              x86_64-w64-mingw32-objcopy dist
  fi
fi

# =============================== arm64 =====================================
# llvm-mingw (clang+lld). Same sources; the arch-specific points live
# under #if defined(__aarch64__) in the sources (see the unlocker README).
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "both" ]; then
  A_CXX="$LLVM_MINGW/aarch64-w64-mingw32-g++"
  A_WINDRES="$LLVM_MINGW/aarch64-w64-mingw32-windres"
  A_OBJCOPY="$LLVM_MINGW/aarch64-w64-mingw32-objcopy"
  if [ ! -x "$A_CXX" ]; then
    echo "WARNING: llvm-mingw not found at $LLVM_MINGW - without it there is no arm64 build."
    echo "Download https://github.com/mstorsjo/llvm-mingw/releases (ucrt/ubuntu-aarch64)"
    echo "and extract to ~/.local/opt/llvm-mingw (or export LLVM_MINGW=/path/to/bin)"
    [ "$ARCH" = "arm64" ] && exit 1
  else
    # DIRECT call (outside an if): any compilation error aborts with -e.
    if [ "$MODE" = "--harden" ]; then
      echo "[arm64] --harden not supported yet (packer not validated on PE ARM64)."
      echo "          Using --lite instead (embedded config, no INI/anti-debug)."
      MODE="--lite"
      FLAGS="$COMMON_FLAGS -O2 -DLITE -fno-ident"
    fi
    build_one arm64 "$A_CXX" "$A_WINDRES" "$A_OBJCOPY" dist/arm64
  fi
fi

# ==================== exports parity test ===================================
# The proxy MUST export everything the real system winmm exports (if the game
# starts importing a new function the proxy lacks, you get "Bad Image" on the
# user machine) and the binary must deliver everything the .def promises.
# Failure here ABORTS the build (exit 1). Without the reconstructed/
# winmm_exports.txt dump the comparison against the real winmm is skipped with
# a warning (VPS).
if [ -f dist/winmm.dll ]; then
  python3 tools/check_exports.py --dll dist/winmm.dll || exit 1
else
  python3 tools/check_exports.py || exit 1
fi

echo ""
echo "==> build complete (arch=$ARCH mode=$MODE)"
