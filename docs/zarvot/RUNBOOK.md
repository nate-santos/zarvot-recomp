# Zarvot local runbook

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
The game has reached the main menu with these controls.

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
- The submodule has not been initialized/built locally.
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
