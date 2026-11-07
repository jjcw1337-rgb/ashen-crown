class_name StormArcFx
extends RefCounted
## Storm Arc's look (StormArc), drawn with the shared lightning (ArcFx): as it rears ("cast"), the plasma flaring in its
## jaws and its wings crackling along their bones; the bolt down the chain ("impact": the path its rules found).
## Draws only.

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			ArcFx.charge(h, DragonKit.jaws(h), WyvernFx.ARC, 0.45)
			_wing_crackle(h)
		"impact":
			ArcFx.chain(h, root, ev["ps"], ev["d"], WyvernFx.ARC, 1.25)
			SkillFx.shake(h, 0.12)
		_:
			return false
	return true

## The wings crackling as it rears: arcs running out along each wing's bones.
static func _wing_crackle(h: Hero) -> void:
	var sk := h.rig.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	var s := sk[0] as Skeleton3D
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	for side in ["L", "R"]:
		var chain_b: Array = []
		for nm in ["arm_%s_0" % side, "arm_%s_1" % side, "fing0_%s_0" % side, "fing0_%s_1" % side, "fing1_%s_1" % side]:
			var i := s.find_bone(nm)
			if i >= 0:
				chain_b.append(s.global_transform * s.get_bone_global_pose(i).origin)
		for k in chain_b.size() - 1:
			ElementalFx.bolt(root, chain_b[k], chain_b[k + 1], 0.3, 0.035, tr, WyvernFx.ARC[0], WyvernFx.ARC[1])
