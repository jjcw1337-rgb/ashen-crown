extends SceneTree
## Screenshots of Grubb's fort from the game's camera at a few spots (approach, outer gate, outer yard,
## bridge, camp, great hall):  godot --path . -s tools/fort_shots.gd -- outprefix
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.test_immortal = true
	await g.load_zone(0, "lair", "start")
	g.ui.close_all()
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var og := Fort.outer_gate()
	var gp := Fort.gate_pos()
	var spots := {"approach": Vector2(0, -12), "outer_gate": og + Vector2(0, -4), "yard_w": Vector2(-38, -52), "yard_e": Vector2(36, -50),
		"bridge": gp + Vector2(0, 6), "camp": Vector2(10, -70), "hall": Fort.HALL + Vector2(0, 12), "hall_close": Fort.HALL + Vector2(0, 8)}
	for k in spots:
		var p: Vector2 = spots[k]
		g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.y), p.y)
		for i in 20:
			await process_frame
		get_root().get_texture().get_image().save_png("%s_%s.png" % [out, k])
		print("saved ", k)
	quit()
