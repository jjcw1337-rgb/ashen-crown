extends SceneTree
var failed := 0
func check(ok: bool, label: String) -> void:
	print("[BOW SPRING] ", "ok " if ok else "FAIL ", label)
	if not ok: failed += 1
func _initialize() -> void:
	for times in [[1.0/240.0], [1.0/60.0], [1.0/30.0], [0.1], [0.005, 0.1, 0.033]]:
		var off := Vector3(0.1, 0.4, 0.5)
		var vel := Vector3.ZERO
		var elapsed := 0.0
		var i := 0
		var bounded := true
		while elapsed < 4.0:
			var dt: float = times[i % times.size()]
			var state := Archer.relax_bow_string(off, vel, dt, Vector3.BACK)
			off = state[0]; vel = state[1]
			bounded = bounded and off.is_finite() and vel.is_finite() and off.length() < 0.7
			elapsed += dt; i += 1
		check(bounded, "finite and bounded at frame times " + str(times))
		check(off == Vector3.ZERO and vel == Vector3.ZERO, "returns to rest at " + str(times))
	var recovered := Archer.relax_bow_string(Vector3(INF,0,0), Vector3.ZERO, 0.1, Vector3.BACK)
	check(recovered[0] == Vector3.ZERO and recovered[1] == Vector3.ZERO, "recovers an invalid prior state")
	print("[BOW SPRING] done, ", failed, " failures")
	quit(1 if failed else 0)
