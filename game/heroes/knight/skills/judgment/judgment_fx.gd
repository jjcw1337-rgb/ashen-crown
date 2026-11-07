class_name JudgmentFx
extends RefCounted
## Judgment's look (Judgment's "impact" {ps: the pillars}): a seal drawn on the ground under each, then a column of
## light slamming down on it in a sunburst, a ring of holy fire and a ripple out to its reach.

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var r := Skill.num("k_judgment", "radius", 3.0)
	match str(ev["e"]):
		"cast":
			pass
		"impact":
			for q in ev.get("ps", PackedVector3Array()):
				HolyFx.seal(root, q, r, 0.1, 0.8, 1.0)
				HolyFx.level_up(h, root, q)
				HolyFx.fire_ring(root, q, 0.4, r, 0.9, 0.35)
				HolyFx.shockwave(root, h.game, q, r + 0.8, 0.35)
				Sfx.play_at("judgment_pillar", q, -1.0)
			SkillFx.shake(h, 0.3)
		"brand":
			HolyBrandsFx.play(h, ev)
		_:
			return false
	return true
