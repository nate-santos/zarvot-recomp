# Zarvot experiment ledger

Append results; do not rewrite an unsuccessful experiment as a success.
Raw files remain local. Sanitized summaries can be committed.

E001-E005 are historical JIT/setup records under the retired Z roadmap.
E006 resets scope; subsequent work uses PLAN.md R milestones. Old next-action
statements remain historical and do not override the current STATUS queue.

## E001 — Initial JIT boot (2026-10-04)

- Task: Z01; check whether the existing runtime can load the supplied game.
- Game: Zarvot base application 1.0.0, title ID `0100E7900C4C0000`.
- Runtime: Windows asset v0.0.12; UI/log reports v0.0.11,
  `HEAD-40aeb31824-HEAD`. Dynarmic JIT, Vulkan, handheld, 1x.
- Host: Ryzen 7 5825U, integrated AMD Radeon; reported available host RAM
  13.85 GiB, dedicated GPU budget 2.00 GiB, Vulkan 1.3.250.
- Result: decrypted loader reports `is64=1`; title screen rendered. Local
  screenshot `reports/zarvot-first-frame.png` was visually inspected.
- Telemetry snapshot: about 60.05 FPS, 16.66 ms, static backend inactive.
- Audio: 48 kHz stereo cubeb stream opened. No listening comparison or audio
  capture was completed; original-music fidelity is unverified.
- Limitation: title screen only, no controlled benchmark or gameplay coverage.
- Quirk: launch RPC exceeded its 30-second timeout but the game continued
  loading successfully. Check process/state before retrying a timed-out launch.
- Decision: preserve JIT as the initial reference; AArch64 makes an AOT
  feasibility experiment possible, not a guaranteed optimization.

## E002 — Foreground/focus investigation (2026-10-04)

- Task: Z01/Z02; investigate inconsistent title-screen FPS.
- Observation before activation: approximately 33 FPS; image still title screen.
- After activating and focusing the game: approximately 60 FPS; keyboard C
  advanced to the main menu, with Story selected.
- Hypothesis: visibility/focus/background state contributes to the discrepancy.
  Not yet a controlled paired test; do not claim an engine speedup.
- Decision: benchmark visible, foreground gameplay under consistent conditions.
  Title/menu samples are not valid substitutes for combat or scene transitions.
- Follow-up: 15 approximately one-second samples at the foreground main menu
  averaged 59.999 FPS (reported samples 59.945–60.080). Raw local evidence:
  `reports/title-foreground-samples.json` (legacy filename; the scene was the
  main menu). These are polling samples, not a per-frame benchmark.

## E003 — Opening Story gameplay baseline (2026-10-04)

- Task: Z01; user requested gameplay performance first.
- Runtime/game/backend: same identities as E001 and RUNBOOK.md; Dynarmic JIT,
  Vulkan, handheld 1x, HIGH accuracy, speed limit 100%, multicore enabled,
  disk shader cache enabled, asynchronous shaders disabled. Compared these
  configuration entries before/after: unchanged. TAS input was enabled with
  looping disabled; no rendering or CPU accuracy change was made.
- Environment: Ryzen 7 5825U, integrated Radeon; Windows Balanced scheme;
  AC online/charging at the power-source check; 60 Hz display. AMD Windows
  driver `31.0.21024.2004`, reported date 2023-08-22. WMI reports two 8 GiB
  memory modules at 3200; channel configuration and temperatures unverified.
- Save: backed up the existing 390-byte save before entering Story. Continue
  did not load a scene; New Game reached the opening jar scene. The game wrote
  a 432-byte save. Original backup remains local; no save data was published.
- Input: brief injected keyboard taps were unreliable in menus. The runtime's
  own TAS playback reliably delivered held A and D-pad inputs. Confirmed Story
  entry, dialogue advancement, shooting, movement out of the enclosure, pause
  and restart-level behavior. Added reusable input and sampling scripts.
- Route: Story > New Game > opening jar dialogue > repeated A presses until
  the `Pew Pew` tutorial with enemies firing. Three approximately 60-second
  samples held A with neutral sticks. Run 2 followed a level restart/dialogue
  replay; run 3 continued the encounter. These are repeated scene observations,
  not identical deterministic routes: enemy/respawn and camera phases varied.
- Cache: existing disk cache retained; scene visited before timed samples.
  Cold boot/first-time shader compilation was not benchmarked separately.

| Run | Duration (s) | Polls | Mean FPS | Median FPS | Minimum reported FPS | Polls below 55 | Mean GPU 3D (%) | Mean CPU core equivalents |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 60.585 | 58 | 57.862 | 59.998 | 11.994 | 3 | 52.95 | 2.479 |
| 2 | 60.621 | 58 | 57.447 | 59.997 | 1.001 | 4 | 48.57 | 2.518 |
| 3 | 60.611 | 58 | 57.395 | 59.998 | 0.000 | 4 | 49.98 | 2.497 |

- Steady readings cluster near 60 FPS, but brief severe drops recur around
  observed hit/fade/restart effects. Do not call this stable 60 FPS gameplay.
  Run 2 includes a reported 1233 ms frame interval; this is not a p99 metric.
- Run 3 also recorded VBlanks: two low-FPS polls reported 0 VBlanks/s; recovery
  polls reported about 60 VBlanks/s while rendering 34–46 FPS. Thus the drops
  cannot all be dismissed as a deliberately lower rendering rate. The speed
  counter remained about 1.0 and did not reveal them; it is insufficient alone.
- Peak observed GPU 3D use was 62.6%; steady-state aggregate process CPU use
  was about 2.5 logical-core equivalents. Working set peaked at 6.16 GiB.
  These counters do not identify the critical thread or exclude short GPU,
  synchronization, allocation, scheduling or shader stalls. Polling saw zero
  shaders building, but can miss compilation between polls. No bottleneck
  attribution or optimization speedup is established.
- Raw local evidence: `reports/z01-tutorial-run1.json` through `run3.json`,
  `reports/z01-opening-dialogue.json`, `reports/z01-sampler-smoke.json`,
  `reports/z01-opening-gameplay.png`, config and save backups under `reports/`.
  Native UI observations also verified gameplay and the final pause menu.
- Tool verification: both PowerShell files parse; the input helper advanced
  real menus/gameplay and guards against overlapping playback; the sampler completed
  its smoke check and all three runs with live GPU/process counters. GPU counter
  discovery is performed once to reduce measurement overhead.
- Limitations: interval polls, no true per-frame trace/1% lows/p99; no heavy
  later-level, moving-route, original-hardware timing or audio fidelity test.
  Audio work was deferred for this session's gameplay focus. Focus was checked
  via visible native snapshots, not continuously validated by the sampler.
- Decision: retain the existing JIT/1x/HIGH reference. Prioritize stall diagnosis
  and a moving combat fixture before pursuing extra AOT coverage. Do not claim
  that lowering resolution, changing accuracy or increasing native coverage
  solves these drops without an equivalent-scene comparison.
- Handoff: game left paused at the opening tutorial, TAS stopped, loop off.
  Resume via M or the pause menu. See RUNBOOK.md for repeatable tool commands.

## E004 — Measurement preparation and manual-playtest handoff (2026-10-04)

- Task: Z01; refresh the measurement workflow and remove unrelated MK8 README
  content. User subsequently chose to perform playtesting later and end session.
- Control: same executable SHA-256 and 1x/HIGH JIT profile as E003. Verified AC
  online and Windows Balanced scheme. Save and profile backed up locally to
  `reports/e004-save-before-test/` and `reports/e004-config-before.ini`.
- A hand-authored movement/fire route completed a 10.533-second sampler smoke
  check: 10 polls, mean 53.900 FPS, median 59.997, minimum 0, one poll below 55.
  This is a short functional check, not a representative benchmark or speedup.
  Raw evidence: `reports/e004-moving-warmup.json`. Opening encounter completion
  was not verified; user clarified that pursuers must be shot to progress.
- PresentMon 2.6.0 portable executable verified against its GitHub release SHA:
  `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`.
  Its five-second ETW capture attempt failed with Windows access denied and
  produced no trace. No per-frame percentile or 1% low is available. No Windows
  group/security changes were made. [Tool source](https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0).
- User-directed change: stop automated gameplay; prepare recording for their
  later test. New `zarvot-benchmark.ps1` wraps interval sampling with a countdown,
  saved-setting/hash metadata and manual scene notes. It sends no inputs and
  rejects a paused game or active TAS at start. Sampler records emulation-thread
  state and counts stopped-thread/TAS-active polls without filtering FPS drops.
- README now presents the real E003 results, method and limitations. No fresh
  full-length representative run was completed this session. Keep tutorial
  observations distinct from the pending manual-playtest baseline.
- Prototype movement/restart fixtures and extended input helper were archived
  locally under `reports/`; the tracked input helper remains its prior version.
- Verification: all four Zarvot PowerShell scripts parsed; README local links
  and Git whitespace checks passed. Live paused-game guard rejected capture,
  wrote no benchmark and left emulation/TAS stopped. A full manual-wrapper run
  remains untested until the user plays.
- Decision: defer further measurements until the user returns. Last RPC state
  was paused with TAS stopped; no further control commands were sent.
- Next: user's three matched 60-second gameplay runs, then review scene/focus,
  pauses, stalls and counters before Z02/Z03 changes. Music fidelity still open.

## E005 — User-requested Windows build tool installation (2026-10-04)

- Task: install CMake and a C compiler; prerequisite setup for future Z04/Z05.
- Before: neither CMake nor a registered MSVC toolchain was installed. Historical
  comments in inherited build scripts described another machine and were not
  evidence of this host's tool availability.
- Installed through Windows Package Manager's verified packages: Kitware.CMake
  4.4.3 and Microsoft.VisualStudio.2022.BuildTools 17.14.41, with the VCTools
  workload and recommended components (C/C++, Windows SDK and bundled Ninja).
- Verification: installer returned success; vswhere reports a complete,
  launchable Build Tools installation with no reboot required. CMake identified
  both C and C++ compilers as MSVC 19.44.35229.0. Project find-vcvars.ps1 located
  the installed environment. A Release/Ninja smoke project configured, compiled
  and linked both languages; both executable tests passed (2/2).
- Local smoke source/build evidence: workspace reports/toolchain-smoke/.
- CMake is on the machine PATH for newly opened terminals. MSVC and bundled
  Ninja are available through the x64 developer environment used by the build
  scripts; no manual global compiler PATH changes were made.
- Limits: this verifies a working host toolchain only. No emulator source build,
  hybrid export, gameplay performance or audio fidelity claim follows.
- Decision: keep tools installed. Preserve the pending user-led manual playtest;
  emulator sessions, saves and configuration were not changed.

## E006 — Recomp-only scope and roadmap reset (2026-10-05)

- Type: user-directed planning decision, not a performance experiment.
- Request: work only on recomp improvements, coverage and correctness; replace
  the emulator optimization plan and progress tracking.
- Review: local inherited history through db36cf5, static campaign/rendering
  findings and current Zarvot docs. Many core commits are submodule pointers;
  the suyu working directory was empty, so implementation was not inspected.
- Upstream leads: actual AOT dispatch (687e4ac), added instruction/target coverage,
  branch chaining/dispatch (432a706), correctness fixes, then compiler, fast
  memory, generation guards and native exact FP improvements (db36cf5).
  Upstream performance reports are not locally reproduced Zarvot results.
- Decision: retire Z optimization queue; introduce R00-R08 with independent
  build, coverage, correctness and performance acceptance. Start R00 source/
  exporter/runtime alignment, then export/compile/prove Zarvot AOT execution.
  Fresh JIT benchmarks and GPU bottleneck classification are not prerequisites.
- Updated PLAN, STATUS, README, RUNBOOK, project index and handoff instructions.
  E001-E005 and E005's pre-existing uncommitted toolchain findings are preserved.
- Scope excludes general emulator settings/performance work. Existing HLE/GPU/
  audio remains support infrastructure; recomp integration changes are in scope.
- Validation: documentation consistency, local Markdown links and Git whitespace
  checks only. No source build, export, runtime control or gameplay test occurred.
- Next: R00. The user still handles gameplay; no automated play authorized.

## E007 — Matching recomp host/exporter build preparation (2026-10-05)

- Task: R00. Recomp plan and agent handoff committed as 5c6156a on zarvot-support.
- Initialized pinned suyu source 5949cab3ba93233ddd1c319bfc6f010f6cfa910a.
  Inspecting current source confirms export RPC and AOT execution telemetry,
  plus ABI 6 memory, generation-guard and exact FP support. No core edits made.
- Prepared workspace-local Python venv/aqtinstall 3.3.0, Qt 6.9.3 with charts/Svg,
  and glslang 16.5.0. MSVC/CMake detected correctly during configuration.
- Git submodule initialization failed in the restricted shell (missing shell
  utilities), then succeeded in the desktop environment. Commit identity used
  the same author as prior Zarvot commits, through per-command configuration.
- Build helper now bounds compilation to two jobs by default and validates its
  build-root boundary before optional cleanup. No cleanup was performed.
- Initial configuration was interrupted to apply bounded parallelism, then
  restarted using cached dependencies. Configuration/build started here;
  E010 records successful completion after an incremental four-job resume.
- Evidence: reports/r00-build.log and ignored source/build and local/tools trees.
- Synthetic checks: inherited shifted-register, translation and side-entry tests
  passed against the pinned emitter. The side-entry suite built/loaded generated
  synthetic C and verified a mutated instruction was refused by guard-v2.
- Limits: no Zarvot AOT export, module compilation, execution or gameplay test.
- Next: finish R00, then inventory/export and compile Zarvot (R01/R02).

## E008 — Explicit export backend and rejected-request checks (2026-10-05)

- Task: R01 preparation while the R00 host build runs.
- Observed current source: aot_test_export accepts a backend and returns action
  acceptance before scheduling export; export completion is a separate status.
- Export driver now accepts --backend hybrid/static/dynarmic and validates local
  input paths. Existing callers can retain the dialog setting by omitting it.
- Rejected/malformed RPC replies, connection resets and export-action timeouts
  no longer masquerade as success. Only the modal dialog-open timeout is allowed.
  The status hint now points to the existing mcp-call.py tool.
- Validation: six offline tests passed, covering explicit hybrid forwarding,
  accepted-but-pending status, missing dialog, protocol/unknown replies, timeout
  boundaries and connection reset. --help parsed successfully.
- Limits: no live export yet. Acceptance is not artifact/build/execution proof.
- Next: after R00 succeeds, use an explicit hybrid export and check final status,
  generated manifest and matching module build; then prove AOT execution (R02).

## E009 — Recomp counters in manual observation tooling (2026-10-05)

- Task: R02 evidence preparation while R00 compiles.
- The read-only Zarvot sampler previously retained static_backend_active but
  omitted execution counts. It now also retains static_blocks, jit_transitions,
  jit_available and guard_v2_ready in every observation. Missing fields remain
  unknown rather than being converted into zero/false.
- These raw counters support later execution/coverage review; FPS or backend
  selection alone is not proof. Compare increasing counts within one session
  and inspect fallbacks. No automated correctness verdict is introduced.
- Validation: PowerShell syntax passed. Live AOT capture remains untested until
  compiled Zarvot modules exist. Recorder still sends no control commands.
- Next: complete R00/R01, load built modules and collect execution evidence.
## E010 — Matching host build, Hybrid export and first compiled module (2026-10-05)

- Tasks: R00 completed, R01 completed for fixed modules, R02 started.
- Source: pinned suyu 5949cab3ba93233ddd1c319bfc6f010f6cfa910a, unchanged.
  Release/MSVC 19.44.35229.0, Qt 6.9.3, CMake 4.4.3, glslang 16.5.0.
- Host build: both suyu and suyu-cmd linked. Started at two compiler jobs, then
  resumed incrementally at four after checking available memory; resume took
  18.7 minutes. No exact combined duration recorded. suyu-cmd --version launched
  and exited 0; Windows subsystem produced no captured version text.
- Matching GUI host started with a separate portable user profile and RPC port
  9743. Copied supplied keys locally; original player profile/saves untouched.
  Export RPC accepted the explicit Hybrid request and later reported done=true,
  success=true. No controller input or automated gameplay occurred.
- Export: ABI 6, features 7 (FM1/GG1/FPX1), translate_all=true, fallback=true,
  requires_runtime_codegen=false. Main/rtld/sdk/subsdk0 build IDs are in the local
  manifest. Fixed-module export does not establish runtime-loaded-code coverage.
- Manifest reports 2,560,754 analyzed blocks and 10,826,444 instructions. Emission
  logs use separate counts; do not equate analyzed blocks with executed blocks.
  Emitted unhandled counts: main 15,687 (0.18%), rtld 9 (0.57%), sdk 3,400 (0.27%),
  subsdk0 741 (0.09%). Mostly reported reserved/unallocated signatures; whether
  any execute remains unknown. These are not runtime coverage percentages.
- Generated C units/source size: main 112 / 3,080.6 MiB, rtld 2 / 0.4 MiB,
  sdk 16 / 334.8 MiB, subsdk0 12 / 216.2 MiB. Main build scale is a concrete
  compiler/resource concern, not a measured runtime-performance defect.
- rtld: MSVC DLL build succeeded (150,016 bytes). Generated CMake selected one
  concurrent compile on this RAM configuration. Build helper now permits bounded
  parallelism and checks source/build roots before reuse/cleanup. No cleanup used.
- Partial loading check: one compiled module loaded, ABI 6 fastmem negotiated.
  Boot RPC timed out. Later state reported game_running=false, static backend
  inactive, static_blocks=0 and jit_transitions=0. This proves loading only.
  Current source opens a firmware preflight dialog in the fresh profile, which
  has no firmware: leading startup explanation, not visually confirmed.
  Computer-use window inspection timed out awaiting app approval; no dialog or
  controller input was sent. Owned smoke host stopped; final process check found
  no suyu process. No gameplay, advancing AOT, strict-static or no-JIT claim.
- Evidence: reports/r00-build*.log, r00-emitter-tests.log, r01-exporter.log,
  r01-export-status.json, r02-rtld-build.log and r02-partial-*; ignored generated/
  and build/ artifacts. Executable/DLL hashes and commands are in RUNBOOK.
- Decision: retain matching build and generated source. Next R02: compile remaining
  modules, resolve startup preflight through the supported interface, and record
  advancing compiled execution. User still handles gameplay tests. General
  emulator performance tuning remains outside scope.
## E011 — Push recomp history and continue sequential module builds (2026-10-05)

- Task: R02. User authorized pushing commits and emphasized allowing slow builds
  time to finish. Commits 5c6156a through 07ec10f pushed to origin/zarvot-support;
  initial GitHub sign-in wait resolved after the user signed in.
- SDK build succeeded with the existing MSVC 19.44 toolchain: 7.0 minutes,
  110,612,992-byte DLL. SHA-256:
  da0fb0ddb7496dc61f84a04459e3023e3712ba6d6137f87d0431c938f393bf45.
  Generated units use /O2 /bigobj /fp:precise with /we4293 retained. No compiler
  flags, correctness guards or game settings changed. clang-cl was not found.
- Added scripts/build-zarvot.ps1: sequential rtld/sdk/subsdk0/main builds,
  incremental reuse, four-module ABI 6 manifest validation and hash, per-module
  completion/DLL hash evidence, fail-stop behavior and an exclusive runner lock.
  No overall build timeout. Lock covers this runner, not direct helper invocations.
- Validation: PowerShell syntax and Git whitespace checks passed. Synthetic local
  fixtures verified completion hashes, compiler-failure stop/status, duplicate
  runner rejection and changed-export rejection. No fixture contains game code.
- Live runner reused rtld/sdk with Ninja reporting no work, then started subsdk0;
  main is queued next. Build completion and execution are still unverified for
  these remaining modules. Active state is local build/recomp/zarvot/build-status.json;
  raw evidence reports/r02-sdk-build.log, r02-module-set-build.log and
  r02-build-runner-tests.log. Inspect processes before resuming an active build.
- Source review: GUI maps loaded images by module/name/load order, while the
  current CLI maps a compact vector of present DLLs by load index. A missing
  middle image can misbase later CLI images. Do not use the CLI for partial sets;
  wait for all four fixed modules. No core change or runtime proof made here.
- Decision: retain sequential memory-aware builds and explicitly preserve the
  user's slow-build instruction in the tracked handoff/plan. Continue R02, then
  collect advancing AOT counts and categorized fallbacks with the matching host.
  Gameplay stays user-led; no emulator-performance work or speedup claim.

## E012 — Third compiled module; main build left active (2026-10-05)

- Task: R02, continuation of E011. The live sequential runner completed subsdk0
  without errors: helper reported 2.8 minutes; runner recorded 173.48 seconds
  including configure/artifact recording. DLL is 67,680,768 bytes, SHA-256
  3f1d06e16fd61446d11d838e7c7bc0c04dc35f886fa5f1d7356ace47c3010ec8.
- Main configured with MSVC and the same one-compile pool, then began its 115
  build steps. Compiler activity and new object/log progress confirmed a healthy
  ongoing build; no build error observed. It is left active with no timeout.
  Main DLL completion remains unverified: inspect live build-status.json and
  processes rather than assuming this handoff still describes current state.
- No game session started, no controller input sent and no settings tuned.
  Three completed DLLs establish build progress only; AOT execution, hybrid
  correctness, strict-static and no-JIT validation remain pending.
- Tooling/slow-build handoff commit 4be4b13 pushed to origin/zarvot-support.
  Raw progress and module hashes remain in the E011 evidence locations.
- Next: let main finish, verify the complete module set, then boot the matching
  host in a separate profile and retain increasing AOT counts plus fallback
  evidence. CLI requires the full module set because of the E011 mapping finding.

## E013 — Complete module set and prove compiled boot/title execution (2026-10-05)

- Tasks: R02 complete; R03 boot/title evidence prepared, gameplay pending.
- The long main build finished successfully after 210.9 minutes (12,656.15
  seconds including configure/artifact recording). Main DLL is 1,509,548,544
  bytes, SHA-256 15d3bb4d96a40bd93a89f6e91381ee3728dac59a40b39ba953fd3b1f8509ce16.
  Build-status records all four modules complete. Current manifest and every
  DLL size/hash matched that record; no rebuild needed. Source remains clean at
  pinned 5949cab3ba93233ddd1c319bfc6f010f6cfa910a; matching CLI hash unchanged.
- Added start-zarvot-recomp.ps1: verifies the complete set, stages copies beside
  the CLI in a unique local run directory and uses fresh portable config/saves.
  Supplied keys copied locally only; original player profile untouched. Clears
  inherited recomp/CLI diagnostic overrides for the child, then restores them.
  Rejects concurrent sessions. No export README, so installed keys/NAND paths
  are not selected by the export-package hook. Sends no controller input.
- First Hybrid-policy run loaded all four modules: ABI 6, guard-v2 ready,
  fastmem and FPX1 negotiated. Fresh default config initially selected docked;
  launcher corrected to use explicit native default flags for handheld. First
  snapshot pair: 3,589,809,639 -> 4,861,081,955 AOT blocks, zero transitions.
  Recorder later observed 7,680,340,123 -> 7,951,582,393, zero transitions.
  Captures progressed through intro/black transition to the visible title.
- Handheld repeat confirmed native config values: handheld, Vulkan, 1x/HIGH,
  100% speed, TAS disabled, local NAND/save paths. All four images/handshakes
  passed again. A 30-second recorder run observed 7,312,156,998 -> 8,419,406,636
  AOT blocks with zero lookup/opcode transitions and zero unresolved import
  traps in the reports. Title-screen captures retained; no gameplay input sent.
- Added measure-zarvot-coverage.ps1: preserves timestamped raw reports and JSON,
  verifies executable/PID/start time, retains absent/partial telemetry as unknown
  and reports counter advancement separately from correctness/performance.
  Live validation caught PowerShell's automatic JSON date parsing; normalized
  timestamps before comparison. Both live recordings then passed. Syntax,
  staging/configuration and concurrent-session rejection checks passed.
- Nonfatal recomp relocation diagnostics: eight unresolved rtld GOT/PLT symbols
  (__EX/__got boundaries and TLS alignment symbols), despite zero runtime import
  traps. Keep them in R03 diagnosis; no core fix or benignness claim follows.
- Uncontrolled title interval readings were roughly 20-27 FPS after startup.
  No matched-route benchmark, frame trace or speedup claim. Generated-code
  size/build cost and compiled execution efficiency remain R06 work; general
  emulator tuning is not introduced.
- These were JIT-capable Hybrid-policy runs (SUYU_NO_JIT=OFF, strict requested
  false). Zero observed fallbacks supports boot/title coverage only. Strict,
  no-JIT, gameplay, input/save correctness and audio fidelity remain unverified.
- Local evidence: build/recomp/zarvot/build-status.json; reports/r02-module-set-build.log;
  build/zarvot-runs/20261006-012917-5168873f and 20261006-013402-d8d4938a,
  each with launch/config/logs/captures/coverage/observations and shutdown record.
  Both owned smoke processes closed gracefully. No emulator remains running.
- User chose to prepare gameplay checks for later. PLAYTEST.md records the open
  R03 route; completed builds/proof retained. Next: user-led Story checks with
  the recorder, then categorize/fix actual coverage or correctness gaps. No
  fresh export/main rebuild unless an affected source change requires it.

## E014 — Start user-led recomp gameplay recording (2026-10-05)

- Task: R03. The user requested playtesting, then continued the project. Actual
  process inspection found no emulator running; Git was clean and synchronized.
  All four completed DLL identities and the ABI 6 export manifest verified again.
  Reused the existing builds; no export, compilation or emulator tuning performed.
- Added an explicit -Visible launcher option for interactive playtests, with
  visibility recorded in launch metadata. Default background launches stay hidden.
  PowerShell syntax check passed and the visible launch succeeded.
- Started an isolated Hybrid session with fresh saves/config, original timing
  and the E013 handheld 1x/HIGH settings. All four module load messages and
  guard-v2/ABI 6/fastmem/FPX1 handshakes observed. Original player saves preserved.
- Started a separate hidden ten-minute coverage recorder, with its PID/start
  time recorded locally. The first 24 complete reports advanced from
  503,045,903 to 3,352,528,309 AOT blocks with zero lookup/opcode transitions and
  no recorder error. This is an interim boot observation, not a gameplay verdict.
  Initial capture visually inspected: rendered Zarvot intro. No input sent.
- Local evidence: build/zarvot-runs/20261006-021312-09bc211a, including launch,
  recorder metadata, captures, logs and observations/20261006-021332-9e8f960e.
  Workspace reports/r03-active-run.json points to this session. Check actual
  process/PID/path/start time on resume; preserve the active playtest and saves.
  Runtime coverage/captures continue after the bounded recorder finishes.
- Gameplay, input/save/audio correctness, strict-static, no-JIT and comparative
  performance remain unverified. PLAYTEST P01-P07 are still open. Next: collect
  the user's named Story route and observations, inspect its coverage/failures,
  then fix concrete recomp gaps. Leave the session open for the user.

## E015 — Diagnose reported combat stalls and fallback discrepancy (2026-10-05)

- Tasks: R03 diagnosis; R06 profiling preparation. The user reported severe
  frame-rate drops during combat, especially shot hit effects, and noticed JIT
  transitions. Exact mode/level and individual hit timestamps were not supplied.
  Inspected the E014 session without stopping it, changing settings or sending
  input. Executable/PID/start time still matched its launch record.
- The ten-minute recorder completed without error: 299 complete reports,
  503,045,903 -> 20,196,871,790 AOT blocks, zero observed lookup/opcode transitions
  and unresolved import traps. No observed counter regressions. Later coverage
  and the live window counter also showed zero transitions. The persisted gaps
  file was empty; no missing-PC/unhandled-opcode fallback log messages found.
- Source review: native window status and FormatRecompCoverage both read
  fallback_from_miss + fallback_from_unhandled. These count attempts including
  rejected strict fallbacks; no reset found. The user's observed transitions
  conflict with this recorded evidence. Keep the discrepancy open rather than
  declaring the observation mistaken or inventing a missing translation.
- The performance log confirms severe drops. Its 170-240s window contained 63
  interval samples spanning 1.0-16.0 FPS, including sustained 5-7 FPS readings.
  At 177.666s it reported 6483.369ms frametime; at 362.759s, 0.0 FPS and
  2429.148ms. These are reported interval statistics, not a per-frame trace.
- Pipeline activity coincided with multiple hitches: 35 creation messages in
  the 170-240s window and 32 in 355-366s. Source logs this on entry to pipeline
  creation, so these counts do not measure shader-build durations or prove
  causation. Cold graphics work is a lead; sustained combat CPU/GPU cost remains
  unattributed. No generic emulator/GPU settings tuning follows from this result.
- Inspected captures of a black transition, an arena with effects, combat with
  shots/score, and a pause menu over another scene. Gameplay clearly rendered,
  but movement/restart/death/save/audio correctness is not established. Updated
  PLAYTEST with partial observations, not passes. Strict/no-JIT still unverified.
- Added opt-in -SamplePc/-SampleAfterSeconds to the isolated launcher. It enables
  the existing runtime sampler after a boot delay and records its block interval
  and delay in launch metadata; no re-export/main build needed. Defaults remain
  unchanged. PowerShell syntax check passed; live sampling remains untested.
  PC counts rank executed locations, not wall-clock cost; sampling has overhead.
- Local evidence: E014 run's analysis/20261006-022157 holds preserved log,
  coverage/observation/gap copies, interval CSV, summary.json and REPORT.md.
  Performance-log snapshot ends at 489.829s; coverage recording continued longer.
  Raw evidence stays local. Original saves and current test session preserved.
- Next: name/repeat the combat section, collect compiled-PC plus native duration
  evidence, separate initial pipeline activity from recurring recomp cost, and
  reconcile any future nonzero transition with timestamp/PC/reason evidence.
  Fix measured generated-code/runtime costs or actual coverage gaps; do not
  claim a speedup, full correctness, or a fallback cause from these observations.

## E016 — Capture UI counters independently and validate compiled-PC sampling (2026-10-06)

- Tasks: R03 diagnostics; R06 sampling preparation. The user recalled a possible
  UI count of six, then reported no transitions in this new run and said the
  earlier observation may not have happened. They clarified there was no combat
  in the new run. Treat the earlier count as uncertain; no fallback gap is
  corroborated. E015's combat slowdown remains a separate open issue.
- Reworked measure-zarvot-coverage.ps1 to poll the owned process's exact caption
  independently of coverage. Retains timestamps, shader count, file age, partial
  reports, UI/file disagreement and counter regression evidence. -UntilExit
  removes the old ten-minute cutoff; full samples append to JSONL while the
  summary keeps the last 300 and all-history totals/maxima. Missing telemetry
  remains unknown. Normal exit and PID/path/start-time changes are distinguished.
- Added opt-in closed-test-profile cloning to the launcher. It verifies matching
  host/export/module identities, rebases isolated storage and preserves controls,
  saves and available caches. Original player profile untouched. Empty native
  storage defaults initially failed validation; corrected and regression-tested
  before launch. Foreign storage remains rejected. Six copied NAND files matched
  hashes and the source stayed unchanged; save-progress semantics remain untested.
- Existing four modules and matching CLI reused, with ABI 6/guard-v2/fastmem/FPX1
  handshakes observed again. Source, export and module hashes match E013; no
  rebuild/re-export or emulator settings optimization. Hybrid policy remained
  JIT-capable, with compiled-PC sampling every 2^18 blocks after 120 seconds.
- Live native window inspection matched a persisted caption for the same owned
  executable. All 146 samples had parsed UI counters and complete reports over
  291.604 seconds: AOT blocks 180,881,897 -> 13,386,471,882; zero observed UI/file
  transitions and import traps, no disagreements or regressions, no read error.
  Maximum observed report age 1.235 seconds. Recorder ended normally on process
  exit; subsequent process inspection confirmed game and recorder absent.
- Final coverage advanced further to 13,413,039,263 AOT blocks, with zero
  fallback/import traps and 1,222 distinct sampled PCs. Module-relative sampling
  is validated, but counts rank execution frequency rather than CPU duration.
  No native cost attribution, matched performance comparison or speedup claim.
- Inspected Story bedroom, dialogue and black-transition captures. These extend
  rendered-scene evidence beyond title; they do not establish movement, shooting,
  combat hit effects, death/restart, expected save progress or audio fidelity.
  User confirmed no combat. No gameplay input automated or process stopped.
- Three synthetic scripts passed: exact JIT versus shader caption parsing,
  large-counter precision and torn/inconsistent report rejection; storage
  rebasing/defaults/foreign-path rejection; real recorder with mocked UI=6/file=0,
  counter advancement, preserved JSONL and normal process exit. Script syntax
  checks passed. These validate tooling, not game translation semantics.
- Local evidence: build/zarvot-runs/20261006-035803-2d087b29; observations under
  20261006-035825-88778d25; final analysis/20261006-040756 contains preserved
  coverage/log/gaps, summary.json, timeline.csv and REPORT.md. Both test profiles,
  saves and generated modules preserved. Raw evidence remains ignored/local.
- Decision: retain the diagnostics and sampling preparation. Current evidence
  supports zero observed fallbacks on this noncombat route only. Two-second UI
  polls do not capture every instantaneous caption state; this run does not
  settle full-game coverage, strict/no-JIT execution or the earlier recollection.
- Next: named user-led combat capture with lifetime UI/file recording and PC
  samples, followed by native compiled-code/helper duration evidence. Fix actual
  recomp gaps or measured generated-code/runtime costs; finish behavioral/audio
  checks separately. Keep general emulator/GPU tuning outside scope.

## E017 — Record first Story combat with native CPU samples (2026-10-10)

- Tasks: R03 named user-led route; R06 compiled-cost attribution. The user
  proposed playing the first Story action sequence. Git was clean/synchronized
  and no emulator/compiler was active before launch. Reused the completed,
  hash-verified four-module set and matching host; no rebuild/re-export, source
  change or emulator settings optimization.
- Started build/zarvot-runs/20261011-030031-b40a1ca6 (UTC ID, October 10 locally),
  using a verified clone of closed E016's saves/settings/caches. Original player
  profile and prior test evidence preserved. Game PID 7872/start time recorded
  in launch.json; lifetime UI/coverage recorder PID 21728. Initial complete
  reports advanced compiled counts with zero UI/file fallbacks/import traps.
  These are interim boot observations, not a combat or full-coverage result.
- Added measure-zarvot-cpu.ps1: bounded CPU.Verbose file trace with a unique WPR
  instance, exact process identity checks, metadata/heartbeats and explicit
  start/save/cleanup errors. Normal game exit finalizes only the owned trace;
  the helper sends no gameplay input and never stops the game. Raw system-wide
  traces stay local and must be filtered to the exact game process/route.
- First non-elevated start returned 0xc5585011 and recording_started=false;
  no trace/session was claimed or cancelled. The user approved Windows elevation
  for the prepared recorder. Elevated recorder PID 28904 successfully started
  native CPU recording at 03:04:37 UTC; metadata heartbeat confirms recording.
  Limit: 900 seconds or game exit. Game exit finalized a successful
  1,995,440,128-byte cpu.etl save; elapsed recorder time including save was
  316.424 seconds, with no recorder/cleanup error. Usable samples/attribution
  remain under analysis. Both recorders and game have exited.
- Synthetic tests passed: full CPU/file-mode/temp-directory/instance arguments,
  unique ownership, normal save/exit, denied start without cleanup, foreign
  process rejection, PID reuse with owned save, and failed-save owned cleanup.
  Both new scripts passed syntax checks. These test tooling, not game semantics.
- Confirmed matching host PDB/map are available; generated AOT DLLs have no
  PDB/maps. Initial native attribution can separate compiled modules and host
  helpers; generated guest-function duration attribution is not yet established.
  Existing PC histograms remain execution-frequency data, not time profiles.
- Prepared official Microsoft PerfView 3.2.8 in ignored local/tools/PerfView.
  Its SHA-256 matches the release digest and Authenticode signature is valid.
  Actual CLI export help and bundled TraceEvent API availability were checked;
  no live ETL was read. Saved-trace export and attribution remain unvalidated.
- Inspected intro and later jar-arena combat/effects captures, including frame-14
  at 03:07:40 UTC showing a score HUD. Brought the owned game window forward. No
  controller/keyboard gameplay automated. Invited the user to reach first Story
  combat, move/shoot/hit enemies, repeat if practical, exit normally and report
  route, slowdown and input/audio behavior. The user confirmed playing the first
  action sequence with many slowdowns/bad frame rates. Frame-12 shows the opening
  jar arena/Pew Pew prompt; frame-17 shows a Story transition. Exact hit times
  and input/audio correctness remain unconfirmed. Save copy hashes after launch
  are partial (5/6 files unchanged); a live save can change and no semantic pass follows.
- Final coverage: 232 complete UI/file samples, AOT blocks
  1,769,111,829 -> 18,317,539,853; zero observed transitions/import traps,
  disagreements or counter regressions, no recorder error. Capture-bounded
  combat window 03:06:40-03:08:10 UTC contained 45 interval FPS readings,
  range 5.5-11.5, median 7, with 41 below 10. The title-menu window had median
  23.5 (30 readings, 19-25.5). These are different scenes, not a performance A/B.
  Local preserved logs/coverage, timeline and interval summary are under
  analysis/20261011-031128. Active pointer now records observed_exited.
- Diagnostic PC snapshots/histogram/coverage publication and periodic PNG
  encoding add work. Correlate capture times; no per-frame percentile or speedup
  claim. E015 hit-effect slowdown remains unresolved and E016 remains a scoped
  noncombat zero-fallback observation. No actual fallback gap is corroborated.
- Decision: preserve the closed test profile and evidence. Next: convert the
  saved trace, filter exact process and capture-bounded combat timestamps, attribute compiled/runtime
  CPU costs, and select a measured recomp fix. Collect PLAYTEST observations
  independently; strict/no-JIT and full-game correctness remain open.

## E018 — Attribute combat CPU samples to compiled modules and host ranges (2026-10-10)

- Task: R06. Analyze the saved E017 first Story action trace before another
  playtest or an optimization change. Source, host and four DLL identities remain
  unchanged. No game/export/build or emulator-settings changes were made.
- Added analyze-zarvot-cpu.ps1 for closed successful profile metadata only. Uses
  matching local PerfView TraceEvent libraries, caches derived ETLX, validates
  exact PID and independent full loaded-executable path, and preserves sample
  UTC/time, thread, IP/native RVA, module/category, image/thread maps and losses.
  Pre-trace process start is clamped to trace start; prior recorder identity
  checks remain necessary. Basename-only identity is rejected; unknowns stay explicit.
- Synthetic metadata/identity tests cover live/failed/foreign traces, another
  PID, path evidence, reused start time, UTC/local equivalence and pre-trace
  limits; native mapping covers 64-bit half-open image boundaries. Tests and
  syntax passed. Full trace/title/combat extraction passed; a cached empty range
  correctly returned zero samples. Fixed PowerShell optional EventPipe overload
  reflection by binding the ETL API in C#, without installing extra dependencies.
- First 1.996 GB conversion took about 70 seconds; cached title/combat exports
  about five seconds together. Trace session 03:04:37.868-03:09:42.015 UTC,
  sampling interval 1 ms, reported events lost 0. Full target-process samples:
  517,377; 373,520 compiled DLLs (72.20%). Save/rundown extends beyond game exit;
  process sample timestamps end around 03:09:19.54 UTC.
- Capture-bounded combat 03:06:40-03:08:10 UTC: 157,467 samples; compiled DLLs
  112,804 (71.64%), main 102,371 (65.01%), SDK 10,049 (6.38%), host executable
  20,733 (13.17%), unmapped 17,284 (10.98%). Title 03:04:40-03:05:40 had 122,350
  samples and similar proportions (72.09% compiled). These are different scenes;
  shares alone establish neither a speedup nor the frame-rate limit.
- Local host attribution checked host hash, matching PE/map timestamp and base,
  and PE/PDB/ETW debug GUID/age. Public labels were bounded by PE unwind ranges
  where available, preserving aliases. Combat ArmRecomp::RunThread: 2,274 leaf
  samples (1.44% of all); four exclusive callbacks combined: 341 (0.22%).
  Diagnostic sampler template: 162 (0.10%); an unbounded nearest SampleDiagnostics
  label: 259 (0.16%), with weaker attribution. No dominant host recomp helper
  emerged; host-side loads/stores/guards were not prominent standalone buckets.
- Largest host bucket Common::Event::WaitFor: 6,781 (4.31% of all samples).
  Its caller/cause is unproven. Compiled images also contain inlined helpers;
  small standalone callback buckets do not prove every helper path is cheap.
  PDB publics returned zero sizes, so no exact call-duration/inlining claim.
- Exact exported run-slice unwind extents contain 2,256 main and 682 SDK samples;
  100,115 main and 9,367 SDK samples remain outside that named function extent.
  They need generated-code/helper mapping. Native RVAs are not guest PCs.
- Local evidence under E017 cpu-profiles/20261011-030437-c0fcc6ec: analysis full
  20261011-031452-6d9ad68b, combat 20261011-031644-3bb647f2, title
  20261011-031647-dcec9403, plus host-attribution local prototypes/results.
  Raw ETL/ETLX, addresses, maps and generated material stay local. Share tooling
  and sanitized findings only. Recorder is committed/pushed in bf78a3d.
- Decision: keep analyzer and measured baseline. No speedup, full correctness or
  fallback cause claimed. Next map hot main native locations through existing
  segment tables/object symbols or a verified symbol map, then select one recomp
  change with semantic checks. Avoid a repeat main compile just for symbols;
  preserve code guards, original timing/music and the completed module set.

## E019 — Map compiled combat samples to generated blocks and helpers (2026-10-11)

- Task: R06. Reused E017's closed combat trace and completed baseline images;
  no export, game launch, input or rebuild. Added zarvot_native_map.py and six
  synthetic tests. The isolated helper calls only ABI/base/index metadata exports,
  never a generated block. Raw addresses and generated mappings remain local.
- Before loading the image, verify canonical completed build, manifest and DLL
  hash/size, recorded isolated run root, CPU analyzer process identity and full
  module path. Check PE size and every selected sample's loaded-image interval,
  instruction pointer and RVA. Recover guest-word spans from existing index
  pointers; assign native block extents only at exact x64 unwind starts.
- Runtime/dispatch labels come from existing COFF object bytes, matching every
  nonrelocated byte and retaining aliases/ambiguous candidates. Six tests passed
  PE/COFF boundaries, relocation masks, aliases/null index gaps, build/process
  identity rejection and sample IP/RVA/load-interval rejection.
- Main combat: 102,371 samples; 77,755 in 15,396 indexed block functions
  (75.95% of main; 49.38% of all combat samples), 19,789 in 22 matched object
  helpers (19.33% of main; 12.57% of all), 2,256 in run-slice (2.20% of main),
  and 2,571 unassigned (2.51% of main). Lookup accounts for 7,269 main samples,
  load64 for 4,777 and load32 for 2,879. These compiled helpers are separate from
  E018's host callbacks; inlined costs remain inside their containing functions.
- Top five block buckets have 3,471 / 2,875 / 2,098 / 2,029 / 1,943 samples.
  Their native extents are 602,112 / 957,092 / 759,360 / 106,544 / 28,576 bytes.
  Local source inspection finds many FP32 add/sub/multiply operations; the top
  block contains 122 FPX operation sites. Its native prologue reserves 66,024
  bytes of stack. These observations motivate a footprint experiment; they do
  not prove exact helper duration, executing guest instruction or the FPS limit.
- Local evidence: E017 cpu-profiles/20261011-030437-c0fcc6ec/
  generated-mapping/main-combat-v3, plus host-attribution prototypes. Generated
  samples, addresses, objects and binaries stay ignored. Baseline preserved.
- Decision/next: test sharing unchanged FP32 exact fallback bodies in runtime.c,
  retaining the native FPX gate at each lane and original flags/rounding/alias
  behavior. Compare actual emitter output to the immutable baseline with full
  state checks, negative controls and repeated quiet synthetic timings. If kept,
  publish the source fork and export/build a separate candidate, then repeat the
  same user-led combat route. R03 behavioral checks remain open independently.

## E020 — Outline exact FP32 fallbacks in compiled code (2026-10-11)

- Task: R06, following E019's hot generated blocks. Change only FPX-on binary32
  add/sub/mul code generation: keep each lane's native gate inline and call
  shared noinline exact helpers for fallback arithmetic. The helper bodies use
  the same emitter text. Preserve operand snapshots, sign-matched zero, FPCR,
  sticky FPSR, guards and original timing. Fused forms and binary64 stay inline;
  ABI/layout/features are unchanged. Shadow results/flags agree; its operand
  diagnostics now retain the original captured bits rather than fallback-local
  mutated operands. No blanket fast-math, emulator settings or JIT optimization.
- Core commit `84568fcadc2b8f062022180b6492d0d8975f4d34` published to
  nate-santos/suyu-zarvot-recomp, branch zarvot-support, from pinned 5949cab3ba.
  GitHub redirects the former dougchansan/suyu-v0.0.4 repository to
  suyu-emu/suyu-main; fork creation retained history, without merging its newer
  head into the candidate. Parent submodule URL/pointer follows this fork.
- Full focused harness: 76,477,440 value/FPSR comparisons, zero mismatches;
  458,752 whole-context checks across 14 scalar/vector/pair/indexed alias cases.
  Native and exact paths both exercised. Negative controls failed as designed
  (nokeep 80,708; nomid 5,039; MXCSR 209,703 mismatches). Inhibit: 729,088 checks,
  zero mismatches; shadow retained 534,966 fast results with zero differences;
  repaired host FP environment passed. Initial sandbox C1902 was a compiler
  setup failure; the same toolchain/tests passed outside that sandbox.
- Full synthetic integration smoke passed coverage and ABI5, ABI6/FM1,
  ABI6+GG1, FPX and GG1+FPX static/shared variants, guard controls and races.
  ABI5/FM1 golden output unchanged. Only the intentional FPX runtime/header/
  export/CMake delta changed its golden hash. Independent source review found
  no actionable defects. No architectural hardware oracle ran on this x64 host.
- Generic benchmark uses independent generators against immutable baseline and
  actual candidate headers, MSVC /O2 /Ob2 /bigobj /fp:precise /MD, no LTO or
  shadow/probe timing. 16-op and 122-op models passed 65,536 full-context
  comparisons across 32 FPCR modes, four FPSR states and seeded edge/random
  inputs. Deliberately corrupted output was detected with exit 1.
- Quiet ABBAABBA repeated medians, equivalent work and matching checksums:
  normal FPX large model 2,828.015 -> 715.658 ns/call (ratio 0.25306);
  small model 111.649 -> 110.194 ns/call (near neutral). Large IXC-clear model
  11,931.240 -> 1,571.110 ns; inhibited 12,674.686 -> 1,609.809 ns. Entry unwind
  extent: large 587,035 -> 13,792 bytes; small 27,175 -> 2,111 bytes. Explicit
  stack allocation: large 65,176 -> 48 bytes; small 272 -> 48 bytes. These
  exclude other fragments/callees and pushed registers. Timings include identical
  output/FPSR resets; RNG, validation and checksums are outside measured loops.
  Named compiler/test processes were absent before/after the final quiet repeat.
- These models isolate recomp arithmetic efficiency; they omit the game's other
  instructions, guards, memory and scheduling. This is neither game FPS nor
  proof that outlining alone resolves combat slowdown. Coverage is unchanged.
  R03 gameplay, input/save/audio and strict/no-JIT checks remain open.
- Exporter/host rebuilt successfully in 53.4 seconds. Candidate exporter SHA-256
  `c6a7f40d21f26c84526a3faf7a3544d4a57ce5238bbb4095d923a43f5c9a73a2`;
  emitter SHA-256 `a5c630fe391c67440c66c38c8af81d421b8d8019fef3bc8556a95f741a0c6f3d`.
  Export completed with explicit Hybrid/FM1/GG1/FPX1/translate_all settings into
  generated/zarvot-fp32-outline/out. User accepted the output-path warning;
  compilation uses the separate Ninja build tree. Game/module/coverage fields
  match baseline exactly, and each runtime has the three outlined definitions.
  Manifest hash remains `29f3a9cb0aeec129475a94835cf165dfc48578b7a3e8a372e37d6dfac99cdb47`;
  it identifies inventory/ABI, not generated C or DLL bytes.
- Separate sequential module build started at 13:47:17 UTC with two-job cap and
  generated one-compile memory pool. rtld, SDK and subsdk0 completed; main
  started at 13:54:39 UTC and completion remains pending. SDK DLL is
  103,827,456 bytes with SHA-256
  `4d040bbff46f5ae231871296fce31e0e41d8e9d2c09d04ba0d39911585a0fa54`;
  its fresh build took 285.8 seconds, not comparable to an incremental resume.
  subsdk0 took 150.8 seconds; its 67,309,568-byte DLL SHA-256 is
  `0b0e23e704fa3ad7734bb43e4f5b7d9e72b05d0ca081d1bcee0ab28476a8a527`.
  Main emitted C shrank 3,230,233,647 -> 2,455,910,697 bytes (24.0%) across the
  same 112 units. SDK C shrank 2.6%; subsdk0 0.3%; rtld unchanged. These measure
  generated source footprint, not execution time. No arbitrary overall timeout.
  Baseline export, build, saves
  and E017 host/DLL copies preserved. Candidate has not executed game code yet.
- Local evidence: build/recompiler-fpx-outline/validation.log;
  build/recompiler-smoke-outline/{golden-proof.log,validation.log};
  build/zarvot-perf-prototypes/outline-fp32/{summary.json,results-final.log};
  workspace reports/e020-{host-build.log,exporter.json,module-build.log};
  build/recomp/zarvot-fp32-outline/build-status.json. Shareable generic benchmark
  tooling added; its analysis path and underlying compiler workflow passed,
  but the promoted wrapper's complete build invocation is not separately run.
  Eight lightweight analysis contract cases accepted valid evidence and rejected
  changed hashes, bad ABBA order/checksums, missing groups, incomplete semantic
  counts and unfinished metadata. No timing was repeated during module builds.
- Launcher now selects separate target/package/host artifacts and allows
  explicitly requested same-game profile reuse after verifying the old manifest,
  source ExeFS hash, module build IDs/segment layouts and process closure. Default
  host/manifest/DLL matching remains strict. Twenty-seven staging/isolation/
  rejection checks and existing profile rebasing tests passed. No actual game
  session launched or saved profile modified by this work.
- Decision: keep as the separately built candidate. Next finish and verify all
  four DLLs, stage an isolated same-game profile, prove candidate compiled
  execution and compare the same user-led opening combat route. Revert by
  selecting preserved baseline artifacts; do not overwrite them.

## E021 — Completed FP32 candidate and first Story action check (2026-10-11)

- Tasks: R02/R03/R06. Resumed by inspecting actual status/processes, without a
  duplicate build. E020's four-module runner completed at 15:02:11 UTC. Main
  took 4,051.7 seconds (67.5 minutes); its DLL shrank 1,509,548,544 -> 807,949,824
  bytes (46.48%). Baseline's 210.9-minute duration had different resume/resource
  conditions; this is not a controlled compiler-speed measurement.
- Candidate core remains `84568fcadc2b8f062022180b6492d0d8975f4d34`, ABI6/features7,
  identical game/coverage manifest hash
  `29f3a9cb0aeec129475a94835cf165dfc48578b7a3e8a372e37d6dfac99cdb47`.
  Main SHA-256 `88c28454edb7ace30d0d9c9633009ca473be3f7da9e3ea605c2be8ed1cd5e386`;
  rtld `e98a84bf4cea30fea44247e00eba3a2fa19e8139ae9847a012c6a23ded36e732`.
  SDK/subsdk0 hashes remain those recorded in E020. All four files matched their
  completed build record before staging/launch. Original exports/images intact.
- Metadata-only comparison matched the five E019 hot blocks by identical index
  and guest side-entry spans. Verified native unwind boundaries and every
  nonrelocated generated COFF byte against both hash-verified DLLs. No game
  block or timing benchmark executed in this comparison. Native block extents
  by baseline heat rank: 602,112 -> 25,884; 957,092 -> 26,836; 759,360 -> 33,252;
  106,544 -> 13,900; 28,576 -> 3,736 bytes. Total 2,453,684 -> 103,608 (95.78%
  smaller). Explicit stack allocations: 66,024/113,064/83,448/240/352 ->
  112/144/144/64/56 bytes, independently checked against prologue encodings.
  These exclude callee frames and do not measure peak stack or execution time.
- Initial visible Hybrid run: build/zarvot-runs/20261011-151415-850d42f2,
  historical PID 31416, start identity recorded in launch.json. Used rebuilt
  host SHA-256 `25eb2acefb24009a814c3392a526b59dcd846f4a3bcd08b67074cc0a49e17c9c`
  and a cloned post-E017 profile, with original settings. Four images loaded;
  ABI6, instruction/generation guards, fastmem and FPX handshake 0x102/runtime-on
  observed. No controller input sent by tooling. User replayed the first Story
  level to its opening action sequence, said it seemed better and movement/effects
  looked good, with some frame-rate stutter. Audio/save/death/restart remain open.
- Game exited normally after about 223 seconds; log ends in coverage/config
  shutdown, and actual process closure was checked. Final complete report:
  9,340,755,870 compiled blocks (an earlier live read had 7,482,912,865), zero
  JIT transitions, lookup misses, unhandled
  opcode or unresolved-import traps. The initial recorder launched in an isolated
  process context could not see the desktop game; the subsequent desktop recorder
  attempt arrived after exit. No lifetime independent UI or native CPU evidence
  exists for this run. Preserve the game-owned log, coverage and seven captures.
  Hybrid remains JIT-capable; this is neither strict nor no-JIT evidence.
- Visually inspected candidate frame 7 (15:17:50.584 UTC) and E017 frame 14
  (03:07:40.679 UTC): both show the blue jar-arena/Chomp action with effects and
  similar scores, but different player/enemy positions. Ten-second neighborhoods
  centered on those captures contain ten one-second PERF log readings each:
  candidate median 13.9945 FPS (11.498-16.494), baseline 6.9965 (4.997-7.994).
  None of the ten candidate readings is below 10; all ten baseline readings are.
  This supports the user's impression, not a causal or repeated A/B speedup.
  Only one candidate capture confirms active combat; preceding captures show
  letterboxed introduction. Host binary, initial save/cache, inputs/effects and
  profiling overhead differ (baseline had WPR, candidate did not). Interval
  readings cannot establish frame percentiles or exact hit latency.
- Controlled candidate staged, not launched: build/zarvot-runs/
  20261011-152125-1090520b, using the preserved E017 host and E016 profile that
  E017 originally cloned. Same host holds executable identity constant; E016
  holds pre-combat save/cache state constant. Existing launcher verifies all
  game/module identities and copies/rebases a new profile. Candidate negotiation
  exports are byte-identical to baseline; runtime header adds only three helper
  declarations, runtime C appends those helpers, compiler flags and ABI unchanged.
  Helpers are DLL-internal. No compatibility concern found for preserved host.
- Local evidence: build/recomp/zarvot-fp32-outline/build-status.json;
  workspace reports/e020-module-build.log; build/e021-native-layout;
  initial run analysis/20261011-152207-1bfa7318/{REPORT.md,summary.json,*csv};
  workspace reports/e021-controlled-staging.json. Raw addresses, generated code,
  binaries, captures, keys and saves remain ignored/local.
- Added optional launcher RecordCoverage: start one hidden lifetime helper in
  the same PowerShell context, verify its unique observation's game PID/start,
  recorder PID, run root and active state within eight seconds, and report
  attachment/failure in launch metadata/return. Never stop the game or retry a
  failed recorder automatically. StageOnly conflict is rejected. Existing helper
  usage remains compatible; explicit observation paths must stay under the run
  and cannot overwrite evidence. Twenty-seven staging/isolation and sixteen
  startup/helper checks passed, including a real child with spaced paths,
  synthetic real-helper polling, legacy invocation, identity/path rejection and
  failed-start preservation. Profile rebasing and telemetry parser checks pass.
- Decision: keep the candidate, with the baseline selectable for rollback.
  Next attach/verify lifetime UI and owned native CPU recorders before user-led
  play, repeat the same action with preserved host/pre-combat profile, and map
  remaining compiled CPU work before selecting the next recomp optimization.
  Repeat equivalent routes before any gameplay speedup claim. No graphics,
  timing, accuracy, music or general emulator tuning is part of this work.

## E022 — Controlled startup recorded; stopped for controller (2026-10-11 local)

- Task: R03/R06. User asked to continue after the exploratory action result.
  Committed/pushed E021 findings and tested automatic recorder in `b78135a`.
  Launched a new isolated candidate from the preserved E017 host and E016
  pre-combat profile, with same game/coverage identities and unchanged settings.
  No rebuild or controller input. All four candidate files verified again.
- Recorded run: build/zarvot-runs/20261012-002546-8ac4669a (UTC ID; October 11
  locally), game PID 31080. Hybrid, Capture, SamplePc after120/shift18 and
  RecordCoverage enabled. Coverage recorder PID 27972 confirmed matching
  game/recorder identity at launch; observation is recorded in launch.json and
  workspace reports/e022-active-run.json. This live attachment validates the
  new launch path independently of synthetic tests.
- Owned CPU recorder requested with the same CPU.Verbose/900-second configuration
  as E017. User approved Windows administrator consent; recorder PID 18828
  entered recording at 00:27:17 UTC, with recording_started=true, fresh heartbeat
  and no error. Local profile cpu-profiles/20261012-002717-f6e1631b.
  Coverage also advanced 103,643,028 -> 5,714,439,554 across 50 complete early
  UI/file reports with zero transitions. Both recorder states were checked before
  inviting action. No combat occurred before the closure recorded below.
  User invited to repeat opening Story combat and exit normally to finalize evidence.
  Do not analyze a live trace or launch another game. The staging-only E021 copy,
  E017 profiled baseline and all saves remain intact.
- User exited before combat because a Bluetooth controller did not control the
  game; earlier play used wired input. Identified as Stadia, recognized by Windows.
  Final coverage: 90 polls, 84 complete reports; AOT advanced 103,643,028 ->
  8,014,253,978, zero UI/file transitions, no recorder error. Native recorder
  saved successfully on process_exited: 809,500,672-byte cpu.etl, no error or
  cleanup error. Normal game/recorder closure verified. This is startup evidence,
  not candidate combat data; do not spend a conversion treating it as combat.
- Log shows no initial controller motion-device notices, then device arrival
  around 138 seconds. Saved bindings still referenced the wired connection.
  A transport/binding mismatch is plausible; exact cause not established. User
  asked to retry with Stadia connected before launch. Keep all saves/evidence.

## E023 — Stadia Bluetooth retry with controlled recording (2026-10-11 local)

- Tasks: R03/R06. User explicitly requested another test with the Stadia
  controller connected first. Confirmed prior game/recorders closed; retained
  E022 trace and profile. Fresh candidate again uses E017 host and E016 initial
  save/cache with original timing/graphics/audio settings. No export/rebuild.
- Active run: build/zarvot-runs/20261012-003140-dc25d36d (UTC ID; October 11
  locally), game PID 24476; coverage recorder PID 29464 attached at launch.
  Owned native recorder PID 21416 entered recording with no error under
  cpu-profiles/20261012-003248-38053670. Verified both before inviting action.
  Hybrid, captures, PC sampling after120/shift18 and CPU.Verbose/900-second limit
  match the intended diagnostic comparison. Live AOT counts advance, no observed
  UI/file transitions. No saved trace or completed gameplay result yet.
- F12 controls panel actually lists Google Stadia Controller 0. Current persisted
  Player 1 button/stick bindings use its Bluetooth transport identifier rather
  than the prior wired identifier. Panel subsequently closed; no gameplay inputs
  sent by tooling. Detection/binding is not a successful user input verdict.
  This controller check is required for the recomp playtest.
  Connection transport differs from E017; retain it as a comparison limitation.
- User invited to confirm menu control, repeat first Story action, report
  stutter/movement/shooting/audio and exit normally. Next inspect actual process
  and recorder state, verify saved trace/errors, then bound combat and map the
  remaining candidate compiled CPU work. Do not launch a duplicate or infer
  combat from the launch. Preserve source profiles and test saves.

### E023 closure and user observations

- User confirmed Stadia Bluetooth works, finished opening Story action and
  closed the window normally. Feedback: performance seemed about the same;
  shooting and audio were fine. No new movement-specific, save, death/restart
  or original music fidelity verdict. This establishes scoped user input/audio
  behavior, not full gameplay correctness.
- Actual game/coverage/CPU processes all exited. Lifetime coverage ended with
  process_exited and no error: 206 polls, 199 complete reports, compiled blocks
  30,934,695 -> 12,665,187,218. Zero UI/file transitions, lookup misses,
  unhandled opcodes, unresolved import traps, disagreements or counter
  regressions. Hybrid remains JIT-capable; no strict/no-JIT proof.
- Owned CPU recorder completed and saved 2,545,942,528-byte cpu.etl without
  recording or cleanup errors. Preserve the closed trace and all saves. No
  game or recorder was restarted during analysis.

## E024 — Candidate combat attribution and next runtime target (2026-10-11 local)

- Tasks: R03/R06. Hypothesis: after exact FP32 fallback outlining, remaining
  recomp costs can be selected from the candidate's own native trace. E023
  retains E017's exact host SHA 43ae6250..., E016 initial profile, ABI6/features7,
  PC sampling after120/shift18, CPU.Verbose, capture and coverage configuration.
  Candidate source remains 84568fcadc; no core change, export or game rebuild.
- Converted only the completed E023 trace. Full analysis:
  cpu-profiles/20261012-003248-38053670/analysis/20261012-004109-4738000c.
  Exact PID/path/start identity passed, sample interval 1 ms, zero lost events;
  full run has 663,917 leaf samples. Trace session starts 00:32:48.6672033 UTC;
  the game predates tracing, so recorded identity and clamped trace start are
  both retained. Full-run samples are not a combat metric.
- Captures 8–11 show blue jar-arena projectiles, red boss combat/effects and
  increasing score; 12/13 show letterboxed transition. Combat window uses exact
  file UTC 00:35:34.1295148–00:37:04.1983949 (90.0688801 seconds), ETL-relative
  165.4623115–255.5311916. Combat export: analysis/20261012-004418-56508734.
  Screenshots establish scene at capture times, not continuous identical work.
- Combat CPU: 178,841 samples; compiled modules 118,791 (66.42%), main 103,486
  (57.86%), SDK 14,752 (8.25%), host 22,478 (12.57%), unknown 28,574 (15.98%).
  Unknown samples stay unknown; module fractions are statistical leaf shares,
  not exact call durations, frame time or causal bottleneck proof.
- Fixed native mapping's baseline-only build path. Select the launch's recorded
  build target; require target, completed module state/hash/size, image/manifest,
  exact process and loaded IP/RVA/time identities to agree. Only absent legacy
  targets default to zarvot; invalid names, path escapes and mismatches reject.
  Mapping retains selected build path/hash. Nine focused synthetic tests pass,
  including candidate selection while baseline metadata is deliberately stale.
- Real candidate main and SDK mapped using their own verified images and
  runtime/dispatch COFF objects. Main: 62,411 indexed-block samples, 34,117
  matched helper samples, 3,420 run-slice export, 3,538 unassigned; 96.58% mapped.
  SDK: 7,897 indexed blocks, 5,513 matched helpers, 1,019 run-slice, 323 unassigned;
  97.81% mapped. Metadata workers executed no game blocks. Raw ranges, side
  entries and generated code stay local in generated-mapping/main-combat-v1
  and sdk-combat-v1 under the CPU profile.
- Across main/SDK, recomp_lookup has 12,288 leaf samples (6.87% of all combat),
  load32/load64 11,874 (6.64%), three outlined exact FP32 helpers 6,264 (3.50%).
  These helper leaves were previously inlined or shared differently; shifting
  labels or proportions is not itself an execution improvement. The current
  loads retain FM1's bounds, same-page, entry-mask checks and shared slow path.
- Instruction-range review places 1,873 lookup leaves in binary-search fallback
  (1.05% of all combat samples): 1,383 main and 490 SDK. Of these, 1,862 land in
  the first segment-search/setup range and 11 in its no-match return; none land
  in the second entry-search/match range. Shared check samples cannot establish
  branch outcomes and sampling skid prevents exact call counts. These are
  internal lookup searches, not JIT transitions or a coverage gap. All 11,874
  load32/load64 leaves precede the slow-path tail jump; 7,287 are at the fast-only
  return. Memory latency can move with inlining; those shares are not removable
  overhead estimates.
- Reused historical host labels only after independently checking both retained
  EXE hashes, PE unwind structure and matching historical PDB GUID/age. The
  rebuilt current PDB/map was not used. A baseline self-check reproduced original
  counts. Candidate host RunThread: 3,347 (1.87% all), direct exclusive callbacks
  519 (0.29%), recomp diagnostics 600 (0.34%); entire arm_recomp.cpp object
  5,116 (2.86%). Largest host leaf Event::WaitFor is 2.52%; caller/cause unknown.
  Only 454 host leaves remain unlabeled. No dominant host recomp callback found.
  Evidence is in the CPU profile's host-attribution directory.
- Same-source PERF intervals: candidate 90 samples, median 7.9945 FPS,
  range 6.479–12.986, 79/90 below10. E017 combat has 90 samples, median6.997,
  range4.997–11.992, 85/90 below10. Candidate UI exact capture window:45 samples,
  median8, range6–13, 35 below10. E017 exact capture window:44 samples,
  median7.25, range5.5–11.5, 40 below10. Preserve the earlier published rounded
  E017 UI window separately:45 samples, median7, 41 below10; no silent revision.
- Phase checks around captures (+/-5 seconds,10 PERF samples each): blue arena
  candidate7.494 vs baseline6.9965 medians, both all below10; red boss8.7435 vs
  6.996. The broad windows mix phases differently, and these neighborhoods are
  not independent benchmark repeats. Inputs/effects, Bluetooth vs wired and
  laptop load differ. User perceived similar performance. No causal speedup,
  per-frame percentile, exact hit latency or full correctness claim.
- Interval evidence: run analysis/20261012-004536-b10729f4/{REPORT.md,summary.json,
  *csv}. All raw traces, captures, samples, generated labels and profiles remain
  ignored/local. Shared changes are the mapper, focused tests and this handoff.
- Decision: keep the smaller, validated FP32 candidate and baseline rollback.
  Inspect native lookup/load sample locations before selecting the next change.
  The first narrow prototype skips segment search for addresses the completed
  block index already rules out, retaining search when index allocation fails.
  Require generated old/new differential boundary/gap/alignment/random tests,
  negative controls and quiet synthetic timings before a separate game candidate.
  FM1 load gates remain later leads: inherited full-helper inlining increased
  footprint and lost performance, and acquire ordering must be preserved.
  Do not introduce a TLS dispatch cache based on leaf counts alone; inherited
  work already found a regression. Graphics, audio, timing and general emulator
  tuning remain outside scope.

## E025 — Indexed lookup rejects impossible probes directly (2026-10-11 local)

- Task: R06. E024 places 1,873 main/SDK leaves (1.05% of all combat samples)
  in lookup's binary-search fallback. Almost all are in the first segment search;
  none are in the entry-search/match portion. Exact probe arguments and branch
  outcomes were not recorded. Hypothesis: skip redundant search when a complete
  allocated index already proves a probe is outside the module or misaligned.
  This is a narrow recomp improvement, not a remedy for all combat stutter.
- Emitter change: if _idx exists, retain the old valid-address indexed result
  (including NULL holes); return NULL for an impossible address. When _idx is
  absent, retain the entire old binary search. No new cache, data layout, ABI,
  feature negotiation, block body, guard, FP, memory-order or timing changes.
  Independent review verified ordered/nonoverlapping segment construction,
  complete side-entry coverage, relative alignment, unsigned bounds and loader
  initialization under the process lock. Rebase does not alter relative indexes.
- Added tests/recompiler_lookup in the core fork. It extracts the real generated
  index builder/lookup from EmitProject using immutable old/new header snapshots;
  substitutes synthetic segment tables and distinct stub pointers only. No game
  data or generated block execution. Eight old/new × allocated/failed × low/high
  legs compare against an independent linear oracle over boundaries, every byte
  around tables, side entries, holes/gaps, misalignment, wrap-around and random
  PCs. All 1,616,528 comparisons passed; repeated setup never retries failed
  allocation. Deliberate wrong-answer control exits1 as expected. Stub identities
  are checked for uniqueness so linker folding cannot hide wrong pointers.
- MSVC19.44 x64 /O2 /Ob2 /bigobj /fp:precise /MD, no LTO. Quiet ABBAABBA,
  four timed runs per arm with equal call counts and checksums: outside-probe
  medians 3.259 -> 1.355 ns (low range), 4.528 -> 2.232 ns (high); misaligned
  5.209 -> 1.364 and 5.238 -> 2.243 ns. High-range valid hits/holes stayed near
  neutral (~2.03/~2.01 ns). Low valid-hit drift is not claimed as a gain.
  Synthetic 75%-hit/25%-outside mix: 2.185 -> 1.366 and 2.325 -> 2.068 ns.
  These tiny synthetic tables do not model game cache footprint or probe mix.
- Total COFF lookup code 281 -> 273 bytes in both range fixtures. The old
  entry-only unwind range was63 bytes because MSVC outlined its fallback;
  comparing it directly with the new273-byte entry would misreport code growth.
  Other extracted helper sizes are unchanged. No game code-size/FPS claim.
- Real old/new smoke exporters compared all five ABI5/FM1/GG1/FPX combinations.
  Baseline matched the old golden hashes; file sets match, and only the two
  dispatch C files change. Runtime definitions, generated blocks, image exports
  and features stay byte-identical. Golden hashes intentionally updated for the
  shared dispatch change. Smoke runner uses forward-slash CMake definitions and
  Release compiler probes on Windows; these fix test setup, not game behavior.
- Local evidence: build/zarvot-perf-prototypes/lookup-early-null/results.json,
  checked3 immutable headers/generated code/compiler outputs, timing.log,
  smoke-compare/comparison.json; workspace reports/e025-smoke.log.
  Failed setup attempts are retained separately. Full runtime smoke execution
  passed with exit0: coverage loop, ABI5, ABI6, ABI6GG, FPX and GGFPX, including
  expected guard refusals and races. Test temporary files were placed under the
  writable project build directory after sandbox temporary-directory denial.
  No product change was needed for that setup issue.
- Decision: keep source candidate core 284f411686160ceaf7ecaead936148c7de5cfe53.
  Next rebuild the exporter, export/build a separate zarvot-lookup-miss target
  and verify all four image identities before a new user-led route. The E023
  playable images remain the earlier FP32 candidate; this change has not executed
  in Zarvot. Preserve both existing module sets/profiles. Do not infer a game FPS
  gain from microbenchmarks or leaf shares.

## E026 — Rebuild lookup candidate for a future test (2026-10-11 local)

- Task: R06. User requested the rebuild for a future session. No gameplay or
  performance test was started. Preserve zarvot, zarvot-fp32-outline and every
  test profile. New target: zarvot-lookup-miss, core
  284f411686160ceaf7ecaead936148c7de5cfe53; E025 validation remains applicable.
- Incremental Release/MSVC19.44 exporter build succeeded. Exporter SHA-256
  302272a980623ef64c8960d5d52ab481c57806e9d96da1577ec20d534dcd72df;
  emitter SHA-256 6b128794061a1d37aa3f735baa8c72a438848844b7a8361fdd1aff761ecb4ead.
  Existing version label is stale; source/header/binary hashes identify this
  build. Preserved E017 runtime will remain the comparison host.
- Initial requests stopped at the long-output-path warning before writing game
  output. Hidden exporter windows were not exposed by computer-use. Restarted
  only the exact recorded idle exporter and passed a verified 66-character
  junction alias directly to the RPC action. The normal driver resolves aliases
  back to the long path; bypassed only that path normalization. No product,
  safety setting or source changes. Alias generated/lm points inside generated/
  to zarvot-lookup-miss. Export completed with done/success true and running false;
  owned exporter closed before module compilation.
- ABI6/features7, four-module inventory and coverage manifest match the FP32
  candidate byte-for-byte (SHA-256
  29f3a9cb0aeec129475a94835cf165dfc48578b7a3e8a372e37d6dfac99cdb47).
  Compared all 186 module project/source files: 182 unchanged; exactly the four
  dispatch C files differ by the validated early-NULL replacement. Runtime,
  block bodies, image exports and CMake settings are identical. Generated data
  and detailed per-file identities remain local.
- Sequential jobs 2 build started at 2026-10-12T01:24:22 UTC (October 11 local),
  runner PID 11980. Generated compile pool remains 1; no overall timeout. rtld
  completed; SDK is compiling. Main and subsdk0 are pending at this checkpoint.
  Local evidence: workspace reports/e026-{exporter-build.log,exporter.json,
  export-status.json,export-verification.json,generated-comparison.json,
  build-start.json,module-runner.json,module-build.log,module-build.stderr.log};
  build/recomp/zarvot-lookup-miss/build-status.json.
- Completion: all four modules finished at 2026-10-12T02:41:23.928Z (October 11
  locally). Main took 4,187.46 seconds (69.7 minutes); whole runner about 77
  minutes. Both build and preparation exited successfully, with empty stderr.
  A large unit temporarily left only 4 MiB physical/1,128 MiB virtual free in a
  single memory snapshot; compilation continued and succeeded. Retain pool 1,
  sequential modules and ample time. Do not infer a stall from a quiet log or
  increase concurrency. These are build resource observations, not game timing.
- Final images, sizes and SHA-256:

  | Module | Bytes | SHA-256 |
  |---|---:|---|
  | rtld | 150,016 | 6d7699fc9c76148528d5826690ae076aa7576ea7c157f57191d00eddbf04575c |
  | sdk | 103,827,456 | f35d53fa4ae5e6ff13a75c1ac6fc92c7a6ea0812ea8dfca8c1cde0fb3fc83d38 |
  | subsdk0 | 67,309,568 | 7f0403a7edfd86f9b12f7fee35ae891806e91da4f72bb03b199ce54d5da629e8 |
  | main | 807,949,824 | ca6976b45808f7ce106e5b82b6375a801dba14a6c8f0c365884d656876a533df |

- Automatic readiness check verified all recorded hashes/sizes, loaded all four
  DLLs and read ABI6/features7 plus required negotiation/dispatch exports.
  4,280 metadata lookup checks passed across sampled index results,
  misalignment/outside probes and two load bases; no guest block was invoked.
  This checks image readiness, not gameplay or host negotiation. Detailed local
  evidence: reports/e026-image-verification.json and preparation logs.
- Staged build/zarvot-runs/20261012-024145-1a00cba2 with E017 host SHA 43ae6250...
  and a fresh E016 profile clone, same-game identity validation and no game or
  recorder launch. Preparation state is ready_for_future_test. On October 12,
  independently rehashed staged host/images; identities still match. Original
  builds/profiles remain intact. Its six NAND files match the E016 initial
  profile by hash; this is copy integrity, not a save-persistence verdict.
  This stage remains unused; E027 is separate.
- Decision: build complete; no rebuild needed. E027 checks actual compiled boot
  separately. Opening-combat performance/correctness comparison remains pending
  the user's future session and verified coverage/CPU recorders. Do not claim a
  gameplay benefit from identical image sizes or synthetic lookup timing.

## E027 — Lookup candidate compiled boot/title (2026-10-12 local)

- Tasks: R02/R06 readiness. User reported compilation finished and requested
  continuation. All E026 build/preparation processes were verified exited;
  all four images had completed and automatic staging succeeded. Independently
  rehashed the staged host/images before this separate boot. Core 284f411686,
  ABI6/features7 and E026 image identities; preserved E017 host SHA 43ae6250...
  with a new E016 initial-profile clone. Original future stage remains unused.
- Run build/zarvot-runs/20261012-121811-3ca1b234. Historical game PID 21612,
  started 12:18:12.8300599 UTC; coverage PID 19600 confirmed attached before
  observation. Used Capture/RecordCoverage, hybrid policy, no PC-sampling or
  CPU recorder for this boot-only check. No controller input or gameplay was
  automated. A CPU trace remains required for the future combat comparison.
- All four candidate DLLs loaded with ArmRecomp active. Guard-v2 ready, ABI6
  fastmem negotiation, four generation-guard modules and FPX handshake 0x102
  succeeded. Runtime confirms FPX/fastmem on and generation guard active.
  Source version text in the preserved host remains historical; recorded
  image/export/host identities establish which build actually executed.
- Title animation rendered; two later captures were black during startup.
  Subsequent captures show the full Zarvot Press Any Button title, visually
  inspected before closure. Those transient captures do not establish a new
  graphics defect. No gameplay, input/audio, save or FPS comparison was made.
- Lifetime coverage finalized process_exited with no error: 93 polls, 88 complete
  reports; compiled blocks 52,851,771 -> 9,287,923,552. Zero UI/file transitions,
  lookup misses, unhandled opcodes, unresolved import traps, disagreements or
  counter regressions. This proves actual compiled boot/title for this new
  candidate, not complete game coverage, strict-static or no-JIT execution.
- Closed only the exact PID/path/start-verified game through normal window
  close at 12:21:20.0919407 UTC. Game and recorder exited; exit code unavailable,
  not assumed 0. No forced stop or input was needed. Active pointer now records
  closure; retain all profiles/captures and the separate unused stage.
- Local evidence: workspace reports/e027-{active-run,closure,coverage-summary}.json;
  run launch.json, user/log/suyu_log.txt, coverage.txt, captures and unique
  observations/launch-a5948af47f104983a0dc1927ec711a25. Raw addresses/data remain
  local. Only sanitized findings and the handoff are published.
- Decision: candidate is built and ready for a future user-led first Story
  combat comparison. Keep host/initial profile/diagnostics constant, verify
  coverage plus owned CPU recording before play, and compare the saved route
  against E023 with its phase/input limitations. Do not make another source
  change or repeat the large build before measuring this candidate. No causal
  gameplay performance improvement or broader correctness claim yet.

## E028 — Recorded lookup-candidate opening Story comparison (2026-10-12 local)

- Tasks: R03/R06. User confirmed Stadia was connected and ready before launch.
  This is the first user-led combat comparison for zarvot-lookup-miss; E027
  remains a separate boot/title check. No rebuild, gameplay automation or
  emulator settings tuning. Preserve all three module sets and all profiles.
- Run build/zarvot-runs/20261012-122856-ec4dadc0, game PID 4312 started
  12:28:57.7043922 UTC. Core 284f411686, E026 image identities, ABI6/features7;
  preserved E017 host SHA-256
  43ae62506a513097acbc0a39f3af3891b103fd159bc67686027311a6833f0e5f,
  with a fresh E016 initial-profile clone. Same host, profile source and
  Capture/SamplePc/RecordCoverage setup as the controlled FP32 comparison;
  laptop load, action phase mix and actual inputs remain uncontrolled.
- Coverage PID 1692 attached with exact game PID/path/start metadata. Owned
  elevated CPU recorder PID 31848 started 12:29:00.5606581 UTC; its unique WPR
  instance reports state recording, recording_started true and no error or
  cleanup error. Both processes and metadata verified before inviting play.
  CPU.Verbose/file recording is capped at 900 seconds or game exit; coverage
  continues until exit. Never cancel another session or analyze a live ETL.
- Interim checkpoint at 12:33:20 UTC: 131 polls, 126 complete reports;
  compiled blocks 53,114,023 -> 10,755,802,960. Zero UI/file transitions,
  lookup misses, unhandled opcodes, unresolved import traps, disagreements or
  counter regressions. CPU state remains recording. These are execution and
  recorder-readiness observations, not combat speed or gameplay verdicts.
- Local evidence: workspace reports/e028-{active-run,recorders,ready}.json;
  run launch.json, observations/launch-1ff88e83acf64f6c899ba13150e7f624 and
  cpu-profiles/20261012-122901-7eff4fae/cpu-profile.json. Active pointer is
  reports/r03-active-run.json. Logs, captures, samples and raw traces stay local.
- Next: user plays opening Story action and exits normally. Verify both final
  recorder states, trace save/identity and no errors; retain the user's
  stutter/input/audio observations separately. Bound combat with captures,
  export the exact-process samples and map against this candidate's verified
  images/objects. Compare lookup leaf work and interval FPS with E023, with
  scene/input/load limitations. No game speedup, strict-static/no-JIT or
  broader correctness claim before reviewing that evidence. Do not make
  another source change or repeat compilation while this comparison is pending.

### E028 closure and user observations

- User finished opening Story combat and exited normally. Feedback: a bit
  better/smoother, uncertain; slowdown during action about ten seconds before
  exit; everything else worked correctly in response to the explicit movement,
  shooting and audio check. These are scoped user observations, not save,
  restart/death, detailed collision or original music-fidelity validation.
- Actual desktop game/coverage/CPU recorder processes are all absent. Exact
  traced game exit: 12:40:26.2931938 UTC. Game exit code unavailable, not assumed
  0. Coverage ended process_exited without error: 342 polls, 336 complete;
  compiled blocks 53,114,023 -> 25,874,802,028. Zero UI/file transitions,
  lookup misses, unhandled opcodes, import traps, disagreements or regressions.
- CPU recorder finalized process_exited at 12:41:08.2668748 UTC, saving
  3,853,516,800-byte cpu.etl with no recording/cleanup error. The later recorder
  finish includes trace save; it is not the game-exit timestamp. Active pointers
  now record closed. Workspace reports/e028-finalization.json retains final
  metadata and user feedback. All profiles and the unused E026 stage survive.
- Decision: review the closed recording in E029 before another source change;
  zero observed transitions is still hybrid-route evidence, not strict/no-JIT.

## E029 — Verify smoother combat and the late slowdown (2026-10-12 local)

- Tasks: R03/R06. User asked to verify the impression of smoother action and
  inspect roughly ten seconds before exit. No new runtime/emitter change, game/export
  rebuild, launch, automated input or settings tuning. E028 core/image/host
  identities remain E026's lookup candidate with E017 host/E016 initial profile.
- Converted only the complete saved trace. Full export
  cpu-profiles/20261012-122901-7eff4fae/analysis/20261012-124156-79f95169:
  exact PID/path/start verified, 1 ms sampling, zero lost events, 1,374,658 game
  samples. Session 12:29:01.1719187–12:40:47.2931024 UTC; process exit comes from
  the exact game process's EndTime, not the session end or recorder completion.
  Conversion took about 161.5 seconds; cached window exports took seconds.
- Captures 19–22 visually show blue jar-arena projectiles/Chomp, red boss combat
  and effects, with rising score/decreasing boss health. Capture 17 still shows
  the title; long title time is excluded from combat. Capture 23 shows the
  Saturday Morning, 10:32 AM Story transition. Thirty-second captures cannot
  locate the precise hit, transition start or continuous identical work.
- Combat window: 12:38:16.073978–12:39:46.2549309 UTC, 90.1809529 seconds;
  ETL-relative 554.9020593–645.0830122. Native export
  analysis/20261012-124536-70c0b664. 91 PERF polls: min 9.492, median 10.994,
  max 18.990 FPS; 22 below 10, 84 below 15. UI has 45 polls, median 11, min 9.5,
  max 18.5; one below 10. E023's capture 8–11 comparison remains 90 PERF polls,
  median 7.9945, min 6.479, max 12.986, 79 below 10; UI 45, median 8, 35 below 10.
  Strict below 10 counts are sensitive to readings such as 9.995 versus rounded
  UI 10.0; retain the separate data sources rather than merging their counts.
- Phase neighborhoods (+/-5 seconds, 10 PERF polls each) also have higher
  medians in this run: blue arena 12.2425 vs 7.494, red boss 10.493 vs 8.7435,
  depleted boss 10.4955 vs 7.7445. These overlapping neighborhoods are not
  independent repeats. Results support the user's smoother impression in this
  run; unmatched action/input/phase mix, warm-up/cache history and laptop load
  prevent a causal or repeatable FPS-gain claim from the lookup change.
- Late dip: log elapsed 670–678 seconds maps to 12:40:07.731122–12:40:15.731122
  UTC. Eight interval polls are 7.497, 0, 0.500, 3.996, 6.994, 3.998, 1, 8.995 FPS;
  median 3.997. The sampled dip occurs roughly 11–18 seconds before actual exit,
  consistent with the user's approximate report. The exact final ten seconds
  contain eight PERF polls at 36.972–38.477 FPS, median 37.7245; UI five polls,
  median 37.5 with the first lagging reading 27. The scene had transitioned.
  Do not average this recovery into a combat metric. Interval frametime fields
  include NaN when no frame completed; they are not a p99/per-frame trace.
- Byte-verified main/SDK mapping uses this target's own runtime/dispatch objects,
  game image/manifest hashes, loaded image/IP/time identities and index/unwind
  checks. All metadata-only: no guest blocks invoked. Combat main 103,926
  samples (60.07% of all), SDK 14,191 (8.20%); compiled total 118,399 (68.44%),
  host 22,393 (12.94%), unknown 23,844 (13.78%). Main/SDK assignments cover 96.40%/
  97.44% of their samples. Outputs: generated-mapping/{main,sdk}-combat-v1.
- Across main/SDK: lookup 10,353 leaves (5.98%), load32/load64 12,511 (7.23%),
  outlined exact FP32 helpers 6,460 (3.73%). Linked lookup branches verified
  against the dispatch object: 8,549 index-only load/return samples, 1,713 shared
  index/bounds checks, 91 shared zero-return and zero in the index-absent-only
  binary-search ranges. E024 had 1,873 search leaves (1.05% of all). This supports
  removal of the intended sampled search work, not zero search calls or a
  causal total-speedup estimate; shared branches, sampling skid and phase mix
  remain limits. Reaggregation corrects E024's combined FP32 count 6,264 -> 6,268
  by including four SDK multiply-helper samples; rounded 3.50% is unchanged.
- The late-dip native export analysis/20261012-124544-ba55e024 has 13,734 samples:
  compiled 10,219 (74.41%), host 1,552 (11.30%), unknown 1,425 (10.38%). Main/SDK
  mapping covers 97.31%/97.19%. Lookup 706 leaves (5.14%), load32/load64 1,034
  (7.53%), outlined FP32 942 (6.86%); zero samples in the lookup search ranges.
  Pre-dip and recovered-transition exports are analysis/20261012-124541-f719804e
  and 20261012-124547-e2c4bc64. Higher compiled share does not identify the
  critical path or the cause of this stall. No JIT-gap evidence emerged.
- Local reproducible review: build/e028-review-run.py, build/e029-native-review.py;
  run analysis/e028-interval-review/{summary.json,*perf.csv}; CPU profile
  helper-leaf-analysis/{summary.json,*lookup-disasm.txt} and
  generated-mapping/{main,sdk}-dip-v1. Workspace reports/e028-native-windows.json,
  e028-native-maps.json and e029-native-review.log. Capture write-time/log-origin
  anchors agree within 0.84 ms across both runs. Raw game data/addresses remain
  local; only these sanitized findings and handoff are committed.
- Decision: retain the validated lookup candidate and all rollback module sets.
  It removes measured redundant work and has scoped user behavior confirmation;
  broad performance remains slow, and causal FPS improvement is unproven.
  Next examine mapped dip blocks and narrowly prototype FM1 load-gate/code-layout
  alternatives using focused semantic/negative-control/timing checks. Preserve
  acquire ordering, permissions, page crossing, invalidation, exclusives, exact
  FP and original timing. Full-helper inlining previously regressed; avoid a
  blanket inline/cache change. No new large build/playtest before prototype
  evidence warrants another recomp candidate. Save/death/restart, original
  music fidelity, later routes and strict/no-JIT checks remain separate/open.

## Template for the next experiment

- ID / R task / date:
- Hypothesis and expected bottleneck:
- Source/exporter/runtime hashes / image ABI/features / compiler flags:
- Game/module build IDs / generated image hashes / backend:
- Scene, exact input route, duration, focus, power, cache and settings:
- Control / candidate (one changed variable):
- Raw local evidence paths:
- Build and AOT execution evidence / fallback counts and reasons:
- Coverage and correctness scope / untested routes:
- Recomp performance results and run-to-run spread (if measured):
- Visual, input, save and audio checks:
- Limitations / unverified claims:
- Decision: keep / revert / inconclusive / defer:
- Next action and rollback:
