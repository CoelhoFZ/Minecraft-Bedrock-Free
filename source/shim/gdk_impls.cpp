// gdk_impls.cpp - REAL IIDs used by the QueryApiImpl hook.
//
// Extracted from the .data of the unpacked unlock-CoelhoFZ (dumps + decompiled
// factory FUN_180007aa0 as ground truth):
//   - factory compares *param_1 == DAT_1800305a0 (+param_1[1]==DAT_1800305a8)
//     for XPackage and DAT_180030578/580 for XStore.
//   - DAT_1800305a0 = qword 0x4aa8e850af406016; 0x305a8 = 0x7eac9dcb3d2f8da8
//   - DAT_180030578 = qword 0x448c7c240dd112ac; 0x30580 = 0x0cd35bfb60392bb9
// (bytes in little-endian, memory order = order of the Guid128).
//
// NOTE: the fake classes (XStoreImpl/XPackageImpl/XalImpl) were REMOVED -
// they were dead skeleton (GetInterface is never called; the real mechanism
// is the hook wrapper in hook_api_impl.cpp). Removed 2026-08-14 during hardening.

#include "gdk_interfaces.h"

const Guid128 kIidXPackage = {
    0x16, 0x60, 0x40, 0xaf, 0x50, 0xe8, 0xa8, 0x4a,
    0xa8, 0x8d, 0x2f, 0x3d, 0xcb, 0x9d, 0xac, 0x7e,
};
const Guid128 kIidXStore = {
    0xac, 0x12, 0xd1, 0x0d, 0x24, 0x7c, 0x8c, 0x44,
    0xb9, 0x2b, 0x39, 0x60, 0xfb, 0x5b, 0xd3, 0x0c,
};
const Guid128 kIidUnlockCoelhoFZInterface{};  // TODO(RE): not located yet
