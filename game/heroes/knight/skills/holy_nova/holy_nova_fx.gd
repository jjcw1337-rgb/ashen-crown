class_name HolyNovaFx
extends RefCounted
## Holy Nova's look (HolyNova's "impact"): the knight's holy fire ring racing out to the edge of the blast (HolyFx.nova).

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"cast":
			pass    # (its effects land on the impact frame)
		"impact":
			HolyFx.nova(h, h.game.world.fx_root, h.global_position, Skill.num("nova", "radius", 7.0))
			SkillFx.shake(h, 0.35)
		_:
			return false
	return true
