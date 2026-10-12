# Zarvot recomp gameplay checks

R03 begins from the compiled boot/title result in E013. The user performs the
inputs; agents prepare recording and review evidence. Original saves/profile
remain separate. A visible title and zero fallbacks establish only that route.

| Check | Current state | Required observation |
|---|---|---|
| P00: boot/title | Complete for E013 smoke scope | Four matching images; advancing AOT counts; visible title |
| P01: menus / Story entry | Opening Story action reached again in E023; Stadia Bluetooth works; broader menu checks pending | Buttons respond; menus/text render; opening Story loads |
| P02: opening movement / shooting | E021 movement/effects good; E023 shooting fine, performance felt about the same; detailed collision checks pending | Movement and shots behave correctly; no stuck input or visual corruption |
| P03: pause / restart / death | Pause menu rendered (E015); resume/restart/death pending | Pause/resume and restart/death flow behave correctly |
| P04: next scene / level | Different scene rendered (E015); transition correctness pending | Transition/load completes with correct visuals/input |
| P05: save / exit / relaunch | Untested in recomp | Reuse the same test profile; expected progress persists |
| P06: music / effects | E023 user reported audio fine during opening action; original fidelity and later transitions unverified | Audible/stable audio, pitch/loops/transitions; original-hardware fidelity remains separate |
| P07: later levels / modes / full game | Untested | Name each route and its evidence; track separately under R08 |

E014 opened the user playtest; E015 records combat performance issues. The user
initially noticed JIT transitions, but all 299 complete recorder reports showed
zero lookup/opcode transitions. Their possible count of six is now uncertain;
no gap PC is established.
Inspect the active run and process before launching another session.
E016 used UntilExit recording of both the actual caption and file counters.
All 146 samples showed zero transitions; the user noticed none and confirmed no
combat during this run. Captures show a Story room/dialogue. The run cloned the
prior closed test profile; compiled-PC sampling worked. Both game and recorder
have exited. Repeat combat and record its mode/level; E016 does not revalidate
combat cost or correctness, or disprove a historical transient observation.

Launch a fresh isolated Hybrid run using scripts/start-zarvot-recomp.ps1 with
-Visible -RecordCoverage; require CoverageRecorderState=attached before inviting
play. For CPU comparisons, separately verify the owned CPU recorder is recording.
The CLI title displays the active backend and fallback transitions;
F12 opens its existing controls panel. The recorder sends no input and makes no
gameplay or performance verdict.

Record the route, any failure and the matching timestamp. Retain captures,
coverage snapshots and logs locally. Group fallback PCs/reasons by module;
unexpected behavior can be a correctness defect even when transitions stay zero.
The launcher creates a fresh profile by default. P05 must deliberately reuse the
same staged profile or use -ProfileFromRun to clone a closed matching test run,
then have the user verify that expected progress persists. Copy hashes alone
do not establish save correctness.

## Next named route: first Story level / opening combat

E017 recorded this route: the user played the first action sequence and reported
many slowdowns/bad frame rates. Captures show the Story menu, opening jar arena
with Pew Pew prompt, combat effects/score and a Story transition. All 232 complete
UI/file samples had zero fallback/import traps; CPU trace saved on normal exit.
This does not establish input, restart/death, save or audio correctness. E018/E019
analyzed the trace and E020 produced a separately validated FP32 candidate.

E021 exercised that candidate on the first Story level/action. The user said it
seemed better and movement/effects looked good, with some frame-rate stutter.
Screenshots confirm the jar-arena/Chomp action; the final report records zero
fallback/import traps. Separate UI/native CPU recorders missed that short run.
At that point audio and save/death/restart behavior remained unconfirmed.
E023 subsequently repeated opening action with the E017 host, E016 initial
profile and verified recorders. The user confirmed Bluetooth works, shooting
and audio were fine, and performance felt about the same. Both recorders saved
on normal exit. E024 reviewed capture-bounded combat and mapped the native trace;
the next work is a compiled runtime prototype, not another immediate playtest.
Save/death/restart, detailed collisions and original music fidelity remain open.
Keep the initial candidate profile and all existing saves intact.

For a future focused repeat, start Story and reach the first
action sequence; report when combat begins and which room/tutorial name appears.
Move, shoot and hit enemies for a few minutes. If practical, restart and repeat
the same encounter in the same session. Report whether later hits still stall,
any visual/input/audio problem, and any visible JIT count. Exit normally when
finished so the lifetime recorder can finalize its evidence.

Record actual route/timestamps rather than assuming that launch means combat
started. Existing PC sampling ranks frequency, not CPU duration. Diagnostic
sampling, coverage publication and periodic PNG capture have overhead; correlate
capture times and attribute native samples before selecting a recomp change.
These runs do not establish a matched FPS gain or per-frame percentiles.

Strict testing must repeat an already checked named route with zero fallback
attempts and advancing counts. Prove no-JIT separately with its build graph,
symbol audit and runtime availability telemetry. Neither is established by E013.

No causal gameplay speedup has been established. E023 holds host, initial
profile and diagnostic configuration constant with E017, but action phase mix,
input/effects, Bluetooth transport and laptop load differ. Its 90 combat PERF
intervals have median 7.9945 FPS; E017's original window has median 6.997. The
user perceived similar performance. These interval readings do not establish
frame percentiles or exact enemy-hit latency. E021's earlier comparison had
additional host/profile/recording differences. E013 title
rates were interval observations with uncontrolled startup/caches/focus.
Preserve original timing/music behavior when investigating compiled-code cost.
