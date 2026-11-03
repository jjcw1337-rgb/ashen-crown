extends SceneTree
## Screenshots of the antechamber before a raid (jj): the matchup cards under the countdown (BgMatchup) and the
## corner room's stash chest, with a made-up roster of four other raiders. Needs a display.
## Usage: godot --path . -s tools/matchup_shot.gd -- outdir
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.set_level(14)
	var BG = load("res://scripts/battlegrounds.gd")
	await g.load_zone(0, BG.ZONE, "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	# the hero by his antechamber's chest
	var chest = null
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "stash":
			if chest == null or it.global_position.distance_to(g.hero.global_position) < chest.global_position.distance_to(g.hero.global_position):
				chest = it
	if chest != null:
		g.hero.global_position = g.world.free_spot_near(chest.global_position + Vector3(1.6, 0, 1.8), 0.6)
	g.bg_mode = true
	g.bg_raid = {"state": "prep:17", "t": 60.0, "open": [], "len": 1200.0, "portals_at": 300.0, "wait": 17.0}
	g.bg_roster = [{"pid": 2, "cls": "demon", "lvl": 15}, {"pid": 3, "cls": "wraith", "lvl": 12}, {"pid": 4, "cls": "plague", "lvl": 16},
		{"pid": 5, "cls": "doug", "lvl": 9}, {"pid": g.multiplayer.get_unique_id(), "cls": "knight", "lvl": 14}]
	for f in 60:
		BG.hud(g, 1.0 / 60.0)
		await process_frame
	get_root().get_texture().get_image().save_png(out + "/matchup.png")
	print("[MS] matchup saved")
	if chest != null:
		# (no raid server here: what its answer does, Net.cl_bg_stash_ok and the fire for everyone)
		var idx: int = g.world.interactables.find(chest)
		g.net.cl_bg_stash_ok(idx)
		BG.stash_fx(g, idx)
		for f in 18:
			BG.hud(g, 1.0 / 60.0)
			await process_frame
		get_root().get_texture().get_image().save_png(out + "/stash_burst.png")
		for f in 50:
			BG.hud(g, 1.0 / 60.0)
			await process_frame
		get_root().get_texture().get_image().save_png(out + "/matchup_stash.png")
		print("[MS] antechamber stash saved (open: %s, slowed: %s)" % [g.ui.stash_panel.visible, g.hero.stash_slowed])
		# the mark everyone sees on the one who opened it
		g.ui.close_all()
		for f in 90:
			BG.hud(g, 1.0 / 60.0)
			await process_frame
		get_root().get_texture().get_image().save_png(out + "/slowed_mark.png")
		print("[MS] slowed mark saved")
	g.bg_mode = false
	quit()
