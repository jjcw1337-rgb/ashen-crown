class_name ElementalFx
extends RefCounted
## The shared skills' own looks (visual overhaul): every class can use Earthshatter, Frost Nova, Arc and War Cry, and
## they were the generic Fx burst and ring in four colours. Now each element has its own shapes, built the way
## InfernalFx and HolyFx build the Demon's and the knight's (shaders compiled once, one-shot pieces under the zone's
## FX node that free themselves, counts by InfernalFx.tier):
##   - Earthshatter: the ground cracks open through the wedge, the crack running out from the blow; rock spikes heave
##     up along it and sink back, chunks and pebbles fly, a dust cloud rolls out.
##   - Frost Nova: frost races over the ground to the edge of the blast (a bright edge ahead of it), a ring of ice
##     crystals bursts up and shatters, cold mist rolls out, glints hang in the air.
##   - Arc: real lightning, a jagged branching bolt re-struck every few frames while it lives, leaping target to
##     target; a flash and sparks on each one.
##   - War Cry: a war sigil burns into the ground, the air ripples, a wave of dust and ash rolls out to the edge of
##     the cry, embers rise round him.
## Draws only (SharedFx calls it from the skills' fx events, on the caster and his puppet alike).

const ROCK := Color(0.3, 0.26, 0.22)
const DUST := Color(0.56, 0.49, 0.4)
const DUST_DARK := Color(0.24, 0.21, 0.17)
const ICE_DEEP := Color(0.2, 0.5, 0.92)
const ICE_PALE := Color(0.8, 0.94, 1.0)
const STORM_CORE := Color(0.93, 0.95, 1.0)
const STORM_GLOW := Color(0.5, 0.56, 1.0)
const WAR := Color(0.86, 0.12, 0.06)
const WAR_EMBER := Color(1.0, 0.45, 0.14)

static var _shaders := {}
static var _rock_mat: StandardMaterial3D
static var _chunks: Array = []
static var _warm_world := 0

static func shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = {"crack": CRACK_SHADER, "frost": FROST_SHADER, "ice": ICE_SHADER, "bolt": BOLT_SHADER, "sigil": SIGIL_SHADER}[key]
		_shaders[key] = s
	return _shaders[key]

static func _mat(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key)
	return m

static func rock_mat() -> StandardMaterial3D:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.albedo_color = Color(0.62, 0.56, 0.5)
		_rock_mat.roughness = 0.95
		_rock_mat.albedo_texture = InfernalFx.noise()
		_rock_mat.uv1_triplanar = true
		_rock_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	return _rock_mat

static func chunk_meshes() -> Array:
	if _chunks.is_empty() and ResourceLoader.exists(Fx.SLAM_CHUNKS):
		var sc: Node = ResCache.inst(Fx.SLAM_CHUNKS)
		for n in sc.find_children("*", "MeshInstance3D", true, false):
			_chunks.append((n as MeshInstance3D).mesh)
		sc.free()
	return _chunks

## Compiles the shaders once per zone by drawing a tiny copy of each (a first cast would hitch).
static func warm(h: Hero) -> void:
	if h == null or not h.is_inside_tree() or h.game == null or h.game.world == null:
		return
	if _warm_world == h.game.world.get_instance_id():
		return
	_warm_world = h.game.world.get_instance_id()
	for k in ["crack", "frost", "ice", "bolt", "sigil"]:
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.quad()
		mi.material_override = _mat(k)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.001
		h.game.world.fx_root.add_child(mi)
		mi.global_position = h.global_position + Vector3(0, 0.05, 0)
		Fx._free_later(mi, 0.3)

static func _piece(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, life: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 6.0
	root.add_child(mi)
	mi.global_position = pos
	Fx._free_later(mi, life)
	return mi

static func _yaw(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

## Dust, mist or ash: InfernalFx's noise-eroded smoke (unlit by fire) in `col`, so it rolls as wisps, not as the flat
## soft blobs a plain particle quad makes. d: the particles() description (no "mesh"/"colors" needed); peak alpha `a`.
static func _dust(root: Node3D, pos: Vector3, col: Color, size: float, a: float, d: Dictionary) -> GPUParticles3D:
	var sm := InfernalFx.smoke_mat(0.0, 1.0)
	sm.set_shader_parameter("smoke", Vector3(col.r, col.g, col.b))
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = sm
	d["mesh"] = q
	d["colors"] = [[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, a)], [0.6, Color(1, 1, 1, a * 0.55)], [1.0, Color(1, 1, 1, 0.0)]]
	if not d.has("angle"):
		d["angle"] = true
	return InfernalFx.particles(root, pos, d)

# ---------------------------------------------------------------- Earthshatter
## The ground split through the wedge ahead of p (direction d, radius r, half-angle half in degrees).
static func earthshatter(h: Hero, root: Node3D, p: Vector3, d: Vector3, r := 5.0, half := 50.0) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	var w = h.game.world
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3(0, 0, -1)
	var yaw := _yaw(d)
	var hr := deg_to_rad(half)
	# the crack, running out from the blow
	var cm := _mat("crack")
	cm.set_shader_parameter("noise_tex", InfernalFx.noise())
	cm.set_shader_parameter("rock", ROCK)
	cm.set_shader_parameter("dust", DUST)
	cm.set_shader_parameter("seed", randf() * 10.0)
	var crack := _piece(root, InfernalFx.wedge_mesh(w, p, yaw, 0.5, r * 1.05, hr * 0.92, 20, 12, 0.08), cm, p, 3.4)
	InfernalFx.tween_param(crack, cm, "reveal", 0.0, 1.1, 0.2)
	InfernalFx.tween_param(crack, cm, "life", 1.0, 0.0, 1.4, 1.9)
	# rock spikes heaving up along the crack and sinking back, the near ones first
	var n: int = [5, 8, 12, 16][tr]
	var shards: Array = []
	for i in n:
		var rr := randf_range(1.0, r * 0.95)
		var a := yaw + randf_range(-hr, hr) * 0.8
		var at: Vector3 = p + Vector3(-sin(a), 0.0, -cos(a)) * rr
		at.y = w.height_at(at.x, at.z) if w != null else p.y
		var sh := _piece(root, InfernalFx.shard_mesh(i), rock_mat(), at + Vector3(0, -1.2, 0), 2.2)
		var up_y: float = root.to_local(at + Vector3(0, -0.05, 0)).y
		var down_y: float = root.to_local(at + Vector3(0, -1.3, 0)).y
		var s := randf_range(0.55, 1.1) * lerpf(1.25, 0.8, rr / r)
		sh.scale = Vector3(s * randf_range(1.4, 2.0), s * randf_range(0.7, 1.1), s * randf_range(1.4, 2.0))
		var out := Vector3(-sin(a), 0, -cos(a))
		sh.rotation = Vector3(0, randf() * TAU, 0)
		sh.rotate(out.cross(Vector3.UP).normalized(), -randf_range(0.15, 0.45))   # leaning away from the blow
		var delay := 0.03 + rr / r * 0.18
		var tw := sh.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(sh, "position:y", up_y, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(randf_range(0.45, 0.7))
		tw.tween_property(sh, "position:y", down_y, 0.55).set_ease(Tween.EASE_IN)
		shards.append(at)
	# chunks thrown out of the crack, pebbles, dust rolling along the ground
	var meshes := chunk_meshes()
	if not meshes.is_empty():
		var nc: int = [4, 7, 10, 14][tr]
		for k in nc:
			var at2: Vector3 = shards[k % shards.size()] if not shards.is_empty() else p + d * 2.0
			var mi := _piece(root, meshes[k % meshes.size()], rock_mat(), at2 + Vector3(0, 0.1, 0), 2.0)
			mi.scale = Vector3.ONE * randf_range(0.45, 1.0)
			var away: Vector3 = (at2 - p) * Vector3(1, 0, 1)
			away = away.normalized() if away.length() > 0.01 else d
			var v := away * randf_range(1.5, 4.0) + Vector3(0, randf_range(4.0, 7.5), 0)
			InfernalFx.fly(mi, v, Vector3(randf_range(-12, 12), randf_range(-8, 8), randf_range(-12, 12)), randf_range(0.9, 1.3), -16.0)
	for k in 3:
		var at3: Vector3 = p + d * (1.2 + k * 1.4)
		InfernalFx.particles(root, at3 + Vector3(0, 0.2, 0), {"amount": [6, 9, 13, 18][tr], "life": 0.7, "explosive": 0.95,
			"shape": "sphere", "r": 0.6, "dir": Vector3.UP, "spread": 40.0, "vel": [4.0, 8.0], "gravity": -16.0,
			"scale": [0.5, 1.0], "size": 0.07, "add": false, "colors": [[0.0, ROCK], [1.0, ROCK]]})
		_dust(root, at3 + Vector3(0, 0.3, 0), DUST_DARK, 1.6, 0.7, {"amount": [4, 6, 9, 12][tr], "life": 1.8, "explosive": 0.8,
			"shape": "box", "box": Vector3(1.2, 0.2, 1.2), "dir": Vector3.UP, "spread": 70.0, "vel": [0.6, 1.8], "gravity": 0.15,
			"damping": [0.8, 1.4], "scale": [0.8, 1.4], "grow": [0.5, 1.7], "spin": 20.0})
	GrassField.impulse(p + d * r * 0.5, r * 0.6, 0.7, 0.4)

# ---------------------------------------------------------------- Frost Nova
static func frost_nova(h: Hero, root: Node3D, p: Vector3, r := 4.0) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	var w = h.game.world
	# frost over the ground, racing out with a bright edge, lingering while the chill does
	var fm := _mat("frost")
	fm.set_shader_parameter("noise_tex", InfernalFx.noise())
	fm.set_shader_parameter("pale", ICE_PALE)
	fm.set_shader_parameter("deep", ICE_DEEP)
	fm.set_shader_parameter("seed", randf() * 10.0)
	var frost := _piece(root, InfernalFx.disc_mesh(w, p, r * 1.08, 48, 6, 0.07), fm, p, 3.6)
	InfernalFx.tween_param(frost, fm, "front", 0.0, 1.0, 0.26).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(frost, fm, "life", 1.0, 0.0, 1.2, 2.2)
	# a ring of ice crystals bursting up behind the front, then shattering
	var n: int = [7, 11, 16, 22][tr]
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / n
		var rr := randf_range(r * 0.45, r * 0.95)
		var out := Vector3(cos(a), 0, sin(a))
		var at: Vector3 = p + out * rr
		at.y = w.height_at(at.x, at.z) if w != null else p.y
		var im := _mat("ice")
		im.set_shader_parameter("pale", ICE_PALE)
		im.set_shader_parameter("deep", ICE_DEEP)
		var c := _piece(root, InfernalFx.shard_mesh(i + 2), im, at, 2.0)
		var s := randf_range(0.5, 1.0) * lerpf(1.2, 0.75, rr / r)
		var full := Vector3(s * randf_range(0.55, 0.85), s * randf_range(1.0, 1.6), s * randf_range(0.55, 0.85))
		c.rotation = Vector3(0, randf() * TAU, 0)
		c.rotate(out.cross(Vector3.UP).normalized(), -randf_range(0.25, 0.6))   # leaning outward
		c.scale = full * 0.02
		var delay := rr / r * 0.22
		var hold := randf_range(0.7, 1.0)
		var tw := c.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(c, "scale", full, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(hold)
		tw.tween_property(c, "scale", full * Vector3(1.15, 0.05, 1.15), 0.14).set_ease(Tween.EASE_IN)
		InfernalFx.tween_param(c, im, "alpha", 1.0, 0.0, 0.14, delay + 0.1 + hold)
		# the shatter: fragments and glints where it stood
		Fx.later(root, delay + 0.1 + hold, func():      # (Fx.later: the zone, and root, may be gone by then)
			InfernalFx.particles(root, at + Vector3(0, 0.5 * full.y, 0), {"amount": [4, 6, 9, 12][tr], "life": 0.6, "explosive": 1.0,
				"shape": "sphere", "r": 0.25, "dir": Vector3.UP, "spread": 70.0, "vel": [2.0, 4.5], "gravity": -12.0,
				"scale": [0.5, 1.1], "size": 0.06, "colors": [[0.0, ICE_PALE], [1.0, Color(ICE_DEEP, 0.0)]]}))
	# the burst at him, cold mist rolling out, glints in the air
	var g := InfernalFx.glow(root, p + Vector3(0, 1.0, 0), 2.2, InfernalFx.glow_mat(ICE_PALE, 2.2, 2.6, 0.5))
	var tg := g.create_tween()
	tg.set_parallel(true)
	tg.tween_property(g, "scale", Vector3.ONE * 3.2, 0.3).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.3)
	Fx._free_later(g, 0.35)
	Fx.flash(root, p + Vector3(0, 1.2, 0), ICE_PALE, 3.0, 0.4, r * 1.6)
	_dust(root, p + Vector3(0, 0.25, 0), Color(0.5, 0.62, 0.72), 1.5, 0.45, {"amount": [6, 10, 14, 20][tr], "life": 1.6, "explosive": 0.9,
		"shape": "ring", "r": 0.8, "r_in": 0.3, "dir": Vector3.UP, "spread": 15.0, "vel": [0.2, 0.6], "radial": [5.0, 8.0],
		"gravity": -0.2, "damping": [2.5, 3.5], "scale": [0.8, 1.4], "grow": [0.6, 1.8], "spin": 15.0})
	InfernalFx.particles(root, p + Vector3(0, 0.6, 0), {"amount": [10, 18, 28, 40][tr], "life": 1.4, "explosive": 0.7,
		"shape": "ring", "r": r * 0.8, "r_in": 0.4, "dir": Vector3.UP, "spread": 30.0, "vel": [0.1, 0.5], "gravity": 0.2,
		"scale": [0.3, 0.9], "size": 0.05, "turb": 0.3,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.15, Color(1, 1, 1)], [0.5, ICE_PALE], [1.0, Color(ICE_PALE, 0.0)]]})
	GrassField.impulse(p, r, 0.5, 0.4)

# ---------------------------------------------------------------- Arc
## Lightning from ps[0] leaping on through each later point (one bolt per leap, 40 ms apart); a fizzle along d when
## nothing was in reach.
static func arc(h: Hero, root: Node3D, ps: PackedVector3Array, d: Vector3) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	if ps.size() < 2:
		var a: Vector3 = ps[0]
		var dd := d.normalized() if d.length() > 0.01 else Vector3(0, 0, -1)
		var end := a + dd * 5.5 + Vector3(0, -0.9, 0)
		bolt(root, a, end, 0.24, 0.07, tr)
		_spark(root, end, tr)
		return
	for i in ps.size() - 1:
		var a2: Vector3 = ps[i]
		var b2: Vector3 = ps[i + 1]
		var delay := 0.04 * i
		if delay <= 0.0:
			_leap(root, a2, b2, tr, i == 0)
		else:
			Fx.later(root, delay, func(): _leap(root, a2, b2, tr, false))

static func _leap(root: Node3D, a: Vector3, b: Vector3, tr: int, first: bool) -> void:
	bolt(root, a, b, 0.3, 0.09 if first else 0.075, tr)
	_spark(root, b, tr)

static func _spark(root: Node3D, at: Vector3, tr: int) -> void:
	Fx.flash(root, at + Vector3(0, 0.4, 0), STORM_GLOW, 3.2, 0.22, 4.5)
	var g := InfernalFx.glow(root, at, 1.1, InfernalFx.glow_mat(STORM_CORE, 3.0, 3.0, 0.9))
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.18)
	Fx._free_later(g, 0.22)
	InfernalFx.particles(root, at, {"amount": [6, 10, 14, 20][tr], "life": 0.35, "explosive": 1.0, "shape": "sphere",
		"r": 0.15, "dir": Vector3.UP, "spread": 180.0, "vel": [4.0, 9.0], "gravity": -9.0, "damping": [3.0, 5.0],
		"scale": [0.4, 0.9], "size": 0.05, "colors": [[0.0, STORM_CORE], [0.5, STORM_GLOW], [1.0, Color(STORM_GLOW, 0.0)]]})

## One lightning bolt from a to b living `dur` seconds: a jagged ribbon facing the camera, struck again with a new
## path every few frames (that's the flicker), with a fork or two; bright white core in a violet-blue glow (or the
## colours given: Thunderstep's are gold).
static func bolt(root: Node3D, a: Vector3, b: Vector3, dur: float, width: float, tr: int, core := STORM_CORE, glow := STORM_GLOW) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := _mat("bolt")
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("glow", glow)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0
	root.add_child(mi)
	mi.global_position = Vector3.ZERO
	mi.top_level = true
	var forks: int = [0, 1, 1, 2][tr]
	var state := {"t": -1.0, "paths": []}
	var draw := func(u: float) -> void:
		if not is_instance_valid(mi):
			return
		var cam: Camera3D = mi.get_viewport().get_camera_3d() if mi.is_inside_tree() else null
		if cam == null:
			return
		var t: float = u * dur
		if t - float(state["t"]) > 0.055 or (state["paths"] as Array).is_empty():
			state["t"] = t
			var paths: Array = [[_jag(a, b, 5, 0.17), width]]
			for k in forks:
				var src: Array = paths[0][0]
				var at: Vector3 = src[randi_range(2, src.size() - 3)]
				var dir: Vector3 = (b - a).normalized() + Vector3(randf_range(-1, 1), randf_range(-0.8, 0.2), randf_range(-1, 1)) * 0.9
				var fl: float = a.distance_to(b) * randf_range(0.2, 0.4)
				paths.append([_jag(at, at + dir.normalized() * fl, 3, 0.2), width * 0.55])
			state["paths"] = paths
		var fade: float = pow(1.0 - u, 1.4) * randf_range(0.65, 1.0)
		im.clear_surfaces()
		for path in state["paths"]:
			_ribbon(im, path[0], float(path[1]), cam.global_position, fade)
	var tw := mi.create_tween()
	tw.tween_method(draw, 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)

## A jagged polyline from a to b: midpoint displacement, `levels` times, each displacement `rough` of the span.
static func _jag(a: Vector3, b: Vector3, levels: int, rough: float) -> Array:
	var pts: Array = [a, b]
	var amp := a.distance_to(b) * rough
	var axis := (b - a).normalized()
	for l in levels:
		var nxt: Array = [pts[0]]
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var side := axis.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
			if side.length() < 0.01:
				side = axis.cross(Vector3.UP)
			nxt.append((p0 + p1) * 0.5 + side.normalized() * amp * randf_range(-1.0, 1.0))
			nxt.append(p1)
		pts = nxt
		amp *= 0.5
	return pts

static func _ribbon(im: ImmediateMesh, pts: Array, width: float, eye: Vector3, alpha: float) -> void:
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var tan: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := tan.cross((eye - p).normalized()).normalized() * width
		var taper := 1.0 - 0.6 * float(i) / float(n - 1)
		var c := Color(1, 1, 1, alpha)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(float(i) / float(n - 1), 0.0))
		im.surface_add_vertex(p - side * taper * 4.0)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(float(i) / float(n - 1), 1.0))
		im.surface_add_vertex(p + side * taper * 4.0)
	im.surface_end()

# ---------------------------------------------------------------- War Cry
static func war_cry(h: Hero, root: Node3D, p: Vector3, r := 8.0) -> void:
	warm(h)
	var tr := InfernalFx.tier(h.game)
	var sm := _mat("sigil")
	sm.set_shader_parameter("war", WAR)
	sm.set_shader_parameter("ember", WAR_EMBER)
	var sg := _piece(root, HolyFx.flat(), sm, p + Vector3(0, 0.07, 0), 1.9)
	sg.scale = Vector3(5.2, 1.0, 5.2)
	sg.rotation.y = randf() * TAU
	InfernalFx.tween_param(sg, sm, "draw", 0.0, 1.0, 0.14)
	sm.set_shader_parameter("flare", 1.0)
	InfernalFx.tween_param(sg, sm, "flare", 1.0, 0.0, 0.45, 0.1)
	InfernalFx.tween_param(sg, sm, "life", 1.0, 0.0, 1.1, 0.6)
	HolyFx.shockwave(root, h.game, p, r + 0.5, 0.5, 0.024)
	Fx.flash(root, p + Vector3(0, 1.4, 0), WAR_EMBER, 3.2, 0.5, r)
	# the wave of dust and ash rolling out along the ground to the edge of the cry
	_dust(root, p + Vector3(0, 0.3, 0), Color(0.2, 0.17, 0.15), 1.4, 0.7, {"amount": [10, 16, 24, 32][tr], "life": 0.95, "explosive": 1.0,
		"shape": "ring", "r": 0.9, "r_in": 0.5, "dir": Vector3.UP, "spread": 10.0, "vel": [0.1, 0.4], "radial": [16.0, 22.0],
		"damping": [6.0, 8.0], "gravity": 0.3, "scale": [0.8, 1.3], "grow": [0.5, 1.6], "spin": 30.0})
	# embers rising round him
	InfernalFx.particles(root, p + Vector3(0, 0.4, 0), {"amount": [10, 16, 24, 34][tr], "life": 1.5, "explosive": 0.75,
		"shape": "ring", "r": 1.4, "r_in": 0.6, "dir": Vector3.UP, "spread": 25.0, "vel": [1.2, 2.8], "gravity": 0.4,
		"damping": [0.8, 1.4], "scale": [0.4, 1.0], "size": 0.06, "turb": 0.6,
		"colors": [[0.0, Color(WAR_EMBER, 0.0)], [0.1, WAR_EMBER], [0.6, WAR], [1.0, Color(WAR, 0.0)]]})
	GrassField.impulse(p, r, 0.75, 0.45)

# ---------------------------------------------------------------- monsters' heavy blows (Enemy.special_fx)
## A heavy blow into the ground at p (a boss's slam, the bear's maul): the crust cracks in a ring round it with six
## fissures, rock spikes heave up round the edge, chunks fly, dust rolls out (the generic ring and burst it was).
static func ground_slam(game, root: Node3D, p: Vector3, r: float) -> void:
	var tr := InfernalFx.tier(game)
	var w = game.world if game != null else null
	var cm := _mat("crack")
	cm.set_shader_parameter("noise_tex", InfernalFx.noise())
	cm.set_shader_parameter("rock", ROCK)
	cm.set_shader_parameter("dust", DUST)
	cm.set_shader_parameter("seed", randf() * 10.0)
	cm.set_shader_parameter("full_circle", 1.0)
	var crack := _piece(root, InfernalFx.wedge_mesh(w, p, randf() * TAU, 0.35, r, PI, 48, 10, 0.08), cm, p, 3.2)
	InfernalFx.tween_param(crack, cm, "reveal", 0.0, 1.1, 0.16)
	InfernalFx.tween_param(crack, cm, "life", 1.0, 0.0, 1.3, 1.8)
	var n: int = [4, 7, 10, 14][tr]
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / n
		var out := Vector3(cos(a), 0, sin(a))
		var at: Vector3 = p + out * r * randf_range(0.55, 0.9)
		at.y = w.height_at(at.x, at.z) if w != null else p.y
		var sh := _piece(root, InfernalFx.shard_mesh(i), rock_mat(), at + Vector3(0, -1.2, 0), 2.0)
		var up_y: float = root.to_local(at + Vector3(0, -0.05, 0)).y
		var down_y: float = root.to_local(at + Vector3(0, -1.3, 0)).y
		var s := randf_range(0.5, 1.0)
		sh.scale = Vector3(s * randf_range(1.4, 1.9), s * randf_range(0.7, 1.1), s * randf_range(1.4, 1.9))
		sh.rotation = Vector3(0, randf() * TAU, 0)
		sh.rotate(out.cross(Vector3.UP).normalized(), -randf_range(0.2, 0.5))
		var tw := sh.create_tween()
		tw.tween_interval(0.02 + randf() * 0.08)
		tw.tween_property(sh, "position:y", up_y, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(randf_range(0.4, 0.6))
		tw.tween_property(sh, "position:y", down_y, 0.5).set_ease(Tween.EASE_IN)
	var meshes := chunk_meshes()
	if not meshes.is_empty():
		for k in [3, 5, 8, 10][tr]:
			var a2 := randf() * TAU
			var mi := _piece(root, meshes[k % meshes.size()], rock_mat(), p + Vector3(cos(a2), 0.1, sin(a2)) * 0.6, 2.0)
			mi.scale = Vector3.ONE * randf_range(0.4, 0.9)
			var v := Vector3(cos(a2), 0, sin(a2)) * randf_range(2.0, 4.5) + Vector3(0, randf_range(4.0, 7.0), 0)
			InfernalFx.fly(mi, v, Vector3(randf_range(-12, 12), randf_range(-8, 8), randf_range(-12, 12)), randf_range(0.9, 1.2), -16.0)
	_dust(root, p + Vector3(0, 0.3, 0), DUST_DARK, 1.6, 0.75, {"amount": [6, 9, 13, 18][tr], "life": 1.6, "explosive": 0.9,
		"shape": "ring", "r": 0.8, "r_in": 0.2, "dir": Vector3.UP, "spread": 20.0, "vel": [0.3, 0.8], "radial": [7.0, 11.0],
		"damping": [3.0, 4.0], "gravity": 0.15, "scale": [0.8, 1.4], "grow": [0.5, 1.7], "spin": 20.0})
	GrassField.impulse(p, r, 0.75, 0.45)

## A boss's fire nova: a ring of hellfire racing out to r along the ground, embers flung up, the air shimmering behind.
static func fire_nova(game, root: Node3D, p: Vector3, r: float, col := Color(1.0, 0.4, 0.1)) -> void:
	var tr := InfernalFx.tier(game)
	var n: int = [10, 14, 20, 26][tr]
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.25, 0.25)) / n
		var out := Vector3(cos(a), 0, sin(a))
		var m := InfernalFx.flame_mat(0.75, 1.2)
		if col.g > col.r:
			# a poison nova: the same fire in sick green
			m.set_shader_parameter("crimson", Color(0.05, 0.3, 0.06))
			m.set_shader_parameter("molten", col)
			m.set_shader_parameter("whitehot", Color(0.85, 1.0, 0.7))
		var hh := randf_range(1.1, 1.8)
		var f := InfernalFx.flame(root, p + out * 0.6 + Vector3(0, hh * 0.42, 0), Vector2(hh * 0.6, hh), m)
		var to := p + out * r * randf_range(0.9, 1.0) + Vector3(0, hh * 0.3, 0)
		var tw := f.create_tween()
		tw.set_parallel(true)
		tw.tween_property(f, "global_position", to, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(f, "scale", Vector3(hh * 0.45, hh * 0.55, 1.0), 0.5)
		InfernalFx.tween_param(f, m, "alpha", 1.0, 0.0, 0.3, 0.3)
		Fx._free_later(f, 0.65)
	InfernalFx.particles(root, p + Vector3(0, 0.4, 0), {"amount": [12, 20, 30, 40][tr], "life": 0.9, "explosive": 0.95,
		"shape": "ring", "r": 1.0, "r_in": 0.4, "dir": Vector3.UP, "spread": 35.0, "vel": [2.0, 5.0], "radial": [6.0, 10.0],
		"gravity": -3.0, "damping": [1.0, 2.0], "scale": [0.4, 1.0], "size": 0.07,
		"colors": [[0.0, Color(1.0, 0.95, 0.8)], [0.3, col], [1.0, Color(col.r * 0.5, col.g * 0.3, col.b * 0.2, 0.0)]]})
	HolyFx.shockwave(root, game, p, r + 0.5, 0.55, 0.022)
	Fx.flash(root, p + Vector3(0, 1.2, 0), col, 4.0, 0.5, r * 1.3)
	GrassField.impulse(p, r, 0.7, 0.5)

## A summoning: a dark circle burns into the ground and smoke rises off it where the summoned will climb out.
static func summon_circle(game, root: Node3D, p: Vector3, r: float, col := Color(0.7, 0.2, 1.0)) -> void:
	var tr := InfernalFx.tier(game)
	var sm := _mat("sigil")
	sm.set_shader_parameter("war", col.darkened(0.3))
	sm.set_shader_parameter("ember", col.lightened(0.3))
	var sg := _piece(root, HolyFx.flat(), sm, p + Vector3(0, 0.07, 0), 2.2)
	sg.scale = Vector3(r * 1.6, 1.0, r * 1.6)
	sg.rotation.y = randf() * TAU
	InfernalFx.tween_param(sg, sm, "draw", 0.0, 1.0, 0.3)
	sm.set_shader_parameter("flare", 0.6)
	InfernalFx.tween_param(sg, sm, "flare", 0.6, 0.0, 0.6, 0.3)
	InfernalFx.tween_param(sg, sm, "life", 1.0, 0.0, 1.0, 1.0)
	InfernalFx.particles(root, p + Vector3(0, 0.2, 0), {"amount": [6, 10, 14, 18][tr], "life": 1.8, "explosive": 0.6,
		"shape": "ring", "r": r * 0.7, "r_in": r * 0.2, "dir": Vector3.UP, "spread": 15.0, "vel": [0.6, 1.4], "gravity": 0.3,
		"damping": [0.6, 1.0], "scale": [0.8, 1.3], "size": 1.1, "grow": [0.5, 1.5], "angle": true, "spin": 15.0, "add": false,
		"colors": [[0.0, Color(0.06, 0.03, 0.08, 0.0)], [0.15, Color(0.06, 0.03, 0.08, 0.6)], [1.0, Color(0.05, 0.02, 0.06, 0.0)]]})
	Fx.flash(root, p + Vector3(0, 1.0, 0), col, 2.5, 0.6, r * 1.4)

# ---------------------------------------------------------------- shaders
## The cracked ground of Earthshatter on InfernalFx.wedge_mesh (UV.x across the wedge, UV.y out along it): a wandering
## main fissure, a web of cracks from cell noise, the broken crust lifted round them in dust and rock colours. Lit
## like the ground; its front runs out with `reveal`.
const CRACK_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 rock : source_color = vec4(0.3, 0.26, 0.22, 1.0);
uniform vec4 dust : source_color = vec4(0.56, 0.49, 0.4, 1.0);
uniform float reveal = 0.0;
uniform float life = 1.0;
uniform float seed = 0.0;
uniform float full_circle = 0.0;   // 1: a whole ring round the blow (UV.x goes round), six fissures radiating out
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
// cell borders (F2 - F1): 0 on the cracks between the plates of broken crust
float crust(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return sqrt(d2) - sqrt(d1);
}
void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, uv * vec2(2.0, 3.0) + vec2(seed, 0.0)).r;
	float front = smoothstep(reveal + 0.04, reveal - 0.06, uv.y + (n - 0.5) * 0.2);
	float sides = mix(smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x), 1.0, full_circle);
	float edge = sides * smoothstep(1.0, 0.8, uv.y) * smoothstep(0.0, 0.06, uv.y);
	vec2 cuv = vec2(uv.x * mix(9.0, 30.0, full_circle), uv.y * 10.0) + vec2(seed * 3.7, 0.0);
	float c = crust(cuv + (vec2(n, texture(noise_tex, uv * 4.0).r) - 0.5) * 0.6);
	float crack = 1.0 - smoothstep(0.03, 0.09, c);
	float near = 1.0 - smoothstep(0.0, 0.3, c);
	float wander = (texture(noise_tex, vec2(uv.y * 1.3 + seed, 0.37)).r - 0.5) * 0.3;
	float mid = mix(abs(uv.x - 0.5 + wander), abs(fract(uv.x * 6.0 + wander * 0.4) - 0.5) * 0.6, full_circle);
	float fissure = 1.0 - smoothstep(0.0, 0.025 + 0.03 * uv.y, mid);
	float dark = max(crack * (0.6 + 0.4 * (1.0 - uv.y)), fissure);
	vec3 col = mix(dust.rgb, rock.rgb, 0.35 + 0.65 * near) * (0.6 + 0.4 * n);
	col = mix(col, vec3(0.015, 0.012, 0.01), dark);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = clamp((0.15 + 0.3 * near + 0.9 * dark) * front * edge * life, 0.0, 1.0);
}
"""

## Frost Nova's frost on InfernalFx.disc_mesh (UV 0.5 at the centre): feathered radial streaks and crystal speckle,
## glossy, with a bright band at the advancing `front`.
const FROST_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 pale : source_color = vec4(0.8, 0.94, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.2, 0.5, 0.92, 1.0);
uniform float front = 0.0;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float n = texture(noise_tex, UV * 2.6 + vec2(seed, 0.0)).r;
	float n2 = texture(noise_tex, UV * 9.0 + vec2(0.3, seed)).r;
	float streak = pow(abs(sin(a * 19.0 + n * 7.0)), 7.0) * smoothstep(0.1, 0.8, r);
	float fern = pow(abs(sin(a * 47.0 + n2 * 9.0)), 12.0) * smoothstep(0.3, 0.9, r);
	float crystals = smoothstep(0.52, 0.8, n2);
	float wobble = (n - 0.5) * 0.14;
	float inside = smoothstep(front + 0.01, front - 0.1, r + wobble);
	float band = smoothstep(front - 0.16, front, r + wobble) * inside;
	float body = 0.3 + 0.35 * crystals + 0.5 * streak + 0.35 * fern;
	ALBEDO = mix(deep.rgb, pale.rgb, 0.5 + 0.5 * crystals);
	ROUGHNESS = 0.2;
	SPECULAR = 0.9;
	EMISSION = pale.rgb * (0.2 * crystals + 0.15 * streak + 1.4 * band) * life;
	ALPHA = clamp(body * inside * smoothstep(1.0, 0.86, r) * life, 0.0, 1.0);
}
"""

## Ice crystals on InfernalFx.shard_mesh (UV.y up the shard): deep blue at the foot to pale at the tip, glossy, a
## cold fresnel glow at the edges, a little see-through.
const ICE_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec4 pale : source_color = vec4(0.8, 0.94, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.2, 0.5, 0.92, 1.0);
uniform float alpha = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float h = clamp(UV.y, 0.0, 1.0);
	vec3 col = mix(deep.rgb, pale.rgb, 0.3 + 0.7 * h);
	ALBEDO = col * 0.55;
	ROUGHNESS = 0.06;
	SPECULAR = 1.0;
	EMISSION = pale.rgb * pow(f, 2.2) * 1.5 + deep.rgb * 0.2 + pale.rgb * smoothstep(0.85, 1.0, h) * 0.6;
	ALPHA = clamp(alpha * (0.6 + 0.4 * f), 0.0, 1.0);
}
"""

## Lightning on a camera-facing ribbon (UV.y across it): a thin white-hot core inside a wider violet-blue glow, HDR
## so the glow pass catches it; COLOR.a carries the flicker.
const BOLT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 core : source_color = vec4(0.93, 0.95, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.5, 0.56, 1.0, 1.0);
uniform float energy = 3.5;
void fragment() {
	float v = abs(UV.y - 0.5) * 2.0;
	float c = exp(-v * v * 60.0);
	float g = exp(-v * v * 6.0) * 0.5;
	ALBEDO = (core.rgb * c * 1.8 + glow.rgb * g) * energy;
	ALPHA = clamp((c + g) * COLOR.a, 0.0, 1.0);
}
"""

## War Cry's sigil on a flat quad (UV 0.5 at the centre): a toothed outer ring, an inner ring and an eight-bladed
## star, crimson burning to ember at the `flare`, drawn round by `draw`.
const SIGIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 war : source_color = vec4(0.86, 0.12, 0.06, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.45, 0.14, 1.0);
uniform float draw = 0.0;
uniform float flare = 0.0;
uniform float life = 1.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float u = (atan(d.y, d.x) + PI) / TAU;
	float sweep = smoothstep(draw + 0.01, draw - 0.01, u);
	float teeth = 0.88 - 0.06 * abs(fract(u * 28.0) - 0.5) * 2.0;
	float ring = smoothstep(0.03, 0.0, abs(r - teeth));
	float ring2 = smoothstep(0.018, 0.0, abs(r - 0.72));
	float k = abs(fract(u * 8.0 + 0.0625) - 0.5) * 2.0;
	float blade_r = 0.2 + 0.46 * (1.0 - k);
	float blade = smoothstep(0.035, 0.0, abs(r - blade_r)) * step(0.18, r) * step(r, 0.7);
	float spoke = smoothstep(0.06, 0.0, k * r) * step(0.16, r) * step(r, 0.66);
	float m = max(max(ring, ring2), max(blade, spoke * 0.6));
	float fade = smoothstep(1.0, 0.9, r);
	vec3 col = mix(war.rgb, ember.rgb, 0.3 + 0.7 * flare) * (1.4 + 2.6 * flare);
	ALBEDO = col;
	ALPHA = clamp(m * sweep * fade * life, 0.0, 1.0);
}
"""
