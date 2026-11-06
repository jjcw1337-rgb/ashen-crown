class_name BgFloors
extends RefCounted
## The Hollow Crypt's lower floors (Blaine's overhaul, docs/queue_battlegrounds_overhaul.md): under the Ossuary
## (floor 1, Battlegrounds.build) lie the Frozen Depths (floor 2: ice-white stone, frost on the floors, cold light,
## the hall of Hrimgar the Frostbound) and the Overgrown Vault (floor 3: something alive has broken in through the
## stone: thorny brambles spilling out of the hermit's grove into the corridors, vines up the pillars, giant
## glowing mushrooms, Old Mossbeard and his golden chest). All three are one raid map (one zone on the server),
## laid out FLOOR_GAP apart; stairways (Inter "descend") take a hero down with a fade (Game._interact).
##
## Each floor is a graph of named rooms (ROOMS2/ROOMS3: centre, size, kind) joined by corridors (LINKS: wide ways,
## narrow shortcuts), so it branches and loops (you can get a little lost) round a boss arena in the middle, with
## landmarks you learn: the arrival stair, the treasure vaults, the portal rooms, the stair down. Every floor has
## its own extraction portals; deeper floors have tougher monsters (FOES, levels) and better chests.
##   BgFloors.build(w)        from Battlegrounds.build, after floor 1's rooms and before the walls
##   BgFloors.themes()        the walls' colours per floor, for World.crypt_shell
##   BgFloors.floor_of(p)     1, 2 or 3

const FLOOR_GAP := 150.0                    # floor n's origin is (0, (n - 1) * FLOOR_GAP)
const PROP_DIR := "res://assets/models/bg/%s.glb"
const NAMES := {1: "The Ossuary", 2: "The Frozen Depths", 3: "The Overgrown Vault"}
const LIGHT := {2: Color(0.55, 0.8, 1.0), 3: Color(0.55, 1.0, 0.45)}
const FOES := {2: ["zombie", "skel_archer", "fallen_reaver"], 3: ["spider", "fetish", "lizardman", "fallen_stalker"]}
const LEVEL_ADD := {2: 2, 3: 4}

## name: [centre (floor-local), size, kind]. kinds: arrive, boss, treasure, crypt, portal, descend, shrine
const ROOMS2 := {
	"frost_stair": [Vector2(-40, -40), Vector2(13, 12), "arrive"],
	"cold_vault": [Vector2(0, -44), Vector2(12, 10), "treasure"],
	"icefall": [Vector2(40, -40), Vector2(15, 13), "crypt"],
	"barracks": [Vector2(-42, 0), Vector2(14, 17), "crypt"],
	"hrimgar": [Vector2(0, 0), Vector2(34, 30), "boss"],
	"rime_shrine": [Vector2(42, 0), Vector2(12, 12), "portal"],
	"gullet": [Vector2(-40, 42), Vector2(12, 12), "portal"],
	"frozen_lake": [Vector2(0, 44), Vector2(18, 11), "treasure"],
	"root_stair": [Vector2(40, 42), Vector2(12, 12), "descend"],
}
const LINKS2 := [["frost_stair", "barracks", 3.0], ["frost_stair", "cold_vault", 3.0], ["cold_vault", "icefall", 3.0],
	["icefall", "rime_shrine", 3.0], ["barracks", "gullet", 3.0], ["gullet", "frozen_lake", 3.0], ["frozen_lake", "root_stair", 3.0],
	["barracks", "hrimgar", 4.0], ["rime_shrine", "hrimgar", 4.0], ["hrimgar", "frozen_lake", 3.0], ["rime_shrine", "root_stair", 2.0],
	["cold_vault", "hrimgar", 2.0]]
const ROOMS3 := {
	"root_bottom": [Vector2(-40, -40), Vector2(12, 12), "arrive"],
	"spore_halls": [Vector2(0, -42), Vector2(20, 12), "crypt"],
	"sunken_library": [Vector2(42, -40), Vector2(14, 14), "treasure"],
	"thornway": [Vector2(-42, 0), Vector2(12, 18), "crypt"],
	"grove": [Vector2(0, 0), Vector2(32, 30), "boss"],
	"fungal_pit": [Vector2(42, 0), Vector2(14, 14), "portal"],
	"bramble_crypt": [Vector2(-40, 42), Vector2(13, 12), "portal"],
	"weeping_vault": [Vector2(0, 44), Vector2(14, 10), "treasure"],
	"rot_shrine": [Vector2(40, 42), Vector2(12, 12), "crypt"],
}
const LINKS3 := [["root_bottom", "spore_halls", 3.0], ["root_bottom", "thornway", 3.0], ["spore_halls", "sunken_library", 3.0],
	["sunken_library", "fungal_pit", 3.0], ["thornway", "bramble_crypt", 3.0], ["bramble_crypt", "weeping_vault", 3.0],
	["weeping_vault", "rot_shrine", 3.0], ["rot_shrine", "fungal_pit", 2.0], ["thornway", "grove", 4.0], ["fungal_pit", "grove", 3.0],
	["spore_halls", "grove", 2.0]]

static var _props := {}

static func origin(n: int) -> Vector2:
	return Vector2(0, (n - 1) * FLOOR_GAP)

static func floor_of(p: Vector3) -> int:
	return clampi(int(round(p.z / FLOOR_GAP)) + 1, 1, 3)

static func themes() -> Array:
	return [{"rect": Rect2(-80, FLOOR_GAP - 75, 160, 150), "a": Color(0.62, 0.68, 0.74), "b": Color(0.42, 0.48, 0.56), "moss": Color(0.7, 0.82, 0.95)},
		{"rect": Rect2(-80, FLOOR_GAP * 2 - 75, 160, 150), "a": Color(0.34, 0.36, 0.28), "b": Color(0.22, 0.25, 0.17), "moss": Color(0.2, 0.36, 0.12)}]

static func prop(name: String) -> Node3D:
	if not _props.has(name):
		var path := PROP_DIR % name
		_props[name] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _props[name]
	return ps.instantiate() if ps else null

## Both lower floors, and the stairs down from floor 1 (`descents1`: where floor 1 puts its stairways).
static func build(w: World, descents1: Array) -> void:
	var r2 := _floor(w, 2, ROOMS2, LINKS2)
	var r3 := _floor(w, 3, ROOMS3, LINKS3)
	var arrive2: Vector3 = _centre(r2["frost_stair"]) + Vector3(0, 0, 2.5)
	var arrive3: Vector3 = _centre(r3["root_bottom"]) + Vector3(0, 0, 2.5)
	for p in descents1:
		_stair(w, p, arrive2, "Stairs down to the Frozen Depths", 2)
	_stair(w, _centre(r2["root_stair"]), arrive3, "The Root Stair, down to the Overgrown Vault", 3)
	w.set_meta("bg_arrive", {2: arrive2, 3: arrive3})

static func _centre(r: Rect2) -> Vector3:
	var c := r.get_center()
	return Vector3(c.x, 0, c.y)

## One floor: its rooms and corridors into World.floor_rects, then each room dressed by its kind and the floor's look.
static func _floor(w: World, n: int, rooms_def: Dictionary, links: Array) -> Dictionary:
	var o := origin(n)
	var rooms := {}
	for key in rooms_def:
		var d: Array = rooms_def[key]
		var c: Vector2 = o + d[0]
		var sz: Vector2 = d[1] * w.rng.randf_range(0.94, 1.06)
		rooms[key] = Rect2(c - sz * 0.5, sz)
		w.floor_rects.append(rooms[key])
	for l in links:
		_link(w, rooms[l[0]], rooms[l[1]], float(l[2]) * 0.5)
	if n == 3:
		# the grove has broken out: thorns and moss creep along every way out of it, thinning as they go
		for l in links:
			if not "grove" in [l[0], l[1]]:
				continue
			var g3: Vector2 = (rooms["grove"] as Rect2).get_center()
			var other: Vector2 = (rooms[l[1] if l[0] == "grove" else l[0]] as Rect2).get_center()
			_creep(w, g3, other)
	var pack := 800 + n * 40
	var foes: Array = FOES[n]
	var lvl: int = Battlegrounds.MON_LEVEL + int(LEVEL_ADD[n])
	for key in rooms:
		var r: Rect2 = rooms[key]
		var c := _centre(r)
		var kind: String = rooms_def[key][2]
		_light_room(w, r, n, kind)
		_dress(w, r, n, kind)
		match kind:
			"boss":
				var boss := "ice_troll" if n == 2 else "hermit"
				w.enemy_spawns.append({"kind": boss, "pos": c, "count": 1, "champ": false, "pack": pack, "level": lvl + 2})
				pack += 1
				if n == 3:
					# the golden chest behind him, against the grove's north wall: sealed while he lives
					var cp := Vector3(c.x, 0, r.position.y + 3.2)
					var m := prop("gold_chest")
					if m == null:
						m = Props.stash_chest(null, Vector3.ZERO, 0.0)
					# (the Meshy chest is prepared at its size, 2 m wide; the stand-in stash chest is grown to match)
					if not ResourceLoader.exists(PROP_DIR % "gold_chest"):
						m.scale = Vector3.ONE * 1.7
					var it: Inter = w._inter("chest", "The Golden Chest", cp, 2.2, m, {"gold": true, "guard": "hermit"})
					Props.footprint(it, Vector2(1.2, 0.8))
					w.solid(it)
					var gl := OmniLight3D.new()
					gl.light_color = Color(1.0, 0.8, 0.35)
					gl.light_energy = 2.2
					gl.omni_range = 7.0
					gl.position = Vector3(0, 2.0, 1.5)
					it.add_child(gl)
			"treasure":
				w._chest(c + Vector3(w.rng.randf_range(-2, 2), 0, w.rng.randf_range(-1.5, 1.5)))
				if n == 3:
					w._chest(c + Vector3(w.rng.randf_range(2.5, 4), 0, 0))
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": c, "count": 2, "champ": w.rng.randf() < 0.5, "pack": pack, "level": lvl})
				pack += 1
			"portal":
				var it: Inter = w._inter("extract", "Extraction Portal", c, 1.8, Fx.portal_model(), {"open": false, "floor": n})
				var pm := it.get_node_or_null("Model")
				if pm:
					pm.visible = false
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": c + Vector3(3, 0, 0), "count": 1, "champ": false, "pack": pack, "level": lvl})
				pack += 1
			"crypt":
				w.enemy_spawns.append({"kind": foes[w.rng.randi() % foes.size()], "pos": c, "count": w.rng.randi_range(2, 3), "champ": w.rng.randf() < 0.3, "pack": pack, "level": lvl})
				pack += 1
				if w.rng.randf() < 0.5:
					w._chest(Vector3(c.x + w.rng.randf_range(-3, 3), 0, r.position.y + 2.0))
	return rooms

## A corridor `hw` either side of the line between two rooms (straight or an L, like floor 1's).
static func _link(w: World, a: Rect2, b: Rect2, hw: float) -> void:
	var ca := a.get_center()
	var cb := b.get_center()
	if absf(ca.y - cb.y) < 1.0:
		w.floor_rects.append(Rect2(minf(ca.x, cb.x), ca.y - hw, absf(cb.x - ca.x), hw * 2.0))
	elif absf(ca.x - cb.x) < 1.0:
		w.floor_rects.append(Rect2(ca.x - hw, minf(ca.y, cb.y), hw * 2.0, absf(cb.y - ca.y)))
	else:
		w.floor_rects.append(Rect2(minf(ca.x, cb.x) - hw, ca.y - hw, absf(cb.x - ca.x) + hw * 2.0, hw * 2.0))
		w.floor_rects.append(Rect2(cb.x - hw, minf(ca.y, cb.y) - hw, hw * 2.0, absf(cb.y - ca.y) + hw * 2.0))

## Thorns and moss along the way from the grove (at a) toward another room (b): an L like the corridor (along x
## first, then z), decals of moss down its length and brambles, denser near the grove.
static func _creep(w: World, a: Vector2, b: Vector2) -> void:
	var corner := Vector2(b.x, a.y)
	var legs := [[a, corner], [corner, b]] if absf(a.y - b.y) > 1.0 and absf(a.x - b.x) > 1.0 else [[a, b]]
	var t_all := 0.0
	for leg in legs:
		var p0: Vector2 = leg[0]
		var p1: Vector2 = leg[1]
		var length := p0.distance_to(p1)
		if length < 1.0:
			continue
		var dir := (p1 - p0) / length
		var side := Vector2(-dir.y, dir.x)
		var s0 := 14.0 if leg == legs[0] else 0.0          # (start outside the grove's own floor)
		var d := s0
		while d < length:
			var fade := 1.0 - clampf((t_all + d - s0) / 26.0, 0.0, 1.0)
			if fade <= 0.05:
				break
			var at := p0 + dir * d
			var dc := Decal.new()
			dc.size = Vector3(3.6, 4.0, 3.6) * (0.7 + fade * 0.5)
			var tex := _moss_tex()
			dc.texture_albedo = tex[0]
			dc.texture_emission = tex[1]
			dc.emission_energy = 1.0
			dc.modulate = Color(1, 1, 1, 0.5 + fade * 0.5)
			dc.position = Vector3(at.x, 0.0, at.y)
			w.props_root.add_child(dc)
			if w.rng.randf() < 0.35 + fade * 0.5:
				var m := prop("brambles")
				if m != null:
					var off := side * w.rng.randf_range(-0.9, 0.9)
					m.scale = Vector3.ONE * w.rng.randf_range(0.35, 0.6) * (0.6 + fade * 0.6)
					w._place(m, Vector3(at.x + off.x, 0, at.y + off.y))
					m.rotation.y = w.rng.randf() * TAU
					# the Meshy thicket is a flat tangle: a second one across it makes a clump from any side
					var m2 := prop("brambles")
					if m2 != null:
						m2.scale = m.scale * 0.85
						w._place(m2, m.position)
						m2.rotation.y = m.rotation.y + PI * 0.5
			d += w.rng.randf_range(2.2, 3.4)
		t_all += length

## The floor's light: cold blue on floor 2, a sickly green glow on floor 3 (a light or two per room, no shadows),
## plus the floor's torches.
static func _light_room(w: World, r: Rect2, n: int, kind: String) -> void:
	var c := r.get_center()
	var k := 2 if kind == "boss" else 1
	for i in k:
		var l := OmniLight3D.new()
		l.light_color = LIGHT[n]
		l.light_energy = (1.4 if kind == "boss" else 0.9) * (1.6 if n == 3 else 1.0)
		l.omni_range = maxf(r.size.x, r.size.y) * (0.55 if kind == "boss" else 0.8)
		l.shadow_enabled = false
		l.position = Vector3(c.x + (i - 0.5) * r.size.x * 0.4 * float(k - 1), 3.2, c.y)
		w.props_root.add_child(l)
	w._wall_torch(Vector3(c.x, 0, r.position.y + 0.15), false)

## The floor's dressing: Meshy pieces (assets/models/bg/), the floor's ground decal (frost, or moss and roots).
static func _dress(w: World, r: Rect2, n: int, kind: String) -> void:
	var c := r.get_center()
	var big := kind == "boss"
	# the ground: frost on floor 2, moss and creeping roots on floor 3
	var d := Decal.new()
	d.size = Vector3(r.size.x * 1.15, 6.0, r.size.y * 1.15)
	var tex: Array = SlothLair._ground_tex("cold") if n == 2 else _moss_tex()
	d.texture_albedo = tex[0]
	d.texture_emission = tex[1]
	d.emission_energy = 0.4 if n == 2 else 1.2
	d.albedo_mix = 0.9
	d.position = Vector3(c.x, 0.0, c.y)
	w.props_root.add_child(d)
	var pieces: Array = ["ice_crystals", "frozen_pillar"] if n == 2 else ["mushrooms", "brambles", "vine_pillar", "fungus"]
	var count := 10 if big else w.rng.randi_range(2, 4)
	for i in count:
		var nm: String = pieces[w.rng.randi() % pieces.size()]
		# round the walls, clear of the room's middle (where the fighting is) and of the doorways' line
		var t := w.rng.randf()
		var side := w.rng.randi() % 4
		var p := Vector2()
		match side:
			0: p = Vector2(lerpf(r.position.x + 1.5, r.end.x - 1.5, t), r.position.y + 1.4)
			1: p = Vector2(lerpf(r.position.x + 1.5, r.end.x - 1.5, t), r.end.y - 1.4)
			2: p = Vector2(r.position.x + 1.4, lerpf(r.position.y + 1.5, r.end.y - 1.5, t))
			_: p = Vector2(r.end.x - 1.4, lerpf(r.position.y + 1.5, r.end.y - 1.5, t))
		if absf(p.x - c.x) < 2.0 or absf(p.y - c.y) < 2.0:
			continue
		var pos := Vector3(p.x, 0, p.y)
		if w.is_near_obstacle(pos, 1.2):
			continue
		# Instantiate only after placement is accepted; rejected unparented scenes leak.
		var m := prop(nm)
		if m == null:
			continue
		var sc := w.rng.randf_range(0.8, 1.25) * (1.3 if big else 1.0)
		m.scale = Vector3.ONE * sc
		w._place(m, pos)
		m.rotation.y = w.rng.randf() * TAU
		if nm in ["ice_crystals", "frozen_pillar"]:
			_ice(m)
		# footprints from the prepared models' sizes (prep_prop.py's half-extents), scaled
		var foot := {"frozen_pillar": 1.6, "vine_pillar": 0.9, "ice_crystals": 0.8, "mushrooms": 1.4, "brambles": 0.0, "fungus": 0.45}
		if float(foot.get(nm, 0.0)) > 0.0:
			w.add_circle(pos, float(foot[nm]) * sc)
	if n == 3:
		# everywhere on this floor: fungus glowing in the corners, a mushroom or two
		for i in (3 if not big else 0):
			var fp := Vector3(lerpf(r.position.x + 1.2, r.end.x - 1.2, w.rng.randf()), 0, r.position.y + 1.2 if i % 2 == 0 else r.end.y - 1.2)
			if w.is_near_obstacle(fp, 1.0):
				continue
			var fm := prop("fungus")
			if fm != null:
				fm.scale = Vector3.ONE * w.rng.randf_range(0.7, 1.2)
				w._place(fm, fp)
				fm.rotation.y = w.rng.randf() * TAU
	if n == 3 and big:
		# the grove: a ring of giant mushrooms round the walls, their caps glowing over the arena, fungus between
		for i in 10:
			var a := TAU * i / 10.0 + 0.15
			var mp := Vector3(c.x + cos(a) * (r.size.x * 0.5 - 2.6), 0, c.y + sin(a) * (r.size.y * 0.5 - 2.6))
			if absf(mp.z - (r.position.y + 3.2)) < 3.0 and absf(mp.x - c.x) < 3.5:
				continue                          # (clear of the golden chest)
			var mm := prop("mushrooms" if i % 3 != 2 else "fungus")
			if mm != null:
				var k := w.rng.randf_range(1.0, 1.5) if i % 3 != 2 else 1.6
				mm.scale = Vector3.ONE * k
				w._place(mm, mp)
				mm.rotation.y = w.rng.randf() * TAU
				if i % 3 != 2:
					w.add_circle(mp, 1.2 * k)
			if i % 2 == 1:
				continue                          # one light for every two caps (Codex's audit: ten was a lot over the room's own)
			var l := OmniLight3D.new()
			l.light_color = Color(0.4, 1.0, 0.55) if i % 4 == 0 else Color(0.7, 0.45, 1.0)
			l.light_energy = 2.0
			l.omni_range = 9.5
			l.shadow_enabled = false
			l.position = mp + Vector3(0, 2.6, 0)
			w.props_root.add_child(l)

## A stairway down: a dark well of steps in the floor with a cold or green glow, and the Inter that takes you down.
static func _stair(w: World, p: Vector3, to: Vector3, label: String, dest: int) -> void:
	var g := Node3D.new()
	g.name = "stair"
	var stone := Props.stone_clean()
	var dark := Mats.mat(Color(0.02, 0.02, 0.025), 1.0)
	Models.P(g, Geo.box(3.4, 0.08, 3.4), dark, Vector3(0, 0.02, 0))
	for i in 5:
		Models.P(g, Geo.box(2.6, 0.12, 0.5), stone, Vector3(0, 0.06 - i * 0.02, -1.2 + i * 0.5))
	for sx in [-1.0, 1.0]:
		Models.P(g, Geo.box(0.35, 0.9, 3.4), stone, Vector3(sx * 1.75, 0.45, 0))
	Models.P(g, Geo.box(3.85, 0.9, 0.35), stone, Vector3(0, 0.45, -1.75))
	var l := OmniLight3D.new()
	l.light_color = LIGHT.get(dest, Color(0.6, 0.7, 1.0))
	l.light_energy = 2.0
	l.omni_range = 5.0
	l.position = Vector3(0, -0.2, 0.3)
	g.add_child(l)
	var it: Inter = w._inter("descend", label, p, 2.0, g, {"to": to, "floor": dest})
	it.set_meta("floor", dest)

static var _ice_sh: Shader

## Meshy's ice comes in flat: lay a cold glassy look over its own colours (a bright rim, a cyan glow in the depth
## of the facets, glossy), one shader for every piece.
static func _ice(m: Node3D) -> void:
	if _ice_sh == null:
		_ice_sh = Shader.new()
		_ice_sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	vec3 base = texture(tex, UV).rgb;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = mix(base * vec3(0.75, 0.88, 1.0), vec3(0.85, 0.95, 1.0), 0.25);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	EMISSION = vec3(0.25, 0.6, 0.95) * (0.18 + fr * 1.1);
}"""
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = _ice_sh
			if src != null and src.albedo_texture != null:
				sm.set_shader_parameter("tex", src.albedo_texture)
			SurfaceMaterials.assign((mi as MeshInstance3D), si, sm)

static var _moss: Array = []

## Floor 3's ground: moss in soft patches and roots creeping through it (albedo with alpha, a faint green emission).
static func _moss_tex() -> Array:
	if not _moss.is_empty():
		return _moss
	var n := 256
	var patch := FastNoiseLite.new()
	patch.frequency = 0.02
	patch.seed = 23
	var roots := FastNoiseLite.new()
	roots.noise_type = FastNoiseLite.TYPE_CELLULAR
	roots.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	roots.frequency = 0.03
	roots.seed = 5
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := (float(x) / n - 0.5) * 2.0
			var v := (float(y) / n - 0.5) * 2.0
			var rr := sqrt(u * u + v * v)
			var m := clampf(patch.get_noise_2d(x, y) * 1.6 + 0.35, 0.0, 1.0) * smoothstep(1.0, 0.55, rr)
			var root := (1.0 - clampf((roots.get_noise_2d(x, y) + 1.0) * 9.0, 0.0, 1.0)) * smoothstep(1.0, 0.3, rr)
			var col := Color(0.16, 0.26, 0.09).lerp(Color(0.24, 0.16, 0.08), root)
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(m * 0.85 + root * 0.9, 0.0, 1.0)))
			var gl := m * 0.06 * (0.5 + 0.5 * sin(float(x) * 0.3) * sin(float(y) * 0.27))
			emi.set_pixel(x, y, Color(gl * 0.4, gl, gl * 0.5))
	alb.generate_mipmaps()
	_moss = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]
	return _moss
