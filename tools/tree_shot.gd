extends SceneTree
## Screenshots of the oaks in the game: the hero stands next to the nearest oak in the moor and in
## town; plus a lineup of the oak kinds. Needs a display. Usage: -- outdir
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _oak_spots() -> Array:
	var out := []
	var want := []
	for k in [1, 2, 3]:
		want.append(Flora.oak_model(k))
	want.append_array([Flora.oak(9), Flora.oak(12), Flora.oak(14)])
	for mmi in g.world.props_root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		if mm and want.has(mm.mesh):
			for i in mm.instance_count:
				out.append((mmi as Node3D).global_transform * mm.get_instance_transform(i).origin)
	return out

func _snap(name: String) -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	for f in 40:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/" + name + ".png")

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	for zone in ["wild", "town"]:
		if zone != "town":
			await g.travel(0, zone, "start")
		else:
			await g.travel(0, "town", "start")
		while g._busy:
			await process_frame
		var spots := _oak_spots()
		var hp: Vector3 = g.hero.global_position
		spots.sort_custom(func(a, b): return a.distance_to(hp) < b.distance_to(hp))
		print("[O] ", zone, " oaks: ", spots.size())
		var shots := 0
		var used := []
		for s in spots:
			if shots >= 2:
				break
			var far := true
			for u in used:
				if (u as Vector3).distance_to(s) < 15.0:
					far = false
			if not far:
				continue
			used.append(s)
			var p := (s as Vector3) + Vector3(2.2, 0, 3.2)
			g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
			await _snap("%s_%d" % [zone, shots])
			shots += 1
	g.quit_game() if g.has_method("quit_game") else null
	quit()
