extends RefCounted
## The Arena's lion, and the Archer's Spirit Beast (the shared quadruped, game/systems/bodies/lion.gd): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["lion", "spirit_beast"]

## A four-legged body rolls onto its side when it dies.
const FALL := "side"
const MOVES := ["feral_lunge"]

static func combat(e: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Variant:
	return FeralBrain.combat(e, delta, hero, to, dist)

static func begin(e: Enemy, sp: String) -> void:
	FeralBrain.begin(e, sp)

static func during(e: Enemy, a: float, hero: Node3D) -> void:
	FeralBrain.during(e, a, hero)

static func impact(e: Enemy, hero: Node3D, dist: float) -> void:
	FeralBrain.impact(e, hero, dist)

static func finish(e: Enemy) -> void:
	FeralBrain.finish(e)

## The lion; the Spirit Beast is the Archer's wolf on the same body.
static func build_rig(kind: String, _variant: int) -> Node3D:
	if kind == "spirit_beast":
		return Lion.build(SpiritBeast.WOLF_GLB, 1.0) if ResourceLoader.exists(SpiritBeast.WOLF_GLB) else null
	return Lion.build() if Lion.ok() else null

static func pose_rig(r: Node3D, st: Dictionary, height: float) -> bool:
	Lion.pose(r, st, height)
	return true

static func model_paths(kind: String) -> PackedStringArray:
	return PackedStringArray([SpiritBeast.WOLF_GLB if kind == "spirit_beast" else Lion.GLB])

static func on_setup(e: Enemy) -> void:
	e.slot_a = randf_range(-1.6, 1.6)
	e.lunge_cd = randf_range(0.5, 2.5)
