# Zarvot recomp roadmap

Updated: 2026-10-05. This supersedes the emulator optimization roadmap.

## Objective

Produce a reproducible Windows recomp build of Zarvot 1.0.0 that executes
its game CPU code ahead of time, preserves original behavior, and progressively
eliminates required JIT fallback. Improve recomp coverage, correctness and
execution efficiency. AOT remains the project goal even if JIT is faster or
already reaches the original frame rate.

Reuse the existing graphics, audio, OS and service compatibility stack. Changes
to its exporter, generated code, AOT loader and CPU runtime are recomp work even
when those files live in the suyu submodule. General emulator performance,
resolution/accuracy tuning, shader settings, backend comparisons and unrelated
GPU/audio optimizations are outside this roadmap. Fix integration blockers only
as needed to export, build, run or validate the recomp.

JIT is a behavioral reference and temporary hybrid fallback. Existing JIT
measurements are historical evidence, not an optimization backlog or a gate on
starting AOT work. Preserve gameplay timing, input, saves, visuals and music.
The user handles gameplay testing; no automated play without a new request.

## Milestones and acceptance

New R IDs avoid changing the meaning of historical Z IDs in the ledger.

| ID | Work | Depends on | Acceptance evidence |
|---|---|---|---|
| R00 | Align source, exporter, runtime and toolchain | Ready now | Pinned source/submodules, matching exporter/runtime ABI, verified compiler and successful host/exporter build |
| R01 | Inventory and export Zarvot | R00 | Module/build-ID inventory, generated source and coverage report; record unsupported or runtime-loaded code |
| R02 | Compile and load the recomp | R01 | Reproducible module build and manifest; matching images load; counters advance while compiled game code executes |
| R03 | Validate hybrid behavior and diagnose gaps | R02 | User-observed menus/gameplay, input/save/audio checks, fallback PCs and reasons grouped by module/instruction/target |
| R04 | Close coverage and correctness gaps | R03; iterate | Missing translations/targets repaired and re-exported; focused regression tests; falling fallback counts on named routes |
| R05 | Validate strict static and no-JIT execution | R04, route by route | Strict runs with zero fallback attempts and advancing AOT counters; separate no-JIT build proves JIT unavailable |
| R06 | Improve recomp execution efficiency | R03 onward, with correctness checks | Measured generated-code/runtime improvement on equivalent work with unchanged behavior; report coverage separately |
| R07 | Package and reproduce the recomp build | R05 and validated R06 changes | Clean rebuild, launcher using local game files, cold boot/save-load/transitions/audio and 30+ minute checks |
| R08 | Expand game coverage | R05 onward | Named later levels/modes and full-playthrough checklist; report remaining gaps and failures explicitly |

First deliverable: a compiled Zarvot module set whose execution is observable.
Next: a correct hybrid gameplay route, then the same route in strict static.
Do not wait for general emulator bottleneck classification or a fresh JIT
benchmark before R00-R02. Do not wait for a full playthrough before fixing
known recomp defects or improving a validated compiled path.

## R00-R02: establish the build

1. Check branch/worktree state and existing project processes; preserve user
   edits, saves and sessions. Initialize the pinned submodule if absent.
2. Resolve the recorded release-label/source mismatch through actual commits,
   executable hashes and image ABI/features. Prefer a matching source build of
   exporter and host; retain the installed runtime as a reference.
3. Verify CMake/MSVC/Ninja from E005 and inspect compiler support. Upstream
   reports clang-cl benefits; verify availability and compatibility before use.
4. Inspect current exporter and scripts, inventory the local game's modules,
   and export into ignored output. Record build IDs and late-loaded code limits.
5. Compile generated modules, validate manifests and load them with the matching
   host. Check static-backend state, advancing static-block counts and fallback
   attempts. An EXE, export success or rendered image alone proves no AOT work.
6. Record exact commands, identities, output locations and build failures in
   RUNBOOK/STATUS and the ledger. Keep generated game code and assets local.

## R03-R05: coverage and correctness

Record misses by module, PC, instruction and reason: unsupported instruction,
undiscovered indirect target, missing/late-loaded module, invalid image or code
guard failure. Rank frequent/costly misses first, but retain cold misses in the
strict-static completion checklist. Feed valid discovered roots back into the
exporter; never turn an unknown instruction into silent success.

Compare changed translations with reference semantics using synthetic instruction
and block tests. Cover registers, flags, FPCR/FPSR, memory effects, exclusives,
relocations, scheduling boundaries and code invalidation as applicable. JIT
agreement is useful evidence, not an infallible architectural oracle. Inspect
actual gameplay and 3D output: successful boot and frame counts miss corruption.

Preserve music assets and game-controlled pitch, loops, transitions and timing.
Track audibility/stability separately from original-hardware fidelity, which
remains unverified without a reference. User-led gameplay validation must cover
input, saves, combat, death/restart and scene transitions; keep untested scenes
explicitly open. Synthetic checks and build work can proceed while playtesting
is pending.

Rebuild the exporter when emitter code changes, then re-export and rebuild all
affected modules. Reject stale/mixed image ABIs. Strict mode must fail visibly
on missing coverage. Prove no-JIT separately using the build graph, symbol audit
and runtime availability telemetry. Zero fallbacks on one route is not proof
that every level or runtime-generated instruction is covered.

## R06: improve the recomp itself

Use the inherited MK8 approach after checking which mechanisms already exist:

- Compare generated-code compiler and optimization choices, beginning with
  clang-cl versus MSVC where supported. Record build time and resource cost.
- Reduce dispatch, block-boundary and AOT/JIT state-transfer overhead through
  bounded module dispatch, block chaining and validated target lookup.
- Verify/use the existing fast guest-memory path, code-generation guards and
  exact native floating-point paths before inventing replacements.
- Profile compiled blocks, memory helpers, guards and floating-point helpers.
  Preserve permissions, invalidation, ordering, exclusives and exact semantics;
  avoid blanket fast-math and disabling correctness guards.
- Consider LTO/PGO or narrowly recovered native routines only with a demonstrated
  recomp cost and differential tests for the affected behavior.

For each change keep the game, route, graphics/audio settings and work performed
constant; repeat comparisons and reject stale modules. Track AOT execution,
fallback attempts, time in compiled code/helpers/dispatch, startup and build
cost. Use genuine frame traces for frame percentiles. Interval FPS polls cannot
establish p99 or 1% lows. A slower correct coverage expansion may still be useful
progress; label it honestly and retain the speed regression as recomp work.

Upstream db36cf5 reports strict-static MK8 improvements from compiler, memory,
guard and FP changes. These are design leads, not Zarvot results. Earlier MK8
claims were corrected after fallback and fixture mistakes; read later findings
before relying on old architecture notes or performance numbers.

## Completion and handoff

A deliverable must reproduce from pinned tools/source plus the user's local
files, execute verified compiled game code, and pass the stated correctness
scope. Track four independent outcomes: builds, coverage, correctness and
performance. Never substitute one for another. Full-game completion requires
the R08 checklist; representative testing supports only a scoped release.

Continue the first ready R task in STATUS. For meaningful work append a ledger
entry with evidence, limitations, decision and next action. Preserve historical
E entries and Z references. Share tooling/source and sanitized findings only;
keep game files, keys, firmware, generated code, saves and raw captures local.

## Retired roadmap mapping

| Historical task | New disposition |
|---|---|
| Z00 | Existing repository/handoff foundation retained |
| Z01 | Existing JIT evidence retained; recomp validation moves to R03/R08 |
| Z02/Z03 | Emulator settings, logging and GPU tuning removed from active scope |
| Z04 | Source/exporter/runtime alignment becomes immediate R00 |
| Z05 | Export/build/execution becomes R01-R03, no JIT benchmark prerequisite |
| Z06/Z07 | Coverage and compiled-code optimization become R04/R06 |
| Z08/Z10 | General graphics/audio optimization removed; fidelity stays mandatory |
| Z09 | Optional recomp routine replacement within R06 |
| Z11 | Recomp packaging and reproducibility become R07 |
| Z12 | Full engine/API rewrite outside the current recomp roadmap |
