class_name Props
extends RefCounted
## Environment props and buildings (Act I: moorland camp style).


# Palette for the moor camp.
const WOOD := Color(0.30, 0.22, 0.15)
const WOOD_D := Color(0.18, 0.13, 0.09)
const HIDE := Color(0.36, 0.27, 0.19)
const HIDE_D := Color(0.24, 0.18, 0.12)
const STONE := Color(0.36, 0.36, 0.34)
const STONE_D := Color(0.24, 0.24, 0.23)
const CLAY := Color(0.46, 0.34, 0.24)
const CLAY_D := Color(0.32, 0.22, 0.15)
const MOSS := Color(0.22, 0.28, 0.12)
const IRON := Color(0.22, 0.22, 0.23)

static var _rocks := {}

## Wood and hide can burn through in A3 (holes with glowing edges).
static func _breakable(m: ShaderMaterial) -> Material:
	m.set_shader_parameter("breakable", 1.0)
	return m
static func wood() -> Material: return _breakable(Mats.world(WOOD, WOOD_D, 0.9, 1.0, 0.0, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0))
static func wood_dark() -> Material: return _breakable(Mats.world(WOOD_D, WOOD_D.darkened(0.3), 0.9, 1.0, 0.0, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0))
static func hide_m() -> Material: return _breakable(Mats.world(HIDE, HIDE_D, 0.95, 0.8))
static func stone() -> Material: return Mats.world(STONE, STONE_D, 0.92, 1.3, 0.55, MOSS)
static func stone_clean() -> Material: return Mats.world(STONE.lightened(0.08), STONE_D, 0.9, 1.6, 0.15, MOSS)
static func clay() -> Material: return Mats.world(CLAY, CLAY_D, 0.85, 2.0)
static func iron() -> Material: return Mats.world(IRON, IRON.darkened(0.4), 0.45, 2.0, 0.0, MOSS, true, 0.8)

## Irregular rock mesh (faceted). Variants are cached.
static func rock_mesh(variant: int, roughness: float = 0.35) -> Mesh:
	var key := "%d_%.2f" % [variant, roughness]
	if _rocks.has(key):
		return _rocks[key]
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = variant * 31 + 7
	n.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + n.get_noise_3dv(v * 1.0) * roughness * 2.0
		var vv := v * d
		vv.y = vv.y * 0.75
		if vv.y < -0.15:
			vv.y = -0.15 + (vv.y + 0.15) * 0.3
		moved[i] = vv
	for i in range(0, idx.size(), 3):
		var a := moved[idx[i]]; var b := moved[idx[i + 1]]; var c := moved[idx[i + 2]]
		var fn := (b - a).cross(c - a).normalized()
		var centre := (a + b + c) / 3.0
		if fn.dot(centre) < 0.0:
			fn = -fn
		Geo.tri(st, a, b, c, fn, fn, fn)
	var m := st.commit()
	_rocks[key] = m
	return m

## Merges a composite prop into one mesh (one surface per material) for MultiMesh use.
static func bake(node: Node3D, deindex := false) -> ArrayMesh:
	var groups := {}
	var mats := {}
	_collect(node, Transform3D.IDENTITY, groups, mats, true, deindex)
	var out := ArrayMesh.new()
	for k in groups.keys():
		var st: SurfaceTool = groups[k]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mats[k])
	node.free()
	return out

static var _flat := {}

## Non-indexed copy of a mesh, so indexed and non-indexed meshes can share one SurfaceTool.
static func _flat_mesh(mesh: Mesh) -> Mesh:
	var id := mesh.get_instance_id()
	if _flat.has(id):
		return _flat[id]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, s)
		st.deindex()
		st.commit(out)
	_flat[id] = out
	return out

static func _collect(n: Node, xf: Transform3D, groups: Dictionary, mats: Dictionary, is_root: bool, deindex := false) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m: Material = mi.material_override
		var key := m.get_instance_id()
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = st
			mats[key] = m
		var mesh: Mesh = _flat_mesh(mi.mesh) if deindex else mi.mesh
		for s in mesh.get_surface_count():
			(groups[key] as SurfaceTool).append_from(mesh, s, t)
	for c in n.get_children():
		_collect(c, t, groups, mats, false, deindex)

static func multimesh(parent: Node3D, mesh: Mesh, xforms: Array, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

# ---------------------------------------------------------------- fire & lights
static func fire(parent: Node3D, pos: Vector3, s: float = 1.0, col: Color = Color(1.0, 0.55, 0.2), light := true, shadow := false, smoke := true) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var flames := GPUParticles3D.new()
	flames.amount = int(24 * s) + 6
	flames.lifetime = 0.7
	flames.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12 * s
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.5 * s
	pm.initial_velocity_max = 1.1 * s
	pm.gravity = Vector3(0, 1.5 * s, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.78, 0.42, 0.9))
	g.set_color(1, Color(0.5, 0.06, 0.0, 0.0))
	g.add_point(0.3, Color(col.r, col.g * 0.85, col.b * 0.6, 0.75))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	flames.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.48) * s
	q.material = Mats.particle_mat(true, Color(1.3, 1.15, 1.0))
	flames.draw_pass_1 = q
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flames)
	# embers
	var em := GPUParticles3D.new()
	em.amount = int(10 * s) + 2
	em.lifetime = 2.2
	em.local_coords = false
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = 0.15 * s
	epm.direction = Vector3(0, 1, 0)
	epm.spread = 25.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.6
	epm.gravity = Vector3(0.2, 0.6, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 1.5
	epm.turbulence_noise_scale = 2.0
	epm.scale_min = 0.5
	epm.scale_max = 1.0
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.7, 0.3, 1.0))
	eg.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = eg
	epm.color_ramp = egt
	em.process_material = epm
	var eq := QuadMesh.new()
	eq.size = Vector2(0.05, 0.05)
	eq.material = Mats.particle_mat(true, Color(3, 3, 3))
	em.draw_pass_1 = eq
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(em)
	if smoke:
		var sm := GPUParticles3D.new()
		sm.amount = int(6 * s) + 2
		sm.lifetime = 3.0
		sm.local_coords = false
		var spm := ParticleProcessMaterial.new()
		spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		spm.emission_sphere_radius = 0.1 * s
		spm.direction = Vector3(0, 1, 0)
		spm.spread = 15.0
		spm.initial_velocity_min = 0.4
		spm.initial_velocity_max = 0.8
		spm.gravity = Vector3(0.15, 0.3, 0)
		spm.scale_min = 1.0
		spm.scale_max = 2.0
		var ssc := Curve.new()
		ssc.add_point(Vector2(0, 0.4))
		ssc.add_point(Vector2(1, 1.6))
		var ssct := CurveTexture.new()
		ssct.curve = ssc
		spm.scale_curve = ssct
		var sg := Gradient.new()
		sg.set_color(0, Color(0.2, 0.18, 0.16, 0.0))
		sg.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
		sg.add_point(0.25, Color(0.18, 0.17, 0.16, 0.35))
		var sgt := GradientTexture1D.new()
		sgt.gradient = sg
		spm.color_ramp = sgt
		sm.process_material = spm
		var sq := QuadMesh.new()
		sq.size = Vector2(0.7, 0.7) * s
		sq.material = Mats.particle_mat(false)
		sm.draw_pass_1 = sq
		sm.position = Vector3(0, 0.4 * s, 0)
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sm)
	if light:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 2.2 * s
		l.omni_range = 7.0 * s
		l.omni_attenuation = 1.4
		l.shadow_enabled = shadow
		l.light_volumetric_fog_energy = 1.5
		l.position = Vector3(0, 0.35 * s, 0)
		l.add_to_group("flicker")
		l.set_meta("base", l.light_energy)
		root.add_child(l)
	return root

## Declares what a prop blocks on the ground, in its own space: a radius, or a box half-size
## (x across, y along local z), optionally offset. World.solid(node) registers it where the
## prop ends up, with the node's yaw and scale.
static func footprint(root: Node3D, shape: Variant, at := Vector3.ZERO) -> Node3D:
	var f := {"at": at}
	if shape is Vector2:
		f["half"] = shape
	else:
		f["r"] = float(shape)
	root.set_meta("footprint", f)
	return root

# ---------------------------------------------------------------- small props
static func tripod_torch(parent: Node3D, pos: Vector3, shadow := false) -> Node3D:
	var root := Models.N(parent, "torch", pos, Vector3(0, randf() * 360.0, 0))
	var wm := wood_dark()
	for i in 3:
		var a := TAU * i / 3.0
		Models.seg(root, Vector3(cos(a) * 0.38, 0, sin(a) * 0.38), Vector3(cos(a) * 0.04, 1.75, sin(a) * 0.04), 0.035, 0.028, wm, 6)
	Models.seg(root, Vector3(0, 1.0, 0), Vector3(0, 1.9, 0), 0.03, 0.03, wm, 6)
	Models.P(root, Geo.lathe([Vector2(0.03, 0), Vector2(0.11, 0.06), Vector2(0.14, 0.14), Vector2(0.12, 0.15), Vector2(0.0, 0.1)], 12, "tbowl"), iron(), Vector3(0, 1.88, 0))
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		Models.seg(root, Vector3(cos(a) * 0.3, 1.2, sin(a) * 0.3), Vector3(cos(a + 2.1) * 0.3, 1.2, sin(a + 2.1) * 0.3), 0.012, 0.012, wm, 4)
	fire(root, Vector3(0, 2.05, 0), 0.75, Color(1.0, 0.55, 0.22), true, shadow)
	return footprint(root, 0.36)

static func pot(parent: Node3D, pos: Vector3, kind: int, s: float = 1.0) -> Node3D:
	var profiles := [
		[Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.24, 0.16), Vector2(0.22, 0.34), Vector2(0.11, 0.46), Vector2(0.1, 0.52), Vector2(0.14, 0.56), Vector2(0.12, 0.58), Vector2(0.0, 0.5)],
		[Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.17, 0.1), Vector2(0.19, 0.28), Vector2(0.14, 0.5), Vector2(0.07, 0.66), Vector2(0.07, 0.78), Vector2(0.12, 0.84), Vector2(0.1, 0.86), Vector2(0.0, 0.8)],
		[Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.24, 0.05), Vector2(0.3, 0.14), Vector2(0.27, 0.15), Vector2(0.0, 0.09)],
		[Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.2, 0.12), Vector2(0.2, 0.3), Vector2(0.17, 0.36), Vector2(0.0, 0.33)],
	]
	var cols := [CLAY, CLAY.lightened(0.12), Color(0.55, 0.5, 0.42), CLAY_D]
	var m := Mats.world(cols[kind % 4], (cols[kind % 4] as Color).darkened(0.15), 0.8, 2.5, 0.0, MOSS)
	var root := Models.N(parent, "pot", pos, Vector3(0, randf() * 360.0, 0))
	s *= 1.35
	Models.P(root, Geo.lathe(profiles[kind % 4], 16, "pot%d" % (kind % 4)), m, Vector3.ZERO, Vector3.ZERO, Vector3(s, s, s))
	return root

static func cauldron(parent: Node3D, pos: Vector3, liquid: Color) -> Node3D:
	var root := Models.N(parent, "cauldron", pos)
	var im := iron()
	Models.P(root, Geo.lathe([Vector2(0.0, 0.05), Vector2(0.25, 0.08), Vector2(0.4, 0.25), Vector2(0.42, 0.45), Vector2(0.36, 0.6), Vector2(0.4, 0.63), Vector2(0.36, 0.64), Vector2(0.0, 0.5)], 18, "cauldron"), im)
	for i in 3:
		var a := TAU * i / 3.0
		Models.seg(root, Vector3(cos(a) * 0.3, 0.12, sin(a) * 0.3), Vector3(cos(a) * 0.36, -0.0, sin(a) * 0.36), 0.04, 0.03, im, 6)
	var lm := Mats.mat(liquid, 0.1, 0.0, liquid, 1.6)
	Models.P(root, Geo.cyl(0.35, 0.35, 0.02, 18), lm, Vector3(0, 0.56, 0))
	footprint(root, 0.44)
	fire(root, Vector3(0, 0.0, 0), 0.6, Color(1.0, 0.5, 0.2), false, false, false)
	var bub := GPUParticles3D.new()
	bub.amount = 10
	bub.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.3, 0)
	var g := Gradient.new()
	g.set_color(0, Color(liquid.r, liquid.g, liquid.b, 0.8))
	g.set_color(1, Color(liquid.r, liquid.g, liquid.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	bub.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	q.material = Mats.particle_mat(true, Color(1.5, 1.5, 1.5))
	bub.draw_pass_1 = q
	bub.position = Vector3(0, 0.6, 0)
	root.add_child(bub)
	var l := OmniLight3D.new()
	l.light_color = liquid
	l.light_energy = 1.2
	l.omni_range = 3.5
	l.position = Vector3(0, 0.9, 0)
	root.add_child(l)
	return root

static func crate(parent: Node3D, pos: Vector3, s: float = 1.0) -> Node3D:
	var root := Models.N(parent, "crate", pos, Vector3(0, randf_range(-20, 20), 0))
	var wm := wood()
	var dm := wood_dark()
	Models.P(root, Geo.box(0.7 * s, 0.6 * s, 0.7 * s), wm, Vector3(0, 0.3 * s, 0))
	for y in [0.03, 0.57]:
		Models.P(root, Geo.box(0.74 * s, 0.06 * s, 0.74 * s), dm, Vector3(0, y * s, 0))
	for x in [-1, 1]:
		for z in [-1, 1]:
			Models.P(root, Geo.box(0.07 * s, 0.6 * s, 0.07 * s), dm, Vector3(x * 0.34 * s, 0.3 * s, z * 0.34 * s))
	return footprint(root, Vector2(0.37, 0.37) * s)

static func barrel(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Models.N(parent, "barrel", pos, Vector3(0, randf() * 360.0, 0))
	Models.P(root, Geo.lathe([Vector2(0.0, 0.0), Vector2(0.27, 0.0), Vector2(0.33, 0.4), Vector2(0.27, 0.8), Vector2(0.0, 0.8)], 16, "barrel"), wood())
	for y in [0.1, 0.4, 0.7]:
		Models.P(root, Geo.torus(0.28 + (0.04 if y == 0.4 else 0.0), 0.31 + (0.04 if y == 0.4 else 0.0), 18, 4), iron(), Vector3(0, y, 0))
	return footprint(root, 0.34)

static func log_pile(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Models.N(parent, "logs", pos, Vector3(0, randf() * 360.0, 0))
	var wm := wood()
	for i in 6:
		var row := 0 if i < 3 else (1 if i < 5 else 2)
		var col := i if i < 3 else (i - 3 if i < 5 else 0)
		var x := (col - (1.0 if row == 0 else (0.5 if row == 1 else 0.0))) * 0.28
		Models.P(root, Geo.cyl(0.13, 0.14, 1.4, 10), wm, Vector3(x, 0.13 + row * 0.24, 0), Vector3(90, 0, randf_range(-3, 3)))
	return footprint(root, Vector2(0.42, 0.7))

static func campfire(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Models.N(parent, "campfire", pos)
	var sm := stone()
	for i in 10:
		var a := TAU * i / 10.0
		var r := Models.P(root, rock_mesh(i % 5, 0.25), sm, Vector3(cos(a) * 0.8, 0.05, sin(a) * 0.8), Vector3(0, randf() * 360.0, 0), Vector3(0.35, 0.3, 0.3))
		r.name = "stone"
	var wm := wood_dark()
	for i in 5:
		var a := TAU * i / 5.0
		Models.seg(root, Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55), Vector3(0, 0.45, 0), 0.07, 0.04, wm, 6)
	Models.P(root, Geo.cyl(0.5, 0.5, 0.02, 12), Mats.world(Color(0.06, 0.05, 0.04), Color(0.15, 0.08, 0.04), 1.0, 2.0, 0.0, MOSS, false, 0.0, Color(1.0, 0.3, 0.05), 0.6), Vector3(0, 0.02, 0))
	fire(root, Vector3(0, 0.2, 0), 1.6, Color(1.0, 0.52, 0.2), true, true)
	return footprint(root, 0.95)

static func banner(parent: Node3D, pos: Vector3, col: Color, trim: Color) -> Node3D:
	var root := Models.N(parent, "banner", pos)
	Models.seg(root, Vector3.ZERO, Vector3(0, 3.2, 0), 0.05, 0.04, wood_dark(), 6)
	Models.seg(root, Vector3(-0.05, 3.0, 0), Vector3(0.75, 3.0, 0), 0.025, 0.025, wood_dark(), 5)
	var cm := ShaderMaterial.new()
	cm.shader = Mats.shader("cloth")
	cm.set_shader_parameter("albedo", col)
	cm.set_shader_parameter("trim", trim)
	cm.set_shader_parameter("wave", 1.0)
	Models.P(root, Geo.quad(0.65, 1.3), cm, Vector3(0.36, 2.35, 0), Vector3(0, 0, 0))
	return footprint(root, 0.12)

# ---------------------------------------------------------------- structures
## Hide tent on crooked poles; door faces +Z.
static func hide_tent(parent: Node3D, pos: Vector3, rot_y: float, w: float = 3.2, d: float = 3.6, h: float = 2.4) -> Node3D:
	var root := Models.N(parent, "tent", pos, Vector3(0, rot_y, 0))
	footprint(root, Vector2(w * 0.5, d * 0.5 + 0.1))
	var wm := wood_dark()
	var hm := Mats.world(HIDE, HIDE_D, 0.95, 0.7)
	hm = hm.duplicate()
	hm.set_shader_parameter("occlude", 1.0)
	# two sloped sheets with ragged lower edges
	for side in [1, -1]:
		var pts := PackedVector2Array()
		var slope := sqrt(pow(w * 0.5, 2) + h * h)
		pts.append(Vector2(-d * 0.5 - 0.15, slope + 0.05))
		pts.append(Vector2(d * 0.5 + 0.15, slope + 0.05))
		var n := 9
		for i in n + 1:
			var t := 1.0 - float(i) / n
			var x := lerpf(-d * 0.5 - 0.2, d * 0.5 + 0.2, t)
			pts.append(Vector2(x, randf_range(-0.05, 0.25)))
		var sheet := Geo.extrude(pts, 0.04)
		var sh := Models.P(root, sheet, hm)
		var ang := atan2(h, w * 0.5)
		sh.basis = Basis(Vector3(0, 1, 0), PI * 0.5) * Basis(Vector3(0, 0, 1), 0)
		sh.rotation = Vector3(0, PI * 0.5, 0)
		sh.rotate_object_local(Vector3(1, 0, 0), 0.0)
		# position sheet: lower edge at x = side * w/2, rising to ridge at centre
		var t3 := Transform3D()
		t3 = t3.rotated(Vector3(0, 0, 1), side * -(PI * 0.5 - ang))
		t3 = Transform3D(Basis(Vector3(0, 1, 0), PI * 0.5), Vector3.ZERO) * t3
		sh.transform = Transform3D(Basis(Vector3(0, 0, 1), side * (PI * 0.5 - ang)) * Basis(Vector3(0, 1, 0), PI * 0.5), Vector3(side * w * 0.5, 0.0, 0))
	# back wall triangle
	var back := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(0, h)])
	Models.P(root, Geo.extrude(back, 0.04, "tentback%.2f%.2f" % [w, h]), hm, Vector3(0, 0, -d * 0.5))
	# dark interior
	Models.P(root, Geo.box(w * 0.7, 0.02, d * 0.9), Mats.world(Color(0.06, 0.05, 0.04), Color(0.04, 0.03, 0.02), 1.0, 1.0, 0.0, MOSS, false), Vector3(0, 0.01, 0))
	# crooked poles poking through ridge
	for z in [-d * 0.5 - 0.1, d * 0.5 + 0.1]:
		Models.seg(root, Vector3(-0.15, 0, z), Vector3(0.12, h + 0.55, z + randf_range(-0.1, 0.1)), 0.05, 0.035, wm, 6)
		Models.seg(root, Vector3(0.18, 0, z), Vector3(-0.1, h + 0.45, z + randf_range(-0.1, 0.1)), 0.05, 0.035, wm, 6)
	Models.seg(root, Vector3(0, h + 0.02, -d * 0.5 - 0.3), Vector3(0, h + 0.02, d * 0.5 + 0.3), 0.04, 0.04, wm, 6)
	# guy ropes stakes
	for side in [1, -1]:
		for z in [-d * 0.4, d * 0.4]:
			Models.seg(root, Vector3(side * (w * 0.5 + 0.5), 0, z), Vector3(side * (w * 0.5 + 0.55), 0.3, z), 0.03, 0.02, wm, 5)
			Models.seg(root, Vector3(side * (w * 0.5 + 0.53), 0.25, z), Vector3(side * w * 0.3, h * 0.45, z), 0.006, 0.006, Mats.world(Color(0.5, 0.45, 0.35), Color(0.4, 0.35, 0.3), 0.9, 1.0, 0.0, MOSS, false), 4)
	return root

## Open-sided forge shed with anvil, hearth and weapon rack.
static func forge(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var root := Models.N(parent, "forge", pos, Vector3(0, rot_y, 0))
	var wm := wood()
	var dm := wood_dark()
	var sm := stone()
	for x in [-2.2, 2.2]:
		for z in [-1.6, 1.6]:
			Models.seg(root, Vector3(x, 0, z), Vector3(x * 0.98, 2.8 if z < 0 else 2.3, z), 0.12, 0.1, dm, 7)
	var roof := Models.P(root, Geo.box(5.4, 0.12, 4.2), Mats.world(Color(0.32, 0.27, 0.17), Color(0.2, 0.16, 0.1), 0.95, 0.6, 0.35, MOSS), Vector3(0, 2.6, 0), Vector3(-10, 0, 0))
	roof.name = "roof"
	for i in 9:
		Models.P(root, Geo.box(0.08, 0.1, 4.3), dm, Vector3(-2.4 + i * 0.6, 2.72, 0), Vector3(-10, 0, 0))
	# back stone wall with hearth
	Models.P(root, Geo.box(4.4, 1.3, 0.5), sm, Vector3(0, 0.65, -1.7))
	var hearth := Models.N(root, "hearth", Vector3(-1.0, 0, -1.2))
	Models.P(hearth, Geo.box(1.6, 0.9, 1.1), sm, Vector3(0, 0.45, 0))
	Models.P(hearth, Geo.box(1.2, 0.08, 0.8), Mats.world(Color(0.08, 0.05, 0.03), Color(0.2, 0.06, 0.02), 1.0, 3.0, 0.0, MOSS, false, 0.0, Color(1.0, 0.35, 0.05), 2.5), Vector3(0, 0.92, 0))
	Models.P(hearth, Geo.cyl(0.35, 0.55, 2.4, 8), sm, Vector3(0, 2.2, -0.2))
	fire(hearth, Vector3(0, 1.0, 0), 0.9, Color(1.0, 0.45, 0.15), true, true)
	# bellows
	Models.P(hearth, Geo.box(0.5, 0.25, 0.8), Mats.world(HIDE, HIDE_D, 0.9, 1.0), Vector3(1.05, 0.6, 0), Vector3(0, 0, 10))
	# anvil
	var anv := Models.N(root, "anvil", Vector3(0.6, 0, 0.1))
	Models.P(anv, Geo.cyl(0.32, 0.38, 0.55, 10), wm, Vector3(0, 0.275, 0))
	var im := iron()
	Models.P(anv, Geo.box(0.32, 0.18, 0.22), im, Vector3(0, 0.64, 0))
	Models.P(anv, Geo.box(0.62, 0.12, 0.26), im, Vector3(0, 0.78, 0))
	var horn := Models.P(anv, Geo.cone(0.11, 0.38, 8), im, Vector3(-0.48, 0.78, 0))
	horn.rotation_degrees = Vector3(0, 0, 90)
	var ham := Models.N(anv, "hammer", Vector3(0.1, 0.86, 0.05), Vector3(0, 30, 0))
	Models.seg(ham, Vector3.ZERO, Vector3(0.38, 0, 0), 0.016, 0.016, dm, 6)
	Models.P(ham, Geo.box(0.08, 0.07, 0.14), im, Vector3(0.38, 0, 0))
	# quench barrel
	var qb := barrel(root, Vector3(1.6, 0, -0.9))
	Models.P(qb, Geo.cyl(0.28, 0.28, 0.02, 14), Mats.shader_water_mat(), Vector3(0, 0.74, 0))
	# grindstone
	var gs := Models.N(root, "grind", Vector3(1.7, 0, 1.0))
	Models.P(gs, Geo.cyl(0.38, 0.38, 0.14, 16), stone_clean(), Vector3(0, 0.62, 0), Vector3(0, 0, 90))
	Models.P(gs, Geo.box(0.5, 0.5, 0.12), dm, Vector3(0, 0.25, 0.2))
	Models.P(gs, Geo.box(0.5, 0.5, 0.12), dm, Vector3(0, 0.25, -0.2))
	# weapon rack with real item models
	var rack := Models.N(root, "rack", Vector3(-1.4, 0, 1.3), Vector3(0, 10, 0))
	Models.seg(rack, Vector3(-0.8, 0, 0), Vector3(-0.8, 1.3, 0), 0.04, 0.04, dm, 6)
	Models.seg(rack, Vector3(0.8, 0, 0), Vector3(0.8, 1.3, 0), 0.04, 0.04, dm, 6)
	Models.seg(rack, Vector3(-0.85, 1.2, 0), Vector3(0.85, 1.2, 0), 0.03, 0.03, dm, 6)
	Models.seg(rack, Vector3(-0.85, 0.2, 0), Vector3(0.85, 0.2, 0), 0.03, 0.03, dm, 6)
	var wi := 0
	for b in ["broad_sword", "war_axe", "mace", "short_sword", "war_hammer"]:
		var wpn := Models.item_model({"base": b, "rarity": 0})
		rack.add_child(wpn)
		wpn.position = Vector3(-0.6 + wi * 0.3, 0.25, 0.04)
		wpn.rotation_degrees = Vector3(90, 0, 0)
		wi += 1
	return root

## Armorer's stall: plank counter, awning, mannequin, shields.
static func armory(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var root := Models.N(parent, "armory", pos, Vector3(0, rot_y, 0))
	var wm := wood()
	var dm := wood_dark()
	# back wall + side walls (plank)
	Models.P(root, Geo.box(4.0, 2.4, 0.15), wm, Vector3(0, 1.2, -1.4))
	Models.P(root, Geo.box(0.15, 2.4, 2.8), wm, Vector3(-2.0, 1.2, 0))
	Models.P(root, Geo.box(0.15, 2.4, 2.8), wm, Vector3(2.0, 1.2, 0))
	for i in 9:
		Models.P(root, Geo.box(0.04, 2.4, 0.04), dm, Vector3(-1.8 + i * 0.45, 1.2, -1.31))
	# roof (gable)
	var rm := Mats.world(Color(0.33, 0.28, 0.18), Color(0.22, 0.18, 0.1), 0.95, 0.6, 0.4, MOSS)
	Models.P(root, Geo.prism(4.6, 1.1, 3.4), rm, Vector3(0, 2.95, -0.1))
	# awning
	var aw := ShaderMaterial.new()
	aw.shader = Mats.shader("cloth")
	aw.set_shader_parameter("albedo", Color(0.42, 0.12, 0.09))
	aw.set_shader_parameter("trim", Color(0.55, 0.45, 0.25))
	aw.set_shader_parameter("wave", 0.3)
	aw.set_shader_parameter("stripes", 6.0)
	aw.set_shader_parameter("edges", 0.0)
	Models.P(root, Geo.quad(4.0, 1.6), aw, Vector3(0, 2.2, 2.0), Vector3(-65, 0, 0))
	for x in [-1.9, 1.9]:
		Models.seg(root, Vector3(x, 0, 2.6), Vector3(x, 1.95, 2.6), 0.05, 0.05, dm, 6)
	# counter
	Models.P(root, Geo.box(3.4, 0.9, 0.6), wm, Vector3(0, 0.45, 1.2))
	Models.P(root, Geo.box(3.6, 0.08, 0.75), dm, Vector3(0, 0.92, 1.2))
	# goods on counter
	var g1 := Models.item_model({"base": "great_helm", "rarity": 0})
	root.add_child(g1)
	g1.position = Vector3(-1.0, 1.1, 1.2)
	var g2 := Models.item_model({"base": "gauntlets", "rarity": 0})
	root.add_child(g2)
	g2.position = Vector3(0.6, 0.98, 1.2)
	var g3 := Models.item_model({"base": "greaves", "rarity": 0})
	root.add_child(g3)
	g3.position = Vector3(1.3, 0.98, 1.2)
	# shields on back wall
	var si := 0
	for b in ["kite_shield", "buckler", "tower_shield", "spiked_shield"]:
		var s := Models.item_model({"base": b, "rarity": 0})
		root.add_child(s)
		s.position = Vector3(-1.4 + si * 0.95, 1.55, -1.25)
		s.rotation_degrees = Vector3(0, 180, 0)
		si += 1
	# armor stand outside
	var stand := Models.N(root, "stand", Vector3(2.7, 0, 1.5), Vector3(0, -20, 0))
	Models.seg(stand, Vector3.ZERO, Vector3(0, 1.3, 0), 0.04, 0.04, dm, 6)
	Models.P(stand, Geo.cyl(0.25, 0.3, 0.06, 10), dm, Vector3(0, 0.03, 0))
	Models.seg(stand, Vector3(-0.35, 1.3, 0), Vector3(0.35, 1.3, 0), 0.03, 0.03, dm, 6)
	var arm := Models.item_model({"base": "plate_mail", "rarity": 0})
	stand.add_child(arm)
	arm.position = Vector3(0, 1.35, 0)
	arm.rotation_degrees = Vector3(0, 180, 0)
	var hl := Models.item_model({"base": "horned_helm", "rarity": 0})
	stand.add_child(hl)
	hl.position = Vector3(0, 1.85, 0)
	hl.rotation_degrees = Vector3(0, 180, 0)
	return root

## Striped gambling tent with a dice table.
static func gamble_tent(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Models.N(parent, "gamble", pos)
	var cm := ShaderMaterial.new()
	cm.shader = Mats.shader("cloth")
	cm.set_shader_parameter("albedo", Color(0.38, 0.1, 0.12))
	cm.set_shader_parameter("trim", Color(0.55, 0.48, 0.3))
	cm.set_shader_parameter("wave", 0.0)
	cm.set_shader_parameter("stripes", 12.0)
	var tent := Models.P(root, Geo.cyl(0.08, 2.4, 2.4, 16), cm, Vector3(0, 2.6, -0.6))
	tent.name = "canopy"
	Models.P(root, Geo.cyl(2.4, 2.4, 0.4, 16), cm, Vector3(0, 1.3, -0.6))
	Models.seg(root, Vector3(0, 0, -0.6), Vector3(0, 4.2, -0.6), 0.06, 0.05, wood_dark(), 6)
	for i in 8:
		var a := TAU * i / 8.0
		Models.seg(root, Vector3(cos(a) * 2.3, 0, -0.6 + sin(a) * 2.3), Vector3(cos(a) * 2.35, 1.5, -0.6 + sin(a) * 2.35), 0.05, 0.04, wood_dark(), 6)
	var flag := banner(root, Vector3(0, 3.2, -0.6), Color(0.6, 0.45, 0.1), Color(0.3, 0.05, 0.05))
	flag.scale = Vector3(0.6, 0.6, 0.6)
	# table
	var tbl := Models.N(root, "table", Vector3(0.0, 0, 1.2))
	Models.P(tbl, Geo.cyl(0.7, 0.7, 0.07, 16), wood(), Vector3(0, 0.8, 0))
	Models.P(tbl, Geo.cyl(0.08, 0.2, 0.8, 8), wood_dark(), Vector3(0, 0.4, 0))
	var felt := Mats.world(Color(0.1, 0.25, 0.12), Color(0.06, 0.18, 0.08), 1.0, 3.0, 0.0, MOSS, false)
	Models.P(tbl, Geo.cyl(0.6, 0.6, 0.01, 16), felt, Vector3(0, 0.84, 0))
	var dm := Mats.mat(Color(0.9, 0.88, 0.8), 0.4)
	for i in 3:
		Models.P(tbl, Geo.box(0.07, 0.07, 0.07), dm, Vector3(-0.2 + i * 0.12, 0.88, 0.1 + (i % 2) * 0.1), Vector3(0, i * 25, 0))
	for i in 3:
		var gp := Models.gold_pile(60 + i * 40)
		tbl.add_child(gp)
		gp.position = Vector3(0.25, 0.85, -0.15 + i * 0.13)
	var lantern := Models.N(tbl, "lantern", Vector3(-0.35, 0.85, -0.25))
	Models.P(lantern, Geo.cyl(0.08, 0.1, 0.22, 6), iron(), Vector3(0, 0.11, 0))
	var lg := OmniLight3D.new()
	lg.light_color = Color(1.0, 0.7, 0.35)
	lg.light_energy = 1.0
	lg.omni_range = 4.0
	lg.position = Vector3(0, 0.25, 0)
	lg.add_to_group("flicker")
	lg.set_meta("base", 1.0)
	lantern.add_child(lg)
	Models.P(lantern, Geo.sph(0.06, 8), Mats.glow(Color(1.0, 0.7, 0.3), 3.0), Vector3(0, 0.12, 0))
	return root

static func stash_chest(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var root := Models.N(parent, "stash", pos, Vector3(0, rot_y, 0))
	var wm := Mats.world(Color(0.35, 0.2, 0.1), Color(0.22, 0.12, 0.06), 0.8, 1.0, 0.0, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0)
	var im := Mats.world(Color(0.3, 0.28, 0.26), Color(0.15, 0.14, 0.13), 0.4, 2.0, 0.0, MOSS, true, 0.85)
	Models.P(root, Geo.box(1.3, 0.65, 0.8), wm, Vector3(0, 0.33, 0))
	var lid := Models.P(root, Geo.cyl(0.4, 0.4, 1.3, 12), wm, Vector3(0, 0.65, 0), Vector3(0, 0, 90), Vector3(1, 1, 1))
	lid.scale = Vector3(0.55, 1.0, 1.0)
	for x in [-0.5, 0.0, 0.5]:
		Models.P(root, Geo.box(0.08, 0.67, 0.82), im, Vector3(x, 0.33, 0))
		Models.P(root, Geo.torus(0.39, 0.43, 14, 4), im, Vector3(x, 0.65, 0), Vector3(0, 0, 90), Vector3(1, 0.55, 1))
	Models.P(root, Geo.box(0.18, 0.22, 0.06), Mats.mat(Color(0.85, 0.65, 0.25), 0.25, 1.0), Vector3(0, 0.6, -0.42))
	return footprint(root, Vector2(0.68, 0.42))

static func waypoint(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Models.N(parent, "waypoint", pos)
	var sm := stone_clean()
	Models.P(root, Geo.cyl(2.0, 2.2, 0.25, 24), sm, Vector3(0, 0.12, 0))
	Models.P(root, Geo.cyl(1.6, 1.7, 0.1, 24), Mats.world(Color(0.28, 0.28, 0.3), Color(0.2, 0.2, 0.22), 0.6, 2.0, 0.0, MOSS, false), Vector3(0, 0.28, 0))
	var rune := Mats.glow_unique(Color(0.3, 0.55, 1.0), 0.9)
	var ring := Models.P(root, Geo.torus(1.2, 1.32, 40, 4), rune, Vector3(0, 0.34, 0))
	ring.name = "rune_ring"
	for i in 8:
		var a := TAU * i / 8.0
		Models.P(root, Geo.box(0.12, 0.02, 0.3), rune, Vector3(cos(a) * 1.0, 0.34, sin(a) * 1.0), Vector3(0, -rad_to_deg(a), 0))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var pil := Models.N(root, "pillar", Vector3(cos(a) * 1.85, 0.25, sin(a) * 1.85))
		Models.P(pil, Geo.box(0.36, 1.4, 0.36), sm, Vector3(0, 0.7, 0), Vector3(0, rad_to_deg(-a), 0))
		Models.P(pil, Geo.box(0.46, 0.15, 0.46), sm, Vector3(0, 1.45, 0), Vector3(0, rad_to_deg(-a), 0))
		Models.P(pil, Geo.box(0.06, 0.5, 0.02), rune, Vector3(cos(a) * -0.19, 0.8, sin(a) * -0.19), Vector3(0, rad_to_deg(-a) + 90, 0))
	var crystal := Models.N(root, "crystal", Vector3(0, 1.4, 0))
	Models.P(crystal, Geo.sph(0.28, 4), Mats.mat(Color(0.3, 0.5, 0.9), 0.05, 0.1, Color(0.4, 0.65, 1.0), 1.2), Vector3.ZERO, Vector3.ZERO, Vector3(0.7, 1.4, 0.7))
	var l := OmniLight3D.new()
	l.light_color = Color(0.45, 0.65, 1.0)
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.position = Vector3(0, 1.2, 0)
	root.add_child(l)
	return root

## Dry-stacked stone wall along a polyline. Returns stone transforms for a MultiMesh.
static func wall_stones(a: Vector3, b: Vector3, height: float, rng: RandomNumberGenerator) -> Array:
	var xf := []
	var dir := (b - a)
	var length := dir.length()
	dir = dir / max(length, 0.001)
	var yaw := atan2(dir.x, dir.z)
	var rows := int(height / 0.32)
	for r in rows:
		var t := rng.randf_range(0.0, 0.3)
		while t < length:
			var sz := rng.randf_range(0.45, 0.75)
			var p := a + dir * t
			var sway := rng.randf_range(-0.06, 0.06)
			var basis := Basis(Vector3.UP, yaw + rng.randf_range(-0.3, 0.3)).scaled(Vector3(rng.randf_range(0.5, 0.7), rng.randf_range(0.36, 0.48), sz * 1.1))
			var top_fall := 1.0 - float(r) / rows * 0.25
			xf.append(Transform3D(basis, p + Vector3(dir.z * sway, 0.15 + r * 0.3 * top_fall, -dir.x * sway)))
			t += sz * 0.85
	return xf

## Grass tuft mesh: a few bent blades.
static func grass_mesh(blades: int = 7, height: float = 0.45) -> Mesh:
	var key := "grass%d_%.2f" % [blades, height]
	if Geo._cache.has(key):
		return Geo._cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = blades * 97
	for i in blades:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var hgt := height * rng.randf_range(0.6, 1.2)
		var wd := 0.022
		var side := Vector3(cos(a), 0, sin(a)) * wd
		var lean := Vector3(-sin(a), 0, cos(a)) * rng.randf_range(0.05, 0.2)
		var segs := 3
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := off + lean * t0 * t0 + Vector3(0, hgt * t0, 0)
			var p1 := off + lean * t1 * t1 + Vector3(0, hgt * t1, 0)
			var w0 := side * (1.0 - t0)
			var w1 := side * (1.0 - t1)
			var n := Vector3.UP
			st.set_uv(Vector2(0, t0)); st.set_normal(n); st.add_vertex(p0 - w0)
			st.set_uv(Vector2(1, t0)); st.set_normal(n); st.add_vertex(p0 + w0)
			st.set_uv(Vector2(1, t1)); st.set_normal(n); st.add_vertex(p1 + w1)
			st.set_uv(Vector2(0, t0)); st.set_normal(n); st.add_vertex(p0 - w0)
			st.set_uv(Vector2(1, t1)); st.set_normal(n); st.add_vertex(p1 + w1)
			st.set_uv(Vector2(0, t1)); st.set_normal(n); st.add_vertex(p1 - w1)
	var m := st.commit()
	Geo._cache[key] = m
	return m

## Gnarled dead tree (baked).
static func dead_tree(seed_v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	var bm := Mats.world(Color(0.22, 0.19, 0.16), Color(0.14, 0.12, 0.1), 0.95, 1.0, 0.25, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0)
	_branch(root, Vector3.ZERO, Vector3(rng.randf_range(-0.15, 0.15), 1, rng.randf_range(-0.15, 0.15)).normalized(), 2.6, 0.26, 0, rng, bm)
	return root

static func _branch(root: Node3D, from: Vector3, dir: Vector3, length: float, r: float, depth: int, rng: RandomNumberGenerator, m: Material) -> void:
	var to := from + dir * length
	Models.seg(root, from, to, r, r * 0.65, m, 7 if depth < 2 else 5)
	if depth >= 3 or r < 0.03:
		return
	var kids := rng.randi_range(2, 3)
	for k in kids:
		var nd := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.4), rng.randf_range(-0.9, 0.9))).normalized()
		_branch(root, to, nd, length * rng.randf_range(0.5, 0.7), r * 0.6, depth + 1, rng, m)

## Moorland pine (baked).
static func pine(seed_v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	var bm := Mats.world(Color(0.25, 0.18, 0.12), Color(0.16, 0.11, 0.07), 0.95, 1.0, 0.0, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0)
	var lm := Mats.world(Color(0.12, 0.18, 0.1), Color(0.07, 0.11, 0.06), 0.95, 2.0, 0.0, MOSS)
	var h := rng.randf_range(4.0, 5.8)
	Models.seg(root, Vector3.ZERO, Vector3(0, h, 0), 0.16, 0.05, bm, 7)
	var layers := 6
	for i in layers:
		var t := float(i) / layers
		var r := lerpf(1.15, 0.3, t) * rng.randf_range(0.85, 1.1)
		var y := h * (0.28 + t * 0.62)
		Models.P(root, Geo.cone(r, 1.1, 7), lm, Vector3(rng.randf_range(-0.08, 0.08), y, rng.randf_range(-0.08, 0.08)), Vector3(rng.randf_range(-8, 8), rng.randf() * 360.0, rng.randf_range(-8, 8)))
	return root

## Leafy oak-like tree (baked).
static func oak(seed_v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	var bm := Mats.world(Color(0.26, 0.2, 0.14), Color(0.15, 0.12, 0.08), 0.95, 1.0, 0.3, MOSS, true, 0.0, Color.BLACK, 0.0, 1.0)
	var lm := Mats.world(Color(0.16, 0.22, 0.09), Color(0.1, 0.14, 0.05), 0.95, 1.5, 0.0, MOSS)
	var lm2 := Mats.world(Color(0.22, 0.26, 0.1), Color(0.13, 0.16, 0.06), 0.95, 1.5, 0.0, MOSS)
	var top := Vector3(rng.randf_range(-0.3, 0.3), 3.0, rng.randf_range(-0.3, 0.3))
	Models.seg(root, Vector3.ZERO, top, 0.35, 0.2, bm, 8)
	for i in 4:
		var a := rng.randf() * TAU
		var e := top + Vector3(cos(a) * 1.3, rng.randf_range(0.6, 1.4), sin(a) * 1.3)
		Models.seg(root, top, e, 0.16, 0.07, bm, 6)
	for i in 9:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.0, 1.6)
		var c := top + Vector3(cos(a) * rr, rng.randf_range(0.8, 2.2), sin(a) * rr)
		Models.P(root, rock_mesh(10 + i % 6, 0.3), lm if i % 2 == 0 else lm2, c, Vector3(0, rng.randf() * 360.0, 0), Vector3.ONE * rng.randf_range(1.6, 2.4))
	return root

static func bush(seed_v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var root := Node3D.new()
	var lm := Mats.world(Color(0.17, 0.21, 0.09), Color(0.1, 0.13, 0.05), 0.95, 2.0, 0.0, MOSS, false)
	for i in 4:
		var a := rng.randf() * TAU
		Models.P(root, rock_mesh(20 + i, 0.35), lm, Vector3(cos(a) * 0.35, 0.25, sin(a) * 0.35), Vector3(0, rng.randf() * 360.0, 0), Vector3.ONE * rng.randf_range(0.6, 0.9))
	return root
