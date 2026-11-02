#!/usr/bin/env python3
"""Surface-detail normal maps for Meshy models whose own normal map is flat (the Materialize approach, in numpy).

    python3 tools/visual_audit/normals_from_albedo.py in.glb out.glb [--tilt 7.0] [--force] [--preview out.png]

Many of the Meshy models shipped with a normal map that adds nothing (mean tilt ~1 degree, see uv_report.py), so
their surfaces shade like smooth plastic over the decimated geometry. This derives a height field from the colour
map's own detail (luminance, high-passed at two scales so baked large-scale shading doesn't become bumps), turns it
into a tangent-space normal map and blends it over the model's normal map (reoriented normal mapping), then writes a
new .glb with only that image replaced. Meshy's UV atlas is thousands of islands, so the slopes are taken only between
texels of the same island (an island id map rasterised from the mesh's UVs): no ridges along the seams. The strength is
set so the result's mean tilt is --tilt degrees (default 7, the median of the models whose Meshy normals are good).
glTF normal maps: +X along +U, +Y toward the top of the image (OpenGL convention).
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_audit import read_glb  # noqa: E402
from uv_report import accessor  # noqa: E402


def island_ids(js, binc, size):
	"""(id map int32 (0 = gutter), island count): every UV island rasterised with its own id."""
	ids = Image.new("I", (size, size), 0)
	d = ImageDraw.Draw(ids)
	nid = 0
	for m in js.get("meshes", []):
		for p in m.get("primitives", []):
			if "TEXCOORD_0" not in p["attributes"] or p.get("mode", 4) != 4:
				continue
			uv = accessor(js, binc, p["attributes"]["TEXCOORD_0"])
			ind = accessor(js, binc, p["indices"]).astype(np.int64).reshape(-1) if "indices" in p else np.arange(uv.shape[0])
			ind = ind[: (ind.size // 3) * 3].reshape(-1, 3)
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
			roots = {}
			uvw = uv % 1.0 if (uv.max() > 1.001 or uv.min() < -0.001) else uv
			for tri, tv in zip(ind, inv[ind]):
				r = find(tv[0])
				if r not in roots:
					nid += 1
					roots[r] = nid
				pts = [(uvw[i][0] * size, uvw[i][1] * size) for i in tri]
				d.polygon(pts, fill=roots[r], outline=roots[r])
	return np.array(ids, dtype=np.int32), nid


def tilt_deg(n, mask):
	xy = np.sqrt(n[..., 0] ** 2 + n[..., 1] ** 2)
	return float(np.degrees(np.arctan2(xy[mask], np.clip(n[..., 2][mask], 1e-3, None))).mean())


def island_grad(h, ids):
	"""Central differences of h along x (columns) and y (rows), using only neighbours in the same island."""
	gx = np.zeros_like(h)
	gy = np.zeros_like(h)
	# x
	same_r = np.zeros_like(ids, dtype=bool)
	same_l = np.zeros_like(ids, dtype=bool)
	same_r[:, :-1] = ids[:, 1:] == ids[:, :-1]
	same_l[:, 1:] = ids[:, :-1] == ids[:, 1:]
	hr = np.zeros_like(h)
	hl = np.zeros_like(h)
	hr[:, :-1] = h[:, 1:]
	hl[:, 1:] = h[:, :-1]
	both = same_r & same_l
	gx[both] = (hr[both] - hl[both]) * 0.5
	only_r = same_r & ~same_l
	gx[only_r] = hr[only_r] - h[only_r]
	only_l = same_l & ~same_r
	gx[only_l] = h[only_l] - hl[only_l]
	# y
	same_d = np.zeros_like(ids, dtype=bool)
	same_u = np.zeros_like(ids, dtype=bool)
	same_d[:-1, :] = ids[1:, :] == ids[:-1, :]
	same_u[1:, :] = ids[:-1, :] == ids[1:, :]
	hd = np.zeros_like(h)
	hu = np.zeros_like(h)
	hd[:-1, :] = h[1:, :]
	hu[1:, :] = h[:-1, :]
	both = same_d & same_u
	gy[both] = (hd[both] - hu[both]) * 0.5
	only_d = same_d & ~same_u
	gy[only_d] = hd[only_d] - h[only_d]
	only_u = same_u & ~same_d
	gy[only_u] = h[only_u] - hu[only_u]
	inside = ids > 0
	gx[~inside] = 0.0
	gy[~inside] = 0.0
	return gx, gy


def nearest_fill(arr, mask):
	"""Gutter texels take the value of the nearest island texel (so mipmaps don't pull in unrelated colours)."""
	_, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
	return arr[iy, ix]


def rnm(base, detail):
	"""Reoriented normal mapping: detail laid over base (both unit vectors, z up)."""
	t = base + np.array([0.0, 0.0, 1.0])
	u = detail * np.array([-1.0, -1.0, 1.0])
	r = t * np.sum(t * u, axis=-1, keepdims=True) / np.clip(t[..., 2:3], 1e-4, None) - u
	return r / np.linalg.norm(r, axis=-1, keepdims=True)


def build(js, binc, target_tilt):
	mat = js["materials"][0]
	pbr = mat.get("pbrMetallicRoughness", {})
	tex = js["textures"]
	ci = tex[pbr["baseColorTexture"]["index"]]["source"]
	ni = tex[mat["normalTexture"]["index"]]["source"] if "normalTexture" in mat else None

	def img(i):
		bv = js["bufferViews"][js["images"][i]["bufferView"]]
		return Image.open(io.BytesIO(binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]))
	col = img(ci).convert("RGB")
	size = col.size[0]
	nimg = img(ni).convert("RGB") if ni is not None else None
	if nimg is not None and nimg.size != col.size:
		nimg = nimg.resize(col.size, Image.LANCZOS)
	ids, n_islands = island_ids(js, binc, size)
	mask = ids > 0
	c = np.asarray(col, dtype=np.float64) / 255.0
	lum = c @ np.array([0.2126, 0.7152, 0.0722])
	lp = nearest_fill(lum, mask)
	# two bands of detail: fine grain (~1-2 texels) and medium forms (~6 texels); the broad shading Meshy baked
	# into the colour (tens of texels) is removed by the high-pass
	fine = lp - ndimage.gaussian_filter(lp, 1.5)
	med = ndimage.gaussian_filter(lp, 1.0) - ndimage.gaussian_filter(lp, 6.0)
	h = fine * 0.6 + med * 1.0
	h -= ndimage.gaussian_filter(h, 24.0)
	gx, gy = island_grad(h, ids)
	base = np.dstack([np.zeros_like(h), np.zeros_like(h), np.ones_like(h)])
	if nimg is not None:
		base = np.asarray(nimg, dtype=np.float64) / 255.0 * 2.0 - 1.0
		base /= np.linalg.norm(base, axis=-1, keepdims=True)
	base_tilt = tilt_deg(base, mask)

	def make(s):
		# a bump rising along +U slopes the normal toward -X; the image's rows run down (-V up in glTF's +Y)
		d = np.dstack([-gx * s, gy * s, np.ones_like(h)])
		d /= np.linalg.norm(d, axis=-1, keepdims=True)
		return rnm(base, d)
	lo, hi = 0.0, 400.0
	out = make(40.0)
	for _ in range(18):
		mid = (lo + hi) * 0.5
		out = make(mid)
		if tilt_deg(out, mask) < target_tilt:
			lo = mid
		else:
			hi = mid
	tilt = tilt_deg(out, mask)
	for k in range(3):
		out[..., k] = nearest_fill(out[..., k], mask)
	out /= np.linalg.norm(out, axis=-1, keepdims=True)
	enc = np.clip((out * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
	return Image.fromarray(enc, "RGB"), {"islands": n_islands, "size": size, "tilt_before": round(base_tilt, 1), "tilt_after": round(tilt, 1),
		"normal_image": ni}


def write_glb(js, binc, replace, path):
	"""Writes js + binc with image index -> new bytes replaced (bufferViews repacked in order, 4-byte aligned)."""
	views = js["bufferViews"]
	img_view = {js["images"][i]["bufferView"]: data for i, data in replace.items()}
	new_bin = bytearray()
	for vi, bv in enumerate(views):
		start = bv.get("byteOffset", 0)
		data = img_view.get(vi, binc[start:start + bv["byteLength"]])
		while len(new_bin) % 4:
			new_bin.append(0)
		bv["byteOffset"] = len(new_bin)
		bv["byteLength"] = len(data)
		new_bin += data
	while len(new_bin) % 4:
		new_bin.append(0)
	js["buffers"][0]["byteLength"] = len(new_bin)
	jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
	while len(jb) % 4:
		jb += b" "
	total = 12 + 8 + len(jb) + 8 + len(new_bin)
	with open(path, "wb") as f:
		f.write(struct.pack("<4sII", b"glTF", 2, total))
		f.write(struct.pack("<II", len(jb), 0x4E4F534A))
		f.write(jb)
		f.write(struct.pack("<II", len(new_bin), 0x004E4942))
		f.write(new_bin)


def main():
	a = sys.argv[1:]
	src, dst = a[0], a[1]
	tilt = float(a[a.index("--tilt") + 1]) if "--tilt" in a else 7.0
	js, binc = read_glb(src)
	if any(v.get("byteStride") for v in js["bufferViews"] if False):
		pass
	nimg, info = build(js, binc, tilt)
	if info["normal_image"] is None:
		print("no normal texture slot in", src, "(not handled)")
		sys.exit(1)
	if info["tilt_before"] > 3.0 and "--force" not in a:
		print("%s: its normal map already has detail (tilt %.1f); --force to blend anyway" % (src, info["tilt_before"]))
		sys.exit(2)
	buf = io.BytesIO()
	nimg.save(buf, "JPEG", quality=94, subsampling=0)
	js["images"][info["normal_image"]]["mimeType"] = "image/jpeg"
	write_glb(js, binc, {info["normal_image"]: buf.getvalue()}, dst)
	print("%s -> %s: %d islands, %d px, normal tilt %.1f -> %.1f deg, %.0f KB" % (src, dst, info["islands"], info["size"],
		info["tilt_before"], info["tilt_after"], os.path.getsize(dst) / 1024))
	if "--preview" in a:
		nimg.resize((512, 512), Image.LANCZOS).save(a[a.index("--preview") + 1])


if __name__ == "__main__":
	main()
