#define NOMINMAX
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "recomp_runtime.h"
#ifdef _WIN32
#include <windows.h>
#endif
using Load = uint64_t (*)(GuestContext*, uint64_t);
using Gate = uintptr_t (*)(GuestContext*, uint64_t, unsigned);
extern "C" {
#define DECLARE(t) uint64_t t##_recomp_load32(GuestContext*,uint64_t); uint64_t t##_recomp_load64(GuestContext*,uint64_t); uintptr_t t##_gate(GuestContext*,uint64_t,unsigned);
DECLARE(baseline) DECLARE(aligned) DECLARE(reversed) DECLARE(combined) DECLARE(masked)
}
struct Leg { const char* name; Load load32, load64; Gate gate; };
#define LEG(t) {#t,t##_recomp_load32,t##_recomp_load64,t##_gate}
static const Leg legs[]{LEG(baseline), LEG(aligned), LEG(reversed), LEG(combined), LEG(masked)};
struct Entry { uintptr_t ptr; uint64_t block, address, watch; };
static constexpr unsigned First = 16, Pages = 128, Count = First + Pages;
static std::array<Entry,Count> table{};
static std::array<std::array<unsigned char,4096>,Pages> memory{};
static RecompHostMem bridge{};
static GuestContext context{};
static uint64_t random_state = UINT64_C(0x27fce12309abd);
static uint64_t Random() { random_state ^= random_state>>12; random_state ^= random_state<<25; random_state ^= random_state>>27; return random_state*UINT64_C(0x2545f4914f6cdd1d); }
static uint64_t Read(uint64_t a, unsigned size) {
    a &= UINT64_C(0xffffffffffff);
    uint64_t result=0;
    for (unsigned j=0;j<size;++j) {
        const uint64_t b=(a+j)&UINT64_C(0xffffffffffff);
        const auto page=b>>12;
        if (page>=First && page<Count) result |= uint64_t(memory[page-First][b&4095]) << (j*8);
    }
    return result;
}
struct Event {uint64_t address,value; uint32_t size;};
static std::vector<Event> events;
static uint64_t Callback(void*,uint64_t a,uint32_t size) {
    const auto value=Read(a,size); events.push_back({a,value,size}); return value;
}
static void Setup() {
    for (unsigned p=0;p<Pages;++p) {
        for (auto& byte:memory[p]) byte=static_cast<unsigned char>(Random());
        table[First+p].ptr=(reinterpret_cast<uintptr_t>(memory[p].data())-uint64_t(First+p)*4096)|1;
    }
    bridge.load=Callback; bridge.page_entries=table.data(); bridge.page_entry_stride=sizeof(Entry);
    bridge.page_bits=12; bridge.pointer_mask=~uint64_t(3); bridge.address_space_max=uint64_t(Count)*4096;
    context.host_mem=&bridge; context.fm_table=reinterpret_cast<const unsigned char*>(table.data());
    context.fm_limit=bridge.address_space_max; context.fpcr=0x1234; context.fpsr=0x5678;
}
static uintptr_t OracleGate(uint64_t a,unsigned size) {
    if (a>=context.fm_limit || (a&4095)+size>4096) return 0;
    return table[a>>12].ptr & ~uintptr_t(3);
}
static bool Correct(const char* inject) {
    uint64_t checks=0;
    // Check the offset identity independently of pointer width or table size.
    for(unsigned i=0;i<100000;++i) {
        const uint64_t va=i<64 ? uint64_t(1)<<i : Random();
        const uint64_t expected=(va/4096)*32, masked=(va&~uint64_t(4095))>>7;
        if(expected!=masked || uint32_t(uint32_t(va>>12)<<5)!=uint32_t(masked)) return false;
        ++checks;
    }
    context.fm_limit=0;
    context.fm_table=nullptr;
    for(unsigned size:{1u,2u,4u,8u,16u}) for(uint64_t a:{uint64_t(0),uint64_t(1),uint64_t(4095),UINT64_MAX})
        for(const auto& leg:legs) {if(leg.gate(&context,a,size)!=0)return false;++checks;}
    context.fm_table=reinterpret_cast<const unsigned char*>(table.data());
    const std::array<uint64_t,9> limits{0,First*4096,First*4096+4096,(Count-1)*4096,Count*4096,
                                      4096,8192,0,Count*4096};
    for (auto limit:limits) {
        context.fm_limit=limit;
        for (unsigned mode=0;mode<4;++mode) {
            table[First+1].ptr=mode==0 ? (reinterpret_cast<uintptr_t>(memory[1].data())-uint64_t(First+1)*4096)|1 : mode-1;
            for (unsigned size:{1u,2u,4u,8u,16u}) for (uint64_t a:std::array<uint64_t,12>{0,First*4096,First*4096+1,(First+1)*4096-1,(First+1)*4096-size,(First+1)*4096-size+1,(First+2)*4096-1,Count*4096-1,Count*4096,UINT64_MAX,UINT64_MAX-7,UINT64_C(0xff00000000010001)}) {
                for (const auto& leg:legs) { if (leg.gate(&context,a,size)!=OracleGate(a,size)) return false; ++checks; }
            }
        }
    }
    context.fm_limit=bridge.address_space_max;
    table[First+1].ptr=(reinterpret_cast<uintptr_t>(memory[1].data())-uint64_t(First+1)*4096)|1;
    for (unsigned i=0;i<100000;++i) {
        uint64_t a=(uint64_t(First+(Random()%Pages))<<12)+(Random()%4096);
        if (i%11==0) a |= (Random()&0xffff)<<48;
        if (i%17==0) a=UINT64_MAX-(Random()%24);
        if (i%7==0) a=(a&~uint64_t(4095))+4093;
        context.fm_limit=i%5==0 ? 0 : bridge.address_space_max;
        const auto before=context;
        for (unsigned size:{4u,8u}) {
            std::vector<Event> reference;
            for (unsigned l=0;l<std::size(legs);++l) {
                events.clear();
                uint64_t result=(size==4?legs[l].load32:legs[l].load64)(&context,a);
                if (l==1 && i==0 && inject && std::strcmp(inject,"--inject-value")==0) result^=1;
                if (l==1 && i==0 && inject && std::strcmp(inject,"--inject-callback")==0) events.push_back({1,2,4});
                if (result!=Read(a,size) || std::memcmp(&before,&context,sizeof context)) return false;
                if (l==0) reference=events;
                else {
                    if (reference.size()!=events.size()) return false;
                    for(unsigned e=0;e<events.size();++e) if(reference[e].address!=events[e].address || reference[e].size!=events[e].size || reference[e].value!=events[e].value) return false;
                }
                ++checks;
            }
        }
    }
    std::printf("CORRECT checks=%llu; values, gate oracle, callbacks and full context agree\n",static_cast<unsigned long long>(checks));
    return true;
}
static volatile uint64_t sink;
struct Dataset { const char* name; unsigned pages, alignment; bool disabled; };
static void Benchmark(const Dataset& dataset, unsigned size, unsigned candidate) {
    Setup();
    std::vector<uint64_t> addresses;
    for (unsigned page=0;page<dataset.pages;++page) for(unsigned slot=0;slot<32;++slot) {
        const unsigned skew=dataset.alignment==0 ? 0 : dataset.alignment==1 ? 1 : slot%2;
        addresses.push_back(uint64_t(First+page)*4096+slot*64+skew);
    }
    // A deterministic shuffled pointer cycle makes the next load depend on the last.
    for (size_t i=addresses.size()-1;i>0;--i) std::swap(addresses[i],addresses[Random()%(i+1)]);
    for (size_t i=0;i<addresses.size();++i) {
        const uint64_t next=addresses[(i+1)%addresses.size()];
        auto& page=memory[(addresses[i]>>12)-First];
        std::memcpy(page.data()+(addresses[i]&4095),&next,size);
    }
    context.fm_limit=dataset.disabled ? 0 : bridge.address_space_max;
    const auto a=size==4?legs[0].load32:legs[0].load64;
    const auto b=size==4?legs[candidate].load32:legs[candidate].load64;
    auto measure=[&](Load load,uint64_t repeats) {
        uint64_t address=addresses[0];
        const auto start=std::chrono::steady_clock::now();
        for(uint64_t i=0;i<repeats;++i) for(size_t j=0;j<addresses.size();++j) address=load(&context,address);
        const double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
        sink=address;
        if(address!=addresses[0] || !events.empty()) {std::puts("TIMED_OUTPUT_MISMATCH");std::exit(1);}
        return elapsed;
    };
    events.clear(); measure(a,2); measure(b,2);
    uint64_t repeats=1;
    double elapsed=0;
    while(repeats<(1u<<24)) {elapsed=measure(a,repeats);if(elapsed>.02)break;repeats*=2;}
    repeats=std::max<uint64_t>(1,static_cast<uint64_t>(repeats*(.06/elapsed)));
    std::vector<double> ta,tb;
    const char* order="ABBAABBA";
    for(unsigned i=0;i<8;++i) {
        const bool base=order[i]=='A'; const double seconds=measure(base?a:b,repeats);
        (base?ta:tb).push_back(seconds);
        std::printf("TIMING variant=%s dataset=%s bytes=%u arm=%c sequence=%u calls=%llu seconds=%.9f\n",legs[candidate].name,dataset.name,size,order[i],i,
                    static_cast<unsigned long long>(repeats*addresses.size()),seconds);
    }
    std::sort(ta.begin(),ta.end());std::sort(tb.begin(),tb.end());
    const double am=(ta[1]+ta[2])/2,bm=(tb[1]+tb[2])/2,calls=double(repeats*addresses.size());
    std::printf("MEDIAN variant=%s dataset=%s bytes=%u baseline_ns=%.3f candidate_ns=%.3f ratio=%.6f baseline_spread=%.6f\n",legs[candidate].name,dataset.name,size,am*1e9/calls,bm*1e9/calls,bm/am,ta.back()/ta.front());
}
int main(int argc,char** argv) {
    Setup();
    const char* option=argc>1?argv[1]:"--correct-only";
    const bool bench=std::strcmp(option,"--bench-only")==0, reverse=std::strcmp(option,"--bench-reverse")==0;
    if(argc>2 || (!bench && !reverse && std::strcmp(option,"--correct-only") &&
                 std::strcmp(option,"--inject-value") && std::strcmp(option,"--inject-callback"))) return 2;
    if(!bench && !reverse) {
        if(!Correct(option)) {std::puts("MISMATCH detected");return 1;}
        return 0;
    }
    const Dataset datasets[]{{"hot-aligned",1,0,false},{"hot-unaligned",1,1,false},{"hot-mixed",1,2,false},
                             {"spread-aligned",128,0,false},{"spread-mixed",128,2,false},{"disabled",1,0,true}};
    for(unsigned step=1;step<std::size(legs);++step) {
        const unsigned candidate=reverse ? unsigned(std::size(legs))-step : step;
        for(const auto& dataset:datasets) for(unsigned size:{4u,8u}) Benchmark(dataset,size,candidate);
    }
    return 0;
}
