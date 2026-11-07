extends RefCounted
## The Forsaken Bear: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["bear"]

## A four-legged body rolls onto its side when it dies.
const FALL := "side"
const MOVES := ["bear_roar", "bear_maul"]

## The Meshy bear on its own skeleton (Bear).
static func build_rig(_kind: String, _variant: int) -> Node3D:
	return Bear.build() if Bear.ok() else null

static func pose_rig(r: Node3D, st: Dictionary, height: float) -> bool:
	Bear.pose(r, st, height)
	return true

static func model_paths(_kind: String) -> PackedStringArray:
	return PackedStringArray([Bear.GLB])

static func combat(e: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Variant:
	return BearBrain.combat(e, delta, hero, to, dist)

## It grazes and wanders its home ground, rearing to roar now and then.
static func idle(e: Enemy, delta: float) -> Variant:
	return BearBrain.idle(e, delta)

static func begin(e: Enemy, sp: String) -> void:
	BearBrain.begin(e, sp)

static func during(e: Enemy, a: float, hero: Node3D) -> void:
	BearBrain.during(e, a, hero)

static func impact(e: Enemy, hero: Node3D, dist: float) -> void:
	BearBrain.impact(e, hero, dist)

static func finish(e: Enemy) -> void:
	BearBrain.finish(e)

static func fx(e: Enemy, ev: String) -> bool:
	if not ev.begins_with("bear_"):
		return false
	BearFx.fx(e, ev)
	return true
