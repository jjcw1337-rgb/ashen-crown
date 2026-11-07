extends RefCounted
## The Feral: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["feral"]

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

## One of its five models (Feral.variant_at: by where it stands, so a pack is mixed).
static func build_rig(_kind: String, variant: int) -> Node3D:
	return Feral.build(variant) if Feral.ok() else null

static func pose_rig(r: Node3D, st: Dictionary, height: float) -> bool:
	Feral.pose(r, st, height)
	return true

static func model_paths(_kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k in Feral.VARIANTS:
		out.append(Feral.GLB % (k + 1))
	return out

## Its place round the hero in the pack, and when it first lunges.
static func on_setup(e: Enemy) -> void:
	e.slot_a = randf_range(-1.6, 1.6)
	e.lunge_cd = randf_range(0.3, 3.0)

## Its rim light between hit flashes.
static func rest_overlay(_e: Enemy) -> Material:
	return Feral.rim_mat()

## Perched up its tree on a client's game.
static func net_lift(e: Enemy) -> float:
	return Feral.perch_pose(e.rig, e.atk_style, e.net_atk)
