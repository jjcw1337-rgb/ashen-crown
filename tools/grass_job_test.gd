extends SceneTree
class Ground extends RefCounted:
	func grass_ground(_x: float, _z: float) -> float: return 1.0
	func grass_biome(_x: float, _z: float) -> Dictionary: return {"meadow": 1.0}
	func grass_height(_x: float, _z: float) -> float: return 0.0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var grass = load("res://scripts/grass.gd")
	print("BIOMES ", grass.BIOMES.keys())
	var ground := Ground.new()
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)
	var n: int = grass.scatter(a, Rect2(-8, -8, 16, 16), ground, grass.ACT1, 1, 421, false)
	var job = grass.ScatterJob.new(b, Rect2(-8, -8, 16, 16), ground, grass.ACT1, 1, 421, false)
	var steps := 0
	while not job.step():
		steps += 1
		await process_frame
	var same: bool = n > 0 and n == job.count and a.get_child_count() == b.get_child_count()
	for i in a.get_child_count():
		var x: MultiMeshInstance3D = a.get_child(i)
		var y: MultiMeshInstance3D = b.get_child(i)
		same = same and x.name == y.name and x.multimesh.buffer == y.multimesh.buffer
	print("[GRASS JOB] same=", same, " clumps=", n, " steps=", steps, " nodes=", a.get_child_count())
	a.queue_free()
	b.queue_free()
	await process_frame
	quit(0 if same else 1)
