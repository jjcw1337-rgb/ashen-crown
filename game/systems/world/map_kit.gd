class_name MapKit
extends RefCounted
## Small helpers every map uses for its Meshy set pieces: a prepared prop placed standing on the ground with its
## footprint (piece), a yaw facing a point (face), a model's meshes merged into one for a MultiMesh (mesh), and an
## animation's root pinned in place (pin_root). Made for the starting camp (archived); the Verdant Reach and the
## multiplayer page's stage use them.

static var _meshes := {}

## A model's meshes merged into one (for MultiMesh).
static func mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var sc: Node = (load(path) as PackedScene).instantiate()
	var mis := sc.find_children("*", "MeshInstance3D", true, false)
	var out: Mesh
	if mis.size() == 1:
		# one mesh (every prepared prop): the imported mesh as it is (Meshy's get no LODs from the importer: their
		# thousands of UV islands leave nothing it can simplify)
		out = (mis[0] as MeshInstance3D).mesh
	else:
		var am := ArrayMesh.new()
		for n in mis:
			var mi: MeshInstance3D = n
			for si in mi.mesh.get_surface_count():
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(si))
				am.surface_set_material(am.get_surface_count() - 1, mi.mesh.surface_get_material(si))
		out = am
	sc.free()
	_meshes[path] = out
	return out

## Places the prop at `path` standing on the ground at `at`, turned by `yaw`, solid by `foot` (its half-extents in
## its own x/z). null if the file isn't there.
static func piece(w: World, path: String, foot: Vector2, at: Vector2, yaw: float, s := 1.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var root := Props.footprint(Models.N(null, path.get_file().get_basename()), foot * 0.9)
	root.set_meta("piece", path.get_file().get_basename())
	root.add_child((load(path) as PackedScene).instantiate())
	w._place(root, Vector3(at.x, 0, at.y))
	root.rotation.y = yaw
	root.scale = Vector3.ONE * s
	w.solid(root)
	return root

## Yaw that turns a model's front (+z) toward a point.
static func face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)

## A Meshy clip's Hips held over their first key (x and z), so the body plays in place (it may still rise and fall).
static func pin_root(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(t)).ends_with(":Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var p0: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(p0.x, v.y, p0.z))
