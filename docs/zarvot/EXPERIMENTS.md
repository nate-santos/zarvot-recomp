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
  restarted using cached dependencies. Configuration/build is currently active;
  success and exact final failure, if any, will be recorded before handoff.
- Evidence: reports/r00-build.log and ignored source/build and local/tools trees.
- Limits: no Zarvot AOT export, module compilation, execution or gameplay test.
- Next: finish R00, then inventory/export and compile Zarvot (R01/R02).
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
