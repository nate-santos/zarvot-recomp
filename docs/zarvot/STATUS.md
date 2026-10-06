# Zarvot recomp handoff

Updated: 2026-10-06. R00/R01/R02 complete. R03 lifetime diagnostics validated (E016).

## Objective and next action

Work only on the recomp: build, coverage, correctness and execution improvements.
Reuse the compatibility stack. Do not resume general emulator performance,
settings or GPU tuning. JIT is a reference and temporary hybrid fallback.

**Active: R03 — user-led recomp gameplay checks and coverage/correctness
diagnosis.** E016 finished normally on process exit: all 146 UI/file samples
showed zero fallback transitions, with advancing AOT counts and no disagreements
or regressions. The user noticed no transitions and clarified that this run
contained no combat; captures show a Story room/dialogue. Their earlier possible
count of six is now uncertain, with no corroborated fallback or gap PC.
The recorder now preserves exact captions and coverage independently until exit;
compiled-PC sampling produced module-relative locations. Next: record a named
user-led combat route, obtain native compiled-code/helper duration evidence,
then fix measured recomp costs or actual gaps and finish behavioral checks.
E015's pipeline activity is a correlation; compiled CPU cost remains unattributed.
E016 used a verified clone of the prior test saves/settings/caches. Game and
recorder have exited. Check workspace reports/r03-active-run.json and actual
processes before another launch; preserve both test profiles and evidence.
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
- E016: 146 complete UI/file samples over 291.604 seconds; AOT blocks advanced
  180,881,897 -> 13,386,471,882. Zero observed fallback/import traps, disagreements
  or regressions. Final report contains 1,222 distinct sampled PCs. Story room
  and dialogue rendered; user confirmed no combat. Prior UI count uncertain.
  Profile clone's six NAND files matched hashes; source unchanged. Three synthetic
  diagnostic tests passed, including independent UI=6/file=0 and normal exit.

## Active task state

| ID | State | Evidence / next condition |
|---|---|---|
| R00 | Complete | Pinned source built suyu/suyu-cmd; command-line host smoke exited 0; exporter RPC worked (E010) |
| R01 | Complete for fixed exported modules | Four-module Hybrid ABI 6 source/manifest exported successfully; late-loaded/generated code remains unverified |
| R02 | Complete | Four DLLs/hash evidence; matching host handshakes; advancing AOT counts; rendered title (E013) |
| R03 | In progress; lifetime diagnostics validated | E016 zero observed fallbacks on noncombat scenes; named combat/correctness checks pending |
| R04 | Pending R03 | Iterative coverage/translation fixes with focused tests |
| R05 | Pending validated routes | Strict-static zero-fallback tests, then separate no-JIT verification |
| R06 | Compiled-PC sampling validated | E016 histogram populated; combat and native duration profile pending |
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
   That host subsequently closed. E016 cloned its verified saves/settings into
   a new isolated run with UntilExit recording and compiled-PC sampling. It
   subsequently exited; recorder completed normally. Check the active pointer
   and actual processes before relaunch; retain both profiles and saves.
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
