import hashlib, json, pathlib
root=pathlib.Path(__file__).resolve().parent
old=(root/'snapshot/core/recompiler/arm64_to_c.h').read_bytes()
text=old.decode('utf-8')
before='''    return "{ uint64_t _a=0,_b=0; memcpy(&_a," + a + "," + sz + ");" +
        (b.empty() ? std::string() : " memcpy(&_b," + b + "," + sz + ");") +
        " const uint64_t _sign="'''
after='''    std::string loads = "{ uint64_t _a=0,_b=0; memcpy(&_a," + a + "," + sz + ");" +
        (b.empty() ? std::string() : " memcpy(&_b," + b + "," + sz + ");");
    if (g_emit_fpx && !dbl) {
        loads = "{ uint32_t _a32; memcpy(&_a32," + a + ",4); ";
        if (b.empty()) loads += "uint64_t _a=_a32,_b=0;";
        else loads += "uint32_t _b32; memcpy(&_b32," + b +
            ",4); uint64_t _a=_a32,_b=_b32;";
    }
    return loads +
        " const uint64_t _sign="'''
newline='\r\n' if '\r\n' in text else '\n'
before=before.replace('\n',newline);after=after.replace('\n',newline)
assert text.count(before)==1
new=text.replace(before,after)
(root/'candidate_snapshot/core/recompiler/arm64_to_c.h').write_bytes(new.encode('utf-8'))
assert new.replace(after,before)==text
identity=json.loads((root/'metadata.json').read_text(encoding='utf-8-sig'))
(root/'snapshot-metadata.json').write_text(json.dumps({'baseline_commit':identity['baseline_commit'],'baseline_sha256':hashlib.sha256(old).hexdigest(),'candidate_sha256':hashlib.sha256(new.encode('utf-8')).hexdigest(),'scope':'Only EmitFPCompareFlags input prefix; g_emit_fpx && !dbl; isolated width-copy prototype; product core unchanged'},indent=2))
print('isolated snapshot prepared')
