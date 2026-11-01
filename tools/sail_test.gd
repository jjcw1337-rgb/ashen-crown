extends SceneTree
## Sailing (boat_ride.gd, Game boat code): boarding at the coast's pier, the crossing to each island's
## jetty at the boat's real speed (steered by the same controls a player uses: hold the mouse on the
## jetty, then heave to), timed in simulated seconds; no grounding on the way; she stops at the shore
## and can always get off again; the open-sea edge turns her back; she rides the waves; landing at an
## island loads it with her moored at its jetty; boarding there sails back out from that island; back
## at the pier the hero steps ashore and she's moored.
var g
const DT := 1.0 / 60.0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
func frames(n: int) -> void:
	for i in n:
		await process_frame
## Steps the boat's own physics by DT (her _process is paused so the clock is exact).
func step(b: BoatRide, n := 1) -> void:
	for i in n:
		b._sail(DT)
		b._float(DT)
		b._place_hero(g.hero)
## Sails from where she is to `to` (x, z) the way a player would; returns [seconds, ok, lowest clearance].
func sail_to(b: BoatRide, to: Vector2, limit := 60.0) -> Array:
	var t := 0.0
	var low := 99.0
	while t < limit:
		var p := Vector2(b.global_position.x, b.global_position.z)
		var d := p.distance_to(to)
		var near := d < 12.0
		b.drive = {"throttle": 0, "steer": 0.0, "stop": near, "point": Vector3(to.x, 0, to.y) if not near else null}
		step(b)
		t += DT
		low = minf(low, b._clearance(b.global_position))
		if d < BoatRide.DOCK_REACH and absf(b.speed) <= BoatRide.DOCK_SPEED:
			return [t, true, low]
	print("   (gave up %.0f m short, speed %.1f, at %s)" % [Vector2(b.global_position.x, b.global_position.z).distance_to(to), b.speed, b.global_position.round()])
	return [t, false, low]
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.boats = ["gull"]
	g.hero.sailed = true
	await g.load_zone(0, "coast", "dock")
	var b: BoatRide = g.boat
	print("[S] coast: boat %s moored %s at %s, clickable %s" % [b != null, not b.sailing, b.global_position.round(), b.inter != null])
	g._interact(b.inter)
	await frames(2)
	print("[S] boarded: sailing %s, hero aboard %s, hero on deck %s" % [g.sailing(), g.hero.aboard, g.hero.global_position.distance_to(b.global_transform * BoatRide.DECK) < 0.1])
	# the real keys aboard (staging's WASD and dodge roll must not move the hero): W sails, A turns her,
	# Space heaves to and never rolls him, the left click steers and never swings
	var y0 := b.yaw
	key(KEY_W, true)
	key(KEY_A, true)
	await create_timer(1.5).timeout
	key(KEY_A, false)
	var spd := b.speed
	var on_deck: bool = g.hero.global_position.distance_to(b.global_transform * BoatRide.DECK) < 0.3
	key(KEY_W, false)
	key(KEY_SPACE, true)
	g.dodge_roll()
	await create_timer(0.3).timeout
	print("[S] keys aboard: W under way %s (%.1f m/s), A turned her %s, hero still at the tiller %s, Space rolled him %s, swinging %s" % [spd > 0.5, spd, absf(wrapf(b.yaw - y0, -PI, PI)) > 0.05, on_deck, g.hero.roll_t >= 0.0, g.hero.atk_t >= 0.0])
	key(KEY_SPACE, false)
	b.set_process(false)
	var start := b.global_transform
	var times := []
	for isle in Isles.ISLANDS:
		b.global_transform = start
		b.yaw = PI * 0.5
		b.speed = 0.0
		b.target = 0.0
		var m: Vector4 = g.isle_mooring(isle, Vector2.ZERO, true)
		var r := sail_to(b, Vector2(m.x, m.z))
		times.append(r[0])
		print("[S] dock -> %-20s %5.1f s, arrived %s, least water under her %.1f m (draft %.1f)" % [isle["name"], r[0], r[1], r[2], BoatRide.DRAFT])
	# straight at the headland's shore: she stops in deep enough water and can back off again
	b.global_position = Vector3(-6, 0, 30)
	b.yaw = atan2(-1.0, 0.0)            # heading east, at the beach south of the pier
	b.speed = 0.0
	b.target = 0.0
	for i in 600:
		b.drive = {"throttle": 1, "steer": 0.0, "stop": false, "point": null}
		step(b)
	var ground := Coast.ground(Vector2(b.global_position.x, b.global_position.z))
	var oc: Ocean = g.world.get_node("Ocean")
	print("[S] charged the shore for 10 s: stopped at (%.1f, %.1f), ground under her %.1f m, sea map depth %.1f, clearance %.1f (afloat %s)" % [b.global_position.x, b.global_position.z, ground, oc.depth_at(b.global_position.x, b.global_position.z), b._clearance(b.global_position), b._clearance(b.global_position) >= BoatRide.DRAFT - 0.2])
	var xp := b.global_position.x
	for i in 240:
		b.drive = {"throttle": -1, "steer": 1.0, "stop": false, "point": null}
		step(b)
	print("[S] backing and turning away: moved %.1f m, not stuck %s" % [absf(b.global_position.x - xp) + absf(b.global_position.z - 30.0), b.global_position.distance_to(Vector3(xp, b.global_position.y, 30)) > 1.0])
	# the open sea's edge
	b.global_position = Vector3(-300, 0, 0)
	b.yaw = PI * 0.5
	for i in 2400:
		b.drive = {"throttle": 1, "steer": 0.0, "stop": false, "point": null}
		step(b)
	var sr: Rect2 = g.world.get_meta("sea_rect")
	print("[S] sailed west 40 s: x %.0f, still inside the sea %s" % [b.global_position.x, sr.has_point(Vector2(b.global_position.x, b.global_position.z))])
	# riding the waves: height and tilt change over a few seconds at anchor
	b.global_position = Vector3(-60, 0, 10)
	var ys := []
	for i in 180:
		b.drive = {"throttle": 0, "steer": 0.0, "stop": true, "point": null}
		step(b)
		ys.append(b.global_position.y)
	print("[S] at anchor in the swell: rises and falls %.2f m, pitch now %.1f deg" % [ys.max() - ys.min(), rad_to_deg(b._pitch)])
	# landing at an island
	var ver := Isles.get_isle("verdant")
	var vm: Vector4 = g.isle_mooring(ver, Vector2.ZERO, true)
	b.global_position = Vector3(vm.x, 0, vm.z)
	b.speed = 0.0
	var dn := b.dock_near()
	print("[S] alongside the Verdant Isle's jetty: dock '%s'" % dn.get("name", ""))
	b.set_process(true)
	g.try_land()
	while g._busy or g.cur_zone != "isle_verdant":
		await process_frame
	await frames(3)
	print("[S] ashore on %s: hero aboard %s, boat moored at the jetty %s, hero near it %.1f m" % [g.cur_zone, g.hero.aboard, g.boat != null and not g.boat.sailing, g.hero.global_position.distance_to(g.boat.global_position)])
	g._interact(g.boat.inter)
	while g._busy or g.cur_zone != "coast":
		await process_frame
	await frames(3)
	var vj := Isles.to_coast(ver, Isles.jetty_end(ver))
	print("[S] boarded at the island: back at sea on the coast, sailing %s, %.0f m from the Verdant jetty" % [g.sailing(), Vector2(g.boat.global_position.x, g.boat.global_position.z).distance_to(vj)])
	b = g.boat
	b.set_process(false)
	var back := sail_to(b, Vector2(Coast.MOOR.x, Coast.MOOR.z))
	print("[S] Verdant Isle -> the pier: %.1f s, arrived %s" % [back[0], back[1]])
	b.set_process(true)
	g.try_land()
	await frames(3)
	print("[S] ashore at the pier: aboard %s, standing on the pier deck %s, boat moored %s" % [g.hero.aboard, g.world.deck_at(g.hero.global_position.x, g.hero.global_position.z) > -INF, not g.boat.sailing])
	var avg := 0.0
	for t in times:
		avg += t
	print("[S] crossing times: %s, average %.1f s" % [times.map(func(t): return snappedf(t, 0.1)), avg / times.size()])
	quit()
