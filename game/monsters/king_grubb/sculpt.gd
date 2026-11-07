class_name Sculpt
extends RefCounted
## Code-sculpted, skinned bodies. Shapes (ellipsoids and round-cone chains) are signed distance
## fields that melt into each other with a smooth union, so a body is one continuous skin
## instead of parts placed side by side. Each shape belongs to a bone; the field is sampled on
## a grid, turned into a mesh with surface nets, and every vertex is weighted to the bones of
## the shapes it is near, so the skin bends smoothly at the joints on a Skeleton3D.
##
## Shapes are in model (rest) space. carve() subtracts (eye sockets, nostrils, a navel).
## Shapes melt only into shapes of the same group (set `group` before adding them), and each
## group is its own closed shell, so an arm hanging against a belly stays an arm when it moves.
## Put a joint's ball in both groups it connects (a shoulder in the body and the arm) so the
## shells overlap there.
## The rest position of each vertex is stored in UV (x, y) and UV2.x, so shaders can texture
## in rest space and the detail stays stuck to the skin as it moves.

const ELLIPSOID := 0
const CONE := 1

var prims: Array = []
var group := 0

## An ellipsoid of radii r at c.
func ellipsoid(bone: int, c: Vector3, r: Vector3, k := 0.04) -> void:
	prims.append({"t": ELLIPSOID, "bone": bone, "c": c, "r": r, "k": k, "cut": false, "grp": group})

## A tapered capsule from a (radius r0) to b (radius r1).
func cone(bone: int, a: Vector3, b: Vector3, r0: float, r1: float, k := 0.04) -> void:
	prims.append({"t": CONE, "bone": bone, "a": a, "b": b, "r0": r0, "r1": r1, "k": k, "cut": false, "grp": group})

## Tapered capsules through a list of points (a limb, a nose, a hunched neck).
func chain(bone: int, pts: Array, radii: Array, k := 0.04) -> void:
	for i in pts.size() - 1:
		cone(bone, pts[i], pts[i + 1], radii[i], radii[i + 1], k)

## Subtracts a sphere-ish hollow (smoothly, by k).
func carve(bone: int, c: Vector3, r: Vector3, k := 0.01) -> void:
	prims.append({"t": ELLIPSOID, "bone": bone, "c": c, "r": r, "k": k, "cut": true, "grp": group})

func _aabb(p: Dictionary) -> AABB:
	var g: float = p["k"]
	if p["t"] == ELLIPSOID:
		var r: Vector3 = p["r"]
		return AABB(p["c"] - r - Vector3.ONE * g, (r + Vector3.ONE * g) * 2.0)
	var rr: float = maxf(p["r0"], p["r1"]) + g
	var a: Vector3 = p["a"]
	var b: Vector3 = p["b"]
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * rr
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * rr
	return AABB(mn, mx - mn)

static func _dist(p: Dictionary, q: Vector3) -> float:
	if p["t"] == ELLIPSOID:
		var r: Vector3 = p["r"]
		var d: Vector3 = q - p["c"]
		return (Vector3(d.x / r.x, d.y / r.y, d.z / r.z).length() - 1.0) * minf(r.x, minf(r.y, r.z))
	var a: Vector3 = p["a"]
	var ba: Vector3 = p["b"] - a
	var pa := q - a
	var t := clampf(pa.dot(ba) / maxf(ba.length_squared(), 1e-9), 0.0, 1.0)
	return (pa - ba * t).length() - lerpf(p["r0"], p["r1"], t)

## Polygonises the field at cell size h. Returns a skinned ArrayMesh (4 weights per vertex).
func build(h: float) -> ArrayMesh:
	var bb: AABB = _aabb(prims[0])
	for p in prims:
		if not p["cut"]:
			bb = bb.merge(_aabb(p))
	bb = bb.grow(h * 2.0)
	var mn := bb.position
	var nx := int(ceil(bb.size.x / h)) + 1
	var ny := int(ceil(bb.size.y / h)) + 1
	var nz := int(ceil(bb.size.z / h)) + 1
	var sy := nx
	var sz := nx * ny
	var grids := {}
	for p in prims:
		if not grids.has(p["grp"]):
			var gg := PackedFloat32Array()
			gg.resize(nx * ny * nz)
			gg.fill(1.0)
			grids[p["grp"]] = gg
	# --- splat each shape into its group's grid within its bounds (unions first, then carves)
	for pass_cut in [false, true]:
		for p in prims:
			if p["cut"] != pass_cut:
				continue
			var gr: PackedFloat32Array = grids[p["grp"]]
			var k: float = p["k"]
			var box := _aabb(p).grow(h * 2.0)
			var x0 := clampi(int((box.position.x - mn.x) / h), 0, nx - 1)
			var x1 := clampi(int(ceil((box.end.x - mn.x) / h)), 0, nx - 1)
			var y0 := clampi(int((box.position.y - mn.y) / h), 0, ny - 1)
			var y1 := clampi(int(ceil((box.end.y - mn.y) / h)), 0, ny - 1)
			var z0 := clampi(int((box.position.z - mn.z) / h), 0, nz - 1)
			var z1 := clampi(int(ceil((box.end.z - mn.z) / h)), 0, nz - 1)
			var ell: bool = p["t"] == ELLIPSOID
			var c := Vector3.ZERO
			var ir := Vector3.ONE
			var rmin := 1.0
			var a := Vector3.ZERO
			var ba := Vector3.ZERO
			var bl := 1.0
			var r0 := 0.0
			var r1 := 0.0
			if ell:
				c = p["c"]
				var r: Vector3 = p["r"]
				ir = Vector3(1.0 / r.x, 1.0 / r.y, 1.0 / r.z)
				rmin = minf(r.x, minf(r.y, r.z))
			else:
				a = p["a"]
				ba = p["b"] - a
				bl = maxf(ba.length_squared(), 1e-9)
				r0 = p["r0"]
				r1 = p["r1"]
			for z in range(z0, z1 + 1):
				var wz := mn.z + z * h
				for y in range(y0, y1 + 1):
					var wy := mn.y + y * h
					var row := z * sz + y * sy
					for x in range(x0, x1 + 1):
						var q := Vector3(mn.x + x * h, wy, wz)
						var d: float
						if ell:
							d = (((q - c) * ir).length() - 1.0) * rmin
						else:
							var pa := q - a
							var t := clampf(pa.dot(ba) / bl, 0.0, 1.0)
							d = (pa - ba * t).length() - lerpf(r0, r1, t)
						var i := row + x
						var cur := gr[i]
						if pass_cut:
							d = -d
							var hh := maxf(k - absf(cur - d), 0.0) / k
							gr[i] = maxf(cur, d) + hh * hh * k * 0.25
						else:
							var hh := maxf(k - absf(cur - d), 0.0) / k
							gr[i] = minf(cur, d) - hh * hh * k * 0.25
			grids[p["grp"]] = gr
	# each group becomes its own closed shell (they overlap where a joint ball is shared)
	var boxes := []
	for p in prims:
		boxes.append(_aabb(p).grow(0.06))
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for grp in grids.keys():
		var shell := _nets(grids[grp], mn, nx, ny, nz, h)
		var verts: PackedVector3Array = shell[0]
		# skin weights: each vertex follows the bones of its group's shapes it sits on or near
		for vi in verts.size():
			var q := verts[vi]
			var bw := {}
			var best := INF
			var best_bone := 0
			for pi in prims.size():
				var p: Dictionary = prims[pi]
				if p["cut"] or p["grp"] != grp or not (boxes[pi] as AABB).has_point(q):
					continue
				var d := _dist(p, q)
				if d < best:
					best = d
					best_bone = p["bone"]
				var reach := maxf(p["k"], 0.03) * 1.5
				var w := clampf(1.0 - maxf(d, 0.0) / reach, 0.0, 1.0)
				if w > 0.0:
					bw[p["bone"]] = bw.get(p["bone"], 0.0) + w * w
			if bw.is_empty():
				bw[best_bone] = 1.0
			var ks: Array = bw.keys()
			ks.sort_custom(func(l, r): return bw[l] > bw[r])
			var bones := PackedInt32Array([0, 0, 0, 0])
			var ws := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			var tot := 0.0
			for j in mini(4, ks.size()):
				bones[j] = ks[j]
				ws[j] = bw[ks[j]]
				tot += ws[j]
			for j in 4:
				ws[j] /= tot
			st.set_bones(bones)
			st.set_weights(ws)
			st.set_uv(Vector2(q.x, q.y))
			st.set_uv2(Vector2(q.z, 0.0))
			st.add_vertex(q)
		for i in (shell[1] as PackedInt32Array):
			st.add_index(base + i)
		base += verts.size()
	st.generate_normals()
	return st.commit()

## Surface nets over one grid: [vertices, triangle indices].
static func _nets(g: PackedFloat32Array, mn: Vector3, nx: int, ny: int, nz: int, h: float) -> Array:
	var sy := nx
	var sz := nx * ny
	var corner := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var coff := PackedInt32Array()
	for cc in corner:
		coff.append(cc.x + cc.y * sy + cc.z * sz)
	var vcell := {}
	var verts := PackedVector3Array()
	var cells := PackedInt32Array()
	var reject := h * 2.0
	var vals := PackedFloat32Array()
	vals.resize(8)
	# one vertex per cell the surface passes through
	for z in nz - 1:
		for y in ny - 1:
			var row := z * sz + y * sy
			for x in nx - 1:
				var i0 := row + x
				if absf(g[i0]) > reject:
					continue
				var inside := 0
				for j in 8:
					var v := g[i0 + coff[j]]
					vals[j] = v
					if v < 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var va := vals[e[0]]
					var vb := vals[e[1]]
					if (va < 0.0) != (vb < 0.0):
						var t := va / (va - vb)
						var ca: Vector3i = corner[e[0]]
						var cb: Vector3i = corner[e[1]]
						acc += Vector3(ca) + (Vector3(cb) - Vector3(ca)) * t
						cnt += 1
				acc /= cnt
				vcell[i0] = verts.size()
				verts.append(mn + (Vector3(x, y, z) + acc) * h)
				cells.append(i0)
	# each grid edge that crosses the surface joins the four cells around it
	var idx := PackedInt32Array()
	for ci in cells.size():
		var i0 := cells[ci]
		var z := i0 / sz
		var y := (i0 % sz) / sy
		var x := i0 % sy
		var v0 := g[i0]
		if y > 0 and z > 0:
			var v1 := g[i0 + 1]
			if (v0 < 0.0) != (v1 < 0.0):
				_quad(idx, vcell, i0, i0 - sy, i0 - sy - sz, i0 - sz, v0 < 0.0)
		if x > 0 and z > 0:
			var v1 := g[i0 + sy]
			if (v0 < 0.0) != (v1 < 0.0):
				_quad(idx, vcell, i0, i0 - sz, i0 - 1 - sz, i0 - 1, v0 < 0.0)
		if x > 0 and y > 0:
			var v1 := g[i0 + sz]
			if (v0 < 0.0) != (v1 < 0.0):
				_quad(idx, vcell, i0, i0 - 1, i0 - 1 - sy, i0 - sy, v0 < 0.0)
	return [verts, idx]

## Two triangles for the quad of cells a-b-c-d, wound to face out of the solid.
static func _quad(idx: PackedInt32Array, vcell: Dictionary, a: int, b: int, c: int, d: int, flip: bool) -> void:
	if not (vcell.has(a) and vcell.has(b) and vcell.has(c) and vcell.has(d)):
		return
	var ia: int = vcell[a]
	var ib: int = vcell[b]
	var ic: int = vcell[c]
	var id: int = vcell[d]
	if flip:
		idx.append_array([ia, ic, ib, ia, id, ic])
	else:
		idx.append_array([ia, ib, ic, ia, ic, id])
