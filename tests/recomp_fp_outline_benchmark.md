# Generic FP32 recomp benchmark

This Windows x64 experiment compares synthetic emitted arithmetic from the
pre-outline emitter with the current FPX1 candidate. It needs 64-bit PowerShell
7, Git and the existing Visual C++ toolchain. It neither starts the game nor
rebuilds the host or any game module. Run it after other builds, games and CPU
tests finish; it never stops them.

From the source checkout:

```powershell
.\scripts\measure-recomp-fp-outline.ps1
```

The baseline defaults to pinned suyu commit
`5949cab3ba93233ddd1c319bfc6f010f6cfa910a`. `-BaselineRef` selects another local
commit that still emits inline exact FP32 bodies. The candidate is the current
`third_party/suyu/src/core/recompiler/arm64_to_c.h`. Both headers are copied into
a new ignored `build/zarvot-perf-prototypes/fp-outline-<id>` directory before
compilation. Git's baseline text is normalized to LF; metadata records the exact
header hashes actually compiled. Existing experiment directories are preserved.

The generator is compiled independently against each header. It enables FM1,
GG1 and FPX1 and uses the real `Translate()` and runtime definitions. It produces
one 16-operation scalar block (8 multiply, 4 add, 4 subtract) and one
122-operation scalar block (34 multiply, 62 add, 26 subtract). Register operands
and encodings are synthetic. The candidate links its production noinline exact
helpers. Both sides use MSVC `/O2 /Ob2 /bigobj /fp:precise /MD` without LTO,
shadow checks or probe counters.

Before timing, the runner compares the whole `GuestContext` for 32 FPCR modes
(rounding/FZ/DN combinations with and without the inhibit bit), four starting
FPSR values, edge payloads and deterministic random values. Each block size
receives 32,768 comparisons. A separate deliberately altered result must be
detected with exit 1. Broader architecture/alias/shadow validation remains the
responsibility of `third_party/suyu/tests/recompiler_fpx`; this benchmark does
not replace it.

Timing uses `ABBAABBA` with fixed equivalent work and verifies matching output
checksums. Datasets cover moderate finite values with FPX1 open, IXC initially
clear, and the native path inhibited. Each timed call includes the same
128-byte output reset and FPSR reset on both sides. Random generation, semantic
comparisons and output hashing are outside the measured region. A near-neutral
small-block result should not be treated as a meaningful speedup. The large
block is intended to expose code-size/optimizer effects; it is not a game scene.

The directory retains compiler logs, assembly listings, binaries, validation and
timing logs, busy-process snapshots, hashes and `summary.json`. Assembly reports
explicit stack allocations separately from pushed registers. Reported native
unwind ranges cover only the fragment containing the function entry, excluding
other fragments and callees. No speed or code-size threshold is a test gate.

To recheck a completed experiment without compiling or timing:

```powershell
.\scripts\measure-recomp-fp-outline.ps1 -AnalyzeOnly -WorkDir .\build\zarvot-perf-prototypes\fp-outline-<id>
```

Analysis verifies saved evidence hashes, both complete semantic reports, all
six timing groups, the ABBA ordering, equal call counts and checksums. Keep raw
artifacts local. Record sanitized results in the project ledger, with the
explicit limit that a synthetic CPU improvement does not establish game FPS,
route correctness or coverage.
