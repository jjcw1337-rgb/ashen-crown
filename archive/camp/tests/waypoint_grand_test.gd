extends SceneTree
## The camp's grand waypoint (WaypointGrand) and the waypoint window's Battlegrounds tab:
## the dais is built at the camp only, its colliders block the braziers and statues but not the
## arrival spot or the walk onto the dais, a hero can path there from the camp's start, it wakes as a
## hero comes near, the travel window still opens and travels back to it, and the Battlegrounds card opens the
## lobby browser's Battlegrounds.
## godot --headless --path . -s game/maps/camp/tests/waypoint_grand_test.gd
## (WaypointGrand is loaded at run time: a static reference compiles the game's
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
	WG = load("res://game/maps/camp/waypoint_grand.gd")
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
	ok(wp.route_box.get_child_count() >= 1, "the Acts tab still shows the route")
	wp.close()
	# from across the camp, the waypoint takes you back to the dais
	g.hero.global_position = g.world.free_spot_near(_stone().global_position + Vector3(0, 0, 14), 1.0)
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
	ok(card_text.contains(Battlegrounds.map_title()) and card_text.contains("%d min" % int(Battlegrounds.RAID_SECS / 60.0)), "the card names the forest and the round's length")
	wp.close()
	# the card opens the lobby browser's Battlegrounds (the raid is a lobby's match, with a fresh run character)
	g.waypoint_battleground("crypt")
	await _settle()
	ok(g.lobby_client != null and g.lobby_client.panel.visible, "the card opens the Battlegrounds lobbies")
	ok(g.playing and g.cur_zone == "town" and not g.bg_mode, "and the hero stays in the camp")
	g.lobby_client.panel.hide()
	print("[G] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
