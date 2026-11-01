class_name DemonChargeFx
extends RefCounted
## Infernal Charge's look, "Hellrunner" (the Demon's E; the gameplay is DemonSkills).
##
##  Wind-up ("wind" {p, q, d, x}): he paws the ground and lowers his head; a burning line tears itself along the
##  ground from his hooves to where he will stop (the exact path, for everyone: the warning his victims get), his
##  horns catch fire, smoke snorts out of his nostrils, the ground cracks under the pawing hoof.
##  The run ("run" {d}): his horns stream fire back over him, the air bends ahead of him (a bow wave of heat haze
##  from High), every hoofstrike cracks the ground and leaves a print glowing then cooling to black (looks only:
##  no hazard), embers drag in his wake.
##  A hit ("hit" {p, d, x: a big one that stopped him}): horn sparks in a cone, a molten flash, dust thrown up,
##  a dull crack; a big one adds a shock ring and a light pop.
##  The skid ("skid" {p, d}): two grooves ploughed behind him glowing at the edges, a plume of dust and embers
##  ahead, sparks from the hand he drags.
## State: h.fxs["hellrunner"] (the line, the horns, the prints), kept by `update`, timing itself out on a partner's
## game if the end is lost.

const HORN_SPLIT := 0.36
const PRINT_EVERY := 0.95

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"wind":
			_wind(h, ev)
		"run":
			_run(h, ev)
		"hit":
			_hit(h, ev)
		"skid":
			_skid(h, ev)
		"end":
			_end(h)
		"cast":
			pass
		_:
			return false
	return true

static func _wind(h: Hero, ev: Dictionary) -> void:
	_end(h)
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev.get("p", h.global_position)
	var q: Vector3 = ev.get("q", p + h.facing() * 6.0)
	var wind: float = float(ev.get("x", 0.35))
	p.y = world.height_at(p.x, p.z)
	# the path: a crack tearing out from his hooves to the end of the charge, in the time he takes to set off
	var ck := DemonKitFx.crack(root, world, p, q, 0.55)
	var rm: ShaderMaterial = ck[1]
	InfernalFx.tween_param(ck[0], rm, "front", 0.0, 1.05, wind * 0.85).set_ease(Tween.EASE_OUT)
	rm.set_shader_parameter("heat", 0.75)
	# the horns
	var horns: Array = []
	for sx in [-1.0, 1.0]:
		var hp: Vector3 = DemonKitFx.head(h) + h.facing().cross(Vector3.UP) * sx * HORN_SPLIT * 0.5
		var f := InfernalFx.fire(root, hp, 0.55, 60.0, tr, tr >= 2, true)
		horns.append({"fire": f, "sx": sx})
	# snorted smoke and the pawing hoof cracking the ground
	InfernalFx.smoke(root, DemonKitFx.head(h) + h.facing() * 0.3 - Vector3(0, 0.25, 0), [2, 3, 5, 6][tr], Vector3(0.1, 0.05, 0.1),
		(h.facing() + Vector3(0, -0.4, 0)).normalized(), 0.6, 0.9, 0.4, 0.65)
	var hoof := p + h.facing() * 0.35
	hoof.y = world.height_at(hoof.x, hoof.z)
	var hc := DemonFx.lava_decal(root, hoof, 0.55, 1.4, 0.15)
	hc.scale = Vector3(0.55, 1, 0.55)
	Fx.burst(root, hoof + Vector3(0, 0.1, 0), Color(0.22, 0.17, 0.14, 0.7), [5, 8, 10, 12][tr], 1.6, 0.25, 0.5, false, -4.0, 60.0, Vector3.UP)
	h.fxs["hellrunner"] = {"line": ck[0], "line_mat": rm, "horns": horns, "until": wind + 3.0, "laid": 0.0, "last": h.global_position,
		"stage": "wind", "trail": []}
	SkillFx.snd(h, "growl", -5.0, 0.7)
	SkillFx.snd(h, "fire_erupt", -14.0, 1.4)
	SkillFx.snd(h, "impact_bone", -12.0, 0.55)

static func _run(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("hellrunner", {})
	if st.is_empty():
		_wind(h, {"p": h.global_position, "q": h.global_position + (ev.get("d", h.facing()) as Vector3) * 8.0, "x": 0.01})
		st = h.fxs["hellrunner"]
	st["stage"] = "run"
	st["last"] = h.global_position
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var d: Vector3 = ev.get("d", h.facing())
	# the wake: embers torn off him and dragged behind
	var wake := InfernalFx.particles(root, h.global_position + Vector3(0, 1.0, 0), {"amount": [14, 24, 34, 44][tr], "life": 0.7,
		"one_shot": false, "shape": "sphere", "r": 0.6, "dir": -d + Vector3(0, 0.3, 0), "spread": 25.0, "vel": [1.0, 3.0],
		"gravity": 0.6, "damping": [0.5, 1.2], "scale": [0.4, 1.0], "size": 0.06, "turb": 2.0,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.3, InfernalFx.MOLTEN], [0.75, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	st["wake"] = wake
	# the bow wave: the air bending ahead of him
	if InfernalFx.haze_ok(h.game):
		var hz := InfernalFx.haze_mat(0.04, true)
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.4, 2.2)
		mi.mesh = qm
		mi.material_override = hz
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		st["bow"] = mi
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.MOLTEN
	l.light_energy = 1.6
	l.omni_range = 5.0
	l.shadow_enabled = false
	root.add_child(l)
	st["light"] = l
	SkillFx.snd(h, "charge_dash", -1.0, 0.8)
	SkillFx.snd(h, "fireball", -9.0, 0.7)

static func _hit(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev["p"]
	var d: Vector3 = ev.get("d", h.facing())
	var big: bool = bool(ev.get("x", false))
	# horn sparks in a cone, a molten spray, the flash
	InfernalFx.particles(root, p, {"amount": [12, 18, 26, 32][tr] + (10 if big else 0), "life": 0.4, "explosive": 1.0,
		"dir": (d + Vector3(0, 0.35, 0)).normalized(), "spread": 38.0, "vel": [4.0, 10.0], "gravity": -9.0,
		"damping": [1.5, 3.0], "scale": [0.5, 1.0], "size": 0.07,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.3, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	var gm := InfernalFx.glow_mat(InfernalFx.WHITEHOT if big else InfernalFx.MOLTEN, 2.0, 2.2, 0.5)
	var g := InfernalFx.glow(root, p, 0.6, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * (2.4 if big else 1.6), 0.16).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.2)
	Fx._free_later(g, 0.25)
	var gp := p
	gp.y = h.game.world.height_at(p.x, p.z)
	Fx.burst(root, gp + Vector3(0, 0.2, 0), Color(0.22, 0.17, 0.14, 0.75), [6, 9, 12, 14][tr], 2.6, 0.3, 0.6, false, -4.0, 55.0, d + Vector3.UP)
	if big:
		DemonKitFx.shock_ring(root, h.game, gp, 2.6, 0.32)
		DemonKitFx.flash_light(root, p, InfernalFx.MOLTEN, 4.0, 6.0, 0.35)
		DemonKitFx.debris(root, gp + Vector3(0, 0.3, 0), [2, 4, 5, 6][tr], d, 3.5, 0.12)
		Sfx.play_at("charge_impact", p, -1.0, 0.75)
		Sfx.play_at("impact_bone", p, -5.0, 0.6)
		Sfx.play_at("slam", p, -9.0, 1.2)
		SkillFx.shake(h, 0.32)
	else:
		Sfx.play_at("charge_impact", p, -5.0, 0.95)
		SkillFx.shake(h, 0.12)

static func _skid(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev.get("p", h.global_position)
	var d: Vector3 = ev.get("d", h.facing())
	p.y = world.height_at(p.x, p.z)
	var st: Dictionary = h.fxs.get("hellrunner", {})
	st["stage"] = "skid"
	var w = st.get("wake")
	if w != null and is_instance_valid(w):
		(w as GPUParticles3D).emitting = false
		Fx._free_later(w, 0.8)
		st.erase("wake")
	# two grooves ploughed behind him, glowing at their edges, cooling
	var side := d.cross(Vector3.UP).normalized()
	for sx in [-1.0, 1.0]:
		var a: Vector3 = p - d * 2.6 + side * sx * 0.32
		var b: Vector3 = p + d * 0.5 + side * sx * 0.32
		var ck := DemonKitFx.crack(root, world, a, b, 0.32)
		var rm: ShaderMaterial = ck[1]
		InfernalFx.tween_param(ck[0], rm, "front", 0.0, 1.05, 0.2)
		InfernalFx.tween_param(ck[0], rm, "heat", 1.0, 0.0, 1.2, 0.2)
		InfernalFx.tween_param(ck[0], rm, "life", 1.0, 0.0, 1.0, 1.4)
		Fx._free_later(ck[0], 2.6)
	# the plume thrown forward, the hand dragged through the dirt
	var front := p + d * 0.9
	InfernalFx.smoke(root, front + Vector3(0, 0.3, 0), [3, 5, 8, 10][tr], Vector3(0.5, 0.1, 0.5), (d + Vector3(0, 0.5, 0)).normalized(), 1.0, 1.2, 0.5, 0.55)
	Fx.burst(root, front + Vector3(0, 0.15, 0), Color(0.24, 0.19, 0.15, 0.75), [8, 12, 16, 20][tr], 3.5, 0.32, 0.7, false, -4.0, 40.0, d + Vector3(0, 0.6, 0))
	DemonKitFx.embers(root, front + Vector3(0, 0.2, 0), [10, 16, 22, 28][tr], 35.0, Vector2(2.0, 5.0), (d + Vector3(0, 0.7, 0)).normalized())
	var hand := SkillFx.hand(h, true)
	InfernalFx.particles(root, Vector3(hand.x, p.y + 0.1, hand.z), {"amount": [6, 10, 14, 16][tr], "life": 0.35, "explosive": 1.0,
		"dir": (d + Vector3(0, 0.5, 0)).normalized(), "spread": 30.0, "vel": [2.0, 5.0], "gravity": -9.0, "scale": [0.5, 1.0], "size": 0.05,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.4, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	_drop_bow(st)
	SkillFx.snd(h, "impact_bone", -10.0, 0.5)
	SkillFx.snd(h, "charge_dash", -11.0, 0.55)
	SkillFx.shake(h, 0.1)

static func _drop_bow(st: Dictionary) -> void:
	var b = st.get("bow")
	if b != null and is_instance_valid(b):
		(b as Node).queue_free()
	st.erase("bow")

## The horns gutter, the line cools, the light goes.
static func _end(h: Hero) -> void:
	if not h.fxs.has("hellrunner"):
		return
	var st: Dictionary = h.fxs["hellrunner"]
	h.fxs.erase("hellrunner")
	for hd in st.get("horns", []):
		var f = hd["fire"]
		if f != null and is_instance_valid(f):
			InfernalFx.fire_on(f, false)
			Fx._free_later(f, 1.2)
	var ln = st.get("line")
	if ln != null and is_instance_valid(ln):
		var rm: ShaderMaterial = st["line_mat"]
		InfernalFx.tween_param(ln, rm, "heat", float(rm.get_shader_parameter("heat")), 0.0, 0.6)
		InfernalFx.tween_param(ln, rm, "life", 1.0, 0.0, 0.8, 0.5)
		Fx._free_later(ln, 1.4)
	var w = st.get("wake")
	if w != null and is_instance_valid(w):
		(w as GPUParticles3D).emitting = false
		Fx._free_later(w, 0.8)
	_drop_bow(st)
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		var tw := (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.3)
		tw.tween_callback((l as Node).queue_free)

## Every frame (the caster's and the puppet's): the horns ride his head, the hoofprints, the bow wave, the light.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("hellrunner"):
		return
	var st: Dictionary = h.fxs["hellrunner"]
	st["until"] = float(st["until"]) - delta
	if float(st["until"]) <= 0.0:
		_end(h)
		return
	var world = h.game.world
	var root: Node3D = world.fx_root
	var fwd := h.facing()
	var side := fwd.cross(Vector3.UP).normalized()
	for hd in st.get("horns", []):
		var f = hd["fire"]
		if f != null and is_instance_valid(f):
			(f as Node3D).global_position = DemonKitFx.head(h) + side * float(hd["sx"]) * HORN_SPLIT * 0.5
	var ln = st.get("line")
	if ln != null and is_instance_valid(ln) and str(st["stage"]) == "wind":
		var rm: ShaderMaterial = st["line_mat"]
		rm.set_shader_parameter("heat", 0.75 + 0.25 * sin(h.anim_time * 22.0))
	if str(st["stage"]) == "run":
		var moved: float = (h.global_position - (st["last"] as Vector3)).length()
		st["last"] = h.global_position
		st["laid"] = float(st["laid"]) + moved
		if float(st["laid"]) >= PRINT_EVERY:
			st["laid"] = 0.0
			_print(h, root, world, side, int(st.get("n", 0)))
			st["n"] = int(st.get("n", 0)) + 1
		var b = st.get("bow")
		if b != null and is_instance_valid(b):
			(b as Node3D).global_position = h.global_position + fwd * 1.3 + Vector3(0, 1.1, 0)
			(b as Node3D).look_at((b as Node3D).global_position + fwd, Vector3.UP)
		var w = st.get("wake")
		if w != null and is_instance_valid(w):
			(w as Node3D).global_position = h.global_position + Vector3(0, 1.0, 0)
		var l = st.get("light")
		if l != null and is_instance_valid(l):
			(l as OmniLight3D).global_position = h.global_position + Vector3(0, 1.4, 0) + fwd * 0.6
			(l as OmniLight3D).light_energy = 1.6 * (0.85 + 0.15 * sin(h.anim_time * 27.0))

## A hoofprint: a small crack that glows and cools to black, a puff of dust and a few embers.
static func _print(h: Hero, root: Node3D, world, side: Vector3, n: int) -> void:
	var p := h.global_position + side * (0.22 if n % 2 == 0 else -0.22)
	p.y = world.height_at(p.x, p.z)
	var dc := DemonFx.lava_decal(root, p, 0.3, 1.8, 0.25, h.rig.global_rotation.y)
	dc.scale = Vector3(0.24, 1, 0.34)
	Fx.burst(root, p + Vector3(0, 0.08, 0), Color(0.22, 0.17, 0.14, 0.6), 4, 1.2, 0.22, 0.4, false, -3.0, 70.0, Vector3.UP)
