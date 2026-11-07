class_name BattleCryFx
extends RefCounted
## Battle Cry's look (BattleCry's "impact"): the seal under him, a shaft of light rising round him and a ring out to the
## stun's reach (HolyFx.battle_cry), and the cry itself.

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"cast":
			pass    # (its effects land on the impact frame)
		"impact":
			HolyFx.battle_cry(h, h.game.world.fx_root, h.global_position, Skill.num("cry", "radius", 6.0))
			SkillFx.snd(h, "battle_cry")
			SkillFx.duck(h, -8.0, 1.2)
			SkillFx.shake(h, 0.3)
		_:
			return false
	return true
