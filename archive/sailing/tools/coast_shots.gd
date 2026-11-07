extends SceneTree
## Screenshots of the Mournwater Coast through the game's own camera (coast.gd): the pier, Osric at his hull and
## on his round to the pier, the fishing hamlet, the wreck, the sea stacks and the beacon on the point.
##   godot --path . --resolution 1600x900 -s tools/coast_shots.gd -- outprefix
var g
func shot(out: String, name: String, frames := 40) -> void:
	for i in frames:
		await process_frame
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
## The first placed prop whose model file has `key` in its name.
func _prop(key: String) -> Node3D:
	for n in g.world.props_root.get_children():
		if n is Node3D and str(n.scene_file_path).get_file().begins_with(key):
			return n
	return null
func _go(p: Vector3, off := Vector3(0, 0, 5.0)) -> void:
	g.hero.global_position = g.world.free_spot_near(p + off, 0.8)
	g.hero.global_position.y = g.world.height_at(g.hero.global_position.x, g.hero.global_position.z)
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.test_immortal = true
	await g.load_zone(0, "coast", "dock")
	while g._busy:
		await process_frame
	await shot(out, "1_pier", 90)
	var osric = null
	for t in g.world.interactables:
		if t.kind == "vendor" and str(t.data.get("role", "")) == "shipwright":
			osric = t
	if osric != null:
		_go(osric.global_position, Vector3(2.0, 0, 7.0))
		await shot(out, "2_osric")
		# his round: off to the pier and back (the hero out of his way, so nothing stops him)
		_go(osric.global_position, Vector3(30.0, 0, 20.0))
		osric._walk_to = (osric.clips["patrol"]["points"] as Array)[1]
		osric._patrol_i = 1
		for i in 150:
			await process_frame
		_go(osric.global_position, Vector3(7.5, 0, 6.0))
		await shot(out, "3_osric_walking", 2)
		for i in 300:
			await process_frame
		await shot(out, "4_osric_at_pier", 2)
		print("osric at ", osric.global_position, " playing ", osric.anim.current_animation)
	for k in ["fishing_hut", "wreck", "sea_stack", "beacon", "rock_pools", "driftwood"]:
		var m := _prop(k)
		if m != null:
			_go(m.global_position, Vector3(0, 0, 7.0) if k != "sea_stack" else Vector3(0, 0, 14.0))
			await shot(out, "5_" + k)
	quit()
