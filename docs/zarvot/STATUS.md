# Zarvot recomp handoff

Updated: 2026-10-05. Recomp plan committed as 5c6156a; R00/R01 complete; R02 in progress (E010).

## Objective and next action

Work only on the recomp: build, coverage, correctness and execution improvements.
Reuse the compatibility stack. Do not resume general emulator performance,
settings or GPU tuning. JIT is a reference and temporary hybrid fallback.

**Next: R02 — compile the remaining main/sdk/subsdk0 modules and prove compiled
execution.** The matching host/exporter and Hybrid source export are complete;
rtld compiled and loaded, but boot observations showed zero executed AOT blocks.
Main contains about 3 GB of generated C: review compiler availability and the
generated compile pool before starting a large build. Build/export commands and
artifact identities are recorded in RUNBOOK. Do not repeat R00/R01 unnecessarily.

## Verified progress

- Zarvot 1.0.0 is AArch64, title ID `0100E7900C4C0000`; base metadata version 0.
- E001-E004 establish JIT boot and controllable opening Story gameplay only.
  Movement, shooting, pause and restart worked. No recomp gameplay was tested.
- E003 interval measurements averaged 57.4-57.9 FPS with brief stalls. They are
  historical reference, not a recomp result; per-frame timings remain absent.
- E005 installed CMake 4.4.3, VS Build Tools 2022 17.14.41, MSVC 19.44.35229.0,
  Windows SDK and bundled Ninja. C/C++ smoke builds/execution passed (2/2).
- R00/R01: matching source host/exporter built; Hybrid ABI 6 export completed
  for main/rtld/sdk/subsdk0. Feature bits 7; translate_all enabled.
- R02: rtld compiled and loaded; main/sdk/subsdk0 are not compiled. No advancing
  AOT execution, strict-static or no-JIT result has been established.
- Later levels, full playthrough and original music fidelity remain unverified.

## Active task state

| ID | State | Evidence / next condition |
|---|---|---|
| R00 | Complete | Pinned source built suyu/suyu-cmd; command-line host smoke exited 0; exporter RPC worked (E010) |
| R01 | Complete for fixed exported modules | Four-module Hybrid ABI 6 source/manifest exported successfully; late-loaded/generated code remains unverified |
| R02 | In progress | rtld DLL compiled/loaded; main/sdk/subsdk0 builds and actual execution proof pending |
| R03 | Pending R02 | User-led hybrid correctness checks and categorized fallback evidence |
| R04 | Pending R03 | Iterative coverage/translation fixes with focused tests |
| R05 | Pending validated routes | Strict-static zero-fallback tests, then separate no-JIT verification |
| R06 | Pending R03 evidence | Profile and improve generated code/AOT runtime; preserve correctness |
| R07 | Pending R05 | Reproducible recomp package and endurance checks |
| R08 | Pending R05 routes | Expand later-level/mode coverage; track full playthrough separately |

The old Z queue is retired; PLAN.md maps it to this queue. E001-E005 retain
their original IDs and observations. General emulator stall diagnosis, resolution
A/B and logging/cache tuning are no longer next actions.

## Resume procedure

1. Read PLAN and latest ledger entry; check actual Git state and processes.
2. Recomp roadmap, README, instructions and E005/E006 are committed in 5c6156a.
   Preserve subsequent changes and check current ahead/behind state afresh.
3. Inspect existing generated export and build artifacts at the identities in
   RUNBOOK. Resume R02; source remains unchanged at its pinned revision.
4. Continue R02 without waiting for manual JIT performance tests. Inspect
   current project sessions before launching or stopping anything.
5. The user handles gameplay. The separate recomp smoke host was stopped after
   an unverified boot; no controller inputs were sent. No suyu process remained
   in the final desktop process check. Recheck actual state before launching.
   Preserve the original player profile/saves; do not automate play.
6. Append evidence and update the relevant R row after each meaningful result.

## Identities and preserved local evidence

- Checkout: source/; branch: zarvot-support; origin: nate-santos/zarvot-recomp;
  upstream: dougchansan/mk8-recomp. Workspace root is not a Git repository.
- Wrapper base db36cf5; pinned suyu 5949cab3ba93233ddd1c319bfc6f010f6cfa910a.
- Installed asset labeled v0.0.12 reports v0.0.11 / HEAD-40aeb31824-HEAD.
  Exact hashes and paths are in RUNBOOK; labels alone do not establish ABI match.
- Host: Ryzen 7 5825U / integrated AMD Radeon, 16 GiB installed RAM.
- Preserve portable JIT profile (Vulkan, handheld 1x/HIGH, original timing),
  saves and E004 backups. Use separate recomp output/profile as needed.
- Local keys already supplied; do not print contents or request acquisition.
- Raw evidence is in reports/; generated code/assets remain ignored and local.
- Existing manual recorder sends no controller input. PresentMon ETW capture
  failed with access denied; no frame-percentile claims follow from old polls.
- RPC launch timeout previously did not imply boot failure. Inspect state before
  retrying. Play-time path errors are historical, not an active tuning task.

## Decisions to preserve

Coverage, correctness and recomp efficiency are separate goals. AOT coverage is
valuable even without an FPS gain, but does not itself prove speed or fidelity.
Do not stop recomp work because JIT is fast enough. Keep graphics/audio support
and original gameplay/music behavior. Fix source in the appropriate recomp
components; current upstream features must be inspected before reimplementation.
R00/R01 are complete; keep building toward the eventual optimized Zarvot recomp.
The first module-loading smoke test stalled before AOT execution. Current source
requires a firmware preflight dialog in this empty firmware profile; that is the
leading explanation, not a visually verified diagnosis. Computer-use inspection
timed out awaiting app approval. The test host was stopped; next work can compile
remaining modules independently. No gameplay/coverage claim follows.
