class_name WraithFx
extends RefCounted
## Visual effects for the Wraith's skills. Everything is parented to the zone's FX node.

const SPIRIT := Color(0.35, 0.85, 1.0)
const VIOLET := Color(0.62, 0.38, 1.0)
const PALE := Color(0.85, 0.95, 1.0)

static var _crescent: ArrayMesh

## A flat crescent blade (the reaping arc), lying in the XZ plane and opening forward (-Z).
static func _crescent_mesh() -> ArrayMesh:
	if _crescent != null:
		return _crescent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	var a0 := deg_to_rad(-85.0)
	var a1 := deg_to_rad(85.0)
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var pts := []
		for t in [t0, t1]:
			var a: float = lerpf(a0, a1, t)
			var taper: float = sin(t * PI)              # thin at both tips
			var outer := 1.0
			var inner: float = 1.0 - 0.32 * taper
			var d := Vector3(sin(a), 0, -cos(a))
			pts.append([d * inner, d * outer, t])
		for q in [[pts[0][0], 0.0, pts[0][2]], [pts[0][1], 1.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]],
				[pts[0][0], 0.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]], [pts[1][0], 0.0, pts[1][2]]]:
			st.set_uv(Vector2(q[2], 1.0 - q[1]))   # 0 at the cutting edge, fading towards the inside
			st.set_normal(Vector3.UP)
			st.add_vertex(q[0])
	_crescent = st.commit()
	return _crescent

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

## Soul Reap: a spectral scythe arc sweeps across the front, a bright edge riding its rim.
static func reap(root: Node3D, pos: Vector3, yaw: float, radius: float) -> void:
	for layer in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _crescent_mesh()
		var col: Color = [SPIRIT, PALE, VIOLET][layer]
		var m := Mats.glow_unique(col, [1.4, 1.8, 0.9][layer], 1.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var r: float = radius * [1.0, 1.04, 0.86][layer]
		mi.global_position = pos + Vector3(0, 0.9 + layer * 0.12, 0)
		mi.scale = Vector3(r * 0.6, 1.0, r * 0.6)
		mi.rotation = Vector3(0.0, yaw + 0.9, [0.0, 0.05, -0.08][layer])
		var tw := mi.create_tween()
		tw.set_parallel(true)
		var d := 0.22 + layer * 0.04
		tw.tween_property(mi, "rotation:y", yaw - 0.9, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(r, 1.0, r), d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.42).set_delay(0.08)
		_free_later(mi, 0.6)
	Fx.burst(root, pos + Vector3(0, 0.9, 0) + Vector3(-sin(yaw), 0, -cos(yaw)) * radius * 0.6, SPIRIT, 26, 4.0, 0.09, 0.5, true, 0.5, 70.0, Vector3(-sin(yaw), 0.2, -cos(yaw)))
	Fx.flash(root, pos + Vector3(0, 1.2, 0), SPIRIT, 2.0, 0.25, 6.0)

## A captured soul: a little flame that curves back to the Wraith and heals it on arrival.
static func soul_wisp(root: Node3D, from: Vector3, hero: Node3D, on_arrive: Callable) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = from
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.07, 10)
	core.material_override = Mats.glow(PALE, 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var tr := _trail(SPIRIT, 0.11, 24, 0.45)
	n.add_child(tr)
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0) + Vector3(0, randf_range(1.0, 2.2), 0)
	var tw := n.create_tween()
	var dur := randf_range(0.45, 0.7)
	tw.tween_method(func(t: float):
		if not is_instance_valid(hero):
			return
		var to: Vector3 = hero.global_position + Vector3(0, 1.3, 0)
		var mid := from.lerp(to, 0.5) + side
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		n.global_position = a.lerp(b, t), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		core.visible = false
		tr.emitting = false
		Fx.burst(root, n.global_position, SPIRIT, 10, 1.5, 0.08, 0.35, true, 0.0)
		on_arrive.call())
	_free_later(n, dur + 0.8)

## Banshee Wail: three shock rings, a burst of pale screaming shapes and a cold flash.
static func wail(root: Node3D, pos: Vector3, radius: float) -> void:
	Fx.ring(root, pos, radius, SPIRIT.darkened(0.35), 0.45, 0.3)
	var tree := root.get_tree()
	tree.create_timer(0.1, false).timeout.connect(func():
		if is_instance_valid(root):
			Fx.ring(root, pos, radius * 0.8, VIOLET.darkened(0.3), 0.5, 0.9))
	tree.create_timer(0.2, false).timeout.connect(func():
		if is_instance_valid(root):
			Fx.ring(root, pos, radius * 1.05, SPIRIT.darkened(0.55), 0.5, 0.15))
	Fx.burst(root, pos + Vector3(0, 1.3, 0), Color(0.75, 0.9, 1.0, 0.7), 30, 9.0, 0.22, 0.5, true, 0.0, 180.0)
	Fx.burst(root, pos + Vector3(0, 0.4, 0), VIOLET, 40, 6.0, 0.12, 0.8, true, 1.5, 90.0)
	# the scream itself: a tall cone of light flaring up out of the hood
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cone(0.6, 2.6, 24)
	var m := Mats.glow_unique(SPIRIT, 2.0, 1.0, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 1.8, 0)
	mi.rotation = Vector3(PI, 0, 0)
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.4, 1.2, 1.4), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 0.9, 0.0, 0.45)
	_free_later(mi, 0.6)

## Shadow Step, departure: the body collapses into smoke and leaves a shade that implodes.
static func shade_depart(root: Node3D, pos: Vector3) -> void:
	Fx.burst(root, pos + Vector3(0, 1.0, 0), Color(0.05, 0.03, 0.09, 0.85), 30, 2.5, 0.35, 0.9, false, 0.6)
	Fx.burst(root, pos + Vector3(0, 1.0, 0), VIOLET, 24, 3.0, 0.1, 0.6, true, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cyl(0.35, 0.5, 2.0, 18)
	var m := Mats.glow_unique(VIOLET, 1.6, 1.0, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 1.0, 0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.05, 1.3, 0.05), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.3, 0.45)
	_free_later(mi, 0.5)

static func shade_implode(root: Node3D, pos: Vector3) -> void:
	Fx.ring(root, pos, 2.6, VIOLET, 0.35, 0.4)
	Fx.burst(root, pos + Vector3(0, 0.8, 0), VIOLET, 30, 5.0, 0.12, 0.45, true, 0.0)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), VIOLET, 3.0, 0.3, 6.0)

## Shadow Step, arrival: mist pours up out of the ground and the Wraith re-forms in it.
static func shade_arrive(root: Node3D, pos: Vector3) -> void:
	Fx.ring(root, pos, 2.4, SPIRIT, 0.35, 0.15)
	Fx.burst(root, pos + Vector3(0, 0.2, 0), SPIRIT, 34, 4.5, 0.14, 0.7, true, 3.0, 35.0)
	Fx.burst(root, pos + Vector3(0, 0.6, 0), Color(0.05, 0.03, 0.09, 0.8), 20, 1.5, 0.4, 0.8, false, 1.0)

## Spectral Host: one orbiting spirit (a bright core in a comet trail).
static func spirit_node(root: Node3D) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.085, 12)
	core.material_override = Mats.glow(PALE, 6.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = Geo.sph(0.17, 12)
	halo.material_override = Mats.glow(SPIRIT, 1.2, 0.0, 1.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	n.add_child(_trail(SPIRIT, 0.13, 40, 0.5))
	return n

static func summon(root: Node3D, pos: Vector3) -> void:
	Fx.pillar(root, pos, SPIRIT, 1.0)
	Fx.ring(root, pos, 3.0, VIOLET, 0.5, 0.2)

static func spirit_hit(root: Node3D, pos: Vector3) -> void:
	Fx.burst(root, pos, PALE, 16, 4.0, 0.08, 0.35, true, 0.0)
	Fx.flash(root, pos, SPIRIT, 1.5, 0.15, 3.0)

## A soft comet trail that stays in world space behind whatever it is attached to.
static func _trail(col: Color, size: float, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.15
	pm.gravity = Vector3.ZERO
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.8))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p
