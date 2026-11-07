class_name CorpseBloom
extends PlagueSkill
## R Corpse Bloom ("bloom"): a seed driven into the ground grows, then breathes: every few seconds a contracting ring,
## then a spore pulse that hurts and Blights everything in reach; anyone who hasn't moved since the ring began is
## snared by its roots (a player through the server: PvpStatus "snare"). Overgrowth pulses it more often, a run's
## talents make it wider, longer and its snare longer.
## PvP (PvpObjects): other players can break it. His own game counts their blows (`owned`, `obj_hit`) and, when it
## breaks, tells the rules (`make("break")`); the server checks a blow's reach against where the rules have it.
## Its look: PlagueBloomFx ("bloom" {p, r, n: its id, x: seconds it breathes, a: seconds between pulses}, "pulse"
## {p, n, t: the monsters its roots lash}, "obj" {n, x: blows left}). Codex "k": cast_s, radius (Bigger Bloom adds
## to it), grow_s, active_s, every, warn (the ring's seconds before a pulse), snare_s, still (metres a foe may move and
## still count as standing still), pulse_flat/lvl/wpn.

var blooms: Array = []      # the rules': {pos, r, age, life, next, every, marks, warned, oid}
var owned := {}             # his game: id -> [blows left, seconds it stands]

func cast(aim: Vector3) -> void:
	hero.atk_aim = within_range(aim, 9.0)
	hero._start_attack("pd_bloom", id)
	hero.atk_dur = cast_secs(0.95)

func impact() -> void:
	var g := ground(hero.atk_aim)
	var r := radius()
	var oid := Plague.new_oid(hero)
	reveal_if_fogged()
	owned[oid] = [int(PvpObjects.HITS["bloom"]), val("grow_s", 1.0) + active_s()]
	hero.fx(id, "bloom", {"p": g, "r": r, "n": oid, "x": active_s(), "a": every()})
	make("bloom", {"g": g, "r": r, "n": oid})

func radius() -> float:
	return val("radius", 3.5) * (1.0 + hero.talent("bloom_size") / 100.0)

func active_s() -> float:
	return val("active_s", 6.0) + hero.talent("bloom_dur")

## Seconds between pulses (Overgrowth: more often), never quicker than its warning ring allows.
func every() -> float:
	return maxf(val("warn", 0.6) + 0.3, val("every", 2.0) / (1.0 + hero.talent("bloom_rate") / 100.0))

## Server: within its range of where it has him, no wider than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	match kind:
		"bloom":
			if not near_him(d.get("g"), float(Data.skill_def(id).get("range", 9.0)) + 4.0):
				return false
			d["r"] = clampf(float(d.get("r", 0.0)), 0.0, radius())
			return true
		"break":
			return obj_pos(int(d.get("n", 0))) is Vector3
	return false

func made(kind: String, d: Dictionary) -> void:
	match kind:
		"bloom":
			var ev := every()
			blooms.append({"pos": d["g"], "r": float(d["r"]), "age": 0.0, "life": val("grow_s", 1.0) + active_s(),
				"next": val("grow_s", 1.0) + ev - val("warn", 0.6), "every": ev, "marks": {}, "warned": false, "oid": int(d.get("n", 0))})
		"break":
			for b in blooms.duplicate():
				if int(b["oid"]) == int(d.get("n", 0)):
					blooms.erase(b)

func update(delta: float) -> void:
	for oid in owned.keys():
		owned[oid][1] = float(owned[oid][1]) - delta
		if float(owned[oid][1]) <= -2.0:
			owned.erase(oid)
	for b in blooms.duplicate():
		b["age"] = float(b["age"]) + delta
		if float(b["age"]) >= float(b["life"]):
			blooms.erase(b)
			continue
		var age: float = b["age"]
		if not bool(b["warned"]):
			if age >= float(b["next"]):
				# the ring begins (the look draws it on its own clock): remember where everyone in reach stands
				b["warned"] = true
				var marks := {}
				for e in foes(b["pos"], float(b["r"]) + 1.5):
					marks[e.get_instance_id()] = e.global_position
				b["marks"] = marks
			continue
		if age < float(b["next"]) + val("warn", 0.6):
			continue
		_pulse(b)

## The pulse: everything in reach hurt and Blighted, and whoever stood still through the ring snared.
func _pulse(b: Dictionary) -> void:
	b["warned"] = false
	b["next"] = float(b["next"]) + float(b["every"])
	var pos: Vector3 = b["pos"]
	var was_at: Dictionary = b["marks"]
	var dmg := base_k("pulse", 14.0, 1.98, 0.26)
	var a := aff()
	var lashed: Array = []
	for e in foes(pos, float(b["r"])):
		damage(e, dmg, pos, false)
		a.blight(e, id)
		var was = was_at.get(e.get_instance_id(), null)
		if was is Vector3 and (was as Vector3).distance_to(e.global_position) < val("still", 0.3):
			PvpStatus.send(hero.game, e, "snare", val("snare_s", 0.6) + hero.talent("bloom_snare"), 1.0)
			if e.pvp_pid <= 0 and e.pvp_obj <= 0:
				lashed.append(e)      # (a player's roots are his own game's, PvpStatusFx)
	hero.fx(id, "pulse", {"p": pos, "n": int(b["oid"]), "t": lashed})

## Where his bloom `oid` is (the server checks a blow's reach against it), or null.
func obj_pos(oid: int) -> Variant:
	for b in blooms:
		if int(b["oid"]) == oid and oid > 0:
			return b["pos"]
	return null

## Another player's blow on it (his own game counts them, through the server): everyone sees it flinch, and the last
## one breaks it on every game and in the rules. True if it was his bloom's.
func obj_hit(oid: int, _attacker: int) -> bool:
	if not owned.has(oid):
		return false
	var left: int = int(owned[oid][0]) - 1
	owned[oid][0] = left
	hero.fx(id, "obj", {"n": oid, "x": left})
	if left <= 0:
		owned.erase(oid)
		make("break", {"n": oid})
	return true

func clear() -> void:
	blooms.clear()
	owned.clear()
