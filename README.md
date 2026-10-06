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

User-led recomp combat rendered, but severe slowdowns around hit effects were
reported. All 299 complete recorder reports showed zero fallback transitions;
reported visible transitions remain unresolved. Some hitches coincided with
graphics-pipeline creation; compiled CPU cost remains unprofiled (E015).

**Next: profile the compiled combat path and finish gameplay correctness checks.**
The main MSVC build took 210.9 minutes and produced a roughly 1.5 GB DLL.
Build cost and generated-code efficiency remain recomp work. See E013 for
execution evidence and the [gameplay checklist](docs/zarvot/PLAYTEST.md).

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
[suyu fork](https://github.com/dougchansan/suyu-v0.0.4).
Inherited scripts and research notes describe upstream work, sometimes historical
versions. Check actual source and artifacts before relying on their assumptions.

Share source, tooling and sanitized findings. Game packages, keys, firmware,
saves, captures and generated game code stay local. See [repository policy](LEGAL.md).
License: GPL-3.0-or-later, matching upstream. Retain component licenses and
[upstream provenance](https://github.com/dougchansan/suyu-v0.0.4/blob/mk8-recomp/PROVENANCE.md).
