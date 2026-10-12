// Compare immutable baseline/candidate synthetic blocks, then time equivalent
// work. Performance is reported, never asserted, and makes no game-FPS claim.
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <xmmintrin.h>
extern "C" {
#include "gen/rt_candidate.h"
void baseline_16(GuestContext*);
void candidate_16(GuestContext*);
void baseline_122(GuestContext*);
void candidate_122(GuestContext*);
}
using Fn = void(*)(GuestContext*);
volatile std::uint64_t sink;
std::uint64_t random_state = 0xc7615a4bc0928ed1ULL;
std::uint64_t Next() { random_state ^= random_state << 13; random_state ^= random_state >> 7; random_state ^= random_state << 17; return random_state; }
void Seed(GuestContext& c, unsigned sample, unsigned mode, std::uint64_t fs) {
    c = {};
    for (auto& x : c.x) x = Next();
    c.pc = Next();
    c.n = Next() & 1; c.z = Next() & 1; c.c = Next() & 1; c.v = Next() & 1;
    for (auto& r : c.vreg) for (auto& h : r) h = Next();
    for (auto& b : c.save_dir) b = static_cast<char>(Next());
    c.tpidr_el0 = Next(); c.tpidrro_el0 = Next();
    c.chain_budget = static_cast<int>(Next());
    c.pending_svc = Next();
    c.fpcr = (std::uint64_t(mode & 3) << 22) | ((mode & 4) ? 1ULL << 24 : 0) |
             ((mode & 8) ? 1ULL << 25 : 0) | ((mode & 16) ? 1ULL << 32 : 0);
    c.fpsr = fs;
    constexpr std::uint32_t edge[]{0,0x80000000,1,0x007fffff,0x00800000,0x00800001,
        0x3f800000,0xbf800000,0x3f000000,0x3f800001,0x3f7fffff,0x7f7fffff,
        0xff7fffff,0x7f800000,0xff800000,0x7fc00023,0x7f800013,0xffc00057};
    if (sample < 72) {
        for (unsigned r = 0; r < 32; ++r) {
            const std::uint32_t v = edge[(sample + ((sample / 18) * r)) % 18];
            std::memcpy(c.vreg[r], &v, 4);
        }
    }
}
bool Correct(Fn a, Fn b, unsigned n, bool inject) {
    unsigned long long checks = 0;
    const std::uint64_t fpsrs[]{0,16,0x08000000,0x0800009f};
    for (unsigned mode = 0; mode < 32; ++mode) for (auto fs : fpsrs) for (unsigned sample = 0; sample < 256; ++sample) {
        GuestContext initial;
        Seed(initial, sample, mode, fs);
        GuestContext base = initial, candidate = initial;
        a(&base); b(&candidate);
        if (inject && !checks) candidate.vreg[0][0] ^= 1;
        if (std::memcmp(&base, &candidate, sizeof base)) {
            const auto* x = reinterpret_cast<const unsigned char*>(&base);
            const auto* y = reinterpret_cast<const unsigned char*>(&candidate);
            unsigned at = 0; while (at < sizeof base && x[at] == y[at]) ++at;
            std::printf("MISMATCH ops=%u mode=%u fpsr=%llx sample=%u offset=%u base=%u candidate=%u\n", n,mode,fs,sample,at,x[at],y[at]);
            return false;
        }
        ++checks;
    }
    std::printf("CORRECT ops=%u full_state_checks=%llu fpcr_modes=32 fpsr_states=4 samples_per_mode=256\n",n,checks);
    return true;
}
std::uint64_t Hash(const std::array<GuestContext,16>& contexts) {
    std::uint64_t h = 1469598103934665603ULL;
    for (const auto& c : contexts) {
        const auto* p = reinterpret_cast<const unsigned char*>(&c);
        for (std::size_t k = 0; k < sizeof c; ++k) { h ^= p[k]; h *= 1099511628211ULL; }
    }
    return h;
}
double Now() { LARGE_INTEGER x,f; QueryPerformanceCounter(&x); QueryPerformanceFrequency(&f); return double(x.QuadPart) / double(f.QuadPart); }
double Measure(Fn f, const std::array<GuestContext,16>& initial, unsigned repeats, std::uint64_t* checksum) {
    auto contexts = initial;
    const double begin = Now();
    for (unsigned k = 0; k < repeats; ++k) {
        for (unsigned j = 0; j < contexts.size(); ++j) {
            auto& c = contexts[j];
            // Reset only the outputs and sticky-status input. Sources are unchanged.
            std::memcpy(c.vreg, initial[j].vreg, sizeof c.vreg[0] * 8);
            c.fpsr = initial[j].fpsr;
            f(&c);
        }
    }
    const double elapsed = Now() - begin;
    *checksum = Hash(contexts);
    sink = sink ^ *checksum;
    return elapsed;
}
void NativeExtent(const char* name, Fn fn) {
    DWORD64 image = 0;
    auto* entry = RtlLookupFunctionEntry(reinterpret_cast<DWORD64>(fn), &image, nullptr);
    // A split function may have more than one unwind range. This is the range
    // containing its entry, not a total including split fragments/callees.
    std::printf("NATIVE_EXTENT function=%s unwind_bytes=%lu native_address=%p\n", name,
                entry ? entry->EndAddress - entry->BeginAddress : 0, reinterpret_cast<void*>(fn));
}
bool Bench(Fn a, Fn b, unsigned n, unsigned dataset, bool reverse) {
    std::array<GuestContext,16> initial{};
    for (unsigned j=0;j<initial.size();++j) {
        Seed(initial[j],1000+j,0,dataset==1?0:16);
        if (dataset==2) initial[j].fpcr = 1ULL << 32;
        for(unsigned r=0;r<32;++r) {
            const float v = (float((Next() % 8001) + 1) / 2048.0f) - 2.0f;
            std::uint32_t bits; std::memcpy(&bits,&v,4);
            initial[j].vreg[r][0] = bits;
            initial[j].vreg[r][1] = 0;
        }
    }
    auto ca=initial,cb=initial;
    for (unsigned j=0;j<initial.size();++j) {a(&ca[j]);b(&cb[j]);}
    if (std::memcmp(ca.data(),cb.data(),sizeof ca)) return false;
    std::uint64_t checksum = 0;
    Measure(a,initial,32,&checksum); Measure(b,initial,32,&checksum);
    unsigned repeats=1;
    double seconds=0;
    while (repeats < (1u<<22)) {
        seconds=Measure(a,initial,repeats,&checksum);
        if (seconds >= .05) break;
        repeats *= 2;
    }
    repeats=std::max(1u,static_cast<unsigned>(repeats*(.12/seconds)));
    const char* pattern=reverse?"BAABBAAB":"ABBAABBA";
    std::vector<double> ta,tb;
    std::uint64_t expected=Hash(ca);
    for(unsigned k=0;k<8;++k) {
        const bool baseline=pattern[k]=='A';
        const double time=Measure(baseline?a:b,initial,repeats,&checksum);
        if (checksum != expected) {std::puts("TIMED_OUTPUT_MISMATCH");return false;}
        (baseline?ta:tb).push_back(time);
        std::printf("TIMING ops=%u dataset=%u sequence=%u arm=%c calls=%u seconds=%.9f checksum=%016llx\n",n,dataset,k,pattern[k],repeats*16,time,checksum);
    }
    std::sort(ta.begin(),ta.end());std::sort(tb.begin(),tb.end());
    const double am=(ta[1]+ta[2])/2,bm=(tb[1]+tb[2])/2;
    std::printf("MEDIAN ops=%u dataset=%u baseline_ns=%.3f candidate_ns=%.3f ratio=%.6f\n",n,dataset,am*1e9/(repeats*16),bm*1e9/(repeats*16),bm/am);
    return true;
}
int main(int argc,char** argv) {
    if (argc > 2 || (argc == 2 && std::strcmp(argv[1],"--inject-mismatch") &&
        std::strcmp(argv[1],"--correct-only") && std::strcmp(argv[1],"--bench-only") &&
        std::strcmp(argv[1],"--bench-reverse"))) {
        std::fprintf(stderr,"usage: benchmark [--correct-only|--bench-only|--bench-reverse|--inject-mismatch]\n");
        return 2;
    }
    const unsigned csr=_mm_getcsr();
    _mm_setcsr((csr & 0x3fu) | 0x1f80u);
    std::printf("COMPILER_MSC_VER=%u context_bytes=%zu RECOMP_FPX_HOST=%u context_fm=%zu/%zu\n",_MSC_VER,sizeof(GuestContext),RECOMP_FPX_HOST,offsetof(GuestContext,fm_table),offsetof(GuestContext,fm_limit));
    NativeExtent("baseline16",baseline_16);NativeExtent("candidate16",candidate_16);
    NativeExtent("baseline122",baseline_122);NativeExtent("candidate122",candidate_122);
    NativeExtent("exact_add32",reinterpret_cast<Fn>(recomp_fp_add32_exact));
    NativeExtent("exact_sub32",reinterpret_cast<Fn>(recomp_fp_sub32_exact));
    NativeExtent("exact_mul32",reinterpret_cast<Fn>(recomp_fp_mul32_exact));
    const bool inject=argc==2&&std::strcmp(argv[1],"--inject-mismatch")==0;
    const bool only_correct=argc==2&&std::strcmp(argv[1],"--correct-only")==0;
    const bool reverse=argc==2&&std::strcmp(argv[1],"--bench-reverse")==0;
    const bool only_bench=reverse||(argc==2&&std::strcmp(argv[1],"--bench-only")==0);
    bool ok=only_bench||Correct(baseline_16,candidate_16,16,inject);
    if(ok&&!inject&&!only_bench)ok=Correct(baseline_122,candidate_122,122,false);
    if(ok&&!inject&&!only_correct)for(unsigned ds=0;ds<3&&ok;++ds) {ok=Bench(baseline_16,candidate_16,16,ds,reverse)&&Bench(baseline_122,candidate_122,122,ds,reverse);}
    _mm_setcsr(csr);
    return ok?0:1;
}
