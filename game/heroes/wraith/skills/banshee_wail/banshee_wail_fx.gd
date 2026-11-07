class_name BansheeWailFx
extends RefCounted
## Banshee Wail's look on every game (BansheeWail is its rules). Draws only:
##  "impact" {r: its reach}: the scream: rings of soul-mist and shadow rolling out from him;
##  "struck" {t: the foes it caught}: a pale burst on each.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"impact":
			var r: float = float(ev.get("r", Skill.num("r_wail", "radius", 6.0)))
			var me: Vector3 = h.global_position
			SpiritFx.ring(root, me, r, SPIRIT, 0.6, 0.6)
			SpiritFx.ring(root, me, r * 0.6, VIOLET, 0.45, 0.4)
			SpiritFx.burst(root, me + Vector3(0, 1.4, 0), Color(0.3, 0.26, 0.42, 0.7), 40, 6.0, 0.3, 0.8, false, 0.4, 100.0)
			SpiritFx.pulse(root, me + Vector3(0, 1.3, 0), SPIRIT, r * 0.8, 0.4)
			SkillFx.snd(h, "banshee_wail", -1.0)
			SkillFx.shake(h, 0.35)
		"struck":
			for e in ev.get("t", []):
				if is_instance_valid(e):
					SpiritFx.burst(root, (e as Node3D).global_position + Vector3(0, 1.4, 0), PALE, 10, 2.0, 0.08, 0.5, true, 1.0)
		_:
			return false
	return true
