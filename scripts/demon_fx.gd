class_name DemonFx
extends RefCounted
## Visual effects for the Demon's skills, and the Underworld that Phase opens.

const EMBER := Color(1.0, 0.42, 0.06)
const HOT := Color(1.0, 0.75, 0.3)
const BLOOD := Color(0.85, 0.04, 0.08)
const SOUL := Color(0.62, 0.42, 1.0)

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

## A steady drift of embers (Blood Pact on a summoned demon).
static func ember_aura() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.3
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.5, 0.1, 0.9))
	g.set_color(1, Color(0.9, 0.05, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## Hellfire Claw: three burning rakes cut across the front, one after another.
static func claw(root: Node3D, pos: Vector3, yaw: float, radius: float) -> void:
	var tree := root.get_tree()
	for k in 3:
		var delay := k * 0.05
		tree.create_timer(delay, false).timeout.connect(func():
			if not is_instance_valid(root):
				return
			var mi := MeshInstance3D.new()
			mi.mesh = WraithFx._crescent_mesh()
			var m := Mats.glow_unique([HOT, EMBER, BLOOD][k], [2.2, 1.8, 1.4][k], 1.0)
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var r: float = radius * (0.95 - k * 0.12)
			mi.global_position = pos + Vector3(0, 1.25 - k * 0.22, 0)
			mi.scale = Vector3(r * 0.7, 1.0, r * 0.7 * 0.55)
			mi.rotation = Vector3(0.0, yaw - 0.7, 0.35 - k * 0.12)
			var tw := mi.create_tween()
			tw.set_parallel(true)
			tw.tween_property(mi, "rotation:y", yaw + 0.7, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(mi, "scale", Vector3(r, 1.0, r * 0.55), 0.16)
			tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.35).set_delay(0.05)
			_free_later(mi, 0.5))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	Fx.burst(root, pos + Vector3(0, 1.0, 0) + fwd * radius * 0.5, EMBER, 30, 5.0, 0.07, 0.45, true, -5.0, 60.0, fwd + Vector3(0, 0.3, 0))
	Fx.flash(root, pos + Vector3(0, 1.2, 0) + fwd, EMBER, 2.2, 0.2, 5.0)

## A few seconds of flame clinging to a clawed monster.
static func ignite(root: Node3D, target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var f := Props.fire(target, Vector3(0, 0.9 * float(target.get("height")), 0), 0.35, EMBER, false, false, false)
	_free_later(f, 1.6)

## Summon: a burning sigil opens on the ground and the demon claws its way out of it.
static func summon_circle(root: Node3D, pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = Geo.torus(0.9, 1.0, 48, 4)
	var rm := Mats.glow_unique(EMBER, 1.8)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.06, 0)
	ring.scale = Vector3(1.3, 0.25, 1.3)
	# a five-pointed star of light inside it
	var star := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * ((i + 2) % 5) / 5.0
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * 1.15
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * 1.15
		var n := (p1 - p0).normalized().cross(Vector3.UP) * 0.035
		for v in [p0 + n, p1 + n, p1 - n, p0 + n, p1 - n, p0 - n]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0.5))
			st.add_vertex(v)
	star.mesh = st.commit()
	var sm := Mats.glow_unique(EMBER.lightened(0.15), 1.7)
	star.material_override = sm
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(star)
	star.global_position = pos + Vector3(0, 0.07, 0)
	for n2 in [ring, star]:
		var tw: Tween = n2.create_tween()
		tw.set_parallel(true)
		tw.tween_property(n2, "rotation:y", 1.2, 1.4)
	var tw2 := ring.create_tween()
	tw2.tween_method(func(v: float):
		rm.set_shader_parameter("alpha_mul", v)
		sm.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 1.4).set_delay(0.4)
	_free_later(ring, 1.9)
	_free_later(star, 1.9)
	Fx.burst(root, pos + Vector3(0, 0.2, 0), EMBER, 40, 4.0, 0.1, 0.9, true, 2.5, 30.0)
	Fx.burst(root, pos + Vector3(0, 0.3, 0), Color(0.08, 0.02, 0.02, 0.85), 20, 1.4, 0.35, 1.0, false, 1.8, 25.0)
	Fx.flash(root, pos + Vector3(0, 0.8, 0), EMBER, 3.0, 0.7, 6.0)

## Blood Pact: blood spirals up from the Demon and its demons.
static func pact(root: Node3D, pos: Vector3) -> void:
	Fx.pillar(root, pos, BLOOD, 1.0)
	Fx.ring(root, pos, 3.5, BLOOD.darkened(0.2), 0.5, 0.2)
	Fx.burst(root, pos + Vector3(0, 1.0, 0), BLOOD, 40, 3.0, 0.1, 1.0, true, 2.0, 50.0)

## Phase: the Demon tears into the Underworld (and back out).
static func phase_tear(root: Node3D, pos: Vector3) -> void:
	Fx.ring(root, pos, 3.0, SOUL.darkened(0.3), 0.4, 0.2)
	Fx.burst(root, pos + Vector3(0, 1.0, 0), SOUL, 36, 4.0, 0.1, 0.7, true, 1.5)
	Fx.burst(root, pos + Vector3(0, 1.0, 0), Color(0.04, 0.0, 0.06, 0.9), 26, 2.0, 0.4, 0.9, false, 0.8)

## Leaving the Underworld: the rift erupts in soul-fire around the Demon.
static func eruption(root: Node3D, pos: Vector3, radius: float) -> void:
	Fx.ring(root, pos, radius, SOUL.darkened(0.25), 0.45, 0.25)
	root.get_tree().create_timer(0.08, false).timeout.connect(func():
		if is_instance_valid(root):
			Fx.ring(root, pos, radius * 0.85, BLOOD.darkened(0.2), 0.45, 0.6))
	Fx.burst(root, pos + Vector3(0, 0.5, 0), SOUL, 50, 7.0, 0.14, 0.7, true, 2.0, 70.0)
	Fx.burst(root, pos + Vector3(0, 0.5, 0), EMBER, 30, 6.0, 0.09, 0.6, true, -3.0, 80.0)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), SOUL, 4.0, 0.4, radius * 2.0)

# ---------------------------------------------------------------- the Underworld
## Souls rising from the ground all around the Demon while Phase lasts.
static func soul_field() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 3.2
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-16, -2, -12), Vector3(32, 10, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.2, 9)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.35, 0)
	pm.turbulence_enabled = false
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.2))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.6, 1.0, 0.0))
	g.add_point(0.25, Color(0.8, 0.7, 1.0, 0.75))
	g.set_color(1, Color(0.9, 0.2, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.2)
	q.material = Mats.particle_mat(true, Color(2.2, 2.2, 2.2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## Full-screen grade for the Underworld: the act is still there, but drained to bone and
## violet, crimson where anything burns, rippling like heat over the dark.
const UNDERWORLD_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amt = 0.0;
void fragment(){
	vec2 uv = SCREEN_UV;
	float w = sin(uv.y * 38.0 + TIME * 2.2) * 0.0018 + sin(uv.x * 23.0 - TIME * 1.4) * 0.0014;
	uv += vec2(w, -w * 0.7) * amt;
	vec2 dc = (uv - 0.5) * 0.007 * amt;
	vec3 c;
	c.r = texture(screen_tex, uv + dc).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - dc).b;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	// shadows sink to indigo, mid-tones turn violet, highlights go bone-pale; lifted so the
	// fight stays easy to read
	l = pow(clamp(l, 0.0, 1.0), 0.75);
	vec3 g = mix(vec3(0.05, 0.02, 0.1), vec3(0.46, 0.22, 0.66), smoothstep(0.0, 0.4, l));
	g = mix(g, vec3(1.0, 0.9, 0.95), smoothstep(0.4, 1.0, l));
	// anything burning (fires, eyes, ember edges) keeps its colour and turns blood-hot
	float hot = clamp((c.r - max(c.g, c.b)) * 2.2, 0.0, 1.0);
	g = mix(g, c * vec3(1.25, 0.55, 0.6), hot);
	vec3 o = mix(c, g, amt * 0.82);
	// a dark ring of veins pulsing at the edge of sight
	vec2 q = SCREEN_UV - 0.5;
	float r = length(q * vec2(1.7, 1.0));
	float vig = smoothstep(0.32, 0.92, r);
	float ang = atan(q.y, q.x);
	float veins = smoothstep(0.86, 1.0, sin(ang * 17.0 + sin(r * 28.0 - TIME * 1.8) * 1.6)) * vig;
	o = mix(o, vec3(0.015, 0.0, 0.03), vig * 0.55 * amt);
	o += vec3(0.65, 0.05, 0.22) * veins * 0.4 * amt * (0.6 + 0.4 * sin(TIME * 3.0));
	COLOR = vec4(o, 1.0);
}
"""
