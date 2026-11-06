class_name Fx
extends RefCounted
## One-shot visual effects. All nodes are parented to `root` (the zone's FX node).

## Effect lights that cast shadows (a skill's fire, a burst): at most EFFECT_SHADOWS at once across every effect and
## every player, each on a dual-paraboloid map (2 passes, not a cube's 6). A new shadow-casting light would otherwise
## re-render the scene round it, and that was Fire Arrow's stutter (docs/systems/performance_kpis.md "skills"). The rest light
## the scene unshadowed. Call it before the light enters the tree, in place of `shadow_enabled = true`.
const EFFECT_SHADOWS := 2

static func effect_shadow(l: OmniLight3D) -> void:
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.shadow_enabled = false
	l.tree_entered.connect(func():
		# (a frame later: a shadow map's first frame can still hold another light's texels)
		later(l, 0.04, func():
			if l.is_inside_tree() and l.get_tree().get_nodes_in_group("fx_shadow").size() < EFFECT_SHADOWS:
				l.add_to_group("fx_shadow")
				l.shadow_enabled = true), CONNECT_ONE_SHOT)

## fn() in t seconds (game time), only if `node` still exists then. Use this, not a timer's lambda that captures a
## node and checks is_instance_valid: when the node is freed first, Godot logs "Lambda capture at index 0 was freed"
## as it calls the lambda, before the check runs (the servers reported it from effects on a puppet that had gone:
## triage 2026-11-02). Here the timer holds only a weak reference; fn is called (and its captures read) only while
## the node lives.
static func later(node: Node, t: float, fn: Callable) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var w: WeakRef = weakref(node)
	node.get_tree().create_timer(t, false).timeout.connect(func():
		var n: Node = w.get_ref() as Node
		if n != null and is_instance_valid(n):
			fn.call())

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

## A steady stream of particles from a parent (embers rising, frost mist, sparks), drawn in world space
## so it trails behind a mover. radius spreads where they start.
static func aura(parent: Node3D, col: Color, amount := 24, speed := 0.6, size := 0.08, life := 1.2, gravity := 0.6, radius := 0.15, spread := 40.0, at := Vector3.ZERO, additive := true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.position = at
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.1
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.15, col)
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
	parent.add_child(p)
	return p

## Streaks: particles stretched along their own flight (aligned to their velocity, the quad turning round that axis
## to face the camera), for sparks and blood droplets (visual overhaul: both were the same round soft dots as every
## burst). size = the streak's width; it is `stretch` times as long.
static var _streak_tex: GradientTexture2D
static var _streak_mats := {}

static func _streak_mat(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if _streak_mats.has(key):
		return _streak_mats[key]
	if _streak_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_streak_tex = GradientTexture2D.new()
		_streak_tex.gradient = g
		_streak_tex.fill = GradientTexture2D.FILL_RADIAL
		_streak_tex.fill_from = Vector2(0.5, 0.5)
		_streak_tex.fill_to = Vector2(0.5, 0.0)
		_streak_tex.width = 32
		_streak_tex.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(2.4, 2.4, 2.4)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _streak_tex
	m.disable_receive_shadows = true
	_streak_mats[key] = m
	return m

static func streaks(root: Node3D, pos: Vector3, colors: Array, amount: int, speed: float, size: float, stretch: float, life: float, additive: bool, gravity: float, spread := 180.0, dir := Vector3.UP, damping := 0.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.96
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = damping * 0.6
	pm.damping_max = damping
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.25))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_offset(0, colors[0][0])
	g.set_color(0, colors[0][1])
	g.set_offset(1, colors[colors.size() - 1][0])
	g.set_color(1, colors[colors.size() - 1][1])
	for i in range(1, colors.size() - 1):
		g.add_point(colors[i][0], colors[i][1])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size * stretch)
	q.material = _streak_mat(additive)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, life + 0.5)
	return p

## Sparks: hot streaks flung out, cooling white to the colour to dark red as they fall, and a short flash.
static func sparks(root: Node3D, pos: Vector3, col := Color(1.0, 0.8, 0.4)) -> void:
	streaks(root, pos, [[0.0, Color(1.0, 0.97, 0.88, 1.0)], [0.25, Color(col.r, col.g, col.b, 1.0)], [1.0, Color(0.7, 0.18, 0.04, 0.0)]],
		20, 7.5, 0.035, 5.0, 0.42, true, -11.0, 180.0, Vector3.UP, 2.0)
	burst(root, pos, col, 5, 1.2, 0.09, 0.18, true, 0.0)
	flash(root, pos, col, 1.5, 0.12)

## Blood: droplets thrown out as short streaks that arc down, and a few round drops; darker as they fly.
static func blood(root: Node3D, pos: Vector3, col: Color) -> void:
	var c := Color(col.r, col.g, col.b, 1.0)
	streaks(root, pos, [[0.0, c.lightened(0.15)], [0.6, c], [1.0, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 0.0)]],
		12, 4.2, 0.045, 3.2, 0.55, false, -12.0, 75.0, Vector3.UP, 0.5)
	burst(root, pos, c, 6, 2.2, 0.08, 0.55, false, -10.0)

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

## Area blows (every nova, shockwave and slam that draws a ring through `ring` or `holy_slam`) are told to whoever
## listens, on every game that plays the effect: a Callable(pos: Vector3, radius: float). The Plague Doctor's swarm
## listens while it's out (any area hit scatters it). Listeners that are no longer valid are dropped.
static var area_listeners: Array[Callable] = []
static func area_hit(pos: Vector3, radius: float) -> void:
	for c in area_listeners.duplicate():
		if c.is_valid():
			c.call(pos, radius)
		else:
			area_listeners.erase(c)

## Expanding ring on the ground (nova, shockwave, slam).
static func ring(root: Node3D, pos: Vector3, radius: float, col: Color, dur: float = 0.5, height: float = 0.25) -> void:
	# every shockwave ring also shoves the grass outward (a bigger ring, a harder shove)
	GrassField.impulse(pos, radius, clampf(0.35 + radius * 0.06, 0.35, 0.75), clampf(dur * 0.8, 0.25, 0.55))
	area_hit(pos, radius)
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

## Holy Slam (the knight's Q) striking the ground: a white explosion. Meshy-painted sprites
## (assets/textures/fx/holy_slam_*.png): a blinding starburst that flares up and one flat on the
## ground, a white shockwave of smoke racing out, and the stone cracked open and glowing white where
## the blade hit, fading over a couple of seconds. Rock chunks (assets/models/fx/rock_chunks.glb, made
## in Blender) are thrown up out of the cracks and tumble back down; white-hot sparks, glowing motes
## and pale dust fill the air.
const SLAM_TEX := {"burst": "res://assets/textures/fx/holy_slam_burst.png", "crack": "res://assets/textures/fx/holy_slam_crack.png", "ring": "res://assets/textures/fx/holy_slam_ring.png"}
const SLAM_CHUNKS := "res://assets/models/fx/rock_chunks.glb"
static var _chunk_meshes: Array = []
static var _stone: StandardMaterial3D

static func _slam_quad(root: Node3D, pos: Vector3, tex_key: String, additive: bool, billboard: bool, yaw: float) -> Array:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	if not billboard:
		q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_texture = ResCache.get_res(SLAM_TEX[tex_key])
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw
	return [mi, m]

static func holy_slam(root: Node3D, pos: Vector3, radius: float) -> void:
	GrassField.impulse(pos, radius * 1.3, 0.9, 0.5)
	area_hit(pos, radius)
	var white := Color(1.0, 0.98, 0.92)
	flash(root, pos + Vector3(0, 0.9, 0), white, 3.0, 0.22, radius * 1.8)
	var tex_ok := ResourceLoader.exists(SLAM_TEX["burst"])
	if tex_ok:
		# the cracked stone, glowing white in its cracks, then cooling and fading away
		var cr := _slam_quad(root, pos + Vector3(0, 0.04, 0), "crack", false, false, randf() * TAU)
		var cmi: MeshInstance3D = cr[0]
		var cm: StandardMaterial3D = cr[1]
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		cm.emission_enabled = true
		cm.emission_texture = cm.albedo_texture
		cm.emission = Color(1, 1, 1)
		cm.emission_energy_multiplier = 0.9
		cmi.scale = Vector3.ONE * radius * 1.25
		var ct := cmi.create_tween()
		ct.tween_property(cm, "emission_energy_multiplier", 0.0, 0.7).set_ease(Tween.EASE_OUT)
		ct.tween_property(cm, "albedo_color:a", 0.0, 1.0).set_delay(1.0)
		_free_later(cmi, 2.9)
		# the starburst: one standing up facing the camera, one flat on the ground
		for spec in [[true, pos + Vector3(0, 0.6, 0), radius * 1.25, 0.32], [false, pos + Vector3(0, 0.08, 0), radius * 1.6, 0.4]]:
			var b := _slam_quad(root, spec[1], "burst", true, spec[0], randf() * TAU)
			var bmi: MeshInstance3D = b[0]
			var bm: StandardMaterial3D = b[1]
			bmi.scale = Vector3.ONE * 0.4
			var bt := bmi.create_tween()
			bt.set_parallel(true)
			bt.tween_property(bmi, "scale", Vector3.ONE * float(spec[2]), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			bt.tween_property(bm, "albedo_color", Color(1, 1, 1, 0), spec[3]).set_delay(0.06).set_ease(Tween.EASE_IN)
			_free_later(bmi, float(spec[3]) + 0.12)
		# the shockwave racing out along the ground
		var r := _slam_quad(root, pos + Vector3(0, 0.12, 0), "ring", true, false, randf() * TAU)
		var rmi: MeshInstance3D = r[0]
		var rm: StandardMaterial3D = r[1]
		rmi.scale = Vector3.ONE * 0.5
		var rt := rmi.create_tween()
		rt.set_parallel(true)
		rt.tween_property(rmi, "scale", Vector3.ONE * radius * 3.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		rt.tween_property(rm, "albedo_color", Color(1, 1, 1, 0), 0.5).set_ease(Tween.EASE_IN)
		_free_later(rmi, 0.55)
	else:
		ring(root, pos, radius * 1.3, white, 0.45, 0.12)
	_slam_chunks(root, pos)
	# white-hot sparks flung out and up, slow glowing motes left hanging, pale dust
	burst(root, pos + Vector3(0, 0.25, 0), white, 48, 9.0, 0.06, 0.45, true, -9.0, 75.0, Vector3.UP)
	burst(root, pos + Vector3(0, 0.5, 0), Color(1.0, 1.0, 1.0, 0.9), 26, 2.2, 0.12, 1.1, true, 0.6, 90.0, Vector3.UP)
	burst(root, pos + Vector3(0, 0.15, 0), Color(0.82, 0.8, 0.76, 0.55), 30, 4.0, 0.3, 0.8, false, -2.5, 85.0, Vector3.UP)

## Rock chunks thrown up out of the cracks: each flies on its own arc and spin, lands, and sinks away.
static func _slam_chunks(root: Node3D, pos: Vector3) -> void:
	if _chunk_meshes.is_empty():
		if not ResourceLoader.exists(SLAM_CHUNKS):
			return
		var sc: Node = ResCache.inst(SLAM_CHUNKS)
		for n in sc.find_children("*", "MeshInstance3D", true, false):
			_chunk_meshes.append((n as MeshInstance3D).mesh)
		sc.free()
		_stone = StandardMaterial3D.new()
		_stone.albedo_texture = ResCache.get_res(SLAM_TEX["crack"])
		_stone.uv1_triplanar = true
		_stone.uv1_scale = Vector3(2.5, 2.5, 2.5)
		_stone.albedo_color = Color(0.85, 0.83, 0.8)
		_stone.roughness = 0.9
		_stone.emission_enabled = true
		_stone.emission = Color(1.0, 0.95, 0.85)
		_stone.emission_energy_multiplier = 0.25
	if _chunk_meshes.is_empty():
		return
	var g := -14.0
	for k in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = _chunk_meshes[k % _chunk_meshes.size()]
		mi.material_override = _stone
		root.add_child(mi)
		var a := TAU * (k + randf_range(-0.35, 0.35)) / 10.0
		var start := pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.1, 0.45) + Vector3(0, 0.05, 0)
		var vel := Vector3(cos(a), 0, sin(a)) * randf_range(1.6, 3.6) + Vector3(0, randf_range(3.5, 6.5), 0)
		var spin := Vector3(randf_range(-14, 14), randf_range(-10, 10), randf_range(-14, 14))
		var sz := randf_range(0.8, 1.6)
		var land := -2.0 * vel.y / g          # time back down to the ground
		mi.global_position = start
		mi.scale = Vector3.ONE * sz
		var tw := mi.create_tween()
		tw.tween_method(func(t: float):
			if not is_instance_valid(mi):
				return
			var tt := minf(t, land)
			mi.global_position = start + Vector3(vel.x * tt, vel.y * tt + 0.5 * g * tt * tt, vel.z * tt)
			mi.rotation = spin * tt, 0.0, land, land)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.6).set_delay(0.5)
		_free_later(mi, land + 1.2)

## A red disc that fills over `dur` seconds to warn of an incoming area attack.
static func telegraph(root: Node3D, pos: Vector3, radius: float, dur: float, col := Color(1.0, 0.15, 0.05)) -> void:
	_telegraph(root, pos, Vector3.FORWARD, radius, PI + 0.1, dur, col)

## A wedge of danger on the ground (the Fallen Reaver's cleave): radius metres out from pos along dir, half
## degrees each side; it fills outward over dur, the moment the blow lands.
static func arc_telegraph(root: Node3D, pos: Vector3, dir: Vector3, radius: float, half: float, dur: float, col := Color(1.0, 0.15, 0.05)) -> void:
	_telegraph(root, pos, dir, radius, deg_to_rad(half), dur, col)

## Both telegraphs (visual overhaul): a crisp glowing rim, the area washed faintly, and the fill sweeping out from the
## middle with a bright front that meets the rim the moment the blow lands, a faint pulse running through it; added
## light, so it tints the ground under it instead of covering it with flat paint (it was a solid unshaded disc or fan).
static var _tele_shader: Shader
static var _tele_disc: ArrayMesh
static func _telegraph(root: Node3D, pos: Vector3, dir: Vector3, radius: float, half: float, dur: float, col: Color) -> void:
	if _tele_shader == null:
		_tele_shader = Shader.new()
		_tele_shader.code = TELEGRAPH_SHADER
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 64
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * 1.02)
			st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * 1.02)
		_tele_disc = st.commit()
	var m := ShaderMaterial.new()
	m.shader = _tele_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("half_angle", half)
	var mi := MeshInstance3D.new()
	mi.mesh = _tele_disc
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.07, 0)
	mi.rotation.y = atan2(-dir.x, -dir.z)
	mi.scale = Vector3(radius, 1, radius)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, maxf(dur, 0.05))
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 1.0, 0.0, 0.12)
	tw.tween_callback(mi.queue_free)

const TELEGRAPH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.15, 0.05, 1.0);
uniform float progress = 0.0;
uniform float half_angle = 3.3;
uniform float alpha = 1.0;
varying vec2 lp;
void vertex() {
	lp = VERTEX.xz;
}
void fragment() {
	float r = length(lp);
	float a = abs(atan(lp.x, -lp.y));
	if (r > 1.0 || a > half_angle) { discard; }
	float px = fwidth(r) * 1.5;
	float rim = smoothstep(0.955 - px, 0.985, r);
	float side = half_angle < 3.1 ? 1.0 - smoothstep(0.0, 0.035 + px, (half_angle - a) * max(r, 0.05)) : 0.0;
	float outline = max(rim, side);
	float filled = 1.0 - smoothstep(progress - px, progress + px, r);
	float front = filled * smoothstep(progress - 0.08, progress, r);
	float pulse = 0.8 + 0.2 * sin(r * 34.0 - TIME * 7.0);
	float v = outline * 0.7 + filled * 0.13 * pulse + front * 0.6 + 0.035;
	ALBEDO = col.rgb * 1.4;
	ALPHA = clamp(v * alpha, 0.0, 1.0);
}
"""

## A crack of lightning from a to b: a jagged line of short glowing segments that flickers out (Storm Snare).
static func bolt(root: Node3D, a: Vector3, b: Vector3, col: Color, dur: float = 0.22) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var m := Mats.glow_unique(col, 4.0, 0.0, 0.0)
	var n := 7
	var prev := a
	var side := (b - a).cross(Vector3.UP).normalized()
	for i in n:
		var t := float(i + 1) / n
		var p := a.lerp(b, t)
		if i < n - 1:
			p += side * randf_range(-0.35, 0.35) + Vector3(0, randf_range(-0.25, 0.25), 0)
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = prev.distance_to(p)
		cm.radial_segments = 4
		cm.rings = 1
		seg.mesh = cm
		seg.material_override = m
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(seg)
		seg.global_position = (prev + p) * 0.5
		if prev.distance_to(p) > 0.01:
			seg.look_at(p, Vector3.UP if absf((p - prev).normalized().y) < 0.95 else Vector3.FORWARD)
			seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		prev = p
	burst(root, b, col, 10, 3.0, 0.06, 0.3, true, 0.0)
	var tw := holder.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur)
	_free_later(holder, dur + 0.05)

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

## A splash on the ground (a kill's blood, a stain of oil): a ragged pool with rays and drops past its edge that runs
## out in a moment, wet and glossy, darker where it is deep, laid over the ground's bumps (SPLAT_SHADER); it dries matte
## and soaks away over the last 14 of its 40 seconds. (It was a flat ten-sided disc.)
static func splat(root: Node3D, pos: Vector3, col: Color, size: float = 0.8) -> void:
	var g = root.get_tree().current_scene if root.is_inside_tree() else null
	var w = g.world if g != null and "world" in g else null
	var m := ShaderMaterial.new()
	m.shader = _splat_shader()
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("col", Color(col.r * 0.78, col.g * 0.72, col.b * 0.72))
	m.set_shader_parameter("deep", Color(col.r * 0.3, col.g * 0.26, col.b * 0.26))
	m.set_shader_parameter("seed", randf() * 10.0)
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.disc_mesh(w, pos, size * randf_range(0.85, 1.2) * 1.6, 28, 3, 0.06)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	InfernalFx.tween_param(mi, m, "spread", 0.0, 1.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, 14.0, 26.0)
	_free_later(mi, 40.5)

static var _splat_sh: Shader
static func _splat_shader() -> Shader:
	if _splat_sh == null:
		_splat_sh = Shader.new()
		_splat_sh.code = SPLAT_SHADER
	return _splat_sh

## A kill's spray: droplets flung up and out as streaks that arc down (more from a bigger body), a few heavier drops.
static func gore(root: Node3D, pos: Vector3, col: Color, big := 0.5) -> void:
	var c := Color(col.r, col.g, col.b, 1.0)
	streaks(root, pos, [[0.0, c.lightened(0.12)], [0.55, c], [1.0, Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 0.0)]],
		int(clampf(18.0 + big * 20.0, 18.0, 40.0)), 5.2, 0.05, 3.0, 0.7, false, -12.0, 85.0, Vector3.UP, 0.4)
	burst(root, pos, c, 8, 2.6, 0.09, 0.6, false, -11.0)

## SPLAT_SHADER: on InfernalFx.disc_mesh (UV centre 0.5, rim 0.5 out). spread 0..1 runs it out, life 1..0 soaks it away.
const SPLAT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.25, 0.02, 0.02, 1.0);
uniform vec4 deep : source_color = vec4(0.09, 0.01, 0.01, 1.0);
uniform float spread = 0.0;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float n = texture(noise_tex, UV * 1.6 + vec2(seed, 0.0)).r;
	float n2 = texture(noise_tex, UV * 6.5 + vec2(0.3, seed)).r;
	float rays = pow(abs(sin(a * 5.0 + seed * 3.0 + n * 4.0)), 18.0);
	float edge = (0.45 + (n - 0.5) * 0.35 + rays * 0.35) * spread;
	float pool = smoothstep(edge + 0.012, edge - 0.03, r);
	float drops = smoothstep(0.78, 0.86, n2) * step(edge, r) * smoothstep(edge * 1.5 + 0.02, edge, r) * spread;
	float m = max(pool, drops);
	float thick = smoothstep(edge, edge * 0.35, r);
	ALBEDO = mix(col.rgb, deep.rgb, clamp(thick * 0.7 + (n2 - 0.5) * 0.2, 0.0, 1.0));
	ROUGHNESS = mix(0.12, 0.55, 1.0 - life);
	SPECULAR = 0.7;
	ALPHA = clamp(m * 0.92 * min(life * 1.5, 1.0) * smoothstep(1.0, 0.92, r), 0.0, 1.0);
}
"""

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
