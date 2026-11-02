extends SceneTree
## The camp's grand waypoint (WaypointGrand) and the waypoint window's Battlegrounds tab:
## the dais is built at the camp only, its colliders block the braziers and statues but not the
## arrival spot or the walk onto the dais, a hero can path there from the camp's start, it wakes as a
## hero comes near, the travel window still opens and travels, and the Battlegrounds card hands off
## to the title's Battlegrounds window (and refuses from co-op).
## godot --headless --path . -s tools/waypoint_grand_test.gd
## (WaypointGrand is loaded at run time, like aurelia.gd in its tools: a static reference compiles the game's
## scripts, and their Sfx, before the autoload exists.)
var g
var WG: GDScript
var fails := 0

func _is_grand(n: Node) -> bool:
	return n.get_script() == WG
func ok(cond: bool, what: String) -> void:
	print("[G] ", "ok   " if cond else "FAIL ", what)
	if not cond:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _settle(n := 4) -> void:
	for f in n:
		await process_frame
	while g._busy:
		await process_frame

func _stone():
	for it in g.world.interactables:
		if is_instance_valid(it) and it.kind == "waypoint":
			return it
	return null

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	WG = load("res://scripts/waypoint_grand.gd")
	await g.start_game(false, "knight")
	await _settle()
	ok(g.cur_zone == "town", "started in the camp")
	var st = _stone()
	ok(st != null, "the camp has a waypoint")
	var grand = null
	if st:
		for c in st.get_children():
			if _is_grand(c):
				grand = c
	ok(grand != null, "the camp's waypoint is the grand dais")
	var p: Vector3 = st.global_position if st else Vector3.ZERO
	# colliders: braziers, statues and the socket block; the arrival spot and the front of the dais don't
	for s in WG.SOLIDS:
		ok(g.world.solid_at(p.x + s[0], p.z + s[1]), "solid at (%.1f, %.1f)" % [s[0], s[1]])
	var arrive: Vector3 = g.world.spawns.get("waypoint_town", Vector3.ZERO)
	ok(not g.world.solid_at(arrive.x, arrive.z), "the arrival spot is clear")
	ok(not g.world.solid_at(p.x, p.z + 2.0), "the front of the dais can be walked on")
	var path: PackedVector3Array = g.world.find_path(g.world.spawns["start"], arrive)
	ok(path.size() >= 1, "a hero can walk from the camp's start to the waypoint (%d points)" % path.size())
	# it wakes as a hero comes near
	g.hero.global_position = p + Vector3(0, 0, 30)
	await _settle(30)
	var far_e: float = grand.ring_mats[0].get_shader_parameter("energy") if grand else 0.0
	g.hero.global_position = arrive
	for f in 240:
		await process_frame
	var near_e: float = grand.ring_mats[0].get_shader_parameter("energy") if grand else 0.0
	ok(grand != null and grand._wake > 0.8, "a hero on the dais wakes it (wake %.2f)" % (grand._wake if grand else 0.0))
	ok(near_e > far_e * 1.5, "the outer channel brightens (%.2f -> %.2f)" % [far_e, near_e])
	# the window still opens and travels
	g.ui.open_waypoints(st)
	await _settle()
	var wp = g.ui.wp_panel
	ok(wp.visible, "the travel window opens at the dais")
	ok(grand != null and grand._flash > 0.5, "opening it flares the dais")
	# the Battlegrounds tab
	wp.sel_group = "battlegrounds"
	wp._fill()
	await _settle()
	var cards: Array = wp.route_box.get_children().filter(func(c): return (c as Control).has_meta("node"))
	ok(cards.size() == Data.WAYPOINT_BATTLEGROUNDS.size(), "one card per battleground (%d)" % cards.size())
	var btn: Button = null
	for c in cards:
		for b in c.find_children("*", "Button", true, false):
			btn = b
	ok(btn != null, "the card has an Enter button")
	wp.sel_group = "acts"
	wp._fill()
	await _settle()
	ok(wp.route_box.get_child_count() >= 2, "the Acts tab still shows the route")
	wp.close()
	# from the dais to the moor and back still works
	g.waypoints_known = ["town", "wild"]
	g.waypoint_go(0, "wild")
	await _settle()
	ok(g.cur_zone == "wild", "travels to the moor")
	var moor_stone = _stone()
	var moor_grand := false
	if moor_stone:
		for c in moor_stone.get_children():
			moor_grand = moor_grand or _is_grand(c)
	ok(moor_stone != null and not moor_grand, "the moor keeps its own stone")
	g.waypoint_go(0, "town")
	await _settle()
	ok(g.cur_zone == "town" and g.hero.global_position.distance_to(_stone().global_position) < 5.0, "back at the camp, beside the dais")
	st = _stone()
	grand = null
	for c in st.get_children():
		if c is WaypointGrand:
			grand = c
	# the Battlegrounds tab's card: the crypt's painting on the banner, the stakes, the character and the server
	g.ui.open_waypoints(_stone())
	wp.sel_group = "battlegrounds"
	wp._fill()
	await _settle()
	ok(wp.banner.texture != null, "the Battlegrounds tab shows the crypt's painting")
	var card_text := ""
	for c in wp.route_box.get_children():
		for l in c.find_children("*", "Label", true, false):
			card_text += (l as Label).text + "\n"
	ok(card_text.contains(Battlegrounds.TITLE) and card_text.contains("%d min" % int(Battlegrounds.RAID_SECS / 60.0)), "the card names the crypt and the round's length")
	ok(card_text.contains(g.char_name) and card_text.contains("gold"), "the card says who goes down and what is at stake")
	ok(card_text.contains("Server"), "the card names the server")
	ok(wp.probe_state != "", "and looks whether it answers (%s)" % wp.probe_state)
	wp.close()
	ok(wp.probe == null, "closing the window drops the probe")
	# the way down: a last word on the stakes first; "Not yet" leaves everything as it was
	await g.waypoint_battleground("crypt")
	await _settle()
	ok(g.playing and g.cur_zone == "town", "asking leaves the hero in the camp")
	ok(g.ui.dialog_panel.visible, "a last word on the stakes is asked")
	var not_yet: Button = null
	var descend: Button = null
	for b in g.ui.dialog_btns.get_children():
		if (b as Button).text == "Not yet":
			not_yet = b
		if (b as Button).text == "Descend":
			descend = b
	ok(not_yet != null and descend != null, "with Descend and Not yet")
	if not_yet:
		not_yet.pressed.emit()
	await _settle()
	ok(not g.ui.dialog_panel.visible and not g.bg_mode and g.playing, "Not yet: nothing happens")
	# Descend with no raid server to answer: the dais flares, the join gives up and the hero is back where he
	# stood, his save not marked in_raid
	var p0: Vector3 = g.hero.global_position
	grand._flash = 0.0
	await g.waypoint_battleground("crypt")
	await _settle()
	for b in g.ui.dialog_btns.get_children():
		if (b as Button).text == "Descend":
			(b as Button).pressed.emit()
	for f in 12:
		await process_frame
	ok(grand != null and grand._flash > 0.3, "Descend flares the dais (%.2f)" % (grand._flash if grand else 0.0))
	ok(g.bg_from_waypoint, "the trip is marked as taken from the waypoint")
	var t0 := Time.get_ticks_msec()
	while (g.bg_mode or g.bg_from_waypoint or g.loading.visible) and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await _settle()
	ok(not g.bg_mode and not g.bg_from_waypoint, "no server answered: out of raid mode again")
	ok(g.playing and g.cur_zone == "town" and g.hero.global_position.distance_to(p0) < 3.0, "and the hero is back in the camp where he stood")
	ok(not g.net.active and not g.loading.visible, "no connection left, the loading screen gone")
	var sv = JSON.parse_string(FileAccess.get_file_as_string(g.save_path()))
	ok(sv is Dictionary and not bool(sv.get("in_raid", true)), "his save is not marked in_raid")
	print("[G] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
