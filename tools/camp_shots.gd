extends SceneTree
## Screenshots of Act I's forest camp (ForestCamp): the hero at each shop (game camera), a high
## overview of the whole camp and a low view through the gate. Needs a display.
## Usage: godot -s tools/camp_shots.gd -- outdir
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(name: String, frames := 6) -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	for f in frames:
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("[C] ", name)

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	while g._busy:
		await process_frame
	print("[C] forest camp: ", g.world.theme.get("forest_camp", false))
	var spots := {"bonfire": Vector3(0, 0, 5), "alchemist": Vector3(-8, 0, -6.5), "smith": Vector3(8, 0, -6.5),
		"armourer": Vector3(11, 0, 5), "gambler": Vector3(-10.5, 0, 6.5), "gate": Vector3(2, 0, -20)}
	for k in spots:
		var p: Vector3 = spots[k]
		g.hero.global_position = g.world.free_spot_near(p, 0.4)
		await _snap(k)
	# the whole camp from high above
	g.ui.root.visible = false
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	g.set_process(false)
	cam.global_transform = Transform3D(Basis(), Vector3(0, 52, 34)).looking_at(Vector3(0, 0, -3))
	cam.fov = 50
	await _snap("overview", 4)
	cam.global_transform = Transform3D(Basis(), Vector3(-3, 5, -38)).looking_at(Vector3(0, 2.5, -25))
	await _snap("gate_outside", 4)
	cam.global_transform = Transform3D(Basis(), Vector3(-11, 5.0, 7)).looking_at(Vector3(5, 1.6, -10))
	await _snap("inside", 4)
	# a rune stone outside the wall (the third of ForestCamp's eleven)
	var ra := TAU * 2.5 / 11.0
	var rp := ForestCamp.CENTER + Vector2(sin(ra), -cos(ra)) * (ForestCamp.RADIUS + 5.7)
	cam.global_transform = Transform3D(Basis(), Vector3(rp.x - 5.5, 2.6, rp.y + 2.5)).looking_at(Vector3(rp.x, 1.3, rp.y))
	await _snap("runestone", 4)
	quit()
