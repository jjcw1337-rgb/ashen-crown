extends SceneTree
## The Demon's kit against a player in the Battlegrounds, three processes:
##   godot --headless --path . -s tools/_late.gd -- res://tools/demon_pvp_test.gd --server --port 24681 --raid-fast server
##   godot --headless --path . -s tools/_late.gd -- res://tools/demon_pvp_test.gd a 24681
##   godot --headless --path . -s tools/_late.gd -- res://tools/demon_pvp_test.gd b 24681
## a is the Demon, b the victim (a tough Knight). a uses each skill on b for real (b is a stand-in target on a's
## screen): the charge staggers and Brands, the fault throws up, Brands and slows, the chain drags and holds, the
## boulder Brands and burns, the Crucible's eruption terrifies; then three staggers in a row show the diminishing
## returns (full, half, none). b checks what landed on him (PvpStatus.landed), that it moved him (the drag) and
## that nothing went past the caps; the server checks it kept the DR window.

var g
var role := "a"
var port := 24681
var host := "127.0.0.1"
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	role = "server" if a.has("server") else ("b" if a.has("b") else "a")
	for i in a.size():
		if a[i].is_valid_int() and int(a[i]) > 1024:
			port = int(a[i])
	if role != "server":
		Battlegrounds.id_path = "user://dpvp_%s_id.txt" % role
		DirAccess.remove_absolute(Battlegrounds.id_path)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[%s] %s%s" % [role.to_upper(), "ok   " if ok else "FAIL ", what])

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	if role == "server":
		await _server()
	else:
		await _player()
	print("[%s] done, %d failed" % [role.to_upper(), fails])
	quit()

func _server() -> void:
	await until(func(): return g.bg != null and g.net.active and not g._busy, 40.0)
	check(await until(func(): return g.net.players.size() == 2, 60.0), "both players are in the crypt")
	check(await until(func(): return g.bg.cc_dr.size() > 0, 90.0), "crowd control between them went through the server (DR kept)")
	await until(func(): return g.net.players.is_empty(), 150.0)

func _player() -> void:
	while g._busy:
		await wait(5)
	await secs(2.0 if role == "a" else 4.0)
	g.char_dir = "user://dpvp_%s_chars/" % role
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	for fn in DirAccess.get_files_at(g.char_dir):
		DirAccess.remove_absolute(g.char_dir + fn)
	g.hero.set_class("demon" if role == "a" else "knight")
	g.hero.new_character()
	g.hero.set_level(20)
	g.char_id = g.new_char_id()
	g.char_name = "Demon" if role == "a" else "Target"
	g.net.my_name = g.char_name
	g.save_game()
	await g.start_battlegrounds("%s:%d" % [host, port], g.char_id)
	check(await until(func(): return g.cur_zone == Battlegrounds.ZONE and not g._busy and not g.net.loading, 30.0), "entered the crypt")
	# a round opens in the antechambers with PvP off behind the gates (Blaine's lobby): ring a bell, wait for the raid
	await until(func(): return not g.bg_raid.is_empty(), 10.0)
	if str(g.bg_raid.get("state", "")).begins_with("lobby"):
		var bells: Array = g.world.interactables.filter(func(t): return t.kind == "bell")
		if not bells.is_empty():
			g._interact(bells[0])
	check(await until(func(): return str(g.bg_raid.get("state", "")) == "raid", 30.0), "the bell rang and the raid is on")
	check(await until(func(): return g.net.puppets().size() == 1 and g.net.puppets()[0].net_has, 40.0), "the other player is here")
	if role == "a":
		await _demon()
	else:
		await _target()
	g.net.shutdown()
	await secs(1.0)

func _proxy():
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_pid > 0:
			return e
	return null

## Stands the Demon `dist` m from b on a free spot along `dir` (from b), facing b, ready to cast anything.
func _stand(dist: float, dir := Vector3(0, 0, 1)) -> Vector3:
	var h = g.hero
	var foe = g.net.puppets()[0]
	var bp: Vector3 = foe.global_position
	# a spot with a clear line to b (the crypt is all walls and corridors)
	var at: Vector3 = bp + dir * dist
	for k in 16:
		var d2: Vector3 = dir.rotated(Vector3.UP, TAU * k / 16.0)
		var c: Vector3 = bp + d2 * dist
		var back: Vector3 = g.world.move(c, bp - c, 0.3)
		var fwd: Vector3 = g.world.move(bp, c - bp, 0.3)
		if back.distance_to(bp) < 0.6 and fwd.distance_to(c) < 0.6:
			at = c
			break
	h.global_position = at
	h._face(bp - h.global_position)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	await secs(0.4)       # (b's stand-in follows b's position)
	return foe.global_position

func _demon() -> void:
	var h = g.hero
	g.test_immortal = true
	g.test_allskills = true
	var DS = load("res://scripts/demon_skills.gd")
	var PS = load("res://scripts/pvp_status.gd")
	check(await until(func(): return _proxy() != null, 10.0), "b is a target for my skills")
	# 1 the charge
	var bp: Vector3 = await _stand(6.0)
	check(h.use_skill("icharge", bp), "Infernal Charge at b")
	await secs(2.0)
	check(DS.branded(h, _proxy()), "it stopped on b and Branded him (on my side)")
	await secs(9.0)       # past the DR window
	# 2 the fault: b on its line
	bp = await _stand(DS.FAULT_AHEAD)
	check(h.use_skill("cslam", bp), "Fault of the Pit across b")
	await secs(2.5)
	await secs(8.0)
	# 3 the chain
	bp = await _stand(6.0)
	check(h.use_skill("grip", bp), "Hellgrip at b")
	await secs(3.5)
	await secs(8.0)
	# 4 the boulder
	bp = await _stand(8.0)
	check(h.use_skill("hurl", bp), "Brimstone Hurl at b")
	await secs(2.0)
	await secs(8.0)
	# 5 the Crucible's eruption
	bp = await _stand(2.5)
	check(h.use_skill("wrath", bp), "Wrath of the Pit beside b")
	await secs(0.6)
	check(h.use_skill("wrath", bp), "and burst it")
	await secs(3.0)
	await secs(9.0)
	# 6 three staggers in a row: full, half, none
	var p = _proxy()
	for i in 3:
		PS.send(g, p, "stagger", 0.8)
		await secs(0.15)
	await secs(4.0)

func _target() -> void:
	var h = g.hero
	g.test_immortal = false
	var PS = load("res://scripts/pvp_status.gd")
	PS.landed.clear()
	h.max_life = 1.0e7
	h.life = 1.0e7
	var start: Vector3 = h.global_position
	var max_move := 0.0
	var max_daze := 0.0
	var max_up := 0.0
	var t_end := Time.get_ticks_msec() + 85000
	while Time.get_ticks_msec() < t_end:
		h.life = maxf(h.life, 1.0e6)
		max_daze = maxf(max_daze, h.daze_t)
		if h.rig != null:
			max_up = maxf(max_up, h.rig.position.y)
		if h.cc.has("pull"):
			max_move = maxf(max_move, h.global_position.distance_to(start))
		else:
			start = h.global_position
		await process_frame
	var kinds := {}
	for x in PS.landed:
		kinds[str(x[0])] = true
	print("[B] landed: ", PS.landed)
	for k in ["stagger", "brand", "knockup", "slow", "pull", "burn", "fear"]:
		check(kinds.has(k), "the Demon's %s landed on me" % k)
	check(max_up > 0.5, "the fault threw me up (%.2f m)" % max_up)
	check(max_move > 2.0, "the chain dragged me (%.1f m)" % max_move)
	check(max_daze <= PvpStatus.MAX_SECS + 0.05, "no status ever held me longer than the cap (%.2f s)" % max_daze)
	check(PS.landed.all(func(x): return float(x[1]) <= (PvpStatus.MAX_SECS if str(x[0]) in PvpStatus.HARD else PvpStatus.SOFT_MAX) + 0.001), "every status within its cap")
	# the last three staggers: full, half, then refused
	var last: Array = PS.landed.filter(func(x): return str(x[0]) == "stagger")
	var tail: Array = last.slice(maxi(0, last.size() - 2))
	check(tail.size() == 2 and absf(float(tail[0][1]) - 0.8) < 0.01 and absf(float(tail[1][1]) - 0.4) < 0.01, "diminishing returns: 0.8 s, then 0.4 s, then none (%s)" % str(tail))
