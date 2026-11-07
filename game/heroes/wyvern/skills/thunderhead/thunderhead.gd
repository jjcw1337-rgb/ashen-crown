class_name Thunderhead
extends DragonSkill
## Thunderhead ("v_cloud", a run skill): the wyvern roars up a storm cloud over the pointer, which strikes a foe
## beneath it every so often while it lasts; no more than a few at once, the oldest giving way (Supercell: faster,
## longer, and a bolt may stun). On the cast's impact frame its own game makes the "cloud" where it aimed; the rules
## (here, or on the match server's copy of it) keep the clouds (`clouds`) and strike from them, and show them ("form",
## "bolt", "end"). Its look: thunderhead_fx.gd (ThunderheadFx). Codex "k": secs, r (metres under it a bolt reaches),
## first and every (seconds to the first bolt and between them), most (clouds at once), dmg (% of the weapon's blow),
## stun_s (Supercell's stun).

var clouds: Array = []      # the rules: [{p, t: seconds left, tick: seconds to the next bolt}]

func cast(at: Vector3) -> void:
	hero._start_attack("cast", id)
	halt()
	aim = at

func impact() -> void:
	make("cloud", {"p": clamp_aim(aim, reach())})

func made(kind: String, d: Dictionary) -> void:
	if kind != "cloud":
		return
	var h := hero
	var p: Vector3 = d["p"]
	while clouds.size() >= int(val("most", 2.0)):
		var old: Dictionary = clouds.pop_front()
		h.fx(id, "end", {"p": old["p"]})
	var secs := val("secs", 4.0) + h.talent("cloud_t")
	clouds.append({"p": p, "t": secs, "tick": val("first", 0.25)})
	h.fx(id, "form", {"p": p, "x": secs, "r": val("r", 5.0)})

## Server: a cloud within its reach of where it has the wyvern.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "cloud" and near_me(d.get("p"), reach() + 4.0)

## The rules: each cloud's time runs out; between, its bolts.
func update(delta: float) -> void:
	var h := hero
	for i in range(clouds.size() - 1, -1, -1):
		var cl: Dictionary = clouds[i]
		cl["t"] = float(cl["t"]) - delta
		cl["tick"] = float(cl["tick"]) - delta
		if float(cl["t"]) <= 0.0:
			clouds.remove_at(i)
			h.fx(id, "end", {"p": cl["p"]})
			continue
		if float(cl["tick"]) > 0.0:
			continue
		cl["tick"] = val("every", 0.5) * (1.0 - h.talent("cloud_rate") / 100.0)
		var foes: Array = h.game.enemies_near(cl["p"], val("r", 5.0)).filter(hits)
		if foes.is_empty():
			continue
		var e = foes[randi() % foes.size()]
		h._hit_enemy(e, val("dmg", 45.0) / 100.0, 0.0, id)
		if not e.dead and h.talent("cloud_stun") > 0.0 and randf() < h.talent("cloud_stun") / 100.0:
			stun(e, val("stun_s", 0.5))
		h.fx(id, "bolt", {"p": cl["p"], "q": e.global_position, "t": [e]})

func clear() -> void:
	clouds.clear()
