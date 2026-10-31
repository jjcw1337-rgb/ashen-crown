class_name KnightFx
extends RefCounted
## Visual effects for the knight's skills (SkillFx events; the gameplay is in Hero._impact / _update_charge).
##  Holy Slam: "slam" {p: where the blade lands, x: hit anything} (the leap itself is the pose)
##  Holy Nova: "impact"
##  Charge: "start" (the dash's dust runs in `update` for 0.5 s), "hit" {p, x: the first one}, "end"
##  Battle Cry: "impact"

const HOLY := Color(1.0, 0.85, 0.4)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match [str(ev["s"]), str(ev["e"])]:
		["cleave", "cast"], ["nova", "cast"], ["cry", "cast"]:
			pass    # their effects land on the impact frame
		["cleave", "slam"]:
			var at: Vector3 = ev["p"]
			for p in ev.get("ps", PackedVector3Array()):
				Fx.sparks(root, p, Color(1.0, 0.97, 0.9))
			Fx.holy_slam(root, at, 2.6)
			SkillFx.shake(h, 0.5 if bool(ev.get("x", false)) else 0.32)
			SkillFx.hitstop(h, 0.09 if bool(ev.get("x", false)) else 0.04)
		["nova", "impact"]:
			Fx.ring(root, pos, 7.0, Color(1.0, 0.75, 0.3), 0.5)
			Fx.burst(root, pos + Vector3(0, 1, 0), Color(1.0, 0.8, 0.4), 50, 9.0, 0.15, 0.6, true, 0.0, 180.0)
			SkillFx.shake(h, 0.35)
		["cry", "impact"]:
			Fx.ring(root, pos, 6.0, HOLY, 0.6)
			Fx.pillar(root, pos, Color(1.0, 0.8, 0.35), 0.8)
			SkillFx.snd(h, "battle_cry")
			SkillFx.duck(h, -8.0, 1.2)
			SkillFx.shake(h, 0.3)
		["charge", "cast"]:
			h.fxs["charge"] = 0.5
			SkillFx.snd(h, "charge_dash", -2.0)
		["charge", "hit"]:
			var p: Vector3 = ev["p"]
			if bool(ev.get("x", false)):
				Sfx.play_at("charge_impact", p, 0.0)
			Fx.sparks(root, p + Vector3(0, 1.0, 0))
		["charge", "end"]:
			h.fxs.erase("charge")
			Fx.ring(root, pos, 2.5, Color(0.9, 0.8, 0.6), 0.35)
			SkillFx.shake(h, 0.25)
		_:
			return false
	return true

## The dust the Charge kicks up, on the caster and on his puppet, for as long as the dash lasts.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("charge"):
		return
	var left: float = float(h.fxs["charge"]) - delta
	if left <= 0.0:
		h.fxs.erase("charge")
		return
	h.fxs["charge"] = left
	Fx.burst(h.game.world.fx_root, h.global_position + Vector3(0, 0.2, 0), Color(0.6, 0.55, 0.45, 0.5), 2, 0.8, 0.3, 0.6, false, 0.5)

static func clear(h: Hero) -> void:
	h.fxs.erase("charge")
