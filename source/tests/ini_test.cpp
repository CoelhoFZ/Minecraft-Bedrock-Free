// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

// ini_test.cpp - native test of the INI parser (runs on Linux, no Windows).
// Uses the REAL unlock-CoelhoFZ.ini format (Main/Hashes) to validate the parser.

#include <cassert>
#include <iostream>

#include "simple_ini.h"

int main() {
    SimpleIni ini;
    const char* sample =
        "[Main]\n"
        "#Language=en-US\n"
        "ProductId=9NBLGGH2JHXJ\n"
        "\n"
        "[Hashes]\n"
        "0=7f0745a64e08d858\n"
        "1337=9286b2bde6d14e0a\n";

    assert(ini.parse(sample));
    assert(ini.size() == 3);
    assert(ini.get("Main", "ProductId") == "9NBLGGH2JHXJ");
    assert(ini.get("Main", "Language") == "");       // comment ignored
    assert(ini.get("Hashes", "0") == "7f0745a64e08d858");
    assert(ini.get("Hashes", "1337") == "9286b2bde6d14e0a");
    assert(ini.has("Main", "ProductId"));
    assert(!ini.has("Main", "Nope"));
    assert(ini.get("Missing", "Key", "def") == "def");  // default

    // Format with \r\n (real Windows file) and spaces around '='
    const char* crlf =
        "[Main]\r\n"
        "ProductId = 9NBLGGH2JHXJ \r\n";
    assert(ini.parse(crlf));
    assert(ini.get("Main", "ProductId") == "9NBLGGH2JHXJ");

    std::cout << "ini_test OK" << std::endl;
    return 0;
}
