class_name LeechBolt
extends WarlockSpell
## Leech Bolt ("w_leechbolt"): a quick bolt, part of what it deals healing her. Its look: WarlockHarrowFx ("bolt").
## Codex "k": dmg (% of her spell power), heal (% of the damage).

func targeted() -> bool:
	return true

func struck(e) -> void:
	var hx := hex()
	hero.fx(id, "bolt", {"t": [e]})
	var dealt := hx.hit(e, hx.amount(id, val("dmg", 140.0) / 100.0, e), Color(0.6, 1.0, 0.45))
	hx.heal(id, dealt * (val("heal", 30.0) / 100.0))
