class_name LastRitesFx
extends RefCounted
## Last Rites' look (LastRites' events): "impact" {p} the slam of Holy Slam and a gold seal where the blade lands;
## "kill" {p} a column of light when it took a life.

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			pass
		"impact":
			var rp: Vector3 = ev["p"]
			Fx.holy_slam(root, rp, Skill.num("cleave", "radius", 2.6))
			HolyFx.seal(root, rp, 2.2, 0.1, 0.8, 1.0)
			Sfx.play_at("last_rites", rp, 0.0)
			SkillFx.shake(h, 0.45)
			SkillFx.hitstop(h, 0.08)
		"kill":
			HolyFx.level_up(h, root, ev["p"])
		_:
			return false
	return true
