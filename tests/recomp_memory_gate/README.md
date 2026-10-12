# FM1 load-gate experiment

From the parent project checkout, with MSVC/CMake/Ninja installed:

```powershell
.\scripts\measure-recomp-memory-gate.ps1 -Benchmark
```

The script snapshots the real emitter and fixture into a new ignored build
directory. It builds unchanged FM1 helpers plus four synthetic alternatives:
skip the page-crossing comparison for aligned accesses, reverse the two guards,
combine them with a non-short-circuit boolean OR, or mask the page offset before
shifting to form the page-table offset. No product emitter changes
are applied. Every access width used by FM1 is a power of two. The generated
gate is checked against an independent eligibility oracle; 32/64-bit results,
callback order/arguments and the full context are checked, with deliberate value
and callback failures. The existing guarded-page FM1 differential fixture also
compares each alternative with disabled FM1 and ABI5, including loads/stores,
page ends, partial limits, tracked/unmapped pages, tags and wrap-around.
Two fixed random seeds are used. A disabled gate is also checked with a null
table, and unknown command-line options must fail visibly.

The benchmark uses dependent synthetic pointer cycles, 32/64-bit loads,
aligned/unaligned/mixed addresses, hot/spread working sets and disabled FM1.
Each comparison uses ABBAABBA order with validated cycle endpoints, optimized
separate compilation and no LTO. Timing is descriptive, not a test gate or a
game-performance prediction. Repeat quiet runs and inspect actual native code
before selecting a source change. Raw logs, generated C and objects remain local.
The built memory_gate executable accepts --bench-reverse to repeat with the
candidate order reversed, without rebuilding or rerunning the correctness legs.
No gameplay input, game files, saves, recording or emulator settings are touched.
