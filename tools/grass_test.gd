extends SceneTree
## The living grass in the game: Act I's camp and the Verdant Reach get the 3D grass (several species, both
## LODs, woodland undergrowth near the trees, none on the trails); the touch field is on outdoors and
## follows the camera; the hero, partners, monsters and pets touch it; an attack's impact frame throws an
## arc; Fx rings shove it. Prints [G] lines.
##   godot --headless --path . -s tools/grass_test.gd
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	print("[G] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	for zone in ["town", "bg"]:
		await g.load_zone(0, zone, "start")
		await process_frame
		var w = g.world
		var species := {}
		var lods := {}
		var clumps := 0
		var painted := 0
		var modelled := 0
		var chunks := 0
		for n in g.get_tree().get_nodes_in_group("grass"):
			if n.has_meta("grass3d"):
				var nm := String(n.name)
				var sp := nm.split("_")[3].rstrip("0123456789")
				species[sp] = true
				lods[int(n.get_meta("grass3d"))] = true
				chunks += 1
				# the Blender clumps (on the Meshy atlas) are drawn with the textured material
				var mat := (n as GeometryInstance3D).material_override as ShaderMaterial
				if mat and bool(mat.get_shader_parameter("textured")):
					modelled += 1
				if int(n.get_meta("grass3d")) == 0:
					clumps += (n as MultiMeshInstance3D).multimesh.instance_count
			else:
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				for k in Flora.GRASS_TOP.size():
					if mm and mm.mesh == Flora.grass_top(k + 1, {}):
						painted += 1
		check(clumps > 5000, "%s: 3D grass, %d clumps" % [zone, clumps])
		check(species.size() >= 4, "%s: species %s" % [zone, species.keys()])
		check(lods.has(0) and lods.has(1), "%s: both levels of detail" % zone)
		check(painted == 0, "%s: no painted clumps left (%d)" % [zone, painted])
		check(modelled == chunks, "%s: Blender clumps on the Meshy textures (%d of %d chunks)" % [zone, modelled, chunks])
		check(g.grass_field.enabled, "%s: touch field on" % zone)
		if zone == "bg":
			await _forest_checks(w)
			await _shadow_checks()
	print("[G] %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit()

## Ultra: the near grass's shadow comes from a shadows-only twin of each LOD0 chunk on the LOD1 clump; other
## presets have no twins and no grass shadows (nightly 2026-11-03).
func _shadow_checks() -> void:
	var count := func() -> Array:
		var tw := 0
		var lod1 := 0
		var cast := 0
		for n in g.get_tree().get_nodes_in_group("grass"):
			if not n.has_meta("grass3d") or n.is_queued_for_deletion():
				continue
			var gi := n as GeometryInstance3D
			if int(n.get_meta("grass3d")) == 2:
				tw += 1
				if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
					lod1 += 1
			elif gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				cast += 1
		return [tw, lod1, cast]
	var q0: int = g.quality
	g.apply_quality(2)
	await process_frame
	await process_frame
	var before: Array = count.call()
	check(int(before[0]) == 0 and int(before[2]) == 0, "below Ultra: no grass shadow twins, no grass shadows (%s)" % str(before))
	g.apply_quality(3)
	await process_frame
	var ultra: Array = count.call()
	check(int(ultra[0]) > 100 and int(ultra[1]) == int(ultra[0]) and int(ultra[2]) == 0, "Ultra: shadows-only twins on the near grass (%s)" % str(ultra))
	g.apply_quality(2)
	await process_frame
	await process_frame
	var back: Array = count.call()
	check(int(back[0]) == 0, "back to High: the twins are gone (%s)" % str(back))
	g.apply_quality(q0)
	await process_frame

func _forest_checks(w) -> void:
	var gf: GrassField = g.grass_field
	# woodland undergrowth near trees, verges by the trails, meadow in the open
	var wood := 0
	for p in w.tree_pts.slice(0, 200):
		if float(w.grass_biome(p.x + 1.0, p.y).get("woodland", 0.0)) > 0.4:
			wood += 1
	check(wood > 40, "forest: woodland undergrowth around trees (%d of 200)" % wood)
	var trail: PackedVector2Array = w.trails[0] if not w.trails.is_empty() else PackedVector2Array()
	var road_bare := 0
	for i in range(0, trail.size(), 4):
		var rp: Vector2 = trail[i]
		if w.grass_ground(rp.x, rp.y) <= 0.02:
			road_bare += 1
	check(trail.size() > 0 and road_bare * 4 >= trail.size() * 0.8, "forest: no grass on the trail (%d bare samples)" % road_bare)
	# who touches it
	await process_frame
	var movers: Array = g._grass_movers()
	check(movers.has(g.hero), "forest: the hero touches the grass")
	var enemies := 0
	for m in movers:
		if m is Enemy:
			enemies += 1
	check(enemies > 0, "forest: monsters touch the grass (%d)" % enemies)
	# the field follows the camera
	g.hero.global_position += Vector3(20, 0, 0)
	await create_timer(2.0).timeout
	var rect: Vector4 = Vector4(gf._shown_origin.x, gf._shown_origin.y, GrassField.SIZE, 1.0)
	var c := Vector2(rect.x + rect.z * 0.5, rect.y + rect.z * 0.5)
	check(c.distance_to(Vector2(g.cam_target.x, g.cam_target.z + GrassField.AHEAD.z)) < 1.0, "forest: field centred on the camera's target")
	# an attack's impact frame throws an arc; an Fx ring shoves a ring
	gf._events.clear()
	g.hero.atk_style = "over"
	g.hero.atk_dur = 0.6
	g.hero.atk_t = 0.01
	await process_frame
	g.hero.atk_t = 0.59
	await process_frame
	await process_frame
	check(gf._events.size() >= 1, "forest: a swing's impact disturbs the grass (%d events)" % gf._events.size())
	gf._events.clear()
	Fx.ring(w.fx_root, g.hero.global_position, 3.0, Color.WHITE)
	check(gf._events.size() == 1, "forest: an Fx ring shoves the grass")
	g.hero.atk_t = -1.0
	# the wind blends to a new profile
	gf.set_wind("storm", 0.2)
	await create_timer(0.6).timeout
	check(float(gf.wind()["strength"]) > 0.8, "forest: the wind blends to a storm (%.2f)" % float(gf.wind()["strength"]))
	gf.set_wind("default", 0.01)
