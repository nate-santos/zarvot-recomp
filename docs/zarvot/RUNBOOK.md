# Zarvot recomp runbook

Updated scope: 2026-10-05. Follow the R task queue in STATUS and PLAN.
The runtime commands below preserve historical reference/validation procedures;
they are not a general emulator optimization queue.

## Recomp build workflow — next work

R00 host/exporter build and R01 Hybrid source export succeeded (E010).
R02 completed for all four modules, including verified compiled execution (E013).
Reuse those outputs for R03 gameplay/coverage checks and R06 compiled-cost
profiling. The build sections below retain historical commands and identities;
other inherited MK8 workflows remain unverified for Zarvot.

1. Check the source branch, changes and existing project processes. Initialize
   the pinned third_party/suyu submodule if missing; inspect current build docs.
2. Establish matching exporter/runtime source and generated-image ABI/features.
   Verify the E005 toolchain; inspect clang-cl availability and exporter support.
3. Build the host/exporter and inventory Zarvot modules/build IDs. Export source
   into ignored generated/ or local/ output using the matching exporter.
   The inherited scripts/export-recomp.py accepts --rom and --out; inspect the
   actual exporter RPC schema and script before use with the selected build.
4. Build modules, validate manifest/image identities and load the matching bundle.
   Record compiler/options, source hashes, module hashes, build duration and errors.
5. Prove the AOT backend executes: capture advancing static-block counters and
   fallback attempts/reasons. Add recomp-specific telemetry if existing manual
   sampling lacks it; ordinary FPS output cannot establish AOT coverage.
6. User-led hybrid validation supplies routes and gap evidence. Iterate fixes,
   re-export/rebuild, then validate strict static and a separate no-JIT host.
   Preserve the user's session, profile and saves throughout.

Use the existing JIT runtime only as a reference when needed. Keep graphics,
audio and original timing fixed during recomp comparisons. Manual gameplay
validation does not block build, export or synthetic correctness work.

## Layout

The current workspace has this shape (paths are relative):

```text
workspace/
  PROJECT_PLAN.md                 entry point for the user
  AGENTS.md                      cross-model instructions
  Zarvot.nsp                     local game
  prod.keys, title.keys          local input files; never print
  runtime/suyu-v0.0.12/           portable installed runtime
    suyu.exe
    user/keys/                   installed copies
    user/config/qt-config.ini    active settings
    user/log/suyu_log.txt        diagnostics
  reports/                       local screenshots and measurements
  source/                        Git checkout
    docs/zarvot/                 canonical roadmap and handoff
    scripts/zarvot-rpc.ps1       local emulator JSON-RPC client
```

Current keyboard mapping: Switch A = C, B = X, Plus = M; left stick = WASD.
Click the game area first. A first key press can be consumed by focus changes.
Opening Story movement, shooting effects and the pause menu are confirmed;
the exact aiming controls and clearing the encounter were not verified.
Face buttons are mapped A=C, B=X, X=V, Y=Z. Short automated taps can miss input;
use the runtime's TAS feature for held/repeatable controller commands.

## Manual gameplay recording

The user will playtest later. Do not automate gameplay unless requested again.
Last observed state was paused with TAS playback/recording stopped. The recorder
below sends no input, changes no settings and leaves control with the player.
Run from workspace root; it provides ten seconds to resume and focus the game:

```powershell
.\source\scripts\zarvot-benchmark.ps1 `
  -ConfigPath .\runtime\suyu-v0.0.12\user\config\qt-config.ini `
  -EmulatorPath .\runtime\suyu-v0.0.12\suyu.exe `
  -Scene 'Opening combat, manual route, run 1' `
  -OutputPath .\reports\manual-run1.json `
  -Seconds 60 -IncludeGpuCounters
```

Use distinct run filenames. Warm up first and repeat the same route three times,
keeping 1x/HIGH, power and foreground state consistent. Record level/route and
any deaths, pauses or transitions in `-Scene` / optional `-Notes`. A stopped
emulation thread or active TAS at the start rejects recording; later stopped
thread/TAS-active polls are counted in the output and FPS drops are retained.
Review these flags before using results as a gameplay comparison. No tool can
confirm whether the player actually followed the described route.

The wrapper records executable identity, saved-profile settings and before/after
config hashes. These do not continuously verify in-memory settings or focus.
Runtime config and saves stay local. The underlying sampler was live-validated
in E003 and E004; full manual-wrapper capture awaits the user's later playtest.

PresentMon 2.6.0 is available locally under `downloads/`. Its ETW trace attempt
failed with Windows access denied; no per-frame capture is available. Continue
with accurately labeled interval polls. Do not invent 1% lows/p99 from them.

## Earlier controller-playback workflow (reference)

E003 left the game paused in the opening jar `Pew Pew` combat tutorial.
TAS is enabled, loop is off and playback is stopped. M opens/closes pause;
the pause menu has resume, restart level, pair controllers and exit to main menu.
Original pre-test save backup: workspace `reports/z01-save-before-gameplay/`.
Original pre-TAS settings: `reports/z01-config-before-tas.ini`. Do not restore
these over later user progress. Current game/profile data stay local.

Run the following from workspace root. First resume via the pause menu; then
inspect the actual scene. These tools neither launch a game nor select a save.

```powershell
# Send a controller button held for 30 input ticks, then release it.
.\source\scripts\zarvot-input.ps1 `
  -TasDirectory .\runtime\suyu-v0.0.12\user\tas `
  -ConfigPath .\runtime\suyu-v0.0.12\user\config\qt-config.ini `
  -Buttons KEY_A -Frames 30

# Sample gameplay while keeping the game visible and foreground.
.\source\scripts\zarvot-sample.ps1 `
  -Scene 'Describe exact scene, route, settings and run number' `
  -EmulatorPath .\runtime\suyu-v0.0.12\suyu.exe `
  -OutputPath .\reports\my-gameplay-run.json -Seconds 60 -IncludeGpuCounters
```

The input helper validates the selected TAS directory, enabled/non-looping
settings and idle playback/recording state, backs up the previous script, and
uses `tas_reset` / `tas_start_stop`. `-Pulses` and `-GapFrames` send repeated
presses; `-LeftX`, `-LeftY`, `-RightX`, `-RightY` specify signed stick values
from -32767 to 32767. Separate simultaneous buttons with semicolons and quote
the string. A fixture ends with neutral input. `Frames` are TAS input ticks,
not captured presentation frames; this experimental playback is not guaranteed
to reproduce identical enemy/physics phases.

E003 held A for 15000 ticks per 60-second run (long enough to cover sampling)
and stopped playback afterward with this local RPC call:

```powershell
.\source\scripts\zarvot-rpc.ps1 -Tool trigger_ui_action `
  -ArgumentsJson '{"action":"tas_start_stop"}'
```

This action toggles playback: check `tas_running` before using it to stop.
Always stop a long fixture after measurement or a failure, and verify input
is released before pausing/leaving the session. Avoid thread diagnostics,
exports or other intrusive operations during a timed run.

The sampler checks the executable path and requires exactly one matching
process. It records interval rendered FPS, VBlanks/s, reported frame time,
emulation speed, shader/TAS state, process CPU/memory and optional Windows GPU
engine utilization. Actual sampling intervals are recorded (about 1.05 s in
E003). Focus must be maintained by the caller. The GPU counter interval follows
the FPS poll, so the observations are not simultaneous. The sampler does not
compute frame percentiles or 1% lows. Aggregate CPU use does not prove which
thread limits frame time. Power, temperature and scene phase need separate
control. See EXPERIMENTS.md for results and caveats.

## Start/resume

Inspect the current `suyu` process and its executable path before launching a
second instance. The supplied runtime supports `-gamer` / `-programmer` /
`-hacker` to avoid a first-run layout modal. Only control a process whose path
belongs to this project. Prefer the built-in local interface for state reads,
screenshots and launch; use supported computer-use tools for controller input.

From this source checkout, while its GUI is running:

```powershell
.\scripts\zarvot-rpc.ps1 -Tool get_emulator_state
```

Discover current tool schemas with `scripts/zarvot-rpc.ps1` without arguments.
The interface uses raw JSON-RPC over loopback port 9742, not HTTP. Do not expose
the port remotely. On this host the execution sandbox may need approval for
loopback connections and user-desktop process launch.

Launch via `launch_game_path` with a JSON argument containing the absolute local
NSP path. A boot may exceed the RPC timeout: inspect state and logs before retry.
`capture_game_screenshot` accepts an absolute local PNG path; await the output
file and inspect it before making visual claims.

## Known baseline settings

- Dynarmic JIT; no static modules active.
- Vulkan; handheld; 1x resolution; high GPU accuracy.
- Original speed limit 100%; no FPS unlock or frame generation.
- Audio auto backend selected cubeb; 48 kHz, stereo; volume 100%.
- Disk shader cache enabled; asynchronous shader compilation disabled.

Back up configuration and saves before A/B runtime/backend changes. Do not
edit the active config while suyu is running: shutdown may overwrite it.

## Source and runtime identity

- Wrapper base: `db36cf53606e67977a26d6758215dfc89fa24724`.
- Baseline emulator submodule: `5949cab3ba93233ddd1c319bfc6f010f6cfa910a` (E010).
- Current recomp source: `84568fcadc2b8f062022180b6492d0d8975f4d34` (E020),
  published to nate-santos/suyu-zarvot-recomp on zarvot-support. The parent pins
  this fork; its history includes the baseline. Do not mix current host files
  with old launch records silently; E017 retains the baseline host and DLLs.
- Downloaded Windows release asset v0.0.12 SHA-256:
  `415e68c9aaf5374dd7f4864c8f267ce4833e13a2cbb2cc9cdf299ed06634ff2a`.
- Installed suyu.exe SHA-256:
  `15bdbf26fa201634bcc3441e9506d19e96c1d91f87bc9fa205c5dfc979c9f2a0`.
- Its log reports `HEAD-40aeb31824-HEAD`; UI says v0.0.11 (mk8-recomp).
- Export kit label: `suyu-aot-kit-abi6-fm1-gg1-fpx1-control-r3`.

Do not equate the version label with source identity. Historical v0.0.4
architecture notes are not a current bug list. Inspect the pinned/current
source before implementing old suggested fixes. Rebuild generated images if
the matching runtime ABI changes.

## Git workflow

`origin` = `https://github.com/nate-santos/zarvot-recomp.git`.
`upstream` = `https://github.com/dougchansan/mk8-recomp.git`.
Working branch = `zarvot-support`, tracking `origin/zarvot-support`.

The source checkout is owned by the desktop user. If the sandbox Git user
reports dubious ownership, use a one-command `-c safe.directory=<exact source
path>` or the normal approved desktop execution context. Do not add a wildcard
global safe-directory exception.

The GitHub fork and branch exist. Browser verification previously hit an
approval-service usage limit after creation; API responses had already
confirmed both. Use available authorized GitHub tools for subsequent source
work. Never recreate a fork merely because a browser check was interrupted.

Stage explicit paths and review `git diff --cached --stat` and the full diff.
Raw logs can contain game addresses and local paths; publish sanitized summaries.

## R00 build preparation (2026-10-05)

The recomp-only roadmap and handoff are committed in 5c6156a. Pinned source
5949cab3ba93233ddd1c319bfc6f010f6cfa910a is checked out unchanged. This tree uses
its declared CPM dependencies and an in-tree Dynarmic; recursively fetching every
legacy .gitmodules entry is not the default build procedure.

Local dependencies: aqtinstall 3.3.0 in local/tools/python, Qt 6.9.3
win64_msvc2022_64 (including qtcharts and qtsvg) under local/tools/Qt, and Khronos
glslang 16.5.0 under local/tools/glslang. CMake/MSVC/Ninja are from E005.
Set the local Python Scripts directory, CMake and Git tools on the process PATH.
The initial build command from the workspace root is:

```powershell
.\source\scripts\build-suyu.ps1 -Configure -ParallelJobs 2
```

The helper defaults to two parallel compiler jobs for the laptop and builds
both suyu and suyu-cmd. Raw configure/build evidence stays in reports/r00-build.log.
This command configured successfully. An incremental four-job resume completed
both host targets; see E010 and reports/r00-build-resume.log. Inspect actual
processes/artifacts before resuming a build.

## First Hybrid export — verified

The matching exporter completed this command with Zarvot. It used its own
portable bin/user profile, supplied keys and RPC port 9743. From the source root,
with local Python on PATH and the exporter already running:

```powershell
$env:SUYU_MCP_PORT = '9743'
python scripts/export-recomp.py --rom ..\Zarvot.nsp --out generated\zarvot\out --backend hybrid source
python scripts/mcp-call.py get_aot_export_status
```

Wait for done=true and success=true, then inspect the AOT manifest and modules.
The driver's zero exit means the request was accepted; it does not mean export
finished. Keep the exporter separate from any player session and verify ownership
before opening the dialog. The inherited automated export/build runner remains
unverified for Zarvot and must be reviewed before use.

## E010 artifacts and next build

Historical baseline source: 5949cab3ba93233ddd1c319bfc6f010f6cfa910a. Host hashes:

- suyu.exe: `63e3da41e1fb4f7f52a0d85d901acffd164dd677d47b355da44ecae9465cc3fc`
- suyu-cmd.exe: `43ae62506a513097acbc0a39f3af3891b103fd159bc67686027311a6833f0e5f`
- rtld DLL: `0ffb63fdbe3e7e454d2e0192b338cbb926169c87ee119b5745f3aa47a9912c5c`

GUI startup used the local Qt bin directory on PATH and Qt plugins through
QT_PLUGIN_PATH, SUYU_MCP_PORT=9743, and SUYU_AOT_TRANSLATE_ALL=1. Create bin/user
before launch for portable isolation; the keys are local, never tracked.
Use -hacker for the exporter. Inspect current processes before starting one.

Successful rtld build from the workspace root:

```powershell
.\source\scripts\build-recomp.ps1 -Target zarvot -Package 'out\Zarvot - Hybrid AOT + JIT' -Module rtld -ParallelJobs 2
```

The same module helper subsequently built main/sdk/subsdk0 (E013). It uses MSVC
currently. Main has 112 generated C units totaling about
3 GB. The generated project selected a one-compile pool for rtld on this host;
--parallel alone does not override that pool. Review current generated CMake
and compiler support before a large main build; do not silently disable guards
or change arithmetic semantics to reduce compilation cost.

The partial test used SUYU_RECOMP_DIR=source/build/recomp/zarvot (absolute at
launch), with only rtld present. Loading and fastmem negotiation succeeded.
Boot remained unverified with zero AOT counts; firmware preflight in the fresh
profile is the leading explanation. Desktop inspection timed out awaiting app
approval. The owned test process was stopped; no controller input was sent.
Do not run inherited run-hybrid.ps1 unchanged: it broadly stops suyu processes
and edits global settings. Use a project-owned, separate profile and retain
original speed/graphics/audio settings for comparisons.

## Slow-laptop module builds

E020's separate target is `zarvot-fp32-outline`. Its exporter rebuild and export
completed, and the sequential runner is active. Check
build/recomp/zarvot-fp32-outline/build-status.json and actual processes before
resuming. Raw logs: workspace reports/e020-host-build.log and
reports/e020-module-build.log. The original `zarvot` export/build stays intact.
The candidate manifest is byte-identical to baseline because its game, coverage
and ABI are unchanged; it does not identify emitted C. Candidate emitter SHA-256
is `a5c630fe391c67440c66c38c8af81d421b8d8019fef3bc8556a95f741a0c6f3d`;
exporter identity is recorded in reports/e020-exporter.json. Verify each new
DLL against its own completed build record before staging.

The generic optimization benchmark is documented in
[tests/recomp_fp_outline_benchmark.md](../../tests/recomp_fp_outline_benchmark.md).
Run only when project builds/tests/games are idle. Its synthetic speed result
does not establish a Zarvot frame-rate gain. E020 retains the measured prototype
and complete semantic/smoke logs under build/; generated artifacts stay local.

After all candidate modules finish, stage a separate profile from the closed
E017 run (workspace-root commands; this sends no input and starts no game):

```powershell
.\source\scripts\start-zarvot-recomp.ps1 -Target zarvot-fp32-outline `
  -ProfileFromRun .\source\build\zarvot-runs\20261011-030031-b40a1ca6 `
  -AllowSameGameProfileReuse -StageOnly
```

The explicit reuse switch verifies the old recorded manifest and the same
source ExeFS hash, module build IDs and segment layouts. It copies saves/settings
to a new run and rebases storage; default reuse still requires matching host,
manifest and DLL identities. Closure checks reject an active/restarted source
profile. Twenty-seven synthetic staging/rejection checks and profile tests pass.
Choose the preserved baseline host explicitly when staging a matching control:

```powershell
.\source\scripts\start-zarvot-recomp.ps1 -Target zarvot `
  -HostRoot .\source\build\zarvot-runs\20261011-030031-b40a1ca6 `
  -ProfileFromRun .\source\build\zarvot-runs\20261011-030031-b40a1ca6 -StageOnly
```

No real candidate/control profiles have been staged by E020 yet. Inspect saves
and route availability before the user-led comparison; a shared save does not
prove identical actions or enemy/effect phases. Use the existing coverage/CPU
recorders after staging and keep gameplay/audio correctness open until observed.

Build the four exported modules sequentially from the workspace root:

```powershell
.\source\scripts\build-zarvot.ps1 -ParallelJobs 2
```

The runner uses the existing per-module helper and incremental Ninja trees;
completed objects are reused. It validates the four-module ABI 6 manifest,
records its hash and each completed DLL's size/hash, and stops on a build error.
Local state is in source/build/recomp/zarvot/build-status.json; raw console output
should stay in reports/. It has no overall timeout. The current generated
projects use MSVC /O2 /bigobj /fp:precise and select RECOMP_JOBS=1 on this laptop.
ParallelJobs caps Ninja activity; it does not enlarge the generated compile pool.

Do not launch this runner alongside a manually started module build. Its lock
prevents duplicate runners only. Before resuming, inspect runner/compiler/Ninja
processes and the status timestamp: an old building status can outlive a stopped
process. Allow an active compiler time to finish even if it emits no new lines.
Record real errors/resource exhaustion separately from elapsed time. Preserve
the existing build trees; no forced clean is needed for an ordinary resume.

E011/E012 completed SDK and subsdk0; main is building. Additional DLL hashes:

- SDK: `da0fb0ddb7496dc61f84a04459e3023e3712ba6d6137f87d0431c938f393bf45`
- subsdk0: `3f1d06e16fd61446d11d838e7c7bc0c04dc35f886fa5f1d7356ace47c3010ec8`

After the runner completes, verify all four recorded DLL hashes and manifest
identity before launching. The ordinary CLI loads DLLs beside suyu-cmd.exe;
SUYU_RECOMP_DIR is the GUI loader's directory override. Use a separate portable
profile/staging directory for a CLI smoke check. Do not stage a partial CLI set:
its current load-index mapping can give a later DLL the wrong base address when
a middle module is absent. The GUI supports subsets through its separate mapping.

The current CPU runtime periodically writes execution/fallback counters to
SUYU_RECOMP_COVERAGE_PATH, or user/log/recomp_coverage.txt by default. Preserve
multiple timestamped readings from one owned process; increasing static blocks
prove ongoing compiled execution. File updates are tied to compiled dispatch
counts, so a missing or unchanged file alone does not diagnose a stopped host.
Check process/log/state too. Positive counts alone do not establish gameplay
correctness, strict-static/no-JIT execution or a speedup.

## Verified compiled boot and manual gameplay preparation (E013)

The main build completed in 210.9 minutes; all four module hashes matched the
build record. Main DLL SHA-256:
`15d3bb4d96a40bd93a89f6e91381ee3728dac59a40b39ba953fd3b1f8509ce16`.
No new export or main compilation is needed to resume R03.

From the workspace root, with no other emulator session running:

```powershell
$run = .\source\scripts\start-zarvot-recomp.ps1 -Capture -Visible
.\source\scripts\measure-zarvot-coverage.ps1 -RunRoot $run.RunRoot -Seconds 60
```

The launcher verifies the completed four-module set and manifest, copies host
and DLLs into a unique source/build/zarvot-runs directory, and starts the ordinary
CLI. Every run has its own portable keys/config/NAND/saves/logs. Local keys stay
ignored; this directory is not a release package. Use -StageOnly to prepare
without launching. Existing player/test sessions are preserved, not stopped.
Use -Visible for an interactive user playtest; background smoke launches remain
hidden by default. Launch metadata records whether visibility was requested.

Config preserves handheld Vulkan 1x/HIGH, 100% speed and disabled TAS. Native
INI keys need explicit default=false when selecting a nondefault value; the
data-storage section is Data%20Storage. Do not reuse Qt config with absolute
paths into a different profile. CLI image load order requires all four DLLs.

The recorder verifies PID/executable/start time and saves raw coverage snapshots
plus observation.json under the run's observations directory. It handles JSON
timestamps parsed as DateTime by current PowerShell. Incomplete reports keep
unknown fields; never reinterpret missing counts as zero fallback. The recorder
sends no input, stops no process and makes no FPS/gameplay verdict.
Review CompiledCountAdvanced and Error in its result; command completion alone
is not a passed execution check. Preserve an incomplete observation for diagnosis.

E013 verified advancing AOT counts, ABI 6/guard/fastmem/FPX1 negotiation and the
visible title. The handheld repeat advanced 7,312,156,998 -> 8,419,406,636 blocks
with zero observed fallback transitions. The host remains JIT-capable; these
were Hybrid-policy runs. -Strict sets the requested policy only, not a no-JIT
build. Do not mark R05 complete from this evidence.

Both E013 smoke hosts closed gracefully. E014 starts the requested user playtest;
check reports/r03-active-run.json (workspace root) and the actual process before
starting another session. The bounded recorder runs for ten minutes; runtime
coverage and captures continue while the game remains open.
Follow PLAYTEST.md for the opening Story route. For save/relaunch checks reuse
the same staged profile or explicitly clone a closed matching test run with
-ProfileFromRun. Launch metadata records local ROM and host paths; normal fresh
launcher calls deliberately create a new profile.
Inspect process ownership before closing a test; preserve user-owned sessions.

## Combat slowdown diagnosis and compiled-PC sampling (E015)

The E014 run retains user/log/suyu_log.txt (one-second PERF readings and
graphics-pipeline creation messages), coverage.txt, user/log/recomp_gaps.json,
and observations/*/observation.json plus raw coverage snapshots. E015 preserves
review copies, an interval CSV, summary.json and REPORT.md under that run's
analysis/20261006-022157 directory. Do not commit these raw files.

All 299 complete recorder reports had zero fallback/import traps despite the
user noticing JIT transitions. The window and coverage use the same cumulative
lookup-miss/unhandled-opcode counters; no counter reset found in source. Keep
the discrepancy open. Several stalls coincide with pipeline creation, which
does not establish CPU/GPU cost or justify settings changes. These interval
readings cannot establish per-frame percentiles or a recomp speedup.

For the next user-led diagnostic launch, after preserving the existing session:

```powershell
$run = .\source\scripts\start-zarvot-recomp.ps1 -Capture -Visible -SamplePc -SampleAfterSeconds 120
```

This opt-in enables the pinned runtime's existing compiled-PC sampling after
the stated boot delay, every 2^18 retired blocks, and records the parameters in
launch.json. It requires no re-export or module rebuild. The launcher otherwise
clears inherited diagnostic overrides, so setting those variables externally
does not enable sampling. Default playtests keep sampling disabled. Syntax
checked; E016 subsequently validated live sampling output.

Sampled PCs identify frequently executed compiled locations, not time spent in
them. Use a native duration profile for CPU/helper cost before optimizing. Name
the combat route and repeat it within the same profile/settings to separate
initial pipeline work from recurring cost. Diagnostic sampling has overhead;
do not treat its FPS as a matched performance comparison with E014.

## Lifetime UI/coverage diagnostics and profile reuse (E016)

The user's earlier recollection of possibly six UI transitions is now uncertain.
They observed none in E016 and confirmed no combat during that run. The E014
collector did not save caption text and stopped after ten minutes; file evidence
alone does not settle what the user observed. The new recorder polls the owned
process's exact MainWindowTitle plus coverage independently every two seconds.
It retains UI/file counts, shader-building text, report age, source disagreements,
counter regressions and incomplete reports. Disagreement can be ordinary snapshot
lag, so it is evidence to investigate, not automatically a runtime defect.

With a closed recorded test profile and no emulator running:

```powershell
$run = .\source\scripts\start-zarvot-recomp.ps1 -Capture -Visible -SamplePc -ProfileFromRun $previousRun
.\source\scripts\measure-zarvot-coverage.ps1 -RunRoot $run.RunRoot -UntilExit
```

-ProfileFromRun accepts only a recorded, closed profile under build/zarvot-runs
with matching host/export/module identities. It clones NAND/saves, controls and
settings, available caches and relevant data into a new directory, rebasing
storage paths. Empty native storage settings retain portable defaults. Foreign
storage paths are rejected. The source profile/raw evidence is preserved; no
original player profile is used. File-copy checks do not establish save semantics.

-UntilExit has no ten-minute cutoff and sends no input. Process exit ends it;
identity changes/errors stop it with a reason. Samples append to samples.jsonl;
observation.json retains the last 300 samples and summary totals/maxima over the
whole recording, updated every ten seconds. Read JSONL for the full timeline.
Changed raw reports are archived, including partial writes. A bounded -Seconds
recording remains available. Missing data stays unknown, never zero.

E016's three synthetic test scripts cover parsing/partial reports, profile
rebasing/defaults and a UI=6/file=0 recording through simulated process exit.
Live recording matched the returned native window caption; compiled-PC histograms
appeared after the 120-second boot delay. E016 ended normally on process exit:
146 complete samples, advancing AOT counts, zero UI/file fallbacks/import traps,
no disagreements or regressions. Final coverage contains 1,222 distinct sampled
PCs. Captures show a Story room/dialogue; combat cost/correctness remains open.
Local run: build/zarvot-runs/20261006-035803-2d087b29; final analysis is under
analysis/20261006-040756. Game and recorder are closed. Inspect the active pointer
and actual processes before relaunch; preserve the profiles and evidence.

## Owned native CPU capture for opening Story combat (E017)

The next route is Story's first action sequence. Let the user move/shoot/hit
enemies, report the room/tutorial and any failure, and repeat the encounter in
the same session if practical. Exit normally to finalize lifetime recordings.
Keep route reports and timestamps local; do not infer combat from a launch.

Alongside the lifetime coverage recorder, from an elevated PowerShell:

```powershell
.\source\scripts\measure-zarvot-cpu.ps1 -RunRoot $run.RunRoot -Seconds 900
```

The helper verifies the recorded executable/PID/start time and uses a unique
WPR instance with the built-in CPU.Verbose file profile. It stops/saves only its
own successfully started instance, on game exit, identity change or the bounded
duration. It sends no input and does not stop the game. Metadata/heartbeats and
WPR command results stay under cpu-profiles/<id>; a successful save produces
cpu.etl. Rejected starts remain explicit errors and never trigger stop/cancel.
Check state, recording_started, error, cleanup_error and trace_bytes; a launched
helper or successful start alone does not prove that a usable trace was saved.

E017's non-elevated attempt returned 0xc5585011, "Failed to enable the policy to
profile system performance." Windows administrator approval for just the recorder
allowed recording to start. No security policy/settings were edited. See
[Microsoft's WPR elevation guidance](https://learn.microsoft.com/en-us/windows/apps/develop/performance/power).
Synthetic tests cover full WPR argument preservation, unique-instance ownership,
normal exit/save, denied start, foreign process, PID reuse and failed-save cleanup.

Native sampling estimates CPU time statistically, not exact call durations or
frame percentiles. The trace is system-wide: filter the exact game process/start
time and actual combat interval before drawing conclusions. Retain raw ETLs
locally. Matching host symbols are in build/suyu/bin/suyu-cmd.pdb and .map;
the four generated DLLs have no PDB/maps, so initial AOT attribution is by module
and native address. Do not confuse helper stacks with guest-PC execution counts.

Portable Microsoft PerfView 3.2.8 is prepared under ignored local/tools/PerfView;
provenance.json records its official release, SHA-256 and valid Microsoft
signature. Its actual CLI help was checked. After a successful trace save,
sample-preserving export uses /AcceptEULA /ShowUnknownAddresses /LogFile:<path>
UserCommand SaveCPUStacks <closed cpu.etl>, with the child process's
_NT_SYMBOL_PATH pointing to build/suyu/bin. This produces cpu.perfView.xml.zip.
Omit the optional process-name argument and retain exact PID/time filtering for
analysis: that argument is a name, and /Process:<pid> does not apply to this
export command. Folded CSV is insufficient for matching the combat timeline.
Do not read or convert a trace still being recorded. E018 validated extraction
through the bundled TraceEvent library as described below; the generic PerfView
xml.zip export remains an alternate route, not the measured extraction method.

Diagnostic PC sampling also copies boundary snapshots, locks its histogram and
publishes coverage. Periodic captures convert/encode PNGs every 30 seconds.
Correlate CAPTURE log times before interpreting dips; these diagnostic runs are
not matched performance benchmarks. Fix measured recomp costs/coverage only.
Do not tune general graphics settings from a stack profile.

E017 closed run: build/zarvot-runs/20261011-030031-b40a1ca6. Native recording
started at 03:04:37 UTC (October 10 locally), then saved on game exit: state
complete, process_exited, 1,995,440,128-byte cpu.etl under
cpu-profiles/20261011-030437-c0fcc6ec. Game and recorders have exited. The user
confirmed first Story action and many slowdowns. All 232 UI/file samples had
zero fallback/import traps. Captures bound a combat window to 03:06:40-03:08:10
UTC: median interval FPS 7 (5.5-11.5), with 41/45 polls below 10. These are
diagnostic interval readings. E018 converted/profiled the saved evidence; recover
hot generated locations before requesting another performance playtest.

## Closed-trace exact-process analysis (E018)

From the workspace root, with the prepared local PerfView tool/libraries:

```powershell
.\source\scripts\analyze-zarvot-cpu.ps1 -ProfilePath $cpuProfile
# E017 combat: relative to ETL session start, not game launch or logger start.
.\source\scripts\analyze-zarvot-cpu.ps1 -ProfilePath $cpuProfile `
  -StartSeconds 122.1318034 -EndSeconds 212.1318034
```

The helper accepts only complete successful cpu-profile.json metadata and the
recorded trace size. It loads libraries unpacked by the matching local PerfView
executable, records their hash/version, converts once to cached cpu.etlx, then
filters the exact PID, full executable path and start identity. A pre-existing
process's trace start is clamped to session start; metadata's earlier recorder
checks remain part of the identity evidence. Basename alone is rejected.

Outputs under cpu-profiles/<id>/analysis/<id> include summary.json, sample-time
CSV, module shares and image/thread/process maps. Unknown addresses and lost
events stay explicit. Samples preserve native instruction pointer/RVA and UTC;
native RVAs must not be treated as guest PCs. No symbol-server downloads, game
input or new trace are performed. The typed ETL wrapper avoids an unrelated
optional EventPipe-client dependency in PowerShell overload reflection.

E018's first 2 GB conversion took about 70 seconds; cached title/combat windows
took about five seconds together. Full trace had 517,377 target samples; combat
had 157,467, with 71.64% compiled DLLs (main 65.01%, SDK 6.38%), host 13.17%,
unknown 10.98%. ETL reports 1 ms sampling and zero lost events. Title module
shares were similar; this does not identify the frame-rate limit. Analyzer
metadata/identity, UTC/clamped starts and 64-bit image-boundary tests passed;
full/window exports were live-data validated, and an empty range yielded zero.

The preserved host-attribution local prototypes checked host SHA, PE/map timestamp
and base, PDB GUID/age against the ETW image map, and bounded public labels using
PE unwind ranges where possible. Combat ArmRecomp::RunThread occupied 1.44% of
all leaf samples; four direct exclusive callbacks combined 0.22%. The largest
host bucket was Common::Event::WaitFor (4.31%), whose caller/cause is not established.
Inlining, padding, funclets, aliases and unbounded nearest labels remain limits.
Exact run-slice export extents account for 2,256 main and 682 SDK samples; most
main samples still need generated-function/helper attribution. No blanket helper,
guard, timing or graphics change follows from these proportions.

E019 recovered the mapping without compilation. From the source checkout,
using a 64-bit Python runtime:

```powershell
python scripts/zarvot_native_map.py --launch "$run/launch.json" --module main `
  --samples "$cpu/analysis/20261011-031644-3bb647f2/samples.csv" `
  --object build/recomp/zarvot/main/CMakeFiles/recompiled_image.dir/recomp_runtime.c.obj `
  --object build/recomp/zarvot/main/CMakeFiles/recompiled_image.dir/src/recompiled_main.c.obj `
  --output "$cpu/generated-mapping/main-combat-new"
python tests/test_zarvot_native_mapping.py
```

Here $run is the closed E017 run directory and $cpu its successful CPU profile
directory. Output must be a new ignored build/local/generated directory. The
tool verifies the canonical baseline build, image/manifest hash, exact process
and full sample module path, plus loaded-image size and every selected IP/RVA/
time interval before calling metadata-only image exports. Unwind starts and
index pointers bound block labels; object relocation masks preserve aliases.
Guest spans identify possible side entries, not the executing guest instruction.

E019 assigns 97.49% of main samples to block extents, object helpers or the
run-slice export. Six synthetic tests passed. The next candidate shares exact
FP32 add/sub/multiply fallback bodies while retaining inline native FPX checks.
Validate semantics and repeat quiet synthetic timings first; game speed remains
unmeasured. Keep a separate target for the eventual candidate export/build:

```powershell
.\scripts\build-zarvot.ps1 -Target zarvot-fp32-outline -ParallelJobs 2
```

That runner expects an already completed four-module export under
generated/zarvot-fp32-outline and writes its own build/recomp target and status.
The default target remains zarvot. Preserve the completed baseline DLLs/profiles;
do not repeat their main compilation just for symbols. A healthy candidate
build may take a long time and has no overall timeout.
