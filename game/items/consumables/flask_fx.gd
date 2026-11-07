class_name FlaskFx
extends RefCounted
## A thrown flask's look on every player's game ("run" "toss", Consumables.throw_flask): a glowing bottle on an arc,
## trailing its colour, bursting where it lands. It only draws.

static func play(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var p: Vector3 = ev.get("p", h.global_position)
	var r: float = float(ev.get("r", 3.0))
	_toss(h, root, p, ev.get("q", p), r, int(ev.get("n", 0)))

## The flask's flight: a glowing bottle on an arc, trailing its colour, bursting where it lands.
static func _toss(h: Hero, root: Node3D, from: Vector3, to: Vector3, r: float, kind: int) -> void:
	var col: Color = [Color(1.0, 0.45, 0.1), Color(0.55, 0.85, 1.0), Color(0.6, 0.65, 1.0)][clampi(kind, 0, 2)]
	var n := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.13
	m.height = 0.3
	n.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.3)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	n.material_override = mat
	root.add_child(n)
	n.global_position = from
	Fx.aura(n, col, 18, 0.3, 0.06, 0.4, 0.0, 0.05)
	Sfx.play_at("swing_light", from, -6.0, 0.8)
	var tw := n.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(n):
			n.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 3.0, 0), 0.0, 1.0, Consumables.TOSS_T)
	tw.tween_callback(func():
		if is_instance_valid(h) and h.game != null and h.game.world != null:
			_burst(h, root, to, r, kind)
		n.queue_free())

static func _burst(h: Hero, root: Node3D, p: Vector3, r: float, kind: int) -> void:
	Sfx.play_at("flask_shatter", p, -2.0)
	match kind:
		0:
			ArrowFx.finish(h, "fire", p + Vector3(0, 0.5, 0), Vector3.FORWARD, false)
			Fx.ring(root, p, r, Color(1.0, 0.5, 0.15), 0.5)
		1:
			Fx.burst(root, p + Vector3(0, 0.6, 0), Color(0.8, 0.95, 1.0), 40, r * 1.5, 0.14, 0.7, true, -6.0)
			Fx.ring(root, p, r, Color(0.65, 0.9, 1.0), 0.7)
			Sfx.play_at("ice_shatter", p, -2.0, 0.8)
		2:
			for i in 3:
				ArcFx.bolt(root, p + Vector3(randf_range(-2, 2), 12.0, randf_range(-2, 2)), p + Vector3(randf_range(-r, r) * 0.5, 0.2, randf_range(-r, r) * 0.5), 0.3, 1.2, ArcFx.STORM, h.game)
			Fx.ring(root, p, r, Color(0.7, 0.75, 1.0), 0.4)
			Sfx.play_at("arc_hit", p, -3.0)
