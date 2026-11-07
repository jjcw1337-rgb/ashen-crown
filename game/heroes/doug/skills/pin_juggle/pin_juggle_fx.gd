class_name PinJuggleFx
extends RefCounted
## What a juggling pin looks like (Pin Juggle, DougFx hands its events here): "pin" flies a burning Meshy pin
## (pin.glb) along its path, from his hands to each foe it bounced on, a spark of fire at each. Draws only.

const PIN := "res://game/heroes/doug/skills/pin_juggle/pin.glb"

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev.get("e", "")) != "pin":
		return false
	var root: Node3D = h.game.world.fx_root
	var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
	for i in ps.size() - 1:
		DougFx.fly(root, PIN, ps[i], ps[i + 1], 0.16, 0.6, 0.35, 0.16 * i, true)
		Fx.burst(root, ps[i + 1], Color(1.0, 0.55, 0.15), 10, 2.0, 0.08, 0.35, true, 0.0)
	SkillFx.snd(h, "fireball", -8.0, 1.5)
	return true
