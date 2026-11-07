class_name MossbeardFx
extends RefCounted
## What Mossbeard's moves and his mushrooms look and sound like on every game (Enemy._fx "bb_*" events from Mossbeard
## and PoisonMushroom).

static func fx(en: Enemy, ev: String) -> void:
	var root: Node3D = en.game.world.fx_root
	var at := en.global_position
	var parts := ev.split(":")
	var name := parts[0]
	var args := BossBrain.args_of(ev)
	var tox := Color(0.45, 1.0, 0.3)
	match name:
		"bb_sprout_tele":
			Fx.burst(root, at + Vector3(0, 1.2, 0), tox, 40, 3.0, 0.15, 1.0, true, 1.0)
			Sfx.play_at("summon", at, -2.0, 0.8)
		"bb_shroom_up":
			Fx.burst(root, at + Vector3(0, 0.3, 0), Color(0.35, 0.25, 0.15, 0.8), 30, 4.0, 0.2, 0.8, false, -6.0, 60.0)
			Fx.ring(root, at, PoisonMushroom.POISON_R, tox, 0.5)
		"bb_cloud":
			Fx.ring(root, at, PoisonMushroom.POISON_R, Color(0.45, 1.0, 0.3, 0.6), 0.9, 0.6)
			Fx.burst(root, at + Vector3(0, 0.8, 0), Color(0.5, 1.0, 0.35, 0.35), 26, 1.6, 0.6, 1.4, false, 0.4, 180.0)
		"bb_snare_tele":
			Fx.telegraph(root, Vector3(args[0], 0, args[1]), 2.0, args[2], tox)
		"bb_snare":
			var p := Vector3(args[0], 0, args[1])
			thorns(root, p, 8, 2.0)
			Sfx.play_at("slam", p, -4.0, 1.5)
		"bb_step":
			Fx.burst(root, Vector3(args[0], 1.0, args[1]), tox, 60, 3.5, 0.2, 1.0, true, 0.6)
			Sfx.play_at("portal", Vector3(args[0], 1.0, args[1]), -6.0, 1.3)
		"bb_burst_tele":
			Fx.telegraph(root, at, 4.5, args[0] if args.size() > 0 else 1.0, tox)
		"bb_burst":
			thorns(root, at, 16, 4.5)
			Fx.ring(root, at, 4.5, tox, 0.5)
			Sfx.play_at("slam", at, 0.0, 1.1)

## Thorny roots lashing up (the snare, the burst): dark curved spikes that whip up and sink.
static func thorns(root: Node3D, at: Vector3, n: int, r: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.15, 0.08)
	m.roughness = 0.9
	for i in n:
		var a := TAU * i / n + randf() * 0.5
		var rr := randf_range(0.3, r)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.08
		cm.height = randf_range(0.8, 1.6)
		mi.mesh = cm
		mi.material_override = m
		root.add_child(mi)
		mi.global_position = at + Vector3(cos(a) * rr, -cm.height * 0.5, sin(a) * rr)
		mi.rotation = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6))
		var tw := mi.create_tween()
		tw.tween_property(mi, "position:y", mi.position.y + cm.height * 0.8, 0.1)
		tw.tween_interval(1.1)
		tw.tween_property(mi, "position:y", mi.position.y - 0.4, 0.4)
		tw.tween_callback(mi.queue_free)
