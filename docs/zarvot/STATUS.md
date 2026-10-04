# Zarvot handoff — current state

Updated: 2026-10-04. Read this first when changing models.

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
| Z01 | In progress | Opening combat measured three times; moving/heavier fixture and per-frame stall diagnosis next; audio deferred this session |
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
3. Last state is paused in the opening jar combat tutorial with TAS stopped.
   Resume, or use Story > Continue after a restart. The original pre-test save
   and pre-TAS config are backed up locally; preserve subsequent user progress.
4. Establish a moving combat route that avoids repeated hits/respawns, then
   capture a real per-frame presentation trace. Compare with the stationary
   tutorial to locate the brief 0–12 FPS / zero-VBlank stalls. Keep the 1x/HIGH
   control; do not infer intended Switch behavior from the speed counter.
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
- Last verified screen is the in-game pause menu at the opening tutorial.
  Frame-based input playback solved unreliable short automated key taps;
  TAS is enabled, loop disabled, playback stopped. See the input helper.
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
