#pragma once
// hook_api_impl.h - QueryApiImpl hook for xgameruntime.dll.
//
// This is the REAL unlock mechanism: the game obtains the GDK interfaces
// (XPackage/XStore) by calling xgameruntime!QueryApiImpl. The unlocker hooks
// this export and returns the REAL object with the license slots overwritten
// with "owned" answers (magic 0x539 / 0x1337).

// Installs the detour on xgameruntime's QueryApiImpl. Returns true if the
// hook became active (or was already). If xgameruntime is not loaded yet,
// schedules a retry in the background.
bool InstallQueryApiImplHook();

// Installs a VectoredExceptionHandler that logs the exact crash (code + RIP +
// stack) to coelhofz_hook.log, to find the crashing slot.
bool InstallCrashHandler();

// ProductId used in the fake entitlements (called by dllmain after init).
void SetUnlockProductId(const char* pid);

// Kill-switch (hardening): points to the stub watchdog flag. If set, the
// hook becomes passthrough (returns the original QueryApiImpl result without
// wrapping) - used when the watchdog detects tampering with winmm.dll after
// load.
void SetHookKillFlag(volatile LONG* flag);
