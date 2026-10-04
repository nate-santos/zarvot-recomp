# Zarvot handoff — current state

Updated: 2026-10-04. Read this first when changing models.

Session stopped at the user's request. The user will perform gameplay testing
later; do not resume automated play. README now contains the real E003 opening
tutorial measurements. A manual recorder is prepared; a representative fresh
manual benchmark is pending. See E004 for the latest limits and local evidence.

## Outcome so far

Zarvot 1.0.0 runs controllable opening Story gameplay on the laptop using
Dynarmic JIT + Vulkan at handheld 1x/HIGH. Movement, shooting, pause and level
restart work. Three 60-second combat observations had medians near 60 FPS and
means of 57.4–57.9 FPS, with recurring brief severe stalls. Gameplay baseline
evidence and reusable tools exist; stall causes, later levels, audio fidelity
and AOT performance remain unverified. See E003 in EXPERIMENTS.md.

GitHub fork: https://github.com/nate-santos/zarvot-recomp

Branch: `zarvot-support`, with local checkout under workspace `source/`.
The repository has `origin` (our fork) and `upstream` (mk8-recomp).

## Task state

| ID | Status | Evidence / next condition |
|---|---|---|
| Z00 | Complete | Fork, branch, roadmap, handoff, source ignore rules and runtime identity recorded; use Git history for commit/sync state |
| Z01 | In progress | E003 opening tutorial measured; manual recorder prepared; user's later moving/heavier playtest and per-frame stall diagnosis next |
| Z02 | Ready after controlled baseline | Focus affects observed FPS; repeated play-time path errors; audit logging flags |
| Z03 | Ready after scene fixture | 1x vs lower-scale A/B to classify GPU pressure |
| Z04 | Planned | Resolve runtime/source revision mismatch before core changes |
| Z05 | Planned | AArch64 eligible; no hybrid export/build/run yet |
| Z06–Z10 | Conditional | Choose based on measured bottlenecks and correctness evidence |
| Z11 | Planned | Launcher, save checks, endurance and reproducibility |
| Z12 | Deferred | Full port only if profiling and maintainability justify it |

## Next session sequence

1. Check current process/UI rather than assuming the game is still running.
2. Check `git status` and branch ahead/behind state; preserve any later user edits.
3. Last RPC observation: game loaded but emulation thread stopped (paused), TAS
   playback/recording off. Leave control with the user; preserve subsequent
   progress. The original and E004 pre-test saves/configs are backed up locally.
4. When the user is ready, record three matched moving/combat routes with the
   manual recorder in RUNBOOK. Do not drive, restart or overwrite their save.
   Compare with E003 to investigate the brief 0–12 FPS / zero-VBlank stalls.
   PresentMon 2.6.0 could not start ETW capture (Windows access denied); genuine
   per-frame timings remain pending. Keep 1x/HIGH as the control.
5. Use an equivalent scene for Z02/Z03 A/B tests (logging/path diagnostics,
   then resolution sensitivity). Identify the bottleneck before CPU/AOT work.
6. Update this file and append an experiment after each meaningful result.

## Facts and open issues

- Title ID `0100E7900C4C0000`; NSP 1,706,554,634 bytes; base metadata version 0;
  running game identifies as 1.0.0; loader confirms 64-bit ARM.
- Local key files were supplied and installed. Never include contents in chat,
  logs or Git. No further acquisition/dumping work is requested.
- Host Ryzen 7 5825U / AMD integrated graphics. Runtime reports 13.85 GiB host
  RAM and 2.00 GiB dedicated GPU budget; shared graphics memory is separate.
- Title/menu images are in workspace `reports/`; see experiment ledger.
- Earlier 33 FPS readings became ~60 after foreground activation/focus. This
  is an environment hypothesis, not a measured optimization win.
- Fifteen foreground main-menu polling samples averaged 59.999 FPS; reported
  samples ranged 59.945–60.080. No per-frame latency distribution was captured.
- TAS is enabled, loop disabled, playback stopped. Manual playtesting is the
  user's preference; prepared recorder sends no controller input. Earlier
  automated attempts did not verify clearing the opening encounter.
- E003 is actual gameplay, but its repeated stationary-fire observations have
  uncontrolled enemy/respawn phases. A stronger moving/heavy combat fixture
  and genuine per-frame trace are still needed for optimization comparisons.
- Opening combat GPU 3D activity averaged 49–53%, observed peak 62.6%; emulator
  CPU use averaged about 2.5 logical cores and working set peaked at 6.16 GiB.
  No proven CPU/GPU bottleneck; aggregate utilization can hide critical stalls.
- Music fidelity is unverified. A 48 kHz stereo output stream initialized;
  neither a hardware-reference comparison nor a listening test has been done.
- Repeated play-time database write errors need diagnosis. Do not create a
  directory based solely on a possibly rewritten user path in a log.
- Runtime asset tag differs from its embedded version string and from the
  wrapper's pinned emulator commit. Exact identities are in RUNBOOK.md.
- No source emulator build or static/hybrid Zarvot export exists yet.
- RPC launch timeout did not imply boot failure; state and rendering later
  confirmed success. Avoid duplicate launches after timeouts.

## Decisions to preserve

- Baseline and fallback is JIT; native coverage is not the optimization goal.
- Prioritize easy measured wins and the iGPU bottleneck test before deep AOT.
- Preserve original music assets, playback logic and timing throughout.
- Canonical plan is PLAN.md, current state is this file, results append to
  EXPERIMENTS.md. Root PROJECT_PLAN.md only points here; avoid duplicate plans.
- Share source and sanitized evidence. Raw game/code/keys/captures stay local.
