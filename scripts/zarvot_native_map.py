#!/usr/bin/env python3
"""Map saved native CPU samples through a verified recomp image's existing index.

Windows CLI; Python standard library only. Calls image metadata exports in this
separate process, never generated blocks, the game, ETW, or controller input.
All address-bearing output must be under this checkout's ignored build/local/
generated directories. See --help. Native samples are not guest instruction PCs.
"""
import argparse
import collections
import csv
import ctypes
import datetime
import hashlib
import json
import mmap
import ntpath
import pathlib
import re
import struct


def sha256(path):
    result = hashlib.sha256()
    with open(path, 'rb') as stream:
        while chunk := stream.read(4 * 1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def normalize_path(value):
    return ntpath.normcase(ntpath.normpath(str(value)))


def utc(value):
    parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Expected an explicit timezone')
    return parsed.astimezone(datetime.timezone.utc)


class PE:
    """Read-only PE32+ view; executable and unwind spans are half-open."""
    def __init__(self, data):
        self.data = data
        if data[:2] != b'MZ':
            raise ValueError('Expected a PE image')
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        if data[pe:pe + 4] != b'PE\0\0':
            raise ValueError('Invalid PE signature')
        machine, count, self.timestamp, _, _, optsize, _ = struct.unpack_from('<HHIIIHH', data, pe + 4)
        opt = pe + 24
        if machine != 0x8664 or struct.unpack_from('<H', data, opt)[0] != 0x20b:
            raise ValueError('Expected an x64 PE32+ image')
        if optsize < 112 + 7 * 8:
            raise ValueError('Missing PE data directories')
        self.base = struct.unpack_from('<Q', data, opt + 24)[0]
        self.size = struct.unpack_from('<I', data, opt + 56)[0]
        self.sections = []
        for i in range(count):
            p = opt + optsize + i * 40
            vsize, rva, raw_size, raw = struct.unpack_from('<IIII', data, p + 8)
            if raw + raw_size > len(data) or rva + vsize > self.size:
                raise ValueError('PE section extends outside the image')
            self.sections.append(dict(name=data[p:p + 8].rstrip(b'\0').decode('ascii'),
                                      start=rva, end=rva + vsize, raw=raw, raw_size=raw_size,
                                      executable=bool(struct.unpack_from('<I', data, p + 36)[0] & 0x20000000)))
        self.directories = [struct.unpack_from('<II', data, opt + 112 + 8 * i)
                            for i in range(min(16, (optsize - 112) // 8))]
        rva, size = self.directories[3]
        if size % 12:
            raise ValueError('Malformed x64 exception directory')
        self.unwind = UnwindRanges(data, self.offset(rva, size), size // 12) if size else UnwindRanges(b'', 0, 0)
        self.exports = self.read_exports()

    def offset(self, rva, size=1):
        for section in self.sections:
            if section['start'] <= rva and rva + size <= section['start'] + section['raw_size']:
                return section['raw'] + rva - section['start']
        raise ValueError('RVA is not backed by the PE file')

    def executable(self, rva):
        return any(s['executable'] and s['start'] <= rva < s['end'] for s in self.sections)

    def read_exports(self):
        rva, size = self.directories[0]
        if not size:
            return []
        p = self.offset(rva, 40)
        _, count, functions, names, ordinals = struct.unpack_from('<IIIII', self.data, p + 20)
        result = []
        for i in range(count):
            name_rva = struct.unpack_from('<I', self.data, self.offset(names + 4 * i, 4))[0]
            ordinal = struct.unpack_from('<H', self.data, self.offset(ordinals + 2 * i, 2))[0]
            fn = struct.unpack_from('<I', self.data, self.offset(functions + 4 * ordinal, 4))[0]
            if rva <= fn < rva + size:  # forwarded export
                continue
            begin = self.offset(name_rva)
            end = self.data.find(b'\0', begin, min(len(self.data), begin + 4096))
            if end < 0:
                raise ValueError('Unterminated export name')
            result.append(dict(name=self.data[begin:end].decode('ascii'), rva=fn))
        return result


class UnwindRanges:
    """Binary search validated .pdata entries without materializing millions of tuples."""
    def __init__(self, data, offset, count):
        self.data, self.offset, self.count = data, offset, count
        if offset + 12 * count > len(data):
            raise ValueError('Exception directory exceeds file')
        previous_end = -1
        for i in range(count):
            begin, end = struct.unpack_from('<II', data, offset + 12 * i)
            if begin >= end or begin < previous_end:
                raise ValueError('Unwind ranges overlap or are unsorted')
            previous_end = end

    def find(self, rva):
        lo, hi = 0, self.count
        while lo < hi:
            middle = (lo + hi) // 2
            begin = struct.unpack_from('<I', self.data, self.offset + 12 * middle)[0]
            if begin <= rva:
                lo = middle + 1
            else:
                hi = middle
        if not lo:
            return None
        begin, end = struct.unpack_from('<II', self.data, self.offset + 12 * (lo - 1))
        return (begin, end) if rva < end else None


def code_sections_from_coff(data):
    """Return function COMDAT bytes/masks for ordinary COFF and MSVC /bigobj."""
    if data[:4] == b'\0\0\xff\xff':
        if struct.unpack_from('<H', data, 6)[0] != 0x8664:
            raise ValueError('Expected x64 COFF /bigobj')
        count, symbols, symbol_count = struct.unpack_from('<III', data, 44)
        header, stride, fields = 56, 20, '<IiHBB'
    else:
        machine, count, _, symbols, symbol_count, optsize, _ = struct.unpack_from('<HHIIIHH', data)
        if machine != 0x8664:
            raise ValueError('Expected x64 COFF')
        header, stride, fields = 20 + optsize, 18, '<IhHBB'
    string_base = symbols + stride * symbol_count
    if string_base + 4 > len(data) or header + count * 40 > len(data):
        raise ValueError('COFF tables extend outside file')
    string_size = struct.unpack_from('<I', data, string_base)[0]
    if string_base + string_size > len(data):
        raise ValueError('COFF string table exceeds file')

    def symbol_name(raw):
        if raw[:4] != b'\0\0\0\0':
            return raw.rstrip(b'\0').decode('ascii')
        p = string_base + struct.unpack_from('<I', raw, 4)[0]
        if not string_base + 4 <= p < string_base + string_size:
            raise ValueError('Invalid COFF string offset')
        end = data.find(b'\0', p, string_base + string_size)
        if end < 0:
            raise ValueError('Unterminated COFF symbol name')
        return data[p:end].decode('ascii')

    sections = []
    for i in range(count):
        p = header + 40 * i
        size, raw, relocations = struct.unpack_from('<III', data, p + 16)
        relocation_count = struct.unpack_from('<H', data, p + 32)[0]
        sections.append(dict(size=size, raw=raw, relocations=relocations,
                             relocation_count=relocation_count,
                             executable=bool(struct.unpack_from('<I', data, p + 36)[0] & 0x20000000), names=[]))
    i = 0
    while i < symbol_count:
        p = symbols + stride * i
        value, section, typ, _, aux = struct.unpack_from(fields, data, p + 8)
        if section > 0 and typ & 0x20 and value == 0:
            if section > count:
                raise ValueError('COFF symbol names a nonexistent section')
            sections[section - 1]['names'].append(symbol_name(data[p:p + 8]))
        i += 1 + aux
        if i > symbol_count:
            raise ValueError('COFF auxiliary entries exceed symbol table')
    result = []
    relocation_sizes = {1: 8, 2: 4, 3: 4, 4: 4, 5: 4, 6: 4, 7: 4, 8: 4, 9: 4, 10: 2, 11: 4}
    for section in sections:
        if not section['executable'] or not section['names'] or not section['size']:
            continue
        size, p = section['size'], section['raw']
        if p + size > len(data):
            raise ValueError('COFF code exceeds file')
        mask = bytearray(b'\1' * size)
        supported = True
        for i in range(section['relocation_count']):
            rva, _, typ = struct.unpack_from('<IIH', data, section['relocations'] + 10 * i)
            length = relocation_sizes.get(typ)
            if length is None:
                supported = False
                break
            if rva + length > size:
                raise ValueError('COFF relocation exceeds section')
            mask[rva:rva + length] = b'\0' * length
        if supported:
            result.append(dict(code=data[p:p + size], mask=mask, names=sorted(set(section['names'])),
                               relocation_count=section['relocation_count']))
    return result


def masked_matches(code, mask, haystack, minimum_anchor=16):
    """Match every nonrelocated byte; preserve every candidate instead of picking one."""
    if len(code) != len(mask):
        raise ValueError('Code/mask length mismatch')
    runs = []
    start = None
    for i, flag in enumerate(mask + b'\0'):
        if flag and start is None:
            start = i
        if not flag and start is not None:
            runs.append((start, i))
            start = None
    if not runs:
        return []
    lo, hi = max(runs, key=lambda span: span[1] - span[0])
    if hi - lo < minimum_anchor:
        return []
    needle, result = code[lo:hi], []
    p = haystack.find(needle)
    while p >= 0:
        begin = p - lo
        if begin >= 0 and begin + len(code) <= len(haystack):
            if all(not flag or code[i] == haystack[begin + i] for i, flag in enumerate(mask)):
                result.append(begin)
        p = haystack.find(needle, p + 1)
    return result


def collect_guest_spans(index, guest_lo, image_base, requested, executable):
    """Consecutive equal pointers form inclusive guest-word spans; retain ICF aliases."""
    result = collections.defaultdict(list)
    previous, first = None, 0

    def finish(end):
        if previous and previous - image_base in requested:
            result[previous - image_base].append((guest_lo + 4 * first, guest_lo + 4 * (end - 1)))

    for i, pointer in enumerate(index):
        if pointer == previous:
            continue
        if previous is not None:
            finish(i)
        if pointer and not executable(pointer - image_base):
            raise ValueError('Index pointer is outside executable image sections')
        previous, first = pointer, i
    if previous is not None:
        finish(len(index))
    return dict(result)


def verify_inputs(launch, analysis, image, module, manifest_path):
    matches = [entry for entry in launch['modules'] if entry['name'] == module]
    if len(matches) != 1 or matches[0]['state'] != 'complete' or launch['image_abi'] != 6:
        raise ValueError('Expected a complete recorded ABI 6 module')
    if image.stat().st_size != matches[0]['bytes'] or sha256(image) != matches[0]['sha256']:
        raise ValueError('Image does not match the recorded build hash/size')
    if sha256(manifest_path) != launch['export_manifest_sha256']:
        raise ValueError('Export manifest differs from the recorded image set')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    if manifest['image_abi'] != launch['image_abi'] or manifest['image_features'] != launch['image_features']:
        raise ValueError('Manifest ABI/features differ from the recorded image set')
    expected_host = ntpath.join(launch['run_root'], 'suyu-cmd.exe')
    if analysis['state'] != 'complete' or analysis['expected_pid'] != launch['pid']:
        raise ValueError('CPU export is incomplete or from another PID')
    if normalize_path(analysis['expected_executable']) != normalize_path(expected_host):
        raise ValueError('CPU export belongs to another executable')
    if utc(analysis['process_started_utc']) != utc(launch['process_started_utc']):
        raise ValueError('CPU export belongs to another process start')
    text = [entry for entry in manifest['modules'] if entry['name'] == module]
    if len(text) != 1:
        raise ValueError('Manifest does not identify exactly one selected module')
    return matches[0], text[0]


def recorded_target(record):
    """Old baseline records omitted target; other missing/invalid values never default."""
    target = record.get('target', 'zarvot')
    reserved = {'con', 'prn', 'aux', 'nul'} | {f'{kind}{i}' for kind in ('com', 'lpt') for i in range(1, 10)}
    if not isinstance(target, str) or not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}', target) or target in reserved:
        raise ValueError('Recorded target must be a valid project build directory name')
    return target


def build_record_path(root, launch):
    target = recorded_target(launch)
    builds = (root / 'build/recomp').resolve()
    path = (builds / target / 'build-status.json').resolve()
    if not builds.is_relative_to(root.resolve()) or path.parent.parent != builds:
        raise ValueError('Build record resolves outside the project recomp build directory')
    return target, path


def verify_build_record(launch, build, module):
    """Anchor the recorded launch to the project's completed module-set evidence."""
    if recorded_target(launch) != recorded_target(build):
        raise ValueError('Launch target differs from the completed project build record')
    if build['state'] != 'complete' or any(launch[key] != build[key] for key in ('image_abi', 'image_features', 'export_manifest_sha256')):
        raise ValueError('Launch differs from the completed project build record')
    recorded = [entry for entry in launch['modules'] if entry['name'] == module]
    completed = [entry for entry in build['modules'] if entry['name'] == module]
    if (len(recorded) != 1 or len(completed) != 1 or
            recorded[0].get('state') != 'complete' or completed[0].get('state') != 'complete' or
            any(recorded[0][key] != completed[0][key] for key in ('sha256', 'bytes'))):
        raise ValueError('Selected image differs from the completed project build record')


def sample_counts(path, module_path, pe, expected_rows, expected_pid=None, image_maps=None):
    counts, weights = collections.Counter(), collections.Counter()
    total = 0
    image_name = ntpath.basename(module_path)
    with open(path, encoding='utf-8-sig', newline='') as source:
        for row in csv.DictReader(source):
            total += 1
            if normalize_path(row['module']) != module_path:
                if ntpath.basename(row['module']).lower() == image_name:
                    raise ValueError('Sample module basename matches but full path is foreign')
                continue
            rva = int(row['native_rva'], 16)
            if not 0 <= rva < pe.size:
                raise ValueError('Native sample RVA is outside the verified image')
            if expected_pid is not None and int(row['pid']) != expected_pid:
                raise ValueError('Selected module sample belongs to another PID')
            if image_maps is not None:
                time = float(row['trace_seconds'])
                active = [entry for entry in image_maps if float(entry['loaded_seconds']) <= time < float(entry['unloaded_seconds'])]
                if len(active) != 1 or int(row['instruction_pointer'], 16) != int(active[0]['image_base'], 16) + rva:
                    raise ValueError('Sample IP/RVA differs from its loaded image interval')
            counts[rva] += 1
            weights[rva] += int(row['reported_count'])
    if total != expected_rows:
        raise ValueError('Sample file row count differs from completed analysis')
    return counts, weights, total


def load_index(image, pe, requested, expected_abi):
    if not hasattr(ctypes, 'WinDLL'):
        raise RuntimeError('Image metadata extraction requires Windows')
    if ctypes.sizeof(ctypes.c_void_p) != 8:
        raise RuntimeError('Use a 64-bit Python runtime')
    dll = ctypes.WinDLL(str(image), winmode=0x1100)
    abi = dll.recomp_image_abi
    abi.argtypes, abi.restype = [], ctypes.c_uint
    if abi() != expected_abi:
        raise ValueError('Loaded image ABI differs from recorded ABI')
    set_base = dll.recomp_image_set_base
    set_base.argtypes, set_base.restype = [ctypes.c_uint64], None
    set_base(0)
    get_index = dll.recomp_image_index
    get_index.argtypes = [ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_void_p)]
    get_index.restype = ctypes.c_int
    lo, hi, pointer = ctypes.c_uint64(), ctypes.c_uint64(), ctypes.c_void_p()
    if get_index(ctypes.byref(lo), ctypes.byref(hi), ctypes.byref(pointer)) != 1 or not pointer.value:
        raise ValueError('Image did not provide its block index')
    if lo.value > hi.value or lo.value & 3 or hi.value & 3:
        raise ValueError('Image returned invalid guest-word boundaries')
    entries = (hi.value - lo.value) // 4 + 1
    if entries > 64 * 1024 * 1024:
        raise ValueError('Image index exceeds the metadata helper limit')
    view = (ctypes.c_uint64 * entries).from_address(pointer.value)
    spans = collect_guest_spans(view, lo.value, dll._handle, requested, pe.executable)
    return spans, dict(guest_lo=lo.value, guest_hi_inclusive=hi.value, entries=entries)


def run(args):
    root = pathlib.Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    if not any(output.is_relative_to(root / directory) for directory in ('build', 'local', 'generated')):
        raise ValueError('Address-bearing output must stay in ignored build/local/generated')
    launch_path, samples_path = args.launch.resolve(), args.samples.resolve()
    runs = (root / 'build/zarvot-runs').resolve()
    if launch_path.name != 'launch.json' or launch_path.parent.parent != runs:
        raise ValueError('Launch must be a recorded direct child of project build/zarvot-runs')
    launch = json.loads(launch_path.read_text(encoding='utf-8-sig'))
    if normalize_path(launch_path.parent) != normalize_path(launch['run_root']):
        raise ValueError('Recorded run root differs from the launch directory')
    target, build_path = build_record_path(root, launch)
    build = json.loads(build_path.read_text(encoding='utf-8-sig'))
    verify_build_record(launch, build, args.module)
    analysis = json.loads(samples_path.with_name('summary.json').read_text(encoding='utf-8-sig'))
    image_name = 'recompiled_image.dll' if args.module == 'main' else f'recompiled_{args.module}.dll'
    image = launch_path.parent / image_name
    if image.resolve().parent != launch_path.parent:
        raise ValueError('Image resolves outside the recorded run directory')
    expected, text = verify_inputs(launch, analysis, image, args.module, launch_path.with_name('aot_manifest.json'))
    stat = image.stat()
    with open(image, 'rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        pe = PE(data)
        module_path = normalize_path(ntpath.join(launch['run_root'], image_name))
        with samples_path.with_name('image-maps.csv').open(encoding='utf-8-sig', newline='') as source:
            image_maps = [entry for entry in csv.DictReader(source) if normalize_path(entry['module']) == module_path]
        if not image_maps or any(int(entry['image_size']) != pe.size for entry in image_maps):
            raise ValueError('Trace loaded-image identity/size differs from the verified PE')
        counts, weights, total_samples = sample_counts(samples_path, module_path, pe, analysis['sample_records'], launch['pid'], image_maps)
        functions = {rva: pe.unwind.find(rva) for rva in counts}
        requested = {value[0] for value in functions.values() if value}
        spans, index = load_index(image, pe, requested, launch['image_abi'])
        if index['guest_lo'] < text['text_vaddr'] or index['guest_hi_inclusive'] + 4 > text['text_vaddr'] + text['text_size']:
            raise ValueError('Image index extends outside the recorded module text')

        # Matching object bytes labels helpers that have no exported name or unwind entry.
        helper_candidates = collections.defaultdict(list)
        object_evidence = []
        for path in args.object:
            path = path.resolve()
            object_evidence.append(dict(name=path.name, sha256=sha256(path)))
            for section in pe.sections:
                if not section['executable']:
                    continue
                code = data[section['raw']:section['raw'] + min(section['raw_size'], args.helper_search_bytes)]
                for function in code_sections_from_coff(path.read_bytes()):
                    for relative in masked_matches(function['code'], function['mask'], code):
                        begin = section['start'] + relative
                        containing = pe.unwind.find(begin)
                        if containing and containing[0] != begin:
                            continue  # a byte sequence inside another function is not a helper entry
                        key = (begin, begin + len(function['code']))
                        helper_candidates[key].append(dict(names=function['names'], object=path.name,
                                                           relocation_count=function['relocation_count'],
                                                           matched_unrelocated_bytes=sum(function['mask'])))
        groups, groupweights, details = collections.Counter(), collections.Counter(), {}
        export_ranges = {}
        for export in pe.exports:
            extent = pe.unwind.find(export['rva'])
            if extent and extent[0] == export['rva']:
                export_ranges.setdefault(extent, []).append(export['name'])
        for rva, count in counts.items():
            candidates = [span for span in helper_candidates if span[0] <= rva < span[1]]
            if len(candidates) == 1:
                span = candidates[0]
                key = ('matched_object_function', *span)
                info = dict(aliases=helper_candidates[span], guest_spans=[])
            elif len(candidates) > 1:
                key = ('ambiguous_object_ranges', rva, rva + 1)
                info = dict(candidate_ranges=candidates, guest_spans=[])
            elif functions[rva] and functions[rva][0] in spans:
                key = ('generated_block_unwind', *functions[rva])
                info = dict(guest_spans=spans[functions[rva][0]])
            elif functions[rva] in export_ranges:
                key = ('export_unwind', *functions[rva])
                info = dict(aliases=export_ranges[functions[rva]], guest_spans=[])
            elif functions[rva]:
                key = ('unassigned_unwind', *functions[rva])
                info = dict(guest_spans=[])
            else:
                key = ('unassigned_native_rva', rva, rva + 1)
                info = dict(guest_spans=[])
            groups[key] += count
            groupweights[key] += weights[rva]
            details[key] = info
        selected = sum(counts.values())
        rows = []
        for key, count in groups.most_common():
            row = dict(category=key[0], native_start=hex(key[1]), native_end_exclusive=hex(key[2]),
                       native_bytes=key[2] - key[1], samples=count, reported_count=groupweights[key],
                       percent_module=100 * count / selected if selected else 0,
                       percent_all=100 * count / total_samples if total_samples else 0, **details[key])
            row['guest_spans'] = [[hex(lo), hex(hi)] for lo, hi in row['guest_spans']]
            rows.append(row)
        if (stat.st_size, stat.st_mtime_ns) != (image.stat().st_size, image.stat().st_mtime_ns):
            raise ValueError('Image changed during analysis')
        output.mkdir(parents=True, exist_ok=False)
        result = dict(mapping_version=1, module=args.module, target=target, image_sha256=expected['sha256'], image_bytes=stat.st_size,
                      sample_file_sha256=sha256(samples_path), launch_file_sha256=sha256(launch_path),
                      export_manifest_sha256=launch['export_manifest_sha256'],
                      build_record_path=build_path.relative_to(root).as_posix(), build_record_sha256=sha256(build_path),
                      image_map_file_sha256=sha256(samples_path.with_name('image-maps.csv')),
                      pe_timestamp=hex(pe.timestamp), preferred_base=hex(pe.base), index=index,
                      total_sample_records=total_samples, module_sample_records=selected,
                      sampled_block_functions=len(spans), object_evidence=object_evidence,
                      helper_search_bytes=args.helper_search_bytes, buckets=rows,
                      limits=['Statistical leaf CPU samples, not exact call durations or proof of the frame-rate limit.',
                              'Generated-block labels require an index pointer equal to an x64 unwind range start.',
                              'Guest spans describe possible block side entries, not the guest instruction executing at the sample.',
                              'Object matches verify every nonrelocation byte; aliases/ICF and inlined callees remain explicit.',
                              'Helpers outside the searched native prefix or absent from supplied objects stay unassigned.',
                              'Output and generated addresses stay local; no game blocks were executed.'])
        (output / 'mapping.json').write_text(json.dumps(result, indent=2), encoding='utf8')
        with open(output / 'native-functions.csv', 'w', newline='', encoding='utf8') as target:
            writer = csv.DictWriter(target, fieldnames=['category', 'native_start', 'native_end_exclusive', 'native_bytes',
                                                        'samples', 'reported_count', 'percent_module', 'percent_all', 'guest_spans'])
            writer.writeheader()
            for row in rows:
                writer.writerow({key: json.dumps(row[key]) if key == 'guest_spans' else row[key] for key in writer.fieldnames})
    print(json.dumps(dict(module=args.module, module_samples=selected, mapped_block_functions=len(spans), output=str(output))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--launch', required=True, type=pathlib.Path, help='Recorded isolated run launch.json')
    parser.add_argument('--module', required=True, choices=('main', 'sdk', 'subsdk0', 'rtld'))
    parser.add_argument('--samples', required=True, type=pathlib.Path, help='Completed CPU analyzer samples.csv; adjacent summary.json required')
    parser.add_argument('--object', action='append', default=[], type=pathlib.Path, help='Existing matching runtime/dispatch COFF object; repeatable')
    parser.add_argument('--helper-search-bytes', type=int, default=1024 * 1024, help='Native executable prefix searched for helper object bytes')
    parser.add_argument('--output', required=True, type=pathlib.Path, help='New ignored build/local/generated directory')
    args = parser.parse_args()
    if args.helper_search_bytes < 1:
        parser.error('--helper-search-bytes must be positive')
    run(args)


if __name__ == '__main__':
    main()
