extends SceneTree
## Close-up frames of the camp waypoint's blue spirit-fire braziers (FireFx "spirit"), to judge the fire's look and
## movement. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s tools/waypoint_fire_shot.gd -- outdir [frames] [step] [view]
## view: close (one brazier, ~2.5 m off) | pair (two braziers and the crystal behind). Saves outdir/fire_NN.png.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/wpfire"
	var frames := int(a[1]) if a.size() > 1 else 6
	var step := int(a[2]) if a.size() > 2 else 4
	var view: String = a[3] if a.size() > 3 else "close"
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.hide_title()
	var grand: Node3D = null
	for n in g.world.find_children("*", "WaypointGrand", true, false):
		grand = n
	if grand == null:
		print("[F] no grand waypoint")
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
	var focus := b.global_position + Vector3(0, 1.45, 0)
	if view == "pair":
		focus = grand.global_position + Vector3(0, 1.6, 2.2)
		cam.global_position = focus + Vector3(0, 2.2, 6.5)
		cam.fov = 45.0
	else:
		var away := (b.global_position - grand.global_position)
		away.y = 0
		away = away.normalized()
		cam.global_position = focus + away * 2.0 + Vector3(0, 0.55, 0) + Vector3(away.z, 0, -away.x) * 0.6
		cam.fov = 40.0
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	for f in 160:      # the zone's name banner fades first
		await process_frame
	for i in frames:
		for f in step:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/fire_%02d.png" % [out, i])
		print("[F] saved frame ", i)
	quit()
