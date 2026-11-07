extends SceneTree
## Every camp of the Verdant Reach can be played: a hero walking in from outside the camp (World.find_path, then
## World.move step by step, the way Hero walks) gets close enough to open its chest, and none of its monsters stands
## inside a prop's footprint or can't get out to a hero (Blaine 2026-11-06: a chest walled in after its camp fell,
## a camp monster that never moved). Prints what blocks a failing camp.
##   godot --headless --path . -s tools/_late.gd -- res://game/maps/verdant_reach/tests/camp_reach_test.gd
var g
var fails := 0

func check(c: bool, what: String) -> void:
	print(("[REACH] ok   " if c else "[REACH] FAIL ") + what)
	if not c:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

## Walk from `a` toward `b` as a hero would: the path, then small steps along it with the world's sliding. Returns
## the closest the walker came to `b`.
func walk(w, a: Vector3, b: Vector3, r := 0.45) -> float:
	var pos := a
	var best := Vector2(pos.x - b.x, pos.z - b.z).length()
	var path: PackedVector3Array = w.find_path(a, b)
	if path.is_empty():
		path = PackedVector3Array([b])
	for wp in path:
		for i in 400:
			var to := Vector3(wp.x - pos.x, 0, wp.z - pos.z)
			if to.length() < 0.2:
				break
			var nxt: Vector3 = w.move(pos, to.normalized() * minf(0.1, to.length()), r)
			if nxt.distance_to(pos) < 0.001:
				break
			pos = nxt
			best = minf(best, Vector2(pos.x - b.x, pos.z - b.z).length())
	return best

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.hide_title()
	g.hero.set_class("knight")
	g.hero.start_run()
	g.bg_mode = true
	g.test_immortal = true
	await g.load_zone(0, "bg", "start")
	var w = g.world
	var camps: Array = load("res://game/maps/verdant_reach/camps.gd").all(w)
	check(camps.size() >= 12, "%d camps" % camps.size())
	var need := 1.4 + 0.45 + 0.35      # (Hero: an Inter's radius + his body + slack)
	for c in camps:
		var at: Vector3 = c["pos"]
		var r: float = float(c["r"])
		var ch = c.get("chest_node")
		var away := Vector3(at.x, 0, at.z).normalized()
		if away.length() < 0.1:
			away = Vector3.FORWARD
		# from four sides outside the camp: the best of them must reach the chest
		var best := 99.0
		for k in 4:
			var dir := away.rotated(Vector3.UP, k * PI * 0.5)
			var start: Vector3 = w.free_spot_near(at + dir * (r + 9.0), 2.0)
			best = minf(best, walk(w, start, ch.global_position))
		check(best <= need, "%s: its chest can be reached (%.1f m, needs %.1f)" % [c["name"], best, need])
		if best > need:
			print("[REACH]      chest at %s; solid there: %s" % [str(ch.global_position.snapped(Vector3.ONE * 0.1)), w.solid_at(ch.global_position.x, ch.global_position.z, 1.0)])
		for e in w.enemies_root.get_children():
			if not (e is Enemy) or e.pack_id != int(c["pack"]):
				continue
			var p: Vector3 = e.global_position
			var stuck: bool = w.solid_at(p.x, p.z, 0.2)
			var out := 99.0
			for k in 4:
				var goal: Vector3 = w.free_spot_near(at + away.rotated(Vector3.UP, k * PI * 0.5) * (r + 9.0), 2.0)
				out = minf(out, walk(w, p, goal, e.radius))
			check(not stuck and out < 3.0, "%s: %s can walk out of the camp (%s, %.1f m short)" % [c["name"], e.kind, "inside a footprint" if stuck else "free", out])
	# the hermit's mushrooms breathe round their own size: two minutes of game time, still the size they began at
	var shrooms: Array = w.enemies_root.get_children().filter(func(x): return x is Enemy and x.kind == "spore_shroom" and not x.dead)
	check(not shrooms.is_empty(), "%d poison mushrooms" % shrooms.size())
	if not shrooms.is_empty():
		var sh = shrooms[0]
		g.hero.global_position = w.free_spot_near(sh.global_position + Vector3(6, 0, 0), 1.0)
		var body: Node3D = sh.rig.get_node_or_null("body")
		await create_timer(0.5).timeout
		var s0: float = body.scale.length() if body != null else 0.0
		Engine.time_scale = 6.0
		await create_timer(20.0 * 6.0, true, false, false).timeout      # (20 s of real time at 6x)
		Engine.time_scale = 1.0
		var s1: float = body.scale.length() if is_instance_valid(body) else 0.0
		check(body != null and s1 > 0.0 and s1 < s0 * 1.1, "a mushroom keeps its size (%.2f -> %.2f after 2 minutes)" % [s0, s1])
	print("[REACH] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
