extends SceneTree
## The Obsidian Wyrm's skills script (Wyrm): no skills of its own yet, its basic attack the common three-swipe combo
## (claw, bite, tail spin) hurting what's in front, its reach its body's, and its class run on the match server like
## the other dragons'. Its body is tested with the others' (tools/dragon_test.gd). Prints [Y] lines; it names its
## skills script, so it runs late:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/wyrm/tests/wyrm_test.gd

var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[Y] %s %s" % ["ok  " if ok else "FAIL", what])

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "wyrm")
	await g.load_zone(0, "bg", "start")
	var h = g.hero
	g.test_immortal = true
	check(h.cls == "wyrm" and ClassSkills.of("wyrm") == Wyrm, "the wyrm's skills script is Wyrm")
	check(Wyrm.IDS.is_empty() and Data.skills_for("wyrm").is_empty() and Wyrm.skill(h, "attack") == null, "it has no skills of its own yet")
	check(ServerRules.CLASSES.has("wyrm"), "its class runs on the match server (ServerRules.CLASSES)")
	check(is_equal_approx(h.reach(), Dragon.reach("wyrm")) and h.reach() > 1.9, "its reach is its body's (%.1f m)" % h.reach())
	for old in g.world.enemies_root.get_children():
		old.queue_free()
	await wait(0.2)
	var p0: Vector3 = h.global_position
	var at: Vector3 = p0 + Vector3(0, 0, -2.0)
	at.y = g.world.height_at(at.x, at.z)
	var e: Enemy = g.spawn_enemy("zombie", at, 5)
	e.speed = 0.0
	e.scripted = 99.0
	e.max_life = 5000.0
	e.life = e.max_life
	h._face(Vector3(0, 0, -1))
	for i in 3:
		h.swipe_attack(at, false)
		await wait(1.05)
	check(e.life < e.max_life, "claw, bite and tail spin hurt what's in front (%d)" % int(e.max_life - e.life))
	print("[Y] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
