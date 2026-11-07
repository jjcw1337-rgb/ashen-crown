class_name UnendingRot
extends WarlockCurse
## Unending Rot ("w_unending"): a curse that grows the longer the foe has been cursed without a break (any of her
## curses), up to `cap` times as strong. Codex "k": dmg, secs, tick, ramp (% more a second), cap (times).

func tick_amount(d: Dictionary) -> float:
	return float(d["per"]) * minf(val("cap", 4.0), 1.0 + val("ramp", 15.0) / 100.0 * hex().afflicted(d["e"])) + hero.talent("dot_flat")
