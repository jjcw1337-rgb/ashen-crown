class_name FesteringHex
extends WarlockCurse
## Festering Hex ("w_festering"): a curse that deals nothing by the tick but bursts every few seconds, hurting and
## briefly stunning the foe (a player is staggered through the server, no longer than pvp_stun_s). Its look:
## WarlockHarrowFx ("fester"). Codex "k": secs, tick, every (seconds between bursts), burst (% of her spell power),
## stun_s, pvp_stun_s.

func tick_amount(_d: Dictionary) -> float:
	return 0.0

func beat(d: Dictionary, delta: float) -> void:
	d["fester"] -= delta
	if d["fester"] > 0.0:
		return
	d["fester"] = val("every", 5.0)
	var e = d["e"]
	var hx := hex()
	hero.fx(id, "fester", {"t": [e]})
	hx.hit(e, hx.amount(id, val("burst", 120.0) / 100.0, e), WarlockHex.SHADOW_TINT)
	hx.stun(e, val("stun_s", 0.5))
