class_name GlacialTomb
extends DragonSkill
## Glacial Tomb ("s_tomb", a run skill): the foe nearest the pointer, and those round it, are sealed in ice (stunned
## and chilled) for its hold; then the tomb shatters, a blow to each one sealed and a lesser one to everything else
## near (Deep Freeze: wider, longer). On the cast's impact frame the serpent's own game picks the first foe and makes the
## "tomb" there, naming that foe (in a match the server finds it by id: ServerRules.foe_of); the rules (here, or on the
## match server's copy of it) seal and shatter (`tombs`). A player is sealed through the server (PvpStatus). Its look:
## glacial_tomb_fx.gd (GlacialTombFx: "seal", "shatter"). Codex "k": pick (metres from the pointer it finds the first
## foe), r (metres round that foe the seal reaches), most (foes in one tomb), hold (seconds sealed), chill and chill_s
## (the cold it leaves, and seconds past the hold), dmg and burst (% of the weapon's blow on each one sealed and on the
## rest), burst_r (metres round it the shatter reaches).

const KNOCK := 1.5           # the shatter's knockback on the sealed
const BURST_KNOCK := 1.0     # and on the rest

var tombs: Array = []        # the rules: tombs holding [{p, t: seconds left, es: the sealed}]

func cast(at: Vector3) -> void:
	hero._start_attack("cast", id)
	halt()
	aim = at

## The tomb goes where it was aimed, on the foe nearest there.
func impact() -> void:
	var at := clamp_aim(aim, reach())
	make("tomb", {"at": at, "id": net_id(_first(at))})

## The foe nearest `at`, within its pick.
func _first(at: Vector3):
	var best = null
	var bd := val("pick", 3.5)
	for e in hero.game.enemies_near(at, bd):
		if hits(e) and e.global_position.distance_to(at) < bd:
			bd = e.global_position.distance_to(at)
			best = e
	return best

## The tomb its rules seal: the foe its id names (the match server), else the one nearest the point; and those round it.
func made(kind: String, d: Dictionary) -> void:
	if kind != "tomb":
		return
	var h := hero
	var at: Vector3 = d["at"]
	var first = foe_by_id(d, reach() + 6.0)
	if first == null:
		first = _first(at)
	var sealed: Array = []
	if first != null:
		sealed.append(first)
		for e in h.game.enemies_near(first.global_position, val("r", 2.5) * (1.0 + h.talent("tomb_r") / 100.0)):
			if hits(e) and e != first and sealed.size() < int(val("most", 6.0)):
				sealed.append(e)
	var secs := val("hold", 1.6) + h.talent("tomb_t")
	for e in sealed:
		stun(e, secs)
		chill(e, val("chill", 0.6), secs + val("chill_s", 2.0))
	var c: Vector3 = first.global_position if first != null else at
	tombs.append({"p": c, "t": secs, "es": sealed})
	h.fx(id, "seal", {"p": c, "t": sealed, "x": secs})

## Server: a tomb within its reach of where it has the serpent.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "tomb" and near_me(d.get("at"), reach() + 4.0)

## The rules: each tomb's hold runs out, and it shatters.
func update(delta: float) -> void:
	for i in range(tombs.size() - 1, -1, -1):
		var tb: Dictionary = tombs[i]
		tb["t"] = float(tb["t"]) - delta
		if float(tb["t"]) <= 0.0:
			tombs.remove_at(i)
			_shatter(tb)

func _shatter(tb: Dictionary) -> void:
	var h := hero
	var es: Array = tb["es"]
	var struck: Array = []
	var c: Vector3 = tb["p"]
	for e in es:
		if hits(e):
			h._hit_enemy(e, val("dmg", 180.0) / 100.0, KNOCK, id)
			struck.append(e)
			c = e.global_position if struck.size() == 1 else c
	var r := val("burst_r", 3.0)
	for e in h.game.enemies_near(c, r):
		if hits(e) and not es.has(e):
			h._hit_enemy(e, val("burst", 90.0) / 100.0, BURST_KNOCK, id)
			struck.append(e)
	h.fx(id, "shatter", {"p": c, "r": r, "t": es})

func clear() -> void:
	tombs.clear()
