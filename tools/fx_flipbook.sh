#!/usr/bin/env bash
# Packs simulated fire frames (tools/blender/fx/fire_flipbook.py) into the flipbook atlas the game's flames play
# (InfernalFx.FIRE_FLIPBOOK): 36 settled frames of 128x256 in a 6 x 6 grid, 768 x 1536 PNG. The sim's first
# frames still carry its start-up puff (a ball of fire floating loose), so packing starts at FIRST.
#   bash tools/fx_flipbook.sh <frames dir> [out.png] [first]
set -euo pipefail
SRC="$1"
OUT="${2:-assets/textures/fx/fire_flipbook.png}"
FIRST="${3:-26}"
mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -start_number "$FIRST" -i "$SRC/fire_%03d.png" -frames:v 1 \
	-vf "scale=128:256:flags=lanczos,tile=6x6" "$OUT"
echo "wrote $OUT"
