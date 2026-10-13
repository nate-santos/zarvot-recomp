import hashlib,json,pathlib,re
root=pathlib.Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
same={}
for name in ['ops-{}.hpp','rt_{}.h','runtime-{}.c','exact-{}.c','shadow-{}.c','soft-{}.txt','wide-{}.txt','vector-{}.txt']:
    a=root/'gen'/name.format('baseline');b=root/'gen'/name.format('candidate')
    assert a.read_bytes()==b.read_bytes(),name
    same[name]=sha(a)
a=(root/'gen/baseline.c').read_text().replace('baseline','variant')
b=(root/'gen/candidate.c').read_text().replace('candidate','variant')
old_re=re.compile(r'\{ uint64_t _a=0,_b=0; memcpy\(&_a,([^,;]+),4\);( memcpy\(&_b,([^,;]+),4\);)?')
sites=[]
def replace(m):
    sites.append({'a':m[1],'b':m[3]})
    s='{ uint32_t _a32; memcpy(&_a32,'+m[1]+',4); '
    return s+('uint32_t _b32; memcpy(&_b32,'+m[3]+',4); uint64_t _a=_a32,_b=_b32;' if m[3] else 'uint64_t _a=_a32,_b=0;')
expected=old_re.sub(replace,a)
assert expected==b,'Unexpected generated change'
assert len(sites)==654+48+1,len(sites)
result={'unchanged':same,'changed_load_sites':len(sites),'normal_source_bytes':len(a),'candidate_source_bytes':len(b),'all_body_changes_are_only_expected_scalar32_load_prefix':True}
(root/'emission-isolation.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
