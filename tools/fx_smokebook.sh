#!/usr/bin/env bash
# Packs simulated smoke frames (tools/blender/fx/smoke_flipbook.py, smk_NNN.png, RGBA) into a flipbook atlas for
# DemonKitFx.smoke (its BOOKS table has each book's grid and frame count).
#   bash tools/fx_smokebook.sh <frames dir> <out.png> <cell WxH> <tile CxR>
#   e.g. bash tools/fx_smokebook.sh /tmp/sims/impact assets/textures/fx/demon/smoke_impact.png 256x256 8x6
set -euo pipefail
SRC="$1"; OUT="$2"; CELL="$3"; TILE="$4"
mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -i "$SRC/smk_%03d.png" -frames:v 1 \
	-vf "scale=${CELL/x/:}:flags=lanczos,format=rgba,tile=${TILE}" -pix_fmt rgba "$OUT"
echo "wrote $OUT"
