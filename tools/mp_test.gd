extends SceneTree
## Two-player co-op test. Run one copy with "-- host" and another with "-- join".

var g
var role := "host"

func _initialize():
	role = "join" if OS.get_cmdline_user_args().has("join") else "host"
	var scn: PackedScene = load("res://main.tscn")
	g = scn.instantiate()
	get_root().add_child(g)
	process_frame.connect(_answer_votes)
	_run()

## The ready check (UI.party_vote): the partner says "Not yet" to the first trip and joins 2 s later, then
## joins every other trip at once; the host joins the partner's trips.
var votes_seen := 0
var _vote_wait := 0.0
var _vote_open := false
func _answer_votes() -> void:
	if g == null or g.ui == null or g.ui.vote_panel == null:
		return
	var ui = g.ui
	if not ui.vote_panel.visible:
		_vote_open = false
		return
	if not _vote_open:
		_vote_open = true
		votes_seen += 1
		_vote_wait = 2.0 if (role == "join" and votes_seen == 1) else 0.3
		if role == "join" and votes_seen == 1 and ui.vote_no.visible:
			ui.vote_no.pressed.emit()
	if ui.vote_yes.visible:
		_vote_wait -= 1.0 / 60.0
		if _vote_wait <= 0.0:
			ui.vote_yes.pressed.emit()

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

func _host() -> void:
	await g.start_host()
	await idle()
	for c in ["wraith", "demon", "warlock"]:
		if OS.get_cmdline_user_args().has(c):
			g.hero.set_class(c)   # also re-sends gear + class to the partner
	g.ui.close_all()
	print("[H1] hosting=", g.net.active and g.net.is_host, " zone=", g.cur_zone)
	var t0 := Time.get_ticks_msec()
	while g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await wait(10)
	print("[H2] partner joined: ", g.net.players.size() == 1, " name=", g.net.players.values()[0]["name"] if g.net.players.size() > 0 else "-")
	await secs(3.0)
	g.playing = false
	g.travel(0, "wild", "from_town")
	await secs(1.0)
	print("[H2b] the ready check: the partner said Not yet, the party waits in town: ", g.cur_zone == "town" and g.ui.vote_panel.visible, " (", g.ui.vote_wait.text, ")")
	var tw := Time.get_ticks_msec()
	while g.cur_zone != "wild" and Time.get_ticks_msec() - tw < 15000:
		await wait(5)
	await wait(5)
	await idle()
	var h = g.hero
	h.vit = 400
	h.recalc()
	h.life = h.max_life
	print("[H3] wild loaded, enemies=", g.net.enemies.size())
	await secs(4.0)
	var ally = g.net.puppets()[0]
	print("[H4] partner visible=", ally.visible, " partner pos ok=", ally.global_position.distance_to(h.global_position) < 6.0)
	var seen := {}
	var max_items := 0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and g.cur_zone == "wild":
		h.life = h.max_life
		if g.world:
			max_items = maxi(max_items, g.world.items_root.get_child_count())
		if OS.get_cmdline_user_args().has("shot") and not shot_done and Time.get_ticks_msec() - t0 > 13000:
			shot_done = true
			var al = g.net.puppets()[0]
			h.global_position = g.world.free_spot_near(al.global_position + Vector3(-2.5, 0, 2.0), 1.0)
			g.cam_target = h.global_position
			await secs(1.5)
			await _snap("/tmp/claude-0/-home-claude/53690df5-e9e9-598f-a0eb-b2995b9001cd/scratchpad/mp_host.png")
		if g.world:
			for e in g.world.enemies_root.get_children():
				if e.dead:
					seen[e.get_instance_id()] = true
		await wait(10)
	print("[H5] monsters killed by partner=", seen.size(), " items dropped peak=", max_items, " items left=", g.net.items.size())
	t0 = Time.get_ticks_msec()
	while g.cur_zone != "town" and Time.get_ticks_msec() - t0 < 20000:
		await wait(10)
	await idle()
	print("[H6] party travelled to town on partner's request: ", g.cur_zone == "town")
	t0 = Time.get_ticks_msec()
	while not g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await wait(10)
	print("[H7] partner left cleanly: ", g.net.players.is_empty())


var shot_done := false
func _snap(path: String) -> void:
	g.playing = true
	g.lmb_held = false
	await wait(3)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)
	g.playing = false

func _join() -> void:
	await secs(2.0)
	g.start_join("127.0.0.1")
	var t0 := Time.get_ticks_msec()
	while (g.net.players.is_empty() or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	g.playing = false
	g.ui.close_all()
	var host_p = g.net.puppets()[0] if g.net.puppets().size() > 0 else null
	await secs(1.0)
	print("[C1] joined=", g.net.is_client(), " zone=", g.cur_zone, " host visible=", host_p != null and host_p.visible, " host class=", host_p.cls if host_p else "-")
	t0 = Time.get_ticks_msec()
	while (g.cur_zone != "wild" or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	await secs(2.0)
	print("[C2] followed host to wild=", g.cur_zone == "wild", " monsters mirrored=", g.net.enemies.size(), " all remote=", g.net.enemies.values().all(func(e): return e.remote))
	var h = g.hero
	h.level = 14
	h.str_ = 120
	h.vit = 400
	h.recalc()
	h.life = h.max_life
	var xp0: int = h.xp + h.level * 100000
	var hits := 0
	var last_life: float = h.life
	var kills := 0
	var seen_dead := {}
	var moved_monsters := false
	var start_pos := {}
	for id in g.net.enemies:
		start_pos[id] = g.net.enemies[id].global_position
	t0 = Time.get_ticks_msec()
	var retarget := 0.0
	while Time.get_ticks_msec() - t0 < 30000:
		if h.life < last_life - 0.5:
			hits += 1
		if h.life < h.max_life * 0.6:
			h.life = h.max_life
		last_life = h.life
		for id in g.net.enemies:
			var e = g.net.enemies[id]
			if is_instance_valid(e) and start_pos.has(id) and e.global_position.distance_to(start_pos[id]) > 1.0:
				moved_monsters = true
		for e in g.world.enemies_root.get_children():
			if e.dead and not seen_dead.has(e.get_instance_id()):
				seen_dead[e.get_instance_id()] = true
				kills += 1
		retarget -= 1.0 / 60.0
		if retarget <= 0.0:
			retarget = 0.4
			var best = null
			var bd := 1e9
			for e in g.world.enemies_root.get_children():
				if e.dead:
					continue
				var d: float = e.global_position.distance_to(h.global_position)
				if d < bd:
					bd = d
					best = e
			if best != null:
				if bd > 8.0:
					h.global_position = g.world.free_spot_near(best.global_position + Vector3(1.5, 0, 0), 1.0)
				g.lmb_held = true
				h.cmd_target(best)
		await wait(1)
		if OS.get_cmdline_user_args().has("shot") and not shot_done and Time.get_ticks_msec() - t0 > 9000:
			shot_done = true
			await _snap("/tmp/claude-0/-home-claude/53690df5-e9e9-598f-a0eb-b2995b9001cd/scratchpad/mp_join.png")
	g.lmb_held = false
	await secs(1.0)
	var gained: int = h.xp + h.level * 100000 - xp0
	print("[C3] monsters moved on my screen=", moved_monsters, " I killed=", kills, " xp gained=", gained > 0, " times hit by monsters=", hits)
	var gold0: int = h.gold
	var inv0: int = h.inventory.filter(func(x): return x != null).size()
	var belt0 := 0
	for b in h.belt:
		if b != null:
			belt0 += int(b.get("count", 1))
	var picked := 0
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and picked < 6:
			h.global_position = gi.global_position
			g._pickup(gi)
			picked += 1
			await secs(0.3)
	await secs(1.5)
	var belt1 := 0
	for b in h.belt:
		if b != null:
			belt1 += int(b.get("count", 1))
	var got: int = (h.gold - gold0) + (h.inventory.filter(func(x): return x != null).size() - inv0) + (belt1 - belt0)
	print("[C4] tried to pick up ", picked, " items, received something=", got > 0, " ground items left=", g.world.items_root.get_child_count())
	g.travel(0, "town", "from_wild")
	t0 = Time.get_ticks_msec()
	while (g.cur_zone != "town" or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	print("[C5] I asked to go to town, party is now in: ", g.cur_zone)
	await secs(2.0)
	g.net.shutdown()
	await secs(1.0)
	print("[C6] disconnected cleanly")
