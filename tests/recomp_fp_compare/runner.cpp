// Generic synthetic instructions only. The independent reference orders
// canonicalized IEEE bit patterns with monotonic integer keys.
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xmmintrin.h>
extern "C" {
#include "gen/rt_candidate.h"
typedef void(*OpFn)(GuestContext*);
extern const OpFn ops_baseline[],ops_candidate[];
void candidate_negative(GuestContext*);
void baseline_bench0(GuestContext*);void candidate_bench0(GuestContext*);
void baseline_bench1(GuestContext*);void candidate_bench1(GuestContext*);
void baseline_bench2(GuestContext*);void candidate_bench2(GuestContext*);
}
#include "gen/ops-candidate.hpp"
static uint64_t rng=UINT64_C(0x8d67e54fcd12a3b9),sink;
uint64_t Next(){rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;return rng;}
unsigned Flags(const GuestContext& c){return c.n*8+c.z*4+c.c*2+c.v;}
void SetFlags(GuestContext& c,unsigned nz){c.n=(nz>>3)&1;c.z=(nz>>2)&1;c.c=(nz>>1)&1;c.v=nz&1;}
bool Holds(unsigned cond,unsigned nz){
    const bool n=(nz&8)!=0,z=(nz&4)!=0,c=(nz&2)!=0,v=(nz&1)!=0;
    switch(cond){case 0:return z;case 1:return !z;case 2:return c;case 3:return !c;
    case 4:return n;case 5:return !n;case 6:return v;case 7:return !v;
    case 8:return c&&!z;case 9:return !c||z;case 10:return n==v;case 11:return n!=v;
    case 12:return !z&&n==v;case 13:return z||n!=v;default:return true;}
}
void Oracle(GuestContext& c,const OpInfo& op){
    if(op.conditional&&!Holds(op.cond,Flags(c))){SetFlags(c,op.nzcv);return;}
    uint32_t a,b=0;std::memcpy(&a,c.vreg[op.rn],4);
    if(!op.zero)std::memcpy(&b,c.vreg[op.rm],4);
    auto sub=[](uint32_t x){return (x&0x7f800000u)==0&&(x&0x7fffffu)!=0;};
    if(c.fpcr&(UINT64_C(1)<<24)){
        if(sub(a)){a&=0x80000000u;c.fpsr|=0x80;}
        if(sub(b)){b&=0x80000000u;c.fpsr|=0x80;}
    }
    auto nan=[](uint32_t x){return (x&0x7f800000u)==0x7f800000u&&(x&0x7fffffu)!=0;};
    const bool an=nan(a),bn=nan(b);
    if(an||bn){
        if(op.signal||(an&&!(a&0x400000u))||(bn&&!(b&0x400000u)))c.fpsr|=1;
        SetFlags(c,3);return;
    }
    if((a&0x7fffffffu)==0)a=0;
    if((b&0x7fffffffu)==0)b=0;
    const uint32_t ak=(a>>31)?~a:(a^0x80000000u),bk=(b>>31)?~b:(b^0x80000000u);
    SetFlags(c,ak==bk?6:ak<bk?8:2);
}
void Seed(GuestContext& c,unsigned mode,uint64_t fpsr,unsigned nz,uint32_t a,uint32_t b,const OpInfo& op){
    std::memset(&c,0xa5,sizeof c);c.pc=Next();c.x[0]=Next();
    c.vreg[op.rn][0]=Next();c.vreg[op.rn][1]=Next();
    c.vreg[op.rm][0]=Next();c.vreg[op.rm][1]=Next();
    c.fpcr=(uint64_t(mode&3)<<22)|((mode&4)?UINT64_C(1)<<24:0)|((mode&8)?UINT64_C(1)<<25:0)|((mode&16)?UINT64_C(1)<<32:0);
    c.fpsr=fpsr;SetFlags(c,nz);
    std::memcpy(c.vreg[op.rn],&a,4);
    if(!op.zero)std::memcpy(c.vreg[op.rm],&b,4);
}
bool Check(unsigned op,const GuestContext& in,uint64_t& checks){
    GuestContext a=in,b=in,expected=in;ops_baseline[op](&a);ops_candidate[op](&b);Oracle(expected,infos[op]);
    ++checks;
    if(std::memcmp(&a,&b,sizeof a)||std::memcmp(&b,&expected,sizeof b)){
        printf("MISMATCH op=%u word=%08x initial_flags=%x actual_flags=%x expected_flags=%x actual_fpsr=%llx expected_fpsr=%llx check=%llu\n",op,infos[op].word,Flags(in),Flags(b),Flags(expected),b.fpsr,expected.fpsr,checks);return false;
    }
    return true;
}
bool Explicit(){
    // Hard-coded expectations independently test oracle conventions, FZ,
    // signalling-vs-quiet forms and conditional suppression of FP effects.
    struct Test{unsigned op;uint32_t a,b;unsigned mode,nz,want;uint64_t fs,expected;};
    const Test tests[]={
        {0,0,0x80000000u,0,0,6,0,0},{0,0xbf800000u,0,0,0,8,0,0},
        {0,0x7f800000u,0x3f800000u,0,0,2,16,16},
        {0,0x7fc00001u,0x3f800000u,0,0,3,0,0},
        {0,0x7f800001u,0x3f800000u,0,0,3,0,1},
        {1,0x7fc00001u,0x3f800000u,0,0,3,0,1},
        {0,1,0,4,0,6,0,128},{0,0x80000001u,0,4,0,6,1,129},
        {0,1,0,0,0,2,0,0},
        {1,0x7fc00001u,1,4,0,3,0,129},
        // Conditional table begins at 14, cond EQ, literal 0, quiet/signalling.
        {14,0x7f800001u,1,4,0,0,16,16},
        {15,0x7fc00001u,1,4,0,0,16,16},
        {14,0x7f800001u,1,4,4,3,16,145},
        {15,0x7fc00001u,1,4,4,3,16,145},
    };
    unsigned count=0;
    for(auto& t:tests){
        GuestContext in,a,b,o;Seed(in,t.mode,t.fs,t.nz,t.a,t.b,infos[t.op]);a=b=o=in;
        ops_baseline[t.op](&a);ops_candidate[t.op](&b);Oracle(o,infos[t.op]);
        if(Flags(o)!=t.want||o.fpsr!=t.expected||std::memcmp(&a,&b,sizeof a)||std::memcmp(&b,&o,sizeof b)){
            printf("EXPLICIT_MISMATCH case=%u oracle_flags=%x wanted=%x oracle_fpsr=%llx wanted_fpsr=%llx\n",count,Flags(o),t.want,o.fpsr,t.expected);return false;
        }++count;
    }printf("EXPLICIT cases=%u passed\n",count);return true;
}
bool Correct(){
    if(!Explicit())return false;
    const uint64_t fpsrs[]={0,16,0x0800009f,UINT64_C(0xa55a000000000080)};
    const uint32_t pairs[][2]={{0,0x80000000u},{0x80000000u,0},{0x3f800000u,0x40000000u},
        {0xbf800000u,0xc0000000u},{0xbf800000u,0x3f800000u},{0x7f800000u,0xff800000u},
        {0x7fc00001u,0x3f800000u},{0x3f800000u,0x7fc00001u},{0x7f800001u,0x3f800000u},
        {0x3f800000u,0xff800001u},{0xffc00001u,0x7fc00001u},{0x7f800001u,1},
        {1,0},{0x807fffffu,0x80000000u},{0x007fffffu,0x00800000u},{0x7f7fffffu,0x7f800000u}};
    uint64_t checks=0;
    for(unsigned op=0;op<NOPS;++op)for(unsigned nz=0;nz<16;++nz)for(unsigned mode=0;mode<32;++mode)for(auto fs:fpsrs)for(auto& pair:pairs){
        GuestContext in;Seed(in,mode,fs,nz,pair[0],pair[1],infos[op]);if(!Check(op,in,checks))return false;
    }
    printf("MATRIX full_context_checks=%llu ops=%u incoming_nzcv=16 fpcr_modes=32 fpsr_states=4 pairs=16\n",checks,NOPS);
    const uint64_t matrix=checks;
    const uint32_t edges[]={0,0x80000000u,1,0x80000001u,0x007fffffu,0x807fffffu,0x00800000u,0x80800000u,
        0x3f800000u,0xbf800000u,0x3f800001u,0xbf800001u,0x7f7fffffu,0xff7fffffu,0x7f800000u,0xff800000u,
        0x7fc00001u,0xffc00001u,0x7f800001u,0xff800001u};
    // Full edge grid for ordinary/zero forms, then seeded raw random for every
    // conditional/literal/alias form. The earlier matrix fully crosses modes.
    for(unsigned op=0;op<NOPS;++op)for(unsigned sample=0;sample<(op<14?400u:256u);++sample){
        uint32_t a=op<14?edges[sample/20]:static_cast<uint32_t>(Next());
        uint32_t b=op<14?edges[sample%20]:static_cast<uint32_t>(Next());
        for(unsigned mode=0;mode<32;++mode){GuestContext in;Seed(in,mode,fpsrs[sample%4],sample%16,a,b,infos[op]);if(!Check(op,in,checks))return false;}
    }
    printf("EXTRA full_context_checks=%llu total=%llu edges=20x20 random_per_conditional=256\n",checks-matrix,checks);
    return true;
}
uint64_t Hash(const std::array<GuestContext,16>& x){uint64_t h=1469598103934665603ULL;for(auto& c:x){const auto*p=reinterpret_cast<const unsigned char*>(&c);for(unsigned k=0;k<sizeof c;++k){h^=p[k];h*=1099511628211ULL;}}return h;}
double Now(){LARGE_INTEGER t,f;QueryPerformanceCounter(&t);QueryPerformanceFrequency(&f);return double(t.QuadPart)/f.QuadPart;}
double Measure(OpFn fn,const std::array<GuestContext,16>& initial,unsigned repeats,uint64_t& checksum){
    auto contexts=initial;const double begin=Now();
    for(unsigned k=0;k<repeats;++k)for(unsigned j=0;j<contexts.size();++j){
        auto& c=contexts[j];c.x[0]=initial[j].x[0];c.fpsr=initial[j].fpsr;
        c.n=initial[j].n;c.z=initial[j].z;c.c=initial[j].c;c.v=initial[j].v;fn(&c);
    }
    const double seconds=Now()-begin;checksum=Hash(contexts);sink^=checksum;return seconds;
}
void Extent(const char* tag,OpFn fn){DWORD64 base=0;auto*p=RtlLookupFunctionEntry(reinterpret_cast<DWORD64>(fn),&base,nullptr);printf("EXTENT function=%s bytes=%u\n",tag,p?p->EndAddress-p->BeginAddress:0);}
bool Bench(unsigned kind,unsigned dataset,bool reverse){
    const OpFn a[]={baseline_bench0,baseline_bench1,baseline_bench2},b[]={candidate_bench0,candidate_bench1,candidate_bench2};
    const uint32_t finite[]={0x3f800000u,0xbf800000u,0x40000000u,0xc0000000u,0,0x80000000u,0x40400000u,0xc0400000u};
    const uint32_t exceptional[]={0x7fc00001u,0x7f800001u,0xff800001u,1,0x80000001u,0x007fffffu,0x80000000u,0x7f800000u};
    std::array<GuestContext,16> initial;
    for(unsigned j=0;j<initial.size();++j){Seed(initial[j],dataset?4:0,0,j,1,2,infos[0]);for(unsigned r=0;r<32;++r){const uint32_t v=(dataset?exceptional:finite)[(r+j)%8];std::memcpy(initial[j].vreg[r],&v,4);}}
    auto ca=initial,cb=initial;for(unsigned j=0;j<ca.size();++j){a[kind](&ca[j]);b[kind](&cb[j]);}if(std::memcmp(ca.data(),cb.data(),sizeof ca)){puts("BENCH_MISMATCH");return false;}
    uint64_t checksum=0;const auto expected=Hash(ca);Measure(a[kind],initial,32,checksum);Measure(b[kind],initial,32,checksum);
    unsigned repeats=1;double seconds=0;while(repeats<(1u<<22)){seconds=Measure(a[kind],initial,repeats,checksum);if(seconds>=.04)break;repeats*=2;}
    repeats=std::max(1u,static_cast<unsigned>(repeats*(.10/seconds)));
    const char*pattern=reverse?"BAABBAAB":"ABBAABBA";std::vector<double> ta,tb;
    for(unsigned k=0;k<8;++k){const bool base=pattern[k]=='A';const double elapsed=Measure(base?a[kind]:b[kind],initial,repeats,checksum);
        if(checksum!=expected){puts("TIMED_CHECKSUM_MISMATCH");return false;}(base?ta:tb).push_back(elapsed);
        printf("TIMING kind=%u dataset=%u sequence=%u arm=%c calls=%u seconds=%.9f checksum=%016llx\n",kind,dataset,k,pattern[k],repeats*16,elapsed,checksum);
    }
    std::sort(ta.begin(),ta.end());std::sort(tb.begin(),tb.end());const double am=(ta[1]+ta[2])/2,bm=(tb[1]+tb[2])/2;
    printf("MEDIAN kind=%u dataset=%u baseline_ns=%.6f candidate_ns=%.6f ratio=%.6f\n",kind,dataset,am*1e9/(repeats*16),bm*1e9/(repeats*16),bm/am);return true;
}
int main(int argc,char**argv){
    if(argc!=2){puts("usage: runner --correct|--negative|--bench|--bench-reverse");return 2;}
    printf("COMPILER=%u context_bytes=%zu ops=%u\n",_MSC_VER,sizeof(GuestContext),NOPS);
    if(!std::strcmp(argv[1],"--negative")){
        GuestContext in,expected,got;Seed(in,0,0,0,0x7fc00001u,0x3f800000u,infos[1]);got=expected=in;Oracle(expected,infos[1]);candidate_negative(&got);
        if(std::memcmp(&expected,&got,sizeof got)){printf("NEGATIVE_DETECTED omitted_FCMPE_IOC actual=%llx expected=%llx\n",got.fpsr,expected.fpsr);return 1;}puts("NEGATIVE_UNDETECTED");return 2;
    }
    if(!std::strcmp(argv[1],"--correct"))return Correct()?0:1;
    const bool reverse=!std::strcmp(argv[1],"--bench-reverse");if(!reverse&&std::strcmp(argv[1],"--bench"))return 2;
    Extent("baseline_reg",baseline_bench0);Extent("candidate_reg",candidate_bench0);Extent("baseline_zero",baseline_bench1);Extent("candidate_zero",candidate_bench1);Extent("baseline_cond",baseline_bench2);Extent("candidate_cond",candidate_bench2);
    const unsigned mxcsr=_mm_getcsr();_mm_setcsr((mxcsr&0x3fu)|0x1f80u);
    bool ok=true;for(unsigned kind=0;kind<3&&ok;++kind)for(unsigned dataset=0;dataset<2&&ok;++dataset)ok=Bench(kind,dataset,reverse);
    _mm_setcsr(mxcsr);return ok?0:1;
}
