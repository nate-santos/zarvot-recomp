# Isolated scalar FP32 compare input experiment

This Windows x64 fixture tests one potential emitter improvement without editing
the product core or exporting/building game modules. The default pinned baseline
is core `60fb490b2e329f9ccb13e3548d85b3f1dc0ac37b`. The candidate changes only
`EmitFPCompareFlags` when FPX emission is enabled and the operand is binary32:
copy each present operand into a `uint32_t`, then widen it unsigned into the
existing `uint64_t` comparison body. A compare with zero explicitly uses zero
without reading the absent second input. This is an isolated prototype, not an
adopted product optimization.

From the parent checkout, with PowerShell 7, MSVC Build Tools and Python:

```powershell
.\scripts\measure-recomp-fp-compare.ps1
```

Validation is the default. The wrapper extracts the pinned Git header into a
fresh ignored `build/zarvot-perf-prototypes/fp-compare-*` directory, snapshots
the fixture, derives the candidate there, and uses the real `Translate` for
both variants. Snapshots use explicit CRLF line endings to reproduce the first
Windows experiment. An existing WorkDir is rejected; failed runs stay intact.
`-BaselineRef` may select another existing commit, but the precise prefix edit
must still match once or preparation fails visibly. The current working core
does not become the candidate and is checked unchanged at the end.

The generated operation table contains 654 S forms: ordinary FCMP/FCMPE,
compare-with-zero, all 16 conditional codes and 16 literal NZCV values in both
signalling forms, and additional equal-source/V31 cases. The checks compare the
entire guest context between old/new output and an independent oracle. That
oracle handles FZ/IDC, signalling/quiet NaNs and IOC, signed-zero equality,
sortable integer keys, and conditional suppression using incoming flags.

There are 26,852,352 whole-context checks over all incoming NZCV, 32 FPCR modes
(rounding, FZ, DN and the FPX inhibit bit), sticky FPSR inputs, poisoned upper
source bits, selected special pairs, a 20-by-20 edge grid for ordinary/zero
forms, and seeded raw random conditional inputs. Fourteen hard-coded expected
cases check the oracle conventions. A deliberately omitted FCMPE IOC must fail.
ABI5, D, selected vector forms, runtime headers/bodies, exact helpers and shadow
definitions must remain byte-identical. The 703 changed generated prefixes are
checked against the intended edit; everything after each prefix must match.

Optional timing runs three quiet passes, with reversed order in the middle:

```powershell
.\scripts\measure-recomp-fp-compare.ps1 -Benchmark
```

Each block contains 16 ordinary, zero or conditional comparisons. Every result
feeds an accumulator; conditional forms also depend on prior flags. Finite and
exceptional/FZ datasets use equal call counts and validated whole-context
checksums outside timing. Timing includes identical accumulator and per-call
output/NZCV/FPSR reset costs. It excludes dispatch, guards, guest memory and game
scenes. Compiler listings must retain all 16 accumulator steps and eliminate
the candidate's partial-write/wide-reload operand stack sequences. Named
game/build/recorder process snapshots are saved before and after each pass;
their visibility depends on the caller's Windows process permissions.

To avoid timing again when only moving the fixture, an earlier completed result
may be referenced explicitly. Its artifact hashes are audited, and generator,
runner, both snapshot headers, generated C/headers/metadata, compiler version and
flags must match. Reference the original fresh result; chained references are
rejected. Earlier logs and timings remain in their original directory:

```powershell
.\scripts\measure-recomp-fp-compare.ps1 -TimingEvidence build/zarvot-perf-prototypes/<prior-result>
```

Audit a completed result without rebuilding or timing:

```powershell
.\scripts\measure-recomp-fp-compare.ps1 -WorkDir build/zarvot-perf-prototypes/<result> -AnalyzeOnly
```

The audit verifies saved hashes, including referenced evidence. Summary files
distinguish fresh timing, referenced timing and validation-only results. All
generated C, binaries, objects, listings and raw timing stay local and ignored.
No controller input, game files, saves, profiles or emulator settings are used.

The independent oracle is not ARM hardware/golden validation. Random inputs use
one deterministic stream; V0 appears in differential benchmark checks rather
than independent single-operation checks. Hard-coded conditional expectations
cover EQ; other conditions are fully crossed against the independent oracle.
Listed native sizes describe linked entry unwind ranges, not total split code
or callees. Synthetic timing is not a gameplay FPS result or full-game proof.
