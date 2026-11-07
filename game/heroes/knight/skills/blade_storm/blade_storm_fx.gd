class_name BladeStormFx
extends RefCounted
## Blade Storm's look (BladeStorm's "impact" {n: the turns}): a ring of holy fire at sword height for each turn, a
## beat apart like its rules' turns, with motes and sparks thrown off the edge and the blade's whirr.

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev["e"]) != "impact":
		return str(ev["e"]) == "cast"
	var root: Node3D = h.game.world.fx_root
	var r := Skill.num("k_whirl", "radius", 3.2)
	var beat := Skill.num("k_whirl", "beat", 0.22)
	for i in int(ev.get("n", 2)):
		var t := root.create_tween()
		t.tween_interval(beat * i)
		t.tween_callback(func():
			if is_instance_valid(h) and h.game != null and h.game.world != null:
				var at: Vector3 = h.global_position
				HolyFx.fire_ring(root, at + Vector3(0, 0.9, 0), 0.8, r, 0.25, 0.28)
				HolyFx.motes(root, at, r * 0.8, 10, 0.8)
				Fx.sparks(root, at + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.75))
				Sfx.play_at("blade_spin", at, -3.0, randf_range(0.95, 1.08)))
	SkillFx.shake(h, 0.18)
	return true
