class_name BananaPeelsFx
extends RefCounted
## What banana peels look like (Banana Peels and Banana Bonanza, DougFx hands their events here): "land" lays the
## Meshy peels (banana.glb) where they fell (Bonanza's each flung out of his hands first, from "q"), each rotting away
## on its own clock; "slip" and "gone" take the peel there away, a slip with a yellow burst and "Slipped!". Draws only.

const BANANA := "res://game/heroes/doug/skills/banana_peels/banana.glb"

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var e := str(ev.get("e", ""))
	match e:
		"land":
			var list: Array = h.fxs.get("peels", [])
			var from_v: Variant = ev.get("q", null)     # Banana Bonanza: each peel is flung out of his hands first
			for p in ev.get("ps", PackedVector3Array()):
				var m := ResCache.inst(BANANA) as Node3D
				if m == null:
					m = MeshInstance3D.new()
					(m as MeshInstance3D).mesh = Geo.sph(0.18, 8)
				root.add_child(m)
				m.global_position = p + Vector3(0, 0.02, 0)
				m.rotation.y = randf() * TAU
				m.set_meta("t", float(ev.get("x", 8.0)))
				list.append(m)
				if from_v is Vector3:
					m.scale = Vector3.ONE * 0.01
					DougFx.fly(root, BANANA, from_v, p + Vector3(0, 0.1, 0), 0.35, 1.6, 0.7)
					var tw := m.create_tween()
					tw.tween_interval(0.33)
					tw.tween_property(m, "scale", Vector3.ONE * 0.7, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					tw.tween_callback(func(): Fx.burst(root, p + Vector3(0, 0.15, 0), Color(1.0, 0.9, 0.35), 8, 2.0, 0.06, 0.35, false, -9.0))
				else:
					m.scale = Vector3.ONE * 0.5
			h.fxs["peels"] = list
			SkillFx.snd(h, "swing_light", -6.0, 1.6)
		"slip", "gone":
			var p2: Vector3 = ev["p"]
			var list2: Array = h.fxs.get("peels", [])
			for i in range(list2.size() - 1, -1, -1):
				var n: Node3D = list2[i]
				if not is_instance_valid(n) or n.global_position.distance_to(p2) < 0.3:
					if is_instance_valid(n):
						n.queue_free()
					list2.remove_at(i)
			if e == "slip":
				Fx.burst(root, p2 + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.25), 20, 3.0, 0.1, 0.5, true, -8.0)
				Fx.number(root, p2 + Vector3(0, 2.0, 0), "Slipped!", Color(1.0, 0.9, 0.3))
				SkillFx.snd(h, "doug_slip", -1.0)
		_:
			return false
	return true

## The peels rot away on their own clocks.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("peels"):
		return
	var list: Array = h.fxs["peels"]
	for i in range(list.size() - 1, -1, -1):
		var n = list[i]
		if not is_instance_valid(n):
			list.remove_at(i)
			continue
		n.set_meta("t", float(n.get_meta("t")) - delta)
		if float(n.get_meta("t")) <= 0.0:
			n.queue_free()
			list.remove_at(i)

static func clear(h: Hero) -> void:
	for n in h.fxs.get("peels", []):
		if is_instance_valid(n):
			n.queue_free()
