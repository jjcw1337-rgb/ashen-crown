extends SceneTree
## Co-op woodcutting: the host owns the trees. Run one copy with "-- host" and one with "-- join".
## The partner fells a pine (each blow goes to the host, which applies it and tells both), sees its wound and its
## fall, picks the logs up (they're host ground items, so they can only be taken once), and a blow sent at a tree
## far away, or faster than a swing, is refused by the host. The host keeps the stump in its save.
## Prints [WH] / [WC] lines.
var g
var role := "host"

func _initialize():
	role = "join" if OS.get_cmdline_user_args().has("join") else "host"
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	process_frame.connect(_answer_votes)
	_run()

func _answer_votes() -> void:
	if g == null or g.ui == null or g.ui.vote_panel == null:
		return
	if g.ui.vote_panel.visible and g.ui.vote_yes.visible:
		g.ui.vote_yes.pressed.emit()

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

func calm() -> void:
	if g.world != null and not g.net.is_client():
		for e in g.world.enemies_root.get_children():
			e.queue_free()

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	await idle()
	if role == "host":
		await _host()
	else:
		await _join()
	quit()

func _pine(h: Harvest) -> int:
	for t in h.trees:
		if t.tkind == "pine":
			return t.id
	return -1

func _host() -> void:
	await g.start_host()
	await idle()
	g.ui.close_all()
	g.test_immortal = true
	var t0 := Time.get_ticks_msec()
	while g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await wait(10)
	print("[WH1] partner joined: ", g.net.players.size() == 1)
	await secs(2.0)
	g.playing = false
	g.travel(0, "wild", "from_town")
	t0 = Time.get_ticks_msec()
	while g.cur_zone != "wild" and Time.get_ticks_msec() - t0 < 20000:
		await wait(5)
	await idle()
	var h: Harvest = Harvest.of(g.world)
	var id := _pine(h)
	print("[WH2] in the moor, %d harvestable trees, the partner's pine is #%d" % [h.trees.size(), id])
	# stay out of the way, keep monsters off
	t0 = Time.get_ticks_msec()
	var t: Harvest.HTree = h.trees[id]
	while t.state == "stand" and Time.get_ticks_msec() - t0 < 60000:
		calm()
		await wait(5)
	print("[WH3] the pine fell on the host's word: ", t.state != "stand", " (life %.0f)" % t.hp)
	await secs(5.0)
	calm()
	var far_id := -1
	for k in h.trees:
		if k.state == "stand" and k.global_position.distance_to(t.global_position) > 20.0:
			far_id = k.id
			break
	var far_hp: float = h.trees[far_id].hp
	await secs(8.0)
	print("[WH4] the far tree the partner tried to strike is untouched: ", is_equal_approx(h.trees[far_id].hp, far_hp))
	g._store_harvest()
	print("[WH5] the stump is in the host's record: ", g.harvest_saved.get(g._harvest_key(), {}).has(str(id)))
	var logs_left := 0
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and gi.item["base"] == "pine_log":
			logs_left += 1
	print("[WH6] pine logs left on the host's ground: ", logs_left)
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
	t0 = Time.get_ticks_msec()
	while (g.cur_zone != "wild" or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	await secs(2.0)
	var h: Harvest = Harvest.of(g.world)
	var id := _pine(h)
	var t: Harvest.HTree = h.trees[id]
	print("[WC1] the same trees here: %d, pine #%d at %s" % [h.trees.size(), id, t.global_position])
	g.hero.vit = 400
	g.hero.recalc()
	g.hero.global_position = t.global_position + Vector3(t.radius - 0.2, 0, 0)
	await wait(5)
	var started: bool = g.hero.start_chop(t)
	var hp_seen := []
	t0 = Time.get_ticks_msec()
	while t.state == "stand" and Time.get_ticks_msec() - t0 < 40000:
		g.hero.life = g.hero.max_life
		if hp_seen.is_empty() or hp_seen[hp_seen.size() - 1] != t.hp:
			hp_seen.append(t.hp)
		await wait(2)
	print("[WC2] chopping: started %s, life seen from the host %s, felled %s" % [started, hp_seen, t.state != "stand"])
	await secs(Harvest.FALL_LOGS_AT + 1.5)
	var logs := []
	for gi in g.world.items_root.get_children():
		if gi is GroundItem and gi.item["base"] == "pine_log":
			logs.append(gi)
	for gi in logs:
		g._pickup(gi)
	await secs(2.0)
	print("[WC3] logs dropped %d, in my bag %d" % [logs.size(), g.hero.count_of("pine_log")])
	# blows the host must refuse: a tree 20 m off, and a burst faster than any swing
	var far_id := -1
	for k in h.trees:
		if k.state == "stand" and k.global_position.distance_to(t.global_position) > 20.0:
			far_id = k.id
			break
	for i in 6:
		g.net.request_chop(far_id, 2.0)
	await secs(3.0)
	print("[WC4] the far tree still whole here too: ", is_equal_approx(h.trees[far_id].hp, h.trees[far_id].max_hp))
	await secs(4.0)
	g.net.shutdown()
	await secs(1.0)
