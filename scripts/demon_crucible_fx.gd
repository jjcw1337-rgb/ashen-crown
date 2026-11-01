class_name DemonCrucibleFx
extends RefCounted
## Wrath of the Pit's look, "Crucible" (the Demon's V; the gameplay is DemonSkills).
##
##  The Crucible ("crucible" {x: its longest}): he drops to a knee and folds his wings round him (the rig), his
##  skin crusts over into black obsidian (the body shader's `cool`), the cracked ground round him darkens in a ring,
##  the air over him trembles (heat haze from High) and embers are sucked in toward him. Every blow he takes
##  ("heat" {x: 0..1 of what he can store}) drives the heat up: the seams in the crust glow brighter (the shader's
##  `wrath`), the ring under him heats, the light grows. Opponents can read it: the brighter he burns, the worse
##  the eruption.
##  The eruption ("erupt" {p, x: Pit-born's length, r: the heat 0..1, t: the foes struck}): the crust bursts off him
##  in a hail of obsidian, his wings fly open, a column of fire roars up, a ring of cracks tears out to ROAR_R with
##  a shock ring of bending air, smoke rolls out, and he burns white-hot through Pit-born (DemonFx's wrath state).
## State: h.fxs["crucible"], kept by `update` (times itself out on a partner's game).

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"crucible":
			_begin(h, ev)
		"heat":
			_heat(h, ev)
		"erupt":
			_erupt(h, ev)
		"cast":
			pass
		_:
			return false
	return true

static func _begin(h: Hero, ev: Dictionary) -> void:
	_end(h, false)
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at := h.global_position
	at.y = world.height_at(at.x, at.z)
	var rm := InfernalFx.rift_mat()
	var ring := MeshInstance3D.new()
	ring.mesh = InfernalFx.disc_mesh(world, at, 2.0, 32, 5, 0.04)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = at
	rm.set_shader_parameter("front", 0.0)
	rm.set_shader_parameter("heat", 0.15)
	InfernalFx.tween_param(ring, rm, "front", 0.0, 1.05, 0.35)
	var pull := InfernalFx.particles(root, at + Vector3(0, 1.2, 0), {"amount": [10, 18, 26, 34][tr], "life": 0.6, "one_shot": false,
		"shape": "sphere", "r": 2.0, "dir": Vector3.UP, "spread": 180.0, "vel": [0.0, 0.2], "radial": [-5.0, -3.0],
		"scale": [0.4, 1.0], "size": 0.05,
		"colors": [[0.0, Color(InfernalFx.CRIMSON, 0.0)], [0.4, InfernalFx.BLOODFIRE], [1.0, InfernalFx.MOLTEN]]})
	var dome: MeshInstance3D = null
	if InfernalFx.haze_ok(h.game):
		dome = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.3
		sm.height = 2.6
		sm.radial_segments = 24
		sm.rings = 12
		dome.mesh = sm
		dome.material_override = InfernalFx.haze_mat(0.02, false)
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dome)
		dome.global_position = at + Vector3(0, 1.1, 0)
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.CRIMSON
	l.light_energy = 0.6
	l.omni_range = 4.0
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = at + Vector3(0, 1.0, 0)
	h.fxs["crucible"] = {"ring": ring, "ring_mat": rm, "pull": pull, "dome": dome, "light": l, "t": 0.0, "heat": 0.0, "shown": 0.0,
		"until": float(ev.get("x", DemonSkills.CRUCIBLE_MAX)) + 1.5, "crust": 0.0, "snd": 0.0, "stage": "hold"}
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.22, 0.17, 0.14, 0.7), [6, 9, 12, 14][tr], 1.8, 0.3, 0.6, false, -3.0, 70.0, Vector3.UP)
	SkillFx.snd(h, "impact_bone", -6.0, 0.45)
	SkillFx.snd(h, "phase_in", -8.0, 0.6)
	SkillFx.snd(h, "growl", -6.0, 0.6)

static func _heat(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("crucible", {})
	if st.is_empty():
		return
	st["heat"] = clampf(float(ev.get("x", 0.0)), 0.0, 1.0)
	var root: Node3D = h.game.world.fx_root
	# the blow glances off the crust: sparks and a chip of obsidian
	var c := h.global_position + Vector3(randf_range(-0.4, 0.4), randf_range(0.8, 1.8), randf_range(-0.4, 0.4))
	InfernalFx.particles(root, c, {"amount": 8, "life": 0.3, "explosive": 1.0, "dir": Vector3.UP, "spread": 80.0, "vel": [2.0, 4.5],
		"gravity": -9.0, "scale": [0.5, 1.0], "size": 0.05,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.4, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	if float(st["snd"]) <= 0.0:
		st["snd"] = 0.18
		Sfx.play_at("impact_metal", h.global_position, -12.0, 0.6)
		Sfx.play_at("fire_erupt", h.global_position, -16.0, 1.2 + float(st["heat"]) * 0.5)

static func _erupt(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at: Vector3 = ev.get("p", h.global_position)
	at.y = world.height_at(at.x, at.z)
	var heat := clampf(float(ev.get("r", 0.0)), 0.0, 1.0)
	var r := DemonSkills.ROAR_R
	var st: Dictionary = h.fxs.get("crucible", {"heat": heat, "shown": heat, "crust": 0.8, "snd": 0.0})
	st["stage"] = "burst"
	st["t"] = 0.0
	st["until"] = 1.0
	h.fxs["crucible"] = st
	var p = st.get("pull")
	if p != null and is_instance_valid(p):
		(p as GPUParticles3D).emitting = false
	# the crust bursting off him
	DemonKitFx.debris(root, at + Vector3(0, 1.2, 0), [6, 10, 14, 18][tr], Vector3.ZERO, 6.0, 0.12)
	DemonKitFx.debris(root, at + Vector3(0, 0.5, 0), [3, 5, 7, 9][tr], Vector3.ZERO, 4.0, 0.18)
	# the white core and the bloom
	var gm := InfernalFx.glow_mat(InfernalFx.WHITEHOT, 2.6, 2.4, 0.7)
	var g := InfernalFx.glow(root, at + Vector3(0, 1.3, 0), 1.0, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * (3.5 + 3.0 * heat), 0.22).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.3)
	Fx._free_later(g, 0.35)
	var bm := InfernalFx.glow_mat(InfernalFx.BLOODFIRE, 1.6, 1.4)
	var bl := InfernalFx.glow(root, at + Vector3(0, 1.0, 0), 2.0, bm)
	bl.create_tween().tween_property(bl, "scale", Vector3.ONE * r * 2.0, 0.4).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(bl, bm, "alpha", 0.55, 0.0, 0.45)
	Fx._free_later(bl, 0.5)
	DemonKitFx.flash_light(root, at + Vector3(0, 1.5, 0), InfernalFx.WHITEHOT, 6.0 + 4.0 * heat, r * 2.0, 0.6)
	# a column of fire roaring up out of him
	var col := InfernalFx.fire(root, at, 3.0 + 1.2 * heat, 80.0, tr, true, true)
	var twc := col.create_tween()
	twc.tween_interval(0.55)
	twc.tween_callback(func(): InfernalFx.fire_on(col, false))
	twc.tween_interval(1.4)
	twc.tween_callback(col.queue_free)
	# the ring of cracks tearing out, and the air bending with it
	var rm := InfernalFx.rift_mat()
	rm.set_shader_parameter("span", 1.6)
	var rift := MeshInstance3D.new()
	rift.mesh = InfernalFx.disc_mesh(world, at, r, 48, 8, 0.045)
	rift.material_override = rm
	rift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rift)
	rift.global_position = at
	InfernalFx.tween_param(rift, rm, "front", 0.0, 1.05, 0.22).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(rift, rm, "heat", 1.4, 0.0, 1.6, 0.2)
	InfernalFx.tween_param(rift, rm, "life", 1.0, 0.0, 1.2, 1.8)
	Fx._free_later(rift, 3.2)
	DemonKitFx.shock_ring(root, h.game, at, r * 1.15, 0.38)
	Fx.ring(root, at + Vector3(0, 0.05, 0), r, InfernalFx.BLOODFIRE, 0.45, 0.35)
	# fires bursting out of the cracks round him
	for i in [4, 6, 8, 10][tr]:
		var ang: float = TAU * float(i) / [4, 6, 8, 10][tr] + randf_range(-0.2, 0.2)
		var fp := at + Vector3(cos(ang), 0, sin(ang)) * randf_range(r * 0.35, r * 0.85)
		fp.y = world.height_at(fp.x, fp.z)
		DemonKitFx.flare_fire(root, fp, randf_range(1.0, 1.6), randf_range(0.05, 0.18), 0.45, tr, i % 2 == 0)
	InfernalFx.smoke(root, at + Vector3(0, 0.5, 0), [5, 8, 12, 15][tr], Vector3(r * 0.4, 0.2, r * 0.4), Vector3.UP, 2.0, 2.4, 1.3, 0.8)
	DemonKitFx.embers(root, at + Vector3(0, 1.0, 0), [24, 40, 60, 80][tr], 180.0, Vector2(3.0, 8.0))
	for e in ev.get("t", []):
		if is_instance_valid(e):
			DemonFx.ignite(root, e)
	_drop_hold(st)
	SkillFx.snd(h, "roar", 0.0, 0.72)
	SkillFx.snd(h, "phase_erupt", -3.0, 0.75)
	SkillFx.snd(h, "boom", -5.0, 0.7)
	SkillFx.duck(h, -9.0, 1.2)
	SkillFx.shake(h, 0.55 + 0.2 * heat)
	SkillFx.hitstop(h, 0.06)

static func _drop_hold(st: Dictionary) -> void:
	for key in ["dome", "pull"]:
		var n = st.get(key)
		if n != null and is_instance_valid(n):
			if n is GPUParticles3D:
				(n as GPUParticles3D).emitting = false
				Fx._free_later(n, 0.8)
			else:
				(n as Node).queue_free()
		st.erase(key)
	var ring = st.get("ring")
	if ring != null and is_instance_valid(ring):
		InfernalFx.tween_param(ring, st["ring_mat"], "life", 1.0, 0.0, 0.5)
		Fx._free_later(ring, 0.6)
	st.erase("ring")
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		var tw := (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.4)
		tw.tween_callback((l as Node).queue_free)
	st.erase("light")

static func _end(h: Hero, _burst: bool) -> void:
	if not h.fxs.has("crucible"):
		return
	var st: Dictionary = h.fxs["crucible"]
	h.fxs.erase("crucible")
	_drop_hold(st)
	if h.rig != null and is_instance_valid(h.rig):
		h.rig.set_meta("crust", 0.0)
		if not h.fxs.has("wrath") and h.rig.has_meta("demon_mats"):
			for m in h.rig.get_meta("demon_mats"):
				(m as ShaderMaterial).set_shader_parameter("wrath", 0.0)

## Every frame: the crust spreads, the heat climbs, then (after the burst) the crust is gone.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("crucible"):
		return
	var st: Dictionary = h.fxs["crucible"]
	st["t"] = float(st["t"]) + delta
	st["until"] = float(st["until"]) - delta
	st["snd"] = maxf(0.0, float(st["snd"]) - delta)
	var holding := str(st["stage"]) == "hold"
	if float(st["until"]) <= 0.0 or (holding and not h.puppet and not DemonSkills.in_crucible(h) and float(st["t"]) > 0.3 and str(SkillFx.style(h)) != "crucible"):
		_end(h, false)
		return
	var crust: float = float(st["crust"])
	if holding:
		crust = minf(crust + delta * 3.0, 0.82)
	else:
		crust = maxf(crust - delta * 9.0, 0.0)
	st["crust"] = crust
	if h.rig != null and is_instance_valid(h.rig):
		h.rig.set_meta("crust", crust)
	var shown: float = lerpf(float(st["shown"]), float(st["heat"]), clampf(delta * 8.0, 0.0, 1.0))
	st["shown"] = shown
	if holding:
		# the seams glowing through the crust (the white heat the wrath's state also drives)
		if h.rig != null and h.rig.has_meta("demon_mats"):
			for m in h.rig.get_meta("demon_mats"):
				(m as ShaderMaterial).set_shader_parameter("wrath", 0.15 + 0.75 * shown + 0.08 * sin(h.anim_time * 17.0))
		var ring = st.get("ring")
		if ring != null and is_instance_valid(ring):
			(st["ring_mat"] as ShaderMaterial).set_shader_parameter("heat", 0.15 + 0.85 * shown)
		var l = st.get("light")
		if l != null and is_instance_valid(l):
			(l as OmniLight3D).light_energy = (0.6 + 3.0 * shown) * (0.85 + 0.15 * sin(h.anim_time * 23.0))
			(l as OmniLight3D).light_color = InfernalFx.CRIMSON.lerp(InfernalFx.MOLTEN, shown)

static func clear(h: Hero) -> void:
	_end(h, false)
