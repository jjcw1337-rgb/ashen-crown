class_name BgPeak
extends RefCounted
## Peak Ruins (jj, 2026-11-04: "a battleground map ... set on a high up mountain and you can barely see below"; his
## pick of three concepts, exports/bg_mountain/peak_ruins.png): a second Battlegrounds map, the Hollow Crypt's proven
## raid layout on a ruined summit above the clouds. Four corner crags are the spawns (a stash chest and a bell
## each), the four side platforms are two Extraction Portals and two treasure ledges, all joined round the ring by rope
## bridges, with a bridge from each side into the central courtyard and its rune circle (three chests and the
## champion). Everything off the stone is a sheer drop into the cloud sea: solid to walk into (World.rock, no walls
## drawn), the edges marked by the ruin's broken walls. Meshy props (assets/models/bg/peak/: wall, gate, tower,
## bridge, crag, brazier, from jj's concept). Battlegrounds.map_id "peak" picks it (the lobby's map choice,
## `--bg-map peak`).

const DIR := "res://assets/models/bg/peak/"
const R := 38.0                 # the ring: platform centres at (±R, ±R) (corners) and (0, ±R), (±R, 0) (sides)
const CORNER := 14.0            # a corner crag's platform
const SIDE := 13.0              # a side platform
const COURT := 30.0             # the courtyard
const BRIDGE_W := 4.0
const CLOUD_Y := -11.0          # the cloud sea, far under the stone

static func prop(name: String) -> Node3D:
	return ResCache.inst(DIR + name + ".glb") as Node3D

static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "bg_peak"}
	var plats := {}                       # Vector2i cell (-1..1) -> Rect2
	var kinds := {}
	for cell in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		var corner: bool = cell.x != 0 and cell.y != 0
		var s := CORNER if corner else SIDE
		var c := Vector2(cell.x * R, cell.y * R)
		plats[cell] = Rect2(c.x - s * 0.5, c.y - s * 0.5, s, s)
		kinds[cell] = "spawn" if corner else ""
	# the sides: two Extraction Portals facing each other, the other two treasure ledges
	var portal_axis := w.rng.randi() % 2
	for cell in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var on_axis: bool = (cell.x == 0) == (portal_axis == 0)
		kinds[cell] = "portal" if on_axis else "treasure"
	var court := Rect2(-COURT * 0.5, -COURT * 0.5, COURT, COURT)
	for cell in plats:
		w.floor_rects.append(plats[cell])
	w.floor_rects.append(court)
	# the bridges: round the ring (every link: on a summit there's no longer way round) and in from each side
	var bridges := []
	var ring := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	for k in 8:
		bridges.append(_bridge(w, plats[ring[k]], plats[ring[(k + 1) % 8]]))
	for cell in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		bridges.append(_bridge(w, plats[cell], court))
	var bb: Rect2 = w.floor_rects[0]
	for r in w.floor_rects:
		bb = bb.merge(r)
	w.bounds = bb.grow(3.0)
	w.dirt_blobs = []
	w.dirt_lines = []
	_void(w)
	# the look: stone and snow on crags falling into the clouds, the bridges, the ruin, the sky round it all
	for cell in plats:
		_platform(w, plats[cell], kinds[cell] == "spawn")
	_platform(w, court, false, true)
	for b in bridges:
		_bridge_model(w, b)
	_cloud_sea(w)
	_far_peaks(w)
	# what's on each platform
	var spawns := []
	var portals := []
	var foes := ["zombie", "skel_archer", "fallen_reaver", "fallen_skirmisher", "fallen_stalker"]
	var pack := 700
	for cell in plats:
		var r: Rect2 = plats[cell]
		var c := r.get_center()
		var out := Vector2(cell.x, cell.y).normalized()      # away from the courtyard
		_brazier(w, Vector3(c.x + out.y * (r.size.x * 0.38), 0, c.y - out.x * (r.size.y * 0.38)))
		_brazier(w, Vector3(c.x - out.y * (r.size.x * 0.38), 0, c.y + out.x * (r.size.y * 0.38)))
		match kinds[cell]:
			"spawn":
				spawns.append(Vector3(c.x, 0, c.y))
				_tower(w, Vector3(c.x + out.x * 4.0, 0, c.y + out.y * 4.0), atan2(out.x, out.y))
				Battlegrounds._bell(w, Vector3(c.x - out.x * 2.2 + 2.0, 0, c.y - out.y * 2.2))
				Battlegrounds._stash_chest(w, Vector3(c.x - out.x * 3.0 - 1.5, 0, c.y - out.y * 3.0 - 1.5), Battlegrounds.stash_chest_no())
			"portal":
				portals.append(Vector3(c.x + out.x * 2.5, 0, c.y + out.y * 2.5))
			"treasure":
				w._chest(Vector3(c.x + out.x * 3.0, 0, c.y + out.y * 3.0))
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": Vector3(c.x, 0, c.y), "count": w.rng.randi_range(1, 2),
					"champ": false, "pack": pack, "level": Battlegrounds.MON_LEVEL})
				pack += 1
		# a ruined wall along the outer edges (the drop's edge: only a look, the void is what stops you)
		_edge_walls(w, r, bridges)
	# the courtyard: the rune circle, braziers at its corners, three chests and its champion with bowmen
	var seal: Node3D = CryptProps.floor_seal()
	if seal != null:
		seal.position = Vector3(0, 0.02, 0)
		seal.scale = Vector3.ONE * 1.25
		w.props_root.add_child(seal)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_brazier(w, Vector3(sx * (COURT * 0.5 - 2.5), 0, sz * (COURT * 0.5 - 2.5)))
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		w._chest(Vector3(cos(a) * 5.5, 0, sin(a) * 5.5))
	_edge_walls(w, court, bridges)
	for b in bridges:
		_court_gate(w, b, court)
	w.enemy_spawns.append({"kind": "fallen_reaver", "pos": Vector3(0, 0, 0), "count": 1, "champ": true, "pack": 690, "level": Battlegrounds.MON_LEVEL + 2})
	w.enemy_spawns.append({"kind": "skel_archer", "pos": Vector3(0, 0, 6.0), "count": 2, "champ": false, "pack": 690, "level": Battlegrounds.MON_LEVEL})
	for p in portals:
		var glow: Node3D = CryptProps.portal_glow() if CryptProps.has("archway") else Fx.portal_model()
		var it: Inter = w._inter("extract", "Extraction Portal", p, 1.8, glow, {"open": false})
		var m := it.get_node_or_null("Model")
		if m:
			m.visible = false
		var arch := CryptProps.archway()
		if arch != null:
			arch.name = "Arch"
			it.add_child(arch)
	w.spawns["start"] = spawns[0] if not spawns.is_empty() else Vector3.ZERO
	w.set_meta("bg_spawns", spawns)
	w.set_meta("bg_gates", [])          # (no antechamber gates up here: the bridges are the chokepoints)

## A straight bridge between two platforms in line (same row or column): its walkable strip, returned.
static func _bridge(w: World, a: Rect2, b: Rect2) -> Rect2:
	var ca := a.get_center()
	var cb := b.get_center()
	var r: Rect2
	if absf(ca.y - cb.y) < 0.5:             # along x
		var left: Rect2 = a if ca.x < cb.x else b
		var right: Rect2 = b if ca.x < cb.x else a
		r = Rect2(left.end.x - 0.5, ca.y - BRIDGE_W * 0.5, right.position.x - left.end.x + 1.0, BRIDGE_W)
	else:                                    # along z
		var top: Rect2 = a if ca.y < cb.y else b
		var bot: Rect2 = b if ca.y < cb.y else a
		r = Rect2(ca.x - BRIDGE_W * 0.5, top.end.y - 0.5, BRIDGE_W, bot.position.y - top.end.y + 1.0)
	w.floor_rects.append(r)
	return r

## Off the stone is the drop: every cell that isn't floor is solid to walk into and blocked for paths (like the
## crypt's rock, World._rock_at), with nothing drawn there.
static func _void(w: World) -> void:
	w._rasterize()
	w.rock.resize(w.gw * w.gh)
	w.rock.fill(0)
	for y in w.gh:
		for x in w.gw:
			var p := Vector2(w.origin.x + (x + 0.5) * World.CELL, w.origin.y + (y + 0.5) * World.CELL)
			if w.is_floor(p.x, p.y):
				continue
			w.rock[y * w.gw + x] = 1
			w.blocked[y * w.gw + x] = 1
			w.astar.set_point_solid(Vector2i(x, y), true)

static func _stone() -> Material:
	return Mats.world(Color(0.24, 0.26, 0.31), Color(0.16, 0.17, 0.21), 0.92, 1.8, 0.0, Color(0.2, 0.3, 0.12), true, 0.0, Color.BLACK, 0.0, 0.35)

static func _snow() -> Material:
	return Mats.mat(Color(0.74, 0.79, 0.88), 0.9, 0.0)

## A platform: a stone slab with snow drifted at its edges, standing on a crag that falls away into the cloud.
static func _platform(w: World, r: Rect2, spawn: bool, court := false) -> void:
	var c := r.get_center()
	var slab := Models.P(w.props_root, Geo.box(r.size.x, 1.0, r.size.y), _stone(), Vector3(c.x, -0.5, c.y))
	slab.name = "slab"
	for k in w.rng.randi_range(2, 4):
		var e := Vector3(w.rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), 0.02, w.rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
		var drift := Models.P(w.props_root, Geo.cyl(w.rng.randf_range(0.6, 1.2), w.rng.randf_range(0.9, 1.6), 0.05, 12), _snow(), e)
		drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the crag under it: the Meshy rock stretched into a pillar, a second one offset for a broken silhouette
	for k in (3 if court else 2):
		var rock := prop("crag")
		if rock == null:
			break
		var sx := r.size.x / 6.5 * (1.15 if k == 0 else 0.8)
		var sz := r.size.y / 5.2 * (1.15 if k == 0 else 0.8)
		var sy := 4.2 if k == 0 else 3.2
		rock.scale = Vector3(sx, sy, sz)
		rock.rotation.y = w.rng.randf_range(0, TAU)
		rock.position = Vector3(c.x + (0.0 if k == 0 else w.rng.randf_range(-2.0, 2.0)), -0.6 - 7.0 * sy, c.y + (0.0 if k == 0 else w.rng.randf_range(-2.0, 2.0)))
		w.props_root.add_child(rock)
		# a second crag upside down hangs under the first: the pillar reaches down into the clouds
		var under := prop("crag")
		if under != null:
			under.scale = Vector3(sx * 0.7, sy * 1.2, sz * 0.7)
			under.rotation = Vector3(PI, w.rng.randf_range(0, TAU), 0)
			under.position = Vector3(rock.position.x, rock.position.y, rock.position.z)
			w.props_root.add_child(under)

static func _bridge_model(w: World, b: Rect2) -> void:
	var m := prop("bridge")
	var along_x := b.size.x > b.size.y
	var length := b.size.x if along_x else b.size.y
	if m == null:
		Models.P(w.props_root, Geo.box(b.size.x, 0.2, b.size.y), Mats.mat(Color(0.32, 0.24, 0.16), 0.9, 0.0), Vector3(b.get_center().x, -0.1, b.get_center().y))
		return
	m.scale = Vector3(length / 9.0, 1.0, BRIDGE_W / 1.75 * 0.8)
	m.rotation.y = 0.0 if along_x else PI * 0.5
	m.position = Vector3(b.get_center().x, -0.25, b.get_center().y)
	w.props_root.add_child(m)

## Broken wall segments along a platform's edges, leaving the bridges' ends open.
static func _edge_walls(w: World, r: Rect2, bridges: Array) -> void:
	var edges := [[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)],
		[Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y)]]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := int(floor(a.distance_to(b) / 5.0))
		for k in n:
			var t := (k + 0.5) / n
			var p := a.lerp(b, t)
			var open := false
			for br in bridges:
				if (br as Rect2).grow(1.5).has_point(p):
					open = true
			if open or w.rng.randf() < 0.3:
				continue                 # a bridge's end, or a gap where the wall has fallen
			var seg := prop("wall")
			if seg == null:
				return
			var d := (b - a).normalized()
			seg.rotation.y = -atan2(d.y, d.x)
			seg.scale = Vector3(1.0, w.rng.randf_range(0.45, 0.8), 0.6)       # low, broken: the camera sees over it
			var outward := Vector2(-d.y, d.x) * 0.9
			seg.position = Vector3(p.x + outward.x, 0, p.y + outward.y)
			w.props_root.add_child(seg)

## Where a side's bridge meets the courtyard: the ruined gate over it (a look: you walk under its arch).
static func _court_gate(w: World, b: Rect2, court: Rect2) -> void:
	if not b.intersects(court):
		return
	var g := prop("gate")
	if g == null:
		return
	var c := b.get_center()
	var along_x := b.size.x > b.size.y
	var at := Vector3(clampf(c.x, court.position.x, court.end.x), 0, clampf(c.y, court.position.y, court.end.y))
	if along_x:
		at.x = court.position.x if c.x < 0 else court.end.x
	else:
		at.z = court.position.y if c.y < 0 else court.end.y
	g.rotation.y = PI * 0.5 if along_x else 0.0
	g.scale = Vector3.ONE * 0.85
	g.position = at
	w.props_root.add_child(g)

static func _tower(w: World, p: Vector3, yaw: float) -> void:
	var t := prop("tower")
	if t == null:
		return
	t.rotation.y = yaw
	t.scale = Vector3.ONE * 0.8
	t.position = p
	w.props_root.add_child(t)
	Props.footprint(t, 2.7)
	w.solid(t)

static func _brazier(w: World, p: Vector3) -> void:
	var b := prop("brazier")
	if b != null:
		b.position = p
		w.props_root.add_child(b)
		Props.footprint(b, 0.5)
		w.solid(b)
	Props.fire(w.props_root, p + Vector3(0, 2.1, 0), 0.55, Color(1.0, 0.55, 0.22), false, false, true, "brazier")
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.32)
	l.light_energy = 1.3
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = p + Vector3(0, 2.6, 0)
	w.props_root.add_child(l)

## The cloud sea far below: two layers of drifting cloud, so you can barely see the valleys under it.
static func _cloud_sea(w: World) -> void:
	for k in 2:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(700, 700)
		pm.subdivide_width = 1
		pm.subdivide_depth = 1
		mi.mesh = pm
		var sm := ShaderMaterial.new()
		sm.shader = _cloud_shader()
		sm.set_shader_parameter("layer", float(k))
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, CLOUD_Y + k * 4.5, 0)
		w.props_root.add_child(mi)

static var _cloud_sh: Shader

static func _cloud_shader() -> Shader:
	if _cloud_sh == null:
		_cloud_sh = Shader.new()
		_cloud_sh.code = CLOUD_SHADER
	return _cloud_sh

const CLOUD_SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float layer = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), u.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * n(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * (0.018 + layer * 0.01) + vec2(TIME * (0.006 + layer * 0.004), TIME * 0.003);
	float c = fbm(p) * 0.75 + fbm(p * 2.7 + 4.0) * 0.35;
	float dens = smoothstep(0.32 + layer * 0.12, 0.85, c);
	vec3 lit = mix(vec3(0.1, 0.12, 0.18), vec3(0.62, 0.62, 0.7), smoothstep(0.3, 0.95, c));
	ALBEDO = lit;
	float far = 1.0 - smoothstep(180.0, 340.0, length(wp.xz));
	ALPHA = clamp((layer > 0.5 ? dens * 0.6 : 0.92) * far, 0.0, 1.0);
}
"""

## Snowy peaks far off round the summit, rising out of the clouds (the concept's skyline).
static func _far_peaks(w: World) -> void:
	var rock := Mats.mat(Color(0.3, 0.31, 0.34), 0.95, 0.0)
	var snow := Mats.mat(Color(0.84, 0.86, 0.9), 0.9, 0.0)
	for k in 16:
		var a := TAU * k / 16.0 + w.rng.randf_range(-0.12, 0.12)
		var dist := w.rng.randf_range(170.0, 280.0)
		var hgt := w.rng.randf_range(45.0, 95.0)
		var rad := hgt * w.rng.randf_range(0.5, 0.75)
		var base := Vector3(cos(a) * dist, CLOUD_Y - 10.0, sin(a) * dist)
		var body := Models.P(w.props_root, Geo.cyl(0.0, rad, hgt, 7), rock, base + Vector3(0, hgt * 0.5, 0))
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap := Models.P(w.props_root, Geo.cyl(0.0, rad * 0.42, hgt * 0.42, 7), snow, base + Vector3(0, hgt * 0.79 + 0.3, 0))
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
