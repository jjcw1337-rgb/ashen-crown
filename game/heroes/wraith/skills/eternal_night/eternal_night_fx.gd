class_name EternalNightFx
extends RefCounted
## Eternal Night's look on every game (EternalNight is its rules). Draws only:
##  "cast": the night (h.fxs["night"]: the dark floor, the souls, his rise and glow, and for the caster the screen's
##    edges darkening; a partner sees a fainter darkening when he stands near it), brought down and lifted with the
##    stages' progress by `update`; "rise"; "scream" (the four ghosts wheeling round him for the rest of it);
##    "tick" (the dark feeding); "fall" (the collapse); "end" {x: finished}.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE
const NIGHT := SpiritFx.NIGHT
const HOVER := 1.0          # how high he rises for the night (on top of WraithBody.HOVER)
const PARTNER := 0.45       # how much of the night's darkening a partner standing in it gets

static func _radius() -> float:
	return Skill.num("night", "radius", 9.0)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match str(ev["e"]):
		"cast":
			_end(h, false)
			var grade: ShaderMaterial = null
			if not h.puppet and h.game.get("vignette") != null:
				grade = h.game.vignette.material
			h.fxs["night"] = {"node": night(root, pos, _radius() * 0.8, grade), "ghosts": [], "k": 0.0, "vig": 0.0}
			_set_hover(h, HOVER)
			SkillFx.snd(h, "host_summon", -4.0, 0.8)
			SkillFx.duck(h, -6.0, 1.5)
		"rise":
			Fx.flash(root, pos + Vector3(0, 2.0, 0), VIOLET, 3.0, 0.6, 9.0)
		"scream":
			scream(root, pos, _radius())
			SkillFx.snd(h, "wail", 0.0, 0.9)
			SkillFx.duck(h, -8.0, 1.0)
			SkillFx.shake(h, 0.5)
			SkillFx.hitstop(h, 0.06)
			if h.fxs.has("night"):
				# four phantoms wheel round him for the rest of the night
				for i in 4:
					var g := SpiritFx.afterimage(h.rig, root, VIOLET, 20.0, 0.25)
					if g != null:
						g.set_meta("phase", TAU * i / 4.0)
						(h.fxs["night"]["ghosts"] as Array).append(g)
		"tick":
			SpiritFx.burst(root, pos + Vector3(0, 1.2, 0), VIOLET, 10, 6.0, 0.1, 0.4, true, 0.0, 180.0)
		"fall":
			collapse(root, pos, Skill.num("night", "fall_r", 6.5))
			SkillFx.snd(h, "slam", -2.0, 0.8)
			SkillFx.snd(h, "phase_erupt", -4.0, 0.9)
			SkillFx.duck(h, -8.0, 1.0)
			SkillFx.shake(h, 0.6)
			SkillFx.hitstop(h, 0.08)
		"end":
			_end(h, bool(ev.get("x", false)))
		_:
			return false
	return true

static func _set_hover(h: Hero, extra: float) -> void:
	if h.rig != null and h._floats():
		h.rig.set("hover", WraithBody.HOVER + extra)

static func _set_glow(h: Hero, g: float) -> void:
	if h.rig != null and h.rig.has_meta("spectral_mats"):
		for m in h.rig.get_meta("spectral_mats"):
			(m as ShaderMaterial).set_shader_parameter("glow", g)
	if h.rig != null and h.rig.has_meta("eye_light"):
		var l := h.rig.get_meta("eye_light") as OmniLight3D
		if l != null:
			l.light_energy = 0.45 * g

## The night lifts: the dark fades up, the ghosts go, he comes down and dims.
static func _end(h: Hero, finished: bool) -> void:
	if not h.fxs.has("night"):
		return
	var n: Dictionary = h.fxs["night"]
	h.fxs.erase("night")
	_set_hover(h, 0.0)
	var node = n["node"]
	if node != null and is_instance_valid(node):
		var tw: Tween = node.create_tween()
		tw.tween_method(func(v: float): set_night(node, v), 1.0 if finished else 0.6, 0.0, 0.5 if finished else 0.3)
		tw.tween_callback(node.queue_free)
	_partner_night(h, 0.0)
	for g in n["ghosts"]:
		if is_instance_valid(g):
			(g as Node).queue_free()
	_set_glow(h, 1.0)

## A partner's night darkens this screen's edges a little when our own hero stands in it (never over our own).
static func _partner_night(h: Hero, want: float) -> void:
	if not h.puppet or h.game.get("vignette") == null:
		return
	var mine: Hero = h.game.hero
	if mine != null and mine.fxs.has("night"):
		return
	(h.game.vignette.material as ShaderMaterial).set_shader_parameter("night", want)

## Every frame (his own game and his puppet's): the dark comes down through the rise, he glows, the ghosts wheel,
## he sinks through the fall.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("night"):
		return
	var a := SkillFx.atk(h)
	var st := SkillFx.style(h)
	var n: Dictionary = h.fxs["night"]
	var node = n["node"]
	if node == null or not is_instance_valid(node):
		_end(h, false)
		return
	var k: float = float(n["k"])
	if st == "night_rise" and a >= 0.0:
		k = smoothstep(0.0, 0.85, a)
		_set_glow(h, 1.0 + a * 2.5)
	elif st in EternalNight.STAGES:
		k = 1.0
	elif h.puppet and a < 0.0:
		# a puppet between stages keeps its night; one whose night ended without the word loses it after a while
		n["idle"] = float(n.get("idle", 0.0)) + delta
		if float(n["idle"]) > 1.0:
			_end(h, false)
			return
	if st in EternalNight.STAGES:
		n["idle"] = 0.0
	n["k"] = k
	set_night(node, k)
	if st == "night_fall" and a > 0.2:
		_set_hover(h, HOVER * (1.0 - smoothstep(0.2, 0.5, a)))
	var c := h.global_position
	for g in n["ghosts"]:
		if not is_instance_valid(g):
			continue
		var ph: float = float(g.get_meta("phase")) + h.anim_time * 2.2
		var r := 3.2
		(g as Node3D).global_position = c + Vector3(cos(ph) * r, 0.25 + sin(ph * 2.0) * 0.3, sin(ph) * r)
		(g as Node3D).rotation = Vector3(-0.35, -ph + PI * 0.5, 0.0)
	if h.puppet:
		# a partner's night: our own screen darkens a little while we stand in it
		var mine: Hero = h.game.hero
		var d: float = mine.global_position.distance_to(c) if mine != null else 99.0
		_partner_night(h, k * PARTNER * (1.0 - smoothstep(_radius(), _radius() * 2.0, d)))

static func clear(h: Hero) -> void:
	_end(h, false)

# ---------------------------------------------------------------- Eternal Night
## The night: the screen's edges close in with violet dark (the vignette's "night", `grade`: the hero's own light
## stays in the middle, so the fight is readable), the dark floor under him with his runes turning, and souls
## drifting up out of the ground. `set_night(n, k)` brings it down (k 0..1) and lifts it again.
static func night(root: Node3D, pos: Vector3, radius: float, grade: ShaderMaterial = null) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	var floor_m := MeshInstance3D.new()
	floor_m.mesh = SpiritFx.disc_mesh()
	var fm := SpiritFx.floor_mat(VIOLET, 0.0)
	fm.set_shader_parameter("runes", 1.0)
	floor_m.material_override = fm
	floor_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_m.position.y = 0.05
	floor_m.scale = Vector3.ONE * radius * 0.6
	n.add_child(floor_m)
	# souls drifting up out of the ground under the night
	var souls := SpiritFx.trail(VIOLET.lerp(PALE, 0.4), 0.14, 60, 2.2)
	var pm := souls.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.7
	pm.emission_ring_inner_radius = 1.0
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	souls.amount_ratio = 0.0
	n.add_child(souls)
	n.set_meta("floor", fm)
	n.set_meta("souls", souls)
	if grade != null:
		n.set_meta("grade", grade)     # the caster's own screen darkens; a puppet's night has no grade
	return n

static func set_night(n: Node3D, k: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	(n.get_meta("floor") as ShaderMaterial).set_shader_parameter("amt", k)
	(n.get_meta("souls") as GPUParticles3D).amount_ratio = k
	if n.has_meta("grade"):
		var g := n.get_meta("grade") as ShaderMaterial
		if g != null:
			g.set_shader_parameter("night", k)

## The scream of the night: three rings of terror racing out, a burst of pale shrieking shapes.
static func scream(root: Node3D, pos: Vector3, radius: float) -> void:
	SpiritFx.ring(root, pos, radius, SPIRIT.darkened(0.3), 0.5, 0.3)
	Fx.later(root, 0.1, func(): SpiritFx.ring(root, pos, radius * 0.85, VIOLET, 0.55, 0.9))
	Fx.later(root, 0.2, func(): SpiritFx.ring(root, pos, radius * 1.05, SPIRIT.darkened(0.55), 0.5, 0.15))
	SpiritFx.burst(root, pos + Vector3(0, 1.5, 0), Color(0.75, 0.9, 1.0, 0.7), 34, 10.0, 0.22, 0.5, true, 0.0, 180.0)
	SpiritFx.burst(root, pos + Vector3(0, 0.5, 0), VIOLET, 40, 6.0, 0.12, 0.8, true, 1.5, 90.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cone(0.6, 2.6, 24)
	var m := Mats.glow_unique(SPIRIT, 2.0, 1.0, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 2.4, 0)
	mi.rotation = Vector3(PI, 0, 0)
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.6, 1.3, 1.6), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 0.9, 0.0, 0.45)
	SpiritFx.free_later(mi, 0.6)

## The night's collapse: the dark drawn into the slam and thrown out again as a wave of spirit-light.
static func collapse(root: Node3D, pos: Vector3, radius: float) -> void:
	SpiritFx.ring(root, pos, radius, VIOLET, 0.5, 0.3)
	SpiritFx.ring(root, pos, radius * 0.7, PALE, 0.35, 0.15)
	SpiritFx.burst(root, pos + Vector3(0, 0.3, 0), SPIRIT, 50, 8.0, 0.14, 0.7, true, 1.0, 80.0)
	SpiritFx.burst(root, pos + Vector3(0, 0.4, 0), Color(0.06, 0.03, 0.1, 0.9), 30, 4.0, 0.5, 0.9, false, 1.0, 90.0)
	Fx.flash(root, pos + Vector3(0, 1.2, 0), PALE, 5.0, 0.5, radius * 2.0)
