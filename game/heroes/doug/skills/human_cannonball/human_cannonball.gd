class_name HumanCannonball
extends BellyFlop
## Human Cannonball (a run's skill, "u_cannon"): fired out of a cannon onto the pointer, he lands in a belly-flop that
## flattens everything round him (BellyFlop; Extra Gunpowder: wider and harder). Its look: Big Top Bounce's mark and
## flop, and its own boom (DougFx "boom").

func fallbacks() -> Dictionary:
	return {"dmg": 260.0, "radius": 4.5, "knock": 2.4, "stun_s": 1.0}

func radius() -> float:
	return k("radius") * (1.0 + hero.talent("cannon_r") / 100.0)

func landed() -> void:
	hero.fx(id, "boom", {"p": hero.global_position, "r": radius()})
	hero.game.add_shake(0.5)
