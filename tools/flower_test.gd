extends SceneTree
## The Act I grass and the rare Sunstar Blooms: the moor gets the 3D grass (grass.gd), a few blooms deep in the
## trees (off the road), and picking one gives +50% experience for 5 minutes, once. Prints [F] lines.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	await wait(0.5)
	var w = g.world
	# Act I's grass is the 3D grass now (grass.gd): count its clumps by species (LOD0 chunks)
	var kinds := {}
	for mmi in g.get_tree().get_nodes_in_group("grass"):
		if mmi.has_meta("grass3d") and int(mmi.get_meta("grass3d")) == 0:
			var sp := String(mmi.name).split("_")[3].rstrip("0123456789")
			kinds[sp] = int(kinds.get(sp, 0)) + (mmi as MultiMeshInstance3D).multimesh.instance_count
	print("[F] 3D grass species: %d of %d, clumps %s" % [kinds.size(), Grass.SPECIES.size(), kinds])
	var blooms: Array = w.interactables.filter(func(t) -> bool: return t.kind == "flower")
	var dists := []
	for b in blooms:
		dists.append(snappedf(w.path_dist(b.global_position.x, b.global_position.z), 0.1))
	print("[F] blooms: %d, metres from the road %s" % [blooms.size(), dists])
	if blooms.is_empty():
		quit()
		return
	var b = blooms[0]
	g.xp_bonus_t = 0.0
	g.hero.global_position = b.global_position + Vector3(0.8, 0, 0)
	g._interact(b)
	var t1: float = g.xp_bonus_t
	var xp0: int = g.hero.xp
	g.gain_kill_xp(100, g.hero.level)
	var gained: int = g.hero.xp - xp0
	g.xp_bonus_t = 10.0
	g._interact(b)
	print("[F] picked: bonus %.0f s, 100 xp kill gave %d, bloom hidden %s, second pick ignored %s" % [t1, gained, not b.get_node("Model").visible, g.xp_bonus_t == 10.0])
	g.ui._process(0.0)
	print("[F] xp bar: ", g.ui.xp_bar.detail)
	quit()
