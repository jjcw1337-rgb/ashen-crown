class_name KnightFx
extends RefCounted
## Visual effects for the knight's skills (SkillFx events; the gameplay is in Hero._impact / _update_charge).
##  Holy Slam: "slam" {p: where the blade lands, x: hit anything} (the leap itself is the pose)
##  Holy Nova: "impact"
##  Charge: "cast" (the dash's trail follows him in `update` for 0.5 s), "hit" {p, x: the first one}, "end"
##  Battle Cry: "impact"
## Nova, Battle Cry and Charge are drawn in the knight's own holy language (HolyFx: the seal, holy fire, the light
## column, the shockwave); they had been the generic Fx ring, burst and pillar in gold.

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
			HolyFx.nova(h, root, pos, 7.0)
			SkillFx.shake(h, 0.35)
		["cry", "impact"]:
			HolyFx.battle_cry(h, root, pos, 6.0)
			SkillFx.snd(h, "battle_cry")
			SkillFx.duck(h, -8.0, 1.2)
			SkillFx.shake(h, 0.3)
		["charge", "cast"]:
			h.fxs["charge"] = 0.5
			HolyFx.charge_start(h, root)
			SkillFx.snd(h, "charge_dash", -2.0)
		["charge", "hit"]:
			var p: Vector3 = ev["p"]
			var first := bool(ev.get("x", false))
			if first:
				Sfx.play_at("charge_impact", p, 0.0)
			HolyFx.charge_hit(h, root, p, first)
		["charge", "end"]:
			h.fxs.erase("charge")
			HolyFx.charge_end(h, root, pos)
			SkillFx.shake(h, 0.25)
		_:
			return false
	return true

## The Charge's trail of light and dust follows him (on the caster and on his puppet) for as long as the dash lasts.
static func update(h: Hero, delta: float) -> void:
	if h.cls == "knight":
		HolyFx.warm(h)
	if not h.fxs.has("charge"):
		if h.fxs.has("charge_trail"):
			HolyFx.charge_clear(h)
		return
	var left: float = float(h.fxs["charge"]) - delta
	if left <= 0.0:
		h.fxs.erase("charge")
		HolyFx.charge_clear(h)
		return
	h.fxs["charge"] = left
	HolyFx.charge_follow(h)

static func clear(h: Hero) -> void:
	h.fxs.erase("charge")
	HolyFx.charge_clear(h)
