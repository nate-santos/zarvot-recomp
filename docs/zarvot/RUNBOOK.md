# Zarvot recomp runbook

Updated scope: 2026-10-05. Follow the R task queue in STATUS and PLAN.
The runtime commands below preserve historical reference/validation procedures;
they are not a general emulator optimization queue.

## Recomp build workflow — next work

No Zarvot source build or export command sequence has been validated yet.
Record exact successful commands here as R00-R02 progress; do not present
inherited MK8 scripts as already tested for Zarvot.

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
- Pinned emulator submodule: `5949cab3ba93233ddd1c319bfc6f010f6cfa910a`.
- The pinned submodule is initialized; matching source build is in progress (E007).
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
This command is underway, not yet a verified successful build. Check running
build processes and the log before starting another one. Source export and
module compilation commands remain unverified for Zarvot.

## Planned first hybrid export

After the matching exporter is built and its separate local configuration is
prepared, open its export dialog through the RPC driver. This command has offline
argument/reply checks but remains unverified with Zarvot. From the source root,
with local Python on PATH and the exporter already running:

```powershell
python scripts/export-recomp.py --rom ..\Zarvot.nsp --out generated\zarvot\out --backend hybrid source
python scripts/mcp-call.py get_aot_export_status
```

Wait for done=true and success=true, then inspect the AOT manifest and modules.
The driver's zero exit means the request was accepted; it does not mean export
finished. Keep the exporter separate from any player session and verify ownership
before opening the dialog. The inherited automated export/build runner remains
unverified for Zarvot and must be reviewed before use.
