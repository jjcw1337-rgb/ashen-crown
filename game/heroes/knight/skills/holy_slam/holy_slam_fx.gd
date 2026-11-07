class_name HolySlamFx
extends RefCounted
## Holy Slam's look (HolySlam's events; the leap itself is the pose): "slam" {p: where the blade lands} the white blast
## there at once, "struck" {ps: the foes it hit} sparks off each and a harder shake.

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			pass    # (its effects land on the impact frame)
		"slam":
			Fx.holy_slam(root, ev["p"], Skill.num("cleave", "radius", 2.6))
			SkillFx.shake(h, 0.32)
			SkillFx.hitstop(h, 0.04)
		"struck":
			for p in ev.get("ps", PackedVector3Array()):
				Fx.sparks(root, p, Color(1.0, 0.97, 0.9))
			SkillFx.shake(h, 0.18)
			SkillFx.hitstop(h, 0.09)
		_:
			return false
	return true
