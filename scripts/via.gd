class_name Via
## A2's wild zone, the Imperial Road (World.run == 1): longer and wider than Act I's moor, and it changes
## as you go. First the moor (a dirt trail, dead trees and pines, the restless dead), then a rocky pass
## where bandits lie in wait round an overturned wagon (an ambush, below), then the old Roman road:
## basalt paving and kerbs, milestones, tombs along both verges, cypresses, toppled columns, and the
## aqueduct striding across the land (the road passes under it). Last, Aurelia's outskirts: a wider
## road between ruined colonnades and statues, a villa's walls, a fountain, bandits holding the way,
## and the triumphal arch into the city (the exit to the lair, aurelia.gd).
##
## Ambush: World.ambushes holds {pos, radius, spawns, done}. Nothing is there until a hero comes within
## `radius` of `pos` (Game._check_ambushes, host only); then the bandits spring from behind the rocks
## (Enemy.leap_from) and the spawns replicate to partners like any other.

## Where along the road (0..1) each stretch starts.
const AMBUSH := 0.36
const ROMAN := 0.45
const OUTSKIRTS := 0.76

const VIA_TERRAIN := {
	"col_a": Color(0.19, 0.2, 0.1), "col_b": Color(0.26, 0.25, 0.13), "col_accent": Color(0.33, 0.31, 0.16),
	"col_path": Color(0.33, 0.27, 0.19), "col_cliff": Color(0.38, 0.35, 0.3), "wet": 0.15, "cob_shade": 0.62,
}
## late summer: the grass gone gold at the tips
const VIA_GRASS := {"base_col": Color(0.16, 0.17, 0.07), "tip_col": Color(0.4, 0.37, 0.17), "dry_col": Color(0.5, 0.44, 0.22), "wind": 1.0}

static func build(w: World) -> void:
	w.bounds = Rect2(-55, -330, 110, 334)
	w.theme = {"name": "wild"}
	var ctrl := [Vector2(0, 2), Vector2(0, -14)]
	var x := 0.0
	for i in 13:
		x = clampf(x + w.rng.randf_range(-18, 18), -30, 30)
		ctrl.append(Vector2(x, -36 - i * 22.5))
	ctrl.append(Vector2(clampf(x * 0.5, -14, 14), -318))
	w.path_poly = w._spline(ctrl, 6)
	var poly := w.path_poly
	var n := poly.size()
	_lay_road(w)
	var end_p: Vector2 = poly[n - 1]
	w.exits.append({"pos": Vector3(0, 0, 0.5), "radius": 2.6, "to": "town", "label": w.act_name("town")})
	# the triumphal arch into Aurelia
	var last_dir: Vector2 = (poly[n - 1] - poly[n - 4]).normalized()
	var arch_p := end_p + last_dir * 2.0
	Roman.triumphal_arch(w, Vector3(arch_p.x, 0, arch_p.y), atan2(last_dir.x, last_dir.y) + PI)
	w.cobble_blobs.append([arch_p, 7.0, 1.0])
	w.exits.append({"pos": Vector3(arch_p.x, 0, arch_p.y) + Vector3(last_dir.x, 0, last_dir.y) * 1.2, "radius": 2.6, "to": "lair", "label": w.act_name("lair")})
	_moor(w)
	_pass(w)
	_roman(w)
	_outskirts(w)
	_vegetation(w)
	for i in 140:
		var px := w.rng.randf_range(w.bounds.position.x + 1, w.bounds.end.x - 1)
		var pz := w.rng.randf_range(w.bounds.position.y + 1, w.bounds.end.y - 3)
		var pd := w.path_dist(px, pz)
		if pd < 2.5:
			continue
		var big := w.rng.randf() < 0.2 and pd > 6.0
		w._rock(Vector3(px, 0, pz), w.rng.randf_range(1.0, 2.0) if big else w.rng.randf_range(0.25, 0.6), big)
	w._rasterize()
	w._flush_stones(Props.stone())
	w._build_terrain(VIA_TERRAIN)
	w._scatter_grass(120000, VIA_GRASS, 0.32)
	w._scatter_ferns(500)
	_packs(w)
	w.spawns["start"] = Vector3(0, 0, -6)
	w.spawns["from_town"] = Vector3(0, 0, -6)
	for k in [["road", 0.22], ["road2", 0.5]]:
		var rp: Vector2 = poly[int(n * k[1])]
		w.spawns[k[0]] = Vector3(rp.x, 0, rp.y)
	w.spawns["from_lair"] = Vector3(arch_p.x, 0, arch_p.y) - Vector3(last_dir.x, 0, last_dir.y) * 5.0

## The point on the road a fraction t along it, and the road's direction there.
static func at(w: World, t: float) -> Vector2:
	return w.path_poly[clampi(int((w.path_poly.size() - 1) * t), 0, w.path_poly.size() - 1)]

static func dir_at(w: World, t: float) -> Vector2:
	var i := clampi(int((w.path_poly.size() - 1) * t), 0, w.path_poly.size() - 2)
	return (w.path_poly[i + 1] - w.path_poly[i]).normalized()

## A spot `off` metres to the side of the road at t (negative: left), clamped inside the zone.
static func beside(w: World, t: float, off: float, along := 0.0) -> Vector2:
	var c := at(w, t)
	var d := dir_at(w, t)
	var p := c + d.orthogonal() * off + d * along
	return Vector2(clampf(p.x, w.bounds.position.x + 3, w.bounds.end.x - 3), p.y)

# ---------------------------------------------------------------- the road
## A dirt trail over the moor; through the pass it narrows; then the Romans' road takes over, the paving
## patchy at first where it has sunk, then whole, with kerbstones, and wider again near the city.
static func _lay_road(w: World) -> void:
	var poly := w.path_poly
	var n := poly.size()
	var mile := 0.0
	for i in n - 1:
		var t := float(i) / (n - 1)
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		if t < ROMAN - 0.03:
			w.dirt_lines.append([a, b, 3.0 if t < AMBUSH - 0.04 or t > AMBUSH + 0.06 else 2.4])
			continue
		var outer := t > OUTSKIRTS
		w.dirt_lines.append([a, b, 5.4 if outer else 4.4])
		# the first stretch of paving has sunk and broken up
		if t < ROMAN + 0.03 and w.rng.randf() < lerpf(0.7, 0.1, (t - ROMAN + 0.03) / 0.06):
			continue
		w.cobble_lines.append([a, b, 4.2 if outer else 3.4])
		var seg := a.distance_to(b)
		var d := (b - a) / maxf(seg, 0.001)
		var nrm := d.orthogonal()
		var u := 0.0
		while u < seg:
			var c := a + d * u
			for s in [-1.0, 1.0]:
				if w.rng.randf() < 0.7:
					var kp: Vector2 = c + nrm * s * (2.6 if outer else 2.15)
					var v := w.rng.randi_range(0, 7)
					if not w.rock_xf.has(v):
						w.rock_xf[v] = []
					var kb := Basis(Vector3.UP, atan2(d.x, d.y) + w.rng.randf_range(-0.1, 0.1)).scaled(Vector3(0.45, w.rng.randf_range(0.2, 0.32), w.rng.randf_range(0.8, 1.0)))
					w.rock_xf[v].append(Transform3D(kb, Vector3(kp.x, w.height_at(kp.x, kp.y) + 0.02, kp.y)))
			u += 1.0
		mile += seg
		if mile > 28.0 and not outer:
			mile = 0.0
			var mp := a + nrm * (3.4 if i % 2 == 0 else -3.4)
			Roman.milestone(w, Vector3(mp.x, 0, mp.y), atan2(d.x, d.y))

# ---------------------------------------------------------------- the moor
static func _moor(w: World) -> void:
	# a burned farmstead: low walls, a dead hearth, a broken cart
	var fp := beside(w, 0.12, -12.0)
	Roman.ruin_wall(w, fp + Vector2(-4, -3), fp + Vector2(4, -3), 1.4)
	Roman.ruin_wall(w, fp + Vector2(-4, -3), fp + Vector2(-4, 3), 1.2)
	Roman.ruin_wall(w, fp + Vector2(4, -3), fp + Vector2(4, 1), 0.9)
	w.dirt_blobs.append([fp, 6.0, 0.8])
	w.solid(Props.campfire(w.props_root, Vector3(fp.x, w.height_at(fp.x, fp.y), fp.y)))
	# a graveyard on a rise
	var gy := beside(w, 0.22, 13.0)
	for i in 14:
		var gp := gy + Vector2((i % 5) * 2.2 - 4.4 + w.rng.randf_range(-0.3, 0.3), (i / 5) * 2.8 + w.rng.randf_range(-0.3, 0.3))
		w._gravestone(Vector3(gp.x, 0, gp.y), w.rng.randf() < 0.25)
	w.dirt_blobs.append([gy + Vector2(0, 2.5), 6.0, 0.5])
	# the waypoint, before the pass
	var wpp := beside(w, 0.3, 6.5)
	w._inter("waypoint", "Waypoint", Vector3(wpp.x, 0, wpp.y), 2.4, Props.waypoint(null, Vector3.ZERO), {"wp": "wild"})
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		w.add_circle(Vector3(wpp.x + cos(a) * 1.85, 0, wpp.y + sin(a) * 1.85), 0.3)
	w.spawns["waypoint"] = Vector3(wpp.x, 0, wpp.y + 3.0)
	w.cobble_blobs.append([wpp, 3.0, 0.8])
	# a signpost at the start of the road: Aurelia, north
	var sp := beside(w, 0.035, 3.6)
	var sign := Props.footprint(Models.N(null, "signpost"), 0.2)
	Models.seg(sign, Vector3.ZERO, Vector3(0, 2.4, 0), 0.07, 0.06, Props.wood_dark(), 6)
	Models.P(sign, Geo.box(1.3, 0.32, 0.06), Props.wood(), Vector3(0.45, 2.0, 0), Vector3(0, 0, -6))
	Models.P(sign, Geo.prism(0.32, 0.32, 0.06), Props.wood(), Vector3(1.2, 2.0, 0), Vector3(0, 0, -96))
	Models.P(sign, Geo.box(0.9, 0.06, 0.07), Mats.mat(Color(0.1, 0.08, 0.06), 0.9), Vector3(0.42, 2.02, 0.01), Vector3(0, 0, -6))
	w._place(sign, Vector3(sp.x, 0, sp.y))
	sign.rotation.y = atan2(dir_at(w, 0.035).x, dir_at(w, 0.035).y) - PI * 0.5
	w.solid(sign)
	# the bandits' last victims, a little before the pass: a caravan dragged off the road and picked over
	var cv := beside(w, AMBUSH - 0.06, -7.0)
	var path := ForestCamp.DIR + "wagon.glb"
	for k in 2:
		if ResourceLoader.exists(path):
			var wg: Node3D = (load(path) as PackedScene).instantiate()
			var q := cv + Vector2(k * 3.6 - 1.8, w.rng.randf_range(-1.5, 1.5))
			w._place(wg, Vector3(q.x, 0, q.y))
			wg.rotation = Vector3(0, w.rng.randf() * TAU, deg_to_rad(12.0 if k == 0 else 78.0))
			wg.scale = Vector3.ONE * 1.1
			w.add_box(Vector3(q.x, 0, q.y), Vector2(1.1, 1.9), wg.rotation.y)
	for k in 7:
		var q := cv + Vector2(w.rng.randf_range(-5, 5), w.rng.randf_range(-4, 4))
		if w.is_near_obstacle(Vector3(q.x, 0, q.y), 0.9):
			continue
		match k % 3:
			0: w._bones(Vector3(q.x, 0, q.y))
			1: w.solid(Props.crate(w.props_root, Vector3(q.x, w.height_at(q.x, q.y), q.y), w.rng.randf_range(0.6, 0.9)))
			_: w.solid(Props.barrel(w.props_root, Vector3(q.x, w.height_at(q.x, q.y), q.y)))
	w.dirt_blobs.append([cv, 6.0, 0.7])
	var kinds := ["healing", "fury", "armor", "experience"]
	kinds.shuffle()
	var s1 := beside(w, 0.17, 7.5)
	w._shrine(Vector3(s1.x, 0, s1.y), kinds[0])
	var s2 := beside(w, 0.6, -8.0)
	w._shrine(Vector3(s2.x, 0, s2.y), kinds[1])
	for t in [0.08, 0.27, 0.52, 0.68, 0.88]:
		var cp := beside(w, t, w.rng.randf_range(7.0, 12.0) * (1.0 if w.rng.randf() < 0.5 else -1.0))
		if w.path_dist(cp.x, cp.y) > 3.0:
			w._chest(Vector3(cp.x, 0, cp.y))

# ---------------------------------------------------------------- the pass and its ambush
## The road narrows between rocky banks; an overturned wagon lies across it, goods spilled, the bait.
## Bandits crouch behind the rocks on both banks and an archer pair on each crest.
static func _pass(w: World) -> void:
	var t0 := AMBUSH
	var c := at(w, t0)
	var d := dir_at(w, t0)
	for k in 26:
		var t := t0 - 0.035 + 0.07 * k / 25.0
		for s in [-1.0, 1.0]:
			var p := beside(w, t, s * w.rng.randf_range(5.5, 9.0))
			w._rock(Vector3(p.x, 0, p.y), w.rng.randf_range(1.3, 2.4), true)
			if w.rng.randf() < 0.6:
				var q := beside(w, t, s * w.rng.randf_range(9.5, 14.0))
				w._rock(Vector3(q.x, 0, q.y), w.rng.randf_range(1.6, 2.8), true)
	# the bandits' lookout on the crest above the pass (the fort's Meshy watchtower), a bowman up top
	var lk := beside(w, t0 + 0.03, 15.5)
	var tower := Fort.model("tower")
	if tower != null:
		var holder := Node3D.new()
		holder.name = "lookout"
		holder.add_child(tower)
		w._place(holder, Vector3(lk.x, 0, lk.y))
		holder.rotation.y = atan2(c.x - lk.x, c.y - lk.y)
		holder.scale = Vector3.ONE * 0.85
		w.add_circle(Vector3(lk.x, 0, lk.y), 1.7)
	# the bait: an overturned wagon half across the road, crates and sacks spilled
	var wp := c + d.orthogonal() * 1.2
	var path := ForestCamp.DIR + "wagon.glb"
	if ResourceLoader.exists(path):
		var wagon: Node3D = (load(path) as PackedScene).instantiate()
		w._place(wagon, Vector3(wp.x, 0, wp.y))
		wagon.rotation = Vector3(0, atan2(d.x, d.y) + 0.4, deg_to_rad(80))
		wagon.position.y += 0.6
		wagon.scale = Vector3.ONE * 1.1
		w.add_box(Vector3(wp.x, 0, wp.y), Vector2(1.2, 2.0), atan2(d.x, d.y) + 0.4)
	for k in 6:
		var q := wp + Vector2(w.rng.randf_range(-3.5, 3.5), w.rng.randf_range(-3.5, 3.5))
		if w.is_near_obstacle(Vector3(q.x, 0, q.y), 0.8):
			continue
		var at3 := Vector3(q.x, w.height_at(q.x, q.y), q.y)
		if k % 2 == 0:
			w.solid(Props.crate(w.props_root, at3, w.rng.randf_range(0.7, 1.0)))
		else:
			w.solid(Props.barrel(w.props_root, at3))
	w._chest(Vector3(wp.x - d.orthogonal().x * 3.0, 0, wp.y - d.orthogonal().y * 3.0))
	w.dirt_blobs.append([wp, 5.0, 0.6])
	# who waits: two bands behind the rocks either side, bowmen on the crests, their captain
	var lv := w.level + 1
	var spawns := []
	for s in [-1.0, 1.0]:
		var hide := beside(w, t0 + 0.006 * s, s * 10.5)
		spawns.append({"kind": "bandit", "pos": Vector3(hide.x, 0, hide.y), "count": 4, "champ": false, "pack": 300 + int(s + 1), "level": lv})
		var crest := beside(w, t0 + 0.02, s * 15.0)
		spawns.append({"kind": "bandit_archer", "pos": Vector3(crest.x, 0, crest.y), "count": 2, "champ": false, "pack": 304 + int(s + 1), "level": lv})
	var cap := beside(w, t0 + 0.025, 0.0)
	spawns.append({"kind": "bandit", "pos": Vector3(cap.x, 0, cap.y), "count": 1, "champ": true, "pack": 310, "level": lv + 1, "name": "the Bandit Captain"})
	w.ambushes.append({"pos": Vector3(c.x, 0, c.y) - Vector3(d.x, 0, d.y) * 4.0, "radius": 9.0, "spawns": spawns, "done": false, "land": Vector3(c.x, 0, c.y)})

# ---------------------------------------------------------------- the Roman road
static func _roman(w: World) -> void:
	# tombs along both verges, Via Appia fashion
	var t := ROMAN + 0.03
	var side := 1.0
	while t < OUTSKIRTS - 0.02:
		var p := beside(w, t, side * w.rng.randf_range(7.5, 10.0))
		if not w.is_near_obstacle(Vector3(p.x, 0, p.y), 3.5):
			var face := dir_at(w, t).orthogonal() * -side
			Roman.tomb(w, Vector3(p.x, 0, p.y), atan2(face.x, face.y), 1 if w.rng.randf() < 0.3 else 0)
		side = -side
		t += w.rng.randf_range(0.022, 0.034)
	# toppled columns and drums scattered off the road
	for k in 22:
		var tt := w.rng.randf_range(ROMAN, OUTSKIRTS)
		var p := beside(w, tt, w.rng.randf_range(5.0, 16.0) * (1.0 if w.rng.randf() < 0.5 else -1.0))
		if w.is_near_obstacle(Vector3(p.x, 0, p.y), 2.0):
			continue
		if k % 3 == 0:
			Roman.drum(w, Vector3(p.x, 0, p.y))
		else:
			Roman.column(w, Vector3(p.x, 0, p.y), 4.4, 0.32, w.rng.randf_range(0.35, 0.85))
	# the aqueduct crosses the road: one bay's arch exactly over it
	var ta := 0.58
	var c := at(w, ta)
	var d := dir_at(w, ta)
	var across := d.rotated(PI * 0.42)
	var bays_l := 0
	while w.bounds.grow(10).has_point(c - across * 5.6 * (bays_l + 1)):
		bays_l += 1
	var bays_r := 0
	while w.bounds.grow(10).has_point(c + across * 5.6 * (bays_r + 1)):
		bays_r += 1
	Roman.aqueduct(w, c - across * 5.6 * (bays_l + 0.5), c + across * 5.6 * (bays_r + 0.5), 0.12, c)
	# cypresses lining the road, gaps where they died
	var trees: Array = []
	var tc := ROMAN + 0.02
	while tc < 0.98:
		for s in [-1.0, 1.0]:
			if w.rng.randf() < 0.72:
				var p := beside(w, tc, s * (6.0 if tc < OUTSKIRTS else 7.0))
				if not w.is_near_obstacle(Vector3(p.x, 0, p.y), 1.2) and p.distance_to(c) > 6.0:
					trees.append(Vector3(p.x, 0, p.y))
		tc += 0.012
	Roman.cypresses(w, trees)

# ---------------------------------------------------------------- Aurelia's outskirts
static func _outskirts(w: World) -> void:
	# ruined colonnades along both sides of the wider road
	for k in 3:
		var t := OUTSKIRTS + 0.03 + k * 0.06
		for s in [-1.0, 1.0]:
			var a := beside(w, t, s * 9.0)
			var b := beside(w, t + 0.035, s * 9.0)
			Roman.colonnade(w, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), 5, 4.2, k != 1)
	# statues facing the road
	for k in 4:
		var t := OUTSKIRTS + 0.02 + k * 0.05
		var s := 1.0 if k % 2 == 0 else -1.0
		var p := beside(w, t, s * 5.8)
		var face := dir_at(w, t).orthogonal() * -s
		Roman.statue(w, Vector3(p.x, 0, p.y), atan2(face.x, face.y), 1.2, k == 2)
	# a villa's walls with a mosaic floor
	var vc := beside(w, 0.84, -19.0)
	var r := Rect2(vc - Vector2(8, 6), Vector2(16, 12))
	Roman.ruin_wall(w, r.position, Vector2(r.end.x, r.position.y), 2.0)
	Roman.ruin_wall(w, r.position, Vector2(r.position.x, r.end.y), 1.8)
	Roman.ruin_wall(w, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - 4.0), 1.5)
	Roman.ruin_wall(w, Vector2(r.position.x + 6.0, r.position.y), Vector2(r.position.x + 6.0, r.end.y - 5.0), 1.3)
	w.cobble_blobs.append([vc, 6.5, 1.0])
	Roman.statue(w, Vector3(vc.x + 3.0, 0, vc.y + 1.0), 0.6, 1.0, true)
	# a fountain at a crossroads
	var fp := beside(w, 0.9, 11.0)
	Roman.fountain(w, Vector3(fp.x, 0, fp.y))
	w.cobble_blobs.append([fp, 5.0, 1.0])

# ---------------------------------------------------------------- trees
## Pines and dead trees on the moor; past the pass, oaks and bushes with the Romans' cypresses.
static func _vegetation(w: World) -> void:
	var dt := [Flora.dead_tree(11), Flora.dead_tree(23), Flora.dead_tree(37)]
	var pines := [Flora.pine(4), Flora.pine(5), Flora.pine(6)]
	var oaks := [Flora.oak_model(1), Flora.oak_model(2), Flora.oak_model(3)]
	var bush := Flora.bush(3)
	var groups := {}
	var b := w.bounds
	var road_z_roman: float = at(w, ROMAN).y
	for i in 2200:
		var px := w.rng.randf_range(b.position.x - World.MARGIN + 3, b.end.x + World.MARGIN - 3)
		var pz := w.rng.randf_range(b.position.y - World.MARGIN + 3, b.end.y + 4)
		var inside := b.grow(-1.5).has_point(Vector2(px, pz))
		if inside and (w.path_dist(px, pz) < 7.0 or w.is_near_obstacle(Vector3(px, 0, pz), 2.5)):
			continue
		if inside and w.rng.randf() < 0.35:
			continue
		var roman := pz < road_z_roman
		var r := w.rng.randf()
		var key := "bush"
		if roman:
			key = "oak%d" % (i % 3) if r < 0.35 else ("pine%d" % (i % 3) if r < 0.5 else "bush")
		else:
			key = "pine%d" % (i % 3) if r < 0.42 else ("dead%d" % (i % 3) if r < 0.66 else ("oak%d" % (i % 3) if r < 0.74 else "bush"))
		if not groups.has(key):
			groups[key] = []
		var s := w.rng.randf_range(0.8, 1.35)
		groups[key].append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(px, w.height_at(px, pz) - 0.15, pz)))
		if inside and key != "bush":
			w.add_circle(Vector3(px, 0, pz), 0.45 if key.begins_with("dead") else (0.7 * s if key.begins_with("oak") else 0.55))
	for key in groups.keys():
		var mesh: Mesh = bush
		if key.begins_with("pine"):
			mesh = pines[int(key.substr(4))]
		elif key.begins_with("dead"):
			mesh = dt[int(key.substr(4))]
		elif key.begins_with("oak"):
			mesh = oaks[int(key.substr(3))]
		w.mm_chunked(mesh, groups[key], true, 32.0, 90.0 if key.begins_with("oak") else 0.0)

# ---------------------------------------------------------------- monsters
## The dead and the moor's things along the first stretches; on the Roman road the dead with a bandit
## band now and then; near the city the bandits hold the road.
static func _packs(w: World) -> void:
	var foes: Array = w.act_info()["foes"]
	var pid := 0
	var champ_done := false
	var t := 0.06
	while t < 0.97:
		if absf(t - AMBUSH) < 0.05:
			t = AMBUSH + 0.06     # the pass is the ambush's
			continue
		var p := beside(w, t, w.rng.randf_range(-12, 12), w.rng.randf_range(-3, 3))
		var pc := Vector3(p.x, 0, p.y)
		if not w.is_blocked(pc.x, pc.z):
			var k: String = foes[w.rng.randi() % foes.size()]
			if t > OUTSKIRTS:
				k = "bandit" if w.rng.randf() < 0.65 else "bandit_archer"
			elif t > ROMAN and w.rng.randf() < 0.25:
				k = "bandit"
			var cnt := w.rng.randi_range(3, 6) if not k.ends_with("archer") else w.rng.randi_range(2, 4)
			var champ := (w.rng.randf() < 0.12) or (not champ_done and t > 0.5)
			if champ:
				champ_done = true
				cnt = w.rng.randi_range(3, 4)
			w.enemy_spawns.append({"kind": k, "pos": pc, "count": cnt, "champ": champ, "pack": pid, "level": w.level + int(t * 4.0)})
			pid += 1
		t += w.rng.randf_range(0.035, 0.055)
