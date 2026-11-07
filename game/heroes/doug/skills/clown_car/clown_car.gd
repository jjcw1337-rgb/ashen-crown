class_name ClownCar
extends Skill
## Clown Car ("car", his ultimate): a tiny clown car screeches in and he drives it for a few seconds, fast and
## unstoppable (his own game: Doug.pace, Doug.unstoppable), ramming whatever he meets; then it bursts and mini clowns
## sprint at the nearest foes and pie them (PieSkill.pie_face). Its rules ram and send the clowns from where they have
## him (here, or on the match server's copy of him). Its look: ClownCarFx. Codex "k": drive_s (seconds he drives),
## speed (times his pace), dmg (% of the weapon's blow, each ram), knock, ram_r (metres), ram_gap (seconds before the
## same foe is rammed again), minis (how many clowns), mini_dmg (% of the weapon's blow, each pie), mini_r (metres they
## look for foes in).

## His own game: seconds left at the wheel.
var drive_t := 0.0
## Its rules' rides: {"t": seconds left, "rammed": foe instance id -> when it was last rammed}.
var rides: Array = []

func can_cast(_aim: Vector3) -> bool:
	return not driving()

func cast(_aim: Vector3) -> void:
	hero._start_attack("car", id)

func impact() -> void:
	drive_t = val("drive_s", 5.0)
	hero.fx(id, "start", {"p": hero.global_position, "x": drive_t})
	make("car", {})

func made(kind: String, _d: Dictionary) -> void:
	if kind == "car":
		rides.append({"t": val("drive_s", 5.0), "rammed": {}})

## Server: one ride at a time.
func server_ok(kind: String, _d: Dictionary) -> bool:
	return kind == "car" and rides.is_empty()

func driving() -> bool:
	return drive_t > 0.0

## His pace at the wheel.
func speed() -> float:
	return val("speed", 2.3) if driving() else 1.0

func update(delta: float) -> void:
	var h := hero
	if drive_t > 0.0 and not h.puppet:
		drive_t -= delta
	for r in rides.duplicate():
		r["t"] = float(r["t"]) - delta
		for e in h.game.enemies_near(h.global_position, val("ram_r", 1.6)):
			if not foe(e):
				continue
			var key := str(e.get_instance_id())
			var now := Time.get_ticks_msec() / 1000.0
			if now - float((r["rammed"] as Dictionary).get(key, -99.0)) > val("ram_gap", 0.8):
				r["rammed"][key] = now
				h._hit_enemy(e, val("dmg", 140.0) / 100.0, val("knock", 4.0), id)
				h.fx(id, "ram", {"p": e.global_position})
		if float(r["t"]) <= 0.0:
			rides.erase(r)
			_minis()

## The car bursts: a mini clown for each of the nearest foes, a pie in its face.
func _minis() -> void:
	var h := hero
	var at := h.global_position
	var foes: Array = h.game.enemies_near(at, val("mini_r", 12.0)).filter(func(e) -> bool: return foe(e))
	foes.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	var tgt := foes.slice(0, int(val("minis", 6.0)))
	h.fx(id, "burst", {"p": at, "t": tgt})
	for e in tgt:
		h._hit_enemy(e, val("mini_dmg", 80.0) / 100.0, 0.0, id)
		PieSkill.pie_face(h, e)

func died() -> void:
	drive_t = 0.0
	rides.clear()

func clear() -> void:
	drive_t = 0.0
	rides.clear()
