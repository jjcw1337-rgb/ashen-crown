class_name WarlockFx
extends RefCounted
## Visual effects for the Warlock's skills. Everything is parented to the zone's FX node.

const FEL := Warlock.FEL
const PALE := Warlock.PALE
const DEEP := Warlock.DEEP

static var _beam_mat: StandardMaterial3D

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

## One Drain Life beam: twisting green strands redrawn every frame, turned to face the
## camera. Bright pulses and motes of life run from the victim back toward the caster, a
## glowing bite sits on the victim and (on the main beam) a vortex swirls in the palm.
class Beam extends MeshInstance3D:
	var width := 0.22
	var arc := 0.0       # lifts the middle of the beam (forks arch from victim to victim)
	var caps := false    # the main beam: a vortex at the caster's hand as well as the bite
	var jitter := 0.0
	var born := -1.0
	# frame state shared by the helpers below
	var _from := Vector3.ZERO
	var _span := Vector3.ZERO
	var _len := 1.0
	var _side := Vector3.RIGHT
	var _up := Vector3.UP
	var _vup := Vector3.UP
	var _t := 0.0

	func _init(w: float) -> void:
		width = w
		jitter = randf() * 10.0
		mesh = ImmediateMesh.new()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		top_level = true
		material_override = WarlockFx.beam_mat()

	## A point on a strand: u runs 0 (caster) to 1 (victim), pinned at both ends.
	func _at(u: float, wob: float, rate: float, ph: float) -> Vector3:
		var env := sin(u * PI)
		var a := u * rate * TAU * _len / 6.0 + _t * 7.0 + ph + jitter
		var off := (_side * sin(a) + _up * cos(a * 1.3) * 0.6) * wob * env
		return _from + _span * u + off + Vector3.UP * arc * env

	## A soft camera-facing disc: bright in the middle, fading to the rim.
	func _blob(im: ImmediateMesh, p: Vector3, r: float, c0: Color, c1: Color, seg := 12, star := 0.0) -> void:
		for i in seg:
			var a0 := TAU * i / seg + _t * 3.0
			var a1 := TAU * (i + 1) / seg + _t * 3.0
			var r0 := r * (1.0 + star * sin(a0 * 3.0 + _t * 9.0))
			var r1 := r * (1.0 + star * sin(a1 * 3.0 + _t * 9.0))
			im.surface_set_color(c0)
			im.surface_add_vertex(p)
			im.surface_set_color(c1)
			im.surface_add_vertex(p + (_side * cos(a0) + _vup * sin(a0)) * r0)
			im.surface_add_vertex(p + (_side * cos(a1) + _vup * sin(a1)) * r1)

	## A ribbon through pts, each point with its own width and colour, facing the camera.
	func _strip(im: ImmediateMesh, pts: Array, ws: Array, cols: Array, across: Vector3) -> void:
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var wa: float = ws[i - 1]
			var wb: float = ws[i]
			var ca: Color = cols[i - 1]
			var cb: Color = cols[i]
			var la := a - across * wa * 0.5
			var ra := a + across * wa * 0.5
			var lb := b - across * wb * 0.5
			var rb := b + across * wb * 0.5
			for v in [[la, ca], [ra, ca], [rb, cb], [la, ca], [rb, cb], [lb, cb]]:
				im.surface_set_color(v[1])
				im.surface_add_vertex(v[0])

	## from: the end the life flows to (the caster's hand, or the main victim for a fork);
	## to: the victim.
	func draw(from: Vector3, to: Vector3, t: float) -> void:
		global_transform = Transform3D.IDENTITY
		var im: ImmediateMesh = mesh
		im.clear_surfaces()
		if born < 0.0:
			born = t
		# on the latch the beam shoots out from the hand to the victim
		var grow := 1.0 - pow(1.0 - clampf((t - born) / 0.16, 0.0, 1.0), 3.0)
		to = from.lerp(to, grow)
		_t = t
		_from = from
		_span = to - from
		_len = _span.length()
		if _len < 0.05:
			return
		var dir := _span / _len
		var cam := get_viewport().get_camera_3d()
		var view := Vector3.UP
		if cam != null:
			view = (cam.global_position - (from + to) * 0.5).normalized()
		_side = dir.cross(view)
		if _side.length() < 0.01:
			_side = dir.cross(Vector3.RIGHT)
		_side = _side.normalized()
		_up = _side.cross(dir).normalized()
		_vup = view.cross(_side).normalized()
		var n := clampi(int(_len * 5.0), 12, 60)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		# strands: [width, wobble, twist rate, phase, colour, alpha]
		var strands := [
			[width * 2.2, 0.05, 2.0, 0.0, WarlockFx.DEEP, 0.45],
			[width, 0.14, 3.0, 0.0, WarlockFx.FEL, 0.75],
			[width * 0.6, 0.2, 4.5, 2.1, WarlockFx.FEL, 0.6],
			[width * 0.45, 0.24, 3.7, 4.4, WarlockFx.DEEP.lightened(0.3), 0.7],
			[width * 0.28, 0.03, 2.5, 4.0, WarlockFx.PALE, 0.75],
		]
		for s in strands:
			var pts := []
			var ws := []
			var cols := []
			for i in n + 1:
				var u := float(i) / n
				pts.append(_at(u, float(s[1]), float(s[2]), float(s[3])))
				ws.append(float(s[0]) * (0.55 + 0.45 * sin(u * PI)) * grow)
				# pulses travel from the victim (u = 1) to the caster (u = 0)
				var pulse := pow(0.5 + 0.5 * sin(u * _len * 2.2 + t * 14.0 + jitter), 6.0)
				var c: Color = s[4]
				var al: float = float(s[5]) * (0.55 + 0.9 * pulse) * smoothstep(0.0, 0.05, u)
				cols.append(Color(c.r, c.g, c.b, clampf(al, 0.0, 1.0)))
			_strip(im, pts, ws, cols, _side)
		# motes of stolen life drifting down the beam into the hand
		for k in 12:
			var h := fposmod(sin(k * 12.9898 + jitter) * 43758.5453, 1.0)
			var u := fposmod(k / 12.0 + h * 0.08 - t * (0.75 + h * 0.4), 1.0)
			var e := sin(u * PI)
			var mp := _at(u, 0.1 + h * 0.2, 3.0, k * 1.7)
			_blob(im, mp, width * (0.22 + 0.2 * h) * (0.4 + 0.6 * e), Color(0.9, 1.0, 0.8, 0.95 * e), Color(0.4, 1.0, 0.3, 0.0), 6)
		# the bite: where the beam sinks into the victim
		var throb := 1.0 + 0.2 * sin(t * 18.0)
		_blob(im, to, width * 3.2 * throb, Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.35), Color(0.0, 0.3, 0.0, 0.0), 16)
		_blob(im, to, width * 1.3 * throb, Color(0.75, 1.0, 0.65, 0.75), Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.0), 12, 0.35)
		if caps:
			# a vortex in the palm: three arms spiralling into a bright core
			_blob(im, from, width * 2.4, Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.3), Color(0.0, 0.3, 0.0, 0.0), 16)
			for arm in 3:
				var pts := []
				var ws := []
				var cols := []
				for i in 10:
					var f := float(i) / 9.0
					var ang := arm * TAU / 3.0 + f * 2.6 - t * 9.0
					var rr := width * 2.1 * (1.0 - f)
					pts.append(from + (_side * cos(ang) + _vup * sin(ang)) * rr)
					ws.append(width * 0.28 * (0.3 + f))
					cols.append(Color(0.6, 1.0, 0.5, 0.15 + 0.8 * f))
				_strip(im, pts, ws, cols, _vup)
			_blob(im, from, width * 0.8, Color(0.8, 1.0, 0.7, 0.75), Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.0), 10)
		im.surface_end()

static func beam_mat() -> StandardMaterial3D:
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.vertex_color_use_as_albedo = true
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.no_depth_test = false
		_beam_mat.albedo_color = Color(1.15, 1.15, 1.15)
	return _beam_mat

static func beam(root: Node3D, w: float) -> Beam:
	var b := Beam.new(w)
	root.add_child(b)
	return b

## A green light riding the caster's hand while the beam is up.
static func hand_light(root: Node3D) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = FEL
	l.light_energy = 1.6
	l.omni_range = 4.5
	l.shadow_enabled = false
	root.add_child(l)
	return l

## Life torn out of a victim: a puff of motes streaming toward the caster.
static func siphon(root: Node3D, at: Vector3, toward: Vector3) -> void:
	var d := toward - at
	Fx.burst(root, at, Color(0.5, 1.0, 0.4, 0.9), 7, 3.2, 0.08, 0.35, true, 0.0, 25.0, d.normalized() if d.length() > 0.1 else Vector3.UP)

## The latch: a flash where the beam first bites.
static func latch(root: Node3D, at: Vector3) -> void:
	Fx.burst(root, at, FEL, 16, 3.0, 0.1, 0.4, true, 0.0)
	Fx.flash(root, at, FEL, 2.0, 0.25, 4.0)

## The fel sigil that turns on the ground under a channelling Warlock.
static func sigil(root: Node3D, radius: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var m := Mats.glow_unique(FEL, 0.65)
	var faint := Mats.glow_unique(DEEP.lightened(0.25), 0.9)
	for spec in [[radius, 0.06, m], [radius * 0.64, 0.04, m], [radius * 0.84, 0.025, faint]]:
		var ring := MeshInstance3D.new()
		ring.mesh = Geo.torus(float(spec[0]) - float(spec[1]), float(spec[0]), 48, 4)
		ring.material_override = spec[2]
		ring.scale = Vector3(1.0, 0.2, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(ring)
	# a pentagram inside the inner ring
	var pr := radius * 0.64
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * ((i + 2) % 5) / 5.0
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * pr
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * pr
		var d := p1 - p0
		var line := MeshInstance3D.new()
		line.mesh = Geo.box(0.035, 0.01, d.length())
		line.material_override = m
		line.position = (p0 + p1) * 0.5
		line.rotation.y = atan2(d.x, d.z)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(line)
	# rune marks between the rings
	for k in 12:
		var a := TAU * k / 12.0
		var rune := MeshInstance3D.new()
		rune.mesh = Geo.box(0.04, 0.01, 0.13 if k % 3 == 0 else 0.08)
		rune.material_override = m
		rune.position = Vector3(sin(a), 0, -cos(a)) * radius * 0.82
		rune.rotation.y = a + (0.6 if k % 2 == 0 else 0.0)
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(rune)
	n.scale = Vector3(0.6, 1.0, 0.6)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		m.set_shader_parameter("alpha_mul", v)
		faint.set_shader_parameter("alpha_mul", v), 0.0, 1.0, 0.2)
	n.set_meta("mats", [m, faint])
	return n

## The sigil gutters out when the channel ends.
static func sigil_fade(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var mats: Array = n.get_meta("mats") if n.has_meta("mats") else []
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3(1.25, 1.0, 1.25), 0.3)
	tw.tween_method(_set_alpha.bind(mats), 1.0, 0.0, 0.3)
	_free_later(n, 0.35)

static func _set_alpha(v: float, mats: Array) -> void:
	for mm in mats:
		(mm as ShaderMaterial).set_shader_parameter("alpha_mul", v)

## Released: the stolen life left in the palm flares and scatters.
static func release(root: Node3D, at: Vector3) -> void:
	Fx.burst(root, at, Color(0.6, 1.0, 0.5, 0.9), 18, 2.5, 0.08, 0.45, true, 1.0)

## Blight Bolt in flight: a pale-green skull of fire trailing fel flame.
static func bolt_node(root: Node3D) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.12, 12)
	core.material_override = Mats.glow(PALE, 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = Geo.sph(0.24, 12)
	halo.material_override = Mats.glow(FEL, 1.4, 0.0, 1.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	# two dark eye sockets so it reads as a skull
	for sx in [-1, 1]:
		var e := MeshInstance3D.new()
		e.mesh = Geo.sph(0.035, 6)
		e.material_override = Mats.flat(Color(0.0, 0.05, 0.0))
		e.position = Vector3(0.045 * sx, 0.03, -0.1)
		n.add_child(e)
	n.add_child(Warlock.fel_flame(1.3, FEL))
	var l := OmniLight3D.new()
	l.light_color = FEL
	l.light_energy = 1.2
	l.omni_range = 3.5
	n.add_child(l)
	return n

static func blight_burst(root: Node3D, pos: Vector3, radius: float) -> void:
	Fx.ring(root, pos, radius, FEL, 0.4, 0.2)
	Fx.burst(root, pos + Vector3(0, 0.4, 0), FEL, 40, 6.0, 0.14, 0.6, true, -4.0, 70.0)
	Fx.burst(root, pos + Vector3(0, 0.5, 0), Color(0.08, 0.16, 0.05, 0.8), 20, 2.0, 0.4, 0.9, false, 0.5)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), FEL, 3.0, 0.35, 7.0)

## A plague pool: a soft, ragged green stain glowing brightest just inside its edge, with
## bubbles rising off it.
static func blight_pool(root: Node3D, pos: Vector3, radius: float, dur: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos + Vector3(0, 0.07, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	var ph := randf() * TAU
	# rings out from the centre: [radius fraction, colour]
	var rings := [[0.0, Color(0.02, 0.2, 0.03, 0.12)], [0.55, Color(0.04, 0.32, 0.05, 0.18)],
		[0.86, Color(0.25, 0.9, 0.2, 0.42)], [1.0, Color(0.05, 0.4, 0.05, 0.0)]]
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		# a ragged edge: the radius wanders around the circle
		var w0 := 1.0 + 0.09 * sin(a0 * 5.0 + ph) + 0.05 * sin(a0 * 11.0 + ph * 2.0)
		var w1 := 1.0 + 0.09 * sin(a1 * 5.0 + ph) + 0.05 * sin(a1 * 11.0 + ph * 2.0)
		for k in rings.size() - 1:
			var f0: float = rings[k][0]
			var f1: float = rings[k + 1][0]
			var c0: Color = rings[k][1]
			var c1: Color = rings[k + 1][1]
			var p00 := Vector3(sin(a0), 0, -cos(a0)) * radius * f0 * w0
			var p01 := Vector3(sin(a1), 0, -cos(a1)) * radius * f0 * w1
			var p10 := Vector3(sin(a0), 0, -cos(a0)) * radius * f1 * w0
			var p11 := Vector3(sin(a1), 0, -cos(a1)) * radius * f1 * w1
			for v in [[p00, c0], [p10, c1], [p11, c1], [p00, c0], [p11, c1], [p01, c0]]:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	var disc := MeshInstance3D.new()
	disc.mesh = st.commit()
	var dm: StandardMaterial3D = beam_mat().duplicate()
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)
	disc.scale = Vector3(0.3, 1.0, 0.3)
	disc.create_tween().tween_property(disc, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var bub := GPUParticles3D.new()
	bub.amount = 36
	bub.lifetime = 1.1
	bub.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.9
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.02
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.4, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.9, 0.3, 0.7))
	g.set_color(1, Color(0.05, 0.3, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	bub.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = Mats.particle_mat(true, Color.WHITE)
	bub.draw_pass_1 = q
	bub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bub)
	var tw := n.create_tween()
	tw.tween_interval(maxf(0.0, dur - 0.6))
	tw.tween_callback(func(): bub.emitting = false)
	tw.tween_property(dm, "albedo_color:a", 0.0, 0.6)
	_free_later(n, dur + 1.2)
	return n

## Soul Shackles: a chain of fel links snapping out from the caster to a victim.
static func chain(root: Node3D, from: Vector3, to: Vector3, dur: float) -> void:
	var d := to - from
	if d.length() < 0.2:
		return
	var c := Node3D.new()
	root.add_child(c)
	c.look_at_from_position(from, to, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	var m := Mats.glow_unique(FEL, 1.2)
	var spacing := 0.13
	var count := int(d.length() / spacing)
	for i in count:
		var link := MeshInstance3D.new()
		link.mesh = Geo.torus(0.028, 0.045, 12, 4)
		link.material_override = m
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		link.position = Vector3(0, 0, -(i + 0.5) * spacing)
		link.scale = Vector3(0.75, 1.0, 1.35)
		link.rotation = Vector3(0, 0, PI * 0.5 if i % 2 == 1 else 0.0)
		c.add_child(link)
	c.scale = Vector3(1.0, 1.0, 0.05)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.0, dur - 0.5))
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.35)
	_free_later(c, dur + 0.2)

## A glowing fetter around a bound enemy's waist for as long as it is held.
static func shackle(target: Node3D, dur: float) -> void:
	if not is_instance_valid(target):
		return
	var h: float = float(target.get("height"))
	var r: float = float(target.get("radius")) + 0.2
	var n := Node3D.new()
	target.add_child(n)
	n.position = Vector3(0, 0.75 * h, 0)
	var m := Mats.glow_unique(FEL, 0.9)
	for k in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = Geo.torus(r - 0.05, r, 32, 4)
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0, k * 0.28 * h - 0.14 * h, 0)
		ring.scale = Vector3(1.0, 0.35, 1.0)
		n.add_child(ring)
	var tw := n.create_tween()
	tw.tween_property(n, "rotation:y", TAU * dur * 0.3, dur)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.4).set_delay(maxf(0.0, dur - 0.4))
	_free_later(n, dur + 0.05)

static func shackle_cast(root: Node3D, pos: Vector3, radius: float) -> void:
	Fx.ring(root, pos, radius, DEEP.lightened(0.2), 0.45, 0.15)
	Fx.burst(root, pos + Vector3(0, 1.0, 0), FEL, 30, 4.0, 0.1, 0.5, true, 0.0)
	Fx.flash(root, pos + Vector3(0, 1.2, 0), FEL, 3.0, 0.35, 8.0)

## Fel Covenant: a column of green fire and a sigil burning outward.
static func covenant(root: Node3D, pos: Vector3) -> void:
	Fx.pillar(root, pos, FEL, 1.0)
	Fx.ring(root, pos, 6.0, FEL, 0.6, 0.25)
	Fx.burst(root, pos + Vector3(0, 0.2, 0), PALE, 50, 5.0, 0.1, 0.9, true, 2.5, 30.0)
	Fx.flash(root, pos + Vector3(0, 1.5, 0), FEL, 4.0, 0.6, 9.0)
