#include "unlock_coelho_fz_impl.h"
#include "enc_strings.h"

UnlockCoelhoFZGDKInterfaceImpl& UnlockCoelhoFZGDKInterfaceImpl::instance() {
    static UnlockCoelhoFZGDKInterfaceImpl inst;  // singleton local static
    return inst;
}

bool UnlockCoelhoFZGDKInterfaceImpl::init(const std::string& ini_path) {
    return load_config(ini_path);
}

bool UnlockCoelhoFZGDKInterfaceImpl::init_embedded() {
    product_id_ = enc::dec(enc::kProdIdDef, enc::kProdIdDefLen, 0x5A);
    return !product_id_.empty();
}

bool UnlockCoelhoFZGDKInterfaceImpl::load_config(const std::string& ini_path) {
    if (!ini_.load(ini_path)) return false;
    product_id_ = ini_.get("Main", "ProductId");
    // [Hashes] 0..n: anti-tamper verification of the game binaries.
    // TODO(RE): implement the real check (the original uses magic
    // constants 0x2b992ddfa232/233 + cmove + decoy not rax, in winmm).
    if (product_id_.empty()) return false;
    return true;
}

// Mirror factory of FUN_180007aa0. The REAL unlock mechanism is the
// QueryApiImpl hook (hook_api_impl.cpp) that wraps the game's XStore/XPackage
// objects - this factory is not used in the active path.
void* UnlockCoelhoFZGDKInterfaceImpl::GetInterface(const Guid128&) {
    return nullptr;
}
