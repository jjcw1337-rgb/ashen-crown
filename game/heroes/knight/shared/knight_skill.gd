class_name KnightSkill
extends Skill
## A skill of the Knight's (docs/content/skills.md): what all of his share. His stuns reach a monster at once and a
## player through the server (PvpStatus "stagger": checked there, with diminishing returns). His leaps (Holy Slam,
## Last Rites) carry him with the attack's lunge (Hero.atk_leap) and land the blade `reach` ahead of him.

## This leap's blade: how far ahead of him it lands (his own game; set by the cast).
var reach := 0.0

## Stuns a foe: a monster here, a player through the server.
func stun(e, secs: float) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "stagger", secs)
	else:
		e.stun(secs)

## A leap to `to` (on the ground, at most `most` away): the blade lands at most `blade` ahead of him, and the attack's
## lunge carries him the rest (Hero._swipe_lunge). Call after Hero._start_attack.
func leap(to: Vector3, most: float, blade: float) -> void:
	var d := (to - hero.global_position) * Vector3(1, 0, 1)
	var dist := minf(d.length(), most)
	reach = minf(dist, blade)
	hero.atk_leap = dist - reach

## Where the blade comes down on the impact frame: `reach` ahead along the aim, on the ground.
func blade_at() -> Vector3:
	var at := hero.global_position + hero.aim_dir() * reach
	at.y = hero.game.world.height_at(at.x, at.z)
	return at

## Server: a point a skill of his names is near where the server has him (within `most` metres, a little more for the
## lag between them).
func near_him(p, most: float) -> bool:
	return p is Vector3 and (p as Vector3).distance_to(hero.global_position) <= most + 4.0
