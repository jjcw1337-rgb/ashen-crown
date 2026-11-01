class_name DemonFx
extends RefCounted
## Visual effects for the Demon's skills (DemonSkills). Each skill has its own look in its own script, all built
## from InfernalFx (his visual language) and DemonKitFx (the pieces they share); this one routes the events and keeps
## what two skills share: the foe held up by Hellgrip, the white heat and meteors of Wrath of the Pit, the Brand.
## Everything one-shot is parented to the zone's FX node; what lingers is state in h.fxs that the `update`s move every
## frame, on his own game and on his puppet on every partner's.
##
## `play` is the skills' fx events (SkillFx: the same on the caster and on his puppet):
##  Molten Fists: "cast", "impact" (DemonFistsFx, "Hellbrand"); "brand" {t | pid, x} (BrandFx on whoever his skills
##    marked), "consume" {t | pid} (the Fists used a Brand up)
##  Infernal Charge: "wind", "run", "hit", "skid", "end" (DemonChargeFx, "Hellrunner")
##  Fault of the Pit: "impact", "erupt" (DemonFaultFx)
##  Brimstone Hurl: "cast", "throw", "splash" (DemonHurlFx, "Shatterstone")
##  Hellgrip: "cast", "fling", "hook", "miss", "smash", "end" (DemonChainFx, "Chain of the Pit"); "grab" {t | pid, x}
##    (the victim hoisted over his head, h.fxs["grip"], here)
##  Wrath of the Pit: "crucible", "heat", "erupt" (DemonCrucibleFx); the white heat after the eruption (h.fxs["wrath"]),
##    "meteor" {p, n, x} (h.fxs["meteors"]; one falling at a player, x >= WRATH_FALL_PVP, gets a glowing circle),
##    "end" {x} (here)

const EMBER := Color(1.0, 0.42, 0.06)
const HOT := Color(1.0, 0.75, 0.3)
const CRUST := Color(0.06, 0.04, 0.035)
const BLOOD := Color(0.85, 0.04, 0.08)
const SOUL := Color(0.62, 0.42, 1.0)
const GRIP_SLACK := 1.5          # a partner's held foe is let go this long after the hold if the smash is lost
const WRATH_SLACK := 1.5

static var _lava_shader: Shader
static var _disc: ArrayMesh
static var _strip: ArrayMesh
static var _rock: Mesh

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var s := str(ev["s"])
	var e := str(ev["e"])
	match s:
		"fists":
			match e:
				"brand":
					for t in DemonKitFx.targets(h, ev):
						BrandFx.mark(t, float(ev.get("x", DemonSkills.BRAND_DUR)))
					return true
				"consume":
					for t in DemonKitFx.targets(h, ev):
						BrandFx.consume(t)
					return true
			return DemonFistsFx.play(h, ev)
		"icharge":
			return DemonChargeFx.play(h, ev)
		"cslam":
			return DemonFaultFx.play(h, ev)
		"hurl":
			return DemonHurlFx.play(h, ev)
		"grip":
			if e == "grab":
				_grab(h, ev)
				return true
			if e == "smash":
				_end_grip(h, true)
			return DemonChainFx.play(h, ev)
		"wrath":
			match e:
				"crucible", "heat":
					return DemonCrucibleFx.play(h, ev)
				"erupt":
					DemonCrucibleFx.play(h, ev)
					_wrath_on(h, float(ev.get("x", DemonSkills.PIT_DUR)))
					return true
				"meteor":
					_meteor(h, root, ev)
					return true
				"end":
					_end_wrath(h, bool(ev.get("x", false)))
					return true
				"cast":
					return true
	return false

## Hellgrip's hold: the victim hauled up over his head, squirming (a monster's rig, or a player's body).
static func _grab(h: Hero, ev: Dictionary) -> void:
	_end_grip(h, false)
	var vs := DemonKitFx.targets(h, ev)
	if vs.is_empty():
		return
	var v: Node3D = vs[0]
	h.fxs["grip"] = {"victim": v, "lift": 0.0, "until": float(ev.get("x", 0.8)) + GRIP_SLACK, "t": 0.0}
	Fx.sparks(h.game.world.fx_root, DemonKitFx.chest(v), EMBER)
	SkillFx.snd(h, "growl", -4.0, 0.75)

## Pit-born: the white heat in his cracks and the light for the rain's length.
static func _wrath_on(h: Hero, rain: float) -> void:
	_end_wrath(h, false)
	h.fxs["wrath"] = {"k": 0.6, "want": 1.0, "until": rain + WRATH_SLACK, "rain": rain}
	var l := OmniLight3D.new()
	l.light_color = HOT
	l.light_energy = 0.0
	l.omni_range = 7.0
	l.shadow_enabled = false
	l.position = Vector3(0, 1.6, 0)
	h.rig.add_child(l)
	h.fxs["wrath"]["light"] = l

## A meteor: the Meshy meteorite (pitted iron and basalt, molten cracks, a white-hot melted face) plunging from the
## sky, its seams blazing, trailing simulated fire and smoke (the comet sim, puff by puff); a mark closes in under
## one falling at a player. It lands with DemonHurlFx.impact: its real pieces, the simulated impact cloud, a crater.
static func _meteor(h: Hero, root: Node3D, ev: Dictionary) -> void:
	var at: Vector3 = ev["p"]
	var fall: float = float(ev.get("x", DemonSkills.WRATH_FALL))
	var k: int = int(ev.get("n", 0))
	var n := DemonHurlFx.rock(root, DemonKitFx.METEOR, 0.95, 2.6)
	var from := at + Vector3(cos(k * 2.4) * 3.0, 15.0, sin(k * 2.4) * 3.0 + 2.0)
	n.global_position = from
	var mark = null
	if fall >= DemonSkills.WRATH_FALL_PVP - 0.01:
		mark = DemonKitFx.target_mark(root, h.game.world, at, DemonSkills.METEOR_R, Color(0.6, 0.18, 0.06))
	var ms: Array = h.fxs.get("meteors", [])
	ms.append({"node": n, "from": from, "to": at, "t": 0.0, "dur": fall, "mark": mark, "trail": 0.0, "last": from})
	h.fxs["meteors"] = ms
	if h.fxs.has("wrath"):
		h.fxs["wrath"]["until"] = maxf(float(h.fxs["wrath"]["until"]), fall + WRATH_SLACK)
	if h.puppet:
		Sfx.play_at("fireball", at, -10.0, 0.6)
	else:
		Sfx.play("fireball", -9.0, 0.6)

## The grip lets go: the victim is back on the ground (dropped, or smashed into it).
static func _end_grip(h: Hero, smashed: bool) -> void:
	if not h.fxs.has("grip"):
		return
	var g: Dictionary = h.fxs["grip"]
	h.fxs.erase("grip")
	var v = g["victim"]
	if v != null and is_instance_valid(v):
		var rig = v.get("rig")
		if rig != null and is_instance_valid(rig):
			rig.position.y = 0.0
			rig.rotation.z = 0.0
		if not smashed:
			v.set_meta("gripped", false)

## The wrath ends: the white heat fades, the light with it.
static func _end_wrath(h: Hero, _finished: bool) -> void:
	if not h.fxs.has("wrath"):
		return
	var n: Dictionary = h.fxs["wrath"]
	h.fxs.erase("wrath")
	_set_heat(h, 0.0)
	var l = n.get("light")
	if l != null and is_instance_valid(l):
		var tw: Tween = (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.6)
		tw.tween_callback((l as Node).queue_free)

## The white heat in his cracks (the body shader's "wrath", Demon.animate keeps "glow" on top of it).
static func _set_heat(h: Hero, k: float) -> void:
	if h.rig == null or not h.rig.has_meta("demon_mats"):
		return
	for m in h.rig.get_meta("demon_mats"):
		(m as ShaderMaterial).set_shader_parameter("wrath", k)

## Every frame after the pose (the caster's and the puppet's).
static func update(h: Hero, delta: float) -> void:
	if not h.is_demon():
		return
	DemonFistsFx.update(h, delta)
	DemonChargeFx.update(h, delta)
	DemonFaultFx.update(h, delta)
	DemonHurlFx.update(h, delta)
	DemonChainFx.update(h, delta)
	DemonCrucibleFx.update(h, delta)
	var world = h.game.world
	var root: Node3D = world.fx_root
	if h.fxs.has("meteors"):
		var bs: Array = h.fxs["meteors"]
		for b in bs.duplicate():
			var n = b["node"]
			if n == null or not is_instance_valid(n):
				bs.erase(b)
				continue
			b["t"] = float(b["t"]) + delta
			var u := clampf(float(b["t"]) / maxf(float(b["dur"]), 0.01), 0.0, 1.0)
			var from: Vector3 = b["from"]
			var to: Vector3 = b["to"]
			var p := from.lerp(to, u)
			var vel: Vector3 = (p - (b["last"] as Vector3)) / maxf(delta, 0.001)
			b["last"] = p
			(n as Node3D).global_position = p
			var sp = (n as Node).get_meta("spin") if (n as Node).has_meta("spin") else null
			if sp != null and is_instance_valid(sp):
				(sp as Node3D).rotation += Vector3(delta * 5.0, delta * 1.5, 0.0)
			b["trail"] = float(b["trail"]) - delta
			if float(b["trail"]) <= 0.0 and u < 0.97:
				b["trail"] = DemonHurlFx.TRAIL_EVERY
				DemonHurlFx.trail(h, root, p, vel, 1.8)
			var mk = b.get("mark")
			if mk != null and is_instance_valid(mk[0]):
				(mk[1] as ShaderMaterial).set_shader_parameter("k", u)
			if u >= 1.0:
				bs.erase(b)
				(n as Node).queue_free()
				if mk != null and is_instance_valid(mk[0]):
					(mk[0] as Node).queue_free()
				DemonHurlFx.impact(h, to, DemonKitFx.METEOR_PIECES, 0.95, DemonSkills.METEOR_R, 1.15)
				Sfx.play_at("boom", to, -3.0, 0.95)
				Sfx.play_at("impact_bone", to, -8.0, 0.5)
		if bs.is_empty():
			h.fxs.erase("meteors")
	if h.fxs.has("grip"):
		var g: Dictionary = h.fxs["grip"]
		var v = g["victim"]
		g["until"] = float(g["until"]) - delta
		g["t"] = float(g["t"]) + delta
		if v == null or not is_instance_valid(v) or bool(v.get("dead")) or float(g["until"]) <= 0.0:
			_end_grip(h, false)
		else:
			# hauled up into the air over his head, squirming
			g["lift"] = lerpf(float(g["lift"]), DemonSkills.GRIP_LIFT, clampf(delta * 7.0, 0.0, 1.0))
			var rig = v.get("rig")
			if rig != null and is_instance_valid(rig):
				rig.position.y = float(g["lift"]) + sin(float(g["t"]) * 14.0) * 0.06
				rig.rotation.z = sin(float(g["t"]) * 9.0) * 0.25 * clampf(float(g["lift"]) / DemonSkills.GRIP_LIFT, 0.0, 1.0)
	if h.fxs.has("wrath"):
		var n: Dictionary = h.fxs["wrath"]
		n["until"] = float(n["until"]) - delta
		if float(n["until"]) <= 0.0 or (not h.puppet and not h.dm.has("wrath")):
			_end_wrath(h, false)
		else:
			var want: float = float(n["want"])
			var k: float = float(n["k"])
			k = lerpf(k, want, clampf(delta * (3.0 if want > k else 1.5), 0.0, 1.0))
			n["k"] = k
			_set_heat(h, k)
			var l = n.get("light")
			if l != null and is_instance_valid(l):
				(l as OmniLight3D).light_energy = 2.2 * k * (0.85 + 0.15 * sin(h.anim_time * 9.0))
			if k > 0.3 and randf() < delta * 10.0 * k:
				Fx.burst(root, h.global_position + Vector3(randf_range(-0.5, 0.5), randf_range(0.6, 2.0), randf_range(-0.4, 0.4)), HOT, 2, 1.5, 0.06, 0.6, true, 0.6, 40.0)

## Everything of his that lingers is gone (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	DemonFistsFx.clear(h)
	DemonChargeFx._end(h)
	DemonFaultFx.clear(h)
	DemonHurlFx.clear(h)
	DemonChainFx.clear(h)
	DemonCrucibleFx.clear(h)
	_end_grip(h, false)
	_end_wrath(h, false)
	if h.fxs.has("meteors"):
		for b in h.fxs["meteors"]:
			if is_instance_valid(b["node"]):
				(b["node"] as Node).queue_free()
			var mk = b.get("mark")
			if mk != null and is_instance_valid(mk[0]):
				(mk[0] as Node).queue_free()
		h.fxs.erase("meteors")

# ---------------------------------------------------------------- the pieces
## Cracked rock with magma glowing through it, flat on the ground (a disc, or a wedge of one opening toward -z),
## breathing, cooling to black over its life. melt 0..1: how molten (a pool) rather than cracked (a slam's floor).
static func lava_decal(root: Node3D, at: Vector3, radius: float, life: float, melt: float, yaw := 0.0, wedge := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh()
	var m := _lava_mat(melt, wedge)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.05, 0)
	mi.rotation.y = yaw
	mi.scale = Vector3(radius, 1.0, radius)
	var l := OmniLight3D.new()
	l.light_color = EMBER
	l.light_energy = 0.8 + melt * 1.2
	l.omni_range = radius * 2.2
	l.shadow_enabled = false
	l.position = Vector3(0, 0.6, 0)
	mi.add_child(l)
	l.scale = Vector3.ONE / maxf(radius, 0.01)
	var em := Fx.aura(mi, EMBER, int(6 + radius * 6 * (0.5 + melt)), 0.9, 0.07, 1.0, 0.8, 0.8, 30.0, Vector3.ZERO)
	em.scale = Vector3.ONE / maxf(radius, 0.01)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("life", v), 1.0, 0.0, life)
	tw.tween_callback(mi.queue_free)
	var tw2 := l.create_tween()
	tw2.tween_property(l, "light_energy", 0.0, life)
	return mi

## A strip of the same cracked, glowing rock from a to b (the fissures).
static func lava_strip(root: Node3D, a: Vector3, b: Vector3, width: float, life: float, melt: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _strip_mesh()
	var m := _lava_mat(melt, 0.0, true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	mi.global_position = a + Vector3(0, 0.06, 0)
	mi.rotation.y = atan2(-d.x, -d.z)
	mi.scale = Vector3(width, 1.0, maxf(len, 0.05))
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("life", v), 1.0, 0.0, life)
	tw.tween_callback(mi.queue_free)
	return mi

## A burst of lava out of a fissure: a pillar of fire, a flash, embers and a short-lived glow on the ground.
static func eruption(root: Node3D, at: Vector3, r: float) -> void:
	Fx.burst(root, at + Vector3(0, 0.2, 0), EMBER, 26, 6.5, 0.09, 0.6, true, -5.0, 28.0, Vector3.UP)
	Fx.burst(root, at + Vector3(0, 0.2, 0), HOT, 10, 4.0, 0.14, 0.4, true, -3.0, 40.0, Vector3.UP)
	Fx.burst(root, at + Vector3(0, 0.1, 0), Color(0.25, 0.2, 0.17, 0.7), 12, 2.5, 0.35, 0.7, false, -1.5, 60.0, Vector3.UP)
	Fx.flash(root, at + Vector3(0, 0.7, 0), EMBER, 2.5, 0.25, 5.0)
	# a short spout of fire (Fx.pillar is a six-metre column: far too much for a crack in the ground)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cyl(0.9, 0.9, 1.0, 16)
	var m := Mats.glow_unique(EMBER, 2.2, 1.2, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.9, 0)
	mi.scale = Vector3(0.12, 0.3, 0.12)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.26, 1.5, 0.26), 0.12)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 0.8, 0.0, 0.3).set_delay(0.12)
	SkillFx.free_later(mi, 0.6)
	lava_decal(root, at, r * 0.8, 1.8, 0.6)

## A boulder lands: the splash of molten rock, the flash, the ring.
static func splash(root: Node3D, at: Vector3, r: float) -> void:
	Fx.ring(root, at + Vector3(0, 0.05, 0), r, EMBER, 0.45, 0.35)
	Fx.burst(root, at + Vector3(0, 0.3, 0), EMBER, 44, 6.0, 0.1, 0.7, true, -5.0, 75.0)
	Fx.burst(root, at + Vector3(0, 0.3, 0), HOT, 16, 4.0, 0.16, 0.5, true, -4.0, 60.0)
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.3, 0.25, 0.2, 0.7), 22, 3.0, 0.4, 0.8, false, -2.0, 70.0)
	Fx.flash(root, at + Vector3(0, 0.9, 0), HOT, 3.5, 0.3, 7.0)

## A meteor's crater: dark rock, molten at the heart, embers rising off it.
static func crater(root: Node3D, at: Vector3, r: float) -> void:
	lava_decal(root, at, r, 4.0, 0.7)
	Fx.ring(root, at + Vector3(0, 0.05, 0), r, EMBER, 0.4, 0.3)
	Fx.burst(root, at + Vector3(0, 0.3, 0), EMBER, 36, 6.0, 0.09, 0.7, true, -5.0, 70.0)
	Fx.burst(root, at + Vector3(0, 0.3, 0), HOT, 12, 4.0, 0.15, 0.45, true, -4.0, 50.0)
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.28, 0.22, 0.18, 0.7), 20, 3.2, 0.4, 0.8, false, -2.0, 70.0)
	Fx.flash(root, at + Vector3(0, 0.9, 0), HOT, 3.5, 0.3, 7.0)

## A lump of molten rock (a boulder, a meteor): dark crust with lava showing, an ember trail behind it.
static func boulder(root: Node3D, r: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh()
	mi.material_override = _rock_mat()
	mi.scale = Vector3(r, r * 0.85, r * 1.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = EMBER
	l.light_energy = 1.4
	l.omni_range = 4.0
	l.shadow_enabled = false
	n.add_child(l)
	var tr := Fx.aura(n, EMBER, 30, 1.2, 0.1, 0.5, 0.2, r * 0.9, 120.0, Vector3.ZERO)
	tr.local_coords = false
	return n

static func _rock_mesh() -> Mesh:
	if _rock == null:
		_rock = Geo.sph(1.0, 10)
	return _rock

static var _rock_m: StandardMaterial3D
static func _rock_mat() -> StandardMaterial3D:
	if _rock_m == null:
		# a dark crust, the heat a dull red inside it (a bright emission reads as a flat yellow disc from afar)
		_rock_m = Mats.mat(Color(0.1, 0.06, 0.05), 0.95, 0.0, Color(0.9, 0.25, 0.04), 0.45, 0.3)
	return _rock_m

static func _lava_mat(melt: float, wedge: float, strip := false) -> ShaderMaterial:
	if _lava_shader == null:
		_lava_shader = Shader.new()
		_lava_shader.code = LAVA_SHADER
	var m := ShaderMaterial.new()
	m.shader = _lava_shader
	m.set_shader_parameter("melt", melt)
	m.set_shader_parameter("wedge", wedge)
	m.set_shader_parameter("strip", 1.0 if strip else 0.0)
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("ember", EMBER)
	return m

## A unit disc in the XZ plane, UV = position (0.5 at the centre).
static func _disc_mesh() -> ArrayMesh:
	if _disc != null:
		return _disc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 36
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for p in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]:
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	_disc = st.commit()
	return _disc

## A unit strip in the XZ plane from z 0 to -1, x -0.5..0.5; UV.x across, UV.y along.
static func _strip_mesh() -> ArrayMesh:
	if _strip != null:
		return _strip
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1)]
	for p in quad:
		st.set_uv(Vector2(p.x + 0.5, -p.z))
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	_strip = st.commit()
	return _strip

const LAVA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float life = 1.0;      // 1 fresh .. 0 cooled and gone
uniform float melt = 0.0;      // 0 cracked rock, 1 a molten pool
uniform float wedge = 0.0;     // > 0: only a wedge of this half-angle (rad) opening toward -z
uniform float strip = 0.0;     // 1: a strip (UV.y along it) instead of a disc
uniform float seed = 0.0;
uniform vec3 ember : source_color = vec3(1.0, 0.42, 0.06);
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fb(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.1 + 1.7; a *= 0.5; } return v; }
void fragment(){
	vec2 q = UV * 2.0 - 1.0;
	float edge;
	vec2 np;
	if (strip > 0.5) {
		edge = (1.0 - smoothstep(0.55, 1.0, abs(q.x))) * (1.0 - smoothstep(0.9, 1.0, abs(q.y)));
		np = vec2(UV.x * 1.5, UV.y * 4.0);
	} else {
		float r = length(q);
		edge = 1.0 - smoothstep(0.62 + 0.25 * melt, 1.0, r + (vn(q * 5.0 + seed) - 0.5) * 0.25);
		if (wedge > 0.0) {
			float ang = atan(q.x, -q.y);
			edge *= 1.0 - smoothstep(wedge * 0.8, wedge, abs(ang));
			edge *= smoothstep(0.0, 0.25, r);
		}
		np = q * 3.0;
	}
	if (edge < 0.02) { discard; }
	float n = fb(np + seed);
	float crack = 1.0 - smoothstep(0.0, 0.07 + 0.05 * melt, abs(n - 0.5));
	float pool = smoothstep(0.35, 0.6, n) * melt;
	float hot = clamp(crack + pool, 0.0, 1.0);
	float breathe = 0.75 + 0.25 * sin(TIME * 2.1 + n * 9.0 + seed);
	float glow = hot * life * breathe;
	// cooling: the glow goes, then the dark rock fades out
	float rock = smoothstep(0.0, 0.25, life);
	ALBEDO = mix(vec3(0.05, 0.035, 0.03), ember * 0.5, glow);
	EMISSION = ember * glow * 3.4 + vec3(1.0, 0.9, 0.6) * pool * life * breathe * 1.6;
	ALPHA = edge * (0.45 + 0.5 * max(hot * life, rock * 0.6));
}
"""

## A steady drift of embers (Blood Pact on a summoned demon).
static func ember_aura() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.3
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.5, 0.1, 0.9))
	g.set_color(1, Color(0.9, 0.05, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## A few seconds of flame clinging to a clawed monster.
static func ignite(root: Node3D, target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var f := Props.fire(target, Vector3(0, 0.25 * float(target.get("height")), 0), 0.45 * float(target.get("height")) + 0.2, EMBER, false, false, false, "burning")
	SkillFx.free_later(f, 1.6)

# ---------------------------------------------------------------- the Underworld
## Souls rising from the ground all around the Demon while Phase lasts.
static func soul_field() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 3.2
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-16, -2, -12), Vector3(32, 10, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.2, 9)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.35, 0)
	pm.turbulence_enabled = false
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.2))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.6, 1.0, 0.0))
	g.add_point(0.25, Color(0.8, 0.7, 1.0, 0.75))
	g.set_color(1, Color(0.9, 0.2, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.2)
	q.material = Mats.particle_mat(true, Color(2.2, 2.2, 2.2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## Full-screen grade for the Underworld: the act is still there, but drained to bone and
## violet, crimson where anything burns, rippling like heat over the dark.
const UNDERWORLD_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amt = 0.0;
void fragment(){
	vec2 uv = SCREEN_UV;
	float w = sin(uv.y * 38.0 + TIME * 2.2) * 0.0018 + sin(uv.x * 23.0 - TIME * 1.4) * 0.0014;
	uv += vec2(w, -w * 0.7) * amt;
	vec2 dc = (uv - 0.5) * 0.007 * amt;
	vec3 c;
	c.r = texture(screen_tex, uv + dc).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - dc).b;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	// shadows sink to indigo, mid-tones turn violet, highlights go bone-pale; lifted so the
	// fight stays easy to read
	l = pow(clamp(l, 0.0, 1.0), 0.75);
	vec3 g = mix(vec3(0.05, 0.02, 0.1), vec3(0.46, 0.22, 0.66), smoothstep(0.0, 0.4, l));
	g = mix(g, vec3(1.0, 0.9, 0.95), smoothstep(0.4, 1.0, l));
	// anything burning (fires, eyes, ember edges) keeps its colour and turns blood-hot
	float hot = clamp((c.r - max(c.g, c.b)) * 2.2, 0.0, 1.0);
	g = mix(g, c * vec3(1.25, 0.55, 0.6), hot);
	vec3 o = mix(c, g, amt * 0.82);
	// a dark ring of veins pulsing at the edge of sight
	vec2 q = SCREEN_UV - 0.5;
	float r = length(q * vec2(1.7, 1.0));
	float vig = smoothstep(0.32, 0.92, r);
	float ang = atan(q.y, q.x);
	float veins = smoothstep(0.86, 1.0, sin(ang * 17.0 + sin(r * 28.0 - TIME * 1.8) * 1.6)) * vig;
	o = mix(o, vec3(0.015, 0.0, 0.03), vig * 0.55 * amt);
	o += vec3(0.65, 0.05, 0.22) * veins * 0.4 * amt * (0.6 + 0.4 * sin(TIME * 3.0));
	COLOR = vec4(o, 1.0);
}
"""
