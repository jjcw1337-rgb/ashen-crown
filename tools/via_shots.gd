extends SceneTree
## Screenshots of A2's Imperial Road (via.gd): a high overview, then the game camera along it (moor,
## the pass, the bandits springing their ambush, the Roman road, the aqueduct, the outskirts, the arch).
##   godot --path . -s tools/via_shots.gd -- outprefix [overview]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _shot(path: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.test_immortal = true
	g.difficulty = 1
	await g.load_zone(0, "wild", "start")
	g.ui.close_all()
	var w = g.world
	if args.has("overview"):
		for e in w.enemies_root.get_children():
			e.queue_free()
		var cam := Camera3D.new()
		w.add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 340.0
		cam.far = 800.0
		var at := Vector3(0, 0, -165)
		cam.transform = Transform3D(Basis(), at + Vector3(0, 300, 1)).looking_at(at, Vector3(0, 0, -1))
		cam.current = true
		g.env.fog_enabled = false
		g.env.volumetric_fog_enabled = false
		for c in g.get_children():
			if c is CanvasLayer:
				c.visible = false
		await _shot(out + "_overview.png", 30)
		quit()
		return
	for e in w.enemies_root.get_children():
		e.set_process(false)
	for k in [["moor", 0.15, 0.0], ["pass", Via.AMBUSH - 0.03, 0.0], ["roman", 0.52, 0.0], ["aqueduct", 0.565, 0.0], ["outskirts", 0.84, 0.0], ["arch", 0.975, 0.0]]:
		var p: Vector2 = Via.beside(w, k[1], k[2])
		g.hero.global_position = Vector3(p.x, w.height_at(p.x, p.y), p.y)
		await _shot("%s_%s.png" % [out, k[0]])
	# the ambush: walk onto the trigger point and catch the bandits in the air
	for e in w.enemies_root.get_children():
		e.set_process(true)
	var am: Dictionary = w.ambushes[0]
	var tp: Vector3 = am["pos"]
	g.hero.global_position = Vector3(tp.x, w.height_at(tp.x, tp.z), tp.z)
	await _shot(out + "_ambush.png", 18)
	var n := 0
	for e in w.enemies_root.get_children():
		if e is Enemy and e.kind.begins_with("bandit") and e.global_position.distance_to(tp) < 30.0:
			n += 1
	print("[V] ambush sprung %s, bandits near %d" % [am["done"], n])
	await _shot(out + "_ambush2.png", 40)
	quit()
