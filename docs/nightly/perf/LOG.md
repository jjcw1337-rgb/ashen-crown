# Performance job: attempts and results

The short log every nightly performance run reads first and adds to (`tools/nightly/perf_prompt.md`). One row per
attempt, kept or reverted, newest last. Keep the cells short: **Focus** what was tried (one line), **Result** the
numbers, **Kept** yes / no / partly, **Next** the follow-up it suggests, **Details** the run's full write-up.
**Type**: `big` (a structural change), `small` (a quick win), `size` (download size), `bench` (the runner's own
benchmark of the night's result, added by the script: the scoreboard; "blocked" = it was slower and didn't ship).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **The download is the importer's defaults.** The glb-extracted textures (`.import` git-ignored, made fresh in CI)
  take `[importer_defaults] texture`: lossless -> WebP q0.9 (11-01, -420 MB), then a 1024 px cap and q0.75 (11-03,
  -133 MiB) showed nowhere: a hero is ~100 px tall in play, ~300 px on the class picker. To re-import, re-extract
  (`git clean -fX assets/models && godot --headless --import`): deleting only the `.import` files loses the mipmaps.
- **Measure the GPU, not TIME_PROCESS.** Every scene on the Mac is GPU-bound (scripts 1.5-3.5 ms, GPU 18-22 ms at
  High). `cpu_process_peak_ms` includes the wait for the GPU. The server KPI's 100 ms "hitches" are macOS throttling
  a background headless process between ticks (its work is 1-3 ms a tick), not game work.
- **Switch things off one at a time** (`--hide`, `--noshadow`, `--envoff`, `--mmnoshadow`, `--nocast`, `--castlist`,
  `--census`, `--grassshadow`), then **check the switch's GPU time moved before trusting its screenshots**: 11-03's
  `--envoff sdfgi` didn't stick in `--fixed-fps` runs and made an invisible-looking "SDFGI off" that was really 12%
  darker. `Grade.pick_shadows` re-enables shadows every 0.4 s.
- **Effects can cost a lot and show nothing, zone by zone.** SSIL at High and SSAO outdoors were invisible (direct
  light dominates); SDFGI on Ultra is NOT (the moor 12% darker without it). Prove it with fixed-step shots vs two
  identical runs plus mean brightness over the 3D area (exclude UI and moving monsters).
- **Shadow passes**: a MultiMesh is culled as one box (keep big instanced sets chunked, `Props.multimesh`); cut-out
  casters pay per pixel (bake masks, `Flora.shadow_twin`); on Ultra the grass's shadow was 14 ms and LOD1 shadows-only
  twins halved it. Sun shadows are ~7 ms at High in camp and moor, spread over many casters (monster bodies, props).
- **Meshy meshes can't be simplified at run time**: neither the importer nor `ImporterMesh.generate_lods` makes LODs,
  even for the well-welded monster bodies (thousands of UV islands lock the borders). LODs and lighter shadow proxies
  need offline Blender work: that is where the next big GPU and size wins are (scenes are 143 MB of the pack).
- **Grass at High (~5.6 ms on the moor)**: 2.3 ms vertex/primitive work, ~1 ms fragment shading, the rest raster
  under MSAA. Culling zero-scaled clumps per chunk only reaches ~11% (20 m chunks straddle the 5 m LOD band).
- **Load time is first loads**: a monster model's first load is 23-34 ms on the main thread; loading the zone's
  models on worker threads during the minimap capture took the moor's arrival 2.25 -> 1.86 s. Compare against your
  own previous commit, and measured back to back: noise is ~2-3% fps.

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
| 2026-11-02 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 9→47, moor Medium 23→57, moor 13→38, moor Ultra 5→11, fight 12→34, boss 20→54, arena 30→99, crypt 35→96; server tick p99 113→105 ms, camp 144M→15M tris, download 411→411 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
| 2026-11-03 | size | Model textures capped at 1024 px (`[importer_defaults]` `process/size_limit`), the Ranger/Plague dyes too (+ mipmaps the coats lacked) | Mac zip 541.5 -> 486.9 MiB; camp VRAM 1513 -> 1261 MB, load 3.4 -> 2.8 s; shots within noise in title, class picker, 3 zones | yes | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | size | Model textures WebP q0.9 -> q0.75 (q0.8 and q0.7 measured too) | generated textures 161 -> 85 MB; Mac zip 486.9 -> 408.6 MiB, Win exe 576.7 -> 443.9 MiB; invisible at 2-3x | yes | the scenes (143 MB): offline decimation | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | big | Ultra grass shadows from shadows-only twins on the LOD1 clump | moor Ultra 13.9 -> 15.6 fps, GPU 70.7 -> 62.7 ms, 33.6 -> 18.7 M primitives; 40.6 dB vs 39.9 noise | yes | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | small | Grass twins: shorter shadow range (36 m) / opaque (no alpha test) | -2 ms but chunk shadows pop / -1 ms, square seed-head shadows | no | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | small | Load the zone's monster models on worker threads during the minimap capture | moor arrival 2.25 -> 1.86 s (3.0 at the night's start), Medium 3.6 -> 2.1, Ultra 5.6 -> 2.9, fort 2.6 -> 2.0 | yes | grass scatter on a thread (0.54 s) | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | big | SDFGI off outdoors on Ultra (13.5 ms of 62) | moor 12% darker: it shows | no | (first look test was void: the switch didn't stick) | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | small | Grass: hide zero-scaled clumps per chunk (sorted instances + visible_instance_count) | only 11% hideable, ~0.25 ms | no | smaller chunks first | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | size | zstd level 19 for imported scenes | 143.5 -> 138.9 MB (-3%), global setting also hits the run-time pipeline cache | no | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | small | Runtime LODs for monster bodies (ImporterMesh.generate_lods) | no LODs made (UV islands) | no | offline Blender LODs / shadow proxies | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | small | Ultra: no grass shadow twins for moss and sparse verge grass | moor Ultra GPU 62.5 -> 61.6 ms, 18.6 -> 17.1 M primitives, 15.7 -> 15.85 fps; shots = noise | yes | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | size | **Night total** (runner's 00:30 before vs bench.sh on the result, 02:10, best of 2) | Mac zip 541.5 -> 408.6 MiB (pck 496.4 -> 363.6), Win exe 576.7 -> 443.9; VRAM -160..-370 MB in every scene; loads: moor M/H/U 3.6/2.9/5.6 -> 2.0/2.6/3.1 s, fight 2.6 -> 1.9, crypt 3.2 -> 2.5; fps: Ultra 14.3 -> 15.7, boss 79.4 -> 82.9, arena 78.6 -> 81.7, others flat (camp 44.5, moor High 51.7, fight 46.8) | yes | offline decimation/LODs (scenes 143 MB; monster shadows) | [runs/2026-11-03.md](runs/2026-11-03.md) |
