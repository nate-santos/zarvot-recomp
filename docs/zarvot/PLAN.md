# Zarvot PC optimization roadmap

Updated: 2026-10-04. Owner: the user; any model can continue via STATUS.md.

## Objective and constraints

Run the user's Zarvot Switch base release reliably on a Windows laptop with a
Ryzen 7 5825U and integrated Radeon graphics. Preserve gameplay speed, input,
saves, visuals and the original music's pitch, looping, mixing and transitions.
First achieve stable original behavior at handheld resolution; then reduce
stutters, CPU/GPU cost, power consumption and startup time. Higher resolution
or frame rates are optional later goals, not substitutes for fidelity.

The observed title/menu runs at approximately 60 FPS in the foreground. This
does not establish the intended frame rate of every gameplay scene. Confirm
original behavior before setting scene-specific budgets (16.67 ms for 60 FPS,
33.33 ms for 30 FPS). An emulator's 100% speed counter is not proof of correct
physics or audio timing.

## What “more native” can and cannot improve

The baseline Dynarmic JIT already translates ARM instructions into native host
machine code. AOT moves that translation before launch; it does not inherently
make the resulting code faster. Both routes still need Switch memory, OS,
graphics and audio behavior. Host GPU shaders also already execute on the PC
GPU after translation. Graphics bandwidth, synchronization, shader compilation,
thermal limits or audio starvation can dominate even with 100% AOT CPU coverage.

Use Amdahl's law to bound proposals: if guest CPU execution is 30% of frame
time, making that entire portion free can improve total speed by at most
1/(1-0.30), or about 1.43x. Coverage by number of blocks is not time saved.
Measure time in hot code, translation and backend transitions separately.

## Priority order

Impact below is a hypothesis conditional on the measured bottleneck, not a
promised percentage. Effort describes engineering complexity, not a deadline.
Reorder the ready queue when evidence changes the expected benefit.

| ID | Work | Effort | Potential benefit | Dependencies / acceptance |
|---|---|---|---|---|
| Z00 | Durable project state, fork, branch, reproducible runtime identity | Small | Enables reliable progress | Docs, ignores, pinned hashes and next action exist |
| Z01 | Foreground gameplay/audio baseline and bottleneck classification | Small–medium | Highest decision value | Representative scenes and repeatable timings |
| Z02 | Cheap settings, cache, local-path and logging fixes | Small | High if throttling, shader stutter or avoidable overhead dominates | A/B evidence; no fidelity regression |
| Z03 | Resolution and GPU workload tuning | Small–medium | Potentially largest immediate FPS gain on the iGPU | Z01; preserve native-resolution reference |
| Z04 | Compare a compatible runtime revision / backend | Medium | High if this experimental build has a regression | Same game, scene, settings and driver |
| Z05 | Hybrid AOT feasibility and honest JIT comparison | Medium | Uncertain; startup/stutter benefit possible, slowdown possible | Z01, matching exporter/runtime/toolchain |
| Z06 | Profile-guided AOT hot-path coverage and fewer transitions | Medium–large | High only if hot fallback or dispatch dominates | Z05 and CPU profiles |
| Z07 | Generated-code compiler and runtime optimization | Medium–large | Moderate–high on a demonstrated CPU bottleneck | Correctness gate and profiler evidence |
| Z08 | GPU translation, synchronization and memory optimization | Large | High if graphics submission/bandwidth dominates | Z03 profiling and emulator source build |
| Z09 | Targeted native replacements for measured expensive routines | Large | Potentially high, title-specific and risky | Recovered semantics plus differential tests |
| Z10 | Audio scheduling, decoder and mixer efficiency | Medium–large | Fewer glitches and lower overhead if audio is a bottleneck | Audio capture/reference suite; fidelity first |
| Z11 | Standalone launcher, endurance testing and reproducible release tooling | Medium | Usability, reliability, consistent startup | Best validated backend, save and audio gates |
| Z12 | Full native engine/API port investigation | Very large | Speculative ceiling, high maintenance cost | Only if remaining bottlenecks justify it |

Audio correctness checks apply to EVERY phase. Fix a discovered audio regression
immediately; Z10 is the later optimization phase, not permission to defer sound.

## First experiments: low effort and high expected return

### Z01 — Establish representative tests

- E003 now provides opening combat observations: roughly 60 FPS between brief
  severe stalls, with 57.4–57.9 FPS run means. The user will do gameplay testing;
  prepare/record their matched routes without automated play. Next prioritize a
  moving route and per-frame capture around hit/respawn effects; average GPU use alone
  does not identify the stall cause. Keep this baseline as the control.
- Record title/menu, a repeatable early story segment, a combat-heavy segment,
  a scene transition and a longer music loop. Add versus/arcade later.
- Keep focus/visibility, charger state, Windows power mode, display refresh,
  GPU driver, background applications, game version and settings consistent.
  Record RAM capacity/channel configuration and temperatures/power when available.
- Warm up first. Repeat equivalent 60–120 second routes at least three times;
  compare medians and run-to-run spread. Keep cold shader-cache startup separate.
- Start with lightweight emulator telemetry. Its periodically reported FPS is
  a health sample, NOT a per-frame trace and cannot establish 1% lows or p99.
  Add per-frame presentation timings and CPU/GPU profiling only where needed.
- Track game FPS, frame-time p50/p95/p99 from genuine frame traces, spikes above
  2x frame budget, load time, CPU/GPU time, shared/dedicated memory use, power,
  temperature and audio underruns when the runtime exposes them.
- Do not interpret background/minimized timing as a gameplay benchmark.

### Z02 — Remove accidental overhead

- Inspect the repeated play-time file-write failure and any other path errors.
  Verify effective paths from this build before patching: logs and config have
  shown different user-directory spellings. Do not create guessed external paths.
- Confirm disk shader and CPU translation caches are enabled, retained and
  compatible. Warm caches through real scenes. Keep a cold-cache comparison.
- Audit release-mode logging and GPU debugging flags. Disable expensive
  diagnostics only after establishing their actual behavior in the source.
  Keep error reporting. Measure before/after; checkbox names alone prove nothing.
- Test normal vs high GPU accuracy only on representative scenes, with a saved
  high-accuracy control. Roll back if particles, blending, shadows or timing differ.
- Investigate the foreground/background FPS discrepancy. Standardize the test
  environment before declaring that an engine optimization is needed.

### Z03 — Is graphics the limiting factor?

- Compare fixed 1x handheld resolution with a lower scale in the same scene.
  A substantial improvement suggests pixel/shader/bandwidth pressure; little
  change calls for CPU, synchronization or frame-cap investigation.
- Test asynchronous shader compilation separately, accepting it only if it
  reduces stutter without missing effects or other visible errors.
- Compare Vulkan and OpenGL when this driver/title gives a concrete reason.
  Warm each cache separately; backend changes are not CPU-backend experiments.
- Investigate texture uploads, ASTC decode, render-target copies and memory
  pressure only if profiling finds them. Avoid speculative global quality cuts.
- Lower resolution with a reconstruction filter can be offered as an optional
  performance preset; it is not an equal-image-quality engine speedup.

### Z04 — Eliminate runtime regressions early

The downloaded asset is tagged v0.0.12, but the executable identifies itself
as v0.0.11 / HEAD-40aeb31824-HEAD. The wrapper pins another emulator commit.
Record executable SHA-256 and actual revision, then align source, exporter,
generated image ABI and runtime before changing core code. Test a second
established compatible build if baseline problems point to this experimental
fork. Preserve portable profiles and backups; do not silently migrate saves.

## Native CPU work, gated by evidence

### Z05 — Prove the path before investing in it

Zarvot 1.0.0 is verified AArch64. Inventory its modules/build IDs, confirm any
runtime-loaded code, then generate an ignored hybrid export. Confirm toolchain
availability before a lengthy build. Match exporter and runtime ABI.

First compare identical JIT and hybrid runs with graphics/audio settings fixed.
Verify static execution counters, hot fallback PCs and transition counts.
Only attempt strict AOT after hybrid coverage and correctness are convincing.
Never call a build native merely because export succeeded or a Windows EXE exists.
If AOT is slower, retain JIT as the default and investigate only profiled causes.

### Z06–Z07 — Optimize the hot work, not the block count

- Rank missed instructions, indirect targets and loaded modules by execution
  frequency AND time. Repair expensive misses first; leave cold fallback working.
- Check the exact current source before implementing features: older upstream
  architecture documents describe v0.0.4, while later revisions already report
  fast memory, code-generation guards and exact floating-point fast paths.
- Reduce backend handoffs and repeated context copying; then investigate
  direct block linking, indirect-branch caches and larger hot regions.
- Test Clang versus MSVC and optimization levels on representative generated
  units. Try LTO/PGO only after a useful profile exists and compile/memory costs
  are recorded. Optimize the emulator host separately from translated modules.
- Profile register spills, helper calls, memory translation and bounds checks.
  Preserve permissions, code invalidation, memory ordering, exclusives and
  Switch floating-point state. No blanket fast-math or unchecked pointer casts.
- Use instruction/block differential tests plus repeatable game routes when
  changing translation, scheduling or memory semantics.

## Graphics and targeted native replacements

### Z08 — Reuse mature graphics behavior

Profile command submission, CPU/GPU fences, shader pipeline compilation,
descriptor updates, texture conversion, readbacks and redundant state changes.
Prefer batching, cache reuse, reduced copies and correct synchronization over a
graphics rewrite. A Vulkan-native replacement for a narrow expensive path may
be valuable, but needs image comparisons and timing measurements on AMD iGPU.

### Z09 — Replace expensive library boundaries selectively

If identified in the binary and hot in profiles, investigate bulk copies,
decompression, texture conversion, math kernels or other stable library calls.
Use native host routines only when calling conventions, guest pointer mapping,
alignment, overflow, floating-point and side-effect semantics are understood.
Keep a selectable original path and differential inputs/results. This can be
more effective than translating additional cold game code.

Detect the game's engine/toolchain from verified metadata before considering
engine-specific work. Do not assume a Unity/IL2CPP binary can be rebuilt for PC
by swapping a player executable, or that the original engine project exists.

## Audio fidelity and efficiency

Keep original assets and game-controlled playback. Preserve sample rates,
decoder state, sample-accurate loops, layered tracks, fades, spatial/channel
mixing, reverb and timing. The baseline opens a 48 kHz stereo cubeb stream;
that proves device initialization only, not that the music is correct.

Build an audio reference set from matching Switch scenes if the user can
provide one. Until then report PC audibility/stability separately from
original-hardware fidelity. Compare pitch/tempo, loop boundaries, transition
latency, clipping and A/V drift; allow alignment/device resampling differences
when deciding whether a waveform comparison is meaningful.

Optimize by preventing starvation, separating audio deadlines from long shader
compiles, avoiding allocation/I/O in callbacks, using bounded buffers, and
profiling decoder/mixer work. Cache or vectorize only verified hot paths. Test
buffer size vs latency without changing tempo. Do not use time stretching,
replacement soundtrack playback or reduced audio quality to hide slow execution.

## Completion and decision rules

Accept a performance change only when repeated matched runs show a useful gain
beyond noise and correctness/audio checks pass. At a stable frame cap, prefer
reduced frame-time spikes, power or CPU/GPU cost over claiming extra FPS.
Label small noisy gains inconclusive and revert regressions.

Z11 requires: cold boot, menus, input, save/load, representative gameplay,
transitions, 30+ minute stability and audio-sync checks. A launcher must use the
user's local files and preserve saves. Publish source/tooling and sanitized
measurements, not generated game code or assets. Full playthrough validation
remains a separate milestone from representative-scene testing.

Stop expanding native code if the best measured backend already meets the
target or the remaining cost is elsewhere. Z12 is a research option, not the
default destination. It requires sufficient reverse engineering, test coverage
and a demonstrated benefit over the maintained compatibility runtime.

## Cross-model workflow

1. Read STATUS and the last experiment before acting.
2. Choose one ready ID; write the hypothesis, control and rollback.
3. Save raw evidence under ignored `local/` (or workspace `reports/`).
4. Change one variable and run matched checks.
5. Append an experiment with result, limits and decision; update STATUS.
6. Commit explicit shareable paths. Record commit ID and publication status in
   the handoff; keep incomplete work plainly marked. Never mark a task complete
   solely because code was written or a build succeeded.

Upstream reference: https://github.com/dougchansan/mk8-recomp
