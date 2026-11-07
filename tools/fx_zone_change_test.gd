extends SceneTree
## The hero's lingering skill effects (Hero.fxs) go with the zone that held their nodes (triage 2026-11-05): a Demon's
## Molten Fists, then a zone change at once. Before Game.load_zone cleared them, MoltenFistsFx.update touched the freed
## nodes every frame ("Trying to assign invalid previously freed instance", demon_fists_fx.gd:168).
## Usage: godot --headless --path . -s tools/_late.gd -- res://tools/fx_zone_change_test.gd
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "demon")
	g.ui.close_all()
	g.test_allskills = true
	g.hero.mana = 9999.0
	g.hero.cursor = g.hero.global_position + Vector3(0, 0, -4)
	g.hero.use_skill("fists", g.hero.cursor)
	for f in 20:
		await process_frame
	print("[FZ1] fxs before=", g.hero.fxs.keys(), " ok=", g.hero.fxs.has("fists"))
	await g.load_zone(0, "sandbox", "start")
	while g._busy:
		await process_frame
	for f in 60:
		await process_frame
	print("[FZ2] fxs after=", g.hero.fxs.keys(), " ok=", g.hero.fxs.is_empty())
	quit()
