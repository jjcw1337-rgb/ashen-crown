extends SceneTree
## Frames following one camp guard (CampGuard) on his round from a near three-quarter camera: is his walk, his turn
## and his stance right? Needs a display; run with --fixed-fps 30.
##   godot --path . --fixed-fps 30 -s tools/_late.gd -- res://game/maps/camp/tools/guard_clip.gd <outdir> [warden|sentry|ironfist] [frames 240] [every 8] [dist 5]

var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[1] if a.size() > 1 else "/tmp/guard"
	var id: String = a[2] if a.size() > 2 else "warden"
	var frames: int = int(a[3]) if a.size() > 3 else 240
	var every: int = int(a[4]) if a.size() > 4 else 8
	var dist: float = float(a[5]) if a.size() > 5 else 5.0
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.visible = false
	if g.day_night != null:
		g.day_night.fixed = 12.0
	g.hero.global_position = Vector3(0, 0, 22)
	var gd: CampGuard = null
	for n in g.world.find_children("*", "CampGuard", true, false):
		if str((n as CampGuard).def["id"]) == id:
			gd = n
	if gd == null:
		print("[GC] no guard ", id)
		quit()
		return
	var cam := Camera3D.new()
	cam.fov = 40
	get_root().add_child(cam)
	cam.current = true
	var k := 0
	for f in frames:
		await process_frame
		if f % every != 0:
			continue
		var p := gd.global_position
		cam.global_transform = Transform3D(Basis(), p + Vector3(dist * 0.7, dist * 0.55, dist * 0.7)).looking_at(p + Vector3(0, 0.9, 0), Vector3.UP)
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/g_%03d.png" % [out, k])
		k += 1
	print("[GC] frames ", k)
	quit()
