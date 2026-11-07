class_name ShadowStepFx
extends RefCounted
## Shadowstep's look on every game (ShadowStep is its rules). Draws only:
##  "blink" {p: from, q: to}: an afterimage stays where he was, he goes out in mist and comes back in it at the
##    landing, a trail of fainter shades between, and the shade he left caves in its "shade_s" later;
##  "strike" {y: his yaw, x: anything near}: the spin's claws tearing all the way round.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match str(ev["e"]):
		"cast":
			pass
		"blink":
			var from: Vector3 = ev["p"]
			var to: Vector3 = ev["q"]
			SpiritFx.afterimage(h.rig, root, VIOLET, 0.55, 0.3)
			mist_out(root, from)
			Sfx.play_at("shade_out", from, -2.0)
			# a trail of fainter shades along the way
			var dist := from.distance_to(to)
			var steps := clampi(int(dist / 1.6), 1, 5)
			for i in range(1, steps):
				var p := from.lerp(to, float(i) / steps)
				SpiritFx.burst(root, p + Vector3(0, 1.0, 0), Color(0.3, 0.26, 0.42, 0.55), 8, 1.2, 0.35, 0.5, false, 0.8)
			mist_in(root, to)
			SkillFx.snd(h, "shade_in", -2.0)
			SkillFx.shake(h, 0.15)
			# the shade left behind caves in a moment later (when ShadowStep's shade strikes)
			Fx.later(root, Skill.num("step", "shade_s", 0.45), func():
				shade_collapse(root, from)
				Sfx.play_at("shade_implode", from, -1.0))
		"strike":
			var yaw: float = float(ev["y"])
			SpiritFx.rake(root, pos, yaw, 2.6, true)
			SpiritFx.rake(root, pos, yaw + PI, 2.6, false)
			SkillFx.snd(h, "reap_swing", -3.0, 1.1)
			SkillFx.shake(h, 0.22 if bool(ev.get("x", false)) else 0.1)
		_:
			return false
	return true

## He comes apart into mist: dark smoke curling up off him and a cold flash in it.
static func mist_out(root: Node3D, pos: Vector3) -> void:
	SpiritFx.burst(root, pos + Vector3(0, 0.9, 0), Color(0.3, 0.26, 0.42, 0.7), 34, 2.0, 0.4, 0.9, false, 0.9, 120.0)
	SpiritFx.burst(root, pos + Vector3(0, 1.0, 0), SPIRIT, 20, 2.5, 0.09, 0.5, true, 0.0)
	Fx.flash(root, pos + Vector3(0, 1.1, 0), VIOLET, 2.2, 0.3, 5.0)

## He re-forms: mist drawn in off the ground into the body, a ring of spirit-light, a flash.
static func mist_in(root: Node3D, pos: Vector3) -> void:
	SpiritFx.ring(root, pos, 2.2, SPIRIT, 0.32, 0.12)
	var p := SpiritFx.burst(root, pos + Vector3(0, 0.15, 0), SPIRIT, 30, 4.0, 0.12, 0.6, true, 3.5, 30.0)
	p.position = pos + Vector3(0, 0.15, 0)
	SpiritFx.burst(root, pos + Vector3(0, 0.7, 0), Color(0.3, 0.26, 0.42, 0.6), 18, 1.4, 0.4, 0.7, false, 1.2)

## The shade he left: a dark echo of his shape (an afterimage) standing where he was, which caves in on itself.
static func shade_collapse(root: Node3D, pos: Vector3) -> void:
	SpiritFx.ring(root, pos, 2.6, VIOLET, 0.35, 0.3)
	SpiritFx.burst(root, pos + Vector3(0, 0.8, 0), VIOLET, 28, 5.0, 0.12, 0.45, true, 0.0)
	SpiritFx.burst(root, pos + Vector3(0, 0.9, 0), Color(0.3, 0.26, 0.42, 0.7), 16, 2.5, 0.45, 0.7, false, 0.6)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), VIOLET, 3.0, 0.3, 6.0)
