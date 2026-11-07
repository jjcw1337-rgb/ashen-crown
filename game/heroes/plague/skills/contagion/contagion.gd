class_name Contagion
extends PlagueSkill
## Contagion (a run's skill, "p_spread"): the foe nearest the pointer is cursed: poisoned and Blighted, and every
## second its poison leaps to all near it; if it dies cursed the plague bursts out of it (Epidemic: the curse itself
## leaps on to the nearest). Its look: PlagueFx "curse" {p: his hand, q: where it struck, t: [the foe], x: seconds},
## "spread" {p: from, t: the foes it leapt to}, "burst" {p}. Codex "k": secs, reach (how near the pointer), every,
## spread_r and spread_s (each leap's reach and poison), burst_r and burst_s (the death burst's), leap_r (Epidemic).

var curses := {}      # instance id -> {e, t, tick}

func cast(aim: Vector3) -> void:
	hero.atk_aim = within_range(aim, 14.0)
	hero._start_attack("pd_flask", id)

func impact() -> void:
	make("curse", {"at": hero.atk_aim})

## Server: at the pointer, within its range of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "curse" and near_him(d.get("at"), float(Data.skill_def(id).get("range", 14.0)) + 4.0)

## The foe nearest the point is cursed (on the match server when his skills run there; it shows everyone).
func made(kind: String, d: Dictionary) -> void:
	if kind != "curse":
		return
	var at: Vector3 = d["at"]
	var best = null
	var bd := val("reach", 4.0)
	for e in foes(at, bd):
		var dist: float = Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length()
		if dist < bd:
			bd = dist
			best = e
	var from := hero.global_position + Vector3(0, 1.5, 0)
	if best == null:
		hero.fx(id, "curse", {"p": from, "q": at})
		return
	_curse(from, best)
	aff().blight(best, id)

func _curse(from: Vector3, e) -> void:
	var secs := val("secs", 6.0)
	hero.fx(id, "curse", {"p": from, "q": e.global_position, "t": [e], "x": secs})
	curses[e.get_instance_id()] = {"e": e, "t": secs, "tick": val("every", 1.0)}
	aff().poison(e, "toxic", secs)

func update(delta: float) -> void:
	for key in curses.keys():
		var c: Dictionary = curses[key]
		var e = c["e"]
		if not is_instance_valid(e):
			curses.erase(key)
			continue
		if e.dead:
			# it died cursed: the plague bursts out of it (Epidemic: the curse itself leaps to the nearest)
			curses.erase(key)
			_spread(e, val("burst_r", 5.0), val("burst_s", 4.0))
			if hero.talent("curse_jump") > 0.0:
				var next = null
				var nd := val("leap_r", 7.0)
				for o in foes(e.global_position, nd):
					var dist: float = o.global_position.distance_to(e.global_position)
					if not curses.has(o.get_instance_id()) and dist < nd:
						nd = dist
						next = o
				if next != null:
					_curse(e.global_position + Vector3(0, 1.0, 0), next)
			hero.fx(id, "burst", {"p": e.global_position})
			continue
		c["t"] = float(c["t"]) - delta
		c["tick"] = float(c["tick"]) - delta
		if float(c["tick"]) <= 0.0:
			c["tick"] = val("every", 1.0)
			_spread(e, val("spread_r", 4.0), val("spread_s", 2.5))
		if float(c["t"]) <= 0.0:
			curses.erase(key)

## Its poison leaps from `e` to everyone within `r`.
func _spread(e, r: float, secs: float) -> void:
	var to: Array = []
	var a := aff()
	for o in foes(e.global_position, r):
		if o == e:
			continue
		a.poison(o, "toxic", secs)
		to.append(o)
	if not to.is_empty():
		hero.fx(id, "spread", {"p": e.global_position, "t": to})

func clear() -> void:
	curses.clear()
