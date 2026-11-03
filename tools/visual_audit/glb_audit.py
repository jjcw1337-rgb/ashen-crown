#!/usr/bin/env python3
"""Visual audit of every 3D model and texture in the project (no Godot or Blender needed).

    python3 tools/visual_audit/glb_audit.py [out_dir]      # default: build/visual_audit

Reads each .glb's own JSON and binary chunks and reports, per model: triangles (as drawn, counting
instanced meshes per node), vertices, surfaces, materials and the texture maps each one uses, every
embedded image (format, pixel size, bytes), whether the normal map is lossy JPEG, skin joints,
animations and their length, morph targets and extensions. Then every loose texture in assets/textures.
Writes models.csv, textures.csv and audit.json, and prints a summary. Used for the visual overhaul's
baseline (docs/visual/AUDIT.md) and to compare before/after.
"""
import csv
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMPONENTS = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def image_size(data: bytes):
	"""(width, height, format) from the first bytes of a PNG, JPEG or WebP file."""
	if data[:8] == b"\x89PNG\r\n\x1a\n":
		w, h = struct.unpack(">II", data[16:24])
		return w, h, "png"
	if data[:2] == b"\xff\xd8":
		i = 2
		while i < len(data) - 9:
			if data[i] != 0xFF:
				i += 1
				continue
			marker = data[i + 1]
			if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
				i += 2
				continue
			seg = struct.unpack(">H", data[i + 2:i + 4])[0]
			if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
				h, w = struct.unpack(">HH", data[i + 5:i + 9])
				return w, h, "jpeg"
			i += 2 + seg
		return 0, 0, "jpeg"
	if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
		kind = data[12:16]
		if kind == b"VP8X":
			w = 1 + int.from_bytes(data[24:27], "little")
			h = 1 + int.from_bytes(data[27:30], "little")
			return w, h, "webp"
		if kind == b"VP8 ":
			w, h = struct.unpack("<HH", data[26:30])
			return w & 0x3FFF, h & 0x3FFF, "webp"
		if kind == b"VP8L":
			b = data[21:25]
			w = 1 + (((b[1] & 0x3F) << 8) | b[0])
			h = 1 + (((b[3] & 0xF) << 10) | (b[2] << 2) | ((b[1] & 0xC0) >> 6))
			return w, h, "webp"
	return 0, 0, "?"


def read_glb(path: str):
	with open(path, "rb") as f:
		blob = f.read()
	magic, version, length = struct.unpack("<4sII", blob[:12])
	if magic != b"glTF":
		raise ValueError("not a glb")
	off = 12
	js, binc = None, b""
	while off < len(blob):
		clen, ctype = struct.unpack("<II", blob[off:off + 8])
		chunk = blob[off + 8:off + 8 + clen]
		if ctype == 0x4E4F534A:
			js = json.loads(chunk.decode("utf-8"))
		elif ctype == 0x004E4942:
			binc = chunk
		off += 8 + clen
	return js, binc


def accessor_max(js, binc, idx):
	acc = js["accessors"][idx]
	if "max" in acc:
		return max(acc["max"])
	return 0.0


def audit_glb(path: str):
	js, binc = read_glb(path)
	meshes = js.get("meshes", [])
	accessors = js.get("accessors", [])
	mesh_tris, mesh_verts, mesh_attrs = [], [], []
	surfaces = 0
	morphs = 0
	for m in meshes:
		t = v = 0
		attrs = set()
		for p in m.get("primitives", []):
			surfaces += 1
			mode = p.get("mode", 4)
			pos = accessors[p["attributes"]["POSITION"]]["count"] if "POSITION" in p["attributes"] else 0
			v += pos
			attrs |= set(p["attributes"].keys())
			n = accessors[p["indices"]]["count"] if "indices" in p else pos
			if mode == 4:
				t += n // 3
			elif mode in (5, 6):
				t += max(0, n - 2)
			morphs = max(morphs, len(p.get("targets", [])))
		mesh_tris.append(t)
		mesh_verts.append(v)
		mesh_attrs.append(attrs)
	# Triangles as drawn: every node that references a mesh draws it once.
	refs = [0] * len(meshes)
	for nd in js.get("nodes", []):
		if "mesh" in nd:
			refs[nd["mesh"]] += 1
	drawn_tris = sum(t * max(1, r) if r else 0 for t, r in zip(mesh_tris, refs))
	if drawn_tris == 0:
		drawn_tris = sum(mesh_tris)
	attrs_all = set().union(*mesh_attrs) if mesh_attrs else set()

	textures = js.get("textures", [])
	images = js.get("images", [])
	views = js.get("bufferViews", [])
	img_info = []
	for im in images:
		data = b""
		if "bufferView" in im:
			bv = views[im["bufferView"]]
			start = bv.get("byteOffset", 0)
			data = binc[start:start + bv["byteLength"]]
		w, h, fmt = image_size(data[:4096]) if data else (0, 0, "uri")
		img_info.append({"w": w, "h": h, "fmt": fmt, "bytes": len(data), "name": im.get("name", "")})

	def tex_img(ref):
		if ref is None:
			return None
		ti = ref.get("index")
		if ti is None or ti >= len(textures):
			return None
		src = textures[ti].get("source")
		if src is None:
			ext = textures[ti].get("extensions", {})
			for e in ext.values():
				if "source" in e:
					src = e["source"]
		return src

	mats = []
	roles = {}
	for mat in js.get("materials", []):
		pbr = mat.get("pbrMetallicRoughness", {})
		slots = {
			"albedo": tex_img(pbr.get("baseColorTexture")),
			"orm": tex_img(pbr.get("metallicRoughnessTexture")),
			"normal": tex_img(mat.get("normalTexture")),
			"ao": tex_img(mat.get("occlusionTexture")),
			"emission": tex_img(mat.get("emissiveTexture")),
		}
		for role, src in slots.items():
			if src is not None:
				roles.setdefault(src, set()).add(role)
		mats.append({
			"name": mat.get("name", ""),
			"maps": [k for k, s in slots.items() if s is not None],
			"alpha": mat.get("alphaMode", "OPAQUE"),
			"double": bool(mat.get("doubleSided", False)),
			"metal": pbr.get("metallicFactor", 1.0),
			"rough": pbr.get("roughnessFactor", 1.0),
			"ext": sorted(mat.get("extensions", {}).keys()),
		})
	for i, info in enumerate(img_info):
		info["roles"] = sorted(roles.get(i, []))

	skins = js.get("skins", [])
	joints = max((len(s.get("joints", [])) for s in skins), default=0)
	anims = []
	for a in js.get("animations", []):
		dur = 0.0
		for s in a.get("samplers", []):
			try:
				dur = max(dur, accessor_max(js, binc, s["input"]))
			except (KeyError, IndexError):
				pass
		anims.append({"name": a.get("name", ""), "secs": round(dur, 2)})

	max_tex = max((max(i["w"], i["h"]) for i in img_info), default=0)
	normal_imgs = [i for i in img_info if "normal" in i["roles"]]
	return {
		"tris": drawn_tris,
		"tris_unique": sum(mesh_tris),
		"verts": sum(mesh_verts),
		"meshes": len(meshes),
		"surfaces": surfaces,
		"materials": len(mats),
		"mat_list": mats,
		"images": img_info,
		"img_count": len(img_info),
		"img_bytes": sum(i["bytes"] for i in img_info),
		"max_tex": max_tex,
		"has_normal": bool(normal_imgs),
		"normal_jpeg": any(i["fmt"] == "jpeg" for i in normal_imgs),
		"has_orm": any("orm" in m["maps"] for m in mats),
		"has_emission": any("emission" in m["maps"] for m in mats),
		"albedo_only": bool(mats) and all(set(m["maps"]) <= {"albedo"} for m in mats),
		"untextured": bool(mats) and all(not m["maps"] for m in mats),
		"tangents": "TANGENT" in attrs_all,
		"uv2": "TEXCOORD_1" in attrs_all,
		"vcolor": "COLOR_0" in attrs_all,
		"joints": joints,
		"anims": anims,
		"anim_count": len(anims),
		"morphs": morphs,
		"extensions": sorted(js.get("extensionsUsed", [])),
		"bytes": os.path.getsize(path),
	}


def category(rel: str) -> str:
	parts = rel.split("/")
	if len(parts) >= 4:
		return parts[2]
	name = parts[-1]
	if name in ("knight_meshy.glb", "knight_armored.glb", "knight_mocap.glb", "archer_ranger.glb",
				"wraith_mocap.glb", "demon_mocap.glb", "gnome_warlock.glb", "plague_doctor.glb"):
		return "heroes"
	if name in ("grubb_mutant.glb",):
		return "bosses"
	return "misc"


def main():
	out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "visual_audit")
	os.makedirs(out_dir, exist_ok=True)
	models = []
	for dp, _, files in os.walk(os.path.join(ROOT, "assets")):
		for fn in sorted(files):
			if fn.lower().endswith(".glb"):
				p = os.path.join(dp, fn)
				rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
				try:
					r = audit_glb(p)
				except Exception as e:  # noqa: BLE001 - report and go on
					r = {"error": str(e), "bytes": os.path.getsize(p)}
				r["path"] = rel
				r["category"] = category(rel)
				models.append(r)
	models.sort(key=lambda r: (r["category"], r["path"]))

	textures = []
	for dp, _, files in os.walk(os.path.join(ROOT, "assets", "textures")):
		for fn in sorted(files):
			if fn.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
				p = os.path.join(dp, fn)
				with open(p, "rb") as f:
					head = f.read(65536)
				w, h, fmt = image_size(head)
				imp = p + ".import"
				comp = ""
				if os.path.exists(imp):
					with open(imp, encoding="utf-8", errors="replace") as f:
						for line in f:
							if line.startswith("compress/mode="):
								comp = line.strip().split("=", 1)[1]
				textures.append({
					"path": os.path.relpath(p, ROOT).replace(os.sep, "/"),
					"w": w, "h": h, "fmt": fmt, "bytes": os.path.getsize(p), "import_compress": comp,
				})

	with open(os.path.join(out_dir, "audit.json"), "w") as f:
		json.dump({"models": models, "textures": textures}, f, indent=1)
	cols = ["category", "path", "tris", "verts", "meshes", "surfaces", "materials", "img_count", "max_tex",
			"img_bytes", "has_normal", "normal_jpeg", "has_orm", "has_emission", "albedo_only", "untextured",
			"tangents", "uv2", "vcolor", "joints", "anim_count", "morphs", "bytes"]
	with open(os.path.join(out_dir, "models.csv"), "w", newline="") as f:
		w = csv.writer(f)
		w.writerow(cols)
		for r in models:
			w.writerow([r.get(c, "") for c in cols])
	with open(os.path.join(out_dir, "textures.csv"), "w", newline="") as f:
		w = csv.writer(f)
		w.writerow(["path", "w", "h", "fmt", "bytes", "import_compress"])
		for t in textures:
			w.writerow([t["path"], t["w"], t["h"], t["fmt"], t["bytes"], t["import_compress"]])

	ok = [m for m in models if "error" not in m]
	print(f"{len(models)} models, {sum(m['tris'] for m in ok):,} triangles in all, "
		  f"{sum(m['bytes'] for m in models) / 1048576:.0f} MB")
	print(f"  normal maps stored as JPEG: {sum(1 for m in ok if m['normal_jpeg'])}"
		  f"  no normal map: {sum(1 for m in ok if not m['has_normal'])}"
		  f"  albedo only: {sum(1 for m in ok if m['albedo_only'])}"
		  f"  untextured: {sum(1 for m in ok if m['untextured'])}")
	print(f"{len(textures)} loose textures, {sum(t['bytes'] for t in textures) / 1048576:.0f} MB")
	for m in models:
		if "error" in m:
			print("  ERROR", m["path"], m["error"])
	print("wrote", out_dir)


if __name__ == "__main__":
	main()
