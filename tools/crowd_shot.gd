extends SceneTree
## Screenshots of the arena crowd (games.gd: the game's monsters on the stands, the bosses in the patron's
## box) once its cards are drawn: calm, then roaring. Needs a display. Usage: -- outdir
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(path: String, frames := 20) -> void:
	for f in frames:
		await process_frame
	get_root().get_texture().get_image().save_png(path)

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 1
	await g.load_zone(0, "lair", "start")
	g.ui.close_all()
	var games = g.world.get_meta("games")
	var t0 := Time.get_ticks_msec()
	while games.crowd_cards == null and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	print("[K] crowd cards drawn in %.1f s: %d spectators, %d kinds" % [(Time.get_ticks_msec() - t0) / 1000.0, games.crowd_cards.multimesh.instance_count if games.crowd_cards else 0, games._atlas_kinds.size()])
	var Aur = load("res://scripts/aurelia.gd")
	var c := Vector3(Aur.CENTRE.x, 0, Aur.CENTRE.y)
	g.hero.global_position = c + Vector3(0, 0, -4)
	g.zoom = 1.6
	g.cam_target = g.hero.global_position
	games.excite = 0.15
	games.excite_to = 0.15
	await _snap(out + "/crowd_calm.png", 40)
	games.excite = 1.0
	games.excite_to = 1.0
	await _snap(out + "/crowd_roar.png", 12)
	g.hero.global_position = c + Vector3(0, 0, -16)
	g.zoom = 0.7
	await _snap(out + "/crowd_box.png", 40)
	(games._atlas as ImageTexture).get_image().save_png(out + "/atlas.png")
	quit()
