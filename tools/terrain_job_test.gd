extends SceneTree
## Small analytic terrain fixture: no imported models or full game needed.
const Builder = preload("res://scripts/terrain_build.gd")
class Ground extends Node3D:
	var detail := 0
	var oak_forest := false
	func ground_h(x: float, z: float) -> float: return x + 2.0 * z
	func dirt_at(x: float, _z: float) -> float: return x / 10.0
	func cobble_at(_x: float, z: float) -> float: return z / 10.0
var fails := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1; push_error(label)
func make(w: Node3D, floor_y := -INF, own := Callable(), clip := Callable()) -> Array:
	var node := MeshInstance3D.new()
	w.add_child(node)
	return [node, Builder.new(w, node, Rect2(0, 0, 2, 2), 1.0, {}, floor_y, own, 0.0, clip)]
func run() -> void:
	Mats.ensure_globals()
	var w := Ground.new()
	root.add_child(w)
	var pair := make(w)
	check(pair[0].mesh == null, "no mesh before preparation")
	var steps := 0
	while not pair[1].step():
		steps += 1
		await process_frame
	check(steps >= 10, "height, vertex and index rows are separate steps")
	var arrays: Array = pair[0].mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size() == 9, "3 by 3 vertices")
	check(arrays[Mesh.ARRAY_INDEX].size() == 24, "four cells / eight triangles")
	# ArrayMesh octahedrally packs normals; permit its observed sub-0.0001 quantization.
	for z in 3:
		for x in 3:
			var i := z * 3 + x
			check(arrays[Mesh.ARRAY_VERTEX][i] == Vector3(x, x + 2 * z, z), "analytic height")
			check(arrays[Mesh.ARRAY_NORMAL][i].distance_to(Vector3(-1, 1, -2).normalized()) < 0.0001, "analytic normal")
	var sync := make(w)
	while not sync[1].step(): pass
	check(sync[0].mesh.surface_get_arrays(0) == arrays, "yielded and synchronous arrays identical")
	var owned := make(w, -INF, func(x, _z): return x < 1.0)
	while not owned[1].step(): pass
	check(owned[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 12, "ownership removes the right-hand cells")
	var clipped := make(w, -INF, Callable(), func(x, z, y): return Vector3(minf(x, 1), y - 0.5, z))
	while not clipped[1].step(): pass
	check(clipped[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][2] == Vector3(1, 1.5, 0), "island clipping preserves caller transform")
	var submerged := make(w, 100.0)
	while not submerged[1].step(): pass
	check(not is_instance_valid(submerged[0]), "wholly submerged patch leaves no empty mesh")
	var cancelled := make(w)
	cancelled[0].free()
	check(cancelled[1].step(), "retired target safely cancels queued work")
	w.free()
	print("[TERRAIN JOB] %d checks / %d failures" % [checks, fails])
	quit(1 if fails else 0)
