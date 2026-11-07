class_name Malediction
extends WarlockSpell
## Malediction ("w_malediction"): a bolt that hits harder for each of her curses on the foe (a plague pool it stands
## in counts). Its look: WarlockHarrowFx ("bolt", bigger with more curses). Codex "k": dmg (% of her spell power),
## per (% more for each curse), max (curses that count).

func targeted() -> bool:
	return true

func struck(e) -> void:
	var hx := hex()
	var n := mini(hx.curses_on(e), int(val("max", 5.0)))
	hero.fx(id, "bolt", {"t": [e], "n": n})
	hx.hit(e, hx.amount(id, val("dmg", 90.0) / 100.0 * (1.0 + val("per", 50.0) / 100.0 * n), e), WarlockHex.SHADOW_TINT)
