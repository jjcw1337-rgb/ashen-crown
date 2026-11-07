extends SceneTree
## The living camp (jj, 2026-11-04): the traders' thirty moves each and their strolls, people talking to each other
## (CampSocial), the smith's hammer landing on the anvil with the tongs in his other hand (SmithForge), the ravens on
## the roofs (CampRavens, Raven), the chimney smoke, and the World-Tree Island (CampIsland: no way out but the
## waypoint, the ground ending at the edge, the underside, the sky, the orbit camera). Prints [L] lines.
## Run with --fixed-fps 60 (it counts frames).
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[L] %s %s" % ["ok  " if ok else "FAIL", what])

func _vendor(role: String) -> Inter:
	for it in g.world.interactables:
		if it.kind == "vendor" and it.data.get("role", "") == role:
			return it
	return null

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	var w: World = g.world
	g.hero.global_position = Vector3(0, 0, 22)        # out of everyone's way
	# --- the traders' moves
	for role in ForestCamp.ACTS:
		var k := _vendor(role)
		if k == null:
			continue
		var have := 0
		for c in ForestCamp.ACTS[role]:
			if k.anim.has_animation(str(c)):
				have += 1
		check(have >= 28, "%s has %d of their %d moves" % [k.label, have, (ForestCamp.ACTS[role] as Array).size()])
	var alch := _vendor("alch")
	check(not (alch.clips.get("patrol", {}) as Dictionary).is_empty(), "the alchemist strolls (to the waypoint and back)")
	# --- the smith
	var smith := _vendor("smith")
	check(smith.has_meta("forge") and smith.has_meta("tongs"), "the smith has his forge and his tongs")
	smith.set_meta("forging", 999.0)
	smith._clip_t = 999.0               # (he'd pick his next move meanwhile)
	var f: Dictionary = smith.get_meta("forge")
	var anvil: Vector3 = f["anvil"]
	var sk: Skeleton3D = smith.model.find_child("Skeleton3D", true, false)
	var low := 99.0
	var tong_d := 99.0
	for i in 150:
		await process_frame
		var hm: Node3D = SmithForge._hammer(smith, sk)
		var face: Vector3 = hm.global_transform * Vector3(SmithForge.HEAD_FACE, SmithForge.HEAD_AT, 0)
		low = minf(low, face.distance_to(anvil + Vector3(0, 0.06, 0)))
		var tg: Node3D = smith.get_meta("tongs")
		tong_d = minf(tong_d, tg.global_position.distance_to(anvil))
	check(low < 0.25, "his hammer's face comes down on the anvil (%.2f m at the closest)" % low)
	check(tong_d < 0.9, "his tongs hold the work on the anvil (%.2f m)" % tong_d)
	smith.set_meta("forging", 0.0)
	smith._clip_t = 0.0
	# --- the ravens
	var cr = w.get_node_or_null("ravens")
	check(cr != null, "ravens in the camp")
	if cr != null:
		for i in 120:
			await process_frame
		var roofs := 0
		for rs in cr.roosts:
			if not rs["ground"]:
				roofs += 1
		check(cr.ravens.size() >= 5 and roofs >= 10, "%d ravens, %d roosts on the roofs" % [cr.ravens.size(), roofs])
		# one spooked off the ground by a hero walking up
		var gr: Raven = null
		for r in cr.ravens:
			if not r.flying() and r.ground:
				gr = r
		if gr != null:
			g.hero.global_position = gr.at + Vector3(1.5, 0, 0)
			var flew := false
			var landed := false
			for i in 60 * 12:
				await process_frame
				if gr.flying():
					flew = true
				elif flew:
					landed = true
					break
			check(flew and landed, "a raven springs off when a hero comes close, and lands again (%s)" % gr.state)
			g.hero.global_position = Vector3(0, 0, 22)
	# --- people talking
	var cs = w.get_node_or_null("social")
	check(cs != null, "the camp's people talk (CampSocial)")
	if cs != null:
		var seen := 0
		var pairs := {}
		for i in 60 * 180:
			await process_frame
			for c in cs.chats:
				var key := str(c["a"].get_instance_id()) + "+" + str(c["b"].get_instance_id())
				if not pairs.has(key):
					pairs[key] = true
					seen += 1
		check(seen >= 2, "%d conversations in three minutes" % seen)
	# --- smoke
	var smoke := 0
	for n in w.fx_root.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial and ((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("book") != null:
			smoke += 1
	check(smoke >= 3, "smoke rising from the forge, the cauldron and the cookfire (%d)" % smoke)
	# --- the island
	if ForestCamp.ISLAND:
		check(w.island_r > 0.0 and w.get_node_or_null("island") != null, "the camp is the World-Tree Island")
		var outs := 0
		for e in w.exits:
			if str(e["to"]) == "wild":
				outs += 1
		check(outs == 0, "the gates are barred")
		check(g.waypoint_known(0, "wild"), "... and the waypoint takes you to the moor")
		check(w.off_island(ForestCamp.CENTER.x + ForestCamp.ISLAND_R + 4.0, ForestCamp.CENTER.y), "past the edge is the void")
		check(w.grass_ground(ForestCamp.CENTER.x + ForestCamp.ISLAND_R + 2.0, ForestCamp.CENTER.y) == 0.0, "nothing grows past it")
		check(g.env.sky.sky_material == g.space_sky, "the sky is space")
		check(g.zoom_max > 1.5, "the wheel zooms out over the island (%.1f)" % g.zoom_max)
		g.zoom = g.zoom_max
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_MIDDLE
		mb.pressed = true
		g._orbit_input(mb)
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(200, -80)
		g._orbit_input(mm)
		check(absf(g.orbit_yaw) > 0.5 and g.orbit_pitch > 0.2, "dragging the middle mouse turns the camera round the island")
		mb.pressed = false
		g._orbit_input(mb)
		g.zoom = 1.0
		for i in 120:
			await process_frame
		check(absf(g.orbit_yaw) < 0.05, "zoomed back in, it settles back to the game's own view")
	print("[L] done, %d failed" % fails)
	quit()
