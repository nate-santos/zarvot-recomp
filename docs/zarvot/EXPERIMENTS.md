# Zarvot experiment ledger

Append results; do not rewrite an unsuccessful experiment as a success.
Raw files remain local. Sanitized summaries can be committed.

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

## Template for the next experiment

- ID / task / date:
- Hypothesis and expected bottleneck:
- Runtime commit + executable hash / game version / backend:
- Scene, exact input route, duration, focus, power, cache and settings:
- Control / candidate (one changed variable):
- Raw local evidence paths:
- Results and run-to-run spread:
- Visual, input, save and audio checks:
- Limitations / unverified claims:
- Decision: keep / revert / inconclusive / defer:
- Next action and rollback:
