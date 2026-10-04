# Zarvot development

Read `docs/zarvot/STATUS.md`, `PLAN.md`, `EXPERIMENTS.md`, and `RUNBOOK.md`
before changing this fork. The upstream README describes MK8 research; the
Zarvot documents describe this project's actual state.

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

