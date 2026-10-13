import argparse,collections,hashlib,json,pathlib,re,statistics
root=pathlib.Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify_saved(directory):
    summary=json.loads((directory/'summary.json').read_text())
    assert summary['state']=='complete'
    for name,wanted in summary['evidence_sha256'].items():
        p=directory/name
        assert p.resolve().is_relative_to(directory.resolve()),name
        assert sha(p)==wanted,('changed evidence',name)
    reference=summary.get('timing_reference')
    if reference:
        other=pathlib.Path(reference['directory'])
        assert sha(other/'summary.json')==reference['summary_sha256']
        verify_saved(other)
    return summary
parser=argparse.ArgumentParser(description='Audit saved scalar compare prototype evidence')
parser.add_argument('--audit',action='store_true')
parser.add_argument('--timing-evidence',type=pathlib.Path)
args=parser.parse_args()
if args.audit:
    result=verify_saved(root)
    print(json.dumps({'state':'audit_passed','full_context_checks':result['full_context_checks'],'timing_mode':result['timing_mode']},indent=2))
    raise SystemExit(0)
snapshot=json.loads((root/'snapshot-metadata.json').read_text())
metadata=json.loads((root/'metadata.json').read_text(encoding='utf-8-sig'))
assert metadata['state']=='complete' and metadata['product_source_unchanged']
assert metadata['baseline_commit']==snapshot['baseline_commit']
validation=(root/'validation.log').read_text(encoding='utf-8-sig')
assert 'EXPLICIT cases=14 passed' in validation
assert 'MATRIX full_context_checks=21430272 ops=654 incoming_nzcv=16 fpcr_modes=32 fpsr_states=4 pairs=16' in validation
assert 'EXTRA full_context_checks=5422080 total=26852352 edges=20x20 random_per_conditional=256' in validation
assert 'NEGATIVE_DETECTED omitted_FCMPE_IOC actual=0 expected=1' in (root/'negative.log').read_text(encoding='utf-8-sig')
timings=[];extents={};quiet={};reference=None
timing_root=root
if args.timing_evidence:
    timing_root=args.timing_evidence.resolve()
    prior=verify_saved(timing_root)
    assert prior.get('timing_mode')!='referenced','Reference the original fresh timing result, not a referenced summary'
    assert all((timing_root/f'timing{i}.log').is_file() for i in (1,2,3)),'Referenced evidence must contain all three original timing logs'
    assert prior['timings'],'Referenced evidence has no timings'
    # Moving the fixture does not justify timing again. Reuse only identical
    # synthetic inputs and compiler listings; keep the original result separate.
    identity_files=['generate.cpp','runner.cpp','snapshot/core/recompiler/arm64_to_c.h','candidate_snapshot/core/recompiler/arm64_to_c.h','gen/baseline.c','gen/candidate.c','gen/rt_baseline.h','gen/rt_candidate.h','gen/ops-baseline.hpp','gen/ops-candidate.hpp']
    identities={}
    for name in identity_files:
        assert sha(root/name)==sha(timing_root/name),('timing inputs differ',name)
        identities[name]=sha(root/name)
    for tag in ['baseline','candidate']:
        first=(root/(tag+'.asm')).read_text().splitlines()[0]
        assert first==(timing_root/(tag+'.asm')).read_text().splitlines()[0],'Compiler versions differ'
    assert metadata['flags']==prior['flags'],'Compiler flags differ'
    reference={'directory':str(timing_root),'summary_sha256':sha(timing_root/'summary.json'),'identical_input_sha256':identities,'scope':'Existing timing executable/result; fresh build validates identical inputs without retiming'}
has_timing=(timing_root/'timing1.log').exists()
if not has_timing:
    assert not any((timing_root/f'timing{i}.log').exists() for i in [2,3]),'Partial timing logs'
for index in (range(1,4) if has_timing else []):
    name=f'timing{index}'
    log=(timing_root/(name+'.log')).read_text(encoding='utf-8-sig')
    groups=collections.defaultdict(list)
    for m in re.finditer(r'TIMING kind=(\d+) dataset=(\d+) sequence=(\d+) arm=([AB]) calls=(\d+) seconds=([0-9.]+) checksum=([0-9a-f]+)',log):
        kind,dataset,sequence,arm,calls,seconds,checksum=m.groups()
        groups[int(kind),int(dataset)].append({'sequence':int(sequence),'arm':arm,'calls':int(calls),'seconds':float(seconds),'checksum':checksum})
    assert len(groups)==6
    pattern='BAABBAAB' if index==2 else 'ABBAABBA'
    for key,rows in sorted(groups.items()):
        assert len(rows)==8
        for sequence,row in enumerate(rows):
            assert row['sequence']==sequence and row['arm']==pattern[sequence]
            assert row['calls']>0 and row['calls']==rows[0]['calls']
            assert row['checksum']==rows[0]['checksum']
        am=statistics.median(r['seconds'] for r in rows if r['arm']=='A')
        bm=statistics.median(r['seconds'] for r in rows if r['arm']=='B')
        timings.append({'pass':index,'kind':key[0],'dataset':key[1],'order':pattern,'calls_per_sample':rows[0]['calls'],'checksum':rows[0]['checksum'],'baseline_ns':am*1e9/rows[0]['calls'],'candidate_ns':bm*1e9/rows[0]['calls'],'ratio':bm/am})
    for tag,size in re.findall(r'EXTENT function=(\w+) bytes=(\d+)',log):
        assert int(size)>0
        if tag in extents:assert extents[tag]==int(size)
        extents[tag]=int(size)
    for when in ['before','after']:
        quiet[name+'-'+when]=json.loads((timing_root/(name+'-quiet-'+when+'.json')).read_text(encoding='utf-8-sig'))
        assert quiet[name+'-'+when]['busy']==[]
assembly={}
for tag in ['baseline','candidate']:
    asm=(root/(tag+'.asm')).read_text()
    for kind in range(3):
        function=f'{tag}_bench{kind}'
        body=re.search(r'(?ms)^'+function+r' PROC\b.*?^'+function+r' ENDP\b',asm).group()
        consumption=len(re.findall(r'\bimul\s+[^\r\n]*, 33\b',body))
        assert consumption==16,(function,consumption)
        counts={
            'flag_consumption_imul33_steps':consumption,
            'wide_operand_stack_stores':len(re.findall(r'\bmov\s+QWORD PTR _[ab]\$\d+\[rsp\],',body)),
            'partial_operand_stack_stores':len(re.findall(r'\bmov\s+DWORD PTR _[ab]\$\d+\[rsp\],',body)),
            'wide_operand_stack_reload_instructions':len(re.findall(r'\bmov\s+\w+, QWORD PTR _[ab]\$\d+\[rsp\]',body)),
        }
        if tag=='candidate':assert counts['wide_operand_stack_stores']==counts['partial_operand_stack_stores']==counts['wide_operand_stack_reload_instructions']==0
        assembly[function]=counts
ranges=[]
for kind in range(3):
    for dataset in range(2):
        rows=[r for r in timings if r['kind']==kind and r['dataset']==dataset]
        if rows:ranges.append({'kind':kind,'dataset':dataset,'ratio_min':min(r['ratio'] for r in rows),'ratio_max':max(r['ratio'] for r in rows),'ratio_median':statistics.median(r['ratio'] for r in rows)})
hashes={str(p.relative_to(root)).replace('\\','/'):sha(p) for p in sorted(root.rglob('*')) if p.is_file() and p.name not in ['summary.json','analysis.log']}
summary={'state':'complete','product_source_unchanged':True,'snapshot':snapshot,'full_context_checks':26852352,'hard_coded_expected_cases':14,'negative_control_expected_exit':1,'emission_isolation':json.loads((root/'emission-isolation.json').read_text()),'compiler_listing':(root/'baseline.asm').read_text().splitlines()[0],'flags':metadata['flags'],'timing_mode':'referenced' if reference else 'fresh' if has_timing else 'not_requested','timing_reference':reference,'timings':timings,'ranges':ranges,'entry_unwind_bytes':extents,'assembly':assembly,'quiet_snapshots':quiet,'evidence_sha256':hashes,'limitations':['Generic synthetic instructions only; no game code executed and no game FPS result.','Baseline and candidate use real Translate; the independently implemented oracle is not ARM hardware/golden validation.','One deterministic random stream. Register0 appears in differential timing validation but not the independent single-op oracle cases.','Conditional explicit hard-coded expectations use EQ; exhaustive conditions including AL/NV use the independent condition oracle.','Timing includes the same flag consumption and per-call NZCV/FPSR/output reset work; excludes dispatch, guards, guest memory, and game scene effects.','Assembly counts are compiler listings; extents are linked entry unwind ranges, excluding split fragments and callees.','Quiet snapshots cover named game/build/recorder processes, not every source of system load.','Prototype remains isolated; product source and completed game module sets unchanged.']}
(root/'summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({'state':summary['state'],'full_context_checks':summary['full_context_checks'],'ranges':ranges,'assembly':assembly,'entry_unwind_bytes':extents},indent=2))
