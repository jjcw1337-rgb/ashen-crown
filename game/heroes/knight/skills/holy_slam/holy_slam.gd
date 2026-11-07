class_name HolySlam
extends KnightSkill
## Holy Slam ("cleave"): he leaps toward the cursor (up to the skill's range) and brings the blade down `reach` ahead
## of him; everything round the blow is hit, thrown back and stunned (a player through the server). His game shows the
## slam where the blade lands at once ("slam"); the rules strike round it ("struck": the sparks on each foe). Its
## look: HolySlamFx. Codex "k": dmg (% of the weapon's blow), radius (metres round the blade, plus each foe's size),
## stun_s, knock, reach (how far ahead of him the blade lands), cast_s.

func cast(aim: Vector3) -> void:
	hero._start_attack("cleave", id, val("cast_s", 0.95))      # crouch, leap, slam, hold the blow, rise
	leap(aim, float(Data.skill_def(id).get("range", 6.0)), val("reach", 1.25))

func impact() -> void:
	var at := blade_at()
	hero.fx(id, "slam", {"p": at})
	make("slam", {"p": at})

## The blow its rules land round where the blade came down.
func made(kind: String, d: Dictionary) -> void:
	if kind != "slam":
		return
	var h := hero
	var at: Vector3 = d["p"]
	var r := val("radius", 2.6)
	var ps := PackedVector3Array()
	for e in h.game.enemies_near(at, r + 1.0):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius <= r:
			h._hit_enemy(e, val("dmg", 160.0) / 100.0, val("knock", 0.6), id)
			stun(e, val("stun_s", 1.0))
			ps.append(e.global_position + Vector3(0, 1.0, 0))
	if not ps.is_empty():
		h.fx(id, "struck", {"ps": ps})

## Server: the blade came down within a leap of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "slam" and near_him(d.get("p"), float(Data.skill_def(id).get("range", 6.0)) + val("reach", 1.25))
