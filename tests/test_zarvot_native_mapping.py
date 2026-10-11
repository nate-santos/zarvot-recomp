"""Synthetic metadata, image-boundary and byte-match tests; no DLL is loaded."""
import csv
import hashlib
import json
import pathlib
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
from zarvot_native_map import PE, UnwindRanges, code_sections_from_coff, collect_guest_spans, masked_matches, normalize_path, sample_counts, verify_build_record, verify_inputs


def pe_fixture():
    data = bytearray(4096)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', data, 0x84, 0x8664, 3, 123, 0, 0, 240, 0x2022)
    opt = 0x98
    struct.pack_into('<H', data, opt, 0x20b)
    struct.pack_into('<Q', data, opt + 24, 0x180000000)
    struct.pack_into('<I', data, opt + 56, 0x4000)
    struct.pack_into('<II', data, opt + 112, 0x3000, 0x200)
    struct.pack_into('<II', data, opt + 112 + 24, 0x2000, 24)
    for i, (name, va, raw, chars) in enumerate([(b'.text', 0x1000, 0x400, 0x60000020),
                                              (b'.pdata', 0x2000, 0x600, 0x40000040),
                                              (b'.edata', 0x3000, 0x800, 0x40000040)]):
        p = opt + 240 + 40 * i
        data[p:p + len(name)] = name
        struct.pack_into('<IIII', data, p + 8, 0x200, va, 0x200, raw)
        struct.pack_into('<I', data, p + 36, chars)
    struct.pack_into('<IIIIII', data, 0x600, 0x1000, 0x1010, 0, 0x1010, 0x1020, 0)
    struct.pack_into('<IIIII', data, 0x800 + 20, 1, 1, 0x3040, 0x3044, 0x3048)
    struct.pack_into('<I', data, 0x840, 0x1000)
    struct.pack_into('<I', data, 0x844, 0x3050)
    struct.pack_into('<H', data, 0x848, 0)
    data[0x850:0x850 + 19] = b'recomp_image_index\0'
    return data


def coff_fixture(big=False, relocation=4):
    header, stride = (56, 20) if big else (20, 18)
    raw = header + 40
    code = b'abcd' + bytes(range(20))
    reloc = raw + len(code)
    symbols = reloc + 10
    data = bytearray(symbols + stride + 4)
    if big:
        struct.pack_into('<HHHH', data, 0, 0, 0xffff, 2, 0x8664)
        struct.pack_into('<III', data, 44, 1, symbols, 1)
    else:
        struct.pack_into('<HHIIIHH', data, 0, 0x8664, 1, 0, symbols, 1, 0, 0)
    struct.pack_into('<III', data, header + 16, len(code), raw, reloc)
    struct.pack_into('<H', data, header + 32, 1)
    struct.pack_into('<I', data, header + 36, 0x60000020)
    data[raw:raw + len(code)] = code
    struct.pack_into('<IIH', data, reloc, 0, 0, relocation)
    data[symbols:symbols + 7] = b'helper\0'
    struct.pack_into('<IiHBB' if big else '<IhHBB', data, symbols + 8, 0, 1, 0x20, 2, 0)
    struct.pack_into('<I', data, symbols + stride, 4)
    return data


class NativeMapTests(unittest.TestCase):
    def test_pe_half_open_ranges_and_exports(self):
        pe = PE(pe_fixture())
        self.assertEqual(pe.base, 0x180000000)
        self.assertEqual(pe.unwind.find(0x100f), (0x1000, 0x1010))
        self.assertEqual(pe.unwind.find(0x1010), (0x1010, 0x1020))
        self.assertIsNone(pe.unwind.find(0x1020))
        self.assertFalse(pe.executable(0x1200))
        self.assertEqual(pe.exports, [dict(name='recomp_image_index', rva=0x1000)])

    def test_reject_bad_or_overlapping_unwind(self):
        data = struct.pack('<IIIIII', 10, 20, 0, 19, 30, 0)
        with self.assertRaisesRegex(ValueError, 'overlap'):
            UnwindRanges(data, 0, 2)
        with self.assertRaisesRegex(ValueError, 'outside'):
            bad = pe_fixture()
            struct.pack_into('<I', bad, 0x98 + 240 + 20, len(bad))
            PE(bad)

    def test_index_spans_preserve_aliases_and_null_gaps(self):
        base = 0x180000000
        index = [base + 0x1000, base + 0x1000, 0, base + 0x1010, base + 0x1000]
        spans = collect_guest_spans(index, 0x80, base, {0x1000, 0x1010}, PE(pe_fixture()).executable)
        self.assertEqual(spans[0x1000], [(0x80, 0x84), (0x90, 0x90)])
        self.assertEqual(spans[0x1010], [(0x8c, 0x8c)])
        with self.assertRaisesRegex(ValueError, 'outside executable'):
            collect_guest_spans([base + 0x1200], 0, base, set(), PE(pe_fixture()).executable)

    def test_coff_regular_and_bigobj_and_relocation_mask(self):
        for big in (False, True):
            fn, = code_sections_from_coff(coff_fixture(big))
            self.assertEqual(fn['names'], ['helper'])
            self.assertEqual(fn['mask'][:4], b'\0' * 4)
            replaced = b'WXYZ' + fn['code'][4:]
            self.assertEqual(masked_matches(fn['code'], fn['mask'], replaced + replaced), [0, 24])
            mismatch = replaced[:-1] + b'!'
            self.assertEqual(masked_matches(fn['code'], fn['mask'], mismatch), [])
        self.assertEqual(code_sections_from_coff(coff_fixture(relocation=0x7fff)), [])

    def test_image_manifest_and_process_identity_rejections(self):
        fixture_root = pathlib.Path(__file__).resolve().parents[1] / 'build/native-map-tests'
        fixture_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=fixture_root) as temp:
            root = pathlib.Path(temp)
            image, manifest = root / 'image.bin', root / 'aot_manifest.json'
            image.write_bytes(b'verified fixture')
            manifest.write_text(json.dumps(dict(image_abi=6, image_features=7,
                                                modules=[dict(name='main', text_vaddr=0, text_size=16)])))
            launch = dict(image_abi=6, image_features=7, run_root=r'C:\test\run', pid=7,
                          process_started_utc='2026-10-11T03:00:00Z',
                          export_manifest_sha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                          modules=[dict(name='main', state='complete', bytes=image.stat().st_size,
                                        sha256=hashlib.sha256(image.read_bytes()).hexdigest())])
            analysis = dict(state='complete', expected_pid=7, expected_executable=r'c:\TEST\run\suyu-cmd.exe',
                            process_started_utc='2026-10-10T23:00:00-04:00')
            verify_inputs(launch, analysis, image, 'main', manifest)
            with self.assertRaisesRegex(ValueError, 'another executable'):
                verify_inputs(launch, dict(analysis, expected_executable=r'C:\foreign\suyu-cmd.exe'), image, 'main', manifest)
            with self.assertRaisesRegex(ValueError, 'another process start'):
                verify_inputs(launch, dict(analysis, process_started_utc='2026-10-11T03:00:01Z'), image, 'main', manifest)
            with self.assertRaisesRegex(ValueError, 'manifest differs'):
                verify_inputs(dict(launch, export_manifest_sha256='0' * 64), analysis, image, 'main', manifest)
            image.write_bytes(b'changed fixture!')
            with self.assertRaisesRegex(ValueError, 'build hash/size'):
                verify_inputs(launch, analysis, image, 'main', manifest)

    def test_canonical_build_and_full_sample_path_identity(self):
        module = dict(name='main', sha256='123', bytes=32)
        launch = dict(image_abi=6, image_features=7, export_manifest_sha256='456', modules=[module])
        build = dict(launch, state='complete')
        verify_build_record(launch, build, 'main')
        with self.assertRaisesRegex(ValueError, 'completed project build'):
            verify_build_record(dict(launch, export_manifest_sha256='789'), build, 'main')
        with self.assertRaisesRegex(ValueError, 'Selected image differs'):
            verify_build_record(dict(launch, modules=[dict(module, sha256='789')]), build, 'main')
        fixture_root = pathlib.Path(__file__).resolve().parents[1] / 'build/native-map-tests'
        fixture_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=fixture_root) as temp:
            path = pathlib.Path(temp) / 'samples.csv'
            def write(module_path, rva='0x1000', ip='0x180001000', pid=7, time=1):
                with path.open('w', newline='') as stream:
                    writer = csv.DictWriter(stream, fieldnames=['module', 'native_rva', 'reported_count', 'instruction_pointer', 'pid', 'trace_seconds'])
                    writer.writeheader()
                    writer.writerow(dict(module=module_path, native_rva=rva, reported_count=1, instruction_pointer=ip, pid=pid, trace_seconds=time))
            expected = normalize_path(r'C:\run\recompiled_image.dll')
            write(r'c:\RUN\recompiled_image.dll')
            counts, weights, total = sample_counts(path, expected, PE(pe_fixture()), 1)
            self.assertEqual((counts[0x1000], weights[0x1000], total), (1, 1, 1))
            write(r'C:\foreign\recompiled_image.dll')
            with self.assertRaisesRegex(ValueError, 'full path is foreign'):
                sample_counts(path, expected, PE(pe_fixture()), 1)
            write(r'C:\run\recompiled_image.dll', '0x4000')
            with self.assertRaisesRegex(ValueError, 'outside the verified image'):
                sample_counts(path, expected, PE(pe_fixture()), 1)
            maps = [dict(image_base='0x180000000', loaded_seconds=0, unloaded_seconds=2)]
            write(expected)
            sample_counts(path, expected, PE(pe_fixture()), 1, 7, maps)
            write(expected, ip='0x180001001')
            with self.assertRaisesRegex(ValueError, 'IP/RVA differs'):
                sample_counts(path, expected, PE(pe_fixture()), 1, 7, maps)
            write(expected, pid=8)
            with self.assertRaisesRegex(ValueError, 'another PID'):
                sample_counts(path, expected, PE(pe_fixture()), 1, 7, maps)
            write(expected, time=2)
            with self.assertRaisesRegex(ValueError, 'IP/RVA differs'):
                sample_counts(path, expected, PE(pe_fixture()), 1, 7, maps)


if __name__ == '__main__':
    unittest.main()
