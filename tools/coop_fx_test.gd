extends SceneTree
## Co-op skill effects (SkillFx), in one process: for every class and every skill in Data.SKILLS, the local hero
## casts it while a puppet of him (a partner's view, Hero.puppet) mirrors his pose and gets every event the way
## a partner would (Net.fx_tap -> SkillFx.decode -> SkillFx.play). Fails if a skill sends no event, if the
## puppet shows nothing for it, if the lingering effects (the tether, the beams, the night, phantoms) don't
## reach the puppet, or if replaying the events on the puppet hurts a monster or changes the puppet's life or
## mana. Prints [X] lines.

var g
var fails := 0
var events: Array = []
var puppet: Hero
const OFF := Vector3(3.0, 0, 0)
## what a partner's copy of each skill must leave in Hero.fxs (the effects that run on)
const LINGER := {"siphon": "tether", "drain": "drain", "night": "night", "phantom": "phantoms", "hurl": "shatter", "grip": "grip", "icharge": "hellrunner", "cslam": "fault", "wrath": "wrath"}

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	current_scene = g
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[X] %s %s" % ["ok  " if ok else "FAIL", what])

func lives(en: Array) -> float:
	var t := 0.0
	for e in en:
		if is_instance_valid(e):
			t += e.life
	return t

func pack(at: Vector3, n: int) -> Array:
	for e in g.enemies_near(at, 60.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3(-1.0 + i * 1.0, 0, 0), 18)
		e.aggro = false
		out.append(e)
	await process_frame
	return out

## The puppet follows the hero's pose each frame, a few metres to the side, as a partner would see it.
func _mirror() -> void:
	if puppet == null or not is_instance_valid(puppet) or g.hero == null:
		return
	var h = g.hero
	puppet.net_pos = h.global_position + OFF
	puppet.net_yaw = h.rig.rotation.y
	var st: Dictionary = h.last_pose.duplicate()
	if st.is_empty():
		st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
	st.erase("time")
	st.erase("phase")
	puppet.net_st = st
	puppet.net_has = true

func _make_puppet() -> void:
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()
	puppet = Hero.new()
	puppet.puppet = true
	puppet.peer_id = 99
	puppet.name = "Ally99"
	g.add_child(puppet)
	puppet.setup(g)
	puppet.apply_net_gear(g.hero.net_gear())
	puppet.global_position = g.hero.global_position + OFF
	_mirror()
	puppet.visible = true

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	process_frame.connect(_mirror)
	g.net.fx_tap = func(w: Dictionary):
		events.append(w)
		if puppet != null and is_instance_valid(puppet):
			SkillFx.play(puppet, SkillFx.decode(g.net, w))
	for cls in Data.CLASSES.keys():
		var args := OS.get_cmdline_user_args()
		if args.has("--classes") and not cls in args[args.find("--classes") + 1].split(","):
			continue
		await g.start_game(false, cls)
		g.ui.close_all()
		await g.travel(0, "wild", "start")
		while g._busy:
			await process_frame
		var h = g.hero
		h.run = RunBuild.new()
		g.test_allskills = true
		h.set_level(20)
		g.test_immortal = true
		g.exit_grace = 1e9    # a hop or dash in a skill must not carry him through a zone exit mid-test
		_make_puppet()
		check(puppet.cls == cls and puppet.puppet, "%s: a puppet of him stands beside him" % cls)
		var root: Node3D = g.world.fx_root
		# (the shared skills on two kinds of body: the knight's and the legless Wraith's)
		for sk in Data.skills_for(cls) + Data.run_skills_for(cls) + (Data.shared_skills() if cls in ["knight", "wraith"] else []):
			var id: String = sk["id"]
			var en: Array = await pack(h.global_position + Vector3(0, 0, -3.5), 3)
			h._face(Vector3(0, 0, -1))
			for k in h.cds.keys():
				h.cds[k] = 0.0
			h.mana = h.max_mana
			h.life = h.max_life
			events.clear()
			var n0 := root.get_child_count()
			var p0 := puppet.get_child_count() + puppet.rig.get_child_count()
			var ok: bool = h.use_skill(id, h.skill_aim(id, en[1].global_position))
			var peak := 0
			var fxs_seen := {}
			for i in (130 if id == "cslam" else (60 if LINGER.has(id) and id != "wrath" else (190 if id == "wrath" else 36))):     # (the fault stays molten 4 s)
				await wait(0.05)
				peak = maxi(peak, root.get_child_count() + g.get_child_count())
				for k in puppet.fxs.keys():
					fxs_seen[k] = true
			if id == "drain":
				h.end_drain()
			await wait(0.2)
			var mine: Array = events.filter(func(w): return str(w["s"]) == id)
			var kinds: Array = mine.map(func(w): return str(w["e"]))
			check(ok and not mine.is_empty(), "%s %s: cast sent %d event(s) %s" % [cls, id, mine.size(), kinds])
			check(peak > n0 or puppet.get_child_count() + puppet.rig.get_child_count() > p0 or fxs_seen.has(LINGER.get(id, "-")),
				"%s %s: the partner's view shows it (%d new nodes)" % [cls, id, peak - n0])
			if LINGER.has(id):
				check(fxs_seen.has(LINGER[id]), "%s %s: its %s reached the puppet" % [cls, id, LINGER[id]])
				check(not puppet.fxs.has(LINGER[id]) or id in ["night", "wrath"], "%s %s: and was let go when it ended" % [cls, id])
			# every event survives the wire: enemies as ids, back to nodes
			for w in mine:
				var d := SkillFx.decode(g.net, w)
				check(d.has("s") and d.has("e") and (not w.has("t") or d["t"] is Array), "%s %s: '%s' decodes" % [cls, id, w["e"]])
			# the replay alone, on a fresh pack by the puppet with the hero far away: no damage, no healing
			var far: Vector3 = h.global_position
			h.global_position = far + Vector3(0, 0, 40.0)
			puppet.net_pos = far + OFF
			puppet.global_position = far + OFF
			h._clear_warlock()
			h.blights.clear()
			DemonSkills.clear(h)        # his lava on the ground would burn the fresh pack
			if h.pd != null:
				h.pd.clear()  # the Plague Doctor's clouds and dome linger where he cast them, over the fresh pack
			var en2: Array = await pack(far + OFF + Vector3(0, 0, -2.5), 3)
			var l0 := lives(en2)
			puppet.life = 50.0
			puppet.mana = 20.0
			for w in mine:
				SkillFx.play(puppet, SkillFx.decode(g.net, w))
			await wait(1.2)
			check(is_equal_approx(lives(en2), l0), "%s %s: replayed on the puppet, the pack is unhurt (%d of %d)" % [cls, id, int(lives(en2)), int(l0)])
			check(is_equal_approx(puppet.life, 50.0) and is_equal_approx(puppet.mana, 20.0), "%s %s: and the puppet's life and mana are untouched" % [cls, id])
			# Frost Volley's storm runs ~5 s (the shatter, the thaw): let both play out, so the next skill's new nodes
			# aren't hidden by the volley's going
			var t_v := Time.get_ticks_msec()
			while (h.fxs.has("frost_volleys") or puppet.fxs.has("frost_volleys")) and Time.get_ticks_msec() - t_v < 9000:
				await wait(0.1)
			if id == "volley":
				await wait(1.2)
			SkillFx.clear(puppet)
			h.global_position = far
			h.end_drain()
			WraithSkills.clear(h)
			DemonSkills.clear(h)
		# the dodge roll (jj: "I never saw the roll in PvP"): his partner sees the puppet tumble
		h.global_position = g.world.free_spot_near(h.global_position, 1.0)
		for e in g.world.enemies_root.get_children():
			e.queue_free()
		await wait(0.6)
		var rolled := false
		var tumble := 0.0
		if load("res://scripts/dodge.gd").start(h, Vector3(1, 0, 0)):
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 450:
				await process_frame
				rolled = rolled or puppet.roll_t >= 0.0
				tumble = maxf(tumble, absf(puppet.rig.rotation.x) + (puppet.rig.position - Vector3.ZERO).length())
		check(rolled and tumble > 0.2, "%s: the dodge roll reached the puppet and it tumbled (%.2f)" % [cls, tumble])
		SkillFx.clear(puppet)
		puppet.queue_free()
		puppet = null
	g.net.fx_tap = Callable()
	# PvP statuses ride in a player's state packet: his puppet on everyone else's screen shows them (PvpStatusFx)
	_make_puppet()
	var hh: Hero = g.hero
	Dodge.cancel(hh) # the preceding roll test must not reject the snare on its invulnerability window
	hh.pvs.clear()
	# This checks packet-driven appearance/removal, not expiry. Leave enough duration for slow
	# first-use frames; the explicit empty packet below is what must remove the visuals.
	PvpStatus.apply(hh, "snare", 10.0, 1.0)
	PvpStatus.apply(hh, "harried", 10.0, 0.25)
	PvpStatus.apply(hh, "blight", 10.0, 3.0)
	puppet.apply_net_state(g.net._hero_packet(hh))
	check(puppet.net_pvs_bits == (PvpStatusFx.SNARE | PvpStatusFx.HARRIED) and puppet.net_pvs_blight == 3,
		"the status packet carries roots, harried and three Blight stacks")
	# Status visuals update in physics, not render callbacks. Two fast process frames can contain no physics tick.
	await physics_frame
	await process_frame
	check(puppet.get_node_or_null("pvs_snare") != null and puppet.get_node_or_null("pvs_harried") != null and puppet.get_node_or_null("pd_fever") != null, "a player's PvP statuses show on his puppet (rooted, harried, Feverish)")
	hh.pvs.clear()
	puppet.apply_net_state(g.net._hero_packet(hh))
	await physics_frame
	await process_frame
	check(puppet.get_node_or_null("pvs_snare") == null and puppet.get_node_or_null("pvs_harried") == null and puppet.get_node_or_null("pd_fever") == null, "and leave it when they end")
	puppet.queue_free()
	puppet = null
	print("[X] done, %d failed" % fails)
	process_frame.disconnect(_mirror)
	g.queue_free()
	for i in 8:
		await process_frame
	quit(1 if fails else 0)
