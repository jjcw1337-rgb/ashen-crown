class_name HrimgarFx
extends RefCounted
## What Hrimgar's moves look and sound like on every game (Enemy._fx "bb_*" events from Hrimgar): the warnings
## (telegraphs) before each lands, then the ice.

static func fx(en: Enemy, ev: String) -> void:
	var root: Node3D = en.game.world.fx_root
	var at := en.global_position
	var parts := ev.split(":")
	var name := parts[0]
	var args := BossBrain.args_of(ev)
	var ice := Color(0.6, 0.9, 1.0)
	match name:
		"bb_slam_tele":
			Fx.telegraph(root, at, 6.0, args[0] if args.size() > 0 else 1.0, ice)
		"bb_slam":
			Fx.ring(root, at, 6.0, ice, 0.6)
			Fx.burst(root, at + Vector3(0, 0.4, 0), Color(0.85, 0.95, 1.0), 60, 7.0, 0.18, 1.0, true, -6.0, 80.0)
			spikes(root, at, 10, 2.0, 5.5)
			Sfx.play_at("slam", at, 2.0, 0.7)
			en.game.add_shake(0.6)
		"bb_lances_tele":
			var d := Vector3(args[0], 0, args[1]).normalized()
			for k in 6:
				Fx.telegraph(root, at + d * (1.5 + k * 2.0), 1.3, args[2], ice)
		"bb_lances":
			var d2 := Vector3(args[0], 0, args[1]).normalized()
			for k in 6:
				spikes(root, at + d2 * (1.5 + k * 2.0), 3, 0.2, 1.0)
			Sfx.play_at("slam", at + d2 * 6.0, -2.0, 1.3)
		"bb_roar_tele":
			Fx.arc_telegraph(root, at, Vector3(args[0], 0, args[1]), 9.0, 35.0, args[2], ice)
			Sfx.play_at("trex_roar" if Sfx.bank.has("trex_roar") else "roar", at + Vector3(0, 3, 0), 0.0, 0.7)
		"bb_roar":
			var d3 := Vector3(args[0], 0, args[1]).normalized()
			Fx.burst(root, at + Vector3(0, 2.6, 0) + d3 * 1.0, Color(0.8, 0.95, 1.0, 0.8), 80, 9.0, 0.25, 1.0, true, -1.0, 30.0, d3)
		"bb_aval_tele":
			var w := float(parts[1]) if parts.size() > 1 else 1.4
			if parts.size() > 2:
				for pt in parts[2].split(";"):
					var xy := pt.split(",")
					if xy.size() == 2:
						Fx.telegraph(root, Vector3(float(xy[0]), 0, float(xy[1])), 2.2, w, ice)
			Sfx.play_at("roar", at, 0.0, 0.6)
		"bb_aval":
			Sfx.play_at("slam", at, 3.0, 0.6)
			en.game.add_shake(0.8)
			Fx.burst(root, at + Vector3(0, 6.0, 0), Color(0.85, 0.95, 1.0), 120, 6.0, 0.25, 1.4, true, -14.0, 180.0)

## Ice spears out of the floor (a burst that rises fast, holds, sinks and is gone): n of them over radius r0..r1.
static func spikes(root: Node3D, at: Vector3, n: int, r0: float, r1: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.3, 0.7, 1.0)
	m.emission_energy_multiplier = 1.2
	m.roughness = 0.1
	for i in n:
		var a := TAU * i / n + randf() * 0.4
		var r := randf_range(r0, r1)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.18, 0.32)
		cm.height = randf_range(1.0, 1.9)
		mi.mesh = cm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = at + Vector3(cos(a) * r, -cm.height * 0.5, sin(a) * r)
		mi.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
		var tw := mi.create_tween()
		tw.tween_property(mi, "position:y", mi.position.y + cm.height * 0.85, 0.12)
		tw.tween_interval(0.9)
		tw.tween_property(mi, "position:y", mi.position.y - 0.3, 0.5)
		tw.tween_callback(mi.queue_free)

