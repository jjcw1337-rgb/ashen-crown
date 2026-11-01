class_name DemonChainFx
extends RefCounted
## Hellgrip's look, "Chain of the Pit" (the Demon's G; the gameplay is DemonSkills).
##
##  The fling ("fling" {p, d, x: the time out, r: the reach}): a sigil burns on his forearm and a chain forges out of
##  it, link by link, white-hot at his arm and cooling to a dull red along its length, an iron claw (the Meshy
##  grappling claw) at its head, sparks grinding off the links. Everyone sees the line it flies.
##  The hook ("hook" {t | pid, p, x: the haul, n: 1 = he is dragged to it}): the claw clamps with a flash and a spray
##  of sparks, fire catches on the victim, and the chain hauls them in (or him to them), the links rattling.
##  A miss ("miss" {p}): the claw snaps shut on nothing and the chain whips back to his arm.
##  The hold ("grab" {t | pid, x}): hoisted over his head (DemonFx's grip state lifts the body), the chain wrapped
##  round them burning.
##  The smash ("smash" {p, t, x}): driven into the ground: a ring of cracks, the chain sinking into them with a burst
##  of fire, rock flung up, a shock ring.
## State: h.fxs["chain"], kept by `update`.

const LINK := 0.16               # the chain's pitch
const MAX_LINKS := 64
const CLAW_SIZE := 0.55

static var _link_mesh: TorusMesh
static var _link_shader: Shader

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"fling":
			_fling(h, ev)
		"hook":
			_hook(h, ev)
		"miss":
			_miss(h, ev)
		"smash":
			_smash(h, ev)
		"end":
			_retract(h)
		"cast":
			_sigil(h)
		_:
			return false
	return true

## The sigil on his forearm as he reaches back.
static func _sigil(h: Hero) -> void:
	_end(h)
	var root: Node3D = h.game.world.fx_root
	var gm := InfernalFx.glow_mat(InfernalFx.MOLTEN, 2.0, 2.4, 0.5)
	var g := InfernalFx.glow(root, SkillFx.hand(h, true), 0.5, gm)
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.BLOODFIRE
	l.light_energy = 1.4
	l.omni_range = 3.0
	l.shadow_enabled = false
	root.add_child(l)
	h.fxs["chain"] = {"state": "ready", "sig": g, "sig_mat": gm, "light": l, "until": 3.0, "len": 0.0, "max": DemonSkills.CHAIN_LEN,
		"dir": h.facing(), "speed": DemonSkills.CHAIN_SPEED}
	SkillFx.snd(h, "fire_erupt", -14.0, 1.3)

static func _fling(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty() or str(st.get("state", "")) != "ready":
		_sigil(h)
		st = h.fxs["chain"]
	st["state"] = "out"
	st["dir"] = ev.get("d", h.facing())
	st["len"] = 0.0
	st["max"] = float(ev.get("r", DemonSkills.CHAIN_LEN))
	st["speed"] = st["max"] / maxf(float(ev.get("x", 0.3)), 0.05)
	st["until"] = 4.0
	# the links: one multimesh, each link's heat in its colour
	if _link_mesh == null:
		_link_mesh = TorusMesh.new()
		_link_mesh.inner_radius = 0.045
		_link_mesh.outer_radius = 0.085
		_link_mesh.rings = 10
		_link_mesh.ring_segments = 6
		_link_shader = Shader.new()
		_link_shader.code = LINK_SHADER
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _link_mesh
	mm.instance_count = MAX_LINKS
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var lm := ShaderMaterial.new()
	lm.shader = _link_shader
	mmi.material_override = lm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tr >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 10.0
	root.add_child(mmi)
	mmi.global_position = Vector3.ZERO
	st["links"] = mmi
	# the claw at its head
	var claw := Node3D.new()
	root.add_child(claw)
	var cm := DemonKitFx.model(DemonKitFx.CLAW)
	if cm != null:
		DemonKitFx.heat_model(cm, 0.6)
		# modelled upright with the chain ring on top: lay it along the chain, talons leading
		cm.rotation = Vector3(-PI * 0.5, 0, 0)
		cm.position = Vector3(0, 0, -CLAW_SIZE * 0.5)
		cm.scale = Vector3.ONE * CLAW_SIZE
		claw.add_child(cm)
	else:
		for k in 3:
			var t := MeshInstance3D.new()
			t.mesh = InfernalFx.shard_mesh(k)
			t.material_override = InfernalFx.shard_mat()
			t.scale = Vector3(0.12, 0.35, 0.12)
			t.rotation = Vector3(-PI * 0.4, TAU * k / 3.0, 0)
			claw.add_child(t)
	st["claw"] = claw
	st["sparks"] = InfernalFx.particles(claw, claw.global_position, {"amount": [6, 10, 14, 18][tr], "life": 0.35, "one_shot": false,
		"dir": Vector3.UP, "spread": 70.0, "vel": [1.0, 3.0], "gravity": -8.0, "scale": [0.5, 1.0], "size": 0.045,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.4, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	SkillFx.snd(h, "cleave_swing", -3.0, 0.8)
	SkillFx.snd(h, "shackles", -7.0, 0.85)

static func _hook(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	var vs := DemonKitFx.targets(h, ev)
	var p: Vector3 = ev.get("p", h.global_position)
	st["state"] = "hooked"
	st["self"] = int(ev.get("n", 0)) == 1
	st["until"] = float(ev.get("x", 0.5)) + 2.5
	if not vs.is_empty():
		var v: Node3D = vs[0]
		st["victim"] = v
		var f := InfernalFx.fire(v, DemonKitFx.chest(v, 0.5), DemonKitFx.height_of(v) * 0.7, 35.0, tr, true, true)
		f.name = "ChainFire"
		st["vfire"] = f
	var gm := InfernalFx.glow_mat(InfernalFx.WHITEHOT, 2.4, 2.0, 0.6)
	var g := InfernalFx.glow(root, p, 0.5, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * 1.8, 0.14).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.18)
	Fx._free_later(g, 0.22)
	InfernalFx.particles(root, p, {"amount": [12, 18, 26, 30][tr], "life": 0.4, "explosive": 1.0, "dir": -(st["dir"] as Vector3) + Vector3(0, 0.4, 0),
		"spread": 55.0, "vel": [3.0, 7.0], "gravity": -9.0, "damping": [1.0, 2.0], "scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.35, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	Sfx.play_at("charge_impact", p, -4.0, 1.3)
	Sfx.play_at("impact_bone", p, -6.0, 0.8)
	SkillFx.shake(h, 0.18)

static func _miss(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	st["state"] = "back"
	st["until"] = 1.5
	var p: Vector3 = ev.get("p", h.global_position)
	Fx.burst(h.game.world.fx_root, p, InfernalFx.MOLTEN, 8, 2.0, 0.05, 0.3, true, -6.0, 90.0)
	Sfx.play_at("cleave_swing", p, -10.0, 1.4)

## The smash: the ground cracks in a ring, the chain sinks into it in a burst of fire.
static func _smash(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at: Vector3 = ev["p"]
	at.y = world.height_at(at.x, at.z)
	var held: bool = bool(ev.get("x", false))
	var rm := InfernalFx.rift_mat()
	var rift := MeshInstance3D.new()
	rift.mesh = InfernalFx.disc_mesh(world, at, DemonSkills.GRIP_SHOCK_R, 32, 5, 0.045)
	rift.material_override = rm
	rift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rift)
	rift.global_position = at
	InfernalFx.tween_param(rift, rm, "front", 0.0, 1.05, 0.14)
	InfernalFx.tween_param(rift, rm, "heat", 1.4, 0.0, 1.2, 0.15)
	InfernalFx.tween_param(rift, rm, "life", 1.0, 0.0, 1.0, 1.2)
	Fx._free_later(rift, 2.4)
	DemonFx.lava_decal(root, at, 1.2, 2.6, 0.55)
	DemonKitFx.shock_ring(root, h.game, at, DemonSkills.GRIP_SHOCK_R * 1.2, 0.3)
	DemonKitFx.flash_light(root, at + Vector3(0, 0.8, 0), InfernalFx.WHITEHOT if held else InfernalFx.MOLTEN, 4.5 if held else 2.0, 7.0, 0.45)
	DemonKitFx.debris(root, at + Vector3(0, 0.3, 0), [4, 6, 8, 10][tr] if held else 3, Vector3.UP, 4.2, 0.16)
	for i in [3, 4, 6, 7][tr]:
		var ang: float = TAU * float(i) / [3, 4, 6, 7][tr] + randf_range(-0.3, 0.3)
		var fp := at + Vector3(cos(ang), 0, sin(ang)) * randf_range(0.7, DemonSkills.GRIP_SHOCK_R * 0.8)
		fp.y = world.height_at(fp.x, fp.z)
		DemonKitFx.flare_fire(root, fp, randf_range(0.9, 1.4), randf_range(0.0, 0.08), 0.45, tr, i % 2 == 0)
	InfernalFx.smoke(root, at + Vector3(0, 0.4, 0), [3, 6, 9, 11][tr], Vector3(0.9, 0.2, 0.9), Vector3.UP, 1.5, 1.8, 1.1, 0.75)
	for e in ev.get("t", []):
		DemonFx.ignite(root, e)
	_retract(h, true)
	Sfx.play_at("slam", at, 0.0 if held else -6.0, 0.82)
	Sfx.play_at("boom", at, -6.0, 0.9)
	if held:
		Sfx.play_at("hellclaw", at, -5.0, 0.75)
	SkillFx.shake(h, 0.45 if held else 0.15)

## The chain goes: whipped back to his arm (or, sunk with the smash, gone in the flash).
static func _retract(h: Hero, sunk := false) -> void:
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	if sunk:
		_end(h)
		return
	st["state"] = "back"
	st["until"] = minf(float(st.get("until", 1.0)), 1.2)

static func _end(h: Hero) -> void:
	if not h.fxs.has("chain"):
		return
	var st: Dictionary = h.fxs["chain"]
	h.fxs.erase("chain")
	for key in ["links", "claw", "sig", "light"]:
		var n = st.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var f = st.get("vfire")
	if f != null and is_instance_valid(f):
		InfernalFx.fire_on(f, false)
		Fx._free_later(f, 1.0)

## Every frame: the chain from his hand to its head, the head flying out, holding on, or coming back.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("chain"):
		return
	var st: Dictionary = h.fxs["chain"]
	st["until"] = float(st["until"]) - delta
	if float(st["until"]) <= 0.0:
		_end(h)
		return
	var hand := SkillFx.hand(h, true)
	var sg = st.get("sig")
	if sg != null and is_instance_valid(sg):
		(sg as Node3D).global_position = hand
		(st["sig_mat"] as ShaderMaterial).set_shader_parameter("alpha", 0.75 + 0.25 * sin(h.anim_time * 20.0))
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		(l as OmniLight3D).global_position = hand
	var dir: Vector3 = st["dir"]
	var tip: Vector3
	match str(st["state"]):
		"ready":
			return
		"out":
			st["len"] = minf(float(st["len"]) + float(st["speed"]) * delta, float(st["max"]))
			tip = hand + dir * float(st["len"])
		"hooked":
			var v = st.get("victim")
			if v != null and is_instance_valid(v):
				tip = DemonKitFx.chest(v, 0.6)
			else:
				st["state"] = "back"
				tip = hand + dir * float(st["len"])
			st["len"] = (tip - hand).length()
		"back":
			st["len"] = maxf(float(st["len"]) - 26.0 * delta, 0.0)
			tip = hand + dir * float(st["len"])
			if float(st["len"]) <= 0.05:
				_end(h)
				return
		_:
			tip = hand
	var claw = st.get("claw")
	if claw != null and is_instance_valid(claw):
		(claw as Node3D).global_position = tip
		var fw := (tip - hand)
		if fw.length() > 0.05:
			(claw as Node3D).look_at(tip + fw.normalized(), Vector3.UP if absf(fw.normalized().y) < 0.95 else Vector3.RIGHT)
	_lay_links(st, hand, tip, h.anim_time, str(st["state"]) == "hooked")

## The links along a slight sag from his hand to the head; the colour is each link's heat (white at his arm,
## cooling to a dull red, brightening again where a hooked chain strains).
static func _lay_links(st: Dictionary, a: Vector3, b: Vector3, t: float, taut: bool) -> void:
	var mmi = st.get("links")
	if mmi == null or not is_instance_valid(mmi):
		return
	var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
	var d := b - a
	var len := d.length()
	var n := mini(int(len / LINK), MAX_LINKS)
	mm.visible_instance_count = n
	if n <= 0:
		return
	var axis := d / len
	var up := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var sag := (0.05 if taut else 0.25) * len / DemonSkills.CHAIN_LEN
	for i in n:
		var u := (float(i) + 0.5) / float(n)
		var p := a + d * u - Vector3(0, sin(u * PI) * sag, 0)
		if taut:
			p += axis.cross(up).normalized() * sin(u * 30.0 + t * 40.0) * 0.015
		var z := axis
		var x := z.cross(up).normalized()
		var y := x.cross(z)
		var bs := Basis(x, y, z) * Basis(Vector3.FORWARD, PI * 0.5 * float(i % 2)) * Basis(Vector3.RIGHT, PI * 0.5)
		mm.set_instance_transform(i, Transform3D(bs, p))
		var heat := clampf(1.0 - u * 1.6, 0.0, 1.0) + (0.35 if taut else 0.0) * (0.6 + 0.4 * sin(t * 12.0 + u * 9.0))
		mm.set_instance_color(i, Color(heat, 0, 0, 1))

static func clear(h: Hero) -> void:
	_end(h)

const LINK_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec3 iron : source_color = vec3(0.07, 0.055, 0.05);
uniform vec3 whitehot : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 molten : source_color = vec3(1.0, 0.42, 0.07);
uniform vec3 crimson : source_color = vec3(0.78, 0.035, 0.05);
varying float heat;
void vertex() { heat = COLOR.r; }
void fragment() {
	float h = clamp(heat, 0.0, 1.2);
	vec3 glow = mix(crimson * 0.6, molten, smoothstep(0.15, 0.6, h));
	glow = mix(glow, whitehot, smoothstep(0.7, 1.0, h));
	ALBEDO = mix(iron, glow * 0.25, smoothstep(0.3, 1.0, h));
	METALLIC = 0.85;
	ROUGHNESS = mix(0.55, 0.85, h);
	EMISSION = glow * (0.25 + 2.6 * h * h);
}
"""
