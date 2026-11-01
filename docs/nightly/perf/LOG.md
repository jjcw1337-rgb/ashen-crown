# Performance job: attempts and results

The short log every nightly performance run reads first and adds to (`tools/nightly/perf_prompt.md`). One row per
attempt, kept or reverted, newest last. Keep the cells short: **Focus** what was tried (one line), **Result** the
numbers, **Kept** yes / no / partly, **Next** the follow-up it suggests, **Details** the run's full write-up.
**Type**: `big` (a structural change), `small` (a quick win), `size` (download size), `bench` (the runner's own
benchmark of the night's result, added by the script: the scoreboard; "blocked" = it was slower and didn't ship).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- The download is mostly textures: Godot extracts the glb textures and imports them by the importer's default, since
  the `.import` files are git-ignored; `[importer_defaults]` in project.godot is the lever (2026-11-01).
- The GPU is only 57-66% busy on the moor and the camp: the main thread is the limit, not the GPU (2026-11-01).
- The camp draws 152 M primitives a frame against the moor's 20 M: the biggest single rendering target (2026-11-01).
- Run-to-run noise on the benchmark is ~2-3% fps; a change smaller than that isn't a result.

## Log

| Date | Type | Focus | Result | Kept | Next | Details |
|---|---|---|---|---|---|---|
| 2026-11-01 | size | Model textures as lossy WebP q0.9 instead of lossless (`[importer_defaults] texture`, + 5 Plague dyes) | Mac zip 725→302 MiB, Win 704→281 MiB; load 5.2→3.8 s; fps same; look within noise | yes | The camp's 152 M primitives; main-thread profiling | [runs/2026-11-01.md](runs/2026-11-01.md) |
