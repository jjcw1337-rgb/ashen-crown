extends SceneTree
## Collision: walk into every footprinted prop in the camp from 8 directions and check the
## hero stops against the prop itself (no gap, no overlap), slides past it when grazing, and
## that pathfinding and line of sight agree with the footprints.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

## Gap between a body of radius r at q and footprint o (negative = overlapping).
func gap(o: Array, q: Vector2, r: float) -> float:
	var c: Vector2 = o[0]
	if o[1] > 0.0:
		return q.distance_to(c) - o[1] - r
	var lp := (q - c).rotated(o[3])
	var half: Vector2 = o[2]
	var d := Vector2(maxf(absf(lp.x) - half.x, 0.0), maxf(absf(lp.y) - half.y, 0.0))
	return d.length() - r

func min_gap(w, q: Vector2, r: float, skip: Vector2 = Vector2(INF, INF)) -> float:
	var m := INF
	for o in w.obstacles:
		if (o[0] as Vector2).distance_to(skip) > 0.01:
			m = minf(m, gap(o, q, r))
	return m

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	var w = g.world
	var r: float = w.BODY_R
	var props: Array = w.props_root.get_children().filter(func(n): return n.has_meta("footprint"))
	var kinds := {}
	for p in props:
		kinds[String(p.name).rstrip("0123456789@")] = true
	print("[C] footprinted props in camp: %d (%s), obstacles %d" % [props.size(), ", ".join(kinds.keys()), w.obstacles.size()])
	# walk at each prop from 8 directions
	var worst_gap := -INF
	var worst_pen := INF
	var bumps := 0
	var tries := 0
	for p in props:
		var c := Vector2(p.position.x, p.position.z)
		for k in 8:
			var a := TAU * k / 8.0
			var dir := Vector2(cos(a), sin(a))
			var q := c - dir * 3.5
			if w.solid_at(q.x, q.y, r):
				continue
			tries += 1
			var pos := Vector3(q.x, 0, q.y)
			var prev := pos
			for i in 120:
				prev = pos
				pos = w.move(pos, Vector3(dir.x, 0, dir.y) * 0.06)
			var end := Vector2(pos.x, pos.z)
			var mg := min_gap(w, end, r)
			worst_pen = minf(worst_pen, mg)
			# wherever it stalled, it must be touching a real footprint (no invisible walls)
			if pos.distance_to(prev) < 0.005:
				bumps += 1
				worst_gap = maxf(worst_gap, mg)
				if mg > 0.05:
					print("[C]   stalled clear of anything: by %s at %s, wall %s" % [p.name, end, w._wall_at(end.x, end.y, r + 0.07)])
	print("[C] head-on walks %d, stalled %d, worst overlap %.3f m, worst gap to the nearest footprint when stopped %.3f m" % [tries, bumps, -minf(worst_pen, 0.0), worst_gap])
	# grazing: walk past a barrel just off its centre line, expect to get by
	var barrels: Array = props.filter(func(n): return is_equal_approx(float(n.get_meta("footprint").get("r", 0.0)), 0.34))
	barrels.sort_custom(func(x, y): return min_gap(w, Vector2(x.position.x, x.position.z), 2.0, Vector2(x.position.x, x.position.z)) > min_gap(w, Vector2(y.position.x, y.position.z), 2.0, Vector2(y.position.x, y.position.z)))
	if not barrels.is_empty():
		var b: Node3D = barrels[0]
		var start := b.position + Vector3(-3.0, 0, 0.25)
		var pos := start
		for i in 120:
			pos = w.move(pos, Vector3(0.06, 0, 0))
		print("[C] graze past barrel: got by %s (x %.2f -> %.2f)" % [pos.x > b.position.x + 1.0, start.x, pos.x])
	# log piles: the long side blocks, the footprint follows the pile's yaw
	var logs: Array = props.filter(func(n): return n.get_meta("footprint").get("half", Vector2.ZERO) == Vector2(0.42, 0.7))
	for lp in logs:
		var along := (lp as Node3D).basis.z
		var across := (lp as Node3D).basis.x
		var lc := (lp as Node3D).position
		print("[C] log pile yaw %d: end of pile at 0.6 m blocked %s, side at 0.6 m along blocked %s, 1.1 m off the side free %s" % [int(rad_to_deg((lp as Node3D).rotation.y)), w.solid_at(lc.x + along.x * 0.6, lc.z + along.z * 0.6), w.solid_at(lc.x + across.x * 0.3 + along.x * 0.6, lc.z + across.z * 0.3 + along.z * 0.6), not w.solid_at(lc.x + across.x * 1.1, lc.z + across.z * 1.1, r)])
	# fire seats: the box follows the log's yaw
	var seats: Array = props.filter(func(n): return n.get_meta("footprint").get("half", Vector2.ZERO) == Vector2(0.25, 0.8))
	var seat_ok := 0
	for s in seats:
		var sn := s as Node3D
		var tip := sn.position + sn.basis.z * 0.7
		if w.solid_at(tip.x, tip.z):
			seat_ok += 1
	print("[C] fire seats blocked along their length: %d/%d" % [seat_ok, seats.size()])
	# pathfinding around a crate and los through it
	var crates: Array = props.filter(func(n): return absf((n.get_meta("footprint").get("half", Vector2.ZERO) as Vector2).x - (n.get_meta("footprint").get("half", Vector2.ZERO) as Vector2).y) < 0.001 and n.get_meta("footprint").has("half"))
	if not crates.is_empty():
		var cc: Vector3 = (crates[0] as Node3D).position
		var a := cc + Vector3(-2.5, 0, 0)
		var bb := cc + Vector3(2.5, 0, 0)
		var path: PackedVector3Array = w.find_path(a, bb)
		var pos := a
		for pt in path:
			for i in 200:
				var dv := pt - pos
				dv.y = 0
				if dv.length() < 0.05:
					break
				pos = w.move(pos, dv.normalized() * minf(0.06, dv.length()))
		print("[C] path round crate: los through %s, %d waypoints, arrived %s" % [w.los(a, bb), path.size(), Vector2(pos.x, pos.z).distance_to(Vector2(bb.x, bb.z)) < 0.3])
	# the hero walking with the real controller into the stash
	var h = g.hero
	var st: Vector3 = w.spawns["start"]
	h.global_position = w.free_spot_near(st, 0.5)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for e in 200:
		w.los(Vector3(-20, 0, -20), Vector3(20, 0, 20))
		n += 1
	print("[C] los 57 m x200: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	# the wilds and the crypt: walls and edges still hold
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	w = g.world
	var edge := Vector3(w.bounds.end.x - 3.0, 0, w.bounds.get_center().y)
	var p2 := edge
	for i in 200:
		p2 = w.move(p2, Vector3(0.06, 0, 0))
	print("[C] wild edge: stopped inside %s (%.2f m from edge)" % [p2.x < w.bounds.end.x - 1.0, w.bounds.end.x - p2.x])
	await g.travel(0, "lair", "start")
	while g._busy:
		await process_frame
	w = g.world
	var sp: Vector3 = w.spawns["start"]
	var inside := 0
	for k in 8:
		var a := TAU * k / 8.0
		var pos := sp
		for i in 600:
			pos = w.move(pos, Vector3(cos(a), 0, sin(a)) * 0.06)
		if not w._wall_at(pos.x, pos.z, r * 0.9):
			inside += 1
	print("[C] crypt walls: walks in 8 directions stayed on the floor %d/8" % inside)
	quit()
