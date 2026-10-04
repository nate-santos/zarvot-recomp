# Zarvot PC performance project

This fork investigates running and optimizing Zarvot 1.0.0 on Windows with a
Ryzen 7 5825U and integrated Radeon graphics. Controllable opening Story gameplay
runs through Dynarmic JIT and Vulkan. Later-level reliability, music fidelity and
an AOT performance improvement remain unverified.

The JIT already executes translated native host instructions. Increasing AOT
coverage is an experiment; measured gameplay improvements determine priorities.

## Measured gameplay performance

Measured **2026-10-04** on Ryzen 7 5825U / integrated AMD Radeon, 16 GiB installed
RAM, AC power, Windows Balanced scheme and a 60 Hz display. Runtime asset v0.0.12
identifies itself as v0.0.11 / `HEAD-40aeb31824-HEAD`; exact hashes are in the
[runbook](docs/zarvot/RUNBOOK.md#source-and-runtime-identity).

Settings: Dynarmic JIT, Vulkan, handheld **1x**, **HIGH** GPU accuracy, 100% speed,
multicore and disk shader cache enabled; asynchronous shaders disabled.

Scene: opening jar / `Pew Pew` combat tutorial, stationary sustained A input.
These are three approximately 60-second observations of the same encounter;
enemy, hit/respawn and camera phases varied. The scene had already been visited,
and the existing shader cache was retained.

| Run | Duration (s) | Polls | Mean FPS | Median FPS | Minimum reported FPS | Polls below 55 |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 60.585 | 58 | 57.862 | 59.998 | 11.994 | 3 |
| 2 | 60.621 | 58 | 57.447 | 59.997 | 1.001 | 4 |
| 3 | 60.611 | 58 | 57.395 | 59.998 | 0.000 | 4 |

Most readings were near 60 FPS, with brief severe stalls around observed
hit/fade/respawn effects. Mean GPU 3D activity was 48.6–53.0%; mean process CPU
use was about 2.5 logical-core equivalents. These aggregates do not identify the
bottleneck. No optimization speedup has been demonstrated.

FPS values are emulator interval polls at approximately one-second intervals,
not individual frame timings. The minimum is a reported interval FPS reading,
not a 1% low. Per-frame p99, representative later combat and an original-hardware
comparison are still pending. A PresentMon capture attempt failed with Windows
ETW access denied. See [E003 and E004](docs/zarvot/EXPERIMENTS.md) for evidence and
limits. A later 10-second movement smoke test is excluded from this table.

## Record your gameplay

The user handles playtesting. The recorder sends no controller input and does
not change settings or pause the game. From the workspace root, with the existing
portable runtime running:

```powershell
.\source\scripts\zarvot-benchmark.ps1 `
  -ConfigPath .\runtime\suyu-v0.0.12\user\config\qt-config.ini `
  -EmulatorPath .\runtime\suyu-v0.0.12\suyu.exe `
  -Scene 'Opening combat, manual route, run 1' `
  -OutputPath .\reports\manual-run1.json `
  -Seconds 60 -IncludeGpuCounters
```

There is a ten-second countdown to resume and focus the game. Keep it visible
and foreground, on the charger. Warm up the scene first, then repeat the same
route three times with distinct output filenames. Keep pauses, deaths and scene
transitions documented; do not combine different scenes into an optimization
comparison. Saved profile settings and their hashes accompany the local results;
in-memory settings and focus are not continuously verified.

## Continue development

- [Current status and next action](docs/zarvot/STATUS.md)
- [Prioritized optimization roadmap](docs/zarvot/PLAN.md)
- [Experiment ledger](docs/zarvot/EXPERIMENTS.md)
- [Setup, controls, measurement and Git workflow](docs/zarvot/RUNBOOK.md)

Next: representative manual gameplay baseline, stall diagnosis, then matched
logging/cache and resolution experiments. Core/AOT work follows bottleneck
evidence and matching runtime/source versions. The current emulator submodule
has not been built locally; there is no Zarvot native executable export yet.

## Repository and provenance

Development branch: `zarvot-support`. `scripts/zarvot-*.ps1` and `docs/zarvot/`
contain this project's tooling and maintained handoff. Other inherited scripts,
tests and research notes retain upstream context and are not Zarvot validation.

Based on [dougchansan/mk8-recomp](https://github.com/dougchansan/mk8-recomp), with
its pinned [suyu fork](https://github.com/dougchansan/suyu-v0.0.4) submodule.
Retain upstream notices and component licenses. Only our source/tooling and
sanitized measurements are shared; game packages, keys, saves, captures and
generated game code stay local. See [repository policy](LEGAL.md).

License: GPL-3.0-or-later, matching upstream. Emulator history and licensing are
documented in its [PROVENANCE.md](https://github.com/dougchansan/suyu-v0.0.4/blob/mk8-recomp/PROVENANCE.md).
