class_name Fx
extends RefCounted
## One-shot visual effects. All nodes are parented to `root` (the zone's FX node).

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

static func number(root: Node3D, pos: Vector3, text: String, col: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.font_size = 64 if big else 44
	l.outline_size = 12
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	root.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.2, 0.2))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.4, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	if big:
		l.scale = Vector3.ONE * 1.6
		tw.tween_property(l, "scale", Vector3.ONE, 0.2)
	_free_later(l, 1.0)

static func burst(root: Node3D, pos: Vector3, col: Color, amount: int = 16, speed: float = 3.0, size: float = 0.12, life: float = 0.5, additive := true, gravity: float = -6.0, spread: float = 180.0, dir := Vector3.UP) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = Mats.particle_mat(additive, Color(2, 2, 2) if additive else Color.WHITE)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, life + 0.5)
	return p

static func sparks(root: Node3D, pos: Vector3, col := Color(1.0, 0.8, 0.4)) -> void:
	burst(root, pos, col, 22, 6.0, 0.07, 0.35, true, -9.0)
	flash(root, pos, col, 1.5, 0.12)

static func blood(root: Node3D, pos: Vector3, col: Color) -> void:
	burst(root, pos, Color(col.r, col.g, col.b, 1.0), 14, 3.0, 0.1, 0.6, false, -9.0)

static func flash(root: Node3D, pos: Vector3, col: Color, energy: float, dur: float, rng: float = 4.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	_free_later(l, dur + 0.05)

## Expanding ring on the ground (nova, shockwave, slam).
static func ring(root: Node3D, pos: Vector3, radius: float, col: Color, dur: float = 0.5, height: float = 0.25) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.torus(0.85, 1.0, 48, 4)
	var m := Mats.glow_unique(col, 3.0, 0.0, 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, height, 0)
	mi.scale = Vector3(0.3, 2.0, 0.3)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur)
	_free_later(mi, dur + 0.05)
	flash(root, pos + Vector3(0, 1, 0), col, 3.0, dur, radius * 1.5)

## A red disc that fills over `dur` seconds to warn of an incoming area attack.
static func telegraph(root: Node3D, pos: Vector3, radius: float, dur: float, col := Color(1.0, 0.15, 0.05)) -> void:
	var outer := MeshInstance3D.new()
	outer.mesh = Geo.torus(0.94, 1.0, 48, 3)
	outer.material_override = Mats.glow(col, 2.0)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(outer)
	outer.global_position = pos + Vector3(0, 0.08, 0)
	outer.scale = Vector3(radius, 0.3, radius)
	var fill := MeshInstance3D.new()
	fill.mesh = Geo.cyl(1.0, 1.0, 0.01, 40)
	var fm := Mats.glow_unique(col, 0.6)
	fill.material_override = fm
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	fill.global_position = pos + Vector3(0, 0.07, 0)
	fill.scale = Vector3(0.05, 1, 0.05)
	var tw := fill.create_tween()
	tw.tween_property(fill, "scale", Vector3(radius, 1, radius), dur)
	_free_later(outer, dur)
	_free_later(fill, dur)

static func pillar(root: Node3D, pos: Vector3, col: Color, dur: float = 1.4) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cyl(0.9, 0.9, 1.0, 24)
	var m := Mats.glow_unique(col, 2.5, 1.5, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 3.0, 0)
	mi.scale = Vector3(0.2, 6.0, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.0, 6.0, 1.0), 0.25)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur).set_delay(0.3)
	_free_later(mi, dur + 0.4)
	burst(root, pos + Vector3(0, 0.5, 0), col, 40, 4.0, 0.12, 1.2, true, 2.0, 40.0)
	flash(root, pos + Vector3(0, 2, 0), col, 4.0, dur, 9.0)

## Blood splat decal left on the floor.
static func splat(root: Node3D, pos: Vector3, col: Color, size: float = 0.8) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cyl(1.0, 1.0, 0.005, 10)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3(size * randf_range(0.7, 1.3), 1, size * randf_range(0.7, 1.3))
	mi.rotation.y = randf() * TAU
	_free_later(mi, 40.0)

## Swirling blue town portal model.
static func portal_model(col := Color(0.3, 0.55, 1.0)) -> Node3D:
	var root := Node3D.new()
	var frame := MeshInstance3D.new()
	frame.mesh = Geo.torus(0.9, 1.05, 40, 8)
	frame.material_override = Mats.glow(col, 2.5)
	frame.rotation_degrees = Vector3(90, 0, 0)
	frame.scale = Vector3(0.85, 1.0, 1.35)
	frame.position = Vector3(0, 1.45, 0)
	root.add_child(frame)
	var disc := MeshInstance3D.new()
	disc.mesh = Geo.cyl(0.92, 0.92, 0.02, 32)
	disc.material_override = Mats.glow(Color(col.r * 0.6, col.g * 0.7, col.b, 0.8), 1.2)
	disc.rotation_degrees = Vector3(90, 0, 0)
	disc.scale = Vector3(0.85, 1.0, 1.35)
	disc.position = Vector3(0, 1.45, 0)
	disc.name = "disc"
	root.add_child(disc)
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 0.95
	pm.emission_ring_inner_radius = 0.8
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.5, 0)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 1.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.position = Vector3(0, 1.45, 0)
	p.scale = Vector3(0.85, 1.35, 1.0)
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.position = Vector3(0, 1.4, 0.4)
	root.add_child(l)
	return root
