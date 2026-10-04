#pragma once
// stub_loader.h - stub entry (layer 1 of the 2-stage packer).
//
// harden-only: in dev/release the proxy uses LoadLibrary of XGameCore.GDK.dll.

#include <windows.h>

// Runs layer 1: validates its own integrity (.text CRC, 2-pass),
// light anti-debug, finds the overlay (BLOB1 = encrypted mapper), decrypts and
// maps it via miniloader, passing the parameters to the mapper DllMain. The
// mapper (BLOB1) decrypts and maps BLOB2 (payload). Failure = silent.
bool StubLoadAndRunPayload(HINSTANCE self);
