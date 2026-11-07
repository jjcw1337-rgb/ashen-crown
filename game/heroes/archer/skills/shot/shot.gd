class_name ArcherShot
extends ArrowSkill
## His shot, the bow attack (Archer.shoot starts it, Hero.swipe_attack and free_attack come there): one arrow, or
## three in a narrow fan with Split Arrow, the middle one at full strength. Its numbers belong to the Split Arrow
## rite, so they stay here until rites carry their own.

const SPLIT_SPREAD := 0.16      # radians between the three
const SPLIT_SIDE := 0.5         # the side arrows' share of the blow

func impact() -> void:
	var n := 3 if hero.talent("arrow_split") > 0.0 else 1
	var mid: int = (n - 1) / 2
	for k in n:
		shoot(hero.atk_aim, false, 1.0 if k == mid else SPLIT_SIDE, (float(k) - (n - 1) * 0.5) * SPLIT_SPREAD)
	RunTalents.on_shot(hero)
