extends SceneTree
## The Plague Doctor (plague.gd): starts with his cane on his mocap body; each skill and his cane attack play their
## own clip; Pestilence Vial poisons without stacking; Swarmcraft flies to its point, bites, harries, can be sent on
## twice and starts its cooldown when it goes home; Corpse Bloom pulses and snares a foe that stood still; three
## different skills make a foe Feverish; Fog of the Forgotten hops him back and speeds him in it; Transfusion soaks
## damage, cleanses and heals at most its cap; The Last Experiment runs both stages, bursts into a quarantine with its
## creature and ends, and bursts small when interrupted; old binds migrate; everything is cleared on a class change.
## Prints [P] lines. Run with --fixed-fps 60.
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

## PvP (PvpObjects): other players can break his bloom, his vat while he cranks it, and the creature; their blows are
## counted on his game (the server lets each player's through once per GAP), and on another player's screen each is
## a stand-in to strike that follows the count and goes when it breaks.
func _pvp_objects(h: Hero, op: Vector3) -> void:
	for i in 120:
		if h.daze_t <= 0.0 and h.atk_t < 0.0:
			break
		await process_frame        # (the stun that interrupted the last crank)
	await _cast(h, "bloom", op)
	var bo: Dictionary = h.pd.blooms[0] if not h.pd.blooms.is_empty() else {}
	var boid: int = int(bo.get("oid", 0))
	var full: int = int(PvpObjects.HITS["bloom"])
	check(boid > 0 and int(bo.get("left", 0)) == full, "his bloom can be struck in PvP (id %d, %d blows)" % [boid, int(bo.get("left", 0))])
	var bnode: Node = bo.get("node")
	h.pd.obj_hit(boid, 7)
	check(int(bo["left"]) == full - 1 and is_instance_valid(bnode) and float(bnode.get("hit_t")) < 0.1, "a blow counts and it recoils (%d left)" % int(bo["left"]))
	for k in full - 1:
		h.pd.obj_hit(boid, 8 + k)
	check(h.pd.blooms.is_empty() and is_instance_valid(bnode) and float(bnode.get("dying")) >= 0.0, "the last blow kills it before its time: it withers away")
	var last := {}
	var a1 := PvpObjects.allow(last, 7, 3, 1, 10.0)
	var a2 := PvpObjects.allow(last, 7, 3, 1, 10.1)
	var a3 := PvpObjects.allow(last, 8, 3, 1, 10.1)
	var a4 := PvpObjects.allow(last, 7, 3, 1, 10.0 + PvpObjects.GAP)
	check(a1 and not a2 and a3 and a4, "the server lets one player's blows on it through once per %.1f s, each player's apart" % PvpObjects.GAP)
	# the vat while he cranks it: broken, the experiment fails (no burst, no quarantine) and his crank stops
	h.cds["experiment"] = 0.0
	h.mana = h.max_mana
	h.use_skill("experiment", op)
	for i in 120:
		await process_frame
		if h.atk_skill == "crank" and h.atk_t >= 0.0:
			break
	await frames(10)
	var void_id: int = int(h.pd.lab.get("oid", 0))
	check(void_id > 0 and int(h.pd.lab.get("stage", 0)) == 1, "his vat can be struck while he cranks it (id %d)" % void_id)
	var vnode: Node = h.pd.lab.get("node")
	for k in int(PvpObjects.HITS["vat"]):
		h.pd.obj_hit(void_id, 20 + k)
	check(h.pd.lab.is_empty() and not (h.atk_t >= 0.0 and h.atk_skill == "crank"), "broken, the experiment fails and his crank stops")
	check(is_instance_valid(vnode) and float(vnode.get("dying")) >= 0.0 and float(vnode.get("burst_t")) < 0.0, "its glass bursts, but no quarantine floods out")
	await frames(30)
	# the creature: killed, the quarantine ends
	await _cast(h, "experiment", op)
	var coid: int = int(h.pd.lab.get("coid", 0))
	check(coid > 0 and int(h.pd.lab.get("stage", 0)) == 2 and int(h.pd.lab.get("cleft", 0)) == int(PvpObjects.HITS["creature"]), "the creature out of it can be struck (id %d)" % coid)
	for k in int(PvpObjects.HITS["creature"]):
		h.pd.obj_hit(coid, 40 + k)
	check(h.pd.lab.is_empty(), "killed, the quarantine ends")
	await frames(10)
	h.pd.clear()
	# another player's screen: a ghost of him in the Battlegrounds puts a stand-in on each of his things
	var pup := Hero.new()
	pup.puppet = true
	pup.peer_id = 77
	pup.name = "Ally77"
	g.add_child(pup)
	pup.setup(g)
	pup.apply_net_gear(h.net_gear())
	pup.global_position = h.global_position + Vector3(3, 0, 0)
	pup.net_has = true
	if pup.pd == null:
		pup.pd = Plague.new(pup)
	pup.pd.remote("bloom|%s|3.50|5" % Plague._v(op))
	await frames(2)
	check(_stand_in(5) == null, "in co-op his partners get no stand-ins (nothing of his is theirs to break)")
	pup.pd.clear()
	g.net.players[77] = {"hero": pup, "name": "Rival"}
	g.bg_mode = true
	pup.pd.remote("bloom|%s|3.50|6" % Plague._v(op))
	await frames(2)
	var sp = _stand_in(6)
	check(sp != null and sp.pvp_owner == 77 and sp.pvp_pid == 0 and is_equal_approx(sp.life, float(full)) and not sp.rig.visible,
		"in the Battlegrounds his bloom has an unseen stand-in to strike (%s)" % (sp.display_name if sp != null else "none"))
	var o := Vector3(op.x, op.y + 12.0, op.z + 6.0)
	check(sp != null and g.pick_enemy(o, (op + Vector3(0, 0.8, 0) - o).normalized()) == sp, "the pointer picks it like a monster")
	pup.pd.remote("obj|6|1")
	await frames(1)
	check(sp != null and is_instance_valid(sp) and is_equal_approx(sp.life, 1.0), "it follows the blows left he sends")
	pup.pd.remote("obj|6|0")
	await frames(2)
	check(not is_instance_valid(sp) or sp.is_queued_for_deletion(), "and goes with the bloom when it breaks")
	check(pup.pd.blooms.is_empty(), "the bloom dies there too")
	pup.pd.remote("vat|%s|8.00|9" % Plague._v(op))
	await frames(2)
	var vs = _stand_in(9)
	var had_vat: bool = vs != null
	pup.pd.remote("burst|8.00|10")
	await frames(2)
	var cs = _stand_in(10)
	check(had_vat and (not is_instance_valid(vs) or vs.is_queued_for_deletion()) and cs != null, "his vat has one while he cranks, and the creature once it's out")
	pup.pd.remote("obj|10|0")
	await frames(2)
	check(pup.pd.lab.is_empty() and (not is_instance_valid(cs) or cs.is_queued_for_deletion()), "killed, its quarantine ends there too")
	pup.pd.remote("bloom|%s|3.50|11" % Plague._v(op))
	await frames(2)
	g.net.players.erase(77)
	await frames(2)
	var gone = _stand_in(11)
	check(gone == null or gone.is_queued_for_deletion(), "a stand-in goes when its owner leaves")
	g.bg_mode = false
	pup.pd.clear()
	pup.queue_free()
	await _clear_foes()

func _stand_in(oid: int):
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_obj == oid and not e.is_queued_for_deletion():
			return e
	return null

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
		if h.atk_t < 0.0 and i > 5:
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
	h.level = 12
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
	h.level = 20
	h.recalc()
	check(h.skill_list().size() == 6 and h.skill_list().map(func(s): return s["id"]) == ["toxic", "swarm", "bloom", "fog", "transfusion", "experiment"], "six skills, in bar order")
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

	# Pestilence Vial: a lobbed vial, a pool, poison that ticks and doesn't stack
	var spot: Vector3 = g.world.free_spot_near(p0 + fwd * 7.0, 1.0)
	var e1 := _foe(spot)
	var l1: float = e1.life
	var seen := await _cast(h, "toxic", spot)
	check(seen == ["pd_flask"], "Pestilence Vial plays its throw %s" % [seen])
	await frames(30)
	var tox_clouds: int = h.pd.clouds.filter(func(c) -> bool: return c["src"] == "toxic").size()
	check(tox_clouds == 1, "the vial shattered into a pool (%d)" % tox_clouds)
	check(e1.life < l1, "the vial and pool hurt the foe in it (%.0f -> %.0f)" % [l1, e1.life])
	check(h.pd.poison.has(e1.get_instance_id()), "he is poisoned")
	# a second flask on the same spot: still one poison from that source
	seen = await _cast(h, "toxic", spot)
	await frames(40)
	var srcs: Dictionary = h.pd.poison[e1.get_instance_id()]["srcs"] if h.pd.poison.has(e1.get_instance_id()) else {}
	check(srcs.size() == 1 and srcs.has("toxic"), "two pools of one skill poison once, not twice %s" % [srcs.keys()])
	var dps1: float = h.pd._poison_dps("toxic")
	var l1b: float = e1.life
	e1.hit_t = 0.0
	e1.flash_t = 0.0
	await frames(60)
	check(e1.hit_t == 0.0 and e1.flash_t <= 0.0, "poison ticks don't flash him white or make him flinch")
	var lost: float = l1b - e1.life
	check(lost > 0.0 and lost < dps1 * 1.6 * 1.6, "the poison ticks at its rate, not doubled (%.0f in 1 s, %.0f/s each)" % [lost, dps1])

	e1.take_damage(99999.0, 0.0, p0, 0.0, false)
	await _clear_foes()
	h.pd.clear()

	# Swarmcraft: it flies to its point (not homing), bites and harries, is sent on twice, cooldown when it goes home
	var sspot: Vector3 = g.world.free_spot_near(p0 + fwd * 8.0, 1.0)
	var es := _foe(sspot)
	var ls: float = es.life
	seen = await _cast(h, "swarm", sspot)
	check(seen == ["pd_swarm"], "Swarmcraft plays its release %s" % [seen])
	check(not h.pd.swarm.is_empty(), "the swarm is out")
	check(h.cds["swarm"] == 0.0, "its cooldown waits for it to come home")
	await frames(150)
	check(es.life < ls, "it bites what's in it (%.0f -> %.0f)" % [ls, es.life])
	check(es.chill_t > 0.0, "and harries it (slowed: %.2f s)" % es.chill_t)
	var mana_before: float = h.mana
	var left0: int = int(h.pd.swarm["left"])
	h.use_skill("swarm", sspot + Vector3(4, 0, 0))
	check(int(h.pd.swarm["left"]) == left0 - 1 and absf(h.mana - mana_before) < 0.01, "using it again sends it on, free (%d left)" % int(h.pd.swarm["left"]))
	h.use_skill("swarm", sspot)
	h.use_skill("swarm", sspot + Vector3(-4, 0, 0))
	check(int(h.pd.swarm["left"]) == 0, "but only twice")
	# an area blow on it (anyone's slam or nova, Fx.ring) blows it apart for a moment
	Fx.ring(g.world.fx_root, h.pd.swarm["pos"], 2.0, Color(1, 1, 1))
	check(float(h.pd.swarm["scatter"]) > 0.0, "an area blow on it scatters it (%.1f s)" % float(h.pd.swarm["scatter"]))
	await frames(int(Plague.SWARM_T * 60.0))
	check(h.pd.swarm.is_empty() and h.cds["swarm"] > 1.0, "it goes home and the cooldown starts (%.1f s)" % h.cds["swarm"])

	# Corpse Bloom: grows, pulses, snares a foe that stood still
	var bspot: Vector3 = es.global_position
	var lb: float = es.life
	es.stun_t = 0.0
	var blows := [0]
	var count_blow := func(_p: Vector3, _r: float) -> void: blows[0] += 1
	Fx.area_listeners.append(count_blow)
	seen = await _cast(h, "bloom", bspot)
	check(seen == ["pd_bloom"], "Corpse Bloom plays its kneel %s" % [seen])
	check(h.pd.blooms.size() == 1, "the bloom is planted")
	await frames(int((Plague.BLOOM_GROW + Plague.BLOOM_EVERY + 0.2) * 60.0))
	check(es.life < lb, "its pulse hurts (%.0f -> %.0f)" % [lb, es.life])
	check(es.stun_t > 0.0, "and its roots hold a foe who stood still (%.2f s)" % es.stun_t)
	check(blows[0] == 0, "its pulse is no area blow (it would scatter his own swarm)")
	Fx.area_listeners.erase(count_blow)

	# Fever: three different skills on one foe
	h.pd.blight.erase(es.get_instance_id())
	h.pd._add_blight(es, "toxic")
	h.pd._add_blight(es, "toxic")
	var b1: Dictionary = h.pd.blight.get(es.get_instance_id(), {})
	check(not b1.is_empty() and (b1["srcs"] as Dictionary).size() == 1 and float(b1["fever"]) <= 0.0, "the same skill twice is one Blight stack")
	h.pd._add_blight(es, "swarm")
	var marks: Node = es.get_node_or_null("pd_blight")
	check(marks != null and marks.get_child_count() == 2, "a Blight mark over him per stack (%d)" % (marks.get_child_count() if marks != null else -1))
	h.pd._add_blight(es, "bloom")
	var bl: Dictionary = h.pd.blight.get(es.get_instance_id(), {})
	check(not bl.is_empty() and float(bl["fever"]) > 0.0, "three different skills make him Feverish")
	check(es.get_node_or_null("pd_blight") == null and es.get_node_or_null("pd_fever") != null, "the marks burst into the Fever (no marks left behind)")
	check(es.get_node_or_null("pd_fever") != null, "and everyone can see it on him")
	es.take_damage(99999.0, 0.0, p0, 0.0, false)
	await _clear_foes()
	h.pd.clear()

	# Fog of the Forgotten: the censer down, the hop back, quicker inside
	var fp0: Vector3 = h.global_position
	seen = await _cast(h, "fog", fp0 + fwd * 5.0)
	await frames(30)
	check(seen == ["pd_fog"], "Fog of the Forgotten plays its censer dash %s" % [seen])
	check(h.pd.fogs.size() == 1, "the fog is down")
	var hop: float = Vector2(h.global_position.x - fp0.x, h.global_position.z - fp0.z).length()
	check(hop > 2.5, "he hops back from the pointer (%.1f m)" % hop)
	check(h.pd._in_fog(h.global_position) and h.pd.speed_mult() > 1.1, "and moves faster in it (x%.2f)" % h.pd.speed_mult())
	# monsters lose track of him in it from beyond its reach (as of a Demon in the Underworld)
	var far_pos: Vector3 = h.global_position + fwd * 9.0
	check(h.pd.hidden_from_monster(far_pos) and not h.pd.hidden_from_monster(h.global_position + fwd * 2.0), "monsters beyond %.1f m can't see him in it; nearer ones can" % Plague.FOG_SEE)
	var mz := _foe(g.world.free_spot_near(far_pos, 0.6), false)
	mz.aggro = true
	await frames(3)
	check(not mz.aggro, "a monster after him loses track of him")
	h.pd._reveal_self()
	check(not h.pd.hidden_from_monster(far_pos), "until he strikes from it (seen for %.0f s)" % Plague.FOG_REVEAL)
	mz.queue_free()
	h.pd.clear()

	# Transfusion: soaks part of each blow, cleanses, heals at most its cap afterwards
	g.test_immortal = false
	h.life = h.max_life * 0.5
	h.heal_pool = 0.0
	PvpStatus.apply(h, "slow", 2.0, 0.4)
	seen = await _cast(h, "transfusion", h.global_position)
	check(seen == ["pd_transfuse"], "Transfusion plays its shudder %s" % [seen])
	check(not PvpStatus.has(h, "slow"), "it washes out his slows")
	var lt: float = h.life
	h.take_hit(100.0, h.global_position + Vector3(1, 0, 0), "magic", "phys")
	var took: float = lt - h.life
	check(took > 0.0 and took < 80.0, "he takes less with the needle in (%.0f of a 100 blow, before armour)" % took)
	var after_hit: float = h.life
	await frames(int((Plague.TRANS_T + 1.5) * 60.0))
	var healed: float = h.life - after_hit
	check(h.pd.trans.is_empty() and healed > 1.0 and healed <= h.max_life * Plague.TRANS_CAP * 1.25 + 2.0, "what the tanks soaked heals him, within its cap (+%.0f incl. regeneration, cap %.0f)" % [healed, h.max_life * Plague.TRANS_CAP])
	g.test_immortal = true
	h.life = h.max_life

	# PvP statuses on a player: shown on him (PvpStatusFx), and in his state packet for his puppet everywhere else
	h.pvs.clear()
	PvpStatus.apply(h, "snare", 1.0, 1.0)
	PvpStatus.apply(h, "harried", 2.0, 0.25)
	PvpStatus.apply(h, "slow", 2.0, 0.3)
	PvpStatus.apply(h, "reveal", 2.0, 1.0)
	PvpStatus.apply(h, "blight", 6.0, 2.0)
	await frames(2)
	check(h.get_node_or_null("pvs_snare") != null and h.get_node_or_null("pvs_harried") != null and h.get_node_or_null("pvs_slow") != null and h.get_node_or_null("pvs_reveal") != null, "rooted, harried, slowed and revealed show on him")
	var bm: Node = h.get_node_or_null("pd_blight")
	check(bm != null and bm.get_child_count() == 2, "with his Blight marks (%d)" % (bm.get_child_count() if bm != null else -1))
	var pk: PackedFloat32Array = g.net._hero_packet(h)
	var want_bits: int = PvpStatusFx.SNARE | PvpStatusFx.HARRIED | PvpStatusFx.SLOW | PvpStatusFx.REVEAL
	check(pk.size() >= 22 and int(pk[20]) == want_bits and int(pk[21]) == 2, "his state packet carries them for his puppet (%s)" % [pk.slice(20)])
	PvpStatus.apply(h, "blight", 4.0, 3.0)
	await frames(2)
	check(h.get_node_or_null("pd_fever") != null and h.get_node_or_null("pd_blight") == null, "at three the marks burst into Fever")
	h.pvs.clear()
	await frames(2)
	check(h.get_node_or_null("pvs_snare") == null and h.get_node_or_null("pvs_harried") == null and h.get_node_or_null("pvs_reveal") == null and h.get_node_or_null("pd_fever") == null, "and it all goes when they end")

	# The Last Experiment: the vat, the crank, the burst, the quarantine and its creature
	var ring := []
	var espot: Vector3 = g.world.free_spot_near(h.global_position + fwd * 5.0, 1.0)
	for k in 6:
		var a := TAU * k / 6.0
		ring.append(_foe(g.world.free_spot_near(espot + Vector3(cos(a), 0, sin(a)) * 3.0, 0.6)))
	var le: float = (ring[0] as Enemy).life
	var eblows := [0]
	var count_eblow := func(_p: Vector3, _r: float) -> void: eblows[0] += 1
	Fx.area_listeners.append(count_eblow)
	seen = await _cast(h, "experiment", espot)
	check(seen == ["pd_slam", "pd_crank"], "The Last Experiment plays both stages, the vat slammed then cranked %s" % [seen])
	check(not h.pd.lab.is_empty() and int(h.pd.lab["stage"]) == 2 and is_equal_approx(float(h.pd.lab["r"]), Plague.EXP_R), "the full quarantine bursts open (%.1f m)" % float(h.pd.lab.get("r", 0.0)))
	check(eblows[0] == 0, "neither the vat's landing nor its burst is an area blow")
	Fx.area_listeners.erase(count_eblow)
	await frames(60)
	check((ring[0] as Enemy).life < le, "it hurts everyone inside (%.0f -> %.0f)" % [le, (ring[0] as Enemy).life])
	check((ring[1] as Enemy).chill_t > 0.0, "and slows them")
	var vat: Node3D = h.pd.lab["node"]
	check(vat.get("creature") != null, "the homunculus crawls out")
	await frames(int((Plague.EXP_T + 0.3) * 60.0))
	check(h.pd.lab.is_empty(), "and the quarantine ends")
	# interrupted: a stun while he cranks bursts it small
	h.cds["experiment"] = 0.0
	h.mana = h.max_mana
	h.use_skill("experiment", espot)
	for i in 120:
		await process_frame
		if h.atk_skill == "crank":
			break
	await frames(20)
	h.daze_t = 0.6
	await frames(4)
	check(not h.pd.lab.is_empty() and int(h.pd.lab["stage"]) == 2 and is_equal_approx(float(h.pd.lab["r"]), Plague.EXP_R_SMALL), "a stun while he cranks bursts it early and small (%.1f m)" % float(h.pd.lab.get("r", 0.0)))
	await _clear_foes()
	h.pd.clear()
	await _pvp_objects(h, g.world.free_spot_near(h.global_position + fwd * 4.0, 1.0))

	# old binds of the retired skills become the new ones
	var ob := {"E": "volatile", "R": "trap", "F": "epidemic", "Q": "toxic"}
	PlagueSkills.migrate_binds(ob)
	check(ob == {"E": "swarm", "R": "bloom", "F": "experiment", "Q": "toxic"}, "old saves' binds move to the new skills %s" % [ob])

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
	check(h.talents == saved_t and h.equipment["weapon"]["base"] == "physician_cane" and h.binds.get("Q", "") == "toxic", "with his talents, his cane and Pestilence Vial on Q (%d talents, %s, Q %s)" % [h.talents.size(), h.equipment["weapon"]["base"], h.binds.get("Q", "")])
	# clean up: a class change clears everything
	await _cast(h, "bloom", h.global_position + fwd * 3.0)
	h.set_class("knight")
	check(h.pd == null, "a class change clears his vials, pools, blooms and statuses")
	h.set_class("plague")
	check(h.pd != null and h.rig.has_meta("plague"), "and he comes back as himself")
	print("[P] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
