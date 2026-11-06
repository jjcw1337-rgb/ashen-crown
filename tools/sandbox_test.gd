extends SceneTree
## The admins' Battlegrounds sandbox (Sandbox, BotBrain): open it from a character, become a level-20 geared knight,
## spawn bots, and check they fight like players: they close in and hit the player (through the stand-ins, at the
## raid's PvP scale, never themselves), the player's blows reach them, a fallen bot stands up again, monsters go for
## bots too, "free for all" makes bots fight each other, the meters count it, and leaving brings the character back
## exactly as it was (level, gear, gold, zone), with nothing saved from inside.
##   godot --headless --fixed-fps 60 --path . -s tools/sandbox_test.gd
var g
var fails := 0
var SB      # sandbox.gd and hero.gd at run time (a static reference compiles their Sfx before the autoload)
var HS
func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	SB = load("res://scripts/sandbox.gd")
	HS = load("res://scripts/hero.gd")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://sandbox_combat_test/"
	g.old_save = "user://sandbox_combat_test/absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()
func _process(_dt: float) -> bool:
	if is_instance_valid(g):g._intro_skip=true
	return false
func check(ok: bool, what: String) -> void:
	print("[SB] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func frames(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "warlock")
	while g._busy:
		await frames(5)
	g.ui.close_all()
	g.dev_tools = false
	var h = g.hero
	h.set_level(7)
	h.gold = 1234
	g.save_game()
	var before := {"cls": h.cls, "level": h.level, "gold": h.gold, "weapon": str(h.equipment.get("weapon", {}).get("name", ""))}
	await g.open_sandbox()
	while g._busy:
		await frames(5)
	var sb = g.sandbox
	check(sb != null and g.cur_zone == "sandbox" and g.char_id == "", "the sandbox opens (zone %s), the character set aside" % g.cur_zone)
	check(h.level == 20 and h.cls == "warlock", "and you're a level-20 geared %s (%d life, %d-%d)" % [h.cls, int(h.max_life), h.dmg_min, h.dmg_max])
	SB.outfit(g, h, "knight", 20, "geared")
	g.test_immortal = true
	var b = sb.spawn_bot("knight", 20, "geared")
	check(b.bot and b.level == 20 and b.cls == "knight", "a level-20 geared knight bot (%d life, armour %d)" % [int(b.max_life), b.armor])
	b.global_position = h.global_position + Vector3(0, 0, -7)
	# it closes in and hits you (immortal: the blows are counted, nothing lost)
	g.test_immortal = false
	var l0: float = h.life
	var t := 0
	while t < 600 and h.life >= l0:
		await frames(1)
		t += 1
	check(h.life < l0, "the bot closes in and hits you (%d -> %d life in %.1f s)" % [int(l0), int(h.life), t / 60.0])
	h.life = h.max_life
	g.test_immortal = true
	# your blows reach it, its own don't (its brain paused, any roll it was in finished)
	sb.bots[0]["brain"].react = 9999.0
	sb.bots[0]["brain"]._think = 9999.0
	await frames(90)
	b.life = b.max_life
	b.ward = 0.0
	var bl0: float = b.life
	HS.striker = h
	var dealt: float = sb.bots[0]["proxy"].take_damage(40.0, 0.0, h.global_position, 0.0, false)
	check(dealt > 0.0 and b.life < bl0, "a blow on its stand-in hurts it (%d dealt, %d -> %d)" % [int(dealt), int(bl0), int(b.life)])
	HS.striker = b
	var own: float = sb.bots[0]["proxy"].take_damage(40.0, 0.0, b.global_position, 0.0, false)
	check(own == 0.0, "and its own blows never land on it")
	# it falls and stands up again
	b.block_chance = 0.0        # (the knight's shield would block it)
	b.take_hit(1e6, h.global_position, "pvp", "phys")
	check(b.dead, "it can fall")
	var t0 := Time.get_ticks_msec()       # (seconds, not frames: headless runs at whatever rate it can)
	while Time.get_ticks_msec() - t0 < 8000 and b.dead:
		await frames(1)
	check(not b.dead and b.life == b.max_life, "and stands up again (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	check(sb.log_lines.size() > 0, "the kill is in the log: %s" % str(sb.log_lines))
	sb.bots[0]["brain"].react = 0.18
	sb.bots[0]["brain"]._think = 0.0
	# monsters go for a bot when it's nearer
	b.global_position = Vector3(10, 0, -10)
	h.global_position = Vector3(-12, 0, 12)
	await frames(2)
	sb.spawn_pack("zombie", 1)
	await frames(2)
	var z = null
	for e in g.world.enemies_root.get_children():
		if e.get("sandbox_hero") == null and "kind" in e and not e.dead:
			z = e
	if z != null:
		z.global_position = b.global_position + Vector3(2, 0, 0)
	check(z != null and g.target_for(z) == b, "a monster goes for the nearest hero, the bot")
	sb.clear_monsters()
	await frames(2)
	# free for all
	var b2 = sb.spawn_bot("demon", 20, "geared")
	b.global_position = Vector3(0, 0, -10)
	b2.global_position = Vector3(3, 0, -10)
	h.global_position = Vector3(0, 0, 16)
	sb.ffa = true
	var d0: float = float(sb._tot(b)["dealt"]) + float(sb._tot(b2)["dealt"])
	t = 0
	while t < 1200 and float(sb._tot(b)["dealt"]) + float(sb._tot(b2)["dealt"]) <= d0:
		h.global_position = Vector3(0, 0, 16)
		await frames(1)
		t += 1
	check(float(sb._tot(b)["dealt"]) + float(sb._tot(b2)["dealt"]) > d0, "free for all: the bots fight each other (first blow after %.1f s)" % (t / 60.0))
	# a duel to the end: who wins, how long it takes, the skills they used
	for k in 900:
		h.global_position = Vector3(0, 0, 16)
		await frames(1)
		if b.dead or b2.dead:
			break
	print("[SB] duel: knight %d/%d, demon %d/%d; %s" % [int(b.life), int(b.max_life), int(b2.life), int(b2.max_life), str(sb.log_lines)])
	check(sb.rate(b) + sb.rate(b2) > 0.0 or float(sb._tot(b)["dealt"]) + float(sb._tot(b2)["dealt"]) > 0.0, "the meters count it: %s" % sb.meter.text.replace("\n", " | "))
	# leaving
	await g.close_sandbox()
	while g._busy:
		await frames(5)
	check(g.sandbox == null and g.cur_zone == "town" and g.char_id != "", "leaving goes back to the camp (%s)" % g.cur_zone)
	var after := {"cls": h.cls, "level": h.level, "gold": h.gold, "weapon": str(h.equipment.get("weapon", {}).get("name", ""))}
	check(str(after) == str(before), "the character is exactly as it was: %s" % str(after))
	check(get_root().find_children("Bot*", "Node3D", true, false).is_empty(), "no bot is left behind")
	print("[SB] done, %d failed" % fails)
	g.queue_free()
	for i in 12: await process_frame
	quit(1 if fails else 0)
