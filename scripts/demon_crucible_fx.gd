class_name DemonCrucibleFx
extends RefCounted
## Wrath of the Pit's look, "Crucible" (the Demon's V; the gameplay is DemonSkills). Volcanic glass, not hellfire:
## nothing here is Molten Fists'.
##
##  The Crucible ("crucible" {x: its longest}): he drops to a knee, folds his wings round him (the rig) and his skin
##  crusts over (the body shader's `cool`), while a cage of black obsidian crystals (the Meshy cocoon) grows up out
##  of the ground round him with a grinding crack, the earth under it crushed in, dust rolling out (simulated ash).
##  Every blow he takes ("heat" {x: 0..1 of what he can store}) chips glass off the crystals in a spray of sparks and
##  drives the heat up: the molten veins in the crystals glow brighter, the ground under him glows, the light grows;
##  the brighter it burns, the worse the eruption (opponents can read it).
##  The eruption ("erupt" {p, x: Pit-born's length, r: the heat 0..1, t: the foes struck}): the cage bursts outward in
##  its real pieces (the cocoon cut into Voronoi shards in Blender, their broken faces molten), a ring of fire and
##  smoke blasts out (the blast sim), a shock ring of bending air, a white flash, a scorched crater under him, and
##  then he burns white-hot through Pit-born (DemonFx's wrath state).
## State: h.fxs["crucible"], kept by `update` (times itself out on a partner's game).

const SCALE_XZ := 0.62
const SCALE_Y := 1.0

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
	_end(h)
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at := h.global_position
	at.y = world.height_at(at.x, at.z)
	var cage := Node3D.new()
	root.add_child(cage)
	cage.global_position = at
	var m := DemonKitFx.model(DemonKitFx.COCOON)
	if m != null:
		DemonKitFx.heat_model(m, 0.6, Color(1.0, 0.3, 0.05))
		cage.add_child(m)
	cage.scale = Vector3(SCALE_XZ, 0.02, SCALE_XZ)
	var tw := cage.create_tween()
	tw.tween_property(cage, "scale", Vector3(SCALE_XZ, SCALE_Y * 1.06, SCALE_XZ), 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(cage, "scale", Vector3(SCALE_XZ, SCALE_Y, SCALE_XZ), 0.12)
	var mark := DemonKitFx.decal(root, at, "crush", Vector2(3.4, 3.4), randf() * TAU, float(ev.get("x", DemonSkills.CRUCIBLE_MAX)) + 3.0, 0.3)
	DemonKitFx.smoke(root, at, "ash", 2.6, 1.2)
	DemonKitFx.clods(root, at + Vector3(0, 0.2, 0), [8, 12, 16, 20][tr], 3.0)
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 0.18, 0.05)
	l.light_energy = 0.6
	l.omni_range = 4.0
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = at + Vector3(0, 1.0, 0)
	h.fxs["crucible"] = {"cage": cage, "mark": mark, "light": l, "t": 0.0, "heat": 0.0, "shown": 0.0,
		"until": float(ev.get("x", DemonSkills.CRUCIBLE_MAX)) + 1.5, "crust": 0.0, "snd": 0.0, "stage": "hold"}
	SkillFx.snd(h, "ice_shatter", -6.0, 0.45)
	SkillFx.snd(h, "impact_bone", -6.0, 0.4)
	SkillFx.snd(h, "growl", -7.0, 0.6)

static func _heat(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("crucible", {})
	if st.is_empty():
		return
	st["heat"] = clampf(float(ev.get("x", 0.0)), 0.0, 1.0)
	var root: Node3D = h.game.world.fx_root
	# the blow glances off the glass: sparks and a chip
	var c := h.global_position + Vector3(randf_range(-0.7, 0.7), randf_range(0.6, 1.8), randf_range(-0.7, 0.7))
	DemonKitFx.sparks(root, c, Vector3.UP, 7, 80.0, Vector2(2.0, 5.0), 0.35)
	if float(st["snd"]) <= 0.0:
		st["snd"] = 0.18
		Sfx.play_at("ice_shatter", h.global_position, -14.0, 0.8 + float(st["heat"]) * 0.3)
		Sfx.play_at("impact_metal", h.global_position, -14.0, 0.55)

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
	var cage = st.get("cage")
	if cage != null and is_instance_valid(cage):
		(cage as Node).queue_free()
	st.erase("cage")
	# the cage bursting outward in its real shards
	var n := DemonKitFx.pieces(root, world, at + Vector3(0, 1.0, 0), DemonKitFx.COCOON_PIECES, SCALE_XZ, 10.0 + 4.0 * heat, 3.0 + 2.0 * heat, 2.4, 0.5, Vector3.ZERO, tr >= 2)
	if n == 0:
		DemonKitFx.sparks(root, at + Vector3(0, 1.0, 0), Vector3.UP, 30, 180.0)
	# the ring of fire and smoke blown out, the shock, the flash, the crater
	DemonKitFx.smoke(root, at, "blast", r * 1.7 + heat * 1.6, 1.7)
	DemonKitFx.shock_ring(root, h.game, at, r * 1.15, 0.38)
	DemonKitFx.flash_light(root, at + Vector3(0, 1.5, 0), Color(1.0, 0.8, 0.6), 6.0 + 4.0 * heat, r * 2.0, 0.6)
	DemonKitFx.decal(root, at, "crater", Vector2(r * 1.3, r * 1.3), randf() * TAU, 6.0, 2.0 + 2.0 * heat)
	DemonKitFx.sparks(root, at + Vector3(0, 1.0, 0), Vector3.UP, [16, 24, 34, 44][tr], 180.0, Vector2(6.0, 14.0), 0.6)
	DemonKitFx.clods(root, at + Vector3(0, 0.3, 0), [16, 24, 32, 40][tr], 7.0)
	for e in ev.get("t", []):
		if is_instance_valid(e):
			DemonKitFx.sparks(root, DemonKitFx.chest(e), Vector3.UP, 6, 60.0, Vector2(2.0, 5.0), 0.35)
	_drop_hold(st)
	SkillFx.snd(h, "roar", 0.0, 0.72)
	SkillFx.snd(h, "ice_shatter", -2.0, 0.55)
	SkillFx.snd(h, "boom", -4.0, 0.65)
	SkillFx.duck(h, -9.0, 1.2)
	SkillFx.shake(h, 0.55 + 0.2 * heat)
	SkillFx.hitstop(h, 0.06)

static func _drop_hold(st: Dictionary) -> void:
	var cage = st.get("cage")
	if cage != null and is_instance_valid(cage):
		(cage as Node).queue_free()
	st.erase("cage")
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		var tw := (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.4)
		tw.tween_callback((l as Node).queue_free)
	st.erase("light")

static func _end(h: Hero) -> void:
	if not h.fxs.has("crucible"):
		return
	var st: Dictionary = h.fxs["crucible"]
	h.fxs.erase("crucible")
	var cage = st.get("cage")
	if cage != null and is_instance_valid(cage):
		# let go without a burst (cut short): the crystals sink back into the ground
		var tw := (cage as Node3D).create_tween()
		tw.tween_property(cage, "scale", Vector3(SCALE_XZ, 0.02, SCALE_XZ), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback((cage as Node).queue_free)
		st.erase("cage")
	_drop_hold(st)
	if h.rig != null and is_instance_valid(h.rig):
		h.rig.set_meta("crust", 0.0)
		if not h.fxs.has("wrath") and h.rig.has_meta("demon_mats"):
			for m in h.rig.get_meta("demon_mats"):
				(m as ShaderMaterial).set_shader_parameter("wrath", 0.0)

## Every frame: the crust spreads on him, the crystals' veins and the ground glow with the heat he stores.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("crucible"):
		return
	var st: Dictionary = h.fxs["crucible"]
	st["t"] = float(st["t"]) + delta
	st["until"] = float(st["until"]) - delta
	st["snd"] = maxf(0.0, float(st["snd"]) - delta)
	var holding := str(st["stage"]) == "hold"
	if float(st["until"]) <= 0.0 or (holding and not h.puppet and not DemonSkills.in_crucible(h) and float(st["t"]) > 0.3 and str(SkillFx.style(h)) != "crucible"):
		_end(h)
		return
	var crust: float = float(st["crust"])
	crust = minf(crust + delta * 3.0, 0.82) if holding else maxf(crust - delta * 9.0, 0.0)
	st["crust"] = crust
	if h.rig != null and is_instance_valid(h.rig):
		h.rig.set_meta("crust", crust)
	var shown: float = lerpf(float(st["shown"]), float(st["heat"]), clampf(delta * 8.0, 0.0, 1.0))
	st["shown"] = shown
	if holding:
		var flick := 0.85 + 0.15 * sin(h.anim_time * 17.0)
		var cage = st.get("cage")
		if cage != null and is_instance_valid(cage):
			DemonKitFx.set_heat(cage, (0.6 + 4.0 * shown) * flick)
		var mark = st.get("mark")
		if mark != null and is_instance_valid(mark):
			DemonKitFx.set_mark_glow(mark, (0.3 + 3.0 * shown) * flick)
		if h.rig != null and h.rig.has_meta("demon_mats"):
			for m in h.rig.get_meta("demon_mats"):
				(m as ShaderMaterial).set_shader_parameter("wrath", 0.1 + 0.6 * shown)
		var l = st.get("light")
		if l != null and is_instance_valid(l):
			(l as OmniLight3D).light_energy = (0.6 + 3.0 * shown) * flick

static func clear(h: Hero) -> void:
	_end(h)
