extends SceneTree
## Screenshots of Act I's birds (birds.gd) over the moor from the game camera, pulled back a little, and
## the count of flocks and birds. Needs a display. Usage: godot --path . -s tools/birds_shot.gd -- outdir
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	g.test_immortal = true
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	g.zoom = 1.4
	var b = g.world.get_node("birds")
	b._burst_t = 1.0
	# one more flock, right over the hero (a picture with birds in it)
	b._new_flock(false)
	var over: Dictionary = b.flocks[b.flocks.size() - 1]
	over["pos"] = g.hero.global_position + Vector3(-6, 8, 4)
	over["h"] = 8.0
	over["dir"] = Vector3(1, 0, -0.6).normalized()
	for bd in over["birds"]:
		(bd as Node3D).position = over["pos"] + (bd as Node3D).get_meta("off")
	for k in 4:
		for f in 45:
			await process_frame
		get_root().get_texture().get_image().save_png("%s/birds_%d.png" % [out, k])
		var cam: Camera3D = get_root().get_viewport().get_camera_3d()
		var on := 0
		var sample := ""
		for fl in b.flocks:
			for bd in fl["birds"]:
				var p: Vector3 = (bd as Node3D).global_position
				if not cam.is_position_behind(p) and get_root().get_visible_rect().has_point(cam.unproject_position(p)):
					on += 1
				if sample == "":
					sample = "bird %s hero %s vis %s in tree %s" % [p.round(), g.hero.global_position.round(), (bd as Node3D).is_visible_in_tree(), (bd as Node3D).is_inside_tree()]
		print("[B] frame %d: %d birds on screen; %s" % [k, on, sample])
	var n := 0
	for fl in b.flocks:
		n += fl["birds"].size()
	print("[B] flocks %d, birds %d" % [b.flocks.size(), n])
	quit()
