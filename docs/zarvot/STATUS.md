# Zarvot recomp handoff

Updated: 2026-10-05. R00/R01/R02 complete. R03 combat diagnosis recorded (E015).

## Objective and next action

Work only on the recomp: build, coverage, correctness and execution improvements.
Reuse the compatibility stack. Do not resume general emulator performance,
settings or GPU tuning. JIT is a reference and temporary hybrid fallback.

**Active: R03 — user-led recomp gameplay checks and coverage/correctness
diagnosis.** E015 confirms severe combat slowdowns reported around shot hit
effects. All 299 complete recorder reports show zero lookup/opcode transitions;
the user's observed JIT transitions remain an unresolved discrepancy. Several
hitches coincide with graphics-pipeline creation, but compiled CPU cost is not
yet attributed. Next: profile compiled PCs/runtime helpers on the same combat
route; finish behavioral checks separately. The launcher now supports an opt-in
-SamplePc mode without rebuilding; live sampling remains untested. Check the
active run pointer in workspace reports/r03-active-run.json and actual processes
before another launch. The ten-minute recorder finished; preserve the session.
All four DLLs built, matched their recorded hashes, loaded with
ABI 6/guard/fastmem/FPX1 negotiation, and executed compiled game code. The title
screen rendered; boot/title observations showed advancing AOT counts and zero
fallback transitions. Combat and a pause menu rendered in E015; gameplay
correctness and audio checks remain incomplete. Follow PLAYTEST.md.
Use the isolated launcher and CLI coverage recorder in RUNBOOK. Do not repeat
the 3.5-hour main build or export unless a source/export change requires it.

## Verified progress

- Zarvot 1.0.0 is AArch64, title ID `0100E7900C4C0000`; base metadata version 0.
- E001-E004 establish JIT boot and controllable opening Story gameplay only.
  Movement, shooting, pause and restart worked. No recomp gameplay was tested.
- E003 interval measurements averaged 57.4-57.9 FPS with brief stalls. They are
  historical reference, not a recomp result; per-frame timings remain absent.
- E005 installed CMake 4.4.3, VS Build Tools 2022 17.14.41, MSVC 19.44.35229.0,
  Windows SDK and bundled Ninja. C/C++ smoke builds/execution passed (2/2).
- R00/R01: matching source host/exporter built; Hybrid ABI 6 export completed
  for main/rtld/sdk/subsdk0. Feature bits 7; translate_all enabled.
- R02: all four modules compiled and loaded. Main finished in 210.9 minutes
  (1,509,548,544-byte DLL); every image and export manifest hash verified.
- Compiled execution: same-process AOT counts advanced 7,680,340,123 ->
  7,951,582,393 in the first observation and 7,312,156,998 -> 8,419,406,636
  in the handheld repeat, with zero observed lookup/opcode fallback transitions.
  Title-screen captures visually inspected. Both were hybrid-policy, JIT-capable
  runs; strict-static and no-JIT execution have not been established.
- Later levels, full playthrough and original music fidelity remain unverified.
- E015: user reported combat hit-effect slowdown; logged intervals reached 5-7
  FPS, with isolated 0-1 FPS samples. Recorder advanced 503,045,903 ->
  20,196,871,790 AOT blocks; no observed fallback/import traps. No per-frame or
  CPU/GPU duration trace; pipeline activity is a correlation, not attribution.

## Active task state

| ID | State | Evidence / next condition |
|---|---|---|
| R00 | Complete | Pinned source built suyu/suyu-cmd; command-line host smoke exited 0; exporter RPC worked (E010) |
| R01 | Complete for fixed exported modules | Four-module Hybrid ABI 6 source/manifest exported successfully; late-loaded/generated code remains unverified |
| R02 | Complete | Four DLLs/hash evidence; matching host handshakes; advancing AOT counts; rendered title (E013) |
| R03 | In progress; combat issue diagnosed provisionally | E015 logs/captures; reported JIT transitions conflict with saved counters; correctness checks still open |
| R04 | Pending R03 | Iterative coverage/translation fixes with focused tests |
| R05 | Pending validated routes | Strict-static zero-fallback tests, then separate no-JIT verification |
| R06 | Ready for combat profiling | E015 slowdown recorded; generated-code/runtime cost unmeasured; preserve correctness |
| R07 | Pending R05 | Reproducible recomp package and endurance checks |
| R08 | Pending R05 routes | Expand later-level/mode coverage; track full playthrough separately |

The old Z queue is retired; PLAN.md maps it to this queue. E001-E005 retain
their original IDs and observations. General emulator stall diagnosis, resolution
A/B and logging/cache tuning are no longer next actions.

## Resume procedure

1. Read PLAN and latest ledger entry; check actual Git state and processes.
2. Recomp roadmap, README, instructions and E005/E006 are committed in 5c6156a.
   Preserve subsequent changes and check current ahead/behind state afresh.
3. Inspect existing generated export and build artifacts at the identities in
   RUNBOOK. Continue R03; source remains unchanged at its pinned revision.
   The sequential runner records its PID and module completion/hash evidence in
   build/recomp/zarvot/build-status.json. Check that process and compiler activity
   before restarting; reports/r02-module-set-build.log holds raw progress.
   The runner completed successfully. Preserve these outputs; incremental builds
   are needed only after an affected source/export change.
4. Continue recomp correctness/coverage work without fresh JIT performance tests. Inspect
   current project sessions before launching or stopping anything.
5. The user handles gameplay. E013 uses unique build/zarvot-runs profiles, never
   the original player profile/saves. Inspect actual process state before
   launching; do not automate play. The launcher refuses a concurrent session.
   Both E013 smoke hosts closed gracefully. The user subsequently requested
   playtesting; E014 started a separate visible session and recorder. E015
   analyzed it without stopping or sending input; bounded recorder completed.
   Check the active pointer and PID/path/start time; preserve the session and saves.
   Collect the user's observations before marking any gameplay/audio check passed.
6. Append evidence and update the relevant R row after each meaningful result.

## Identities and preserved local evidence

- Checkout: source/; branch: zarvot-support; origin: nate-santos/zarvot-recomp;
  upstream: dougchansan/mk8-recomp. Workspace root is not a Git repository.
- Wrapper base db36cf5; pinned suyu 5949cab3ba93233ddd1c319bfc6f010f6cfa910a.
- Installed asset labeled v0.0.12 reports v0.0.11 / HEAD-40aeb31824-HEAD.
  Exact hashes and paths are in RUNBOOK; labels alone do not establish ABI match.
- Host: Ryzen 7 5825U / integrated AMD Radeon, 16 GiB installed RAM.
- Preserve portable JIT profile (Vulkan, handheld 1x/HIGH, original timing),
  saves and E004 backups. Use separate recomp output/profile as needed.
- Local keys already supplied; do not print contents or request acquisition.
- Raw evidence is in reports/; generated code/assets remain ignored and local.
- Existing manual recorder sends no controller input. PresentMon ETW capture
  failed with access denied; no frame-percentile claims follow from old polls.
- RPC launch timeout previously did not imply boot failure. Inspect state before
  retrying. Play-time path errors are historical, not an active tuning task.

## Decisions to preserve

Coverage, correctness and recomp efficiency are separate goals. AOT coverage is
valuable even without an FPS gain, but does not itself prove speed or fidelity.
Do not stop recomp work because JIT is fast enough. Keep graphics/audio support
and original gameplay/music behavior. Fix source in the appropriate recomp
components; current upstream features must be inspected before reimplementation.
R00-R02 are complete; keep building toward the eventual optimized Zarvot recomp.
E010's GUI boot was unverified, but E013 proved execution through the ordinary
CLI and rendered the title screen without a firmware preflight dialog. Gameplay
coverage, audio fidelity and speed are separate remaining goals. No fallback on
boot/title does not establish complete coverage or absence of JIT in the build.
