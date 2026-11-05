extends SceneTree
## A raid's antechamber stash opening on a client (Battlegrounds.stash_fx + Game.chest_lid), then the gates rising
## soon after (close_stashes): every delayed effect must find what it captured still there (triage 2026-11-05: the
## smoke freed itself 0.4 s before its own clean-up ran, "Lambda capture at index 0 was freed" on every client).
## The engine's error can't be seen from the script: run it and look for "Lambda capture" in the output.
## Usage: godot --headless --path . -s tools/_late.gd -- res://tools/stash_fx_test.gd
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var BG = load("res://scripts/battlegrounds.gd")
	await g.load_zone(0, BG.ZONE, "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.bg_mode = true
	var chests: Array = []
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "stash":
			chests.append(it)
	print("[SF1] chests ", chests.size(), " ok=", chests.size() >= 2)
	if chests.size() < 2:
		quit()
		return
	# one opened and left to burn out its whole show (4 s of smoke)
	var a = chests[0]
	g.chest_lid(a, true)
	BG.stash_fx(g, g.world.interactables.find(a))
	# one opened just before the gates rise (its fire and loop go while their own delayed starts are pending)
	var b = chests[1]
	g.chest_lid(b, true)
	BG.stash_fx(g, g.world.interactables.find(b))
	for f in 12:
		await process_frame
	BG.close_stashes(g)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5500:
		await process_frame
	print("[SF2] opened and closed: lid_open a=", a.get_meta("lid_open", false), " b=", b.get_meta("lid_open", false),
		" fire left=", a.get_node_or_null("stash_fire") != null or b.get_node_or_null("stash_fire") != null)
	print("[SF] done (look for 'Lambda capture' above: there must be none)")
	quit()
