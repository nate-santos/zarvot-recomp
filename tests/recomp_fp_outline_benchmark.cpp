// Generate generic synthetic binary32 arithmetic from one emitter revision.
// Compile once against the baseline header, then again with BENCH_CANDIDATE
// against the candidate. No game instruction words or assets are used.
#include <cstdio>
#include <fstream>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>
#include "core/recompiler/arm64_to_c.h"

namespace sr = suyu::recomp;
void Write(const std::filesystem::path& p, const std::string& s) {
    std::ofstream f(p, std::ios::binary);
    if (!f.write(s.data(), static_cast<std::streamsize>(s.size()))) throw std::runtime_error("write failed");
}
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    const std::filesystem::path dir(argv[1]);
    std::filesystem::create_directories(dir);
    sr::g_translate_all = true;
    sr::g_emit_fastmem = true;
    sr::g_emit_guard_gen = true;
    sr::g_emit_fpx = true;
#ifdef BENCH_CANDIDATE
    const std::string tag = "candidate";
    Write(dir / "helpers.c", "#include \"rt_candidate.h\"\n" + sr::FpxExactRuntimeC());
#else
    const std::string tag = "baseline";
#endif
    Write(dir / ("rt_" + tag + ".h"), sr::RuntimeH());
    std::string code = "#include \"rt_" + tag + ".h\"\n";
    for (unsigned n : {16u, 122u}) {
        std::vector<unsigned> kinds;
        if (n == 16) {
            for (unsigned j = 0; j < 8; ++j) { kinds.push_back(0); kinds.push_back(j & 1 ? 2 : 1); }
        } else {
            unsigned left[]{34, 62, 26};
            for (unsigned j = 0; kinds.size() < n; ++j) {
                const unsigned k = j % 3;
                if (left[k]) { kinds.push_back(k); --left[k]; }
            }
        }
        code += "__declspec(noinline) void " + tag + "_" + std::to_string(n) + "(GuestContext*c){\n";
        unsigned counts[3]{};
        for (unsigned j = 0; j < kinds.size(); ++j) {
            const unsigned k = kinds[j];
            ++counts[k];
            const unsigned rd = (n == 16 ? j / 2 : j) % 8;
            const unsigned rn = k == 0 ? 8 + rd : rd;
            const unsigned rm = k == 0 ? 16 + rd : 24 + rd;
            const unsigned opcode = k == 0 ? 0x1e200800u : k == 1 ? 0x1e202800u : 0x1e203800u;
            const unsigned word = opcode | (rm << 16) | (rn << 5) | rd;
            bool miss = false;
            std::string body;
            if (!sr::Translate(word, 0x1000 + 4 * j, body, &miss) || miss) throw std::runtime_error("unexpected translation gap");
            code += body;
        }
        code += "}\n";
        std::printf("%s_synthetic_%u mul=%u add=%u sub=%u\n", tag.c_str(), n, counts[0], counts[1], counts[2]);
    }
    Write(dir / (tag + ".c"), code);
    std::printf("%s_source_bytes=%zu\n", tag.c_str(), code.size());
}
