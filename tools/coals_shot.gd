extends SceneTree
## Close-up frames of what burns in the camp waypoint's braziers (BrazierCoals): the stones, crystals, crack glow
## and sparks, to judge their look and motion. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --fixed-fps 30 --path . -s tools/coals_shot.gd -- outdir [frames] [step] [view] [quality]
## view: bowl (one brazier from 1.3 m, looking down into the bowl) | close (the brazier at eye height, 2 m off) |
## pair (two braziers and the crystal behind) | top (straight down into the bowl). quality 0..3 (the graphics
## preset; the software renderer is slow, Low is the default). Saves outdir/coals_NN.png.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/coals"
	var frames := int(a[1]) if a.size() > 1 else 4
	var step := int(a[2]) if a.size() > 2 else 6
	var view: String = a[3] if a.size() > 3 else "bowl"
	var quality := int(a[4]) if a.size() > 4 else 0
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	g.apply_quality(quality)
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.hide_title()
	var grand: Node3D = null
	for n in g.world.find_children("*", "WaypointGrand", true, false):
		grand = n
	if grand == null:
		print("[S] no grand waypoint")
		quit(1)
		return
	var braz: Array = []
	for n in grand.get_children():
		if str(n.name).begins_with("brazier"):
			braz.append(n)
	braz.sort_custom(func(x, y): return x.global_position.z > y.global_position.z)   # front ones first
	var b: Node3D = braz[0]
	g.hero.global_position = grand.global_position + Vector3(0, 0, 9)   # out of the way, but near enough to wake it
	var cam := Camera3D.new()
	get_root().add_child(cam)
	var bowl := b.global_position + Vector3(0, BrazierCoals.FLOOR_Y + 0.08, 0)
	var away := (b.global_position - grand.global_position)
	away.y = 0
	away = away.normalized()
	var side := Vector3(away.z, 0, -away.x)
	match view:
		"pair":
			var focus := grand.global_position + Vector3(0, 1.6, 2.2)
			cam.global_position = focus + Vector3(0, 2.2, 6.5)
			cam.fov = 45.0
			cam.look_at(focus, Vector3.UP)
		"close":
			var focus := b.global_position + Vector3(0, 1.45, 0)
			cam.global_position = focus + away * 2.0 + Vector3(0, 0.55, 0) + side * 0.6
			cam.fov = 40.0
			cam.look_at(focus, Vector3.UP)
		"top":
			cam.global_position = bowl + Vector3(0.001, 1.6, 0)
			cam.fov = 32.0
			cam.look_at(bowl, Vector3.UP)
		_:
			cam.global_position = bowl + away * 0.95 + side * 0.45 + Vector3(0, 0.95, 0)
			cam.fov = 38.0
			cam.look_at(bowl, Vector3.UP)
	cam.current = true
	g.ui.visible = false      # no HUD or zone banner over the bowl
	for f in 45:
		await process_frame
	for i in frames:
		for f in step:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/coals_%02d.png" % [out, i])
		print("[S] saved frame ", i)
	quit()
