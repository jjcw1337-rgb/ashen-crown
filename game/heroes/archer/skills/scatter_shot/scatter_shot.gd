class_name ScatterShot
extends ArrowSkill
## Scatter Shot (a run's skill, "a_multishot"): five arrows in a fan (seven with Wide Fan), each for its codex "k"
## dmg (% of the weapon's blow). A foe close enough takes several.

func impact() -> void:
	var n := int(val("arrows", 5.0)) + int(hero.talent("multishot_more"))
	for k in n:
		shoot(hero.atk_aim, false, val("dmg", 55.0) / 100.0, (float(k) - (n - 1) * 0.5) * (0.17 if n <= 5 else 0.13))
