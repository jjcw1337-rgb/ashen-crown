class_name CrushingCoilFx
extends RefCounted
## Crushing Coil's look (CrushingCoil, "crush"): the tail spin's crush: the ground cracked and thrown up
## (ElementalFx.ground_slam), cold mist rolled out over it, and a spray of frost off each foe crushed. Draws only.

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev["e"]) != "crush":
		return false
	var root: Node3D = h.game.world.fx_root
	var p: Vector3 = ev["p"]
	var r: float = float(ev.get("r", 4.2))
	ElementalFx.ground_slam(h.game, root, p, r)
	ElementalFx._dust(root, p + Vector3(0, 0.25, 0), FrostFx.MIST, 1.8, 0.5, {"amount": 12, "life": 1.3,
		"explosive": 1.0, "shape": "ring", "r": 1.0, "r_in": 0.5, "dir": Vector3.UP, "spread": 10.0, "vel": [0.1, 0.4],
		"radial": [4.0, 6.5], "damping": [2.5, 3.5], "scale": [0.9, 1.4], "grow": [0.6, 1.8]})
	for e in ev.get("t", []):
		if is_instance_valid(e):
			Fx.streaks(root, (e as Node3D).global_position + Vector3(0, 1.0, 0), [[0.0, Color(0.9, 0.96, 1.0)], [1.0, Color(0.5, 0.75, 1.0, 0.0)]], 8, 5.0, 0.04, 3.0, 0.35, true, -6.0)
	SkillFx.shake(h, 0.28)
	SkillFx.snd(h, "slam", -4.0, 0.8)
	return true
