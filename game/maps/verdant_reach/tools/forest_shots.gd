extends SceneTree
## Screenshots of the Verdant Reach (BgForest) from the game camera: a starting glade, a camp of each region, the
## two bosses' grounds, the stream's bridge and the middle, and ForestLife's places (a shrine, the mushroom woods' heart). `-- outdir` (needs a display).
var g
var out := "user://forest_shots"

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func shot(name: String, p: Vector2) -> void:
	var y: float = g.world.height_at(p.x, p.y)
	g.hero.global_position = Vector3(p.x, y, p.y)
	g.cam_target = g.hero.global_position
	g.cam_pivot.position = g.hero.global_position
	for i in 40:
		await process_frame
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[SHOT] ", out.path_join(name + ".png"))

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.hide_title()
	g.hero.set_class("archer")
	g.hero.start_run()
	g.bg_mode = true
	g.test_immortal = true
	await g.load_zone(0, "bg", "start")
	var F = load("res://game/maps/verdant_reach/verdant_reach.gd")
	if OS.get_cmdline_user_args().has("keyart"):
		# the lobby's Battlegrounds art: no HUD, the camera a little further out, the hero out of the way
		g.ui._set_hud(false)
		g.ui.hint_lbl.visible = false
		g.ui.zone_lbl.visible = false
		g.hero.visible = false
		for k in [["key_mush", Vector2(-48, 40)], ["key_elf", Vector2(50, -44)], ["key_ruins", Vector2(8, 24)], ["key_stream", Vector2(18, 40)]]:
			await shot(k[0], k[1])
		quit(0)
		return
	await shot("glade_sw", F.SPAWNS[0] + Vector2(4, -4))
	await shot("stream", Vector2(20, -20))
	# ForestLife's places: the mushroom woodland's heart, a crystal shrine, a meadow by the stream
	await shot("mush_heart", F.MUSH_C + Vector2(6, 4))
	var L = load("res://game/maps/verdant_reach/forest_life.gd")      # (at run time: a static reference compiles it before Sfx exists)
	var spots: Array = L.shrines
	print("[LIFE] shrines ", spots, " flower clumps ", L.flower_pts.size() * 5)
	if not spots.is_empty():
		await shot("shrine", spots[0] + Vector2(0, 3))
	await shot("meadow", Vector2(30, 30))
	# (the bosses last: their intro cards hold the screen a while)
	for id in ["sporefall", "shadeleaf", "sundered", "nightwhisper", "brookside", "barrow", "heartwood", "rootknot", "rimewood", "frostfang", "grotto"]:
		for c in F.CAMPS:
			if c["id"] == id:
				await shot("camp_" + c["id"], c["at"] + Vector2(0, float(c["r"]) * 0.8))
	quit(0)
