# Performance job: attempts and results

The short log every nightly performance run reads first and adds to (`tools/nightly/perf_prompt.md`). One row per
attempt, kept or reverted, newest last. Keep the cells short: **Focus** what was tried (one line), **Result** the
numbers, **Kept** yes / no / partly, **Next** the follow-up it suggests, **Details** the run's full write-up.
**Type**: `big` (a structural change), `small` (a quick win), `size` (download size), `bench` (the runner's own
benchmark of the night's result, added by the script: the scoreboard; "blocked" = it was slower and didn't ship).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **Measure the GPU, not TIME_PROCESS.** `cpu_process_peak_ms` includes drawing and the wait for the GPU; the KPI now
  has `script_ms` / `render_cpu_ms`. On the Mac every scene is GPU-bound (moor High, 2026-11-02: scripts 9 ms, render CPU
  2 ms, GPU 53 ms). The 11-01 "main thread is the limit" reading was wrong.
- **Switch things off one at a time** (`--hide`, `--hide Props#a-b`, `--noshadow`, `--envoff`, `--mmnoshadow`,
  `--census`): every win tonight came from a bisect, and two of the three were not where the triangle counts pointed.
  `Grade.pick_shadows` turns shadows back on every 0.4 s: take lights out of its group to test them.
- **A MultiMesh is culled as one box.** Spread one over a zone and every shadow pass that touches it draws all of it
  (the camp: 133 M primitives from 2.6 M triangles). `Props.multimesh` now chunks into 16 m cells; keep big instanced
  sets chunked.
- **Shadow passes pay for fragment work.** Procedural alpha (the leaf cards) in four cascades was ~8 ms; triangles and
  vertices weren't the cost (welding the trunk, dropping its discard: no gain). Bake procedural cut-outs for shadow
  casters (`Flora.shadow_twin`, `foliage_mask_<kind>.png`); 8-bit masks, the pass is bandwidth bound.
- **Effects can cost a lot and show nothing.** SSIL at High (6-8 ms) and SSAO outdoors (~7 ms) were invisible:
  Godot's SSAO/SSIL only touch ambient/indirect light and these scenes are lit directly. Prove "looks the same" with
  `--fixed-fps 30` screenshots against two identical runs plus mean brightness; it can differ by zone (SSAO shows in
  the crypt). Shared passes hide costs: SSAO off alone measured ~0 while SSIL was still on.
- Meshy meshes are seam-split triangle soup (~2.5 vertices a triangle): Godot's LOD generator gives up on them, in
  the importer and at run time. LODs need welding/simplifying offline (Blender).
- Remaining GPU on the moor at High (quiet Mac ~16 ms; under load ~31): grass the biggest (fragment, not vertex),
  the terrain shader (~20% of it), MSAA, sun shadows. Unshadowed lamps, volumetric fog and glow measure ~0.
- The download is textures (141 MB) and mesh data (110 MB) plus the intro; `[importer_defaults]` was the 11-01 lever.
  Machine load varies within a night (11-02: a screen share until ~02:30 halved the GPU): compare pairs measured
  back to back, and re-measure the start commit if the load changes; noise is ~2-3% fps.

## Log

| Date | Type | Focus | Result | Kept | Next | Details |
|---|---|---|---|---|---|---|
| 2026-11-01 | size | Model textures as lossy WebP q0.9 instead of lossless (`[importer_defaults] texture`, + 5 Plague dyes) | Mac zip 725→302 MiB, Win 704→281 MiB; load 5.2→3.8 s; fps same; look within noise | yes | The camp's 152 M primitives; main-thread profiling | [runs/2026-11-01.md](runs/2026-11-01.md) |
| 2026-11-02 | big | Props.multimesh splits instances into 16 m cells (a MultiMesh is culled as one box: each lamp's shadow cube drew the whole forest) | camp High 133 M -> 15.6 M primitives, 9.4 -> 15.2 fps; other zones unchanged | yes | chunk every big instanced set | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | LODs for the oaks (ImporterMesh.generate_lods) | no LODs made: Meshy soup can't be simplified | no | weld + simplify offline | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Oak shadow twin: same mesh, no discard; then welded trunk + LODs | GPU 52.8 -> 52.7 / 52.5 ms | no | (the leaves were the cost) | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | big | Oak shadows from a shadows-only twin whose leaf cards read a baked mask (`foliage_mask_<kind>.png`, 256 px 8-bit) | moor High GPU 52.6 -> 46.4 ms, 13.5 -> 16.5 fps; camp 15.6 -> 18.3; fort +3% | yes | same for other procedural cut-outs in shadow passes | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Shadow twins for pines, ferns, bushes (+ bark shadow shader) | 47.6 vs 46.4 ms oaks only | no | | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Baked leaf mask in the main view too | 46.3 -> 45.3 ms (~2%) | no | not worth the look risk | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Grass vertex early-out for zero-scaled clumps | 46.4 -> 45.9 ms (noise) | no | grass is fragment-bound | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | big | SSIL only on Ultra (6-8 ms at High, invisible: fixed-step shots in 5 zones = run-to-run noise, brightness within 0.5%) | crypt 35 -> 50 fps, moor 16.5 -> 19.3, camp 18.3 -> 21.3, fight 14.1 -> 16.8; -150 MB VRAM | yes | check MSAA/grass the same way | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Sun soft-shadow filter High -> Medium/Low; shadow atlas 4096 -> 2048 | ~1 ms; ~2 ms but coarser | no | | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Arena crowd atlas: one frame per card instead of two | atlas 5.5 -> 3.7 s; arena 1% low 16 -> 28 fps, hitches 2.4 -> 0/min (partly the atlas finishing inside the KPI's settle) | yes | preload the kinds' glbs on threads | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | size | Measured only: pack contents, normal maps at WebP q0.8 / half size, monster texture caps | no change: Mac 410.8 MiB zip, Win 390.1 MiB zip | no | normal maps q0.8 (-35%) with committed .import files | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | big | SSAO outdoors only on Ultra (indoors kept from Medium: in the crypt it shows, 4.7% darker corners; outdoors screenshots = noise, brightness within 0.1-1%) | ~7 ms at High: moor 19.0 -> 23.0 fps, camp 21.6 -> 25.2, fort 24.5 -> 30.5, Medium moor 26.1 -> 33.1 (under load) | yes | MSAA and grass the same way | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | small | Crowd atlas: preload the kinds' glbs on threads | build_rig 35-200 ms per kind unchanged (it's the rig, not the file) | no | cache built rigs, or build behind the loading screen | [runs/2026-11-02.md](runs/2026-11-02.md) |
| 2026-11-02 | big | **Night total, like for like on a quiet Mac** (97521a2 vs the result, both 02:30-02:38) | camp 13.1 -> 46.4 fps, moor M/H/U 41.1/21.0/6.7 -> 57.8/37.6/11.3, fight 20.3 -> 33.6, fort 42.2 -> 54.0, arena 84.5 -> 99.1, crypt 93 -> 95 (vsync); download unchanged 410.8 MiB | yes | the runner's 00:31 "before" was under a screen share's load: compare like for like | [runs/2026-11-02.md](runs/2026-11-02.md) |
