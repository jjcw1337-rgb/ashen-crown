class_name ThunderDiveFx
extends RefCounted
## Thunder Dive's look (ThunderDive): up on its beating wings ("start": the flight pose, the rig's "fly" meta, its
## height kept by `update` in Hero.fxs "drg_dive"), down in a strike of the Blender-rendered lightning, the ground
## cracked and scorched, each foe struck crackling ("land"). Draws only.

const DIVE_H := 7.0               # metres up at the top of the dive

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var game = h.game
	match str(ev["e"]):
		"start":
			h.fxs["drg_dive"] = {"t": 0.0, "dur": float(ev.get("x", 1.0))}
			DragonFlight.gust(h, 1.3)
			ArcFx.charge(h, DragonKit.jaws(h), WyvernFx.ARC, 0.35)
		"land":
			_end(h)
			var p: Vector3 = ev["p"]
			var r: float = float(ev.get("r", 4.0))
			ArcFx.bolt(root, p + Vector3(randf_range(-1, 1), 16.0, randf_range(-1, 1)), p + Vector3(0, 0.2, 0), 0.35, 1.6, WyvernFx.ARC, game)
			ElementalFx.ground_slam(game, root, p, r)
			ArcFx._scorch(root, p, r * 0.55)
			for e in ev.get("t", []):
				if is_instance_valid(e):
					ArcFx._struck(h, root, (e as Node3D).global_position + Vector3(0, 1.0, 0), WyvernFx.ARC)
			ArcFx._flash(root, p + Vector3(0, 1.5, 0), WyvernFx.ARC[1], 6.0, 0.3, r * 2.5)
			DragonFlight.gust(h, 1.8)
			SkillFx.snd(h, "thunder_blast", 0.0, 1.0)
			SkillFx.shake(h, 0.45)
			SkillFx.hitstop(h, 0.06)
		_:
			return false
	return true

## Every frame (caster and everyone else's copy): up fast, a hang at the top, then a steep drop onto them (it lands on
## the dive's impact frame).
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("drg_dive"):
		return
	var dv: Dictionary = h.fxs["drg_dive"]
	dv["t"] = float(dv["t"]) + delta
	var a := clampf(float(dv["t"]) / maxf(float(dv["dur"]), 0.01), 0.0, 1.0)
	var f := clampf((a - ThunderDive.TAKEOFF) / (Anim.impact_at("dive") - ThunderDive.TAKEOFF), 0.0, 1.0)
	if a >= 1.0 or h.rig == null:
		_end(h)
		return
	var up := sin(PI * pow(f, 0.7)) if f < 1.0 else 0.0
	h.rig.position.y = DIVE_H * up
	h.rig.rotation.x = 0.35 * smoothstep(0.55, 0.95, f) - 0.2 * (1.0 - smoothstep(0.0, 0.4, f)) * float(f > 0.0)
	h.rig.set_meta("fly", f)

static func clear(h: Hero) -> void:
	_end(h)

## Down on its feet.
static func _end(h: Hero) -> void:
	if not h.fxs.has("drg_dive"):
		return
	h.fxs.erase("drg_dive")
	if h.rig != null:
		h.rig.position = Vector3.ZERO
		h.rig.rotation.x = 0.0
		if h.rig.has_meta("fly"):
			h.rig.remove_meta("fly")
