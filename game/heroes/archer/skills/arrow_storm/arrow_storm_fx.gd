class_name ArrowStormFx
extends RefCounted
## Arrow Storm's look on every game: on its "impact" event {p: the mark, r: its reach}, the storm of arrows climbing
## out of the bow and falling over the mark (draws only; the strikes are ArrowStorm's).

static func play(h: Hero, ev: Dictionary) -> void:
	_rain(h, h.game.world.fx_root, ev["p"], float(ev.get("r", Skill.num("a_barrage", "radius", 4.5))))
	SkillFx.snd(h, "arrow_rain", -2.0, 0.9)

## Arrow Storm's look: the Meshy war arrows falling out of the sky over the mark in a staggered storm, each sticking
## in with a puff of dust, over 1.5 seconds (every peer).
static func _rain(h: Hero, root: Node3D, g: Vector3, r: float) -> void:
	var w = h.game.world
	# the mark first: a claw-raked ring where the storm will fall, then the arrows (a war arrow 1.5 times its size,
	# each trailing a pale streak, striking in with a burst of dust and chips)
	ArcherFx.hunter_mark(root, g, r, Color(0.95, 0.86, 0.6), 1.9)
	Fx.ring(root, g, r, Color(0.95, 0.85, 0.55), 1.7, 0.12)
	for i in 34:
		var a := randf() * TAU
		var d := sqrt(randf()) * r
		var at := g + Vector3(cos(a) * d, 0.0, sin(a) * d)
		at.y = w.height_at(at.x, at.z)
		var n := Archer._arrow_mesh("war")
		root.add_child(n)
		n.scale = Vector3.ONE * 1.5
		Fx.aura(n, Color(0.95, 0.9, 0.75), 6, 0.05, 0.05, 0.25, 0.0, 0.03)
		var from := at + Vector3(randf_range(-1.5, 1.5), 13.0, randf_range(-1.5, 1.5))
		n.global_position = from
		n.look_at(at, Vector3.RIGHT)
		n.visible = false
		var tw := n.create_tween()
		tw.tween_interval(0.15 + float(i) / 34.0 * 1.35)
		tw.tween_callback(func(): n.visible = true)
		tw.tween_property(n, "global_position", at + (from - at).normalized() * 0.35, 0.22)
		tw.tween_callback(func():
			Fx.burst(root, at + Vector3(0, 0.15, 0), Color(0.55, 0.47, 0.36), 10, 2.4, 0.1, 0.45, false, -6.0)
			Fx.sparks(root, at + Vector3(0, 0.2, 0), Color(1.0, 0.92, 0.7)))
		tw.tween_interval(1.2)
		tw.tween_callback(n.queue_free)
