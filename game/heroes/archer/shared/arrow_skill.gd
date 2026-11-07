class_name ArrowSkill
extends Skill
## A skill of the archer's that looses arrows: his shot, Fire Arrow and the run's Scatter Shot, Blast Arrow, Glacial
## Shard and Storm Shot. `shoot` sends the "loose" event (every game's look flies the arrow it sees, ArcherArrowFx)
## and keeps the arrow's Missile here, which `update` flies to deal the hits. Each skill says what a hit does (`hit`)
## and what happens where its arrow ends (`ended`).

## The arrow it looses (ArrowFx.PRESETS: war, fire, frost, storm).
var kind := "war"
## Its arrows in flight (Missiles).
var shots: Array = []

## The aimed shots' cast: aim help on a foe near the pointer (Archer.assist), turn to it, draw.
func cast(aim: Vector3) -> void:
	hero.atk_aim = Archer.assist(hero, aim)
	hero._face(hero.atk_aim - hero.global_position)
	hero._start_attack("bow", id)

## Looses one toward `at`, turned by `yaw` radians, for `mult` of the weapon's blow.
func shoot(at: Vector3, pierce: bool, mult: float, yaw: float) -> Missile:
	var h := hero
	var from: Vector3 = h.global_position + Vector3(0, 1.35, 0)
	# the shot's own aim (taken from the pointer when the draw began), so walking on while he draws doesn't swing
	# it; a different point (Phoenix Quiver's) gets its own direction
	var dir := h.aim_dir()
	if not at.is_equal_approx(h.atk_aim):
		dir = h.dir_to(at)
	dir = dir.rotated(Vector3.UP, yaw)
	from += dir * 0.6
	# off the bow in his hand, where the nocked arrow lay
	var J: Dictionary = h.rig.get_meta("j")
	if J.has("at_hand_l") and h.weapon_node != null and is_instance_valid(h.weapon_node) and h.weapon_node.get_parent() == J.get("grip_bow_at"):
		from = (J["at_hand_l"] as Node3D).global_position + dir * 0.15
	h.fx(id, "loose", {"p": from, "d": dir, "k": kind, "x": pierce, "m": mult})
	var m := Missile.new(from, dir)
	m.speed = Archer.ARROW_SPEED
	m.left = Archer.FLIGHT
	m.pierce = pierce
	m.data = {"mult": mult}
	shots.append(m)
	return m

func update(delta: float) -> void:
	for m in shots.duplicate():
		m.step(hero.game, delta, func(e) -> bool: return not e.dead, func(e) -> void: hit(m, e))
		if m.done:
			shots.erase(m)
			ended(m)

## What a hit does: the blow, and the one he shoots is the one his beast goes for.
func hit(m: Missile, e) -> void:
	strike(m, e)
	hero.mark = e
	hero.mark_t = 6.0

## The blow itself: its share of the weapon's, Shatter's more on the chilled (archer.gd), a fire arrow searing the
## wound (Enemy.seared: fire, not a spray of blood).
func strike(m: Missile, e) -> void:
	e.seared = kind == "fire"
	hero._hit_enemy(e, float(m.data["mult"]) * Archer.shatter(hero, e), 0.25 if not m.pierce else 0.5, id)
	e.seared = false

## Where its flight ends (its range run out, a wall, or the foe a plain arrow stopped in).
func ended(_m: Missile) -> void:
	pass

func clear() -> void:
	shots.clear()
