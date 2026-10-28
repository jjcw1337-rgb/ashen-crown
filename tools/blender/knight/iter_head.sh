#!/bin/bash
# quick head iteration: build mesh, write parts.json, render face/face34/side, make a sheet
set -e
S=$1; TAG=$2; STEP=${3:-0.0015}
cd /home/claude/ashen_crown/tools/blender/knight
python3 - "$S" "$STEP" <<'PY'
import sys, json
from sdf import mesh, write_ply
import model
f = model.head_skin()
v, fa = mesh(f, [-0.11, -0.13, 1.53], [0.11, 0.13, 1.93], float(sys.argv[2]))
write_ply(sys.argv[1] + "/head.ply", v, fa)
json.dump({"meshes": [{"file": "head.ply", "mat": "skin"}], "eyes": [{"c": list(model.eye_c(s)), "r": model.EYE_R} for s in (1.0, -1.0)]}, open(sys.argv[1] + "/parts.json", "w"))
print("head", len(fa), "tris")
PY
cd $S && timeout 900 xvfb-run -a blender -b --python /home/claude/ashen_crown/tools/blender/knight/render.py -- $S $S/$TAG face,face34,side 2>&1 | grep -E "Error" | head -3
python3 -c "
from PIL import Image
ims=[Image.open('$S/${TAG}_'+f+'.png').convert('RGB').resize((450,500)) for f in ['face','face34','side']]
o=Image.new('RGB',(1350,500))
for i,im in enumerate(ims): o.paste(im,(i*450,0))
o.save('$S/${TAG}_sheet.png')"
