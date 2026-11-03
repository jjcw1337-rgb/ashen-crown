#!/usr/bin/env python3
"""Lights the glowing parts Meshy only painted: an emission map from the colour map's hot texels.

    python3 tools/visual_audit/emission_from_albedo.py in.glb out.glb [--strength 3] [--kind ember] [--preview out.png]

Meshy has no emission channel, so the Ashen King's embers in the cracks of his armour and his burning eyes came out
as orange paint that goes dark in a dark crypt. This finds the hot texels (kind "ember": saturated orange-yellow
brighter than their surroundings), keeps their own colour as the glow, writes it as the material's emissive texture
(glTF emissiveTexture, with KHR_materials_emissive_strength so Godot imports it with an energy above 1) and leaves
everything else in the file as it was.
"""
import io
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_audit import read_glb  # noqa: E402
from normals_from_albedo import write_glb  # noqa: E402


def smoothstep(a, b, x):
	t = np.clip((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def ember_mask(rgb):
	r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
	mx = rgb.max(2)
	mn = rgb.min(2)
	sat = (mx - mn) / np.maximum(mx, 1e-4)
	hue_ok = smoothstep(0.08, 0.25, r - b) * smoothstep(0.02, 0.12, r - g * 0.6) * (1.0 - smoothstep(0.85, 1.0, g / np.maximum(r, 1e-4)))
	bright = smoothstep(0.22, 0.6, mx)
	# brighter than the neighbourhood: cracks glow, a uniformly orange surface (rust, skin) doesn't
	lum = rgb @ np.array([0.299, 0.587, 0.114])
	local = ndimage.uniform_filter(lum, size=31)
	contrast = smoothstep(0.02, 0.12, lum - local)
	return np.clip(hue_ok * smoothstep(0.3, 0.6, sat) * bright * (0.5 + 0.5 * contrast), 0.0, 1.0)


def main():
	a = sys.argv[1:]
	src, dst = a[0], a[1]
	strength = float(a[a.index("--strength") + 1]) if "--strength" in a else 3.0
	preview = a[a.index("--preview") + 1] if "--preview" in a else ""
	js, binc = read_glb(src)
	done = {}
	new_images = []
	for m in js.get("materials", []):
		pbr = m.get("pbrMetallicRoughness", {})
		if "baseColorTexture" not in pbr:
			continue
		bi = js["textures"][pbr["baseColorTexture"]["index"]]["source"]
		if bi not in done:
			bv = js["bufferViews"][js["images"][bi]["bufferView"]]
			s = bv.get("byteOffset", 0)
			im = Image.open(io.BytesIO(binc[s:s + bv["byteLength"]])).convert("RGB")
			rgb = np.asarray(im).astype(np.float64) / 255.0
			mask = ember_mask(rgb)
			# a soft bloom inside the texture so thin cracks read at a distance
			mask = np.maximum(mask, ndimage.gaussian_filter(mask, 2.0) * 0.6)
			# the glow: the painted colour pushed toward a hot ember orange (the paint is a dull, desaturated orange)
			emi = np.clip(mask[:, :, None] * (0.4 * 1.6 * rgb + 0.6 * np.array([1.0, 0.42, 0.1])), 0.0, 1.0)
			ob = io.BytesIO()
			Image.fromarray((emi * 255.0 + 0.5).astype(np.uint8)).save(ob, "JPEG", quality=92)
			print("image %d: %.2f%% of texels glow (mask > 0.3)" % (bi, 100.0 * float((mask > 0.3).mean())))
			if preview:
				Image.fromarray((emi * 255.0 + 0.5).astype(np.uint8)).resize((1024, 1024)).save(preview)
			# a new image + texture in the JSON; its bytes become a new bufferView appended after the others
			view = len(js["bufferViews"])
			js["bufferViews"].append({"buffer": 0, "byteOffset": 0, "byteLength": 0})
			img = len(js["images"])
			js["images"].append({"bufferView": view, "mimeType": "image/jpeg", "name": "emission"})
			tex = len(js["textures"])
			sampler = js["textures"][pbr["baseColorTexture"]["index"]].get("sampler")
			t = {"source": img}
			if sampler is not None:
				t["sampler"] = sampler
			js["textures"].append(t)
			done[bi] = tex
			new_images.append((view, ob.getvalue()))
		m["emissiveTexture"] = {"index": done[bi]}
		m["emissiveFactor"] = [1.0, 1.0, 1.0]
		m.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": strength}
	if not done:
		sys.exit("no material with a colour map in " + src)
	used = js.setdefault("extensionsUsed", [])
	if "KHR_materials_emissive_strength" not in used:
		used.append("KHR_materials_emissive_strength")
	# append the new images' bytes: write_glb repacks views in order, reading each from binc at its old offset
	binc = bytearray(binc)
	for view, data in new_images:
		while len(binc) % 4:
			binc.append(0)
		js["bufferViews"][view]["byteOffset"] = len(binc)
		js["bufferViews"][view]["byteLength"] = len(data)
		binc += data
	write_glb(js, bytes(binc), {}, dst)
	print("%s -> %s (emissive strength %.1f)" % (src, dst, strength))


if __name__ == "__main__":
	main()
