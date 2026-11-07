class_name InfernalChargeFx
extends RefCounted
## Infernal Charge's look, "Hellrunner" (the Demon's E; the gameplay is InfernalCharge). Ash, dirt and a burning ram's
## skull, not hellfire: nothing here is Molten Fists'.
##
##  Wind-up ("wind" {p, q, d, x}): he paws the ground (it's crushed in, clods fly, a puff of simulated ash), snorts
##  ash; a scorched gouge burns itself along the ground from his hooves to where he will stop (a Meshy-painted
##  furrow projected on the terrain, its embers igniting: the exact path, for everyone); a burning ram's skull (the
##  Meshy skull, a flickering ghost of fire) rises before his head.
##  The run ("run" {d}): the skull leads him, the air bending round it (heat haze from High); every hoofstrike throws
##  a puff of simulated ash and dust, clods and a few sparks off his hooves; a light rides with him.
##  A hit ("hit" {p, d, x: a big one that stopped him}): sparks in a cone off his horns, a puff of ash; a big one
##  adds the skull bursting forward, a shock ring, a light pop, a heavy crack.
##  The skid ("skid" {p, d}): his hooves plough a furrow behind him, a wave of ash and dirt rolls out ahead, sparks
##  off the hand he drags.
## State: h.fxs["hellrunner"] (the furrow, the skull, the light), kept by `update`, timing itself out on a partner's
## game if the end is lost.

## The ram's horns his apparition wears (a Meshy model).
const HORNS := "res://game/heroes/demon/skills/infernal_charge/horns.glb"
const PRINT_EVERY := 1.3
const SKULL := 1.0

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
	# the path: a scorched gouge from his hooves to the end of the charge
	var d := (q - p) * Vector3(1, 0, 1)
	var mid := p + d * 0.5
	mid.y = world.height_at(mid.x, mid.z)
	var fur := DemonKitFx.decal(root, mid, "furrow", Vector2(d.length() + 1.2, 1.5), atan2(-d.z, d.x), wind + 2.6, 5.0)
	fur.scale = Vector3(0.02, 1, 1)
	var tw := fur.create_tween()
	tw.tween_property(fur, "scale", Vector3.ONE, wind * 0.8).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(fur, "position", fur.position, wind * 0.8)
	fur.position = fur.position - Vector3(d.x, 0, d.z) * 0.49
	# the burning ram's skull rising before him
	var skull := Node3D.new()
	root.add_child(skull)
	var sm := DemonKitFx.model(InfernalChargeFx.HORNS)
	var gm := DemonKitFx.ghost_mat(Color(1.0, 0.32, 0.06), 0.8)
	if sm != null:
		for mi in sm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = gm
		sm.position = Vector3(0, -0.45, 0)
		skull.add_child(sm)
	skull.scale = Vector3.ONE * 0.2
	skull.create_tween().tween_property(skull, "scale", Vector3.ONE * SKULL, wind).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var em := InfernalFx.particles(skull, skull.global_position, {"amount": [6, 10, 16, 20][tr], "life": 0.5, "one_shot": false,
		"shape": "sphere", "r": 0.5, "dir": Vector3.UP, "spread": 40.0, "vel": [0.4, 1.4], "gravity": 1.2,
		"scale": [0.4, 1.0], "size": 0.05,
		"colors": [[0.0, Color(1.0, 0.85, 0.6)], [0.4, Color(1.0, 0.42, 0.08)], [1.0, Color(0.5, 0.05, 0.02, 0.0)]]})
	# the paw and the snort
	var hoof := p + h.facing() * 0.4
	hoof.y = world.height_at(hoof.x, hoof.z)
	DemonKitFx.decal(root, hoof, "crush", Vector2(0.9, 0.9), randf() * TAU, 2.4, 0.15)
	DemonKitFx.smoke(root, hoof, "ash", 0.9, 0.9)
	DemonKitFx.clods(root, hoof + Vector3(0, 0.1, 0), [5, 8, 10, 12][tr], 2.4)
	DemonKitFx.smoke(root, DemonFx.head(h) + h.facing() * 0.45 - Vector3(0, 0.5, 0), "ash", 0.55, 0.8, false, Color(0.7, 0.66, 0.62, 0.8))
	h.fxs["hellrunner"] = {"furrow": fur, "skull": skull, "skull_mat": gm, "em": em, "until": wind + 3.0, "laid": 0.0,
		"last": h.global_position, "stage": "wind"}
	SkillFx.snd(h, "growl", -4.0, 0.68)
	SkillFx.snd(h, "impact_bone", -11.0, 0.5)

static func _run(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("hellrunner", {})
	if st.is_empty():
		_wind(h, {"p": h.global_position, "q": h.global_position + (ev.get("d", h.facing()) as Vector3) * 8.0, "x": 0.01})
		st = h.fxs["hellrunner"]
	st["stage"] = "run"
	st["last"] = h.global_position
	var root: Node3D = h.game.world.fx_root
	if InfernalFx.haze_ok(h.game):
		var hz := InfernalFx.haze_mat(0.045, true)
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.6, 2.4)
		mi.mesh = qm
		mi.material_override = hz
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		st["bow"] = mi
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.12)
	l.light_energy = 1.8
	l.omni_range = 5.0
	l.shadow_enabled = false
	root.add_child(l)
	st["light"] = l
	(st["skull_mat"] as ShaderMaterial).set_shader_parameter("energy", 1.2)
	SkillFx.snd(h, "charge_dash", -1.0, 0.75)

static func _hit(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev["p"]
	var d: Vector3 = ev.get("d", h.facing())
	var big: bool = bool(ev.get("x", false))
	DemonKitFx.sparks(root, p, d + Vector3(0, 0.3, 0), [10, 16, 22, 28][tr] + (12 if big else 0), 38.0, Vector2(5.0, 12.0))
	var gp := p
	gp.y = h.game.world.height_at(p.x, p.z)
	DemonKitFx.smoke(root, gp, "ash", 1.5 if big else 1.0, 1.0)
	DemonKitFx.clods(root, gp + Vector3(0, 0.2, 0), [6, 9, 12, 14][tr], 3.5, d + Vector3.UP)
	if big:
		var st: Dictionary = h.fxs.get("hellrunner", {})
		var sk = st.get("skull")
		if sk != null and is_instance_valid(sk):
			# the skull smashes on into them and bursts
			var tw := (sk as Node3D).create_tween().set_parallel(true)
			tw.tween_property(sk, "global_position", (sk as Node3D).global_position + d * 1.4, 0.16)
			tw.tween_property(sk, "scale", Vector3.ONE * SKULL * 1.8, 0.16)
			InfernalFx.tween_param(sk, st["skull_mat"], "alpha", 1.0, 0.0, 0.18)
			st.erase("skull")
			Fx._free_later(sk, 0.25)
		DemonKitFx.shock_ring(root, h.game, gp, 2.6, 0.32)
		DemonKitFx.flash_light(root, p, Color(1.0, 0.6, 0.3), 4.0, 6.0, 0.35)
		Sfx.play_at("charge_impact", p, -1.0, 0.72)
		Sfx.play_at("impact_bone", p, -5.0, 0.55)
		Sfx.play_at("slam", p, -9.0, 1.15)
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
	# the furrow his hooves plough as he brakes
	var back := p - d * 1.2
	DemonKitFx.decal(root, back, "furrow", Vector2(3.0, 1.3), atan2(-d.z, d.x), 3.5, 2.5)
	var front := p + d * 1.0
	DemonKitFx.smoke(root, front, "ash", 1.7, 1.2)
	DemonKitFx.smoke(root, front + d.cross(Vector3.UP) * 0.7, "ash", 1.1, 1.1)
	DemonKitFx.smoke(root, front - d.cross(Vector3.UP) * 0.7, "ash", 1.1, 1.1)
	DemonKitFx.clods(root, front + Vector3(0, 0.15, 0), [10, 16, 22, 26][tr], 4.0, d + Vector3(0, 0.6, 0), 40.0)
	var hand := SkillFx.hand(h, true)
	DemonKitFx.sparks(root, Vector3(hand.x, p.y + 0.1, hand.z), d + Vector3(0, 0.5, 0), [8, 12, 16, 20][tr], 30.0, Vector2(3.0, 7.0))
	_drop_skull(st)
	_drop_bow(st)
	SkillFx.snd(h, "impact_bone", -10.0, 0.5)
	SkillFx.snd(h, "charge_dash", -11.0, 0.55)
	SkillFx.shake(h, 0.1)

static func _drop_bow(st: Dictionary) -> void:
	var b = st.get("bow")
	if b != null and is_instance_valid(b):
		(b as Node).queue_free()
	st.erase("bow")

static func _drop_skull(st: Dictionary) -> void:
	var sk = st.get("skull")
	if sk != null and is_instance_valid(sk):
		var em = st.get("em")
		if em != null and is_instance_valid(em):
			(em as GPUParticles3D).emitting = false
		InfernalFx.tween_param(sk, st["skull_mat"], "alpha", 1.0, 0.0, 0.3)
		Fx._free_later(sk, 0.9)
	st.erase("skull")

static func _end(h: Hero) -> void:
	if not h.fxs.has("hellrunner"):
		return
	var st: Dictionary = h.fxs["hellrunner"]
	h.fxs.erase("hellrunner")
	_drop_skull(st)
	_drop_bow(st)
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		var tw := (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.3)
		tw.tween_callback((l as Node).queue_free)

## Every frame (the caster's and the puppet's): the skull leads his head, the hoofstrikes, the bow wave, the light.
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
	var sk = st.get("skull")
	if sk != null and is_instance_valid(sk):
		var lead := 0.9 if str(st["stage"]) == "run" else 0.55
		(sk as Node3D).global_position = DemonFx.head(h) + fwd * lead - Vector3(0, 0.25, 0)
		(sk as Node3D).look_at((sk as Node3D).global_position - fwd, Vector3.UP)
	if str(st["stage"]) == "run":
		var moved: float = (h.global_position - (st["last"] as Vector3)).length()
		st["last"] = h.global_position
		st["laid"] = float(st["laid"]) + moved
		if float(st["laid"]) >= PRINT_EVERY:
			st["laid"] = 0.0
			_hoofstrike(h, root, world, int(st.get("n", 0)))
			st["n"] = int(st.get("n", 0)) + 1
		var b = st.get("bow")
		if b != null and is_instance_valid(b):
			(b as Node3D).global_position = h.global_position + fwd * 1.5 + Vector3(0, 1.2, 0)
			(b as Node3D).look_at((b as Node3D).global_position + fwd, Vector3.UP)
		var l = st.get("light")
		if l != null and is_instance_valid(l):
			(l as OmniLight3D).global_position = h.global_position + Vector3(0, 1.6, 0) + fwd * 0.9
			(l as OmniLight3D).light_energy = 1.8 * (0.85 + 0.15 * sin(h.anim_time * 27.0))

## A hoofstrike: his burning hoofprint, a puff of simulated ash and dust, clods, a few sparks.
static func _hoofstrike(h: Hero, root: Node3D, world, n: int) -> void:
	var side := h.facing().cross(Vector3.UP).normalized()
	var p := h.global_position + side * (0.22 if n % 2 == 0 else -0.22) - h.facing() * 0.3
	p.y = world.height_at(p.x, p.z)
	DemonKitFx.smoke(root, p, "ash", 0.85, 0.9, false, Color(1, 1, 1, 0.85))
	DemonKitFx.clods(root, p + Vector3(0, 0.08, 0), 4, 2.2, -h.facing() + Vector3.UP)
	# his cloven hoofprint burned into the ground (a Meshy painting), the heat in it dying over a few seconds
	var f := h.facing()
	DemonKitFx.decal(root, p, "hoof", Vector2(0.55, 0.55), atan2(-f.x, -f.z), 3.2, 2.4)
	if n % 2 == 0:
		DemonKitFx.sparks(root, p + Vector3(0, 0.05, 0), -h.facing() + Vector3(0, 0.6, 0), 4, 35.0, Vector2(2.0, 5.0), 0.3)
