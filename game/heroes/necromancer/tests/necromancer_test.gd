extends SceneTree
## The Necromancer (game/heroes/necromancer/): his Meshy body on the mocap player with his scythe-staff in hand, his
## binds; Bone Bolt flies and strikes (and pierces into the next foe); Graveyard rises at the pointer (its site: the
## waypoint's floor and guardian, gravestones, the risen dead), its dead strike the foes inside every beat and slow
## them, a foe outside is left alone, and after its time it crumbles and is gone. With a folder after the script,
## shots from the game camera go there (idle, Bone Bolt, the graveyard risen and fighting).
## Run: godot --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/necromancer/tests/necromancer_test.gd [out_dir]
var g
var fails := 0
var out := ""

func _initialize():
	for a in OS.get_cmdline_user_args():
		if not str(a).begins_with("res://"):
			out = str(a)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	print("[NECRO] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1

func secs(t: float) -> void:
	for i in int(t * 60.0):
		await process_frame

func shot(name: String) -> void:
	if out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(out.path_join(name))

func pack(at: Vector3, n: int, spread := 1.4) -> Array:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	var list := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3((i - n * 0.5) * spread, 0, randf_range(-0.4, 0.4)), 1)
		e.max_life = 5000.0
		e.life = 5000.0
		e.speed = 0.0
		list.append(e)
	return list

func cast(id: String, aim: Vector3) -> bool:
	var h = g.hero
	var n := 0
	while h.atk_skill != "" and n < 600:
		await process_frame
		n += 1
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	return h.use_skill(id, aim)

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "necromancer")
	g.ui.close_all()
	while g._busy:
		await process_frame
	var h = g.hero
	h.set_level(10)
	g.test_immortal = true
	var anim: AnimationPlayer = h.rig.find_child("AnimationPlayer", true, false)
	check(h.cls == "necromancer" and h.rig.has_meta("necromancer"), "the Necromancer's body")
	check(anim != null and anim.has_animation("slam") and anim.has_animation("cast_quick") and anim.has_animation("run"), "his clips (%s)" % (str(anim.get_animation_list().size()) if anim != null else "none"))
	var staff := h.equipment.get("weapon", {}) as Dictionary
	check(str(staff.get("base", "")) == "grave_scythe", "his scythe-staff in hand (%s)" % str(staff.get("base", "")))
	# (a hero with fewer than six of his own: the first on the right mouse and leading the hotkeys, Hero.default_binds)
	check(str(h.binds.get("rmb", "")) == "bone_bolt" and h.binds.values().has("graveyard"), "Bone Bolt on the right mouse, Graveyard on the bar (%s)" % str(h.binds))
	h._face(Vector3(0, 0, -1))
	await secs(1.0)
	await shot("necro_idle.png")
	# Bone Bolt: the first in line is struck, and it flies on through into the one behind
	var line := []
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	for i in 2:
		var e = g.spawn_enemy("zombie", h.global_position + Vector3(0, 0, -5.0 - 2.5 * i), 1)
		e.max_life = 5000.0
		e.life = 5000.0
		e.speed = 0.0
		line.append(e)
	var l0: float = line[0].life
	var l1: float = line[1].life
	check(await cast("bone_bolt", line[0].global_position), "Bone Bolt cast")
	await secs(0.32)
	await shot("necro_bone_bolt.png")
	await secs(1.0)
	check(line[0].life < l0, "it struck the first (%d)" % int(l0 - line[0].life))
	check(line[1].life < l1, "and pierced into the one behind (%d)" % int(l1 - line[1].life))
	# Graveyard: four foes inside, one well outside
	var mid: Vector3 = h.global_position + Vector3(0, 0, -8)
	var inside: Array = await pack(mid, 4, 1.6)
	var far = g.spawn_enemy("zombie", mid + Vector3(14, 0, 0), 1)
	far.max_life = 5000.0
	far.life = 5000.0
	far.speed = 0.0
	var before: Array = inside.map(func(e): return e.life)
	var f0: float = far.life
	check(await cast("graveyard", mid), "Graveyard cast")
	await secs(1.0)
	var site: Node = null
	for n in g.world.fx_root.get_children():
		if n is GraveyardSite:
			site = n
	check(site != null, "the graveyard rises where he aimed")
	if site != null:
		check(site.props.size() >= 8 and site.dead.size() == 4, "its floor, guardian, pillars, gravestones and braziers (%d) and four risen dead (%d)" % [site.props.size(), site.dead.size()])
	await secs(1.8)
	await shot("necro_graveyard.png")
	await secs(1.4)
	await shot("necro_graveyard_strike.png")
	var struck := 0
	for i in inside.size():
		if inside[i].life < float(before[i]):
			struck += 1
	check(struck >= 3, "its dead struck the foes inside (%d of 4)" % struck)
	check(inside.any(func(e): return e.slow_t > 0.0), "and the grave chill slows them")
	check(far.life >= f0, "a foe outside it is left alone")
	await secs(6.0)
	var gone := true
	for n in g.world.fx_root.get_children():
		if n is GraveyardSite:
			gone = false
	check(gone, "after its time the dead crumble and it's gone")
	print("[NECRO] done, %d failed" % fails)
	quit(1 if fails else 0)
