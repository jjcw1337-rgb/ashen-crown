extends SceneTree
## The living grass in the game: Act I's camp, moor and fort get the 3D grass (several species, both
## LODs, woodland undergrowth near the trees, none on the road); the touch field is on outdoors and
## follows the camera; the hero, partners, monsters and pets touch it; an attack's impact frame throws an
## arc; Fx rings shove it; A2 keeps its own grass and the field is off there. Prints [G] lines.
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
	g.difficulty = 0
	for zone in ["town", "wild", "lair"]:
		await g.load_zone(0, zone, "start")
		await process_frame
		var w = g.world
		var species := {}
		var lods := {}
		var clumps := 0
		var painted := 0
		for n in g.get_tree().get_nodes_in_group("grass"):
			if n.has_meta("grass3d"):
				var nm := String(n.name)
				var sp := nm.split("_")[3].rstrip("0123456789")
				species[sp] = true
				lods[int(n.get_meta("grass3d"))] = true
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
		check(g.grass_field.enabled, "%s: touch field on" % zone)
		if zone == "wild":
			await _moor_checks(w)
	# A2 keeps its own grass, and the field is off there
	g.difficulty = 1
	await g.load_zone(0, "wild", "start")
	await process_frame
	var any3d := false
	for n in g.get_tree().get_nodes_in_group("grass"):
		if n.has_meta("grass3d"):
			any3d = true
	check(not any3d, "A2 road: keeps its own grass")
	check(not g.grass_field.enabled, "A2 road: touch field off")
	print("[G] %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	quit()

func _moor_checks(w) -> void:
	var gf: GrassField = g.grass_field
	# woodland undergrowth near trees, verges by the road, meadow in the open
	var wood := 0
	for p in w.tree_pts.slice(0, 200):
		if float(w.grass_biome(p.x + 1.0, p.y).get("woodland", 0.0)) > 0.4:
			wood += 1
	check(wood > 40, "moor: woodland undergrowth around trees (%d of 200)" % wood)
	var road_bare := 0
	for i in range(0, w.path_poly.size(), 4):
		var rp: Vector2 = w.path_poly[i]
		if w.grass_ground(rp.x, rp.y) <= 0.02:
			road_bare += 1
	check(road_bare * 4 >= w.path_poly.size() * 0.8, "moor: no grass on the road (%d bare samples)" % road_bare)
	# who touches it
	await process_frame
	var movers: Array = g._grass_movers()
	check(movers.has(g.hero), "moor: the hero touches the grass")
	var enemies := 0
	for m in movers:
		if m is Enemy:
			enemies += 1
	check(enemies > 0, "moor: monsters touch the grass (%d)" % enemies)
	# the field follows the camera
	g.hero.global_position += Vector3(20, 0, 0)
	await create_timer(2.0).timeout
	var rect: Vector4 = Vector4(gf._shown_origin.x, gf._shown_origin.y, GrassField.SIZE, 1.0)
	var c := Vector2(rect.x + rect.z * 0.5, rect.y + rect.z * 0.5)
	check(c.distance_to(Vector2(g.cam_target.x, g.cam_target.z + GrassField.AHEAD.z)) < 1.0, "moor: field centred on the camera's target")
	# an attack's impact frame throws an arc; an Fx ring shoves a ring
	gf._events.clear()
	g.hero.atk_style = "over"
	g.hero.atk_dur = 0.6
	g.hero.atk_t = 0.01
	await process_frame
	g.hero.atk_t = 0.59
	await process_frame
	await process_frame
	check(gf._events.size() >= 1, "moor: a swing's impact disturbs the grass (%d events)" % gf._events.size())
	gf._events.clear()
	Fx.ring(w.fx_root, g.hero.global_position, 3.0, Color.WHITE)
	check(gf._events.size() == 1, "moor: an Fx ring shoves the grass")
	g.hero.atk_t = -1.0
	# the wind blends to a new profile
	gf.set_wind("storm", 0.2)
	await create_timer(0.6).timeout
	check(float(gf.wind()["strength"]) > 0.8, "moor: the wind blends to a storm (%.2f)" % float(gf.wind()["strength"]))
	gf.set_wind("moor", 0.01)
