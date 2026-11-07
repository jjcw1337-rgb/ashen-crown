class_name ArrowStorm
extends Skill
## Arrow Storm (a run's skill, "a_barrage"): a storm of plain arrows loosed high that falls on the cursor, striking
## everything within reach several times (Barrage: more strikes). Its look: ArrowStormFx. Codex "k": dmg (% of the
## weapon's blow, each strike), radius, reach (how far off it can fall), strikes, first and beat (seconds to the
## first strike and between strikes).

var zones: Array = []

func cast(aim: Vector3) -> void:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	hero.atk_aim = hero.global_position + to.limit_length(val("reach", 14.0))
	hero._start_attack("bow", id)

func impact() -> void:
	var g: Vector3 = hero.atk_aim
	g.y = hero.game.world.height_at(g.x, g.z)
	var r := val("radius", 4.5)
	hero.fx(id, "impact", {"p": g, "r": r})
	make("storm", {"g": g, "r": r})

## The storm its rules beat.
func made(kind: String, d: Dictionary) -> void:
	if kind != "storm":
		return
	var n := int(val("strikes", 6.0)) + int(hero.talent("barrage_ticks"))
	var gap := val("beat", 0.25)
	zones.append(GroundZone.new(d["g"], float(d["r"]), 0.1 + n * gap, val("first", 0.15), gap, n))

## Server: a storm within his reach of where it has him, no wider than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "storm" or not d.get("g") is Vector3:
		return false
	if (d["g"] as Vector3).distance_to(hero.global_position) > val("reach", 14.0) + 4.0:
		return false
	d["r"] = minf(float(d.get("r", 0.0)), val("radius", 4.5))
	return true

func update(delta: float) -> void:
	for z in zones.duplicate():
		if z.beat(delta):
			for e in hero.game.enemies_near(z.pos, z.r):
				if foe(e):
					hero._hit_enemy(e, val("dmg", 32.0) / 100.0, 0.05, id)
		if z.over():
			zones.erase(z)

func clear() -> void:
	zones.clear()
