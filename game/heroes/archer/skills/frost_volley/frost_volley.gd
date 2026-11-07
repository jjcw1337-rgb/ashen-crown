class_name FrostVolley
extends Skill
## Frost Volley: a flight of frost arrows loosed high that rains on the cursor, striking everything within reach
## again and again and chilling it (Rime: colder; Shatter: the chilled take more), and leaves the ground frozen,
## slowing whatever stands in it or crosses it until it has thawed (jj). Its look: FrostVolleyRainFx (the rain's
## strikes) and FrostVolleyFx (the storm). Codex "k": dmg (% of the weapon's blow, each beat), radius (metres; Wide
## Volley adds to it), reach (how far off it can fall), chill (% slower), chill_max, chill_s, ground_chill_s,
## rain_s (how long it rains), first and beat (seconds to the first strike and between strikes).

var zones: Array = []      # its rains (GroundZone), each with its frozen ground

func cast(aim: Vector3) -> void:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	hero.atk_aim = hero.global_position + to.limit_length(val("reach", 14.0))
	hero._start_attack("bow", id)

func impact() -> void:
	var at: Vector3 = hero.atk_aim
	var g := Vector3(at.x, hero.game.world.height_at(at.x, at.z), at.z)
	var r := val("radius", 4.0) * (1.0 + hero.talent("volley_size") / 100.0)
	hero.fx(id, "impact", {"p": g, "r": r})    # the flight up and the storm, on every game
	# the rain's beat (FrostVolleyRainFx keeps the same one from the same numbers)
	zones.append(GroundZone.new(g, r, val("rain_s", 1.3), val("first", 0.25), val("beat", 0.2)))

func update(delta: float) -> void:
	for z in zones.duplicate():
		if z.beat(delta):
			_strike(z)
		_frozen_ground(z, delta)
		if z.over() and z.age >= FrostVolleyFx.SHATTER_AT + FrostVolleyFx.THAW:
			zones.erase(z)

func _slow() -> float:
	return minf(val("chill", 40.0) / 100.0 * (1.0 + hero.talent("chill_pct") / 100.0), val("chill_max", 75.0) / 100.0)

## A beat of the rain: a hit on everything in reach, chilling it.
func _strike(z: GroundZone) -> void:
	var slow := _slow()
	for e in hero.game.enemies_near(z.pos, z.r):
		if not e.dead:
			hero._hit_enemy(e, val("dmg", 35.0) / 100.0 * Archer.shatter(hero, e), 0.0, id)
			e.chill(slow, val("chill_s", 2.0))

## The frozen ground: everything on it is slowed (a moment past the edge too: leaving it, he's still slow for a step or
## two), from when the frost has spread until it has thawed, shrinking from the edges in as it thaws (the storm's
## timing: FrostVolleyFx's ground is full until the shatter, then thaws over THAW).
func _frozen_ground(z: GroundZone, delta: float) -> void:
	z.data["slow_tick"] = float(z.data.get("slow_tick", 0.0)) - delta
	if float(z.data["slow_tick"]) > 0.0:
		return
	z.data["slow_tick"] = 0.25
	var fr := frozen_radius(z.age, z.r)
	if fr < 0.3:
		return
	var slow := _slow()
	for e in hero.game.enemies_near(z.pos, fr):
		if not e.dead:
			e.chill(slow, val("ground_chill_s", 0.6))

static func frozen_radius(age: float, r: float) -> float:
	if age < FrostVolleyFx.STORM_AT + 0.15:
		return 0.0
	if age <= FrostVolleyFx.SHATTER_AT:
		return r
	var k := smoothstep(0.0, 1.0, (age - FrostVolleyFx.SHATTER_AT) / FrostVolleyFx.THAW)
	return r * clampf((1.0 - k) * 1.2, 0.0, 1.0)

func clear() -> void:
	zones.clear()
