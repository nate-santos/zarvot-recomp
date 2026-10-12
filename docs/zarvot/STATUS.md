# Zarvot recomp handoff

Updated: 2026-10-12. Lookup candidate built, staged and compiled boot verified.

## Objective and next action

Work only on the recomp: build, coverage, correctness and execution improvements.
Reuse the compatibility stack. Do not resume general emulator performance,
settings or GPU tuning. JIT is a reference and temporary hybrid fallback.

**First ready task: R03/R06 — user-led opening Story combat comparison with
zarvot-lookup-miss when the user is ready. No rebuild needed.** E026 completed
all four modules from core 284f411686. Main took 69.7 minutes; all recorded DLL
hashes/sizes, ABI6/features7, exported metadata and 4,280 lookup/rebase checks
passed. A preserved unused stage is build/zarvot-runs/20261012-024145-1a00cba2,
using the E017 host and E016 initial profile. Future normal launch creates a
new copy; StageOnly is not a resumable session. Connect Stadia before launch,
then verify coverage attachment and the owned CPU recorder before inviting play.
The user requested readiness for a future session; no gameplay was automated.

E027 separately verified actual compiled boot/title at
build/zarvot-runs/20261012-121811-3ca1b234. All four images loaded with guard-v2,
generation guard, fastmem and FPX negotiation/runtime-on. 88 complete reports
advance compiled counts 52,851,771 -> 9,287,923,552 with zero UI/file fallbacks,
import traps, disagreements or regressions. The complete Press Any Button title
rendered after startup transitions. No controller input was sent. Owned game
and coverage recorder exited normally; no CPU trace was requested for this
boot-only check. Hybrid remains JIT-capable, and no combat FPS/behavior gain is
established. Keep the future stage and all earlier profiles intact.

E026 rebuilt the exporter and completed the separate export. All 186 module
files were compared with the FP32 candidate: 182 are identical and only the four dispatch
C files contain exactly E025's validated lookup change. Manifest/coverage,
ABI6/features7 and game/module inventory are unchanged. Build evidence is in
build/recomp/zarvot-lookup-miss/build-status.json and workspace
reports/e026-module-runner.json. Build/preparation PIDs 11980/30768 exited.
Main DLL is 807,949,824 bytes, SHA ca6976b4...; full identities are in E026.

E025's indexed early-NULL
change passed 1,616,528 differential lookup checks, a deliberate failing control,
quiet synthetic timings and the complete five-variant runtime smoke suite.
Only generated dispatch changes; valid index hits/holes and allocation-failure
search remain intact. Earlier zarvot-fp32-outline images use core 84568fcadc and
do not contain this change. Preserve all three module sets and E017/E023
profiles. For any future affected rebuild, allow healthy sequential compilation
to finish without an arbitrary overall timeout; retain the memory-aware pool.
Keep ABI/layout, guards, FP and gameplay timing unchanged. Reuse the E017 host
and E016 initial profile for the user-led comparison with both recorders
verified. FM1 load-gate experiments remain later leads;
inherited full-helper inlining regressed and acquire ordering must survive.

E023 is closed: build/zarvot-runs/20261012-003140-dc25d36d (October 11 locally).
Historical game/coverage/CPU PIDs 24476/29464/21416 all exited. CPU profile
cpu-profiles/20261012-003248-38053670 saved 2,545,942,528 bytes with no recording
or cleanup error. Coverage has 199 complete reports, advancing AOT counts to
12,665,187,218 and zero UI/file fallbacks, import traps, disagreements or
regressions. User confirmed Stadia Bluetooth works, finished opening Story
action, and reported performance about the same with shooting/audio fine.
Movement-specific recheck, saves, death/restart and original music fidelity
remain open independently.

E024 converted and verified the exact process, 1 ms sampling and zero lost
events. Capture 8 through 11 bounds combat at 00:35:34.1295148–00:37:04.1983949
UTC: 178,841 CPU samples, 66.42% in compiled modules, main 57.86%, SDK 8.25%,
host 12.57%, unknown 15.98%. Main mapping assigns 96.58% to indexed blocks,
byte-matched helpers or run-slice export. Across main/SDK, block lookup accounts
for 12,288 leaf samples (6.87% of all), load32/load64 11,874 (6.64%), and the
three outlined exact FP32 helpers 6,264 (3.50%). Host RunThread is 1.87% and
direct exclusive callbacks 0.29%; no dominant host recomp helper emerged.
Leaf shares locate work, not exact call time or the cause of stutter.

Combat PERF intervals have median 7.9945 FPS (90 samples, 79 below 10), versus
6.997 in E017's original 90-second combat window. Same preserved host, E016
initial profile and diagnostic configuration reduce comparison differences,
but phase mix, inputs/effects, Bluetooth transport and laptop load are not
matched. The user still perceives similar performance; no causal speedup or
frame-percentile claim. See E024 for the separate UI metrics and phase checks.
All four candidate modules are complete and preserved at
build/recomp/zarvot-fp32-outline. Main is 46.48% smaller than baseline; the five
previous hot blocks are 95.78% smaller in aggregate. E020's focused semantic
checks passed; these footprint/synthetic results do not establish full-game
correctness. Keep both module sets, E013/E017 profiles and raw evidence local.
Check reports/r03-active-run.json and actual desktop processes before launching.
Use -RecordCoverage plus the separately verified owned CPU recorder when a new
user-led test is warranted. Native mapping now selects and verifies the recorded
build target, rather than assuming baseline; nine focused tests pass.

E017 used
an isolated clone of E016 for the requested first Story action sequence. The
user played it and reported many slowdowns/bad frame rates. All
232 complete UI/file samples showed zero transitions/import traps, with advancing
AOT counts and no disagreements/regressions. In a capture-bounded 90-second
combat window, 41/45 interval FPS polls were below 10 (median 7; range 5.5-11.5).
The elevated native CPU trace saved successfully on game exit (1.996 GB). Game
and recorders are closed. E018 converted the trace and verified exact process
identity, a 1 ms sample interval and zero reported lost events. During the
capture-bounded combat window, 71.64% of CPU samples were in compiled DLLs,
including 65.01% in main; 13.17% were in the host and 10.98% remain unmapped.
Host recomp callbacks are small leaf buckets; no dominant host helper emerged.
E019 mapped most main samples through the verified index, unwind ranges and
runtime/dispatch object bytes. Native RVAs and block labels are not guest PCs.
These proportions locate CPU work, not the cause of low FPS or exact call time;
title/combat are different scenes. Diagnostic overhead and inlined helpers remain.
E017 did not establish input/audio/save correctness or exact hit timestamps;
E023's later input/shooting/audio observations are recorded above.
The older possible UI count of six is uncertain; no fallback gap is corroborated.
Check workspace
reports/r03-active-run.json and actual processes before another launch; preserve
all test profiles and evidence. Continue from the saved profile before requesting
another performance playtest. Keep R03 behavioral checks open independently.
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
- E017 preparation: reused the same four verified DLLs and host, with no rebuild
  or settings tuning. AOT counts advanced 1,769,111,829 -> 18,317,539,853 across
  232 complete reports, with zero UI/file fallbacks/import traps. Jar-arena
  combat/effects and Story transition captures inspected; user confirmed first
  action sequence and severe slowdowns. Native WPR trace saved normally; no
  CPU attribution or gameplay/audio correctness verdict yet.
  Owned-profiler synthetic tests passed normal save/exit,
  rejected start, foreign process, PID reuse and failed-save cleanup.
- E018: exact-process full trace and cached title/combat exports validated.
  Combat contains 157,467 CPU samples, 112,804 in compiled modules; main 102,371,
  SDK 10,049. Verified host map/PDB/unwind ranges place ArmRecomp::RunThread at
  1.44% of all combat samples; direct exclusive callbacks combined at 0.22%.
  No helper-cause or speedup claim. Analyzer identity/UTC/address tests passed.
- E019: recovered 15,396 sampled block function mappings from the existing
  hash-verified main DLL. Main samples: 75.95% block extents, 19.33% matched
  object helpers, 2.20% run-slice export, 2.51% unassigned. Six mapping tests
  passed; full sample IP/RVA/load-interval and process/build identities checked.
  Out-of-line compiled lookup/load helpers are distinct from host callbacks.
- E020: FPX-only FP32 outlining published with focused tests; ABI5/FM1 output
  hashes unchanged. Generic benchmark passed 65,536 full-context comparisons
  and deliberate mismatch detection; 122-op native extent fell 97.65%, explicit
  stack allocation 65,176 -> 48 bytes. Separate candidate export has the same
  game/module/coverage manifest as baseline; runtime definitions contain all
  three outlined helpers. Four-module build subsequently completed in E021;
  baseline artifacts and generated inventory are preserved.
  Main generated C shrank 24.0% (3,230,233,647 -> 2,455,910,697 bytes) with the
  same 112 source units and coverage inventory; game FPS remains unmeasured.
  Separate-build launcher/profile reuse passed 27 synthetic isolation/rejection
  checks. Candidate/control staging commands are in RUNBOOK.
- E021: main finished at 15:02:11 UTC after 4,051.7 seconds. All four candidate
  DLL identities match the completed build. Five baseline-hot blocks retain
  identical guest index/side-entry spans and verified native/object mappings;
  explicit block stack allocations fell 66,024/113,064/83,448/240/352 ->
  112/144/144/64/56 bytes, excluding callees. Candidate ABI6/features7, generation
  guards, fastmem and FPX handshake/runtime-on were observed. User replayed the
  first Story level/action, reported good movement/effects and some stutter.
  At that point audio, death/restart, saves and later routes remained open. Hybrid policy remains
  JIT-capable; zero recorded transitions is not strict/no-JIT proof.
- E023/E024: controlled setup completed opening action with working Bluetooth,
  shooting and audible/stable audio reported by the user. Native trace saved
  normally and was mapped against verified candidate images and preserved host
  labels. Combat remains slow; target compiled lookup/load paths next. Save,
  death/restart, original music fidelity and later routes are unverified.
- E025: core 284f411686 removes redundant segment searches for impossible probes
  when the full block index exists. Synthetic miss timings improve; total
  fixture lookup code shrinks 281 -> 273 bytes. All five runtime smoke variants,
  guards/races and coverage loop pass. No game export/build or FPS result yet.
- E026/E027: four lookup-candidate modules completed and verified; unused future
  stage preserved. Separate boot/title check loads/negotiates every image and
  advances compiled counts with zero observed fallbacks. Both owned test
  processes are closed. New candidate combat performance/correctness is pending.

## Active task state

| ID | State | Evidence / next condition |
|---|---|---|
| R00 | Complete | Pinned source built suyu/suyu-cmd; command-line host smoke exited 0; exporter RPC worked (E010) |
| R01 | Complete for fixed exported modules | Four-module Hybrid ABI 6 source/manifest exported successfully; late-loaded/generated code remains unverified |
| R02 | Complete | Four DLLs/hash evidence; matching host handshakes; advancing AOT counts; rendered title (E013) |
| R03 | Opening action checked; broader behavior pending | E021 movement/effects good; E023 Bluetooth/shooting/audio fine; saves/death/restart/music fidelity pending |
| R04 | Pending R03 | Iterative coverage/translation fixes with focused tests |
| R05 | Pending validated routes | Strict-static zero-fallback tests, then separate no-JIT verification |
| R06 | Lookup candidate built; compiled boot checked; combat comparison pending | E025 checks, E026 four-image verification/staging and E027 advancing AOT counts pass; user-led recorded route next |
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
   RUNBOOK. Baseline source is 5949cab3ba; playable FP32 source is 84568fcadc;
   lookup candidate source is 284f411686 (built/staged E026, compiled boot E027).
   Its build/recomp/zarvot-lookup-miss/build-status.json is complete. Do not
   rebuild it or confuse it with the earlier FP32 target.
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
   E017 is the preserved profiled baseline: build/zarvot-runs/20261011-030031-b40a1ca6
   (UTC run ID; started on October 10 locally). Historical game PID 7872,
   lifetime recorder PID 21728 and elevated CPU recorder PID 28904 have finished.
   Native profile cpu-profiles/20261011-030437-c0fcc6ec/cpu-profile.json records
   a successful 1,995,440,128-byte cpu.etl save and process_exited end reason.
   The first non-elevated attempt failed without starting a session; retain it
   separately. Local interval/coverage review: analysis/20261011-031128.
   E018 native exports are under that profile's analysis directory: full
   20261011-031452-6d9ad68b, combat 20261011-031644-3bb647f2, title
   20261011-031647-dcec9403. Host/export range attribution and local prototypes
   are in host-attribution. E019's verified main mapping is under
   generated-mapping/main-combat-v3. Use capture-bounded combat
   03:06:40-03:08:10 UTC, not an assumed hit timestamp. E020 validated and
   exported the FP32 outlining candidate; its separate runner completed all four
   modules at 15:02:11 UTC. E021's initial candidate run is closed:
   build/zarvot-runs/20261011-151415-850d42f2 (historical PID 31416). It used the
   rebuilt host and post-E017 profile, so it is an exploratory comparison.
   Preserved-baseline host plus E016 profile is verified/staged separately at
   build/zarvot-runs/20261011-152125-1090520b; no game/recorders started there.
   E022 closed before combat because the Bluetooth controller did not control
   the game. Run build/zarvot-runs/20261012-002546-8ac4669a retains 84 complete
   UI/file reports with zero transitions and a successfully saved 809,500,672-byte
   CPU trace; it is startup evidence, not a combat comparison. Recorders finished.
   E023 is the user-requested retry after connecting Stadia before launch:
   build/zarvot-runs/20261012-003140-dc25d36d. Read reports/e023-active-run.json
   and reports/e023-recorders.json; verify current game and recorder state.
   CPU profile is cpu-profiles/20261012-003248-38053670; it completed with a
   2,545,942,528-byte trace and no error. User confirmed input/shooting/audio,
   performance about the same. E024 full native export is analysis/
   20261012-004109-4738000c; capture-bounded combat is 20261012-004418-56508734.
   Main/SDK mappings are generated-mapping/main-combat-v1 and sdk-combat-v1;
   preserved-host labels were independently verified in host-attribution.
   Do not tune general emulator settings or
   assume that a synthetic gain is a gameplay gain.
   Collect the user's observations before marking any gameplay/audio check passed.
6. Append evidence and update the relevant R row after each meaningful result.

## Identities and preserved local evidence

- Checkout: source/; branch: zarvot-support; origin: nate-santos/zarvot-recomp;
  upstream: dougchansan/mk8-recomp. Workspace root is not a Git repository.
- Wrapper base db36cf5; baseline suyu 5949cab3ba93233ddd1c319bfc6f010f6cfa910a;
  playable FP32 candidate 84568fcadc2b8f062022180b6492d0d8975f4d34;
  validated lookup source 284f411686160ceaf7ecaead936148c7de5cfe53 in the core fork.
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
