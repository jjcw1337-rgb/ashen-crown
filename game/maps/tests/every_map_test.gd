extends SceneTree
## Every map in the registry (Maps.all), every zone it declares: the zone loads and builds, the hero stands on it, it
## has its title and arrival line, its music is in the sound bank (or it says it has none), its loading art is there
## if it names one, and it lights without errors. A map script that breaks any of that shows here, by zone.
##   godot --path . --fixed-fps 60 -s tools/_late.gd -- res://game/maps/tests/every_map_test.gd
var g
var fails := 0

func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://every_map_test/"
	g.old_save = "user://every_map_test/absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()

func _process(_dt: float) -> bool:
	if is_instance_valid(g):
		g._intro_skip = true
	return false

func check(ok: bool, what: String) -> void:
	print("[MAPS] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "knight")
	while g._busy:
		await frames(5)
	g.ui.close_all()
	var seen := {}
	for m in Maps.all():
		var c: Dictionary = (m as Script).get_script_constant_map()
		var zones: Array = c.get("ZONES", [])
		check(not zones.is_empty(), "%s declares its zones %s" % [(m as Script).resource_path.get_file(), str(zones)])
		for z in zones:
			check(not seen.has(z), "zone %s is built by one map only" % z)
			seen[z] = true
			check(Maps.of(z) == m, "Maps.of(%s) is its map" % z)
			await g.load_zone(0, z, "start")
			while g._busy:
				await frames(5)
			await frames(30)
			var built: bool = g.world != null and g.world.kind == z and g.cur_zone == z
			var standing: bool = g.hero != null and is_finite(g.world.height_at(g.hero.global_position.x, g.hero.global_position.z)) if built else false
			var mus := Maps.music(z)
			var song := str(mus["song"])
			var art: String = str(c.get("LOADING_ART", ""))
			check(built and standing, "%s loads and builds, the hero standing on it" % z)
			check(Maps.title(z) != "" and Maps.arrive(z).contains(Maps.title(z)), "%s: \"%s\", \"%s\"" % [z, Maps.title(z), Maps.arrive(z)])
			check(song == "" or Sfx.BANK.has("music_" + song), "%s: its music (%s) is in the bank" % [z, song if song != "" else "none"])
			check(art == "" or Maps.loading_art(z) == art, "%s: its loading art (%s)" % [z, art if art != "" else "none"])
			check(Maps.indoor(z) == bool(c.get("INDOOR", false)) and g.indoor() == Maps.indoor(z), "%s: indoor %s" % [z, str(Maps.indoor(z))])
	print("[MAPS] done, %d failed" % fails)
	quit(1 if fails else 0)
