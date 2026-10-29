class_name Roman
## Roman architecture for A2 (the Imperial Road and Aurelia), built in code: columns whole and broken,
## arches (an extruded wall with a round opening), the aqueduct's arcades, roadside tombs, milestones,
## marble statues, cypresses, fountains and the triumphal arch. Weathered travertine, tuff, brick and
## terracotta. Pieces that repeat (aqueduct bays, cypresses, column drums) go into MultiMeshes.

# ---------------------------------------------------------------- materials
static func marble() -> Material:
	return Mats.world(Color(0.84, 0.8, 0.72), Color(0.66, 0.62, 0.55), 0.82, 1.7, 0.22, Color(0.3, 0.34, 0.18))
static func marble_clean() -> Material:
	return Mats.world(Color(0.92, 0.9, 0.85), Color(0.78, 0.75, 0.7), 0.6, 2.2, 0.05, Color(0.3, 0.34, 0.18))
static func tuff() -> Material:
	return Mats.world(Color(0.56, 0.53, 0.47), Color(0.42, 0.4, 0.36), 0.92, 1.3, 0.35, Color(0.25, 0.3, 0.14))
static func brick() -> Material:
	return Mats.world(Color(0.58, 0.31, 0.2), Color(0.42, 0.21, 0.14), 0.9, 2.6, 0.2, Color(0.25, 0.3, 0.14))
static func tile() -> Material:
	return Mats.world(Color(0.66, 0.33, 0.2), Color(0.5, 0.24, 0.15), 0.8, 3.0, 0.1, Color(0.25, 0.3, 0.14))
static func bronze() -> Material:
	return Mats.world(Color(0.55, 0.42, 0.22), Color(0.32, 0.42, 0.34), 0.45, 1.8, 0.0, Color.BLACK, true, 0.75)
static func foliage() -> Material:
	return Mats.world(Color(0.1, 0.17, 0.08), Color(0.05, 0.1, 0.05), 0.95, 4.0)
static func red_cloth() -> Material:
	return Mats.world(Color(0.55, 0.08, 0.06), Color(0.35, 0.04, 0.03), 0.9, 1.5)

# ---------------------------------------------------------------- meshes
## A wall `w` wide, `h` tall and `d` deep with a round-topped opening `span` wide whose crown is `crown`
## high, centred, on the ground. Faces +z/-z; x across.
static func arch_mesh(w: float, h: float, d: float, span: float, crown: float) -> Mesh:
	var key := "arch%.2f_%.2f_%.2f_%.2f_%.2f" % [w, h, d, span, crown]
	var r := span * 0.5
	var spring := crown - r
	var pts := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(-r, 0), Vector2(-r, spring)])
	for i in range(1, 12):
		var a := PI - PI * i / 12.0
		pts.append(Vector2(cos(a) * r, spring + sin(a) * r))
	pts.append_array([Vector2(r, spring), Vector2(r, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Vector2(-w * 0.5, h)])
	return Geo.extrude(pts, d, key)

## A cypress: a tall dark flame of foliage on a short trunk.
static func cypress_mesh() -> Mesh:
	return Geo.lathe([Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.16, 0.5), Vector2(0.62, 0.9), Vector2(0.9, 2.2), Vector2(0.82, 3.8), Vector2(0.56, 5.0), Vector2(0.24, 5.9), Vector2(0.0, 6.3)], 9, "cypress")

static func _own(mesh: Mesh, m: Material) -> Mesh:
	var c: Mesh = mesh.duplicate()
	if c is PrimitiveMesh:
		(c as PrimitiveMesh).material = m
	else:
		for i in c.get_surface_count():
			c.surface_set_material(i, m)
	return c

# ---------------------------------------------------------------- pieces
## A column standing at p: plinth, base, a slightly tapering shaft, a capital. broken (0..1) snaps the
## shaft that far down and tips the stump's top.
static func column(w: World, p: Vector3, h := 4.5, r := 0.32, broken := 0.0, m: Material = null) -> Node3D:
	if m == null:
		m = marble()
	var g := Props.footprint(Models.N(null, "column"), r * 1.35)
	var sh := h * (1.0 - broken)
	Models.P(g, Geo.box(r * 2.7, 0.3, r * 2.7), m, Vector3(0, 0.15, 0))
	Models.P(g, Geo.cyl(r * 1.15, r * 1.25, 0.22, 14), m, Vector3(0, 0.41, 0))
	Models.P(g, Geo.cyl(r * 0.88, r, sh, 14), m, Vector3(0, 0.52 + sh * 0.5, 0))
	if broken <= 0.0:
		Models.P(g, Geo.cyl(r * 1.25, r * 0.92, 0.3, 14), m, Vector3(0, 0.52 + sh + 0.15, 0))
		Models.P(g, Geo.box(r * 2.8, 0.22, r * 2.8), m, Vector3(0, 0.52 + sh + 0.41, 0))
	else:
		Models.P(g, Geo.cyl(r * 0.6, r * 0.88, 0.25, 9), m, Vector3(0.05, 0.52 + sh + 0.08, 0), Vector3(0, 0, 14))
	w._place(g, p)
	g.rotation.y = w.rng.randf() * TAU
	w.solid(g)
	return g

## A column drum lying where it fell.
static func drum(w: World, p: Vector3, r := 0.32, l := 1.1) -> void:
	var g := Props.footprint(Models.N(null, "drum"), Vector2(l * 0.5, r))
	Models.P(g, Geo.cyl(r, r, l, 14), marble(), Vector3(0, r * 0.85, 0), Vector3(0, 0, 90))
	w._place(g, p)
	g.rotation.y = w.rng.randf() * TAU
	w.solid(g)

## A row of columns from a to b carrying a beam (entablature); broken: gaps and stumps, the beam fallen.
static func colonnade(w: World, a: Vector3, b: Vector3, n: int, h := 4.2, ruined := false) -> void:
	var cols: Array = []
	for i in n:
		var p := a.lerp(b, float(i) / maxf(n - 1, 1))
		var br := 0.0
		if ruined and w.rng.randf() < 0.5:
			br = w.rng.randf_range(0.3, 0.85)
		if ruined and w.rng.randf() < 0.15:
			drum(w, p + Vector3(w.rng.randf_range(-1.5, 1.5), 0, w.rng.randf_range(-1.5, 1.5)))
			continue
		cols.append(column(w, p, h, 0.3, br))
	if not ruined:
		var d := b - a
		var beam := Models.N(null, "entablature")
		Models.P(beam, Geo.box(d.length() + 0.9, 0.55, 0.85), marble(), Vector3(0, 0, 0))
		Models.P(beam, Geo.box(d.length() + 1.1, 0.18, 1.0), marble(), Vector3(0, 0.36, 0))
		var mid := (a + b) * 0.5
		w._place(beam, mid)
		beam.position.y += 0.52 + h + 0.8
		beam.rotation.y = atan2(-d.z, d.x)

## The aqueduct: a line of arches from a to b (two tiers, the channel on top), striding over whatever is
## below; bays are missing here and there and the upper tier is broken in places. Piers are solid, the
## arches open (a road passes under: the bay over `clear` always stands).
static func aqueduct(w: World, a: Vector2, b: Vector2, gaps := 0.12, clear := Vector2(1e9, 1e9)) -> void:
	var d := b - a
	var n := int(d.length() / 5.6)
	var dir := d / d.length()
	var yaw := atan2(-dir.y, dir.x)
	var low: Array = []
	var high: Array = []
	var chan: Array = []
	var low_m := _own(arch_mesh(5.6, 8.2, 2.0, 4.0, 6.6), tuff())
	var high_m := _own(arch_mesh(5.6, 3.6, 1.6, 2.6, 2.7), tuff())
	var chan_m := _own(Geo.box(5.6, 0.9, 1.8), brick())
	for i in n:
		var c := a + dir * (5.6 * (i + 0.5))
		var hy := w.height_at(c.x, c.y)
		var keep := c.distance_to(clear) < 4.0
		if w.rng.randf() < gaps and i > 1 and i < n - 2 and not keep and c.distance_to(clear) > 9.0:
			# a fallen bay: the piers' stumps and rubble
			for s in [-1, 1]:
				var pp: Vector2 = c + dir * s * 2.2
				column(w, Vector3(pp.x, 0, pp.y), 1.4, 0.75, 0.3, tuff())
			for k in 3:
				drum(w, Vector3(c.x + w.rng.randf_range(-3, 3), 0, c.y + w.rng.randf_range(-2.5, 2.5)), 0.5, 1.2)
			continue
		var base := Basis(Vector3.UP, yaw)
		low.append(Transform3D(base, Vector3(c.x, hy - 1.0, c.y)))
		var broken := w.rng.randf() < 0.18 and not keep
		if not broken:
			high.append(Transform3D(base, Vector3(c.x, hy - 1.0 + 8.2, c.y)))
			chan.append(Transform3D(base, Vector3(c.x, hy - 1.0 + 8.2 + 3.6 + 0.45, c.y)))
		# the piers between the arches are solid (0.8 m each side of a bay's 4 m opening)
		for s in [-1, 1]:
			var pp: Vector2 = c + dir * s * 2.4
			w.add_box(Vector3(pp.x, 0, pp.y), Vector2(1.0, 0.42), atan2(dir.x, dir.y))
	var root := Models.N(w.props_root, "aqueduct")
	root.set_meta("roman", "aqueduct")
	Props.multimesh(root, low_m, low)
	Props.multimesh(root, high_m, high)
	Props.multimesh(root, chan_m, chan)

## A roadside tomb: a marble house-tomb with a pediment and pilasters, or a round drum tomb with an
## earth cap (style 0/1).
static func tomb(w: World, p: Vector3, yaw: float, style := 0) -> void:
	var m := marble()
	if style == 0:
		var g := Props.footprint(Models.N(null, "tomb"), Vector2(1.7, 1.7))
		Models.P(g, Geo.box(3.4, 1.0, 3.4), tuff(), Vector3(0, 0.5, 0))
		Models.P(g, Geo.box(2.8, 2.6, 2.8), m, Vector3(0, 2.3, 0))
		Models.P(g, Geo.box(3.1, 0.3, 3.1), m, Vector3(0, 3.75, 0))
		var ped := Models.P(g, Geo.prism(3.1, 1.0, 3.1), tile(), Vector3(0, 4.4, 0))
		ped.rotation.y = PI * 0.5
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				Models.P(g, Geo.cyl(0.15, 0.17, 2.6, 10), m, Vector3(sx * 1.38, 2.3, sz * 1.38))
		Models.P(g, Geo.box(1.0, 1.7, 0.08), bronze(), Vector3(0, 2.0, 1.42))
		Models.P(g, Geo.box(1.8, 0.35, 0.05), Mats.mat(Color(0.25, 0.22, 0.2), 0.9), Vector3(0, 3.25, 1.42))
		w._place(g, p)
		g.rotation.y = yaw
		w.solid(g)
	else:
		var g := Props.footprint(Models.N(null, "tomb"), 3.0)
		Models.P(g, Geo.cyl(3.0, 3.1, 0.8, 24), tuff(), Vector3(0, 0.4, 0))
		Models.P(g, Geo.cyl(2.7, 2.7, 3.2, 24), m, Vector3(0, 2.4, 0))
		Models.P(g, Geo.cyl(2.85, 2.85, 0.3, 24), m, Vector3(0, 4.1, 0))
		Models.P(g, Geo.sph(2.6, 16, 0.5), Mats.world(Color(0.22, 0.26, 0.12), Color(0.16, 0.2, 0.09), 0.95, 2.0), Vector3(0, 4.2, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
		Models.P(g, Geo.box(1.2, 0.4, 0.06), Mats.mat(Color(0.25, 0.22, 0.2), 0.9), Vector3(0, 3.0, 2.72))
		w._place(g, p)
		g.rotation.y = yaw
		w.solid(g)

## A Roman milestone (miliarium): a squat inscribed column on a square base.
static func milestone(w: World, p: Vector3, yaw: float) -> void:
	var g := Props.footprint(Models.N(null, "miliarium"), 0.45)
	Models.P(g, Geo.box(0.9, 0.35, 0.9), tuff(), Vector3(0, 0.17, 0))
	Models.P(g, Geo.cyl(0.32, 0.36, 1.6, 12), marble(), Vector3(0, 1.15, 0))
	Models.P(g, Geo.box(0.42, 0.5, 0.02), Mats.mat(Color(0.3, 0.27, 0.24), 0.9), Vector3(0, 1.3, 0.34))
	w._place(g, p)
	g.rotation = Vector3(w.rng.randf_range(-0.06, 0.06), yaw, w.rng.randf_range(-0.08, 0.08))
	w.solid(g)

const STATUE_GLB := "res://assets/models/knight_armored.glb"

## A marble statue on a plinth: the Meshy crusader (STATUE_GLB) carved in marble, or without it the
## game's humanoid in a heroic stance, an arm raised with a spear; toppled (or headless) when broken.
static func statue(w: World, p: Vector3, yaw: float, s := 1.25, broken := false) -> Node3D:
	var g := Props.footprint(Models.N(null, "statue"), 0.9)
	Models.P(g, Geo.box(1.6, 1.4, 1.6), tuff(), Vector3(0, 0.7, 0))
	Models.P(g, Geo.box(1.8, 0.2, 1.8), marble(), Vector3(0, 1.5, 0))
	Models.P(g, Geo.box(1.1, 0.3, 0.04), Mats.mat(Color(0.3, 0.27, 0.24), 0.9), Vector3(0, 0.95, 0.81))
	var mm := marble_clean()
	var fig: Node3D
	if ResourceLoader.exists(STATUE_GLB):
		# the Meshy crusader (the knight in plate) carved in marble, in his rest pose
		fig = Node3D.new()
		var body: Node3D = (load(STATUE_GLB) as PackedScene).instantiate()
		fig.add_child(body)
		body.rotation.y = PI          # the glb faces +z; a statue faces its plinth's front like the old figure
		var top := 0.0
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mm
			top = maxf(top, (mi as MeshInstance3D).get_aabb().end.y)
		body.scale = Vector3.ONE * (1.8 * s / maxf(top, 0.1))
	else:
		var white := Color(0.88, 0.86, 0.8)
		fig = Models.humanoid({"skin": white, "cloth": white, "cloth2": white, "armor": white, "height": s, "bulk": 1.1, "head": "human", "hair": white, "cape": white})
		for mi in fig.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mm
	g.add_child(fig)
	fig.position = Vector3(0, 1.6, 0)
	if fig.has_meta("j"):
		var J: Dictionary = fig.get_meta("j")
		if J.has("sh_r"):
			(J["sh_r"] as Node3D).rotation = Vector3(deg_to_rad(-150), 0, deg_to_rad(-10))
		if J.has("sh_l"):
			(J["sh_l"] as Node3D).rotation = Vector3(deg_to_rad(-20), 0, deg_to_rad(15))
		if J.has("hand_r"):
			Models.seg(J["hand_r"], Vector3(0, -1.0, 0), Vector3(0, 1.2, 0), 0.025, 0.025, mm, 6)
		if broken and J.has("head"):
			(J["head"] as Node3D).visible = false
	if broken and w.rng.randf() < 0.5:
		fig.rotation = Vector3(deg_to_rad(80), 0, 0)
		fig.position = Vector3(0, 1.9, 1.0)
	w._place(g, p)
	g.rotation.y = yaw
	w.solid(g)
	return g

## A fountain: a round basin of dark water with a bronze spout on a pillar.
static func fountain(w: World, p: Vector3) -> void:
	var g := Props.footprint(Models.N(null, "fountain"), 2.4)
	Models.P(g, Geo.cyl(2.4, 2.5, 0.7, 28), marble(), Vector3(0, 0.35, 0))
	Models.P(g, Geo.cyl(2.15, 2.15, 0.05, 28), Mats.shader_water_mat(Color(0.04, 0.08, 0.08), Color(0.1, 0.18, 0.16)), Vector3(0, 0.6, 0))
	Models.P(g, Geo.cyl(0.35, 0.45, 1.8, 12), marble(), Vector3(0, 1.2, 0))
	Models.P(g, Geo.cyl(0.9, 0.4, 0.3, 16), bronze(), Vector3(0, 2.1, 0))
	w._place(g, p)
	w.solid(g)

## The triumphal arch over the road into Aurelia: a great vault between massive piers, engaged columns,
## a dark inscription on the attic, bronze figures on top. Faces along the road (yaw).
static func triumphal_arch(w: World, p: Vector3, yaw: float) -> Node3D:
	var g := Models.N(null, "triumphal_arch")
	g.set_meta("roman", "arch")
	var m := marble()
	Models.P(g, _own(arch_mesh(13.0, 10.0, 3.6, 6.0, 8.2), m), m)
	Models.P(g, Geo.box(13.4, 2.6, 3.9), m, Vector3(0, 11.3, 0))
	Models.P(g, Geo.box(13.8, 0.35, 4.1), m, Vector3(0, 10.05, 0))
	Models.P(g, Geo.box(7.5, 1.5, 0.06), Mats.mat(Color(0.22, 0.2, 0.18), 0.9), Vector3(0, 11.3, 1.97))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Models.P(g, Geo.cyl(0.38, 0.42, 9.0, 14), m, Vector3(sx * 5.3, 4.5, sz * 2.0))
		Models.P(g, Geo.box(1.4, 2.0, 0.1), Mats.mat(Color(0.3, 0.27, 0.24), 0.9), Vector3(sx * 4.0, 5.0, 1.85))
	# a bronze chariot-group stand-in on top: horses' backs and a figure
	for k in 4:
		Models.P(g, Geo.box(0.5, 0.9, 2.0), bronze(), Vector3(-1.5 + k, 13.1, 0.2))
	Models.P(g, Geo.cyl(0.35, 0.4, 2.2, 10), bronze(), Vector3(0, 13.7, -1.0))
	w._place(g, p)
	g.rotation.y = yaw
	for sx in [-1, 1]:
		var o := Basis(Vector3.UP, yaw) * Vector3(sx * 5.0, 0, 0)
		w.add_box(p + o, Vector2(1.5, 1.95), yaw)
	return g

## Cypresses (a MultiMesh): the tall dark trees lining Roman roads.
static func cypresses(w: World, at: Array) -> void:
	var xf: Array = []
	for p in at:
		var q: Vector3 = p
		var s := w.rng.randf_range(0.8, 1.25)
		xf.append(Transform3D(Basis(Vector3.UP, w.rng.randf() * TAU).scaled(Vector3(s, s * w.rng.randf_range(0.9, 1.25), s)), Vector3(q.x, w.height_at(q.x, q.z) - 0.1, q.z)))
		w.add_circle(Vector3(q.x, 0, q.z), 0.45 * s)
	Props.multimesh(w.props_root, _own(cypress_mesh(), foliage()), xf)

## A low ruined wall of brick on a tuff footing from a to b, uneven along its top.
static func ruin_wall(w: World, a: Vector2, b: Vector2, h := 1.6) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 1.2))
	var g := Models.N(null, "ruin")
	for i in n:
		var hh := h * w.rng.randf_range(0.35, 1.0)
		var x := -d.length() * 0.5 + (i + 0.5) * d.length() / n
		Models.P(g, Geo.box(d.length() / n + 0.02, hh, 0.6), brick(), Vector3(x, hh * 0.5 + 0.3, 0))
	Models.P(g, Geo.box(d.length() + 0.2, 0.35, 0.75), tuff(), Vector3(0, 0.17, 0))
	var mid := (a + b) * 0.5
	w._place(g, Vector3(mid.x, 0, mid.y))
	g.rotation.y = atan2(-d.y, d.x)
	w.add_box(Vector3(mid.x, 0, mid.y), Vector2(0.4, d.length() * 0.5), atan2(d.x, d.y))
