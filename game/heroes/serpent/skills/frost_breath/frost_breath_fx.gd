class_name FrostBreathFx
extends RefCounted
## Frost Breath's look (FrostBreath; jj, 2026-11-04). From its cast's own event ("cast"), on the serpent's own game and
## everyone else's copy of it, then `update` for the breath's use: a freezing gale out of its jaws along the way its
## head points (noise-eroded cold mist billowing out and widening, ice crystals glittering in it, frost needles spat out
## fast), a cold light riding it; the ground frosts over along the cone (FrostVolleyFx's hoarfrost); ice crystal
## clusters burst up where the gale ends, and shatter a while later; foes in it frost over. Draws only.

const ID := "frost_breath"

## The breath's length (its use) and reach (its range), from its data.
static func _secs() -> float:
	return float(Data.skill_def(ID).get("use", 1.4))

static func _reach() -> float:
	return float(Data.skill_def(ID).get("range", 7.0))

## Where the breath leaves its jaws, and the way its head points (flat-ish).
static func _jaws(h: Hero) -> Array:
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	var hd = J.get("head")
	var at: Vector3 = h.global_position + Vector3(0, 1.6, 0) + h.facing() * 1.6
	var d: Vector3 = h.facing()
	if hd is Node3D and is_instance_valid(hd):
		var hn := hd as Node3D
		at = hn.global_position + h.facing() * 0.55 + Vector3(0, -0.1, 0)
	return [at, d]

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"cast":
			_start(h)
		_:
			return false
	return true

static func _start(h: Hero) -> void:
	clear(h)
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var jd := _jaws(h)
	var at: Vector3 = jd[0]
	var d: Vector3 = jd[1]
	# the gale: billowing mist, glittering crystals, needles of frost, all shed into the world from the jaws
	var mist := ElementalFx._dust(root, at, FrostFx.MIST, 0.9, 0.42, {"one_shot": false, "amount": [10, 16, 24, 34][tr],
		"life": 0.75, "explosive": 0.0, "shape": "sphere", "r": 0.12, "dir": d, "spread": 16.0, "vel": [7.0, 10.0],
		"damping": [6.0, 9.0], "gravity": -0.6, "scale": [0.7, 1.2], "grow": [0.35, 3.2]})
	var glit := InfernalFx.particles(root, at, {"one_shot": false, "amount": [12, 20, 30, 44][tr], "life": 0.7,
		"explosive": 0.0, "shape": "sphere", "r": 0.1, "dir": d, "spread": 20.0, "vel": [6.0, 11.0], "damping": [4.0, 7.0],
		"gravity": -1.5, "scale": [0.4, 1.0], "size": 0.022,
		"colors": [[0.0, Color(1.3, 1.4, 1.5)], [0.6, FrostFx.PALE], [1.0, Color(FrostFx.DEEP, 0.0)]]})
	var needles := InfernalFx.particles(root, at, {"one_shot": false, "amount": [6, 10, 14, 20][tr], "life": 0.45,
		"explosive": 0.0, "shape": "sphere", "r": 0.08, "dir": d, "spread": 10.0, "vel": [12.0, 16.0], "gravity": -4.0,
		"scale": [0.5, 1.0], "size": 0.03, "colors": [[0.0, Color(1.2, 1.3, 1.4)], [1.0, Color(FrostFx.PALE, 0.0)]]})
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.6, 0.82, 1.0)
	lt.light_energy = 0.0
	lt.omni_range = 7.0
	lt.shadow_enabled = false
	root.add_child(lt)
	h.fxs["breath"] = {"t": 0.0, "mist": mist, "glit": glit, "needles": needles, "light": lt, "frost": false, "ice": false}
	SkillFx.snd(h, "frost_breath", -2.0, randf_range(0.95, 1.03))
	SkillFx.shake(h, 0.06)

static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("breath"):
		return
	var b: Dictionary = h.fxs["breath"]
	b["t"] = float(b["t"]) + delta
	var t: float = b["t"]
	var secs := _secs()
	var reach := _reach()
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var jd := _jaws(h)
	var at: Vector3 = jd[0]
	var d: Vector3 = jd[1]
	var on: bool = t > 0.18 and t < secs - 0.12
	for k in ["mist", "glit", "needles"]:
		var p = b[k]
		if is_instance_valid(p):
			(p as GPUParticles3D).global_position = at
			(p as GPUParticles3D).emitting = on
			var pm := (p as GPUParticles3D).process_material as ParticleProcessMaterial
			pm.direction = d
	var lt = b["light"]
	if is_instance_valid(lt):
		(lt as OmniLight3D).global_position = at + d * 2.5
		(lt as OmniLight3D).light_energy = (1.6 if on else 0.0) * randf_range(0.85, 1.0)
	# the ground frosting over along the cone, once the gale reaches it
	if not bool(b["frost"]) and t > 0.4:
		b["frost"] = true
		var w = h.game.world
		var g: Vector3 = h.global_position
		for i in 3:
			var c: Vector3 = g + d * (2.2 + i * 2.0)
			c.y = w.height_at(c.x, c.z)
			_frost_patch(h, root, c, 1.1 + i * 0.55)
	# ice bursting up where it ends
	if not bool(b["ice"]) and t > 0.65:
		b["ice"] = true
		var g2: Vector3 = h.global_position + d * reach * 0.85
		var crystals: Array = []
		for i in [2, 3, 4, 5][tr]:
			var off := d.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * randf_range(-1.2, 1.2) + d.cross(Vector3.UP) * randf_range(-1.8, 1.8)
			var p: Vector3 = g2 + off
			p.y = h.game.world.height_at(p.x, p.z)
			var cn := FrostFx.crystal(root, p, randf_range(0.5, 0.95), tr)
			if cn != null:
				crystals.append(cn)
		Sfx.play_at("ice_arrow_hit", g2, -4.0, 0.85)
		var wld = h.game.world
		Fx.later(root, 2.6, func():        # (skipped once the zone's fx_root is gone; captures no hero)
			for cn in crystals:
				if is_instance_valid(cn):
					FrostFx.smash(root, wld, cn, tr)
			Sfx.play_at("ice_shatter", g2, -5.0, 1.0))
	# foes in the gale frost over
	if on and fmod(t, 0.25) < delta:
		for e in h.game.enemies_near(h.global_position + d * reach * 0.5, reach * 0.6):
			if not e.dead and (e.global_position - h.global_position).normalized().dot(d) > 0.55:
				FrostFx.frost_body(h.game, e, 2.0)
	if t > secs:
		_end(b)
		h.fxs.erase("breath")

## The gale stops: its particles let go and fade, its light goes out.
static func _end(b: Dictionary) -> void:
	for k in ["mist", "glit", "needles"]:
		var p = b[k]
		if is_instance_valid(p):
			(p as GPUParticles3D).emitting = false
			Fx._free_later(p as Node, 1.2)
	if is_instance_valid(b["light"]):
		(b["light"] as Node).queue_free()

## A breath still blowing is let go (a class change, a zone change, a new breath).
static func clear(h: Hero) -> void:
	if h.fxs.has("breath"):
		_end(h.fxs["breath"])
		h.fxs.erase("breath")

## A patch of hoarfrost on the ground (FrostVolleyFx's ground shader): it spreads, holds, then thaws.
static func _frost_patch(h: Hero, root: Node3D, c: Vector3, r: float) -> void:
	var gm := FrostFx.mat("ground")
	gm.set_shader_parameter("hoar", FrostFx.hoarfrost())
	gm.set_shader_parameter("noise_tex", InfernalFx.noise())
	gm.set_shader_parameter("pale", FrostFx.PALE)
	gm.set_shader_parameter("deep", FrostFx.DEEP)
	gm.set_shader_parameter("seed", randf() * 10.0)
	gm.set_shader_parameter("tile", maxf(1.0, r * 0.55))
	var mi := ElementalFx._piece(root, InfernalFx.disc_mesh(h.game.world, c, r, 32, 5, 0.06), gm, c, 6.0)
	InfernalFx.tween_param(mi, gm, "front", 0.0, 1.0, 0.35).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(mi, gm, "thaw", 0.0, 1.0, 2.5, 3.0)
