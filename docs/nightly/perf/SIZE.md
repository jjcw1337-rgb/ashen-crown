# Download size (a standing goal of the nightly performance run)

Blaine, 2026-11-01: "we want this to be much much smaller." Every night the performance run measures the exported
size per platform and records it here (newest last), whatever its main concept is; at least every other night the
concept itself should be a size reduction until the download is well under 200 MB.

| Date | Windows | Mac | Linux | .pck | Note |
|---|---|---|---|---|---|
| 2026-11-01 | 669 MiB | 736 MiB | 652 MiB | 618 MB (Mac) | baseline, staging-173ef29 (itch uploads) |
| 2026-11-01 | 704 -> 281 MiB zip (exe 762 -> 336) | 725 -> 302 MiB zip | 275 MiB zip (bin 318) | 682 -> 255 MiB (Mac) | nightly: lossy WebP q0.9 for model textures that imported lossless; local exports (zip -r), intro.ogv (81.5 MiB) included |
| 2026-11-02 | 390.1 MiB zip (exe 445.3) | 410.8 MiB zip (fresh import) | | 365.0 MiB (Mac) | nightly: no size change tonight (perf concepts); grew 302 -> 411 MiB since 11-01 from the day's new content (dinosaurs, trolls, crypt floors and bosses, NPCs) |
| 2026-11-03 | 520.7 -> 387.8 MiB zip (exe 576.7 -> 443.9) | 541.5 -> 408.6 MiB zip | | 496.4 -> 363.6 MiB (Mac) | nightly: model textures capped at 1024 px and WebP q0.75 (`[importer_defaults]`), dyes capped; it had grown 411 -> 541 since 11-02 |
| 2026-11-05 | 607.8 MiB zip (exe 664.4) | 628.6 MiB zip (fresh import; unchanged tonight) | | 584.1 MiB (Mac) | nightly: no size change (load-time and shadow concepts). It grew 408.6 -> 628.6 since 11-03: jj undid the 1024 px cap and q0.75 the same day (full textures on every preset), plus the living camp |

Where it goes (2026-11-01): assets 420 MB on disk: models 346 MB (the biggest: knight_statue, knight_mocap,
grubb_mutant, plague_doctor, knight_armored, archer_ranger, wraith_mocap, title/gate, gnome_warlock, demon_mocap,
fort/gate: 9-12 MB each, mostly embedded textures), textures 30 MB, audio 24 MB, intro.ogv 21 MB; the imported
cache is 570 MB. Things to check: textures embedded in the .glb files (resolution, format, duplicates), whether
both S3TC and ETC2/ASTC copies of every texture end up in each platform's pack, mesh density (decimation, LODs),
unused assets still exported, audio format and sample rates, the intro video's bitrate, the export's own
compression.

NOT A TARGET: assets/intro.ogv (Blaine's trailer, 1080p, 85 MB) is deliberately full quality ("just put up good
shit"); never recompress or shrink it. Count it separately when reporting the download size.

After 2026-11-01 (pack 255 MiB, Mac): intro.ogv 81.5 MiB (not a target), imported scenes (meshes + their auto LODs)
83 MB, textures 109 MB (glb-extracted, now lossy, ~64 MB; committed lossless UI/grass PNGs and VRAM textures ~45 MB),
audio 24 MB. Without the intro the Mac download is ~220 MiB. Next: the scenes (mesh compression, auto-LOD
generation, knight_mocap.glb and knight_armored.glb carry the same three textures twice, byte for byte), the Mac pack carrying
both S3TC and ETC2 copies of every VRAM texture, textures larger than they are ever seen on screen.

2026-11-02 (pack 365 MiB, Mac): glb-extracted textures 141 MB (normal maps 47.8 MB of the 136 MB under assets/models,
metal/rough 3.7, albedo 84.7), imported scenes 110 MB (compressed RSCC; almost all mesh vertex data: no auto-LODs, as
the importer can't simplify Meshy's seam-split meshes; no shadow meshes; vertex compression already on), intro.ogv 85 MB
(not a target), PNGs 35 MB, audio 8 MB, scripts 2 MB. No VRAM-compressed textures remain (no S3TC/ETC2 duplicates).
The Mac binary is universal (x86_64 + arm64), 154 MB raw (~45 MB zipped): arm64-only would be a product decision.
Measured, not yet done: 2048 normal maps as WebP q0.8 are 35% smaller (35-38 dB vs 39-42 at q0.9), at half size 65%
smaller; most monster textures are already 1024 (capping the 8 that are 2048 saves ~10 MB). Levers for a size night:
the normal maps (committed `.import` files for the extracted textures, which are git-ignored now), decimating the
heaviest Meshy bodies offline (with real LODs), the knight bodies' three identical textures.

2026-11-03 (pack 363.6 MiB, Mac, after the night): imported scenes 143.5 MB (5.4 M vertices, all with tangents, 2.5 M
skinned; `godot --headless --path . -s tools/scene_weight.gd -- out.txt` lists every glb's vertices, triangles,
attributes and animation keys), intro.ogv 85 MB (not a target), model textures 85 MB (1024 px, q0.75), committed
textures 55 MB (fx flipbooks lossless by design, the grass atlas, UI, talents), audio 8 MB. Without the intro the Mac
download is ~325 MiB. Measured, not done: zstd level 19 for the scenes -3% (global setting; not worth it). The scenes
are the next lever: Godot can't simplify the Meshy meshes (no LODs at import or with `ImporterMesh.generate_lods`),
so decimate offline in Blender: the densest static props (stash chest 54 k triangles / 91 k vertices, waypoint dais
44 k / 93 k, title gate 40 k / 85 k, sloop 39 k / 70 k, camp forge and alchemy 24 k / 50 k) and the bodies (player
classes 60-95 k vertices, monsters 20-60 k).

2026-11-05 (pack 584.1 MiB, Mac; parsed from the .pck's own directory): model textures (glb-extracted, full size,
WebP q0.9 by jj's rule) 243.5 MB, imported scenes 188.4 MB (6.1 M vertices; the 7 camp traders and 3 guards are 4-6 MB
each, mostly 30-52 animation clips: 1.55 M keys in all), intro.ogv 85.4 MB (not a target), committed PNG textures
79.4 MB, audio 11.1 MB, scripts 2.8 MB. Byte-identical duplicates across glbs: only 8 MB (the knight bodies' three
textures, the fractured props' `_pieces` copies). Files nothing references by path are few and mostly fallbacks
(the painted grass clumps, the retired Phoenix textures: ~10 MB). Animation compression would save perhaps 15-20 MB
but `ForestCamp._pin_root` and `CampGuard._unroot` edit the hips' tracks at run time, which compressed tracks refuse
(pin them at import first). The remaining lever inside the rules is offline decimation of the densest Meshy scenes
(stash chest 153 k vertices, the knight bodies and the statue 92-95 k, waypoint dais 93 k, title gate 85 k).
