#!/usr/bin/env python3
"""Contact sheets of the model sheets (tools/visual_audit/model_sheet.py) with each model's stats from glb_audit.py.

    python3 tools/visual_audit/contact_sheet.py sheets_dir audit.json out_dir [--per 8]

One PNG per category (heroes, monsters, npc, camp, ...): each row is a model's three views with a caption line
(triangles, texture size, maps, joints, animations).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sheets, audit_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
per = int(sys.argv[sys.argv.index("--per") + 1]) if "--per" in sys.argv else 8
os.makedirs(out, exist_ok=True)
audit = {m["path"]: m for m in json.load(open(audit_path))["models"]}
try:
	font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
except OSError:
	font = ImageFont.load_default()
groups = {}
for f in sorted(os.listdir(sheets)):
	if not f.endswith(".png") or f.startswith("_"):
		continue
	parent, name = f[:-4].split("__", 1)
	rel = "assets/models/%s%s.glb" % ("" if parent == "models" else parent + "/", name)
	cat = audit.get(rel, {}).get("category", parent)
	groups.setdefault(cat, []).append((rel, os.path.join(sheets, f)))
for cat, items in groups.items():
	for page in range(0, len(items), per):
		chunk = items[page:page + per]
		ims = [Image.open(p).convert("RGB") for _, p in chunk]
		w = max(i.width for i in ims)
		h = ims[0].height
		cap = 24
		sheet = Image.new("RGB", (w, (h + cap) * len(ims)), (24, 24, 26))
		d = ImageDraw.Draw(sheet)
		for k, ((rel, _), im) in enumerate(zip(chunk, ims)):
			y = k * (h + cap)
			m = audit.get(rel, {})
			maps = "+".join(sorted({x for mm in m.get("mat_list", []) for x in mm["maps"]}))
			txt = "%s   %s tris   tex %s   %s   joints %s   anims %s" % (rel[14:], format(m.get("tris", 0), ","), m.get("max_tex", "?"),
				maps or "no maps", m.get("joints", 0), m.get("anim_count", 0))
			d.text((8, y + 4), txt, fill=(235, 220, 160), font=font)
			sheet.paste(im, (0, y + cap))
		fn = os.path.join(out, "%s_%d.png" % (cat, page // per + 1))
		sheet.save(fn)
		print(fn, len(chunk))
