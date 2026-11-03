class_name SharedFx
extends RefCounted
## What the shared skills (SharedSkills) look and sound like, for the caster and his puppet alike (SkillFx.play
## hands their events here, whatever the hero's class). Draws only. Each element's look is ElementalFx's (the
## visual overhaul: they were the generic Fx burst and ring in four colours).

const EARTH := Color(1.0, 0.5, 0.18)        # the slam's warning wedge: a hot earthy orange
const ICE := Color(0.6, 0.85, 1.0)
const STORM := Color(0.75, 0.7, 1.0)
const CRY := Color(1.0, 0.3, 0.2)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var e := str(ev["e"])
	match str(ev["s"]):
		"earthshatter":
			match e:
				"cast":
					SkillFx.snd(h, "swing_heavy", -6.0, 0.7)
				"windup":
					Fx.arc_telegraph(root, h.global_position, ev["d"], 5.0, 50.0, float(ev["x"]), EARTH)
				"impact":
					var d: Vector3 = ev["d"]
					var p: Vector3 = ev["p"]
					var area: Dictionary = Data.skill_def("earthshatter").get("area", {})
					ElementalFx.earthshatter(h, root, p, d, float(area.get("r", 5.0)), float(area.get("angle", 100.0)) * 0.5)
					SkillFx.snd(h, "slam", -2.0, 0.8)
					SkillFx.snd(h, "boom", -9.0, 0.7)
					SkillFx.shake(h, 0.35)
				_:
					return false
		"frost_nova":
			match e:
				"cast":
					SkillFx.snd(h, "spirit_dart", -10.0, 0.7)
					InfernalFx.particles(root, SkillFx.hand(h, true), {"amount": 10, "life": 0.5, "shape": "sphere", "r": 0.12,
						"dir": Vector3.UP, "spread": 180.0, "vel": [0.2, 0.6], "radial": [-3.0, -2.0], "scale": [0.4, 0.9], "size": 0.05,
						"colors": [[0.0, Color(ElementalFx.ICE_PALE, 0.0)], [0.3, ElementalFx.ICE_PALE], [1.0, Color(ElementalFx.ICE_DEEP, 0.0)]]})
				"impact":
					ElementalFx.frost_nova(h, root, ev["p"], float(ev["r"]))
					SkillFx.snd(h, "ice_shatter", -3.0, 1.0)
					SkillFx.shake(h, 0.12)
				_:
					return false
		"arc":
			match e:
				"cast":
					var hand := SkillFx.hand(h, true)
					ElementalFx.bolt(root, hand, hand + Vector3(randf_range(-0.3, 0.3), 0.35, randf_range(-0.3, 0.3)), 0.18, 0.03, 1)
				"impact":
					var ps: PackedVector3Array = ev["ps"]
					ElementalFx.arc(h, root, ps, ev["d"])
					SkillFx.snd(h, "thunder_strike", -8.0, 1.35)
				_:
					return false
		"war_cry":
			match e:
				"cast":
					pass
				"impact":
					ElementalFx.war_cry(h, root, ev["p"], SharedSkills.CRY_R)
					SkillFx.snd(h, "battle_cry", -2.0, 1.0)
					SkillFx.shake(h, 0.2)
				_:
					return false
		_:
			return false
	return true
