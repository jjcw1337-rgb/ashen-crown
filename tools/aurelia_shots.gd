extends SceneTree
## Screenshots of A2's Aurelia (aurelia.gd) and the arena: a high overview, then the game camera at the
## city gate, the main street, the crossroads, the temple, the plaza with Varro, and the sand during the
## lions' bout.   godot --path . -s tools/aurelia_shots.gd -- outprefix [overview]
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
	await g.load_zone(0, "lair", "start")
	g.ui.close_all()
	var w = g.world
	if args.has("overview"):
		for e in w.enemies_root.get_children():
			e.queue_free()
		var cam := Camera3D.new()
		w.add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 210.0
		cam.far = 800.0
		var at := Vector3(0, 0, -95)
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
	for k in [["gate", Vector2(0, -16)], ["street", Vector2(0, -36)], ["crossroads", Vector2(6, -60)], ["temple", Vector2(-24, -58)], ["plaza", Vector2(0, -110)]]:
		var p: Vector2 = k[1]
		g.hero.global_position = Vector3(p.x, w.height_at(p.x, p.y), p.y)
		await _shot("%s_%s.png" % [out, k[0]])
	var games = w.get_meta("games")
	games.begin()
	var sp: Vector3 = w.spawns["arena"]
	g.hero.global_position = sp
	await _shot(out + "_sand0.png", 30)
	for i in 300:
		await process_frame
		if games.state == "stage":
			break
	await _shot(out + "_sand1.png", 60)
	var c3: Vector3 = w.spawns["arena"] - Vector3(0, 0, 9.0)
	g.hero.global_position = Vector3(c3.x, w.height_at(c3.x, c3.z), c3.z)
	games.excite = 1.0
	await _shot(out + "_center.png", 30)
	print("[A] state %s stage %d foes %d crowd %d" % [games.state, games.stage, games.foes.size(), w.props_root.get_node("crowd").multimesh.instance_count])
	if args.has("boss"):
		# on to the champion: clear each bout, then catch the spikes coming up round him
		for s in 3:
			for i in 600:
				await process_frame
				if games.state == "stage" and games.stage == s:
					break
			for e in games.foes:
				if is_instance_valid(e) and not e.dead:
					e.take_damage(99999.0, 0.0, g.hero.global_position, 0.0, false)
		for i in 900:
			await process_frame
			if games.state == "boss" and games.spikes.size() > 0:
				break
		g.hero.global_position = games.boss.global_position + Vector3(0, 0, 5)
		await _shot(out + "_boss1.png", 50)
		await _shot(out + "_boss2.png", 30)
	quit()
