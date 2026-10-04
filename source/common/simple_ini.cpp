#include "simple_ini.h"

#include <cctype>
#include <fstream>
#include <sstream>

namespace {

std::string trim(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}

}  // namespace

bool SimpleIni::load(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::ostringstream ss;
    ss << f.rdbuf();
    return parse(ss.str());
}

bool SimpleIni::parse(const std::string& data) {
    values_.clear();
    std::string section;  // "" = before any [section]
    std::istringstream in(data);
    std::string line;
    while (std::getline(in, line)) {
        // strips \r (Windows line ending)
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::string t = trim(line);
        if (t.empty()) continue;
        if (t[0] == ';' || t[0] == '#') continue;  // comment
        if (t[0] == '[') {                          // new section
            std::size_t close = t.find(']');
            if (close == std::string::npos) continue;
            section = trim(t.substr(1, close - 1));
            continue;
        }
        std::size_t eq = t.find('=');
        if (eq == std::string::npos) continue;
        std::string key = trim(t.substr(0, eq));
        std::string val = trim(t.substr(eq + 1));
        if (key.empty()) continue;
        values_[{section, key}] = val;
    }
    return true;
}

std::string SimpleIni::get(const std::string& section,
                           const std::string& key,
                           const std::string& def) const {
    auto it = values_.find({section, key});
    return it == values_.end() ? def : it->second;
}

bool SimpleIni::has(const std::string& section, const std::string& key) const {
    return values_.count({section, key}) != 0;
}
