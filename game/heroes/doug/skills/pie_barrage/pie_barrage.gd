class_name PieBarrage
extends PieSkill
## Pie Barrage (a run's skill, "u_barrage"): a flurry of cream pies flung onto the foes round the pointer, one each,
## the rest round the spot (Bakery Order: more of them); each lands like a Cream Pie, Pieing the foe it finds the
## first time (PieSkill). Its look is the Cream Pie's (bigger pies). Codex "k": dmg (% of the weapon's blow, each),
## pies (how many), radius (metres round the pointer it looks for foes), spread_min and spread_max (metres out from the
## pointer the spare pies fall), gap (seconds between the throws).

var aim := Vector3.ZERO

func cast(at: Vector3) -> void:
	aim = at
	hero._start_attack("pie", id)

func impact() -> void:
	var h := hero
	var at := aim
	var off := at - h.global_position
	off.y = 0
	if off.length() > float(Data.skill_def(id).get("range", 12.0)):
		at = h.global_position + off.normalized() * float(Data.skill_def(id).get("range", 12.0))
	var foes: Array = h.game.enemies_near(at, val("radius", 5.0)).filter(func(e) -> bool: return foe(e))
	var n := most()
	var ps := PackedVector3Array()
	var ts := PackedFloat32Array()
	for i in n:
		var to: Vector3
		if i < foes.size():
			to = foes[i].global_position
		else:
			var a := TAU * float(i) / n
			to = at + Vector3(cos(a), 0, sin(a)) * randf_range(val("spread_min", 1.0), val("spread_max", 3.5))
		var t := flight() + i * val("gap", 0.05)
		ps.append(to)
		ts.append(t)
		h.fx("pie", "throw", {"p": h.global_position + Vector3(0, 1.2, 0), "q": to, "x": t, "r": 1.1})
	make("pies", {"ps": ps, "ts": ts})

func blow() -> float:
	return val("dmg", 80.0) / 100.0

func most() -> int:
	return int(val("pies", 6.0)) + int(hero.talent("barrage_more"))

## Its pies fall round the point aimed at, as far as the foes it looks for there.
func reach() -> float:
	return float(Data.skill_def(id).get("range", 12.0)) + val("radius", 5.0)
