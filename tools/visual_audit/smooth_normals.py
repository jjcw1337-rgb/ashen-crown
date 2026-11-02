#!/usr/bin/env python3
"""Smooth shading for faceted Meshy props: recomputes vertex normals in a .glb from its own geometry.

    python3 tools/visual_audit/smooth_normals.py in.glb out.glb [--crease 60]

Meshy's decimated exports split every vertex along their thousands of UV seams and give each copy its own normal,
so round things (a flask, a rock) shade in flat patches with hard edges between them. This rebuilds each vertex's
normal as the area-weighted average of the faces round it, then averages the copies that sit at the same point
when they lean less than --crease degrees apart (real creases stay sharp). Only the NORMAL data changes, in place:
same vertices, same skin, same everything else, so it is safe on rigged models too. Godot rebuilds tangents on
import (ensure_tangents).
"""
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_audit import read_glb  # noqa: E402
from normals_from_albedo import write_glb  # noqa: E402
from uv_report import accessor  # noqa: E402


def smooth(P, I, crease_deg):
	n = P.shape[0]
	tri = I.reshape(-1, 3)
	fn = np.cross(P[tri[:, 1]] - P[tri[:, 0]], P[tri[:, 2]] - P[tri[:, 0]])     # length = 2 x area
	vn = np.zeros_like(P)
	for k in range(3):
		np.add.at(vn, tri[:, k], fn)
	vn /= np.clip(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12, None)
	# the copies of a vertex along a seam: same position (to 1e-5 of the model's size)
	size = float(np.ptp(P, axis=0).max())
	q = np.round(P / max(size * 1e-5, 1e-9)).astype(np.int64)
	_, grp = np.unique(q, axis=0, return_inverse=True)
	grp = grp.reshape(-1)
	cos_c = np.cos(np.radians(crease_deg))
	out = vn.copy()
	order = np.argsort(grp, kind="stable")
	gs = grp[order]
	starts = np.flatnonzero(np.r_[True, gs[1:] != gs[:-1]])
	ends = np.r_[starts[1:], len(gs)]
	for s, e in zip(starts, ends):
		if e - s < 2:
			continue
		idx = order[s:e]
		v = vn[idx]
		# each copy takes the mean of the copies within the crease angle of it
		sim = (v @ v.T) >= cos_c
		m = sim.astype(np.float64) @ v
		out[idx] = m / np.clip(np.linalg.norm(m, axis=1, keepdims=True), 1e-12, None)
	return out.astype(np.float32)


def main():
	a = sys.argv[1:]
	src, dst = a[0], a[1]
	crease = float(a[a.index("--crease") + 1]) if "--crease" in a else 60.0
	js, binc = read_glb(src)
	binc = bytearray(binc)
	done = 0
	for m in js["meshes"]:
		for p in m["primitives"]:
			at = p["attributes"]
			if "NORMAL" not in at or "indices" not in p:
				continue
			acc = js["accessors"][at["NORMAL"]]
			if acc["componentType"] != 5126 or acc["type"] != "VEC3":
				continue
			P = accessor(js, bytes(binc), at["POSITION"])
			I = accessor(js, bytes(binc), p["indices"]).astype(np.int64).reshape(-1)
			N = smooth(P, I, crease)
			bv = js["bufferViews"][acc["bufferView"]]
			off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
			stride = bv.get("byteStride", 0) or 12
			for i in range(N.shape[0]):
				struct.pack_into("<3f", binc, off + i * stride, *N[i])
			done += 1
	write_glb(js, bytes(binc), {}, dst)
	print("%s -> %s: %d primitive(s) re-shaded (crease %.0f deg)" % (src, dst, done, crease))


if __name__ == "__main__":
	main()
