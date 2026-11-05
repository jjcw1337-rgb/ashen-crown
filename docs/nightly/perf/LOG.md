# Performance job: attempts and results

The short log every nightly performance run reads first and adds to (`tools/nightly/perf_prompt.md`). One row per
attempt, kept or reverted, newest last. Keep the cells short: **Focus** what was tried (one line), **Result** the
numbers, **Kept** yes / no / partly, **Next** the follow-up it suggests, **Details** the run's full write-up.
**Type**: `big` (a structural change), `small` (a quick win), `size` (download size), `bench` (the runner's own
benchmark of the night's result, added by the script: the scoreboard; "blocked" = it was slower and didn't ship).

## Lessons (rewritten by each run: at most 8 bullets, the most useful first)

- **Cut-out shadow casters cost, triangles don't.** At High the sun's shadow is ~7 ms of the moor's 18; 58 monster
  bodies (2.2 M primitives) cost 0.33 ms of it, but anything with a `discard` (leaf cards, the see-through dither on
  every tall prop) runs its fragment shader in every cascade. Shadows-only twins fix it without changing the look:
  baked leaf masks (`Flora.shadow_twin`, 11-02; the harvest trees 11-05: -1.2 ms), opaque depth-only twins for the
  see-through props (`Props.shadow_twins`, 11-05: fort -1.2 ms, camp -1 ms). `--castlist` marks them `cut=true`.
- **Loads are main-thread file loads and fixed waits.** Load models on worker threads before the build needs them
  (`ZonePreload`: lists recorded with `--preload-record`; camp 5.8 -> 3.4 s) and don't wait wall-clock time where
  game time will do (the skill warm in fast-forward: 2.5 -> 0.8 s). A load's parts: `[LZ]`-style prints round
  `world.build`, the minimap capture (~0.3 s) and the warm.
- **Use the switches, and check they took.** `--hide`, `--noshadow`, `--envoff`, `--mmnoshadow N [--mmhide]`,
  `--nocast a,b|cut|all-mm`; in a zsh loop write `${=a}` (zsh doesn't split `$a`: 11-05's first hour measured
  nothing). If primitives and GPU time didn't move, the switch didn't take. Moor High breakdown (11-05): sun shadows
  7.2 ms, grass 5.7 (vertex 2.2, fragment 1.1, raster 2.4), MSAA 3.2, oaks 2.1, vfog 0.4, glow 0.3.
- **The download is the textures (jj: full size, q0.9, don't shrink them).** Mac zip 629 MiB (11-05): model textures
  244 MB, scenes 188 (6.1 M vertices; animations only 1.55 M keys), intro 85 (not a target), committed PNGs 79, audio
  11. Left: decimating the heaviest Meshy scenes offline; animation compression collides with the run-time hip pinning.
- **Measure like for like, on a quiet Mac.** The runner's 00:30 "before" can be taken under load (11-02, 11-05: camp
  30 fps vs 55 an hour later); compare your own back-to-back runs. Noise is ~2-3% fps; the camp's hour (DayNight) moves
  it only ~3%. Fixed-step shots (`--fixed-fps 30`) against two identical runs; PSNR over the 3D area, not zero.
- **Effects can cost a lot and show nothing, zone by zone.** SSIL at High and SSAO outdoors were invisible (11-02);
  SDFGI on Ultra is not (the moor 12% darker without it). Ultra stays full (jj).
- **Godot shader traps.** A `return` in `vertex()` skips the engine's own epilogue (garbage); a `discard` anywhere
  makes the shadow pass run the fragment shader. Meshy materials are double-sided: generated shaders say
  `cull_disabled`, and a stand-in material must match.
- **Meshy meshes can't be simplified at run time** (no LODs from the importer or `generate_lods`: UV islands lock the
  borders); LODs and lighter shadow proxies need offline Blender work.

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
| 2026-11-03 | small | Budgeted omni (fire) shadows as dual-paraboloid instead of cube maps (`Grade.pick_shadows`) | camp High 44.1 -> 46.4 fps, GPU 22.4 -> 21.3 ms, 12.2 -> 10.3 M primitives; fort +1.4%; shots = noise. First try set the mode every 0.4 s: a dip (fort 1% low 59 -> 30), fixed by setting it only when it differs | yes | | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | size | **Night total** (runner's 00:30 before vs bench.sh on the result, 02:10, best of 2) | Mac zip 541.5 -> 408.6 MiB (pck 496.4 -> 363.6), Win exe 576.7 -> 443.9; VRAM -160..-370 MB in every scene; loads: moor M/H/U 3.6/2.9/5.6 -> 2.0/2.6/3.1 s, fight 2.6 -> 1.9, crypt 3.2 -> 2.5; fps: Ultra 14.3 -> 15.7, boss 79.4 -> 82.9, arena 78.6 -> 81.7, others flat (camp 44.5, moor High 51.7, fight 46.8) | yes | offline decimation/LODs (scenes 143 MB; monster shadows) | [runs/2026-11-03.md](runs/2026-11-03.md) |
| 2026-11-03 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 45→46, moor Medium 88→89, moor 51→51, moor Ultra 14→16, fight 47→48, boss 79→80, arena 79→77, crypt 94→95; server tick p99 99→92 ms, camp 12M→10M tris, download 542→409 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
| 2026-11-05 | big | Skill warm's settle in fast-forward (time_scale 4, at most 66 ms of game time a frame) | warm 2.5-2.9 -> 0.9-1.0 s at High (Ultra 2.6-7.9 -> 1.3-2.5); archer first casts still no stutters | yes | | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | big | ZonePreload: the zone's recorded glbs on worker threads from the loading screen's first frame | load camp 5.8 -> 3.4 s, crypt 3.9 -> 2.8, fort 4.1 -> 3.7, moor 2.8 -> 2.5 | yes | lists for A2/A3, coast, isles | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Grass.scatter: species sums once per cell, int bucket keys (output hashes the same) | moor loop 563 -> ~455 ms | yes | scatter on a thread (the build still writes the grid after it) | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Harvest trees cast from the oaks' baked-mask shadow twin | moor High GPU 18.08 -> 16.87 ms, 52.5 -> 56.3 fps; shots = noise | yes | other cut-out casters | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | big | Props.shadow_twins: see-through props cast from an opaque depth-only twin | fort GPU 10.75 -> 9.58 ms (81.6 -> 89.7 fps), camp 17.5 -> 16.5 (56 -> 59), moor -0.2; shots = noise | yes | dais, lair props, ferns/bushes | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Twins for the code-built Mats.PROP_SHADER props too | mixed (camp 17.02 vs 17.25 without, worse than without them) | no | | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Warm draws the hidden 3D view at a quarter size | warm moor 938 -> 781 ms, fort 1760 -> 1650 | yes | | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Grass vertex early-out for zero-scaled clumps (again) | `return` version broken (skips Godot's epilogue); if/else 18.1 -> 17.9 ms | no | | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Minimap capture in 1-2 frames instead of 3 | 320 -> 264 ms | no | | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | size | Measured only: pack contents, duplicates, unused files, animation keys | Mac zip 628.6 MiB (was 408.6 on 11-03: jj's full textures +220); byte-identical duplicates 8 MB; animations 1.55 M keys vs 6.1 M vertices | no | offline decimation of the heaviest Meshy scenes | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | big | **Night total, like for like** (c1d6c2c fresh worktree vs the result, both on a quiet Mac 02:00-02:15) | load camp 7.6 -> 4.0 s, moor 5.0 -> 2.8, fight 4.9 -> 2.8, fort 6.2 -> 3.9, arena 5.4 -> 3.1, crypt 5.8 -> 3.1, Medium 4.5 -> 2.7, Ultra 6.3 -> 5.3; fps camp 56.5 -> 58.0, moor M/H/U 88.8/51.8/15.7 -> 90.5/54.0/16.5, fight 47.2 -> 49.6, fort 81.5 -> 86.7, arena 81.2 -> 81.6, crypt 95.6 -> 95.1; download 628.6 MiB unchanged | yes | the runner's 00:30 "before" was on a loaded Mac (camp 30 fps vs 55 at 00:45) | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | small | Measured only: the moor on Ultra, one switch at a time | 56.4 ms GPU: grass 25.3 (raster under MSAA 8x ~11, vertex ~6, fragment ~4, its shadow twins 4.3), sun shadows 18.3, SDFGI 12.8, MSAA 8x->4x 4.8, SSIL 4.0, vfog 2.7, SSR 1.8, SSAO 0.8 | no | Ultra grass at the same look (LOD1 sooner, fewer twin chunks) | [runs/2026-11-05.md](runs/2026-11-05.md) |
| 2026-11-05 | bench | Runner's KPI benchmark of the night's result (avg fps) | camp 30→58, moor Medium 56→90, moor 39→54, moor Ultra 15→16, fight 46→50, boss 80→85, arena 79→80, crypt 96→95; server tick p99 98→106 ms, camp 8M→8M tris, download 629→629 MB | shipped | | `docs/nightly/perf/metrics.jsonl` |
