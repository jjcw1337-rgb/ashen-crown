class_name FaultOfThePit
extends DemonSkill
## Fault of the Pit (R, "cslam", area control; a main skill the Path of Exile way: no cooldown, a "use" time and a
## measured "power"): the slam splits the ground in a line `len` long, `ahead` in front of him, across his aim; after
## `warn` it erupts (hurt, thrown up, Branded) and stays molten for `life` s (Lava Trail: longer), burning and slowing
## whoever crosses it. Its look: FaultOfThePitFx. Codex "k": dmg (% of the weapon's blow), magma (% of his magma),
## ahead, len and w (metres), warn and life (seconds), knock, knockup_s (monsters; players: its "pvp" knockup), tick
## (seconds between the molten ground's burns), burn (% of his magma each), slow (% slower; players: its "pvp" slow).

## The fault its rules keep (one at a time: a new slam's replaces it): {a, b, t, erupted, life, tick}.
var fault := {}

func cast(_aim: Vector3) -> void:
	start("cslam")

func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

## The slam: the line opens (seen at once), and its rules keep it.
func impact() -> void:
	var h := hero
	var fwd := h.aim_dir()
	var side := fwd.cross(Vector3.UP).normalized()
	var mid := h.global_position + fwd * val("ahead", 3.0)
	var half := val("len", 7.0) * 0.5
	var a: Vector3 = mid - side * half
	var b: Vector3 = mid + side * half
	a.y = h.game.world.height_at(a.x, a.z)
	b.y = h.game.world.height_at(b.x, b.z)
	mid.y = h.game.world.height_at(mid.x, mid.z)
	var life := _life()
	h.fx(id, "impact", {"p": h.global_position + fwd * 1.1, "q": mid, "ps": PackedVector3Array([a, b]), "y": h.rig.global_rotation.y,
		"x": val("warn", 0.4), "r": life})
	make("fault", {"a": a, "b": b, "x": life})
	SkillFx.hitstop(h, 0.03)

func _life() -> float:
	return val("life", 4.0) + hero.talent("trail_dur")

## Server: a fault in front of where it has him, no longer and no longer-lived than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "fault" or not (d.get("a") is Vector3 and d.get("b") is Vector3):
		return false
	var a: Vector3 = d["a"]
	var b: Vector3 = d["b"]
	var reach := val("ahead", 3.0) + val("len", 7.0) * 0.5 + 4.0
	if a.distance_to(hero.global_position) > reach or b.distance_to(hero.global_position) > reach:
		return false
	if Vector2(b.x - a.x, b.z - a.z).length() > val("len", 7.0) + 0.5:
		return false
	d["x"] = clampf(float(d.get("x", 0.0)), 0.0, _life())
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind == "fault":
		fault = {"a": d["a"], "b": d["b"], "t": 0.0, "erupted": false, "life": float(d["x"]), "tick": 0.0}

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()

func step(delta: float) -> void:
	if not fault.is_empty():
		_burn(delta)

## The warning, the eruption, then the molten ground's ticks until it cools.
func _burn(delta: float) -> void:
	var h := hero
	var f := fault
	f["t"] = float(f["t"]) + delta
	var a: Vector3 = f["a"]
	var b: Vector3 = f["b"]
	var half := val("len", 7.0) * 0.5
	var w := val("w", 1.4)
	if not bool(f["erupted"]):
		if float(f["t"]) < val("warn", 0.4):
			return
		f["erupted"] = true
		var struck := []
		for e in h.game.enemies_near((a + b) * 0.5, half + 1.5):
			if foe(e) and _seg_dist(e.global_position, a, b) - e.radius <= w * 0.5:
				struck.append(e)
				hit(e, val("dmg", 140.0) / 100.0, val("knock", 0.6), magma(h, val("magma", 70.0) / 100.0))
				if is_instance_valid(e) and not e.dead:
					cc(e, "knockup", val("knockup_s", 0.7), pvp("knockup", 0.35))
					Demon.brands(h).mark(e)
		h.fx(id, "erupt", {"ps": PackedVector3Array([a, b]), "t": struck.filter(func(x) -> bool: return not PvpStatus.is_player(x)),
			"x": not struck.is_empty()})
		f["tick"] = val("tick", 0.4)
		return
	var left: float = float(f["life"]) - (float(f["t"]) - val("warn", 0.4))
	if left <= 0.0:
		fault = {}
		return
	f["tick"] = float(f["tick"]) - delta
	if float(f["tick"]) > 0.0:
		return
	f["tick"] = val("tick", 0.4)
	for e in h.game.enemies_near((a + b) * 0.5, half + 1.5):
		if foe(e) and _seg_dist(e.global_position, a, b) - e.radius * 0.6 <= w * 0.5:
			var dmg: float = magma(h, val("burn", 22.0) / 100.0) * h.buff_mult() * h.dmg_mult(id) * (pvp("dmg", 1.0) if PvpStatus.is_player(e) else 1.0)
			e.take_damage(0.0, dmg, e.global_position, 0.0, false)
			if is_instance_valid(e) and not e.dead:
				var slow_s := val("tick", 0.4) + 0.35
				cc(e, "slow", slow_s, slow_s, {"k": pvp("slow", val("slow", 35.0) / 100.0) if PvpStatus.is_player(e) else val("slow", 35.0) / 100.0})

func clear() -> void:
	fault = {}
