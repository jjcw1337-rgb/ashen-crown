class_name ShadowProxy
## Lighter shadows for skinned bodies (nightly perf 2026-11-04). A Meshy body is split at every UV seam (1.5-2.3
## vertices per triangle) and casts its shadow at full detail into every cascade it touches. Its shadow needs none
## of that: `attach(mi)` gives the body a shadows-only twin on the same skeleton and skin, made once per mesh and
## cached: the vertices welded by position (no UVs), then simplified with meshoptimizer (`ImporterMesh.generate_lods`,
## which can't simplify the seam-split original); the body itself then casts nothing. The shadow pass draws only
## depth, so nothing else on screen changes. `-- --noshadowproxy` turns it off for comparisons.

## Triangle share kept for the shadow (of the welded mesh). Bodies are ~1-4 m in a frame where the sun's texels
## are ~3-10 cm: a third of the triangles is still finer than the shadow map can show.
const KEEP := 0.35
## Bodies lighter than this keep their own shadow (a proxy isn't worth a second skinned mesh).
const MIN_TRIS := 6000

static var _cache := {}
static var enabled := true
static var _checked := false

static func on() -> bool:
	if not _checked:
		_checked = true
		if OS.get_cmdline_user_args().has("--noshadowproxy"):
			enabled = false
	return enabled

## Puts a shadows-only twin of `mi` (a skinned MeshInstance3D) beside it and switches its own shadow off.
## Returns the twin, or null when the body is light, not opaque or has no skin.
static func attach(mi: MeshInstance3D) -> MeshInstance3D:
	if not on() or mi == null or mi.mesh == null or mi.skin == null:
		return null
	if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or mi.has_meta("shadow_proxy"):
		return null
	var pm: ArrayMesh = proxy_mesh(mi.mesh, mi)
	if pm == null:
		return null
	var tw := MeshInstance3D.new()
	tw.name = "ShadowProxy"
	tw.mesh = pm
	tw.skin = mi.skin
	tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	tw.layers = mi.layers
	mi.add_sibling(tw)
	tw.skeleton = mi.skeleton if mi.skeleton.is_absolute() else NodePath("../" + str(mi.skeleton)) if str(mi.skeleton) != ".." else NodePath("..")
	tw.transform = mi.transform
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("shadow_proxy", tw)
	return tw

## Every skinned body under `root` gets its twin (see `attach`).
static func attach_all(root: Node) -> void:
	if not on() or root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.skin != null and mi.name != "ShadowProxy":
			attach(mi)

## The welded, simplified shadow mesh of `m` (cached), or null when it isn't worth one / can't cast like the body.
static func proxy_mesh(m: Mesh, mi: MeshInstance3D = null) -> ArrayMesh:
	var key := m.get_rid().get_id()
	if _cache.has(key):
		return _cache[key]
	var out: ArrayMesh = _build(m, mi)
	_cache[key] = out
	return out

static func _opaque(mat: Material) -> bool:
	if mat == null:
		return true
	if mat is BaseMaterial3D:
		var b: BaseMaterial3D = mat
		return b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and b.cull_mode == BaseMaterial3D.CULL_BACK
	return false   # a shader may move vertices or cut pixels: keep the body's own shadow

static func _build(m: Mesh, mi: MeshInstance3D) -> ArrayMesh:
	if not (m is ArrayMesh) or m.get_surface_count() == 0:
		return null
	var am: ArrayMesh = m
	var tris := 0
	for s in am.get_surface_count():
		var mat: Material = mi.get_surface_override_material(s) if mi and s < mi.get_surface_override_material_count() and mi.get_surface_override_material(s) else am.surface_get_material(s)
		if mi and mi.material_override:
			mat = mi.material_override
		if not _opaque(mat):
			return null
		if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		if not (am.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES):
			return null
		tris += am.surface_get_array_index_len(s) / 3
	if tris < MIN_TRIS or am.get_blend_shape_count() > 0:
		return null
	# weld every surface into one by position (bones and weights from the first vertex at a spot)
	var pos := PackedVector3Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var at := {}
	var per := 4
	for s in am.get_surface_count():
		var arr: Array = am.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if v.is_empty() or b.is_empty():
			return null
		var bp: int = b.size() / v.size()
		if bp != 4:
			return null   # 8-weight skins: leave them
		var remap := PackedInt32Array()
		remap.resize(v.size())
		for i in v.size():
			var p: Vector3 = v[i]
			var k := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
			var j: int = at.get(k, -1)
			if j < 0:
				j = pos.size()
				at[k] = j
				pos.append(p)
				for q in per:
					bones.append(b[i * per + q])
					wts.append(w[i * per + q])
			remap[i] = j
		if ii.is_empty():
			for i in v.size():
				idx.append(remap[i])
		else:
			for i in ii.size():
				idx.append(remap[ii[i]])
	# drop triangles the weld collapsed
	var clean := PackedInt32Array()
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var bb := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		if a != bb and bb != c and a != c:
			clean.append(a)
			clean.append(bb)
			clean.append(c)
	var nrm := _normals(pos, clean)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = wts
	arrays[Mesh.ARRAY_INDEX] = clean
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var best := clean
	var want := int(clean.size() * KEEP)
	for l in im.get_surface_lod_count(0):
		var li: PackedInt32Array = im.get_surface_lod_indices(0, l)
		if li.size() >= want / 2 and li.size() < best.size() and absi(li.size() - want) < absi(best.size() - want):
			best = li
	arrays[Mesh.ARRAY_INDEX] = best
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.custom_aabb = am.get_aabb().grow(am.get_aabb().size.length() * 0.25)
	out.set_meta("proxy_of", [am.get_surface_count(), tris, clean.size() / 3, best.size() / 3, pos.size()])
	return out

static func _normals(pos: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(pos.size())
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var f := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		n[a] += f
		n[b] += f
		n[c] += f
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 0.0 else Vector3.UP
	return n
