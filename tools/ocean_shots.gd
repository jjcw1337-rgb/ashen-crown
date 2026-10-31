extends SceneTree
## Screenshots of the Mournwater Coast and its islands (coast.gd, isles.gd, ocean.gd):
##   godot --path . -s tools/ocean_shots.gd -- outprefix [quality 0-3] [only]
## The coast from the game camera on the pier, views across the sea from low over the water (what the
## sailing camera will see), a high view of the whole sea, and each island from its jetty and its landmark.
var g
var cam: Camera3D
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(out: String, name: String, frames := 8) -> void:
	for i in frames:
		await process_frame
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)
func look(from: Vector3, to: Vector3, fov := 50.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		get_root().add_child(cam)
	cam.far = 1600.0
	cam.near = 0.3
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.current = true
func game_cam() -> void:
	if cam:
		cam.current = false
	g.cam.current = true
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var q := int(args[1]) if args.size() > 1 else 2
	var only: String = args[2] if args.size() > 2 else ""
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.test_immortal = true
	g.set_quality(q)
	g.ui.close_all()
	g.ui.visible = false
	var I = load("res://scripts/isles.gd")
	if only == "" or only == "coast":
		await g.load_zone(0, "coast", "dock")
		g.ui.visible = false
		g.hero.global_position = Vector3(8.0, 1.05, 0.5)
		game_cam()
		await shot(out, "pier")
		g.hero.global_position = Vector3(24.0, g.world.height_at(24.0, -3.0), -3.0)
		await shot(out, "shed")
		var lost: Dictionary = I.get_isle("lost")
		var lc: Vector2 = I.centre(lost)
		look(Vector3(6.0, 7.0, 10.0), Vector3(lc.x, 6.0, lc.y))
		await shot(out, "sea_west")
		var ver: Dictionary = I.get_isle("verdant")
		var vc: Vector2 = I.centre(ver)
		var mid: Vector2 = Coast.DOCK.lerp(I.to_coast(ver, I.jetty_end(ver)), 0.55)
		look(Vector3(mid.x + 6.0, 9.0, mid.y + 14.0), Vector3(vc.x, 4.0, vc.y))
		await shot(out, "sailing_to_verdant")
		var bl: Dictionary = I.get_isle("bleak")
		var bj: Vector2 = I.to_coast(bl, I.jetty_end(bl))
		var bdir: Vector2 = (bj - Coast.DOCK).normalized()
		var bp: Vector2 = bj - bdir * 24.0
		look(Vector3(bp.x, 8.0, bp.y) + Vector3(-bdir.y, 0, bdir.x) * 6.0, Vector3(bj.x, 3.0, bj.y) + Vector3(bdir.x, 0, bdir.y) * 40.0)
		await shot(out, "arriving_bleak")
		look(Vector3(-120.0, 520.0, 260.0), Vector3(-120.0, 0.0, 0.0), 55.0)
		await shot(out, "overview", 30)
	for id in I.ids():
		if only != "" and only != id:
			continue
		await g.load_zone(0, I.zone_of(id), "start")
		g.ui.visible = false
		game_cam()
		g.hero.global_position = g.world.spawns["start"]
		await shot(out, "%s_jetty" % id)
		var isle: Dictionary = I.get_isle(id)
		var pois: Array = g.world.spawns.keys().filter(func(k): return str(k).begins_with("poi_"))
		if pois.size() > 0:
			g.hero.global_position = g.world.spawns[pois[0]]
			await shot(out, "%s_%s" % [id, pois[0]])
		# the island from offshore, low, the way you see it sailing in
		var ju: Vector2 = I.jetty_end(isle) + Vector2(60.0, 25.0)
		var jp: Vector3 = I.at(g.world, isle, Vector2.ZERO, ju)
		look(Vector3(jp.x, 10.0, jp.z), Vector3(0, 8.0, 0))
		await shot(out, "%s_offshore" % id)
	quit()
