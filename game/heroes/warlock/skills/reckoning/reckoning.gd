class_name Reckoning
extends WarlockCurse
## Reckoning ("w_reckoning"): a curse whose every tick deals what all her other curses on the foe deal in a tick.
## Codex "k": secs, tick.

func tick_amount(d: Dictionary) -> float:
	var hx := hex()
	var sum := 0.0
	for o in hx.dots:
		if o["e"] == d["e"] and o != d and str(o["id"]) != id:
			sum += hx.tick_amount(o)
	return sum
