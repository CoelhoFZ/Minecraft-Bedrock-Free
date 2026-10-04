#pragma once
// gdk_interfaces.h - GDK interfaces the shim imitates (REAL vftables).
//
// The ORDER of the slots below mirrors exactly the vftables of the unpacked
// DLL (see reconstructed/REAL_VFTABLES.md):
//   - IXStoreVirtual   @ 0x30400 (43 slots)
//   - IXPackageVirtual @ 0x29b50 (20 slots)
// Each method documents the real RVA (FUN_18000xxxx) and the behavior
// observed in the decompilation. The game calls the slots by OFFSET - if the
// order does not match, the call lands on the wrong function (crash/denied).
//
// RTTI found: XStore, XStoreVirtual, XPackage, XPackageVirtual,
// UnlockCoelhoFZInterface, UnlockCoelhoFZGDKInterfaceImpl + CSimpleIniTempl.
// The shim does NOT import GDK (zero XStore/Xal/XPackage in the imports).
//
// Portable types (no windows.h) to allow native syntax-check.

#include <cstddef>
#include <cstdint>
#include <cstring>

// Simple 16-byte GUID (equivalent to the Windows IID).
struct Guid128 {
    uint8_t b[16];
};
inline bool operator==(const Guid128& a, const Guid128& b) {
    for (int i = 0; i < 16; ++i) {
        if (a.b[i] != b.b[i]) return false;
    }
    return true;
}
inline bool operator!=(const Guid128& a, const Guid128& b) { return !(a == b); }

// Error code returned by the original in the failure branches (0x8924xxxx =
// GDK Xbox error family; it is NOT E_NOTIMPL 0x80004001 - just our label
// for reference).
constexpr int32_t kErrXbox = 0x89245302;
// Status magic 1337 used by the unlock fillers (0x539).
constexpr uint32_t kStatusMagic = 0x539;
// E_INVALIDARG (0x80070057) - parameter validation.
constexpr int32_t kErrInvalidArg = 0x80070057;

// IIDs of the interfaces provided by the shim (extracted from .data via the factory).
extern const Guid128 kIidXStore;
extern const Guid128 kIidXPackage;
extern const Guid128 kIidUnlockCoelhoFZInterface;

// Entitlement: the game asks "does the user own this product?" and the shim
// answers "yes, Durable, no expiration" -> the game runs complete.
struct XStoreEntitlement {
    const char* kind;           // "Durable" / "Consumable"
    const char* id;             // ProductId (ex.: 9NBLGGH2JHXJ)
    const char* skuId;          // SKU do produto
    int64_t     expirationDate; // 0 = never expires
};

// =====================================================================
// IXStoreVirtual - mirrors the GDK XStore interface (vftable 0x30400,
// 43 slots, extracted from the unpacked DLL). Slots documented with the
// real RVA and the decompiled behavior. See reconstructed/REAL_VFTABLES.md.
// =====================================================================
class IXStoreVirtual {
public:
    // slot  0 @ 0xad10 - dtor / scalar deleting destructor
    virtual ~IXStoreVirtual() = default;

    // slot  1 @ 0xa8d0 - NO-OP
    virtual int32_t Slot01() { return 0; }
    // slot  2 @ 0x31090 - stub (outside the pulled .c files)
    virtual int32_t Slot02() { return 0; }
    // slot  3 @ 0x4da0 - Fwd(+0x0): dispatches to backend at this+0x18
    virtual int32_t Slot03() { return 0; }
    // slot  4 @ 0x4db0 - Fwd(+0x8)
    virtual int32_t Slot04() { return 0; }
    // slot  5 @ 0x4dc0 - Fwd(+0x10)
    virtual int32_t Slot05() { return 0; }
    // slot  6 @ 0x4dd0 - Fwd(+0x18)
    virtual int32_t Slot06() { return 0; }
    // slot  7 @ 0x4de0 - RET 0 (non-trial)
    virtual int32_t Slot07() { return 0; }
    // slot  8 @ 0x4df0 - *status = 0x539 (magic ok); S_OK
    virtual int32_t Slot08(uint32_t* status) {
        if (status != nullptr) { *status = kStatusMagic; return 0; }
        return kErrXbox;
    }
    // slot  9 @ 0x4e10 - NO-OP
    virtual void Slot09() {}
    // slot 10 @ 0x4e20 - fills 4 fields with 0x539
    virtual void Slot10(uint32_t* out) {
        if (out != nullptr) { out[0] = out[1] = out[2] = out[3] = kStatusMagic; }
    }
    // slot 11 @ 0x4e50 - RET 1 (LICENSED/OWNED - the unlock!)
    virtual int32_t IsOwned() { return 1; }
    // slot 12 @ 0x4e60 - *out = 0x539 + calls callback
    virtual int32_t Slot12(void* /*ctx*/, void* /*cb*/, uint32_t* out) {
        if (out != nullptr) { *out = kStatusMagic; return 0; }
        return kErrXbox;
    }
    // slot 13 @ 0x4e50 - RET 1 (LICENSED)
    virtual int32_t IsOwned2() { return 1; }
    // slot 14 @ 0x4ea0 - GetProductId: copies the string to buffer
    virtual int32_t GetProductId(char* buf, std::size_t size) {
        if (buf != nullptr && size > 0) { buf[0] = '\0'; return 0; }
        return kErrXbox;
    }
    // slot 15 @ 0x4f30 - *out = 0; S_OK
    virtual int32_t Slot15(uint32_t* out) {
        if (out != nullptr) { *out = 0; return 0; }
        return kErrXbox;
    }
    // slot 16 @ 0x4f50 - QueryEntitlementsAsync (the big one: enumerates
    // entitlements and calls the game callback). XStoreImpl implements it.
    // Mirror of the decompiled FUN_180004f50(param_2, type, ctx, cb): the
    // original calls cb(ctx, entitlement, 0) for each item in the list.
    virtual int32_t QueryEntitlementsAsync(void* param2, int type, void* ctx, void* cb) = 0;
    // slot 17 @ 0x57c0 - Fwd(+0x70)
    virtual int32_t Slot17() { return 0; }
    // slot 18 @ 0x57d0 - Fwd(+0x78)
    virtual int32_t Slot18() { return 0; }
    // slot 19 @ 0x57f0 - Fwd(+0x80)
    virtual int32_t Slot19() { return 0; }
    // slot 20 @ 0x5810 - Fwd(+0x88)
    virtual int32_t Slot20() { return 0; }
    // slot 21 @ 0x5820 - Fwd(+0x90)
    virtual int32_t Slot21() { return 0; }
    // slot 22 @ 0x5830 - Fwd(+0x98)
    virtual int32_t Slot22() { return 0; }
    // slot 23 @ 0x5840 - complex (queue) -> S_OK stub
    virtual int32_t Slot23() { return 0; }
    // slot 24 @ 0x5a30 - validates params -> S_OK or E_INVALIDARG
    virtual int32_t Slot24(void* p2, void* p4, void* p5) {
        if (p2 != nullptr && p4 != nullptr) return (p5 != nullptr) ? 0 : kErrInvalidArg;
        return kErrInvalidArg;
    }
    // slot 25 @ 0x4e50 - RET 1 (LICENSED)
    virtual int32_t IsOwned3() { return 1; }
    // slot 26 @ 0x5a60 - complex -> S_OK stub
    virtual int32_t Slot26() { return 0; }
    // slot 27 @ 0x5c40 - complex -> S_OK stub
    virtual int32_t Slot27() { return 0; }
    // slot 28 @ 0x5d00 - Fwd(+0xc8)
    virtual int32_t Slot28() { return 0; }
    // slot 29 @ 0x5dd0 - list lookup + Fwd(+0xd0)
    virtual int32_t Slot29() { return 0; }
    // slot 30 @ 0x5e50 - Fwd(+0xd8)
    virtual int32_t Slot30() { return 0; }
    // slot 31 @ 0x5e90 - dispatch (param==1 -> vft+0xa0, else param[3]+0xe0)
    virtual int32_t Slot31(int /*param*/) { return 0; }
    // slot 32 @ 0x5ed0 - Fwd(+0x120)
    virtual int32_t Slot32() { return 0; }
    // slot 33 @ 0x5e60 - Fwd(+0xf0)
    virtual int32_t Slot33() { return 0; }
    // slot 34 @ 0x5a50 - Fwd(+0xf8)
    virtual int32_t Slot34() { return 0; }
    // slot 35 @ 0x5e70 - Fwd(+0x100)
    virtual int32_t Slot35() { return 0; }
    // slot 36 @ 0x5f70 - Fwd(+0x108)
    virtual int32_t Slot36() { return 0; }
    // slot 37 @ 0x5e80 - Fwd(+0x110)
    virtual int32_t Slot37() { return 0; }
    // slot 38 @ 0x5ee0 - dispatch (vft+0xa0 / param[3]+0x118)
    virtual int32_t Slot38(int /*param*/) { return 0; }
    // slot 39 @ 0x5f20 - dispatch (vft+0xa8)
    virtual int32_t Slot39() { return 0; }
    // slot 40 @ 0x5f80 - complex -> S_OK stub
    virtual int32_t Slot40() { return 0; }
    // slot 41 @ 0x6160 - complex -> S_OK stub
    virtual int32_t Slot41() { return 0; }
    // slot 42 @ 0x5f30 - dispatch (vft+0xa0 / param[3]+0x138)
    virtual int32_t Slot42(int /*param*/) { return 0; }
};

// =====================================================================
// IXPackageVirtual - mirrors the GDK XPackage interface (vftable
// 0x29b50, 20 slots). Practically ALL slots answer 1 (owned/installed) -
// it is the unlock signature on the package side.
// =====================================================================
class IXPackageVirtual {
public:
    // slot  0 @ 0x177e4 - dtor (did not decompile)
    virtual ~IXPackageVirtual() = default;

    // slot  1 - NULL in the original
    virtual int32_t Slot01() { return 0; }
    // slot  2 @ 0x1782c - RET 1 (LICENSED)
    virtual int32_t Slot02() { return 1; }
    // slot  3 - NULL in the original
    virtual int32_t Slot03() { return 0; }
    // slot  4 @ 0x19cdc - init/registration
    virtual int32_t Slot04() { return 0; }
    // slot  5 @ 0x19d50 - RET 1
    virtual int32_t Slot05() { return 1; }
    // slot  6 @ 0x4e50 - RET 1 (LICENSED)
    virtual int32_t IsOwned() { return 1; }
    // slot  7 @ 0x4e50 - RET 1 (LICENSED)
    virtual int32_t IsOwned2() { return 1; }
    // slot  8 @ 0x1cf7c - __acrt_initialize_locks -> 1
    virtual int32_t Slot08() { return 1; }
    // slot  9 @ 0x1cfe0 - RET 1
    virtual int32_t Slot09() { return 1; }
    // slot 10 @ 0x1f1a0 - bool check (DAT_180036cb0) -> != 0
    virtual int32_t Slot10() { return 1; }
    // slot 11 @ 0x1f1d0 - (did not decompile)
    virtual int32_t Slot11() { return 0; }
    // slot 12 - NULL in the original
    virtual int32_t Slot12() { return 0; }
    // slot 13 @ 0x1786c - (did not decompile)
    virtual int32_t Slot13() { return 0; }
    // slot 14 @ 0x18718 - init -> RET 1 on success
    virtual int32_t Init() { return 1; }
    // slot 15 @ 0x1875c - RET 1
    virtual int32_t Slot15() { return 1; }
    // slot 16 @ 0x194e0 - __acrt_initialize_lowio -> 1
    virtual int32_t Slot16() { return 1; }
    // slot 17 @ 0x1951c - __acrt_uninitialize_lowio -> 1
    virtual int32_t Slot17() { return 1; }
    // slot 18 @ 0x1e940 - RET 1
    virtual int32_t Slot18() { return 1; }
    // slot 19 @ 0x4e50 - RET 1 (LICENSED)
    virtual int32_t Slot19() { return 1; }
};

// =====================================================================
// IUnlockCoelhoFZInterface - root interface of the shim. The real vftable
// 0x26380 has 16 slots (CRT + shim mix; see REAL_VFTABLES.md); slots 8
// (0x1000, creates sub-object) and 9 (0x1060, constructor) are the cores.
// Here we keep the conceptual factory methods.
// =====================================================================
class IUnlockCoelhoFZInterface {
public:
    virtual ~IUnlockCoelhoFZInterface() = default;

    // Factory: mirror of FUN_180007aa0 - given an interface GUID, returns
    // the XStore/XPackage object with the right vftable.
    virtual void* GetInterface(const Guid128& iid) = 0;
    virtual const char* product_id() const = 0;
};
