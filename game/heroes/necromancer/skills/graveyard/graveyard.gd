class_name Graveyard
extends Skill
## Graveyard ("graveyard", Q): he slams his scythe-staff down and a graveyard tears up out of the ground at the
## pointer: the old waypoint's rune-ring floor, a hooded guardian, broken pillars, gravestones, braziers of green soul
## fire. After `rise` seconds its risen dead (`risen` of them: zombies and bone archers, clawing out between the graves)
## start striking: every `beat`, each of them strikes one foe inside the graveyard (the nearest each, so several foes
## share the dead out), and every foe inside is slowed by the grave chill (`slow`%). It lasts `secs`, then the dead
## crumble and the graves sink. Its rules keep the graveyards (`yards`, GroundZones); its look (GraveyardFx) raises
## its own copy of the place from the "rise" event and shows each strike from the "strike" event (where each of the
## dead struck), so what is seen and what hits agree. The answer to it: walk out of it.
## Codex "k": radius, secs, rise, beat, risen, dmg (% of the weapon's blow, each strike), slow.

var yards: Array = []       # rules: GroundZones, each with data {"n": its risen}

func cast(aim: Vector3) -> void:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	hero.atk_aim = hero.global_position + to.limit_length(float(Data.skill_def(id).get("range", 14.0)))
	hero._start_attack("grave_slam", id)

## The staff strikes the ground: the graveyard rises where he aimed.
func impact() -> void:
	var g: Vector3 = hero.atk_aim
	g.y = hero.game.world.height_at(g.x, g.z)
	var d := {"g": g, "r": val("radius", 6.0), "x": val("secs", 8.0), "n": int(val("risen", 4.0))}
	hero.fx(id, "rise", d)
	make("yard", d)

func made(kind: String, d: Dictionary) -> void:
	if kind != "yard":
		return
	var secs := float(d.get("x", val("secs", 8.0)))
	var z := GroundZone.new(d["g"], float(d["r"]), secs, val("rise", 1.0), val("beat", 1.0))
	z.data = {"n": int(d.get("n", 4))}
	yards.append(z)

## Server: a graveyard within his reach of where it has him, no bigger, no longer and no more crowded than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "yard" or not d.get("g") is Vector3:
		return false
	if (d["g"] as Vector3).distance_to(hero.global_position) > float(Data.skill_def(id).get("range", 14.0)) + 4.0:
		return false
	d["r"] = minf(float(d.get("r", 0.0)), val("radius", 6.0))
	d["x"] = minf(float(d.get("x", 0.0)), val("secs", 8.0))
	d["n"] = mini(int(d.get("n", 0)), int(val("risen", 4.0)))
	return true

func update(delta: float) -> void:
	var slow := val("slow", 25.0) / 100.0
	for z in yards.duplicate():
		var inside: Array = []
		for e in hero.game.enemies_near(z.pos, z.r):
			if foe(e) and Vector2(e.global_position.x - z.pos.x, e.global_position.z - z.pos.z).length() <= z.r:
				inside.append(e)
		if z.age >= val("rise", 1.0):
			for e in inside:
				_chill(e, slow)
		if z.beat(delta) and not inside.is_empty():
			# the dead share the foes out: the nearest to the middle first, each of the dead the next in turn
			inside.sort_custom(func(a, b): return a.global_position.distance_squared_to(z.pos) < b.global_position.distance_squared_to(z.pos))
			var spots: Array = []
			for i in int(z.data.get("n", 4)):
				var e = inside[i % inside.size()]
				hero._hit_enemy(e, val("dmg", 45.0) / 100.0, 0.02, id)
				spots.append([i, e.global_position])
			hero.fx(id, "strike", {"g": z.pos, "t": spots})
		if z.over():
			hero.fx(id, "end", {"g": z.pos})
			yards.erase(z)

## The grave chill: a monster slowed while it stands inside; another player through the server, which checks it.
func _chill(e, k: float) -> void:
	if int(e.get("pvp_pid")) > 0:
		if Engine.get_process_frames() % 20 == 0:
			hero.game.net.send_pvp_status(int(e.pvp_pid), "slow", 0.4, {"k": k})
		return
	e.slow(0.3, k)

## Where the `i`th of `n` risen dead claws out: round the graveyard, a little inside its edge.
static func risen_spot(g: Vector3, r: float, i: int, n: int) -> Vector3:
	var a := TAU * (float(i) + 0.5) / float(maxi(1, n)) + 0.4
	return g + Vector3(cos(a), 0, sin(a)) * r * 0.55

func clear() -> void:
	yards.clear()
