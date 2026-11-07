class_name AegisFx
extends RefCounted
## Aegis's look (Aegis's events): "impact" the seal under him, a shaft of light and a ring out to the taunt, and the
## ward's glow round him while it holds; "burst" {p, x: what it soaked} a ring of holy fire and a ripple out to the
## burst's reach, harder the more it soaked, and the glow gone.

## How much soaked makes the biggest burst (the look's scale only).
const FULL := 120.0
const WARD := "aegis_ward"

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var r := Skill.num("k_aegis", "radius", 5.0)
	match str(ev["e"]):
		"cast":
			pass
		"impact":
			HolyFx.battle_cry(h, root, h.global_position, r)
			var ward := Fx.aura(h, Color(1.0, 0.9, 0.55), 22, 0.15, 0.08, 1.0, 0.2, 0.8, 50.0, Vector3(0, 1.0, 0))
			ward.name = WARD
			Fx._free_later(ward, Skill.num("k_aegis", "secs", 5.0) + 1.0)
			SkillFx.snd(h, "aegis_raise", -2.0)
		"burst":
			var bp: Vector3 = ev["p"]
			var big := clampf(float(ev.get("x", 0.0)) / FULL, 0.3, 1.0)
			HolyFx.seal(root, bp, 2.0, 0.1, 0.7, 0.6 + big)
			HolyFx.sunburst(root, bp + Vector3(0, 1.2, 0), 1.8 + big, 0.3, 1.6 + big, 1.0)
			HolyFx.fire_ring(root, bp, 0.5, r, 0.9 + big, 0.4)
			HolyFx.shockwave(root, h.game, bp, r + 0.8, 0.4)
			var wf := h.get_node_or_null(WARD)
			if wf != null:
				wf.queue_free()
			Sfx.play_at("aegis_burst", bp, -1.0)
			SkillFx.shake(h, 0.2 + 0.3 * big)
		_:
			return false
	return true
