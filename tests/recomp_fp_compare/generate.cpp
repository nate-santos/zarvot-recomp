#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
#include "core/recompiler/arm64_to_c.h"
namespace sr=suyu::recomp;
struct Info { unsigned word,rn,rm,signal,zero,conditional,cond,nzcv; };
void Write(const std::filesystem::path& p,const std::string& s) {
    std::ofstream out(p,std::ios::binary); if(!out.write(s.data(),s.size())) throw std::runtime_error("write failed");
}
std::string Body(unsigned word) {
    bool miss=false; std::string s;
    if(!sr::Translate(word,0x1000,s,&miss)||miss) throw std::runtime_error("translation gap");
    return s;
}
Info Make(unsigned rn,unsigned rm,unsigned signal,unsigned zero,unsigned conditional,unsigned cond,unsigned nzcv) {
    unsigned word=conditional ? 0x1e200400u|(rm<<16)|(cond<<12)|(rn<<5)|(signal<<4)|nzcv
                              : 0x1e202000u|(rm<<16)|(rn<<5)|(signal<<4)|(zero<<3);
    return {word,rn,rm,signal,zero,conditional,cond,nzcv};
}
int main(int argc,char**argv) {
    if(argc!=2)return 2; const std::filesystem::path dir(argv[1]);
    std::filesystem::create_directories(dir);
#ifdef BENCH_CANDIDATE
    const std::string tag="candidate";
#else
    const std::string tag="baseline";
#endif
    sr::g_translate_all=true;sr::g_emit_fastmem=true;sr::g_emit_guard_gen=true;sr::g_emit_fpx=true;
    Write(dir/("rt_"+tag+".h"),sr::RuntimeH());
    Write(dir/("runtime-"+tag+".c"),sr::RuntimeC());
    Write(dir/("exact-"+tag+".c"),sr::FpxExactRuntimeC());
    Write(dir/("shadow-"+tag+".c"),sr::FpxShadowC());
    std::vector<Info> infos;
    const unsigned pairs[][2]={{1,2},{1,1},{31,2},{1,31},{31,31}};
    for(auto& pair:pairs)for(unsigned sig=0;sig<2;++sig) infos.push_back(Make(pair[0],pair[1],sig,0,0,0,0));
    for(unsigned rn:{1u,31u})for(unsigned sig=0;sig<2;++sig) infos.push_back(Make(rn,0,sig,1,0,0,0));
    for(unsigned cond=0;cond<16;++cond)for(unsigned nz=0;nz<16;++nz)for(unsigned sig=0;sig<2;++sig)
        infos.push_back(Make(1,2,sig,0,1,cond,nz));
    for(unsigned p=1;p<5;++p)for(unsigned cond=0;cond<16;++cond)for(unsigned sig=0;sig<2;++sig)
        infos.push_back(Make(pairs[p][0],pairs[p][1],sig,0,1,cond,(p+cond)&15));
    std::string metadata="#pragma once\n#include <stdint.h>\nstruct OpInfo {unsigned word,rn,rm,signal,zero,conditional,cond,nzcv;};\nstatic const OpInfo infos[]={\n";
    std::string code="#include \"rt_"+tag+".h\"\n#include <string.h>\n";
    std::string soft,wide,table="typedef void(*OpFn)(GuestContext*);\nconst OpFn ops_"+tag+"[]={\n";
    for(unsigned k=0;k<infos.size();++k) {
        auto& op=infos[k];
        metadata+="{"+std::to_string(op.word)+","+std::to_string(op.rn)+","+std::to_string(op.rm)+","+std::to_string(op.signal)+","+std::to_string(op.zero)+","+std::to_string(op.conditional)+","+std::to_string(op.cond)+","+std::to_string(op.nzcv)+"},\n";
        sr::g_emit_fpx=true;
        code+="static void "+tag+"_op"+std::to_string(k)+"(GuestContext*c){"+Body(op.word)+"}\n";
        table+=tag+"_op"+std::to_string(k)+",\n";
        sr::g_emit_fpx=false;soft+=Body(op.word)+"\n";
        sr::g_emit_fpx=true;wide+=Body(op.word|0x400000u)+"\n";
    }
    Write(dir/("ops-"+tag+".hpp"),metadata+"};\n#define NOPS "+std::to_string(infos.size())+"\n");
    Write(dir/("soft-"+tag+".txt"),soft);Write(dir/("wide-"+tag+".txt"),wide);
    std::string vector;
    for(unsigned word:{0x4e22e420u,0x6e22e420u,0x6ea2e420u,0x4ea0d820u,0x6ea0c820u,0x4ea0c820u}) vector+=Body(word)+"\n";
    Write(dir/("vector-"+tag+".txt"),vector);
    // Flags are consumed after every compare. All operands stay in guest
    // registers; no game words, data, memory callbacks or block code is used.
    for(unsigned kind=0;kind<3;++kind) {
        code+="__declspec(noinline) void "+tag+"_bench"+std::to_string(kind)+"(GuestContext*c){uint64_t acc=c->x[0];\n";
        for(unsigned k=0;k<16;++k) {
            unsigned rn=(k*2+1)%32,rm=(k*2+2)%32;
            auto op=Make(rn,kind==1?0:rm,k&1,kind==1,kind==2,k%14,(k*5)&15);
            code+=Body(op.word);
            code+="\nacc=(acc*33)^((uint64_t)c->n*8+(uint64_t)c->z*4+(uint64_t)c->c*2+c->v);\n";
        }
        code+="c->x[0]=acc;}\n";
    }
    std::string negative=Body(Make(1,2,1,0,0,0,0).word);
    const std::string from="if(1) c->fpsr|=1;";
    const size_t at=negative.find(from);
    if(at==std::string::npos||negative.find(from,at+1)!=std::string::npos)throw std::runtime_error("negative edit ambiguous");
    negative.replace(at,from.size(),"if(0) c->fpsr|=1;");
    code+="void "+tag+"_negative(GuestContext*c){"+negative+"}\n";
    Write(dir/(tag+".c"),code+table+"};\n");
    printf("GENERATED %s ops=%zu benchmark_kinds=3 comparisons_per_block=16\n",tag.c_str(),infos.size());
}
