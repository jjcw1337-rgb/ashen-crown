class_name GaleWingsFx
extends RefCounted
## Gale Wings' look (GaleWings, "gust"): one great wingbeat: dust driven out in a cone, the grass flattened, a streak
## of wind off each foe struck. Draws only.

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev["e"]) != "gust":
		return false
	var root: Node3D = h.game.world.fx_root
	var p: Vector3 = ev["p"]
	var d: Vector3 = ev["d"]
	var r: float = float(ev.get("r", 6.5))
	DragonFlight.gust(h, 2.0)
	SkillFx.snd(h, "gale_gust", 0.0)
	var tr := InfernalFx.tier(h.game)
	ElementalFx._dust(root, p + d * 1.2 + Vector3(0, 0.4, 0), Color(0.62, 0.6, 0.55), 1.5, 0.55, {"amount": [8, 12, 16, 22][tr],
		"life": 1.1, "explosive": 1.0, "shape": "point", "dir": d + Vector3(0, 0.12, 0), "spread": 38.0, "vel": [r * 1.4, r * 2.2],
		"damping": [2.5, 3.5], "scale": [0.8, 1.3], "grow": [0.8, 2.2]})
	GrassField.impulse(p + d * r * 0.5, r * 0.6, 1.0, 0.5)
	for e in ev.get("t", []):
		if is_instance_valid(e):
			Fx.streaks(root, (e as Node3D).global_position + Vector3(0, 1.2, 0), [[0.0, Color(0.95, 0.95, 0.9)], [1.0, Color(0.6, 0.6, 0.55, 0.0)]], 6, 6.0, 0.03, 4.0, 0.3, true, -3.0, 50.0, ev["d"])
	SkillFx.shake(h, 0.2)
	return true
