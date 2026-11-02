class_name BotBrain
extends RefCounted
## A computer player for a hero (the admins' sandbox, Sandbox; tools/pvp_sim.gd): it plays the hero's real skills and
## weapon the way a decent player would. Every `react` seconds it picks the nearest foe (a player over a monster
## when one is near), drinks a potion when low, rolls out of a melee foe's reach when hurt, uses the best skill that
## is ready, affordable and in reach (leading a moving foe a little, aiming off by its `accuracy`), and otherwise
## fights with its weapon: melee classes close in and hold the combo, ranged ones keep their distance, backing off
## and circling when a foe gets close. Everything goes through the same calls the mouse and keys use (Hero.use_skill,
## cmd_target, free_attack, Dodge.start, drink), so the numbers are the game's.

var react := 0.18           # seconds between decisions
var accuracy := 0.85        # 0..1: how often it uses a skill it could, and how close it aims
var focus := ""             # a hero's name to go for first ("" = the nearest)
var target: Enemy = null
var _think := 0.0
var _dodge_cd := 0.0
var _pot_cd := 0.0
var _last := Vector3.INF
var _vel := Vector3.ZERO
var _side := 1.0

## One frame of play. `pick` (Callable: hero -> Enemy) finds what to fight.
func think(h: Hero, pick: Callable, delta: float) -> void:
	Hero.striker = h
	_dodge_cd -= delta
	_pot_cd -= delta
	_think -= delta
	if h.dead:
		h.bot_hold = false
		return
	if target != null and is_instance_valid(target):
		var p: Vector3 = target.global_position
		if _last != Vector3.INF:
			_vel = _vel.lerp((p - _last) / maxf(delta, 0.001), clampf(delta * 6.0, 0.0, 1.0))
		_last = p
	if _think > 0.0:
		return
	_think = react * randf_range(0.7, 1.3)
	if h.life < h.max_life * 0.4 and _pot_cd <= 0.0:
		for i in 4:
			var it = h.belt[i]
			if it is Dictionary and Data.BASES[it["base"]].has("heal"):
				h.drink(i)
				_pot_cd = 5.0
				break
	var t: Enemy = pick.call(h)
	if t != target:
		_last = Vector3.INF
		_vel = Vector3.ZERO
	target = t
	if target == null:
		h.bot_hold = false
		return
	var tp: Vector3 = target.global_position
	var to := tp - h.global_position
	to.y = 0.0
	var d := to.length()
	var ranged := h.reach() > 4.0
	# hurt with a foe at arm's length: roll out of it
	if _dodge_cd <= 0.0 and d < 3.0 and h.life < h.max_life * 0.55 and randf() < 0.5:
		var away := (-to).normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9))
		if Dodge.start(h, away):
			_dodge_cd = 4.0
			return
	if not h.can_act():
		return
	var lead := tp + _vel * 0.35
	var err := (1.0 - accuracy) * 2.5
	var aim := lead + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
	if randf() < accuracy and _skill(h, d, aim):
		return
	if ranged:
		h.bot_hold = false
		if d < 4.5:
			# too close: back off and to the side
			if randf() < 0.15:
				_side = -_side
			var back := (-to).normalized() * 4.0 + to.normalized().cross(Vector3.UP) * _side * 2.5
			h.cmd_move(h.global_position + back)
		elif d > h.reach() - 0.5:
			if h.target != target:
				h.cmd_target(target)
		else:
			h.target = null
			h.moving = false
			h._face(aim - h.global_position)
			h.free_attack(aim)
	else:
		h.bot_hold = true
		if h.target != target:
			h.cmd_target(target)

## The best skill to use now (the deepest first: ultimates, then the rest), if any. True when one went off.
func _skill(h: Hero, d: float, aim: Vector3) -> bool:
	var list: Array = h.skill_list().duplicate()
	list.reverse()
	for s in list:
		var id: String = s["id"]
		if id in ["attack", "block"] or Data.skill_locked(s, h.level) or float(h.cds.get(id, 0.0)) > 0.0 or h.mana < h.skill_cost(id):
			continue
		var kind := str(s.get("aim", "facing"))
		var rng := float(s.get("range", 0.0))
		if kind == "self" and d > 7.0:
			continue
		if kind == "point" and d > maxf(rng, 12.0) + 1.0:
			continue
		if kind == "facing" and rng > 0.0 and d > rng + 1.0:
			continue
		if kind == "facing" and rng <= 0.0 and d > maxf(h.reach() + 1.5, 6.0):
			continue
		# a skill with no cooldown (a spender like Brimstone Hurl) is mixed in with the weapon, not spammed, and
		# never spends the mana a cooldown skill needs; a long cast at a foe on the move waits for a better moment
		if float(s.get("cd", 0.0)) <= 0.0:
			if randf() > 0.4 or h.mana - h.skill_cost(id) < h.max_mana * 0.3:
				continue
			if float(s.get("use", 0.0)) > 1.2 and _vel.length() > 2.0:
				continue
		h._face(aim - h.global_position)
		if h.use_skill(id, h.skill_aim(id, aim)):
			return true
	return false
