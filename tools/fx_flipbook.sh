#!/usr/bin/env bash
# Packs simulated fire frames (tools/blender/fx/fire_flipbook.py) into the flipbook atlas the game's flames play
# (InfernalFx.FIRE_FLIPBOOK): 64 frames of 128x256 in an 8 x 8 grid, 1024 x 2048 PNG.
#   bash tools/fx_flipbook.sh <frames dir> [out.png]
set -euo pipefail
SRC="$1"
OUT="${2:-assets/textures/fx/fire_flipbook.png}"
mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -start_number 0 -i "$SRC/fire_%03d.png" -frames:v 1 \
	-vf "scale=128:256:flags=lanczos,tile=8x8" "$OUT"
echo "wrote $OUT"
