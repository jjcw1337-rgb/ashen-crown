extends SceneTree
## The Plague Doctor (plague.gd): starts with his cane on his mocap body; each skill and his cane attack play their
## own clip; Toxic Flask poisons without stacking; Volatile Mixture blasts and ignites a cloud; Pestilent Trap waits
## for the first foe and stuns; The Last Epidemic runs both stages, infects, spreads at most INF_JUMPS times and
## collapses; everything is cleared on a class change. Prints [P] lines. Run with --fixed-fps 60.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[P] %s %s" % ["ok  " if ok else "FAIL", what])

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _foe(at: Vector3, still := true) -> Enemy:
	var e: Enemy = g.spawn_enemy("zombie", at, 3)
	e.max_life = 20000.0           # tough enough to watch the poison and infection work on him
	e.life = e.max_life
	if still:
		e.set_process(false)          # a target that stands still
	return e

func _clear_foes() -> void:
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame

## Which whole-body clip the rig is playing now ("" when none).
func _act(h) -> String:
	var r = h.rig
	if r.get("acts") == null or (r.get("acts") as Dictionary).is_empty() or float(r.get("w_act")) < 0.5:
		return ""
	return str(r.get("act_cur"))

## Casts a skill and waits for its whole move; returns the clips seen playing.
func _cast(h, id: String, at: Vector3) -> Array:
	h.cds[id] = 0.0
	h.mana = h.max_mana
	var ok: bool = h.use_skill(id, at)
	var seen := []
	for i in 200:
		await process_frame
		var a := _act(h)
		if a != "" and not seen.has(a):
			seen.append(a)
		if h.atk_t < 0.0 and (h.pd == null or not h.pd.stage2) and i > 5:
			break
	if not ok:
		seen.append("<refused>")
	return seen

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "plague")
	g.test_immortal = true
	await g.load_zone(0, "wild", "start")
	await _clear_foes()
	var h = g.hero
	h.level = 20          # (The Last Epidemic, his ultimate, opens at 20)
	h.recalc()
	h.mana = h.max_mana
	check(h.cls == "plague" and h.pd != null, "a new character can be a Plague Doctor")
	check(h.equipment["weapon"] != null and h.equipment["weapon"]["base"] == "physician_cane", "he starts with his Physician's Cane")
	check(h.rig.has_meta("plague") and str(h.rig.get_meta("meshy")) == "plague", "he wears his own body (the Meshy plague doctor on the mocap rig)")
	var dyed := false
	for mi in h.rig.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			var om := (mi as MeshInstance3D).get_surface_override_material(si) as StandardMaterial3D
			dyed = dyed or (om != null and om.albedo_texture != null and om.albedo_texture.resource_path.ends_with("coat_%s.jpg" % Plague.COLORS))
	check(dyed, "his leather wears its colour scheme (%s)" % Plague.COLORS)
	var acts: Dictionary = h.rig.get("acts")
	check(acts.size() == Plague.ACTS.size(), "every clip he needs is in the model (%d of %d)" % [acts.size(), Plague.ACTS.size()])
	check(h.skill_list().size() == 4 and h.skill_list().map(func(s): return s["id"]) == ["toxic", "volatile", "trap", "epidemic"], "four skills, in bar order")
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	var p0: Vector3 = h.global_position

	# the cane: the three-blow combo plays a clip each
	var e0 := _foe(g.world.free_spot_near(p0 + fwd * 1.6, 0.5))
	var l0: float = e0.life
	var cane_clips := []
	for k in 3:
		h.swipe_attack(e0.global_position)
		for i in 90:
			await process_frame
			var a := _act(h)
			if a != "" and not cane_clips.has(a):
				cane_clips.append(a)
			if h.atk_t < 0.0 and i > 3:
				break
	check(e0.life < l0, "his cane strikes (%.0f -> %.0f)" % [l0, e0.life])
	check(cane_clips.size() == 3, "each blow of the combo has its own clip %s" % [cane_clips])
	var acts2: Dictionary = h.rig.get("acts")
	check(acts2["swipe1"]["clip"] == "peck" and acts2["swipe2"]["clip"] == "flick" and acts2["swipe3"]["clip"] == "censer_slam", "his own moves: Crow's Peck, Vial Flick, Censer Slam")
	var pz: Dictionary = h.pd.poison.get(e0.get_instance_id(), {})
	check(pz.has("srcs") and (pz["srcs"] as Dictionary).has("cane"), "his cane blows poison what they strike")
	check(h.pd.clouds.any(func(c) -> bool: return c["src"] == "cane"), "and the Censer Slam cracks a vial into a little cloud")
	await _clear_foes()

	# Toxic Flask: a lobbed flask, a cloud, poison that ticks and doesn't stack
	var spot: Vector3 = g.world.free_spot_near(p0 + fwd * 7.0, 1.0)
	var e1 := _foe(spot)
	var l1: float = e1.life
	var seen := await _cast(h, "toxic", spot)
	check(seen == ["pd_flask"], "Toxic Flask plays its throw %s" % [seen])
	await frames(30)
	var tox_clouds: int = h.pd.clouds.filter(func(c) -> bool: return c["src"] == "toxic").size()
	check(tox_clouds == 1, "the flask shattered into a cloud (%d)" % tox_clouds)
	check(e1.life < l1, "the flask and cloud hurt the foe in it (%.0f -> %.0f)" % [l1, e1.life])
	check(h.pd.poison.has(e1.get_instance_id()), "he is poisoned")
	# a second flask on the same spot: still one poison from that source
	seen = await _cast(h, "toxic", spot)
	await frames(40)
	var srcs: Dictionary = h.pd.poison[e1.get_instance_id()]["srcs"] if h.pd.poison.has(e1.get_instance_id()) else {}
	check(srcs.size() == 1 and srcs.has("toxic"), "two clouds of one skill poison once, not twice %s" % [srcs.keys()])
	var dps1: float = h.pd._poison_dps("toxic")
	var l1b: float = e1.life
	e1.hit_t = 0.0
	e1.flash_t = 0.0
	await frames(60)
	check(e1.hit_t == 0.0 and e1.flash_t <= 0.0, "poison ticks don't flash him white or make him flinch")
	var lost: float = l1b - e1.life
	check(lost > 0.0 and lost < dps1 * 1.6 * 1.6, "the poison ticks at its rate, not doubled (%.0f in 1 s, %.0f/s each)" % [lost, dps1])

	# Volatile Mixture: a fuse, a blast, and the cloud ignites
	var clouds_before: int = h.pd.clouds.size()
	var l1c: float = e1.life
	seen = await _cast(h, "volatile", spot)
	check(seen == ["pd_volatile"], "Volatile Mixture plays its crouched throw %s" % [seen])
	await frames(90)
	check(e1.life < l1c, "the blast hurts (%.0f -> %.0f)" % [l1c, e1.life])
	check(e1.burn_t > 0.0, "and sets him burning")
	check(clouds_before > 0 and h.pd.clouds.size() < clouds_before, "the blast ignited the poison cloud (%d -> %d)" % [clouds_before, h.pd.clouds.size()])
	e1.take_damage(99999.0, 0.0, p0, 0.0, false)
	await _clear_foes()

	# Pestilent Trap: set, armed, sprung by the first foe; at most two
	var tspot: Vector3 = g.world.free_spot_near(p0 + fwd * -5.0, 1.0)
	seen = await _cast(h, "trap", tspot)
	check(seen == ["pd_trap"], "Pestilent Trap plays its kneel-and-set %s" % [seen])
	check(h.pd.traps.size() == 1, "a trap is set")
	await _cast(h, "trap", tspot + Vector3(3, 0, 0))
	await _cast(h, "trap", tspot + Vector3(-3, 0, 0))
	check(h.pd.traps.size() == 2, "never more than two traps (%d)" % h.pd.traps.size())
	await frames(60)
	var tp: Dictionary = h.pd.traps[0]
	var e2 := _foe(tp["pos"])
	var l2: float = e2.life
	await frames(10)
	check(h.pd.traps.size() == 1, "the first foe on it springs it")
	check(e2.stun_t > 0.0 and e2.life < l2, "stunned and hurt (stun %.1f, %.0f -> %.0f)" % [e2.stun_t, l2, e2.life])
	check(h.pd.clouds.any(func(c) -> bool: return c["src"] == "trap"), "and it vents its cloud")
	e2.take_damage(99999.0, 0.0, p0, 0.0, false)
	await _clear_foes()
	h.pd.clear()

	# The Last Epidemic: two stages, a dome, infection that spreads a limited number of times
	var ring := []
	for k in 10:
		var a := TAU * k / 10.0
		ring.append(_foe(g.world.free_spot_near(h.global_position + Vector3(cos(a), 0, sin(a)) * 4.0, 0.6)))
	seen = await _cast(h, "epidemic", h.global_position)
	check(seen == ["pd_slam", "pd_dome"], "The Last Epidemic plays both stages, the censer smashed then the arms raised %s" % [seen])
	check(not h.pd.dome.is_empty(), "the dome is up")
	await frames(40)
	var inf: int = ring.filter(func(e) -> bool: return h.pd.infected.has(e.get_instance_id())).size()
	check(inf == ring.size(), "everyone inside is infected (%d of %d)" % [inf, ring.size()])
	# the carriers die one after another: the disease can't jump more than INF_JUMPS times
	h.pd.dome = {}
	for e in ring:
		e.take_damage(99999.0, 0.0, p0, 0.0, false)
		await frames(2)
	var crowd := []
	for k in 12:
		crowd.append(_foe(g.world.free_spot_near(h.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 0.5)))
	var c0 := crowd[0] as Enemy
	h.pd.jumps = 0
	h.pd._infect(c0, 0)
	for k in 12:
		for e in crowd:
			if h.pd.infected.has(e.get_instance_id()) and not e.dead:
				e.take_damage(99999.0, 0.0, p0, 0.0, false)
				break
		await frames(3)
	check(h.pd.jumps <= Plague.INF_JUMPS, "infection stops after %d jumps (%d)" % [Plague.INF_JUMPS, h.pd.jumps])
	check(crowd.any(func(e) -> bool: return not e.dead), "so it can't wipe out a crowd on its own (%d of 12 left)" % crowd.filter(func(e) -> bool: return not e.dead).size())
	await _clear_foes()

	# the idle: standing about with the cane away, now and then he peers at a vial; a step ends it
	var st := {"move": 0.0, "atk": -1.0, "draw": 0.0, "hit": 0.0}
	h.moving = false
	h.pd.idle_t = Plague.IDLE_EVERY + 0.5
	h.pd.idle_fidget(st, 0.1)
	var inspecting: bool = st.get("style", "") == "pd_inspect" and float(st["atk"]) > 0.0
	var st2 := {"move": 1.0, "atk": -1.0, "draw": 0.0, "hit": 0.0}
	h.pd.idle_fidget(st2, 0.1)
	check(inspecting and not st2.has("style") and h.pd.fid_a < 0.0, "standing about he takes out a vial to inspect; a step ends it")
	# saving and loading keeps him a plague doctor, with his talents, his cane and his binds
	h.talents = Talents.auto_build("plague", h.level - 1)
	h.recalc()
	g.save_game()
	var saved_t: Dictionary = h.talents.duplicate()
	h.set_class("knight")
	check(g.load_game(), "the save loads")
	h = g.hero
	await frames(5)
	check(h.cls == "plague" and h.pd != null and h.rig.has_meta("plague"), "and he comes back a plague doctor on his own body")
	check(h.talents == saved_t and h.equipment["weapon"]["base"] == "physician_cane" and h.binds.get("Q", "") == "toxic", "with his talents, his cane and Toxic Flask on Q (%d talents, %s, Q %s)" % [h.talents.size(), h.equipment["weapon"]["base"], h.binds.get("Q", "")])
	# clean up: a class change clears everything
	await _cast(h, "trap", tspot)
	h.set_class("knight")
	check(h.pd == null, "a class change clears his flasks, clouds, traps and statuses")
	h.set_class("plague")
	check(h.pd != null and h.rig.has_meta("plague"), "and he comes back as himself")
	print("[P] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
