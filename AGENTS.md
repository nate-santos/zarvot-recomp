# Zarvot development

Read `docs/zarvot/STATUS.md`, `PLAN.md`, `EXPERIMENTS.md`, and `RUNBOOK.md`
before changing this fork. The README summarizes measured Zarvot results;
inherited upstream research is context, not Zarvot validation.

Scope is recomp builds, coverage, correctness and execution improvements only.
JIT is a reference and temporary fallback. General emulator performance tuning
is outside scope. Follow the R task queue; historical Z tasks are retired.
Do not gate export/build work on fresh JIT benchmarks or stop at JIT performance.

This laptop builds slowly. Allow healthy builds to finish; elapsed time or a
quiet compiler alone is not failure. Keep generated CMake's memory-aware job
pool, build modules sequentially and check compiler activity/object progress.
Resume existing build trees incrementally. Check processes and
`build/recomp/zarvot/build-status.json` before starting a second build; a status
marked building is not proof its process is still alive. Stop only on an actual
error, demonstrated resource failure or an explicit user request.

Keep stable task IDs and update evidence, decisions and the next action after
each meaningful experiment. Never claim gameplay/audio fidelity from a title
screen or an initialized audio device. Do not infer a speedup from AOT coverage.

Use `zarvot-support` for current work. Keep `main` aligned with upstream until
there is a reason to change it. Source fixes belong in the emulator submodule;
fork that repository when a concrete core change is ready, preserve its history,
and commit the new submodule pointer in this repository.

Do not commit game data, keys, firmware, translated game code, raw traces,
screenshots, saves or local machine paths. Use `local/`, `generated/`, `build/`
and `targets/` for ignored output. Stage explicit source paths and review the
staged diff before commits or publication. Keep licenses and provenance intact.

Prefer one variable per performance experiment, repeatable foreground scenes,
warm and cold cache results kept separate, and rollback to a saved configuration.
Do not silently enable inaccurate CPU/GPU options to improve a benchmark.

The user handles gameplay testing. Do not automate play or change controller
state unless the user requests it again. Prepare recording and analyze evidence.
