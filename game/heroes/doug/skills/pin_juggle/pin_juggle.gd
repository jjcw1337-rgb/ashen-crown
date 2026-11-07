class_name PinJuggle
extends Skill
## Pin Juggle ("juggle"): flaming juggling pins thrown one after another at the cursor; each lands on the foe nearest
## it and bounces on to the next nearest, and the next. Its rules throw them (here, or on the match server's copy of
## him) and every game sees each pin's path ("pin": PinJuggleFx). Codex "k": dmg (% of the weapon's blow, each pin on
## each foe), pins (how many), gap (seconds between throws), bounces (foes each bounces on to), reach (metres from the
## pointer to its first foe), bounce_r (metres to the next).

var aim := Vector3.ZERO
## Its rules' pins still to throw: {"t": seconds to the throw, "at": the point aimed at}.
var pins: Array = []

func cast(at: Vector3) -> void:
	aim = at
	hero._start_attack("juggle", id)

func impact() -> void:
	make("pins", {"at": aim})

func made(kind: String, d: Dictionary) -> void:
	if kind != "pins":
		return
	for i in int(val("pins", 5.0)):
		pins.append({"t": i * val("gap", 0.14), "at": d["at"]})

## Server: pins at a point within its range of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "pins" and d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= float(Data.skill_def(id).get("range", 12.0)) + 4.0

func update(delta: float) -> void:
	for i in range(pins.size() - 1, -1, -1):
		var pin: Dictionary = pins[i]
		pin["t"] = float(pin["t"]) - delta
		if float(pin["t"]) <= 0.0:
			pins.remove_at(i)
			_throw(pin["at"])

## One pin: on the foe nearest the point, then bouncing on to the nearest it hasn't struck.
func _throw(at: Vector3) -> void:
	var h := hero
	var reach := val("reach", 3.5)
	var first = null
	var bd := reach
	for e in h.game.enemies_near(at, reach + 0.5):
		if not foe(e):
			continue
		var d: float = e.global_position.distance_to(at)
		if d < bd:
			bd = d
			first = e
	var ps := PackedVector3Array([h.global_position + Vector3(0, 1.3, 0)])
	var hit := []
	if first == null:
		ps.append(at)
	else:
		var cur = first
		var jump := val("bounce_r", 6.0)
		for b in int(val("bounces", 2.0)) + 1:
			if cur == null:
				break
			hit.append(cur)
			ps.append(cur.global_position + Vector3(0, 1.0, 0))
			h._hit_enemy(cur, val("dmg", 60.0) / 100.0, 0.0, id)
			var nxt = null
			var nd := jump
			for e in h.game.enemies_near(cur.global_position, jump):
				if hit.has(e) or not foe(e):
					continue
				var d2: float = e.global_position.distance_to(cur.global_position)
				if d2 < nd:
					nd = d2
					nxt = e
			cur = nxt
	h.fx(id, "pin", {"ps": ps, "t": hit})

func died() -> void:
	pins.clear()

func clear() -> void:
	pins.clear()
