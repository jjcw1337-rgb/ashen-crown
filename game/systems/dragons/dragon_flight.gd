class_name DragonFlight
extends RefCounted
## A dragon off the ground. A dragon is far too long to tumble through the dodge roll (Dodge.pose hands it here): one
## whose body flies (Dragon.KINDS "flies": the Storm Wyvern, jj) takes to the air instead (a crouch, a leap up on its
## beating wings, a glide over and a landing that drops into its legs); the others lunge low, nose down, and rise out
## of it. Dragon.pose spreads and beats the wings and tucks the legs by the rig's "fly" meta (0..1 through a flight),
## which a skill's look may set too (the Storm Wyvern's Thunder Dive). Draws only.

const FLY_H := 2.3          # metres a dragon rises on its flight (in place of the roll)

## The roll this frame (s: 0..1 through it), after the body's pose.
static func roll(h: Hero, s: float) -> void:
	if not bool(Dragon.spec(h.cls).get("flies", false)):
		h.rig.rotation.x = -0.12 * sin(PI * s)
		h.rig.position = Vector3(0, -0.15 * sin(PI * s), 0)
		return
	var up := sin(PI * smoothstep(0.08, 0.92, s))
	var crouch := smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.08, 0.16, s)) + smoothstep(0.88, 0.96, s) * (1.0 - smoothstep(0.96, 1.0, s))
	h.rig.rotation.x = 0.18 * sin(PI * s) - 0.1 * up * (1.0 - s)
	h.rig.position = Vector3(0, FLY_H * up - 0.22 * crouch, 0)
	h.rig.set_meta("fly", s)
	if not h.has_meta("fly_dust") and s > 0.05:
		h.set_meta("fly_dust", 1)
		gust(h, 1.0)
	if s > 0.92 and int(h.get_meta("fly_dust", 0)) == 1:
		h.set_meta("fly_dust", 2)
		gust(h, 1.4)

## Its wings throwing the dust up (taking off, k 1; landing, k 1.4): a ring of dust and torn grass blown out, the
## grass flattened, a wingbeat, and a thump as it lands.
static func gust(h: Hero, k: float) -> void:
	var root: Node3D = h.game.world.fx_root
	var g := h.global_position
	ElementalFx._dust(root, g + Vector3(0, 0.15, 0), Color(0.5, 0.45, 0.38), 1.1 * k, 0.45, {"amount": int(6 * k),
		"life": 0.9, "explosive": 1.0, "shape": "ring", "r": 0.8, "r_in": 0.4, "dir": Vector3.UP, "spread": 15.0,
		"vel": [0.2, 0.5], "radial": [3.0 * k, 5.0 * k], "damping": [2.5, 3.5], "scale": [0.8, 1.2], "grow": [0.6, 1.8]})
	GrassField.impulse(g, 3.5 * k, 0.8, 0.45)
	SkillFx.snd(h, str(Dragon.spec(h.cls).get("flap", "wyvern_flap")), -2.0 if k > 1.2 else -4.0, 0.9 if k > 1.2 else 1.0)
	if k > 1.2:
		SkillFx.snd(h, h.cls + "_step", -1.0, 0.8)
		SkillFx.shake(h, 0.12)
