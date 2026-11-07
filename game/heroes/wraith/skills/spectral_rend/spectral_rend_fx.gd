class_name SpectralRendFx
extends RefCounted
## Spectral Rend's look on every game (SpectralRend is its rules; the claws growing on his hands are SpiritFx's).
## Draws only:
##  "rake" {y: his yaw, l: the left claw, x: all the way round}: three thin crescents tearing across in front;
##  "souls" {ps: where they were torn out}: a soul out of each foe the rake struck, flying back to him.

const PALE := SpiritFx.PALE

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match str(ev["e"]):
		"cast":
			pass
		"rake":
			var yaw: float = float(ev["y"])
			var left: bool = bool(ev.get("l", false))
			SpiritFx.rake(root, pos, yaw, 3.0, left)
			if bool(ev.get("x", false)):
				SpiritFx.rake(root, pos, yaw + PI, 3.0, not left)
			if left:
				SkillFx.snd(h, "swing_light", -4.0, 0.9)
			SkillFx.shake(h, 0.05)
		"souls":
			var ps: PackedVector3Array = ev["ps"]
			for i in ps.size():
				Fx.sparks(root, ps[i], PALE)
				SpiritFx.soul_wisp(root, ps[i], h, WraithSkill.wisp_time(i), -9.0)
			# (the rake that tore them out lands harder: 0.14 in all)
			SkillFx.shake(h, 0.09)
		_:
			return false
	return true
