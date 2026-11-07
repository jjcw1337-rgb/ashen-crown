class_name BattleCry
extends KnightSkill
## Battle Cry ("cry"): the class's battle buff (Hero.buff_t: more damage and defense; Hero.buff_mult) for its time, and
## everything near him stunned (a player through the server). Rallying Cry (the talent "cry_heal") heals him a share of
## his life. The buff and the heal are his own game's at once (it owns his life and his defense); the stun is the
## rules', and on the match server its copy of him takes the buff too, so his skills hit as hard there (it wears off
## there with ServerRules.update). Its look: BattleCryFx ("impact"). Codex "k": secs, stun_s, radius, cast_s.

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.6) * Data.attack_pace(hero.cls)

func impact() -> void:
	var h := hero
	_rally()
	if h.talent("cry_heal") > 0.0:
		h.gain_life(h.max_life * h.talent("cry_heal") / 100.0)
	h.fx(id, "impact")
	make("cry", {"p": h.global_position})

func _rally() -> void:
	hero.buff_t = val("secs", 12.0) + hero.talent("buff_dur")

## The cry its rules sound: the buff on the server's copy of him, everything near stunned.
func made(kind: String, d: Dictionary) -> void:
	if kind != "cry":
		return
	_rally()
	for e in hero.game.enemies_near(d["p"], val("radius", 6.0)):
		if foe(e):
			stun(e, val("stun_s", 2.0))

## Server: the cry is where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "cry" and near_him(d.get("p"), 0.0)
