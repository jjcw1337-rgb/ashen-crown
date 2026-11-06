extends SceneTree
## Screenshots of Peak Ruins (bg_peak.gd) from the game camera: a spawn crag, a bridge, the courtyard, a portal ledge.
##   godot --path . --resolution 1920x1080 -s tools/_late.gd -- res://tools/peak_shots.gd <outdir>
var g
func _initialize():
	Battlegrounds.map_id = "peak"
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run():
	var out: String = OS.get_cmdline_user_args()[-1]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	while g._busy:
		await process_frame
	g.test_immortal = true
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var spots := {"spawn": g.world.spawns["start"], "bridge": Vector3(-BgPeak.R * 0.5, 0, -BgPeak.R), "court": Vector3(0, 0, 4), "side": Vector3(0, 0, -BgPeak.R)}
	for k in spots:
		var p: Vector3 = spots[k]
		g.hero.global_position = p
		g.cam_target = p
		g.cam_pivot.position = p
		for i in 50:
			await process_frame
		get_root().get_texture().get_image().save_png("%s/%s.png" % [out, k])
		print("[PEAK] saved ", k)
	quit()
