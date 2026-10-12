// Synthetic gate experiment from the real emitter. Never reads game data.
#include <filesystem>
#include <fstream>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include "core/recompiler/arm64_to_c.h"

static void Write(const std::filesystem::path& p, const std::string& text) {
    std::ofstream f(p, std::ios::binary);
    if (!f.write(text.data(), static_cast<std::streamsize>(text.size())))
        throw std::runtime_error("write failed");
}
static void Replace(std::string& text, const std::string& from, const std::string& to) {
    const auto at = text.find(from);
    if (at == std::string::npos || text.find(from, at + from.size()) != std::string::npos)
        throw std::runtime_error("expected exactly one FM1 gate");
    text.replace(at, from.size(), to);
}
static std::string Gate(const std::string& text) {
    const auto start = text.find("static RECOMP_INLINE uintptr_t recomp_fm_entry(");
    const auto end = text.find("\n}", start);
    if (start == std::string::npos || end == std::string::npos) throw std::runtime_error("gate missing");
    return text.substr(start, end + 2 - start);
}
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    const std::filesystem::path out(argv[1]);
    std::filesystem::create_directories(out);
    namespace sr = suyu::recomp;
    const std::string header = sr::BuildRuntimeH(true);
    const std::string baseline = sr::BuildRuntimeC(true);
    // GG1 changes stores but must not change the load gate being measured.
    if (Gate(baseline) != Gate(sr::BuildRuntimeC(true, true))) return 3;
    const std::string checks =
        "  if(va >= c->fm_limit) return 0;\n"
        "  if((va & 0xfffu) > 0x1000u - bytes) return 0;\n";
    std::set<std::string> names;
    const std::regex function(R"(\brecomp_[a-zA-Z0-9_]+\s*\()");
    const auto all = header + baseline + sr::BuildRuntimeC(false);
    for (auto it = std::sregex_iterator(all.begin(), all.end(), function); it != std::sregex_iterator(); ++it) {
        std::string name = it->str();
        name.erase(name.find_first_of(" (\t\r\n"));
        names.insert(name);
    }
    Write(out / "recomp_runtime.h", header);
    Write(out / "baseline_gate.txt", Gate(baseline));
    for (const std::string tag : {"baseline", "aligned", "reversed", "combined", "masked", "abi5"}) {
        std::string runtime = tag == "abi5" ? sr::BuildRuntimeC(false) : baseline;
        if (tag == "aligned") Replace(runtime, checks,
            "  if(va >= c->fm_limit) return 0;\n"
            "  if((va & (bytes - 1u)) && (va & 0xfffu) > 0x1000u - bytes) return 0;\n");
        if (tag == "reversed") Replace(runtime, checks,
            "  if((va & 0xfffu) > 0x1000u - bytes) return 0;\n"
            "  if(va >= c->fm_limit) return 0;\n");
        if (tag == "combined") Replace(runtime, checks,
            "  if((va >= c->fm_limit) | ((va & 0xfffu) > 0x1000u - bytes)) return 0;\n");
        if (tag == "masked") Replace(runtime,
            "((uintptr_t)(va >> RECOMP_FM_PAGE_BITS)\n                                            << RECOMP_FM_STRIDE_LOG2)",
            "((uintptr_t)((va & ~UINT64_C(0xfff)) >> (RECOMP_FM_PAGE_BITS - RECOMP_FM_STRIDE_LOG2)))");
        std::string rename = "/* Synthetic experiment names; runtime unchanged except the gate. */\n";
        for (const auto& name : names) rename += "#define " + name + " " + tag + "_" + name + "\n";
        Write(out / (tag + "_names.h"), rename);
        runtime = "#include \"" + tag + "_names.h\"\n" + runtime;
        if (tag != "abi5") runtime += "\nuintptr_t " + tag +
            "_gate(GuestContext*c,uint64_t a,unsigned n){return recomp_fm_entry(c,a,n);}\n";
        Write(out / (tag + ".c"), runtime);
        if (tag != "abi5") Write(out / (tag + "_gate.txt"), Gate(runtime));
    }
    return 0;
}
