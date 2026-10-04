#pragma once
// simple_ini.h - minimalist INI parser.
//
// Functional equivalent of the CSimpleIni embedded by unlock-CoelhoFZ
// (detected via RTTI: CSimpleIniTempl<D,S,SI_NoCase,SI_ConvertA> with
// FileWriter/OutputWriter). Supports the format used by the real
// unlock-CoelhoFZ.ini:
//
//   [Main]
//   #Language=en-US
//   ProductId=9NBLGGH2JHXJ
//   [Hashes]
//   0=7f0745a64e...
//
// Implemented portably (no dependencies) to allow native syntax-check/testing
// on Linux.

#include <cstddef>
#include <map>
#include <string>
#include <utility>

class SimpleIni {
public:
    // Reads the file from disk and parses it. Returns false if it did not open.
    bool load(const std::string& path);
    // Parses a buffer (used by load() and in tests).
    bool parse(const std::string& data);

    std::string get(const std::string& section,
                    const std::string& key,
                    const std::string& def = std::string()) const;
    bool has(const std::string& section, const std::string& key) const;

    std::size_t size() const { return values_.size(); }

private:
    // composite key = (section, key)
    std::map<std::pair<std::string, std::string>, std::string> values_;
};
