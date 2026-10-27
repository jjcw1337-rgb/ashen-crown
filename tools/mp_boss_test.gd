extends SceneTree
## Co-op King Grubb: run one copy with "-- host" and one with "-- join". The host takes the party
## to his vault and stays back; the joining player fights him. Checks that the partner sees the
## mutant model, his first sack bursting (piles, the sack gone from his back, grabbers), that a
## pile the partner steps on gives them gold and hurts him on the host, and that his death ends
## the act for both.

var g
var role := "host"

func _initialize():
	role = "join" if OS.get_cmdline_user_args().has("join") else "host"
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func idle() -> void:
	while g._busy or g.net.loading:
		await wait(5)

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	await idle()
	if role == "host":
		await _host()
	else:
		await _join()
	quit()

func _boss():
	if g.world == null:
		return null
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.boss and not e.dead:
			return e
	return null

func _host() -> void:
	await g.start_host()
	await idle()
	g.ui.close_all()
	g.test_immortal = true
	var t0 := Time.get_ticks_msec()
	while g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await wait(10)
	print("[H1] partner joined: ", not g.net.players.is_empty())
	await secs(2.0)
	g.playing = false
	g.travel(0, "lair", "boss_room")
	await wait(5)
	await idle()
	var boss = _boss()
	g.hero.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 11.0), 1.0)
	g.boss_killed = false
	print("[H2] vault loaded, boss ", boss.kind if boss else "-")
	# wait for the partner to wake him, then knock him to his first sack
	t0 = Time.get_ticks_msec()
	while not boss.aggro and Time.get_ticks_msec() - t0 < 40000:
		g.hero.life = g.hero.max_life
		await wait(5)
	await secs(3.0)
	boss.life = boss.max_life * 0.74
	t0 = Time.get_ticks_msec()
	while boss.hoard.state != "spill" and Time.get_ticks_msec() - t0 < 10000:
		await wait(5)
	print("[H3] partner woke him: ", boss.aggro, ", sack burst: ", boss.hoard.state == "spill")
	var robbed0: int = boss.hoard.robbed
	t0 = Time.get_ticks_msec()
	while boss.hoard.robbed == robbed0 and Time.get_ticks_msec() - t0 < 25000:
		g.hero.life = g.hero.max_life
		await wait(5)
	print("[H4] the partner took a pile and it hurt him on the host: ", boss.hoard.robbed > robbed0)
	t0 = Time.get_ticks_msec()
	while not boss.dead and Time.get_ticks_msec() - t0 < 40000:
		g.hero.life = g.hero.max_life
		await wait(5)
	print("[H5] the partner killed him: ", boss.dead, ", act done ", g.boss_killed)
	await secs(10.0)
	print("[H6] time_scale ", Engine.time_scale)
	print("[H6] victory shown on the host: ", g.ui.victory_panel.visible)
	t0 = Time.get_ticks_msec()
	while not g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await wait(10)

func _join() -> void:
	await secs(2.0)
	g.start_join("127.0.0.1")
	var t0 := Time.get_ticks_msec()
	while (g.net.players.is_empty() or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	g.playing = false
	g.ui.close_all()
	g.test_immortal = true
	t0 = Time.get_ticks_msec()
	while (g.cur_zone != "lair" or g.net.loading or g._busy or _boss() == null) and Time.get_ticks_msec() - t0 < 40000:
		await wait(5)
	await secs(1.5)
	var boss = _boss()
	var held: bool = boss != null and boss.rig.has_meta("held")
	print("[C1] followed to the vault: ", g.cur_zone == "lair", ", boss mirrored: ", boss != null and boss.remote, ", mutant model: ", held)
	var h = g.hero
	g.boss_killed = false
	# walk up and wake him
	h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 5.0), 1.0)
	t0 = Time.get_ticks_msec()
	while boss.hoard.piles.is_empty() and Time.get_ticks_msec() - t0 < 30000:
		h.life = h.max_life
		await wait(5)
	await secs(1.5)
	var sacks: int = boss.rig.get_meta("sacks") if boss.rig.has_meta("sacks") else 3
	var grabbers := 0
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.kind == "grabber" and not e.dead:
			grabbers += 1
	print("[C2] sack burst on my screen: piles ", boss.hoard.piles.size(), ", sacks on his back ", sacks, ", grabbers ", grabbers, ", boss bar shown ", g.ui.boss_bar_box.visible)
	# step on a pile: the gold comes to me
	var gold0: int = h.gold
	var tried := 0
	t0 = Time.get_ticks_msec()
	while h.gold == gold0 and not boss.hoard.piles.is_empty() and Time.get_ticks_msec() - t0 < 12000:
		# stand on the pile furthest from the king (his goblins race for the near ones)
		var far = null
		var fd := -1.0
		for pid in boss.hoard.piles.keys():
			var d: float = boss.hoard.piles[pid]["pos"].distance_to(boss.global_position)
			if d > fd:
				fd = d
				far = pid
		h.global_position = boss.hoard.piles[far]["pos"]
		tried += 1
		await secs(0.6)
	print("[C3] I took a pile: gold +", h.gold - gold0, " (stood on ", tried, " piles)")
	# finish him off
	# his attack poses come through (smash, lob, scoop...): each style he shows is one the net syncs
	var styles := {}
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		if boss.net_atk >= 0.0:
			styles[boss.atk_style] = true
		await wait(2)
	g.test_onehit = true
	t0 = Time.get_ticks_msec()
	while is_instance_valid(boss) and not boss.dead and Time.get_ticks_msec() - t0 < 30000:
		h.life = h.max_life
		if h.global_position.distance_to(boss.global_position) > 3.5:
			h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 2.6), 0.8)
		h.cmd_target(boss)
		g.lmb_held = true
		await wait(5)
	g.lmb_held = false
	await secs(6.0)
	print("[C4a] time_scale ", Engine.time_scale)
	await secs(5.0)
	print("[C4] he fell on my screen: ", not is_instance_valid(boss) or boss.dead, ", act done ", g.boss_killed, ", victory shown ", g.ui.victory_panel.visible, ", attack poses seen ", styles.keys())
	g.net.shutdown()
	await secs(1.0)
