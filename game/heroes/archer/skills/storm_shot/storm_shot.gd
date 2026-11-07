class_name StormShot
extends ArrowSkill
## Storm Shot (a run's skill, "a_stormshot"): a charged arrow into the first foe it strikes, then lightning leaping
## on to more (Storm Jumps: further). Codex "k": dmg (% of the weapon's blow), jumps, chain (% of his average blow
## each leap deals), chain_r (metres a leap reaches).

func _init(h: Hero, skill_id: String) -> void:
	super(h, skill_id)
	kind = "storm"

func impact() -> void:
	shoot(hero.atk_aim, false, val("dmg", 100.0) / 100.0, 0.0)

func hit(m: Missile, e) -> void:
	strike(m, e)
	var avg: float = (hero.dmg_min + hero.dmg_max) * 0.5
	var each := avg * val("chain", 70.0) / 100.0 * hero.buff_mult() * hero.dmg_mult(id)
	RunTalents._chain(hero, e, int(val("jumps", 4.0)) + int(hero.talent("storm_jumps")), each, val("chain_r", 7.0))
	hero.mark = e
	hero.mark_t = 6.0
