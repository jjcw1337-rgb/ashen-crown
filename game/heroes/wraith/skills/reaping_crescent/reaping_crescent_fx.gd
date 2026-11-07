class_name ReapingCrescentFx
extends RefCounted
## Reaping Crescent's look on every game (ReapingCrescent is its rules). Draws only:
##  "impact" {y: his yaw}: the great crescent of soul-fire sweeping out in front of him;
##  "reaped" {y, n: how many it reaped}: a soul out of each, flying back to him.

const SPIRIT := SpiritFx.SPIRIT

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var yaw: float = float(ev.get("y", 0.0))
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))
	match str(ev["e"]):
		"impact":
			var r := Skill.num("r_reap", "radius", 5.0)
			SpiritFx.rake(root, h.global_position, yaw, r, true)
			SpiritFx.rake(root, h.global_position, yaw, r * 0.85, false)
			SpiritFx.ring(root, h.global_position + dir * 2.0, 2.4, SPIRIT, 0.35)
			SkillFx.shake(h, 0.2)
		"reaped":
			for i in int(ev.get("n", 0)):
				SpiritFx.soul_wisp(root, h.global_position + dir * 3.0 + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5)), h, 0.4 + i * 0.05)
		_:
			return false
	return true
