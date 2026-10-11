// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

#pragma once
// unlock_coelho_fz_impl.h - shim singleton.
//
// Mirrors the decompiled key functions of unlock-CoelhoFZ:
//   - FUN_180001060 (constructor): creates the object with
//     UnlockCoelhoFZGDKInterfaceImpl::vftable and stores the backend pointer
//     (DAT_180036d08) + singleton at DAT_180036d20.
//
// CURRENT RESPONSIBILITY: read unlock-CoelhoFZ.ini (ProductId) and expose the
// product_id to the hook (SetUnlockProductId). The real unlock mechanism
// (QueryApiImpl wrapper) lives in hook_api_impl.cpp - the fake object
// factory (XStoreImpl/XPackageImpl) was REMOVED as dead code.

#include <string>

#include "gdk_interfaces.h"
#include "simple_ini.h"

class UnlockCoelhoFZGDKInterfaceImpl final : public IUnlockCoelhoFZInterface {
public:
    // Singleton (equivalent to DAT_180036d20 in the original).
    static UnlockCoelhoFZGDKInterfaceImpl& instance();

    // init: loads unlock-CoelhoFZ.ini (ProductId) - dev mode only.
    bool init(const std::string& ini_path);

    // init_embedded (harden): ProductId via encrypted constant (enc_strings.h)
    // - there is no INI on disk nor file reads in the final binary.
    bool init_embedded();

    // Mirror factory (FUN_180007aa0) - the real mechanism does not use it; kept
    // only to satisfy the base interface (returns nullptr).
    void* GetInterface(const Guid128& iid) override;
    const char* product_id() const override { return product_id_.c_str(); }

private:
    UnlockCoelhoFZGDKInterfaceImpl() = default;

    bool load_config(const std::string& ini_path);

    std::string product_id_;
    SimpleIni ini_;
};
