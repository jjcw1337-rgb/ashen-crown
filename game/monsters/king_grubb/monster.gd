extends RefCounted
## King Grubb the Gilded (boss) and his Gold Grabbers: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["goblin_king", "grabber"]
## How its body carries itself (Anim's personalities).
const PERSONALITY := "goblin"

## His fight (Hoard): bombs, scooped gold, staggering, cackling.
const MOVES := ["bomb", "scoop", "burst", "cackle"]

## The goblins' sculpted bodies (Goblin, the def's "model").
static func build_rig(kind: String, _variant: int) -> Node3D:
	return Goblin.build(str(Data.ENEMIES[kind]["model"]))

## Once he stands where he lives, his fight (Hoard) begins.
static func on_placed(e: Enemy) -> void:
	if e.def.get("hoard", false):
		e.hoard = Hoard.new(e)
		e.hoard.call_deferred("start")

static func begin(e: Enemy, sp: String) -> void:
	Hoard.begin(e, sp)

static func during(e: Enemy, a: float, hero: Node3D) -> void:
	Hoard.during(e, a, hero)

static func impact(e: Enemy, hero: Node3D, dist: float) -> void:
	Hoard.impact(e, hero, dist)

static func finish(e: Enemy) -> void:
	Hoard.finish(e)

## The king shakes the ground as he walks.
static func heavy_steps(e: Enemy) -> bool:
	return e.boss

## Knees buckle, then he topples forward onto his belly with a bounce (the king shakes the ground).
static func fall(e: Enemy, _f: float, delta: float) -> void:
	e.rig.rotation.x = -Anim.kf(e.dead_t, [[0.0, 0.0], [0.5, 0.08], [1.1, 1.3], [1.25, 1.18], [1.4, 1.28]])
	if e.dead_t > 1.1 and e.dead_t - delta <= 1.1 and e.boss:
		e.game.add_shake(0.5)
		Fx.burst(e.game.world.fx_root, e.global_position - e.rig.global_transform.basis.z * 1.5, Color(0.4, 0.35, 0.3, 0.8), 40, 4.0, 0.3, 0.9, false, -3.0, 80.0)
