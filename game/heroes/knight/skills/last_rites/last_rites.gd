class_name LastRites
extends KnightSkill
## Last Rites (a run's skill, "k_rites"): a leap like Holy Slam's onto the foe nearest the pointer and a blow round
## where the blade lands, harder the more life each foe is missing. A kill makes it ready again (his own game's
## cooldown: `give`), and No Quarter (the talent "rites_buff") gives him a moment's more damage and speed (a run's buff:
## on the server's copy of him too, RunTalents.buff). His game picks the foe and leaps, and shows the blow at once
## ("impact"); the rules strike ("kill" when one falls). Its look: LastRitesFx. Codex "k": dmg (% of the weapon's blow),
## missing (% more for all of a foe's life missing), radius, knock, pick (how near the pointer a foe is taken), reach
## (how far ahead of him the blade lands), cast_s, and No Quarter's nq_dmg, nq_frw (% more damage and run speed), nq_s.

func cast(aim: Vector3) -> void:
	var h := hero
	var best = null
	var bd := val("pick", 3.5)
	for e in h.game.enemies_near(aim, bd):
		var dd: float = e.global_position.distance_to(aim)
		if foe(e) and dd < bd:
			bd = dd
			best = e
	var tgt: Vector3 = best.global_position if best != null else aim
	var to := (tgt - h.global_position) * Vector3(1, 0, 1)
	var most := float(Data.skill_def(id).get("range", 9.0))
	var dist := minf(to.length(), most)
	h._face(to)
	h.atk_aim = h.global_position + to.normalized() * dist if to.length() > 0.1 else aim
	h._start_attack("cleave", id, val("cast_s", 0.85))
	leap(tgt, most, val("reach", 1.25))

func impact() -> void:
	var at := blade_at()
	hero.fx(id, "impact", {"p": at})
	make("rites", {"p": at})

## The blow its rules land: harder on the wounded; a kill readies it again.
func made(kind: String, d: Dictionary) -> void:
	if kind != "rites":
		return
	var h := hero
	var at: Vector3 = d["p"]
	var killed := false
	for e in h.game.enemies_near(at, val("radius", 2.8)):
		if not foe(e):
			continue
		var missing: float = 1.0 - e.life / maxf(1.0, e.max_life)
		h._hit_enemy(e, (val("dmg", 150.0) + val("missing", 200.0) * missing) / 100.0, val("knock", 0.4), id)
		if e.dead:
			killed = true
	if not killed:
		return
	h.fx(id, "kill", {"p": at})
	give("ready", {})
	if h.talent("rites_buff") > 0.0:
		RunTalents.buff(h, "no_quarter", {"dmg": val("nq_dmg", 30.0), "frw": val("nq_frw", 20.0)}, val("nq_s", 4.0))

## Server: the blade came down within a leap of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "rites" and near_him(d.get("p"), float(Data.skill_def(id).get("range", 9.0)) + val("reach", 1.25))

## His own game: a kill made it ready again.
func given(kind: String, _d: Dictionary) -> void:
	if kind == "ready":
		hero.cds[id] = 0.0
