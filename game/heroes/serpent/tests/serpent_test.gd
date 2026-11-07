extends SceneTree
## The Frost Serpent's skills on their objects (Serpent's kit, Hero.kit): Frost Breath holds its jaws open and its rules
## beat the cone (latch, beats, end), Glacial Tomb seals then shatters from its rules' tombs, Crushing Coil crushes and
## slows, Rime Lance chills a line and freezes the chilled; and each one's server
## check (Skill.server_ok) takes what adds up and refuses what doesn't. Prints [S] lines; it names its skill objects,
## so it runs late:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/serpent/tests/serpent_test.gd

var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[S] %s %s" % ["ok  " if ok else "FAIL", what])

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
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	h.mana = h.max_mana
	h.cds.clear()
	await wait(0.2)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "serpent")
	await g.load_zone(0, "bg", "start")
	var h = g.hero
	g.test_immortal = true
	g.test_allskills = true
	h.start_run()
	h.level = 12
	h.recalc()
	check(h.cls == "serpent" and ClassSkills.of("serpent") == Serpent, "the serpent's skills script is Serpent")
	check(ServerRules.CLASSES.has("serpent"), "its skills run on the match server (ServerRules.CLASSES)")
	var p0: Vector3 = h.global_position
	var fwd := Vector3(0, 0, -1)

	# Frost Breath: the jaws open (the latch), the rules beat the cone, the jaws close (the end)
	await fresh(h)
	h._face(fwd)
	var near := [dummy(p0 + fwd * 3.0), dummy(p0 + fwd * 5.0)]
	var behind := dummy(p0 - fwd * 3.0)
	check(h.use_skill("frost_breath", p0 + fwd * 5.0), "Frost Breath cast")
	var fb: FrostBreath = Serpent.skill(h, "frost_breath")
	var was_latched := false
	for i in 120:
		await process_frame
		was_latched = was_latched or fb.latched
	check(was_latched and not fb.latched and not fb.on, "its jaws opened (the latch) and closed (the end)")
	check(near.all(func(e): return hurt(e) and e.chill_t > 0.0) and not hurt(behind), "the cone is struck and chilled, the one behind spared")

	# Glacial Tomb: sealed (stunned, unhurt) from its rules' tomb, then the shatter
	await fresh(h)
	var tomb := [dummy(p0 + fwd * 7.0), dummy(p0 + fwd * 7.0 + Vector3(1.2, 0, 0))]
	check(h.use_skill("s_tomb", tomb[0].global_position), "Glacial Tomb cast")
	var gt: GlacialTomb = Serpent.skill(h, "s_tomb")
	await wait(0.9)
	check(gt.tombs.size() == 1 and tomb.all(func(e): return e.stun_t > 0.0 and not hurt(e)), "its rules hold the tomb; both sealed, not yet hurt")
	await wait(1.8)
	check(gt.tombs.is_empty() and tomb.all(func(e): return hurt(e)), "the tomb shatters on them")

	# Crushing Coil: everything round it crushed and slowed
	await fresh(h)
	var coil := [dummy(p0 + Vector3(2.5, 0, 0)), dummy(p0 + Vector3(-2.0, 0, 1.5))]
	check(h.use_skill("s_coil", p0), "Crushing Coil cast")
	await wait(1.6)
	check(coil.all(func(e): return hurt(e) and e.slow_t > 0.0), "everything round it crushed and slowed")

	# Rime Lance: the line chilled, the chilled one frozen
	await fresh(h)
	h._face(fwd)
	var lance := [dummy(p0 + fwd * 4.0), dummy(p0 + fwd * 8.0)]
	lance[1].chill(0.5, 5.0)
	check(h.use_skill("s_lance", p0 + fwd * 9.0), "Rime Lance cast")
	await wait(1.4)
	check(lance.all(func(e): return hurt(e)) and lance[0].chill_t > 0.0 and lance[1].stun_t > 0.0, "the line is struck, the first chilled, the chilled one frozen")

	# the server's checks: what adds up is taken, what doesn't is refused
	var far: Vector3 = h.global_position + Vector3(60, 0, 0)
	var here: Vector3 = h.global_position
	check(fb.server_ok("latch", {"p": here, "d": Vector3(0, 0.3, -2)}) and not fb.server_ok("latch", {"p": far, "d": fwd}), "Frost Breath: a latch where it stands, not one far off")
	check(gt.server_ok("tomb", {"at": here + fwd * 10.0}) and not gt.server_ok("tomb", {"at": far}), "Glacial Tomb: a tomb in reach, not one far off")
	var cc: CrushingCoil = Serpent.skill(h, "s_coil")
	var rl: RimeLance = Serpent.skill(h, "s_lance")
	check(cc.server_ok("coil", {"p": here}) and not cc.server_ok("coil", {"p": far}), "Crushing Coil: a coil where it stands only")
	check(rl.server_ok("lance", {"p": here, "d": fwd}) and not rl.server_ok("lance", {"p": here, "d": Vector3.UP}), "Rime Lance: a lance aimed along the ground only")
	check(not cc.server_ok("tomb", {"at": here}), "a skill takes only its own kind")
	ClassSkills.clear(h)
	print("[S] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
