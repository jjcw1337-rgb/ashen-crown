class_name SoulShackles
extends WarlockSpell
## Soul Shackles ("shackles"): everything near her is hit and bound in place (stunned; a player only hurt: its stun
## isn't reviewed for PvP yet). Its look: WarlockFx ("impact": the chains). Codex "k": reach (metres; Binding Reach
## adds to it), bind_s (seconds; Iron Chains and Haunting add to it), dmg (% of the weapon's blow), cast_s.

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.5) * Data.attack_pace(hero.cls)

func impact() -> void:
	make("bind", {"p": hero.global_position})

func made(kind: String, d: Dictionary) -> void:
	if kind != "bind":
		return
	var h := hero
	var reach_s := val("reach", 7.0) + h.talent("shackle_range")
	var bind_t := val("bind_s", 2.5) + h.talent("shackle_dur") + h.talent("fear_dur")
	var bound: Array = h.game.enemies_near(d["p"], reach_s).filter(func(e) -> bool: return foe(e))
	h.fx(id, "impact", {"r": reach_s, "x": bind_t, "t": bound})
	for e in bound:
		h._hit_enemy(e, val("dmg", 80.0) / 100.0, 0.0, id)
		if not e.dead:
			e.stun(bind_t)

## Server: the chains where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "bind" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= 4.0
