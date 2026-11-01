# Download size (a standing goal of the nightly performance run)

Blaine, 2026-11-01: "we want this to be much much smaller." Every night the performance run measures the exported
size per platform and records it here (newest last), whatever its main concept is; at least every other night the
concept itself should be a size reduction until the download is well under 200 MB.

| Date | Windows | Mac | Linux | .pck | Note |
|---|---|---|---|---|---|
| 2026-11-01 | 669 MiB | 736 MiB | 652 MiB | 618 MB (Mac) | baseline, staging-173ef29 (itch uploads) |
| 2026-11-01 | 704 -> 281 MiB zip (exe 762 -> 336) | 725 -> 302 MiB zip | 275 MiB zip (bin 318) | 682 -> 255 MiB (Mac) | nightly: lossy WebP q0.9 for model textures that imported lossless; local exports (zip -r), intro.ogv (81.5 MiB) included |

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
