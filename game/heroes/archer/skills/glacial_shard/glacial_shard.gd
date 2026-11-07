class_name GlacialShard
extends ArrowSkill
## Glacial Shard (a run's skill, "a_glacial"): an arrow of ice through every foe in a line, chilling each
## (Shatterpoint: freezing the already chilled). Codex "k": dmg (% of the weapon's blow), chill (% slower), chill_s,
## freeze_s.

func _init(h: Hero, skill_id: String) -> void:
	super(h, skill_id)
	kind = "frost"

func impact() -> void:
	shoot(hero.atk_aim, true, val("dmg", 110.0) / 100.0, 0.0)

func hit(m: Missile, e) -> void:
	strike(m, e)
	if not e.dead:
		if hero.talent("glacial_freeze") > 0.0 and RunTalents.chilled(e):
			RunTalents._freeze(hero, e, val("freeze_s", 1.2))
		e.chill(val("chill", 40.0) / 100.0, val("chill_s", 3.0))
	hero.mark = e
	hero.mark_t = 6.0
