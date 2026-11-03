#!/usr/bin/env python3
"""Gives a Meshy model's metal its reflectance back: lifts the colour map where the metal map says metal.

    python3 tools/visual_audit/metal_lift.py in.glb out.glb [--target 0.5] [--rough 0.1] [--preview out.png]

Meshy paints metal parts with a near-black base colour (the armoured knight's plate: sRGB 0.25 median, i.e. a linear
reflectance of 5% where steel's is ~55%). For a metal the base colour IS the reflectance (F0), so in the game's dark
zones that plate only ever reflected 5% of any light: the knight read as a black blob with no highlights. This scales
the colour map in linear light where the metallic channel says metal (blended smoothly over metallic 0.2-0.55, so
cloth, leather and skin are untouched), so the metal's median comes to --target (sRGB), keeping every scratch, edge
and stain in proportion; the metal's roughness drops by --rough for crisper highlights. Only the two images change
(same UVs, skin, animations); textures shared by several materials are done once. Writes JPEG at quality 93.
"""
import io
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_audit import read_glb  # noqa: E402
from normals_from_albedo import write_glb  # noqa: E402


def to_lin(c):
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
	c = np.clip(c, 0.0, 1.0)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def smoothstep(a, b, x):
	t = np.clip((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def image_bytes(js, binc, img_index):
	bv = js["bufferViews"][js["images"][img_index]["bufferView"]]
	s = bv.get("byteOffset", 0)
	return binc[s:s + bv["byteLength"]]


def main():
	a = sys.argv[1:]
	src, dst = a[0], a[1]
	target = float(a[a.index("--target") + 1]) if "--target" in a else 0.5
	drough = float(a[a.index("--rough") + 1]) if "--rough" in a else 0.1
	preview = a[a.index("--preview") + 1] if "--preview" in a else ""
	js, binc = read_glb(src)
	pairs = set()
	for m in js.get("materials", []):
		pbr = m.get("pbrMetallicRoughness", {})
		if "baseColorTexture" in pbr and "metallicRoughnessTexture" in pbr:
			bi = js["textures"][pbr["baseColorTexture"]["index"]]["source"]
			mi = js["textures"][pbr["metallicRoughnessTexture"]["index"]]["source"]
			pairs.add((bi, mi))
	replace = {}
	for bi, mi in sorted(pairs):
		base_im = Image.open(io.BytesIO(image_bytes(js, binc, bi))).convert("RGB")
		mr_im = Image.open(io.BytesIO(image_bytes(js, binc, mi))).convert("RGB")
		if mr_im.size != base_im.size:
			mr_im = mr_im.resize(base_im.size, Image.BILINEAR)
		base = np.asarray(base_im).astype(np.float64) / 255.0
		mr = np.asarray(mr_im).astype(np.float64) / 255.0
		metal = mr[:, :, 2]
		w = smoothstep(0.2, 0.55, metal)
		lin = to_lin(base)
		lum = lin @ np.array([0.2126, 0.7152, 0.0722])
		sel = metal > 0.55
		if sel.sum() < 100:
			print("image %d: no metal to lift" % bi)
			continue
		med = float(np.median(lum[sel]))
		gain = float(np.clip(to_lin(np.array(target)) / max(med, 1e-4), 1.0, 6.0))
		k = 1.0 + (gain - 1.0) * w
		out = to_srgb(lin * k[:, :, None])
		rough = mr[:, :, 1]
		mr2 = mr.copy()
		mr2[:, :, 1] = np.clip(rough - drough * w, 0.22, 1.0)
		after = (to_lin(out) @ np.array([0.2126, 0.7152, 0.0722]))[sel]
		print("image %d: metal %.0f%% of texels, median %.3f -> %.3f (sRGB), gain x%.2f in linear; roughness %.2f -> %.2f" % (
			bi, 100.0 * sel.mean(), float(to_srgb(np.array(med))), float(to_srgb(np.array(np.median(after)))), gain,
			float(np.median(rough[sel])), float(np.median(mr2[:, :, 1][sel]))))
		ob = io.BytesIO()
		Image.fromarray((out * 255.0 + 0.5).astype(np.uint8)).save(ob, "JPEG", quality=93)
		replace[bi] = ob.getvalue()
		om = io.BytesIO()
		Image.fromarray((mr2 * 255.0 + 0.5).astype(np.uint8)).save(om, "JPEG", quality=93)
		replace[mi] = om.getvalue()
		for idx in (bi, mi):
			js["images"][idx]["mimeType"] = "image/jpeg"
		if preview:
			s = 768
			pv = Image.new("RGB", (s * 2, s))
			pv.paste(base_im.resize((s, s)), (0, 0))
			pv.paste(Image.fromarray((out * 255.0 + 0.5).astype(np.uint8)).resize((s, s)), (s, 0))
			pv.save(preview)
	write_glb(js, binc, replace, dst)
	print("%s -> %s" % (src, dst))


if __name__ == "__main__":
	main()
