extends SceneTree
## The Mournwater Coast and its islands (coast.gd, isles.gd, ocean.gd): the camp's west gate leads there,
## the coast builds with its sea and five islands, the routes from the dock to each island's jetty are
## about the planned length of open water and clear of land, the islands keep apart, the hero walks the
## headland and the pier but not into the sea, each island's own zone builds with its landmark spots,
## and the sea's surface on the CPU matches what floats on it.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func ms(t0: int) -> int:
	return Time.get_ticks_msec() - t0
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var w = g.world
	var to_coast: Array = w.exits.filter(func(e): return e["to"] == "coast")
	print("[O] camp: west gate exit to the coast %s, arrival from the coast %s" % [to_coast.size() == 1, w.spawns.has("from_coast")])
	var t0 := Time.get_ticks_msec()
	await g.load_zone(0, "coast", "from_town")
	w = g.world
	print("[O] coast built in %d ms: sea %s ocean %s title '%s'" % [ms(t0), w.sea, w.has_node("Ocean"), g.zone_title(0, "coast")])
	var oc: Ocean = w.get_node("Ocean")
	# routes: dock -> each jetty end, open water all the way, about the planned length
	for isle in Isles.ISLANDS:
		var a := Coast.DOCK
		var b := Isles.to_coast(isle, Isles.jetty_end(isle))
		var dist := a.distance_to(b)
		var dry := 0
		for k in 200:
			var p := a.lerp(b, (k + 0.5) / 200.0)
			if Coast.ground(p) > -0.8:
				dry += 1
		print("[O] route to %-20s %.1f m of water (planned %.0f), %d of 200 samples too shallow" % [isle["name"], dist, float(isle["sail"]), dry])
	# islands keep apart: no land of one within 8 m of another
	var close := 999.0
	for i in Isles.ISLANDS.size():
		for j in range(i + 1, Isles.ISLANDS.size()):
			var ci := Isles.centre(Isles.ISLANDS[i])
			var cj := Isles.centre(Isles.ISLANDS[j])
			close = minf(close, ci.distance_to(cj) - float(Isles.ISLANDS[i]["r"]) * 1.08 - float(Isles.ISLANDS[j]["r"]) * 1.08)
	print("[O] narrowest channel between islands: %.1f m" % close)
	# walking: headland yes, pier yes, sea no
	var st: Vector3 = w.spawns["start"]
	var pier := Vector3(4.0, 0, 0)
	var sea := Vector3(-6.0, 0, 6.0)
	print("[O] walk: start blocked %s, pier end blocked %s (deck %.2f), open sea blocked %s, height at pier %.2f" % [w.solid_at(st.x, st.z, 0.3), w.solid_at(pier.x, pier.z, 0.3), w.deck_at(pier.x, pier.z), w.solid_at(sea.x, sea.z, 0.3), w.height_at(pier.x, pier.z)])
	var path: PackedVector3Array = w.find_path(st, w.spawns["dock"])
	print("[O] path from the start to the dock: %d steps" % path.size())
	# the sea surface: CPU height changes with time and stays within the swell
	var y0 := oc.surface_y(-40.0, 10.0)
	await create_timer(1.0).timeout
	var y1 := oc.surface_y(-40.0, 10.0)
	print("[O] surface at sea %.2f -> %.2f m a second later (moves %s), depth there %.1f m, shore distance %.1f m" % [y0, y1, absf(y1 - y0) > 0.005, oc.depth_at(-40.0, 10.0), oc.shore_at(-40.0, 10.0)])
	print("[O] sea rocks for boats: %d" % (w.get_meta("sea_rocks") as Array).size())
	# each island's own zone
	for isle in Isles.ISLANDS:
		t0 = Time.get_ticks_msec()
		await g.load_zone(0, Isles.zone_of(isle["id"]), "start")
		w = g.world
		var pois: Array = w.spawns.keys().filter(func(k): return str(k).begins_with("poi_"))
		var sp: Vector3 = w.spawns["start"]
		var reach := 0
		for k in pois:
			var pp: PackedVector3Array = w.find_path(sp, w.spawns[k])
			if pp.size() > 0:
				reach += 1
		print("[O] %-20s built in %5d ms, start blocked %s, places %s, reachable on foot %d/%d, boat at the jetty %s" % [isle["name"], ms(t0), w.solid_at(sp.x, sp.z, 0.3), pois, reach, pois.size(), g.boat != null])
	t0 = Time.get_ticks_msec()
	await g.load_zone(0, "coast", "from_isle_lost")
	print("[O] back to the coast in %d ms (cached ground and sea map)" % ms(t0))
	await g.load_zone(0, "town", "from_coast")
	print("[O] back in camp at the west gate: %s" % (g.hero.global_position.distance_to(g.world.spawns["from_coast"]) < 3.0))
	quit()
