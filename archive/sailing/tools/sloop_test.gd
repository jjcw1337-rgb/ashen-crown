extends SceneTree
## The Ember Sloop (an imported boat, Data.BOATS "sloop"): the model loads from its glb (not the Gull's fallback),
## the shipwright offers both boats, buying her puts her at the pier in the Gull's place, the hero stands on her deck
## at the helm, she crosses to every island's jetty at her own speed without grounding, lands at an island and
## sails back to the pier. Like sail_test, her physics are stepped by hand so the clock is exact.
var g
const DT := 1.0 / 60.0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func frames(n: int) -> void:
	for i in n:
		await process_frame
func step(b: BoatRide, n := 1) -> void:
	for i in n:
		b._sail(DT)
		b._float(DT)
		b._place_hero(g.hero)
func sail_to(b: BoatRide, to: Vector2, limit := 60.0) -> Array:
	var t := 0.0
	var low := 99.0
	while t < limit:
		var p := Vector2(b.global_position.x, b.global_position.z)
		var d := p.distance_to(to)
		var near := d < 14.0 * b.kl
		b.drive = {"throttle": 0, "steer": 0.0, "stop": near, "point": Vector3(to.x, 0, to.y) if not near else null}
		step(b)
		t += DT
		low = minf(low, b._clearance(b.global_position))
		if d < BoatRide.DOCK_REACH * b.kl and absf(b.speed) <= BoatRide.DOCK_SPEED:
			return [t, true, low]
	print("   (gave up %.0f m short, speed %.1f, at %s)" % [Vector2(b.global_position.x, b.global_position.z).distance_to(to), b.speed, b.global_position.round()])
	return [t, false, low]
## The model's own mesh: the glb's, not the Gull's code-built hull.
func from_glb(b: BoatRide) -> bool:
	return b.model.get_node_or_null("model") != null and b.model.get_node_or_null("hull") == null
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.boats = []
	g.hero.sailed = true
	g.hero.gold = int(Data.BOATS["gull"]["price"]) + int(Data.BOATS["sloop"]["price"]) + 3100
	print("[L] glb exists %s, dims %s" % [ResourceLoader.exists(str(Data.BOATS["sloop"]["glb"])), Boat.dims("sloop")])
	var m := Boat.model("sloop")
	print("[L] Boat.model(sloop): imported %s, lamps %d" % [m.get_node_or_null("model") != null, m.find_children("lamp*", "OmniLight3D", true, false).size()])
	m.free()
	await g.load_zone(0, "coast", "dock")
	print("[L] before buying: the pier holds '%s'" % g.boat.id)
	print("[L] buy the Gull %s, buy the sloop %s, gold left %d, owns %s" % [g.buy_boat("gull"), g.buy_boat("sloop"), g.hero.gold, g.hero.boats])
	await frames(3)
	var b: BoatRide = g.boat
	print("[L] after buying: the pier holds '%s', from its glb %s, moored %s, scale k %.2f / %.2f, need %.1f m of water" % [b.id, from_glb(b), not b.sailing, b.kl, b.kb, b.DRAFT])
	print("[L] moored clear of the pier: clearance %.1f m (>= 0 %s), %.1f m from the Gull's mooring" % [b._clearance(b.global_position), b._clearance(b.global_position) >= 0.0, Vector2(b.global_position.x, b.global_position.z).distance_to(Vector2(Coast.MOOR.x, Coast.MOOR.z))])
	g._interact(b.inter)
	await frames(2)
	print("[L] boarded: sailing %s, aboard %s, hero at the helm %s (local %s)" % [g.sailing(), g.hero.aboard, g.hero.global_position.distance_to(b.global_transform * b.DECK) < 0.1, (b.global_transform.affine_inverse() * g.hero.global_position).snapped(Vector3.ONE * 0.01)])
	b.set_process(false)
	var start := b.global_transform
	var times := []
	var all_ok := true
	for isle in Isles.ISLANDS:
		b.global_transform = start
		b.yaw = PI * 0.5
		b.speed = 0.0
		b.target = 0.0
		var mm: Vector4 = g.isle_mooring(isle, Vector2.ZERO, true)
		var r := sail_to(b, Vector2(mm.x, mm.z))
		times.append(r[0])
		all_ok = all_ok and r[1]
		print("[L] dock -> %-20s %5.1f s, arrived %s, least water under her %.1f m (needs %.1f)" % [isle["name"], r[0], r[1], r[2], b.DRAFT])
	var ver := Isles.get_isle("verdant")
	var vm: Vector4 = g.isle_mooring(ver, Vector2.ZERO, true)
	b.global_position = Vector3(vm.x, 0, vm.z)
	b.speed = 0.0
	print("[L] alongside the Verdant Isle's jetty: dock '%s'" % b.dock_near().get("name", ""))
	b.set_process(true)
	g.hero.set_level(10)      # (the Verdant Isle asks for level 10)
	g.try_land()
	while g._busy or g.cur_zone != "isle_verdant":
		await process_frame
	await frames(3)
	print("[L] ashore on %s: the jetty holds '%s', moored %s, clear of the jetty %s, hero %.1f m from her, within her reach %.1f m %s" % [g.cur_zone, g.boat.id, not g.boat.sailing, g.boat._clearance(g.boat.global_position) >= 0.0, g.hero.global_position.distance_to(g.boat.global_position), g.boat.inter.radius, Vector2(g.hero.global_position.x, g.hero.global_position.z).distance_to(Vector2(g.boat.global_position.x, g.boat.global_position.z)) <= g.boat.inter.radius])
	g._interact(g.boat.inter)
	while g._busy or g.cur_zone != "coast":
		await process_frame
	await frames(3)
	b = g.boat
	print("[L] boarded at the island: sailing '%s' %s" % [b.id, g.sailing()])
	b.set_process(false)
	var back := sail_to(b, Vector2(Coast.MOOR.x, Coast.MOOR.z))
	print("[L] Verdant Isle -> the pier: %.1f s, arrived %s" % [back[0], back[1]])
	b.set_process(true)
	g.try_land()
	await frames(3)
	print("[L] ashore at the pier: aboard %s, on the pier deck %s, moored %s, clear of the pier %s" % [g.hero.aboard, g.world.deck_at(g.hero.global_position.x, g.hero.global_position.z) > -INF, not g.boat.sailing, g.boat._clearance(g.boat.global_position) >= 0.0])
	var avg := 0.0
	for t in times:
		avg += t
	print("[L] crossing times %s, average %.1f s, all arrived %s" % [times.map(func(t): return snappedf(t, 0.1)), avg / times.size(), all_ok and back[1]])
	quit()
