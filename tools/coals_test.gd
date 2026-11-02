extends SceneTree
## The stones and crystals in the camp waypoint's braziers (BrazierCoals): every brazier has its pile, the four
## piles differ and never repeat a piece within a pile, every stone lies inside its bowl, the glow follows the
## fire's light, the shaders compile, and the fallback pile builds without the library.
## godot --headless --path . -s tools/coals_test.gd
var g
var fails := 0
func ok(cond: bool, what: String) -> void:
	print("[C] ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _settle(n := 4) -> void:
	for f in n:
		await process_frame
	while g._busy:
		await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	await _settle()
	var grand: WaypointGrand = null
	for n in g.world.find_children("*", "WaypointGrand", true, false):
		grand = n
	ok(grand != null, "the camp has the grand waypoint")
	if grand == null:
		print("[C] done, %d failure(s)" % fails)
		quit(1)
		return
	var coals: Array = []
	for b in grand.get_children():
		if str(b.name).begins_with("brazier"):
			var c := b.get_node_or_null("coals")
			ok(c is BrazierCoals, "%s has its coals" % b.name)
			if c is BrazierCoals:
				coals.append(c)
	ok(coals.size() == 4, "four piles (%d)" % coals.size())
	var have_lib := ResourceLoader.exists(BrazierCoals.GLB)
	ok(have_lib, "the library glb is there (%s)" % BrazierCoals.GLB)
	if have_lib:
		ok(BrazierCoals._lib.size() >= 30, "the library holds %d pieces" % BrazierCoals._lib.size())
		var kinds := {}
		for p in BrazierCoals._lib:
			kinds[BrazierCoals._lib[p]["kind"]] = kinds.get(BrazierCoals._lib[p]["kind"], 0) + 1
		ok(kinds.get("rock", 0) >= 8 and kinds.get("frag", 0) >= 8 and kinds.get("cry", 0) >= 6, "stones, fragments and crystals: %s" % str(kinds))
		for p in BrazierCoals._lib:
			if not (BrazierCoals._lib[p].has("l0") and BrazierCoals._lib[p].has("l1")):
				ok(false, "%s has both LODs" % p)
		ok(BrazierCoals._piles.size() == 4, "four settled piles in the glb (%d)" % BrazierCoals._piles.size())
		var sigs := {}
		for k in BrazierCoals._piles.size():
			var pile: Array = BrazierCoals._piles[k]
			ok(pile.size() >= 18, "pile %d has %d pieces" % [k, pile.size()])
			var used := {}
			var crystals := 0
			for it in pile:
				ok(not used.has(it["piece"]), "pile %d uses %s once" % [k, it["piece"]]) if used.has(it["piece"]) else null
				used[it["piece"]] = true
				if str(it["piece"]).begins_with("cry"):
					crystals += 1
			ok(crystals >= 2, "pile %d has %d crystals" % [k, crystals])
			var names := used.keys()
			names.sort()
			var sig := ",".join(PackedStringArray(names))
			ok(not sigs.has(sig), "pile %d differs from the others" % k)
			sigs[sig] = true
		# every vertex of every merged mesh lies in its bowl: inside the lip, above the floor, under the flame's top
		for c in coals:
			var cc: BrazierCoals = c
			for mi in cc.get_children():
				if not (mi is MeshInstance3D) or str(mi.name) == "bed" or str(mi.name) == "haze":
					continue
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				var arr := mesh.surface_get_arrays(0)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var out := 0
				var top := 0.0
				for v in vs:
					if Vector2(v.x, v.z).length() > 0.39 or v.y < BrazierCoals.FLOOR_Y - 0.03 or v.y > BrazierCoals.FLOOR_Y + 0.5:
						out += 1
					top = maxf(top, v.y)
				ok(out == 0, "%s/%s: %d of %d vertices stay in the bowl (top %.2f)" % [cc.get_parent().name, mi.name, vs.size() - out, vs.size(), top])
				ok(top > BrazierCoals.FLOOR_Y + 0.06, "%s/%s rises above the floor" % [cc.get_parent().name, mi.name])
			var tris := 0
			for mi in cc.get_children():
				if mi is MeshInstance3D and str(mi.name).ends_with("_l0"):
					tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
			# full heaps (jj: no reduction in quality): ~50-65 pieces a bowl, LOD1 beyond the LOD0 distance
			ok(tris > 2000 and tris <= 20000, "%s LOD0 is %d triangles" % [cc.get_parent().name, tris])
	# the glow follows the fire's light
	var c0: BrazierCoals = coals[0] if coals.size() > 0 else null
	if c0 != null and c0.fire_light != null:
		var base := float(c0.fire_light.get_meta("base"))
		c0.fire_light.remove_from_group("flicker")
		c0.fire_light.light_energy = base * 0.5
		for f in 20:
			await process_frame
		var low: float = c0.mats[0].get_shader_parameter("fire")
		c0.fire_light.light_energy = base * 1.0
		for f in 20:
			await process_frame
		var high: float = c0.mats[0].get_shader_parameter("fire")
		ok(low < 0.6 and high > 0.9, "the crack glow follows the flame's light (%.2f -> %.2f)" % [low, high])
	else:
		ok(c0 != null and c0.fire_light == null, "no fire light to follow (fallback flicker)")
	# the fallback pile builds without the library
	var fb := BrazierCoals.new()
	g.world.add_child(fb)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	fb._fallback(rng)
	ok(fb.get_child_count() >= 10, "the fallback pile builds (%d parts)" % fb.get_child_count())
	fb.queue_free()
	await _settle(10)
	print("[C] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
