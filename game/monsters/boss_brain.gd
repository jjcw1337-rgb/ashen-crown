class_name BossBrain
extends RefCounted
## A boss's brain (host side, like the Hollow Sloth's): Enemy._process hands it the frame (`vel = brain.update(...)`)
## and it plays timed moves. Every move is an atk_t / atk_dur / atk_style on the Enemy (so its pose plays on every
## peer), and everything seen is an Enemy fx event sent before it lands, so a player can read it and answer it.
## A boss names its moves (`moves`: [seconds, impact at 0..1, pose style]), picks one (`choose`), starts it
## (`start`: its cooldown and its warning) and lands it (`land`); `keep_at` is how close it fights.
## Used by Hrimgar (game/monsters/hrimgar/) and Mossbeard (game/monsters/mossbeard/).

var e: Enemy
var kind := ""
var move := ""
var cds := {}
var aim := Vector3.ZERO
var aim_dir := Vector3.FORWARD

func _init(en: Enemy) -> void:
	e = en
	kind = en.kind
	for m in moves():
		cds[m] = randf_range(1.0, 3.0)

# ---------------------------------------------------------------- what a boss fills in
func moves() -> Dictionary:
	return {}

func choose(_tgt: Hero, _dist: float) -> String:
	return ""

func start(_m: String, _warn: float) -> void:
	pass

func land(_tgt: Hero) -> void:
	pass

## How close it fights; closer than `back_off` it steps away (0: never).
func keep_at() -> float:
	return 2.4

func back_off() -> float:
	return 0.0

## The moves that keep turning to their target until they land (a swing, a bolt).
func tracks(_m: String) -> bool:
	return false

# ---------------------------------------------------------------- the shared loop
func _target() -> Hero:
	var best: Hero = null
	var bd := 1e9
	for h in e.game.all_heroes():
		if not is_instance_valid(h) or h.dead or h.get("phased") == true:
			continue
		var d: float = h.global_position.distance_to(e.global_position)
		if d < bd and d < 30.0:
			bd = d
			best = h
	return best

func heroes_in(at: Vector3, r: float) -> Array:
	return e.game.all_heroes().filter(func(h) -> bool: return is_instance_valid(h) and not h.dead and Vector2(h.global_position.x - at.x, h.global_position.z - at.z).length() < r)

func ready(m: String) -> bool:
	return float(cds.get(m, 0.0)) <= 0.0

## The frame: returns the velocity (Enemy._process moves it with the usual separation and collision).
func update(delta: float, _hero: Node3D, _to: Vector3, _dist: float, _gone: bool) -> Vector3:
	for m in cds:
		cds[m] = float(cds[m]) - delta
	var tgt := _target()
	if e.stun_t > 0.0:
		e.stun_t -= delta
		return Vector3.ZERO
	if move != "":
		if e.atk_t < 0.0:
			move = ""
		elif tgt != null:
			return _play(delta, tgt)
		else:
			e.atk_t = -1.0
			move = ""
	if tgt == null:
		e.aggro = false
		return Vector3.ZERO
	if not e.aggro:
		if tgt.global_position.distance_to(e.global_position) > float(e.def.get("aggro", 15.0)):
			return Vector3.ZERO
		e.aggro = true
		e.game.on_boss_aggro(e)
		e._fx("bear_roar")          # (its roar, and the intro card with it)
	var to := tgt.global_position - e.global_position
	to.y = 0
	var dist := to.length()
	var pick := choose(tgt, dist)
	if pick != "":
		_start(pick, tgt)
		return Vector3.ZERO
	if dist > keep_at():
		return to.normalized() * e.speed
	if dist < back_off():
		return -to.normalized() * e.speed * 0.8
	e._face(to)
	return Vector3.ZERO

func _start(m: String, tgt: Hero) -> void:
	move = m
	var spec: Array = moves()[m]
	e.atk_style = spec[2]
	e.atk_t = 0.0
	e.atk_dur = float(spec[0]) * (0.85 if e.life < e.max_life * 0.3 else 1.0)
	e.impact_done = false
	e.special = m
	aim = tgt.global_position
	aim_dir = tgt.global_position - e.global_position
	aim_dir.y = 0
	aim_dir = aim_dir.normalized() if aim_dir.length() > 0.01 else -e.rig.global_transform.basis.z
	e._face(aim_dir)
	start(m, e.atk_dur * float(spec[1]))

func _play(delta: float, tgt: Hero) -> Vector3:
	e.atk_t += delta
	var a := e.atk_t / e.atk_dur
	var hit_at: float = moves()[move][1]
	if tracks(move) and a < hit_at * 0.8:
		e._face(tgt.global_position - e.global_position)
		aim = tgt.global_position
	if not e.impact_done and a >= hit_at:
		e.impact_done = true
		land(tgt)
	if e.atk_t >= e.atk_dur:
		e.atk_t = -1.0
		e.special = ""
		move = ""
		e.cooldown = 0.4
	return Vector3.ZERO

## An fx event's numbers ("name:1.0,2.0,3.0" -> [1, 2, 3]), for a boss's look.
static func args_of(ev: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var parts := ev.split(":")
	if parts.size() > 1:
		for v in parts[1].split(","):
			if v.is_valid_float():
				out.append(float(v))
	return out
