class_name AimIndicator
extends Node3D
## Click to cast's look (Aiming decides): while an area skill is armed, a thin ring round the hero at its range and a
## circle as big as its area where it would land, red while the pointer is past the range (the circle then sits
## where the cast would really land, at the range's edge). Two meshes, made the first time and reused; their rims
## follow the ground (World.height_at) and are refitted only when they move. They draw over grass and small bumps
## (pulled a little toward the camera) and under bodies.

const SEGS := 72               # points round each rim
const LIFT := 0.05             # metres over the ground
const RANGE_BAND := 0.12       # the range ring's width (m)
const SPOT_BAND := 0.16        # the landing circle's rim (m)
const RANGE_TINT := Color(1.0, 0.93, 0.78, 0.42)
const READY_TINT := Color(1.0, 0.86, 0.48, 0.95)
const FAR_TINT := Color(1.0, 0.24, 0.17, 0.95)

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fill = 0.0;      // the inside's opacity (0: a ring only)
uniform float pull = 0.8;      // metres toward the camera: over grass and small bumps, under bodies
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz += normalize(-v.xyz) * pull;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	// UV.y 1: the rim's band (UV.x 0 inside edge, 1 outside edge); 0: the fill (UV.x 0 centre, 1 rim)
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	float inside = fill * mix(0.25, 1.0, UV.x * UV.x);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * mix(inside, edge, UV.y);
}
"""

static var _shader: Shader

var aiming: Aiming
var ring: MeshInstance3D       # the skill's range round the hero
var spot: MeshInstance3D       # where it lands, as big as its area
## What the circle shows now (tests read these): its centre, its radius, past the range or not.
var spot_at := Vector3.ZERO
var spot_r := 0.0
var spot_far := false
var _fit := {}                 # each mesh -> [centre, radius, its points] it was last fitted to

func _init(a: Aiming) -> void:
	aiming = a
	name = "AimIndicator"

func _process(_delta: float) -> void:
	var g: Node = aiming.game
	if not aiming.armed() or g.hero == null or g.world == null:
		if ring != null:
			ring.visible = false
			spot.visible = false
		return
	if ring == null:
		ring = _part(false, RANGE_TINT)
		spot = _part(true, READY_TINT)
	var h: Hero = g.hero
	var id := aiming.skill
	spot_at = aiming.landing(h.cursor)
	spot_r = Aiming.radius(h, id)
	spot_far = not aiming.in_reach(h.cursor)
	_fit_to(ring, h.global_position, Aiming.reach(id), RANGE_BAND, false)
	_fit_to(spot, spot_at, spot_r, SPOT_BAND, true)
	(spot.material_override as ShaderMaterial).set_shader_parameter("tint", FAR_TINT if spot_far else READY_TINT)
	ring.visible = true
	spot.visible = true

## One of the two: a rim (and a fill inside it), its vertices placed by _fit_to.
func _part(fill: bool, tint: Color) -> MeshInstance3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("fill", 0.22 if fill else 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(fill)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.top_level = true
	add_child(mi)
	return mi

## The mesh's shape: a centre and a rim of SEGS for the fill, then a band of SEGS inner and outer points. Its
## positions are set later in place (_fit_to), so it is never made again.
func _mesh(fill: bool) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var o := 0
	if fill:
		v.append(Vector3.ZERO)
		uv.append(Vector2(0, 0))
		for i in SEGS:
			v.append(Vector3.ZERO)
			uv.append(Vector2(1, 0))
			idx.append_array([0, 1 + i, 1 + (i + 1) % SEGS])
		o = 1 + SEGS
	for i in SEGS:
		v.append_array([Vector3.ZERO, Vector3.ZERO])
		uv.append_array([Vector2(0, 1), Vector2(1, 1)])
		var a := o + i * 2
		var b := o + ((i + 1) % SEGS) * 2
		idx.append_array([a, a + 1, b + 1, a, b + 1, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))     # (its points move in place)
	return m

## Places a rim of radius r round c on the ground: the node at c, every point at the ground's height under it.
func _fit_to(mi: MeshInstance3D, c: Vector3, r: float, band: float, fill: bool) -> void:
	var last: Array = _fit.get(mi, [])
	if not last.is_empty() and (last[0] as Vector3).distance_to(c) < 0.02 and is_equal_approx(float(last[1]), r):
		return
	var w: Node = aiming.game.world
	var cy: float = w.height_at(c.x, c.z)
	mi.global_position = Vector3(c.x, cy, c.z)
	var rin := maxf(r - band, 0.0)
	var v := PackedVector3Array()
	if fill:
		v.append(Vector3(0, LIFT, 0))
	var rim := PackedVector3Array()
	for i in SEGS:
		var a := TAU * float(i) / SEGS
		var d := Vector3(cos(a), 0.0, sin(a))
		var y: float = w.height_at(c.x + d.x * r, c.z + d.z * r) - cy + LIFT
		rim.append(Vector3(d.x, y, d.z))
	if fill:
		for p in rim:
			v.append(Vector3(p.x * rin, p.y, p.z * rin))
	for p in rim:
		v.append(Vector3(p.x * rin, p.y, p.z * rin))
		v.append(Vector3(p.x * r, p.y, p.z * r))
	(mi.mesh as ArrayMesh).surface_update_vertex_region(0, 0, v.to_byte_array())
	_fit[mi] = [c, r, v]

## How far the circle's drawn outer edge is from its centre (tests: the furthest of its points).
func spot_rim_radius() -> float:
	var last: Array = _fit.get(spot, []) if spot != null else []
	var out := 0.0
	for p in (last[2] if last.size() > 2 else PackedVector3Array()):
		out = maxf(out, Vector2(p.x, p.z).length())
	return out
