# Zarvot recomp gameplay checks

R03 begins from the compiled boot/title result in E013. The user performs the
inputs; agents prepare recording and review evidence. Original saves/profile
remain separate. A visible title and zero fallbacks establish only that route.

| Check | Current state | Required observation |
|---|---|---|
| P00: boot/title | Complete for E013 smoke scope | Four matching images; advancing AOT counts; visible title |
| P01: menus / Story entry | Untested in recomp | Buttons respond; menus/text render; opening Story loads |
| P02: opening movement / shooting | Untested in recomp | Movement and shots behave correctly; no stuck input or visual corruption |
| P03: pause / restart / death | Untested in recomp | Pause/resume and restart/death flow behave correctly |
| P04: next scene / level | Untested in recomp | Transition/load completes with correct visuals/input |
| P05: save / exit / relaunch | Untested in recomp | Reuse the same test profile; expected progress persists |
| P06: music / effects | Untested in recomp | Audible/stable audio, pitch/loops/transitions; original-hardware fidelity remains separate |
| P07: later levels / modes / full game | Untested | Name each route and its evidence; track separately under R08 |

E014 opens the user playtest with recording; behavioral results are pending.
Inspect the active run and process before launching another session.

Launch a fresh isolated Hybrid run using scripts/start-zarvot-recomp.ps1 -Visible;
use scripts/measure-zarvot-coverage.ps1 against its returned run directory while the
user plays. The CLI title displays the active backend and fallback transitions;
F12 opens its existing controls panel. The recorder sends no input and makes no
gameplay or performance verdict.

Record the route, any failure and the matching timestamp. Retain captures,
coverage snapshots and logs locally. Group fallback PCs/reasons by module;
unexpected behavior can be a correctness defect even when transitions stay zero.
The launcher creates a fresh profile each time, so P05 must deliberately relaunch
the same staged executable/config/profile rather than create another fresh run.

Strict testing must repeat an already checked named route with zero fallback
attempts and advancing counts. Prove no-JIT separately with its build graph,
symbol audit and runtime availability telemetry. Neither is established by E013.

No recomp speedup has been measured. E013 title rates were interval observations,
with uncontrolled startup/caches/focus, and do not support a comparative claim.
Preserve original timing/music behavior when investigating compiled-code cost.
