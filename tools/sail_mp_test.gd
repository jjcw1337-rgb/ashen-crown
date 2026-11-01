extends SceneTree
## Co-op sailing (Net._boat_packet, BoatRide.puppet_update, Game._add_boat's party trip). Run one copy with
## "-- host" and another with "-- join" (both own a boat):
## the party goes to the coast; the host sails out: the partner sees his boat leave the pier under his puppet,
## at the tiller, while the partner's own boat stays moored; the host lands at the pier and the partner's copy
## of his boat goes. Then the party crosses to the Verdant Isle and the host boards there: the whole party
## comes out to sea, each aboard his own boat, a few lengths apart. Prints [H]/[C] lines.

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

func zone(z: String, limit := 40.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while (g.cur_zone != z or g._busy or g.net.loading) and Time.get_ticks_msec() - t0 < int(limit * 1000.0):
		await wait(5)
	await secs(1.0)
	return g.cur_zone == z

func key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

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
	g.ui.close_all()
	g.hero.boats = ["gull"]
	g.hero.sailed = true
	var t0 := Time.get_ticks_msec()
	while g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await wait(10)
	print("[H1] partner joined: ", g.net.players.size() == 1)
	await secs(3.0)
	g.travel(0, "coast", "from_town")
	print("[H2] at the coast: ", await zone("coast"))
	await secs(3.0)
	var b: BoatRide = g.boat
	g.hero.global_position = Vector3(1.5, 1.05, -0.8)
	g._interact(b.inter)
	key(KEY_W, true)
	await secs(10.0)
	key(KEY_W, false)
	print("[H3] sailing out: aboard %s, %.0f m from the pier, at %s" % [g.hero.aboard, Vector2(b.global_position.x, b.global_position.z).distance_to(Vector2(Coast.MOOR.x, Coast.MOOR.z)), b.global_position.round()])
	await secs(4.0)
	g.land_boat({"kind": "pier", "name": "the pier"})
	print("[H4] landed at the pier: aboard ", g.hero.aboard)
	await secs(4.0)
	g.travel(0, "isle_verdant", "jetty")
	print("[H5] on the Verdant Isle: ", await zone("isle_verdant"))
	await secs(3.0)
	g._interact(g.boat.inter)
	print("[H6] boarded at the isle, back at sea: ", await zone("coast"), " aboard ", g.hero.aboard)
	await secs(6.0)
	var ally = g.net.puppets()[0] if g.net.puppets().size() > 0 else null
	var ab: BoatRide = ally.net_boat if ally else null
	print("[H7] the partner sailed out too: his boat %s, %.1f m from mine" % [ab != null, ab.global_position.distance_to(g.boat.global_position) if ab else -1.0])
	await secs(4.0)

func _join() -> void:
	await secs(2.0)
	g.start_join("127.0.0.1")
	var t0 := Time.get_ticks_msec()
	while (g.net.players.is_empty() or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
		await wait(5)
	g.ui.close_all()
	g.hero.boats = ["gull"]
	g.hero.sailed = true
	print("[C1] joined: ", g.net.is_client())
	print("[C2] followed to the coast: ", await zone("coast"))
	var host_p = g.net.puppets()[0] if g.net.puppets().size() > 0 else null
	# wait for the host to sail out
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and (host_p.net_boat == null or Vector2(host_p.net_boat.global_position.x, host_p.net_boat.global_position.z).distance_to(Vector2(Coast.MOOR.x, Coast.MOOR.z)) < 25.0):
		await wait(5)
	var nb: BoatRide = host_p.net_boat
	var deck := nb.global_transform * BoatRide.DECK if nb else Vector3.ZERO
	print("[C3] the host's boat under him: %s, %.0f m out, him at its tiller %s (%.2f m), riding the swell y %.2f" % [nb != null,
		Vector2(nb.global_position.x, nb.global_position.z).distance_to(Vector2(Coast.MOOR.x, Coast.MOOR.z)) if nb else -1.0,
		host_p.global_position.distance_to(deck) < 0.3 if nb else false, host_p.global_position.distance_to(deck) if nb else -1.0, nb.global_position.y if nb else 0.0])
	print("[C4] my own boat still moored at the pier: %s (%.1f m)" % [not g.boat.sailing and g.boat.global_position.distance_to(Coast.MOOR) < 1.5, g.boat.global_position.distance_to(Coast.MOOR)])
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and host_p.net_boat != null:
		await wait(5)
	print("[C5] he landed: his boat's copy gone ", host_p.net_boat == null, ", him on the pier ", host_p.global_position.distance_to(Vector3(Coast.DOCK.x + 1.0, 0, -0.6)) < 2.5)
	print("[C6] followed to the Verdant Isle: ", await zone("isle_verdant"))
	print("[C7] sailed out with the party: ", await zone("coast"), " aboard my own boat ", g.hero.aboard)
	await secs(4.0)
	var hb: BoatRide = host_p.net_boat
	print("[C8] the host's boat beside mine: %s, %.1f m apart (not on top of each other %s)" % [hb != null, hb.global_position.distance_to(g.boat.global_position) if hb else -1.0, hb != null and hb.global_position.distance_to(g.boat.global_position) > 5.0])
	await secs(8.0)
