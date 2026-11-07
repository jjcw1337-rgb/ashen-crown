class_name SpiritFx
extends RefCounted
## The Wraith's spirit-light, what his skills' looks share (skills/*/*_fx.gd; docs/systems/effects.md): his colours,
## his bursts of curling wisps and rolling shadow, his rings of soul-mist, his claws and their rakes, a soul flying
## back to him, a pulse of light, his afterimages, the dark ground decal and a comet trail. Draws only.

## His cold cyan spirit-light (SPIRIT), the pale core of a torn soul (PALE), and the violet of the dark he moves
## through (VIOLET, NIGHT).
const SPIRIT := Color(0.35, 0.85, 1.0)
const VIOLET := Color(0.62, 0.38, 1.0)
const PALE := Color(0.85, 0.95, 1.0)
const NIGHT := Color(0.18, 0.08, 0.32)

static var _mark: ArrayMesh
static var _disc: ArrayMesh
static var _claw: ArrayMesh
static var _floor_shader: Shader
static var _ribbon_mat: StandardMaterial3D

## The Wraith's own particles and rings (visual overhaul): his spirit-light was the generic soft-dot burst and his
## shock rings the generic glowing torus, the same as every class's. Now spirit light streaks out as curling wisps
## (quads stretched along their flight, fading cyan to violet), shadow rolls as soft smoke (InfernalFx's smoke, unlit by
## fire), and a ring is a ripple of soul-mist racing over the ground. Same arguments as Fx.burst / Fx.ring.
static var _wisp_mat: StandardMaterial3D
static var _ring_shader: Shader

static func _wisp_material() -> StandardMaterial3D:
	if _wisp_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_wisp_mat = StandardMaterial3D.new()
		_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wisp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_wisp_mat.billboard_keep_scale = true
		_wisp_mat.vertex_color_use_as_albedo = true
		_wisp_mat.albedo_color = Color(2.2, 2.2, 2.2)
		_wisp_mat.albedo_texture = gt
		_wisp_mat.disable_receive_shadows = true
	return _wisp_mat

static func burst(root: Node3D, pos: Vector3, col: Color, amount: int = 16, speed: float = 3.0, size: float = 0.12, life: float = 0.5, additive := true, gravity: float = -6.0, spread: float = 180.0, dir := Vector3.UP) -> GPUParticles3D:
	if not additive:
		# shadow: soft rolling smoke in the burst's colour
		var sm := InfernalFx.smoke_mat(0.0, clampf(col.a, 0.2, 1.0))
		sm.set_shader_parameter("smoke", Vector3(col.r, col.g, col.b))
		var q := QuadMesh.new()
		q.size = Vector2(size * 2.2, size * 2.2)
		q.material = sm
		return InfernalFx.particles(root, pos, {"amount": maxi(3, amount / 3), "life": life * 1.4, "explosive": 0.9,
			"shape": "sphere", "r": size, "dir": dir, "spread": spread, "vel": [speed * 0.25, speed * 0.6], "gravity": gravity * 0.3,
			"damping": [1.0, 1.8], "scale": [0.7, 1.2], "grow": [0.6, 1.5], "angle": true, "spin": 25.0, "mesh": q,
			"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.15, Color(1, 1, 1, 0.9)], [0.6, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]]})
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life * 1.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity * 0.5 + 0.6, 0)
	pm.damping_min = speed * 0.6
	pm.damping_max = speed * 1.1
	pm.particle_flag_align_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.22
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(PALE.r, PALE.g, PALE.b, 0.0))
	g.add_point(0.08, Color(PALE.r, PALE.g, PALE.b, 1.0))
	g.add_point(0.35, Color(col.r, col.g, col.b, 0.9))
	g.set_color(1, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q2 := QuadMesh.new()
	q2.size = Vector2(size * 0.7, size * 3.2)
	q2.material = _wisp_material()
	p.draw_pass_1 = q2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	free_later(p, p.lifetime + 0.5)
	return p

## A ripple of soul-mist racing out over the ground from pos to `radius` in `dur` (the ring every Wraith skill used),
## with the grass shoved and a flash of its light, as Fx.ring had.
static func ring(root: Node3D, pos: Vector3, radius: float, col: Color, dur: float = 0.5, height: float = 0.25) -> void:
	GrassField.impulse(pos, radius, clampf(0.35 + radius * 0.06, 0.35, 0.75), clampf(dur * 0.8, 0.25, 0.55))
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = SOUL_RING_SHADER
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("pale", PALE)
	m.set_shader_parameter("seed", randf() * 10.0)
	var mi := MeshInstance3D.new()
	mi.mesh = HolyFx.flat()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, minf(height, 0.12), 0)
	mi.scale = Vector3(radius * 2.3, 1.0, radius * 2.3)
	InfernalFx.tween_param(mi, m, "front", 0.12, 0.92, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	free_later(mi, dur + 0.05)
	Fx.flash(root, pos + Vector3(0, 1, 0), col, 3.0, dur, radius * 1.5)

## The soul-mist ring on a flat quad (UV 0.5 at the centre): a band at `front` eroded into wisps by noise, pale at its
## leading edge and fading to the skill's colour behind it.
const SOUL_RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform vec4 pale : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float front = 0.1;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float n = texture(noise_tex, vec2(a * 0.6 + seed, r * 1.5 - TIME * 0.4)).r;
	float n2 = texture(noise_tex, vec2(a * 2.1 - seed, r * 3.0)).r;
	float x = (r - front) / 0.16;
	float band = exp(-x * x * 2.0) * smoothstep(0.25, 0.7, n + 0.25);
	float trail = smoothstep(front, front - 0.35, r) * smoothstep(front - 0.5, front - 0.2, r) * 0.35 * smoothstep(0.4, 0.8, n2);
	float lead = exp(-pow((r - front - 0.03) / 0.04, 2.0));
	vec3 c = mix(col.rgb, pale.rgb, clamp(lead * 1.2, 0.0, 1.0)) * 2.4;
	ALBEDO = c;
	ALPHA = clamp((band + trail + lead * 0.5) * life * smoothstep(1.0, 0.92, r), 0.0, 1.0);
}
"""

static func free_later(n: Node, t: float) -> void:
	var w: WeakRef = weakref(n)
	n.get_tree().create_timer(t, false).timeout.connect(func():
		var m: Node = w.get_ref() as Node
		if m != null and is_instance_valid(m):
			m.queue_free())

## A thin claw-mark crescent (a narrower band over a shorter arc).
static func mark_mesh() -> ArrayMesh:
	if _mark != null:
		return _mark
	_mark = _crescent_make(0.1, 55.0)
	return _mark

static func _crescent_make(thick: float, half_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	var a0 := deg_to_rad(-half_deg)
	var a1 := deg_to_rad(half_deg)
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var pts := []
		for t in [t0, t1]:
			var a: float = lerpf(a0, a1, t)
			var taper: float = sin(t * PI)
			var inner: float = 1.0 - thick * taper
			var d := Vector3(sin(a), 0, -cos(a))
			pts.append([d * inner, d, t])
		for q in [[pts[0][0], 0.0, pts[0][2]], [pts[0][1], 1.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]],
				[pts[0][0], 0.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]], [pts[1][0], 0.0, pts[1][2]]]:
			st.set_uv(Vector2(q[2], 1.0 - q[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(q[0])
	return st.commit()

## A unit disc in the XZ plane with UV = position (0.5 at the centre), for ground decals.
static func disc_mesh() -> ArrayMesh:
	if _disc != null:
		return _disc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for p in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]:
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	_disc = st.commit()
	return _disc

## A curved spectral claw: a tapering blade bent along its length, pointing down -Y from the fingertip.
static func claw_mesh() -> ArrayMesh:
	if _claw != null:
		return _claw
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var prev: Array = []
	for i in n + 1:
		var t := float(i) / n
		var r := 0.011 * (1.0 - t * 0.92)
		var p := Vector3(0.0, -t, -0.3 * t * t)     # bends forward as it goes down
		var hoop := []
		for k in 5:
			var a := TAU * k / 5.0
			hoop.append(p + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.6))
		if not prev.is_empty():
			for k in 5:
				var k2 := (k + 1) % 5
				for v in [prev[k], hoop[k], hoop[k2], prev[k], hoop[k2], prev[k2]]:
					st.set_uv(Vector2(0.0, t))
					st.add_vertex(v)
		prev = hoop
	st.generate_normals()
	_claw = st.commit()
	return _claw

static func ribbon_mat() -> StandardMaterial3D:
	if _ribbon_mat == null:
		_ribbon_mat = StandardMaterial3D.new()
		_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ribbon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ribbon_mat.vertex_color_use_as_albedo = true
		_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ribbon_mat.albedo_color = Color(1.2, 1.2, 1.2)
	return _ribbon_mat

# ---------------------------------------------------------------- the spectral claws (Spectral Rend, Phantom Assault)
## Four claws of spirit-light on each hand, on the skeleton's hand bones (BoneAttachment3D: the bone's own Y runs
## down the fingers), grown out by set_claws. The armature is in centimetres (scale 0.01), hence the x100.
static func claws(rig: Node3D) -> Array:
	if rig.has_meta("claws"):
		return rig.get_meta("claws")
	var out := []
	var skels := rig.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		rig.set_meta("claws", out)
		return out
	var skel: Skeleton3D = skels[0]
	for bone in ["RightHand", "LeftHand"]:
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var at := BoneAttachment3D.new()
		at.bone_name = bone
		skel.add_child(at)
		var side := 1.0 if bone == "RightHand" else -1.0
		# the way the fingers point, in the hand bone's own frame: on along the forearm
		var hg := skel.get_bone_global_rest(bi)
		var fg := skel.get_bone_global_rest(skel.get_bone_parent(bi))
		var fingers: Vector3 = (hg.basis.inverse() * (hg.origin - fg.origin)).normalized()
		var hand_up: Vector3 = (hg.basis.inverse() * Vector3.UP).normalized()      # the back of the hand (A-pose, palms down)
		var across := fingers.cross(hand_up).normalized()
		var base := Basis(-across, -fingers, -across.cross(-fingers)).orthonormalized()  # the claw mesh hangs down -y, curling to the palm
		for i in 4:
			var c := MeshInstance3D.new()
			c.mesh = claw_mesh()
			c.material_override = Mats.glow_unique(PALE.lerp(SPIRIT, 0.6), 2.2, 0.0, 0.0)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var fan := Basis(fingers, deg_to_rad((i - 1.5) * 9.0 * side)) * Basis(across, deg_to_rad(-12.0))
			c.transform = Transform3D((fan * base).scaled(Vector3(100.0, 0.1, 100.0)), fingers * 9.0 + across * (i - 1.5) * 2.0 * side)
			c.set_meta("base", fan * base)
			c.visible = false
			at.add_child(c)
			out.append(c)
	rig.set_meta("claws", out)
	return out

## k 0..1: how far the claws are out (0.38 m at full), their light with them.
static func set_claws(rig: Node3D, k: float) -> void:
	for c in claws(rig):
		var m := c as MeshInstance3D
		if not is_instance_valid(m):
			continue
		m.visible = k > 0.01
		m.basis = (m.get_meta("base") as Basis).scaled(Vector3(100.0 + k * 30.0, maxf(0.1, 24.0 * k), 100.0 + k * 30.0))
		(m.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", clampf(k * 1.4, 0.0, 1.0))

## The rake: three thin spectral crescents tearing across in front, a flash and a spray of torn light.
static func rake(root: Node3D, pos: Vector3, yaw: float, radius: float, left: bool) -> void:
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))
	for layer in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mark_mesh()
		var col: Color = [PALE, SPIRIT, SPIRIT.lerp(VIOLET, 0.5)][layer]
		var m := Mats.glow_unique(col, [2.0, 1.5, 1.1][layer], 1.2)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var r: float = radius * [0.9, 1.0, 0.8][layer]
		mi.global_position = pos + Vector3(0, 1.05 + (layer - 1) * 0.2, 0)
		var s := 1.0 if left else -1.0
		mi.scale = Vector3(r * 0.5, 1.0, r * 0.5)
		mi.rotation = Vector3(-0.3 * s * (0.6 + layer * 0.2), yaw + 0.7 * s, 0.3 * s)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		var d := 0.16 + layer * 0.03
		tw.tween_property(mi, "rotation:y", yaw - 0.7 * s, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(r, 1.0, r), d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.3).set_delay(0.06)
		free_later(mi, 0.45)
	burst(root, pos + Vector3(0, 1.1, 0) + dir * radius * 0.6, SPIRIT, 18, 4.5, 0.08, 0.4, true, 0.5, 60.0, dir + Vector3(0, 0.3, 0))
	Fx.flash(root, pos + Vector3(0, 1.2, 0) + dir * 0.8, SPIRIT, 1.6, 0.2, 5.0)

## The claws on his hands follow the attack (on his own game and his puppet's): out for Spectral Rend's rakes and
## Phantom Assault's strike, grown as the arm draws back, out again for Shadowstep's spin, gone soon after.
static func update_claws(h: Hero, delta: float) -> void:
	var a := SkillFx.atk(h)
	var st := SkillFx.style(h)
	var want := 0.0
	if a >= 0.0 and st == "rend":
		want = Anim.kf(a, [[0.0, 0.0], [0.3, 1.0], [0.85, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and st == "phantom":
		want = Anim.kf(a, [[0.0, 0.0], [0.25, 1.0], [0.8, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and st == "wstep":
		want = Anim.kf(a, [[0.35, 0.0], [0.6, 1.0], [0.9, 1.0], [1.0, 0.0]])
	var ck: float = float(h.fxs.get("claw_k", 0.0))
	ck = lerpf(ck, want, clampf(delta * 18.0, 0.0, 1.0)) if want < ck else want
	h.fxs["claw_k"] = ck
	if h.rig != null and h._floats() and (ck > 0.001 or bool(h.fxs.get("claw_shown", false))):
		set_claws(h.rig, ck)
		h.fxs["claw_shown"] = ck > 0.001

## The claws put away (death, a class change, a zone change).
static func clear_claws(h: Hero) -> void:
	if h.rig != null and h.rig.has_meta("claws"):
		set_claws(h.rig, 0.0)
	h.fxs.erase("claw_k")
	h.fxs.erase("claw_shown")

## A soul torn out of a foe: a pale flame that curves back to the Wraith over dur s (a skill's heal lands then:
## WraithSkill.wisp_time). On his own screen it chimes as it arrives, `db` loud (none when db is INF).
static func soul_wisp(root: Node3D, from: Vector3, hero: Node3D, dur: float, db := INF) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = from
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.07, 10)
	core.material_override = Mats.glow(PALE, 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var tr := trail(SPIRIT, 0.11, 24, 0.45)
	n.add_child(tr)
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0) + Vector3(0, randf_range(1.0, 2.2), 0)
	var tw := n.create_tween()
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
		burst(root, n.global_position, SPIRIT, 10, 1.5, 0.08, 0.35, true, 0.0)
		if db < INF and is_instance_valid(hero) and hero is Hero and (hero as Hero)._mine() and not (hero as Hero).dead:
			Sfx.play("soul_return", db))
	free_later(n, dur + 0.8)

## A ring of pale light that races out from a point in the air (hits, the soul leaving).
static func pulse(root: Node3D, pos: Vector3, col: Color, size: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.sph(1.0, 16)
	var m := Mats.glow_unique(col, 1.6, 0.0, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur)
	free_later(mi, dur + 0.05)

# ---------------------------------------------------------------- afterimages (Shadowstep, Phantom Assault, Eternal Night)
## A ghost of the Wraith frozen in his pose this instant: a copy of the skinned body (the armature with its bone
## poses) under its own spectral materials, tinted and thinned to spirit (the shader's "ghost" and phase_amt).
## It lives `life` seconds, dissolving over the last part. Returns the ghost's root (its origin = the hero's).
static func afterimage(rig: Node3D, root: Node3D, tint: Color, life: float, start_phase := 0.3) -> Node3D:
	var body: Node3D = rig.get_node_or_null("Body")
	if body == null:
		return null
	var arm: Node3D = body.get_node_or_null("Armature")
	if arm == null:
		return null
	var g := Node3D.new()
	root.add_child(g)
	g.global_transform = rig.global_transform
	var b := Node3D.new()
	b.transform = body.transform       # the float's lean and height, the turn
	g.add_child(b)
	var copy: Node3D = arm.duplicate()
	b.add_child(copy)
	var mats := []
	for mi in copy.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var src := m.get_surface_override_material(si) as ShaderMaterial
			if src == null:
				continue
			var mat := src.duplicate() as ShaderMaterial
			mat.set_shader_parameter("ghost", 1.0)
			mat.set_shader_parameter("spirit", tint)
			mat.set_shader_parameter("phase_amt", start_phase)
			mat.set_shader_parameter("glow", 2.0)
			m.set_surface_override_material(si, mat)
			mats.append(mat)
	g.set_meta("mats", mats)
	g.set_meta("born", 0.0)
	var tw := g.create_tween()
	tw.tween_method(func(v: float):
		for mt in mats:
			(mt as ShaderMaterial).set_shader_parameter("phase_amt", v), start_phase, 1.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	free_later(g, life + 0.05)
	return g

## A dark ground decal: black fading to a coloured rim, with slow drifting noise.
static func floor_mat(col: Color, amt: float) -> ShaderMaterial:
	if _floor_shader == null:
		_floor_shader = Shader.new()
		_floor_shader.code = FLOOR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	m.set_shader_parameter("rim", col)
	m.set_shader_parameter("amt", amt)
	return m

const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 rim : source_color = vec3(0.6, 0.4, 1.0);
uniform float amt = 1.0;
uniform float runes = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void fragment(){
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float n = vn(c * 9.0 + vec2(TIME * 0.25, -TIME * 0.17)) * 0.5 + vn(c * 19.0 - TIME * 0.4) * 0.25;
	float edge = 1.0 - smoothstep(0.78, 1.0, r + (n - 0.4) * 0.25);
	float dark = edge * 0.78;
	float ring = smoothstep(0.1, 0.0, abs(r - 0.86 + (n - 0.4) * 0.2)) * 0.9;
	float ang = atan(c.y, c.x);
	float rn = 0.0;
	if (runes > 0.0) {
		float spokes = smoothstep(0.75, 1.0, sin(ang * 12.0 + TIME * 0.6) * 0.5 + 0.5) * smoothstep(0.3, 0.45, r) * (1.0 - smoothstep(0.7, 0.8, r));
		float inner = smoothstep(0.06, 0.0, abs(r - 0.42));
		rn = (spokes + inner) * runes;
	}
	vec3 col = mix(vec3(0.02, 0.01, 0.04), rim, clamp(ring + rn, 0.0, 1.0) * 0.8) * (0.6 + 0.4 * n);
	ALBEDO = col * (1.0 + (ring + rn) * 0.7);
	ALPHA = clamp(dark + ring * 0.9 + rn * 0.6, 0.0, 1.0) * amt;
}
"""

## A soft comet trail that stays in world space behind whatever it is attached to.
static func trail(col: Color, size: float, amount: int, life: float) -> GPUParticles3D:
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
