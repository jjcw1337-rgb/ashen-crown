extends SceneTree
## The Storm Wyvern's skills on their objects (Wyvern's kit, Hero.kit): Storm Arc's rules find the chain and strike
## it, Thunder Dive flies its own game there and its rules strike and stun where it lands, Thunderhead's rules keep the
## clouds and strike from them (no more than its most at once), Gale Wings strikes and slows the cone ahead; and each
## one's server check (Skill.server_ok) takes what adds up and refuses what doesn't. Prints [V] lines; it names its
## skill objects, so it runs late:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/wyvern/tests/wyvern_test.gd

var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[V] %s %s" % ["ok  " if ok else "FAIL", what])

func wait(s: float) -> void:
	await create_timer(s).timeout

func dummy(at: Vector3) -> Enemy:
	at.y = g.world.height_at(at.x, at.z)
	var e: Enemy = g.spawn_enemy("zombie", at, 5)
	e.speed = 0.0
	e.max_life = 100000.0
	e.life = e.max_life
	e.scripted = 99.0
	return e

func hurt(e) -> bool:
	return is_instance_valid(e) and e.life < e.max_life

func fresh(h) -> void:
	ClassSkills.clear(h)
	SkillFx.clear(h)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	h.mana = h.max_mana
	h.cds.clear()
	await wait(0.2)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "wyvern")
	await g.load_zone(0, "bg", "start")
	var h = g.hero
	g.test_immortal = true
	g.test_allskills = true
	h.start_run()
	h.level = 12
	h.recalc()
	check(h.cls == "wyvern" and ClassSkills.of("wyvern") == Wyvern, "the wyvern's skills script is Wyvern")
	check(ServerRules.CLASSES.has("wyvern"), "its skills run on the match server (ServerRules.CLASSES)")
	var p0: Vector3 = h.global_position
	var fwd := Vector3(0, 0, -1)

	# Storm Arc: into the first ahead and on through the nearest others
	await fresh(h)
	h._face(fwd)
	var arc := [dummy(p0 + fwd * 4.0), dummy(p0 + fwd * 7.0), dummy(p0 + fwd * 10.0)]
	check(h.use_skill("storm_arc", p0 + fwd * 5.0), "Storm Arc cast")
	await wait(1.2)
	check(arc.all(func(e): return hurt(e)), "the bolt leapt through all three")

	# Thunder Dive: its own game flies it there; its rules strike and stun where it lands
	await fresh(h)
	h.global_position = p0
	var target := dummy(p0 + Vector3(9.0, 0, 0))
	check(h.use_skill("v_dive", target.global_position), "Thunder Dive cast")
	var td: ThunderDive = Wyvern.skill(h, "v_dive")
	check(not td.dive.is_empty(), "its own game holds the flight")
	await wait(1.4)
	check(td.dive.is_empty() and h.global_position.distance_to(p0) > 6.0, "it flew there (%.1f m)" % h.global_position.distance_to(p0))
	check(hurt(target) and target.stun_t > 0.0, "and struck and stunned where it landed")
	check(h.rig == null or (is_zero_approx(h.rig.position.y) and not h.rig.has_meta("fly")), "down on its feet after")
	h.global_position = p0

	# Thunderhead: its rules keep the cloud and strike from it; no more than its most at once
	await fresh(h)
	var under := [dummy(p0 + Vector3(8, 0, 0)), dummy(p0 + Vector3(9, 0, 2))]
	check(h.use_skill("v_cloud", under[0].global_position), "Thunderhead cast")
	var th: Thunderhead = Wyvern.skill(h, "v_cloud")
	await wait(1.6)
	check(th.clouds.size() == 1 and under.any(func(e): return hurt(e)), "its rules hold the cloud; it strikes beneath")
	for i in 2:
		h.cds.erase("v_cloud")
		h.mana = h.max_mana
		h.use_skill("v_cloud", p0 + Vector3(0, 0, 8.0 + i * 3.0))
		await wait(1.3)
	check(th.clouds.size() == int(th.val("most", 2.0)), "no more than its most at once (%d)" % th.clouds.size())
	await wait(5.0)
	check(th.clouds.is_empty(), "and they're gone when their time is up")

	# Gale Wings: the cone ahead struck and slowed, the one behind spared
	await fresh(h)
	h._face(fwd)
	var ahead := dummy(p0 + fwd * 3.0)
	var behind := dummy(p0 - fwd * 4.0)
	check(h.use_skill("v_gale", p0 + fwd * 5.0), "Gale Wings cast")
	await wait(1.2)
	check(hurt(ahead) and ahead.slow_t > 0.0 and not hurt(behind), "the cone ahead struck and slowed, the one behind spared")

	# the server's checks: what adds up is taken, what doesn't is refused
	var far: Vector3 = h.global_position + Vector3(60, 0, 0)
	var here: Vector3 = h.global_position
	var sa: StormArc = Wyvern.skill(h, "storm_arc")
	var gw: GaleWings = Wyvern.skill(h, "v_gale")
	check(sa.server_ok("arc", {"p": here + Vector3(0, 2, 0), "d": fwd}) and not sa.server_ok("arc", {"p": far, "d": fwd}), "Storm Arc: a bolt from its jaws, not from far off")
	check(td.server_ok("land", {"p": here + Vector3(10, 0, 0)}) and not td.server_ok("land", {"p": far}), "Thunder Dive: a landing within a dive, not far off")
	check(th.server_ok("cloud", {"p": here + Vector3(12, 0, 0)}) and not th.server_ok("cloud", {"p": far}), "Thunderhead: a cloud in reach, not far off")
	check(gw.server_ok("gust", {"p": here, "d": fwd}) and not gw.server_ok("gust", {"p": here, "d": Vector3.UP}), "Gale Wings: a gust aimed along the ground only")
	check(not gw.server_ok("cloud", {"p": here}), "a skill takes only its own kind")
	ClassSkills.clear(h)
	print("[V] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
