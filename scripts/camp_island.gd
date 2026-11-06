class_name CampIsland
extends Node3D
## The World-Tree Island (jj, 2026-11-04: "blocked it so the town is everything and what you see outside is just
## space", concept 2 of three, "lets use number 2"): Act I's camp adrift in real space. ForestCamp cuts the ground at
## the island's ragged edge (World.island_r, island_edge) and bars the west and north gates; this builds what's round
## it: the island's underside (a Meshy inverted mountain of earth and rock, assets/models/island/underside.glb) under the
## edge, clusters of the World-Tree's roots hanging off it (roots.glb), springs pouring out of the cliff in waterfalls
## that fall away into the void, rocks drifting by the edge, the two places the gates used to lead to hanging far off
## as small islands of their own (the coast with its beach and pier, the moor with its oaks and ruined tower: isle_*.glb,
## dimmed by the distance), asteroids tumbling round it all (Meshy's, and NASA's Bennu) and comets streaking past; and
## the sky (space_sky(): the real sky, ESO's Milky Way panorama, with aurora curtains and Saturn, its real surface and
## rings; assets/textures/space/, sources and licences in CREDITS.md there).
## Zoomed out (the scroll wheel goes further in the camp, Game.zoom_max) you see the island whole.
## Cosmetic and local; no collisions (nothing past the wall can be reached).

const DIR := "res://assets/models/island/"
const TEX := "res://assets/textures/space/"
const UNDER_DEPTH := 0.92      # the underside's height as a fraction of its width
const UNDER_TOP := -0.6        # its grassy top, just under the ground's edge (its middle is cut out: level_top.py)
const ASTEROIDS := 18
const DEBRIS := 14
const COMET_EVERY := Vector2(5.0, 12.0)

var world: World
var rocks: Array = []          # {node, c (orbit centre), r, a, w (angular speed), y, bob, spin: Vector3}
var drifts: Array = []         # {node, base, ph, amp}
var comets: Array = []         # {node, card, from, to, t, dur}
var falls: Array = []          # waterfall materials (their flow is in the shader)
var _comet_t := 2.0

static func glb(n: String) -> Node3D:
	var p := DIR + n + ".glb"
	if not ResourceLoader.exists(p):
		return null
	return (load(p) as PackedScene).instantiate()

static func build(w: World) -> void:
	var ci := CampIsland.new()
	ci.name = "island"
	ci.world = w
	w.add_child(ci)
	ci._build()

func _c3() -> Vector3:
	return Vector3(world.island_c.x, 0, world.island_c.y)

func _build() -> void:
	var c := _c3()
	var R := world.island_r
	# the underside: its grassy top just under the ground's edge, reaching a little past it
	var us := glb("underside")
	if us != null:
		add_child(us)
		var aabb := _aabb(us)
		# (its width counts the roots and grass hanging out over its rim: the top's own rim is 0.49 of the width,
		# measured in Blender; it goes just under the ground's edge)
		var k := (R + 0.6) / (maxf(aabb.size.x, aabb.size.z) * 0.5)
		us.scale = Vector3(k, k * UNDER_DEPTH * maxf(aabb.size.x, aabb.size.z) / maxf(aabb.size.y, 0.01), k)
		# (the grass of its top lies 0.935 of the way up: bushes on its rim stand above it; measured in Blender,
		# tools/blender/island/level_top.py levelled it)
		var top := (aabb.position.y + aabb.size.y) * us.scale.y      # (the grass's level: level_top.py cut what stood above it)
		us.position = c + Vector3(0, UNDER_TOP - top, 0)
		_no_shadow(us)
	else:
		_rock_cone(c, R + 2.5)
	# the World-Tree's roots hanging off the cliff all round
	var rn := 0
	for i in 11:
		var a := TAU * (i + randf_range(-0.3, 0.3)) / 11.0
		var e := world.island_edge(c.x + cos(a), c.z + sin(a)) - 2.0
		var p := c + Vector3(cos(a), 0, sin(a)) * e
		var ro := glb("roots")
		if ro == null:
			break
		add_child(ro)
		var s := randf_range(7.0, 13.0)
		var ab := _aabb(ro)
		ro.scale = Vector3.ONE * s / maxf(ab.size.y, 0.01)
		# its trunk end buried in the rock under the rim, the roots hanging out below
		ro.position = p + Vector3(0, UNDER_TOP - 1.2 - (ab.position.y + ab.size.y) * ro.scale.y, 0)
		ro.rotation.y = randf() * TAU
		_no_shadow(ro)
		rn += 1
	# waterfalls: springs bursting out of the cliff, falling away into the void
	for a in [0.35, 1.25, 2.2, 4.3]:
		var e := world.island_edge(c.x + cos(a), c.z + sin(a))
		_waterfall(c + Vector3(0, UNDER_TOP - 0.6, 0) + Vector3(cos(a), 0, sin(a)) * (e + 1.2), a)
	# the coast and the moor, far off, small and dim: where the gates used to lead
	_isle("isle_coast", c + Vector3(-118, -16, 18), 34.0, 0.4)
	_isle("isle_moor", c + Vector3(14, -8, -128), 40.0, PI)
	# rocks adrift just off the edge, bobbing
	var rock_models := ["asteroid1", "asteroid2", "asteroid3", "bennu"]
	for i in DEBRIS:
		var a := randf() * TAU
		var e := world.island_edge(c.x + cos(a), c.z + sin(a))
		var p := c + Vector3(cos(a), 0, sin(a)) * (e + randf_range(3.0, 16.0)) + Vector3(0, randf_range(-14.0, 3.0), 0)
		var n := _rock(str(rock_models[i % 3]))
		if n == null:
			continue
		add_child(n)
		n.scale = Vector3.ONE * randf_range(0.6, 2.4) / maxf(_aabb(n).size.length(), 0.01) * 1.7
		n.position = p
		n.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_no_shadow(n)
		drifts.append({"node": n, "base": p, "ph": randf() * TAU, "amp": randf_range(0.2, 0.7), "spin": Vector3(randf_range(-0.1, 0.1), randf_range(-0.15, 0.15), 0)})
	# asteroids tumbling round it all, near and far, above and below
	for i in ASTEROIDS:
		var n := _rock(str(rock_models[i % 4]))
		if n == null:
			continue
		add_child(n)
		var size := randf_range(3.0, 14.0) if i % 4 != 0 else randf_range(16.0, 30.0)
		n.scale = Vector3.ONE * size / maxf(_aabb(n).size.length(), 0.01) * 1.7
		_no_shadow(n)
		var r := randf_range(R + 30.0, 190.0)
		rocks.append({"node": n, "r": r, "a": randf() * TAU, "w": randf_range(0.004, 0.02) * (1.0 if randf() < 0.75 else -1.0) * 60.0 / r,
			"y": randf_range(-70.0, 30.0), "bob": randf() * TAU, "spin": Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))})

## One of the rocks (a Meshy asteroid, or NASA's Bennu); asteroid1 if that one isn't there.
func _rock(n: String) -> Node3D:
	if not ResourceLoader.exists(DIR + n + ".glb"):
		return glb("asteroid1")
	var r := glb(n)
	# out in the void there's no air: the camp's mist mustn't pale the rocks the way it does the far islands
	for mi in (r.find_children("*", "MeshInstance3D", true, false) if n != "bennu" else []):
		var g := mi as MeshInstance3D
		for si in g.mesh.get_surface_count():
			var base := g.mesh.surface_get_material(si)
			if base is BaseMaterial3D:
				var m2 := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				m2.disable_fog = true
				SurfaceMaterials.assign(g, si, m2)
	if n == "bennu":
		# NASA's shape model has no texture (a flat pale grey): Bennu is one of the darkest things in the solar
		# system, a rubble pile of black boulders; a dark stone laid over it in world space
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _bennu_mat()
	return r

var _bennu: StandardMaterial3D
func _bennu_mat() -> StandardMaterial3D:
	if _bennu == null:
		var nz := FastNoiseLite.new()
		nz.frequency = 0.09
		nz.fractal_octaves = 5
		var nt := NoiseTexture2D.new()
		nt.noise = nz
		nt.seamless = true
		nt.width = 256
		nt.height = 256
		var nm := NoiseTexture2D.new()
		nm.noise = nz
		nm.seamless = true
		nm.as_normal_map = true
		nm.bump_strength = 6.0
		nm.width = 256
		nm.height = 256
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.28, 0.26)
		m.albedo_texture = nt
		m.normal_enabled = true
		m.normal_texture = nm
		m.roughness = 1.0
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.35
		m.disable_fog = true
		_bennu = m
	return _bennu

func _isle(n: String, at: Vector3, size: float, yaw: float) -> void:
	var m := glb(n)
	if m == null:
		return
	add_child(m)
	var ab := _aabb(m)
	m.scale = Vector3.ONE * size / maxf(maxf(ab.size.x, ab.size.z), 0.01)
	m.position = at
	m.rotation.y = yaw
	_no_shadow(m)
	# far off and in the island's shadow-light: a little darker, cooler
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		for si in g.get_surface_override_material_count():
			var base := g.mesh.surface_get_material(si)
			if base is StandardMaterial3D:
				var sm := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.albedo_color = Color(0.62, 0.66, 0.74)
				SurfaceMaterials.assign(g, si, sm)
	drifts.append({"node": m, "base": at, "ph": randf() * TAU, "amp": 1.2, "spin": Vector3(0, 0.004, 0)})

## A plain rock cone under the edge (no Meshy model).
func _rock_cone(c: Vector3, r: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = 0.8
	cm.height = r * 1.5
	cm.radial_segments = 40
	cm.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = Mats.mat(Color(0.25, 0.2, 0.16), 0.95, 0.0)
	add_child(mi)
	mi.position = c + Vector3(0, -0.6 - cm.height * 0.5, 0)

const FALL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
uniform float speed = 1.6;
uniform vec3 water : source_color = vec3(0.78, 0.88, 0.95);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	// UV.y runs down the fall; streaks racing down, breaking up and thinning to spray and nothing in the void
	vec2 u = vec2(UV.x * 7.0, UV.y * 5.0 - TIME * speed);
	float s = n(u) * 0.6 + n(u * 2.3 + 3.1) * 0.4;
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	float down = 1.0 - smoothstep(0.35, 1.0, UV.y);
	float a = (0.35 + smoothstep(0.3, 0.75, s) * 0.65) * edge * down;
	ALBEDO = mix(water * 0.7, vec3(1.0), smoothstep(0.55, 0.95, s));
	ALPHA = clamp(a * 0.85, 0.0, 1.0);
}
"""

## A spring out of the cliff: a sheet of water arcing out and falling away, spray where it leaves the rock.
func _waterfall(at: Vector3, a: float) -> void:
	var out := Vector3(cos(a), 0, sin(a))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := Vector3(-out.z, 0, out.x)
	var rows := 24
	var length := 70.0
	var wdt := randf_range(3.4, 4.6)
	for j in rows:
		var u0 := float(j) / rows
		var u1 := float(j + 1) / rows
		for uu in [[u0, u1]]:
			var p0 := _fall_pt(at, out, u0 * length)
			var p1 := _fall_pt(at, out, u1 * length)
			var w0 := wdt * (1.0 + u0 * 1.8)
			var w1 := wdt * (1.0 + u1 * 1.8)
			var aa := p0 - side * w0 * 0.5
			var bb := p0 + side * w0 * 0.5
			var cc := p1 - side * w1 * 0.5
			var dd := p1 + side * w1 * 0.5
			for v in [[aa, Vector2(0, u0)], [bb, Vector2(1, u0)], [dd, Vector2(1, u1)], [aa, Vector2(0, u0)], [dd, Vector2(1, u1)], [cc, Vector2(0, u1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = FALL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	falls.append(m)
	# spray where it bursts out
	ElementalFx._dust(self, at + Vector3(0, -1.0, 0), Color(0.85, 0.9, 0.95), 2.2, 0.35, {"amount": 14, "life": 2.4, "one_shot": false,
		"shape": "sphere", "r": 1.2, "dir": out + Vector3(0, -0.6, 0), "spread": 40.0, "vel": [1.0, 2.5], "gravity": -1.2,
		"damping": [0.2, 0.5], "scale": [0.7, 1.3], "grow": [1.0, 3.0]})

func _fall_pt(at: Vector3, out: Vector3, d: float) -> Vector3:
	# out of the rock and down: a short arc, then straight down, drifting a little
	var t := d / 9.0
	return at + out * (1.6 * (1.0 - exp(-t)) * 2.0) + Vector3(0, -0.8 - d, 0)

static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.transform * m.mesh.get_aabb()
		var p := m.get_parent()
		while p != null and p != n:
			if p is Node3D:
				b = (p as Node3D).transform * b
			p = p.get_parent()
		out = b if first else out.merge(b)
		first = false
	return out

static func _no_shadow(n: Node3D) -> void:
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Barred for now: a gate's opening closed with a plug of sharpened logs and two braces (ForestCamp.ISLAND).
static func bar_gate(w: World, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var root := Models.N(null, "gate_bar")
	var wood := Props.wood_dark()
	for i in 9:
		var x := -3.4 + i * 0.85
		var h := randf_range(3.0, 3.6)
		Models.seg(root, Vector3(x, 0, 0), Vector3(x, h, 0), 0.2, 0.17, wood, 7)
		var tip := Models.P(root, Geo.cone(0.18, 0.5, 7), wood, Vector3(x, h + 0.22, 0))
		tip.name = "tip"
	for y in [0.8, 2.3]:
		Models.seg(root, Vector3(-3.8, y, 0.25), Vector3(3.8, y, 0.25), 0.14, 0.14, wood, 6)
	Models.seg(root, Vector3(-3.6, 0.4, 0.4), Vector3(3.6, 2.9, 0.4), 0.13, 0.13, wood, 6)
	Models.seg(root, Vector3(3.6, 0.4, 0.4), Vector3(-3.6, 2.9, 0.4), 0.13, 0.13, wood, 6)
	w._place(root, at)
	root.rotation.y = yaw
	w.add_box(at, Vector2(4.2, 0.7), yaw)

# ------------------------------------------------------------------ moving: asteroids, drifting rocks, comets
func _process(delta: float) -> void:
	var tt := Time.get_ticks_msec() * 0.001
	var c := _c3()
	for r in rocks:
		var n: Node3D = r["node"]
		r["a"] = float(r["a"]) + float(r["w"]) * delta
		var a: float = r["a"]
		n.position = c + Vector3(cos(a) * float(r["r"]), float(r["y"]) + sin(tt * 0.2 + float(r["bob"])) * 2.0, sin(a) * float(r["r"]))
		n.rotation += (r["spin"] as Vector3) * delta
	for d in drifts:
		var n: Node3D = d["node"]
		n.position = (d["base"] as Vector3) + Vector3(0, sin(tt * 0.35 + float(d["ph"])) * float(d["amp"]), 0)
		n.rotation += (d["spin"] as Vector3) * delta
	_comet_t -= delta
	if _comet_t <= 0.0:
		_comet_t = randf_range(COMET_EVERY.x, COMET_EVERY.y)
		_comet()
	var cam := get_viewport().get_camera_3d()
	for cm in comets.duplicate():
		cm["t"] = float(cm["t"]) + delta
		var u: float = float(cm["t"]) / float(cm["dur"])
		if u >= 1.0:
			(cm["node"] as Node3D).queue_free()
			comets.erase(cm)
			continue
		var from: Vector3 = cm["from"]
		var to: Vector3 = cm["to"]
		var p := from.lerp(to, u)
		var nd: Node3D = cm["node"]
		nd.position = p
		var fade := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.85, 1.0, u))
		((cm["card"] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("fade", fade)
		# the tail streams back from the head, its face turned to the camera
		var dir := (to - from).normalized()
		var to_cam := (cam.global_position - p).normalized() if cam != null else Vector3.UP
		var yv := to_cam.cross(dir).normalized()
		var zv := dir.cross(yv).normalized()
		(cm["card"] as Node3D).global_transform = Transform3D(Basis(-dir, yv, zv), p)

const COMET_SHADER := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float fade = 1.0;
void fragment() {
	vec4 c = texture(tex, UV);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	ALBEDO = c.rgb * smoothstep(0.12, 0.6, c.a) * 2.0 * fade * edge;
	ALPHA = 1.0;
}
"""
var _comet_tex: Texture2D

## A comet across the sky: well clear of the island, a long straight run in 6 to 11 seconds.
func _comet() -> void:
	var tex := TEX + "comet.png"
	if _comet_tex == null and ResourceLoader.exists(tex):
		_comet_tex = load(tex)
	if _comet_tex == null:
		return
	var c := _c3()
	var a := randf() * TAU
	var r := randf_range(110.0, 220.0)
	var mid := c + Vector3(cos(a) * r, randf_range(10.0, 70.0), sin(a) * r)
	var d := Vector3(randf_range(-1, 1), randf_range(-0.35, 0.1), randf_range(-1, 1)).normalized()
	var span := randf_range(180.0, 300.0)
	var nd := Node3D.new()
	add_child(nd)
	var card := MeshInstance3D.new()
	var q := QuadMesh.new()
	var L := randf_range(30.0, 60.0)
	q.size = Vector2(L, L * 0.5625)
	q.center_offset = Vector3(L * 0.44, 0, 0)      # the head (the bright end, the image's left) at the node
	card.mesh = q
	var sh := Shader.new()
	sh.code = COMET_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", _comet_tex)
	card.material_override = m
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.top_level = true
	nd.add_child(card)
	comets.append({"node": nd, "card": card, "from": mid - d * span * 0.5, "to": mid + d * span * 0.5, "t": 0.0, "dur": randf_range(6.0, 11.0)})

# ------------------------------------------------------------------ the sky
const SKY_SHADER := """
shader_type sky;
uniform sampler2D sky_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D planet_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ring_tex : source_color, filter_linear, repeat_disable;
uniform vec3 band_n = vec3(0.15, 0.8, -0.58);    // the galaxy's pole: its band runs across the void the game camera looks into
uniform vec3 core_dir = vec3(-0.2, -0.55, -0.8); // and its bright core there, below the island's north edge
uniform vec3 planet_dir = vec3(0.62, -0.32, -0.72);
uniform float planet_r = 0.11;
uniform vec3 ring_n = vec3(0.3, 0.92, 0.25);
uniform vec3 star_light = vec3(-0.7, 0.35, 0.6);
uniform float brightness = 1.0;

float hash3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1, 0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0, 1), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1, 1), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); }

vec3 stars(vec3 d, float scale, float dens) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	vec3 col = vec3(0.0);
	float h = hash3(cell);
	if (h > 1.0 - dens) {
		vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5) * 0.7;
		float dist = length(p - c);
		float b = smoothstep(0.42, 0.0, dist) * (0.4 + 0.6 * hash3(cell + 7.7));
		float t = hash3(cell + 9.1);
		col = mix(vec3(1.0, 0.82, 0.62), vec3(0.7, 0.82, 1.0), t) * b * b * 2.2;
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.004, 0.005, 0.011);
	// the real sky: ESO's panorama of the Milky Way, laid round the sky in galactic coordinates (band_n the pole)
	vec3 bn = normalize(band_n);
	vec3 cd = normalize(core_dir);
	vec3 e1 = normalize(cd - bn * dot(cd, bn));
	vec3 e2 = cross(bn, e1);
	float lat = asin(clamp(dot(d, bn), -1.0, 1.0));
	float lon = fract(atan(dot(d, e2), dot(d, e1)) / 6.2831853 + 0.5);
	col += texture(sky_tex, vec2(lon, 0.5 - lat / 3.1415927)).rgb * 0.9;
	col += stars(d, 160.0, 0.02) * 0.6;          // (a few crisp bright points over the photograph)
	// aurora curtains low on one side of the sky: green fading to pink at their tops
	float ay = d.y;
	float az = atan(d.x, d.z);
	float curtain = vnoise(vec2(az * 9.0, 0.5)) * 0.7 + vnoise(vec2(az * 23.0, 2.0)) * 0.3;
	float rays = pow(vnoise(vec2(az * 60.0, ay * 1.5)), 2.0);
	float band = smoothstep(-0.02, 0.14, ay) * smoothstep(0.42, 0.12, ay) * smoothstep(0.35, 0.85, curtain);
	float side = smoothstep(-0.2, 0.6, dot(normalize(vec2(d.x, d.z) + 1e-4), normalize(vec2(-0.8, -0.6))));
	vec3 aur = mix(vec3(0.15, 0.9, 0.5), vec3(0.9, 0.3, 0.7), smoothstep(0.1, 0.45, ay));
	col += aur * band * (0.25 + rays * 0.6) * side * 0.22;
	// the ringed giant: a lit sphere and its ring, far off
	vec3 pd = normalize(planet_dir);
	vec3 rn = normalize(ring_n);
	float R = tan(planet_r);
	float cosang = dot(d, pd);
	vec3 pu = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
	vec3 pv = cross(pu, pd);
	vec2 q = vec2(dot(d, pu), dot(d, pv)) / sin(planet_r);
	bool hit = cosang > cos(planet_r) && dot(q, q) < 1.0;
	// the ring: where the ray meets the ring's plane through the planet's centre
	float dn = dot(d, rn);
	vec4 ringc = vec4(0.0);
	float ring_far = 0.0;
	if (abs(dn) > 1e-4) {
		float t = dot(pd, rn) / dn;
		if (t > 0.0) {
			vec3 P = d * t;
			float rr = length(P - pd) / R;
			if (rr > 1.28 && rr < 2.41) {
				vec4 rt = texture(ring_tex, vec2((rr - 1.28) / 1.13, 0.5));      // (Saturn's: 1.28 to 2.41 of its radius)
				float lit = 0.35 + 0.65 * clamp(dot(rn, normalize(star_light)) * 0.5 + 0.6, 0.0, 1.0);
				ringc = vec4(rt.rgb * rt.rgb * lit * 0.8, rt.a * 0.9);
				ring_far = t > 1.0 ? 1.0 : 0.0;
			}
		}
	}
	if (ringc.a > 0.0 && (!hit || ring_far < 0.5))
		col = mix(col, ringc.rgb, ringc.a * (hit ? 0.0 : 1.0));
	if (hit) {
		vec3 n = normalize(q.x * pu + q.y * pv - sqrt(1.0 - dot(q, q)) * pd);
		float plat = asin(clamp(dot(n, rn), -1.0, 1.0)) / 3.1415927 + 0.5;
		vec3 t1 = normalize(cross(rn, vec3(0.0, 0.0, 1.0)));
		vec3 t2 = cross(rn, t1);
		float plon = atan(dot(n, t2), dot(n, t1)) / 6.2831853 + 0.5;
		vec3 surf = texture(planet_tex, vec2(plon, plat)).rgb;
		float lam = clamp(dot(n, normalize(star_light)), 0.0, 1.0);
		float rim = pow(1.0 - clamp(-dot(n, d), 0.0, 1.0), 3.0);
		vec3 pc = surf * surf * (0.03 + lam * 0.95) + vec3(0.9, 0.75, 0.55) * rim * lam * 0.25;
		// the ring's shadow band across the planet
		col = pc;
		if (ringc.a > 0.0 && ring_far < 0.5)
			col = mix(col, ringc.rgb, ringc.a);
	}
	COLOR = col * brightness;
}
"""

static func space_sky() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in [["sky_tex", "milkyway_eso.jpg"], ["planet_tex", "saturn.jpg"], ["ring_tex", "saturn_rings.png"]]:
		var p: String = TEX + str(k[1])
		if ResourceLoader.exists(p):
			m.set_shader_parameter(str(k[0]), load(p))
	return m
