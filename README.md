# Zarvot recomp project

Build a reproducible Windows ahead-of-time recompilation of Zarvot 1.0.0.
The project focuses on compiled-code coverage, correctness and efficiency,
progressing from hybrid execution to validated strict-static/no-JIT gameplay.
It reuses suyu's graphics, audio, OS and services. General emulator performance
tuning is outside the project scope.

## Current state

Zarvot is verified AArch64. All four Hybrid ABI 6 modules (main, rtld, sdk and
subsdk0) compiled and loaded with the matching source host. AOT counters advanced
during isolated boot/title tests with zero observed fallback transitions, and
the title screen rendered. R02 is complete; this does not establish gameplay
correctness, full-game coverage, strict-static/no-JIT execution or a speedup.
The existing JIT runtime reaches controllable opening Story gameplay.
Later levels, full-game correctness and music fidelity remain unverified.

The first Story action sequence had severe slowdowns despite zero observed
fallbacks (E017). Native CPU sampling placed 71.64% of combat samples in compiled
modules. E019 mapped 97.49% of main samples and found very large repeated FP32
exact fallback bodies in busy blocks. E020 shares those bodies while retaining
inline native FPX checks and exact semantics. It passed 76,477,440 value/flag
comparisons and 458,752 whole-context alias checks. A large synthetic block took
74.7% less elapsed CPU time; this is not a game FPS result.

E021 completed and exercised the separate optimized module set. Main built in
67.5 minutes and shrank from 1,509,548,544 to 807,949,824 bytes. The same five hot
block extents shrank 95.78% in total. The user replayed the first Story action,
reported improvement and good movement/effects, with some stutter remaining.
The final report recorded 9.34 billion compiled blocks and zero fallback/import
traps. Initial combat interval readings are encouraging, but differing host,
profile state and recording overhead prevent a controlled speedup claim.

E023 repeated opening combat using the preserved host, pre-combat profile and
verified recorders. Bluetooth, shooting and audio worked; the user felt
performance was about the same. Combat interval readings remain low (median
about 8 FPS). E024 mapped the saved native trace: 66.42% of combat CPU samples
are in compiled modules, with lookup and load helpers among the remaining costs.
Differences in combat phase and inputs prevent a causal gameplay speedup claim.

E025 removes redundant table searches when the complete block index already
rules out an address. It passed 1.6 million lookup comparisons and the full
runtime smoke suite. Synthetic miss lookups are faster; later game evidence is
scoped below.

**The separate lookup candidate completed recorded opening Story combat.**
All 186 generated module files were compared; only the four dispatch C files
contain the validated change. E026 verified all four images and staged an unused
future profile. E027 loaded them and rendered the full title screen, advancing
compiled counts with zero observed fallbacks. E028 then completed the user-led
route with correct movement/shooting/audio reported and zero recorded JIT
transitions. E029 confirms median combat interval FPS about 11 versus prior 8,
supporting the user's impression of smoother action in this run. A late dip
still reached 0–9 FPS before a Story transition. Different inputs, phase mix,
warm-up/cache history and laptop load prevent attributing the FPS change to the
lookup optimization. Native samples no longer land in its binary-search path;
guest-memory helpers are the next focused recomp investigation.
All three module sets and recordings are preserved. Save/death/restart
checks, original music fidelity, strict/no-JIT
execution and later routes remain open. See the [gameplay checklist](docs/zarvot/PLAYTEST.md).

## Development sequence

1. Pin matching source, exporter, runtime ABI and compiler.
2. Inventory and export the game's modules; compile and load them.
3. Prove compiled execution, validate hybrid behavior and record fallback gaps.
4. Fix missing coverage and incorrect translations; re-export and regression-test.
5. Validate named routes in strict static, then with a genuinely no-JIT host.
6. Improve generated code and AOT dispatch, memory, guards and FP paths.
7. Package a reproducible recomp and expand gameplay coverage.

The inherited MK8 work supplies the pipeline and optimization leads. Its results
are not Zarvot validation. AOT coverage and speed are reported separately;
recompilation remains the goal even when JIT is faster.

- [Current progress and next action](docs/zarvot/STATUS.md)
- [Recomp roadmap and acceptance criteria](docs/zarvot/PLAN.md)
- [Experiment and decision ledger](docs/zarvot/EXPERIMENTS.md)
- [Local build and validation runbook](docs/zarvot/RUNBOOK.md)

## Historical reference

E001-E004 document JIT-only boot/gameplay and recording preparation. E003's three
opening tutorial observations averaged 57.4-57.9 FPS with brief severe stalls.
These were interval polls, not per-frame traces or recomp results. The full
method, limitations and local evidence references remain in the ledger.
E005 verifies the installed host toolchain; E006 records the recomp-only scope.

The user handles gameplay testing. Existing manual recording tools remain
available through the runbook; automated play requires a new user request.

## Repository and provenance

Development branch: `zarvot-support`. Based on
[dougchansan/mk8-recomp](https://github.com/dougchansan/mk8-recomp) and its pinned
[suyu lineage](https://github.com/dougchansan/suyu-v0.0.4). Recomp changes are pinned
from [the Zarvot core fork](https://github.com/nate-santos/suyu-zarvot-recomp/tree/zarvot-support),
preserving the original source history and the local E013/E017 baseline.
Inherited scripts and research notes describe upstream work, sometimes historical
versions. Check actual source and artifacts before relying on their assumptions.

Share source, tooling and sanitized findings. Game packages, keys, firmware,
saves, captures and generated game code stay local. See [repository policy](LEGAL.md).
License: GPL-3.0-or-later, matching upstream. Retain component licenses and
[upstream provenance](https://github.com/dougchansan/suyu-v0.0.4/blob/mk8-recomp/PROVENANCE.md).
