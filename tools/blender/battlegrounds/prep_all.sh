#!/bin/bash
# Prepares every Meshy prop of the Hollow Crypt into assets/models/crypt/ (rebake_crypt_prop.py: clean UVs, baked
# textures). The raw Meshy downloads are read from $1 (default ~/fable_bg/meshy). Re-run a single prop by name:
#   bash tools/blender/battlegrounds/prep_all.sh [rawdir] [name]
set -e
RAW=${1:-$HOME/fable_bg/meshy}
ONLY=${2:-}
OUT=assets/models/crypt
S=tools/blender/battlegrounds/rebake_crypt_prop.py
mkdir -p "$OUT"
run() {  # name  args...
	local name=$1; shift
	if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then return; fi
	echo "=== $name"
	blender -b --python "$S" -- "$RAW/$name.glb" "$OUT/$1.glb" "$2" "$3" "${@:4}" 2>&1 | grep -E "PROP|EXPORTED|BAKED|Error|error" || true
}
# name          out           size    tris  options
run sarc        sarcophagus   x=2.3   9000  --tex 1024
run pillar      pillar        h=4.0   6000  --tex 1024 --xy 0.6
run arch        archway       h=3.6   9000  --tex 1024
run bones       bones         w=1.3   5000  --tex 1024 --voxel 0.004
run sconce      sconce        h=0.55  3000  --tex 512 --keep y,-0.16
run brazier     brazier       w=1.2   5000  --tex 1024
run niche       niche         x=1.0   6000  --tex 1024 --tint 0.62,0.64,0.62
run chest2      chest         x=1.0   9000  --tex 1024 --solid 0.02
