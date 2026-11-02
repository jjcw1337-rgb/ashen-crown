#!/usr/bin/env python3
"""UV and texture-gutter report for every textured .glb (pure Python: numpy + Pillow).

    python3 tools/visual_audit/uv_report.py [out.csv] [glb ...]     # default: every glb under assets/models

Meshy's decimated models carry thousands of tiny UV islands with unpainted gutters between them (often black).
Mipmaps average those gutters into the colours at a distance, so a model drawn small (the game camera) turns darker,
speckled and, through the roughness map, glossy at the seams. Per model this prints:
  coverage  share of the texture covered by UV triangles
  islands   UV islands (connected triangles in UV space)
  gutter    mean colour of the uncovered texels in the colour map (0-255)
  dark@N    how much darker the colour map reads at mip size N (sampled inside the islands) than at full size,
            as a percentage of its luminance: the darkening players actually see at the game's distance
  rough@N   the same for the roughness channel (negative = glossier at a distance)
Used by docs/visual/AUDIT.md and by tools/visual_audit/pad_textures.py (which fixes it).
"""
import csv
import io
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_audit import ROOT, read_glb  # noqa: E402

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def accessor(js, binc, idx):
	acc = js["accessors"][idx]
	bv = js["bufferViews"][acc["bufferView"]]
	dt = np.dtype(CT[acc["componentType"]])
	n = NC[acc["type"]]
	count = acc["count"]
	off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
	stride = bv.get("byteStride", 0) or dt.itemsize * n
	raw = np.frombuffer(binc, dtype=np.uint8, count=stride * (count - 1) + dt.itemsize * n, offset=off)
	if stride == dt.itemsize * n:
		arr = raw.view(dt).reshape(count, n)
	else:
		arr = np.lib.stride_tricks.as_strided(raw, shape=(count, dt.itemsize * n), strides=(stride, 1)).copy().view(dt).reshape(count, n)
	arr = arr.astype(np.float64)
	if acc.get("normalized"):
		arr /= float(np.iinfo(dt).max)
	return arr


def uv_triangles(js, binc, uv_set=0):
	"""All triangles of every primitive that uses material 0's textures, as UV coordinates (N, 3, 2)."""
	tris = []
	for m in js.get("meshes", []):
		for p in m.get("primitives", []):
			key = "TEXCOORD_%d" % uv_set
			if key not in p["attributes"] or p.get("mode", 4) != 4:
				continue
			uv = accessor(js, binc, p["attributes"][key])
			if "indices" in p:
				ind = accessor(js, binc, p["indices"]).astype(np.int64).reshape(-1)
			else:
				ind = np.arange(uv.shape[0])
			ind = ind[: (ind.size // 3) * 3].reshape(-1, 3)
			tris.append(uv[ind])
	return np.concatenate(tris) if tris else np.zeros((0, 3, 2))


def coverage_mask(tris, size):
	img = Image.new("L", (size, size), 0)
	d = ImageDraw.Draw(img)
	t = tris * size
	for tri in t:
		d.polygon([(tri[0][0], tri[0][1]), (tri[1][0], tri[1][1]), (tri[2][0], tri[2][1])], fill=255, outline=255)
	return np.array(img) > 0


def count_islands(js, binc):
	"""Islands = connected components of triangles sharing a UV-space vertex position."""
	total = 0
	for m in js.get("meshes", []):
		for p in m.get("primitives", []):
			if "TEXCOORD_0" not in p["attributes"]:
				continue
			uv = accessor(js, binc, p["attributes"]["TEXCOORD_0"])
			ind = accessor(js, binc, p["indices"]).astype(np.int64).reshape(-1) if "indices" in p else np.arange(uv.shape[0])
			ind = ind[: (ind.size // 3) * 3].reshape(-1, 3)
			# weld vertices with the same UV (to 1e-5)
			q = np.round(uv * 1e5).astype(np.int64)
			_, inv = np.unique(q[:, 0] * 10_000_019 + q[:, 1], return_inverse=True)
			parent = np.arange(inv.max() + 1)

			def find(a):
				while parent[a] != a:
					parent[a] = parent[parent[a]]
					a = parent[a]
				return a
			for t in inv[ind]:
				ra, rb, rc = find(t[0]), find(t[1]), find(t[2])
				parent[rb] = ra
				parent[rc] = ra
			roots = {find(v) for v in np.unique(inv[ind])}
			total += len(roots)
	return total


def image_of(js, binc, tex_ref):
	if tex_ref is None:
		return None
	t = js["textures"][tex_ref["index"]]
	src = t.get("source")
	im = js["images"][src]
	bv = js["bufferViews"][im["bufferView"]]
	data = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
	return Image.open(io.BytesIO(data))


def mip_shift(arr, mask, size):
	"""Mean of the channel inside the islands at full size minus the mean at a box-filtered `size` (sampled inside)."""
	h = arr.shape[0]
	f = h // size
	if f < 2:
		return 0.0
	small = arr[: size * f, : size * f].reshape(size, f, size, f).mean(axis=(1, 3))
	msmall = mask[: size * f, : size * f].reshape(size, f, size, f).mean(axis=(1, 3)) > 0.5
	full = arr[mask].mean()
	return float(small[msmall].mean() - full)


def report(path):
	js, binc = read_glb(path)
	mats = js.get("materials", [])
	if not mats:
		return None
	pbr = mats[0].get("pbrMetallicRoughness", {})
	col = image_of(js, binc, pbr.get("baseColorTexture"))
	if col is None:
		return None
	w, h = col.size
	size = min(w, 1024)
	tris = uv_triangles(js, binc)
	if tris.size == 0:
		return None
	mask = coverage_mask(tris % 1.0 if (tris.max() > 1.001 or tris.min() < -0.001) else tris, size)
	colf = np.asarray(col.convert("RGB").resize((size, size), Image.BOX), dtype=np.float64) / 255.0
	lum = colf @ np.array([0.2126, 0.7152, 0.0722])
	gutter = (colf[~mask].mean(axis=0) * 255).round().astype(int).tolist() if (~mask).any() else [0, 0, 0]
	full_l = lum[mask].mean()
	out = {"path": os.path.relpath(path, ROOT).replace(os.sep, "/"), "tex": w, "coverage": round(float(mask.mean()) * 100, 1),
		   "islands": count_islands(js, binc), "gutter": gutter, "albedo_lum": round(float(full_l), 3),
		   "albedo_p90": round(float(np.percentile(lum[mask], 90)), 3)}
	nrm = image_of(js, binc, mats[0].get("normalTexture"))
	if nrm is not None:
		nf = np.asarray(nrm.convert("RGB").resize((size, size), Image.BOX), dtype=np.float64) / 255.0 * 2.0 - 1.0
		xy = np.sqrt(nf[:, :, 0] ** 2 + nf[:, :, 1] ** 2)
		# how far the normals lean from straight out, on average (0 = a flat map that adds nothing)
		out["normal_tilt"] = round(float(np.degrees(np.arctan2(xy[mask], np.clip(nf[:, :, 2][mask], 1e-3, None))).mean()), 1)
	for s in (256, 128, 64):
		out["dark@%d" % s] = round(-mip_shift(lum, mask, s) / max(full_l, 1e-4) * 100, 1)
	orm = image_of(js, binc, pbr.get("metallicRoughnessTexture"))
	if orm is not None:
		ormf = np.asarray(orm.convert("RGB").resize((size, size), Image.BOX), dtype=np.float64) / 255.0
		rough = ormf[:, :, 1]
		out["rough_full"] = round(float(rough[mask].mean()), 3)
		out["rough@128"] = round(mip_shift(rough, mask, 128), 3)
		out["rough_gutter"] = round(float(rough[~mask].mean()), 3) if (~mask).any() else 0.0
	return out


def main():
	args = sys.argv[1:]
	out_csv = args.pop(0) if args and args[0].endswith(".csv") else None
	files = args
	if not files:
		for dp, _, fs in os.walk(os.path.join(ROOT, "assets", "models")):
			for f in sorted(fs):
				if f.endswith(".glb"):
					files.append(os.path.join(dp, f))
	rows = []
	for f in sorted(files):
		try:
			r = report(f)
		except Exception as e:  # noqa: BLE001
			print("fail", f, e)
			continue
		if r:
			rows.append(r)
			print("%-44s tex %4d  cover %5.1f%%  islands %6d  albedo %.3f (p90 %.3f)  normal tilt %s deg  rough %s" % (
				r["path"][14:], r["tex"], r["coverage"], r["islands"], r["albedo_lum"], r["albedo_p90"], r.get("normal_tilt", "-"),
				r.get("rough_full", "-")))
	if out_csv:
		keys = ["path", "tex", "coverage", "islands", "gutter", "albedo_lum", "albedo_p90", "normal_tilt", "dark@256", "dark@128", "dark@64", "rough_full", "rough@128", "rough_gutter"]
		with open(out_csv, "w", newline="") as fh:
			wr = csv.writer(fh)
			wr.writerow(keys)
			for r in rows:
				wr.writerow([r.get(k, "") for k in keys])


if __name__ == "__main__":
	main()
