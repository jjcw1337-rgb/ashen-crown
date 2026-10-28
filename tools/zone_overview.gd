extends SceneTree
## A high, steep view down the first stretch of Cairnfell Moor (for comparing road layouts).
## Usage: godot --path . -s tools/zone_overview.gd -- out.png [--road N]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "wild", "start")
	g.ui.close_all()
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var w = g.world
	var mid: Vector2 = w.path_poly[int(w.path_poly.size() * 0.36)]
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 125.0
	cam.far = 400.0
	var at := Vector3(0, 0, mid.y)
	cam.transform = Transform3D(Basis(), at + Vector3(0, 120, 40)).looking_at(at)
	cam.current = true
	for c in g.get_children():
		if c is CanvasLayer:
			c.visible = false
	g.hero.visible = false
	# no fog or haze from up here
	for we in g.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.6
	w.add_child(sun)
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("saved")
	quit()
