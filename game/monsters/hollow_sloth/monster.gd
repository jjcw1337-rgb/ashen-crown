extends RefCounted
## The Hollow Sloths (fire, ice, storm): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["sloth_fire", "sloth_ice", "sloth_storm"]

## A four-legged body rolls onto its side when it dies.
const FALL := "side"

static func build_rig(kind: String, _variant: int) -> Node3D:
	var d: Dictionary = Data.ENEMIES[kind]
	return Sloth.build(str(d.get("variant", "")), (d["look"] as Dictionary).get("skin", Color(0.52, 0.56, 0.47)))

static func pose_rig(r: Node3D, st: Dictionary, height: float) -> bool:
	Sloth.pose(r, st, height)
	return true

static func model_paths(kind: String) -> PackedStringArray:
	return PackedStringArray([Sloth.GLB % str(Data.ENEMIES[kind].get("variant", ""))])

## Its elemental dress and its brain (Sloth, an instance: it keeps its own state).
static func on_setup(e: Enemy) -> void:
	Sloth.dress(e.rig, str(e.def.get("element", "")))
	e.sloth = Sloth.new(e)
	e.atk_style = "sloth_walk"
	e.add_to_group("sloth")

static func fx(e: Enemy, ev: String) -> bool:
	if not ev.begins_with("sloth"):
		return false
	Sloth.fx(e, ev)
	return true
