extends SceneTree
## Screenshots of the party's ready check (UI.party_vote): a partner's trip with Join / Not yet, and your
## own trip waiting on the party. Needs a display. Usage: godot --path . -s tools/vote_shot.gd -- outdir
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(path: String) -> void:
	for f in 20:
		await process_frame
	get_root().get_texture().get_image().save_png(path)

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.ui.party_vote("Jace", g.zone_title(0, "wild"), false)
	await _snap(out + "/vote_join.png")
	g.ui.party_vote("Aldric", g.zone_title(0, "wild"), true)
	g.ui.party_vote_wait(["Jace"])
	await _snap(out + "/vote_wait.png")
	quit()
