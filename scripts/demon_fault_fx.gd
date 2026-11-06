class_name DemonFaultFx
extends RefCounted
## Fault of the Pit's look (the Demon's R; the gameplay is DemonSkills). Tectonic: rock, lava and steam, not
## hellfire: nothing here is Molten Fists'.
##
##  The slam ("impact" {p: the blow, q: the fault's middle, ps: [a, b] its ends, x: the warning, r: how long it
##  stays molten}): the ground under his fists is crushed in (a Meshy-painted mark), clods and dust (simulated ash)
##  burst up, a shock runs through the earth; the ground splits along the line from the middle to both ends (a
##  Meshy-painted fault line, a lava seam in broken earth), its seam pulsing hotter through the warning so everyone
##  sees exactly where it will go.
##  The eruption ("erupt" {ps, t, x}): the fault heaves up out of the ground: the Meshy lava fissure (black basalt,
##  a crack of flowing lava) rises along the line, obsidian slabs (the Meshy plates) tilt up apart on both sides,
##  chunks of rock are flung up, a wall of simulated steam and gas boils off the lava, dust billows along it (the
##  impact sim), a lava light runs its length. Anyone on it is thrown up in a spray of sparks and dust.
##  Molten (r s): steam keeps rising, the lava breathes; at the end the steam thins, the lava dulls, and the fissure
##  and slabs sink back into the ground in a last puff of dust.
## State: h.fxs["fault"], kept by `update` (a partner's copy times itself out from r).

const PLATES := [4, 6, 8, 10]
const STEAM := [2, 3, 4, 5]

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"impact":
			_slam(h, ev)
		"erupt":
			_erupt(h, ev)
		"cast":
			pass
		_:
			return false
	return true

static func _slam(h: Hero, ev: Dictionary) -> void:
	_end(h)
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev["p"]
	p.y = world.height_at(p.x, p.z)
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	if ps.size() < 2:
		return
	var a: Vector3 = ps[0]
	var b: Vector3 = ps[1]
	var mid := (a + b) * 0.5
	mid.y = world.height_at(mid.x, mid.z)
	var warn: float = float(ev.get("x", DemonSkills.FAULT_WARN))
	var life: float = float(ev.get("r", DemonSkills.FAULT_LIFE))
	# the blow
	DemonKitFx.decal(root, p, "crush", Vector2(2.2, 2.2), randf() * TAU, 3.0, 0.3)
	DemonKitFx.smoke(root, p, "ash", 2.0, 1.1)
	DemonKitFx.clods(root, p + Vector3(0, 0.2, 0), [10, 14, 20, 24][tr], 3.6)
	DemonKitFx.pieces(root, world, p + Vector3(0, 0.15, 0), DemonKitFx.BOULDER_PIECES, 0.2, 3.0, 0.0, 1.4, 1.2)
	DemonKitFx.shock_ring(root, h.game, p, 2.2, 0.3)
	DemonKitFx.flash_light(root, p + Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.25), 2.5, 5.0, 0.3)
	# the line splitting open: a scorched gouge torn from the middle out to both ends
	var d := (b - a) * Vector3(1, 0, 1)
	var yaw := atan2(-d.z, d.x)
	var gouge := DemonKitFx.decal(root, mid, "faultline", Vector2(d.length() + 0.6, DemonSkills.FAULT_W * 1.3), yaw, warn + life + 1.0, 0.4)
	gouge.scale = Vector3(0.05, 1, 1)
	gouge.create_tween().tween_property(gouge, "scale", Vector3.ONE, warn * 0.6).set_ease(Tween.EASE_OUT)
	h.fxs["fault"] = {"a": a, "b": b, "gouge": gouge, "t": 0.0, "warn": warn, "life": life, "until": warn + life + 2.5,
		"stage": "warn", "plates": [], "steam": []}
	SkillFx.snd(h, "slam", 0.0, 0.76)
	SkillFx.snd(h, "boom", -9.0, 0.65)
	SkillFx.duck(h, -3.0, 0.5)
	SkillFx.shake(h, 0.35)

static func _erupt(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("fault", {})
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	if st.is_empty():
		if ps.size() < 2:
			return
		st = {"a": ps[0], "b": ps[1], "t": 0.0, "warn": 0.0, "life": DemonSkills.FAULT_LIFE, "until": DemonSkills.FAULT_LIFE + 2.5,
			"plates": [], "steam": []}
		h.fxs["fault"] = st
	st["stage"] = "molten"
	st["t"] = 0.0
	var a: Vector3 = st["a"]
	var b: Vector3 = st["b"]
	var d := (b - a) * Vector3(1, 0, 1)
	var len := d.length()
	var dir := d.normalized()
	var side := dir.cross(Vector3.UP)
	var yaw := atan2(-d.z, d.x)
	var plates: Array = []
	# the fissure heaving up along the line: two Meshy sections end to end (or stand-in slabs)
	var segs := 2
	for i in segs:
		var c := a + d * ((float(i) + 0.5) / segs)
		c.y = world.height_at(c.x, c.z)
		var node := DemonKitFx.model(DemonKitFx.FISSURE)
		if node == null:
			continue
		_crack_only(node, float(i) * 7.3 + a.x)
		root.add_child(node)
		# the tile's crack runs along its z: laid along the fault, only its top at the ground's level
		var along := (len / segs) / 3.2 * 1.12
		var across := DemonSkills.FAULT_W * 1.15 / 1.5
		node.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(across, 0.85, along))
		var rest := c - Vector3(0, 0.8, 0)
		node.global_position = c - Vector3(0, 1.5, 0)
		var tw := node.create_tween()
		tw.tween_interval(0.02 * i)
		tw.tween_property(node, "global_position", c - Vector3(0, 0.55, 0), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(node, "global_position", rest, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		plates.append({"node": node, "rest": rest, "h": 1.4, "heat": 3.0})
	# obsidian slabs tilting up apart along both sides
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(a.x * 10.0), int(b.z * 10.0)))
	var n: int = PLATES[tr]
	for i in n:
		var u := (float(i) + rng.randf_range(0.2, 0.8)) / float(n)
		var lane := (1.0 if i % 2 == 0 else -1.0)
		var pp := a + d * u + side * lane * DemonSkills.FAULT_W * rng.randf_range(0.55, 0.8)
		pp.y = world.height_at(pp.x, pp.z)
		var hgt := rng.randf_range(0.7, 1.2)
		var node2 := DemonKitFx.model(DemonKitFx.PLATE)
		if node2 == null:
			continue
		DemonKitFx.heat_model(node2, 1.6)
		root.add_child(node2)
		var tilt := Basis(dir, -lane * rng.randf_range(0.45, 0.8)) * Basis(Vector3.UP, yaw + rng.randf_range(-0.35, 0.35))
		node2.basis = tilt * Basis.from_scale(Vector3(rng.randf_range(0.6, 0.9), hgt, rng.randf_range(0.7, 1.0)))
		var rest2 := pp - Vector3(0, hgt * 0.15, 0)
		node2.global_position = pp - Vector3(0, hgt * 1.1, 0)
		var tw2 := node2.create_tween()
		tw2.tween_interval(absf(u - 0.5) * 0.12 + rng.randf_range(0.0, 0.05))
		tw2.tween_property(node2, "global_position", rest2, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		plates.append({"node": node2, "rest": rest2, "h": hgt, "heat": 1.6})
	st["plates"] = plates
	# rock flung up, dust billowing along it (the impact sim, small), and the steam boiling off the lava
	for k in 3:
		var c2 := a + d * (0.2 + 0.3 * k)
		c2.y = world.height_at(c2.x, c2.z)
		DemonKitFx.smoke(root, c2, "impact", 2.6, 1.4)
		DemonKitFx.pieces(root, world, c2 + Vector3(0, 0.3, 0), DemonKitFx.BOULDER_PIECES, 0.26, 5.0, 2.0, 2.0, 1.2)
	var steam: Array = []
	for k in STEAM[tr]:
		var c3: Vector3 = a + d * ((float(k) + 0.5) / float(STEAM[tr]))
		c3 += side * randf_range(-0.25, 0.25)
		c3.y = world.height_at(c3.x, c3.z) - 0.3      # (the sim's source line sits in the crack, out of sight)
		steam.append(DemonKitFx.smoke(root, c3, "steam", randf_range(1.3, 1.7), randf_range(2.2, 2.8), true, Color(1.0, 0.94, 0.88, 0.6)))
	st["steam"] = steam
	DemonKitFx.clods(root, (a + b) * 0.5 + Vector3(0, 0.3, 0), [16, 24, 32, 40][tr], 5.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.1)
	l.light_energy = 4.5
	l.omni_range = len * 0.8
	l.shadow_enabled = tr >= 3
	root.add_child(l)
	l.global_position = (a + b) * 0.5 + Vector3(0, 1.0, 0)
	st["light"] = l
	for e in DemonKitFx.targets(h, ev):
		_thrown(root, e, tr)
	var midp := (a + b) * 0.5
	Sfx.play_at("boom", midp, -1.0, 0.8)
	Sfx.play_at("impact_bone", midp, -5.0, 0.45)
	Sfx.play_at("fire_erupt", midp, -9.0, 0.6)
	SkillFx.shake(h, 0.42)
	if bool(ev.get("x", false)):
		SkillFx.hitstop(h, 0.04)

## Someone on the fault: thrown up off their feet in a spray of sparks and dust (a monster's body lifts and drops;
## a player's own game lifts him itself, PvpStatus).
static func _thrown(root: Node3D, e: Node3D, tr: int) -> void:
	var c := DemonKitFx.chest(e, 0.3)
	DemonKitFx.sparks(root, c, Vector3.UP, [8, 12, 16, 20][tr], 35.0, Vector2(3.0, 8.0))
	DemonKitFx.smoke(root, e.global_position, "ash", 1.6, 0.9)
	if e is Hero:
		return
	var rig = e.get("rig")
	if rig != null and is_instance_valid(rig):
		var y0: float = (rig as Node3D).position.y
		var tw := (rig as Node3D).create_tween()
		tw.tween_property(rig, "position:y", y0 + 0.9, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(rig, "position:y", y0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

## The Meshy fissure is a square tile of broken ground with a lava crack down its middle; only the crack is wanted.
## Its materials become CRACK_SHADER: the tile's own texture and lava glow, cut away outside a jagged band round the
## crack that narrows to nothing at both ends (per pixel, so no straight edge and none of the tile's sides show).
static func _crack_only(n: Node3D, seed: float) -> void:
	if _crack_shader == null:
		_crack_shader = Shader.new()
		_crack_shader.code = CRACK_SHADER
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var base = m.get_active_material(i)
			var sm := ShaderMaterial.new()
			sm.shader = _crack_shader
			if base is BaseMaterial3D and (base as BaseMaterial3D).albedo_texture != null:
				sm.set_shader_parameter("albedo_tex", (base as BaseMaterial3D).albedo_texture)
			sm.set_shader_parameter("seed", seed)
			sm.set_shader_parameter("heat", 3.0)
			SurfaceMaterials.assign(m, i, sm)

static var _crack_shader: Shader
const CRACK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 heat_col : source_color = vec4(1.0, 0.42, 0.07, 1.0);
uniform float heat = 3.0;
uniform float half_w = 0.75;
uniform float half_l = 1.58;
uniform float seed = 0.0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// a band round the crack (the tile's z), wandering in width, jagged, closing at both ends
	float end = half_l - abs(lp.z);
	float taper = clamp(end / 0.7, 0.0, 1.0);
	float w = half_w * (0.7 + 0.6 * vnoise(vec2(lp.z * 1.3 + seed, seed))) * (0.12 + 0.88 * taper);
	float jag = 0.22 * (vnoise(vec2(lp.x * 4.0 + seed, lp.z * 4.0)) - 0.5) + 0.08 * (vnoise(vec2(lp.x * 13.0, lp.z * 13.0 + seed)) - 0.5);
	float edge = w + jag - abs(lp.x);
	if (edge < 0.0) {
		discard;
	}
	vec4 t = texture(albedo_tex, UV);
	// scorched dark toward the torn edge, where it meets the ground
	float rim = smoothstep(0.0, 0.3, edge);
	ALBEDO = t.rgb * mix(0.35, 1.0, rim);
	ROUGHNESS = 0.88;
	EMISSION = t.rgb * heat_col.rgb * heat * mix(0.25, 1.0, rim);
}
"""

## Every frame: the warning's embers pulse, the lava breathes, and at the end it all sinks.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("fault"):
		return
	var st: Dictionary = h.fxs["fault"]
	st["t"] = float(st["t"]) + delta
	st["until"] = float(st["until"]) - delta
	if float(st["until"]) <= 0.0:
		_end(h)
		return
	var t: float = float(st["t"])
	match str(st["stage"]):
		"warn":
			var k := clampf(t / maxf(float(st["warn"]), 0.05), 0.0, 1.0)
			var g = st.get("gouge")
			if g != null and is_instance_valid(g):
				DemonKitFx.set_mark_glow(g, 0.5 + 3.2 * k + 0.9 * sin(t * (18.0 + 30.0 * k)))
			if t > float(st["warn"]) + 0.6:
				st["stage"] = "molten"     # a partner who never got the eruption
				st["t"] = 0.0
		"molten":
			var life: float = float(st["life"])
			var cool := smoothstep(life - 0.9, life, t)
			var l = st.get("light")
			if l != null and is_instance_valid(l):
				var fl := 0.85 + 0.15 * sin(h.anim_time * 11.0) * sin(h.anim_time * 4.3)
				(l as OmniLight3D).light_energy = lerpf(4.5, 1.8, smoothstep(0.0, 0.6, t)) * fl * (1.0 - cool)
			for pl in st["plates"]:
				var breathe := 0.82 + 0.18 * sin(h.anim_time * 2.4 + float(pl["h"]) * 5.0)
				DemonKitFx.set_heat(pl["node"], float(pl["heat"]) * breathe * (1.0 - cool * 0.85))
			if t >= life and not st.has("sinking"):
				st["sinking"] = true
				_sink(h, st)

## The end: the steam thins, the fissure and slabs sink back into the ground in a last puff of dust.
static func _sink(h: Hero, st: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	for s in st.get("steam", []):
		DemonKitFx.smoke_out(s, 1.2)
	st["steam"] = []
	for pl in st.get("plates", []):
		var n = pl["node"]
		if n == null or not is_instance_valid(n):
			continue
		var rest: Vector3 = pl["rest"]
		var tw := (n as Node3D).create_tween()
		tw.tween_interval(randf_range(0.0, 0.25))
		tw.tween_property(n, "global_position", rest - Vector3(0, float(pl["h"]) * 1.3, 0), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback((n as Node).queue_free)
	st["plates"] = []
	var mid := ((st["a"] as Vector3) + (st["b"] as Vector3)) * 0.5
	DemonKitFx.smoke(root, mid, "ash", 2.4, 1.2)
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		(l as Node).queue_free()
	st.erase("light")
	Sfx.play_at("impact_bone", mid, -14.0, 0.45)
	st["until"] = 1.2

static func _end(h: Hero) -> void:
	if not h.fxs.has("fault"):
		return
	var st: Dictionary = h.fxs["fault"]
	h.fxs.erase("fault")
	for pl in st.get("plates", []):
		var n = pl["node"]
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	for s in st.get("steam", []):
		if s != null and is_instance_valid(s):
			(s as Node).queue_free()
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		(l as Node).queue_free()

static func clear(h: Hero) -> void:
	_end(h)
