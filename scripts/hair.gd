class_name LongHair
extends RefCounted
## Shoulder-length, wavy hair for the knight: layered hair cards (ribbons whose shader draws
## individual strands with ragged tips) rooted on the sculpted scalp and draped over the head,
## neck and shoulders. The cards hang from the head joint; their vertex shader swings them with
## the wind and with a damped spring the rig drives from the head's motion (knight_rig.gd).

const HEAD_BONE := Vector3(0, 1.66, 0)   # Knight.BONE_DEF head rest position
const SEGS := 14
const WIND := Vector3(0.85, 0.0, 0.35)

static var _cache: ArrayMesh
static var _shader: Shader

## Adds (or removes) the hair on a knight rig to match the gear.
static func attach(root: Node3D, gear: Dictionary) -> void:
	var J: Dictionary = root.get_meta("j")
	var hd: Node3D = J["head"]
	var old := hd.get_node_or_null("LongHair")
	if old:
		old.name = "OldHair"
		old.queue_free()
	root.set("hair_mat", null)
	if not gear.get("long_hair", true) or gear.get("coif", false):
		return
	var mi := MeshInstance3D.new()
	mi.name = "LongHair"
	mi.mesh = mesh()
	var m := material(gear["hair"])
	mi.material_override = m
	hd.add_child(mi)
	root.set("hair_mat", m)
	root.set("hair_node", mi)

static func material(col: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("hair", col)
	m.set_shader_parameter("wind", WIND.normalized())
	return m

## Smallest distance from the body axis the hair may hang at (head, neck, shoulders).
static func _min_radius(phi: float, y: float, layer: int) -> float:
	var margin := 0.014 + layer * 0.006
	var r := 0.0
	if y > Knight.HEAD_Y0 - 0.03:
		var t := clampf((y - Knight.HEAD_Y0) / (Knight.HEAD_Y1 - Knight.HEAD_Y0), 0.12, 1.0)
		var hp := Knight.head_pt(phi, t)
		r = maxf(r, Vector2(hp.x, hp.z - Knight.HEAD_CZ).length() + margin + 0.004)
	if y < 1.7:
		r = maxf(r, 0.064 + margin)
	if y < Knight.T_Y1:
		var tp := Knight.torso_pt(phi, y)
		r = maxf(r, Vector2(tp.x, tp.z - Knight.HEAD_CZ).length() + margin)
	return r

static func mesh() -> ArrayMesh:
	if _cache != null:
		return _cache
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	var card := 0
	for layer in 3:
		var count := 40 + layer * 10
		for i in count:
			# roots: around the sides and back, leaving the face clear
			var side := 1.0 if i % 2 == 0 else -1.0
			var k := (float(i >> 1) + rng.randf_range(0.0, 0.8)) / float(count >> 1)
			var aa := lerpf(0.98, PI, pow(k, 0.85))
			var a := side * aa
			var hl := Knight._line(Knight.HAIRLINE, aa)
			var t := clampf(maxf(hl, 0.55) + 0.05 + layer * 0.07 + rng.randf_range(0.0, 0.05), 0.0, 0.84)
			var front := aa < 1.38
			var tip_y := 1.5 + rng.randf_range(-0.025, 0.03)
			if front:
				tip_y = 1.54 + rng.randf_range(-0.02, 0.03)
			elif aa > 2.3:
				tip_y = 1.47 + rng.randf_range(-0.025, 0.025)
			var p := Knight.head_pt(a, t) + Knight.head_nrm(a, t) * (0.004 + layer * 0.003)
			var down := (Knight.head_pt(a, t - 0.03) - Knight.head_pt(a, t)).normalized()
			var dir := (down + Knight.head_nrm(a, t) * 0.5).normalized()
			if dir.y > -0.25:
				dir = Vector3(dir.x, -0.25, dir.z).normalized()
			var drift := Vector3.ZERO
			if front:
				drift = Vector3(0, 0, 0.05)           # frames the face, then falls by the neck
			elif aa < 2.0:
				drift = Vector3(0, 0, 0.3)            # sweeps back past the ear, behind the shoulder
			var length := (p.y - tip_y) * 1.08 + 0.03
			var step := length / SEGS
			var pts := [p]
			for s in SEGS:
				dir = (dir + Vector3(0, -0.32, 0) + drift * 0.3).normalized()
				p = p + dir * step
				# keep outside the head, neck and shoulders
				var cz := Knight.HEAD_CZ
				var phi := atan2(p.x, -(p.z - cz))
				var rmin := _min_radius(phi, p.y, layer)
				var hv := Vector2(p.x, p.z - cz)
				if hv.length() < rmin:
					hv = hv.normalized() * rmin
					p = Vector3(hv.x, p.y, hv.y + cz)
				pts.append(p)
			# ribbon: a little wave, width tapering to the tip
			var phase := rng.randf() * TAU
			var wid := rng.randf_range(0.034, 0.046) * (1.0 - layer * 0.06)
			var tint := rng.randf()
			var radial := Vector3(sin(a), 0.0, -cos(a))
			var sidev := Vector3.UP.cross(radial).normalized()
			sidev = sidev.rotated(radial, rng.randf_range(-0.25, 0.25))
			for s in SEGS + 1:
				var f := float(s) / SEGS
				var c: Vector3 = pts[s]
				var tg: Vector3 = ((pts[mini(s + 1, SEGS)] as Vector3) - (pts[maxi(s - 1, 0)] as Vector3)).normalized()
				var wave := sin(f * 8.0 + phase) * 0.013 * f
				c += sidev * wave + radial * (sin(f * 6.0 + phase * 1.7) * 0.006 + 0.008) * f
				var hw := wid * lerpf(0.5, 0.36, f)
				var out := Vector3(c.x, 0.0, c.z - Knight.HEAD_CZ).normalized()
				if c.y > Knight.HEAD_Y0:
					out = (c - Vector3(0, c.y - 0.02, Knight.HEAD_CZ)).normalized()
				var nrm := (out * 0.75 + tg.cross(sidev).normalized() * 0.25 * signf(tg.cross(sidev).dot(out))).normalized()
				for e in 2:
					var q := c + sidev * (hw if e == 1 else -hw)
					st.set_normal(nrm)
					st.set_tangent(Plane(sidev, 1.0))
					st.set_uv(Vector2(float(e), f))
					st.set_uv2(Vector2(float(card) * 0.618, float(layer)))
					st.set_color(Color(float(layer) / 2.0, tint, 0.0, 1.0))
					st.add_vertex(q - HEAD_BONE)
			for s in SEGS:
				var v0 := base + s * 2
				st.add_index(v0)
				st.add_index(v0 + 1)
				st.add_index(v0 + 2)
				st.add_index(v0 + 1)
				st.add_index(v0 + 3)
				st.add_index(v0 + 2)
			base += (SEGS + 1) * 2
			card += 1
	_cache = st.commit()
	return _cache

const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 hair : source_color = vec3(0.22, 0.14, 0.08);
uniform vec3 sway = vec3(0.0);      // head-local spring offset of the tips (from the rig)
uniform vec3 wind = vec3(0.9, 0.0, 0.4); // head-local wind direction (from the rig)
uniform float gust_amt = 1.0;
uniform float clock = 0.0;          // seconds, advanced by the rig
varying float v_tint;
varying float v_layer;

float h11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void vertex(){
	float w = pow(UV.y, 1.5);
	float id = UV2.x;
	float gust = (0.55 + 0.45 * sin(clock * 1.3 + id * 0.7)) * (0.6 + 0.4 * sin(clock * 0.37 + 1.3));
	vec3 off = sway * w;
	off += wind * gust * gust_amt * 0.045 * w;
	vec3 across = normalize(cross(wind + vec3(0.0001), vec3(0.0, 1.0, 0.0)));
	off += across * sin(clock * 6.5 + id * 3.1 + UV.y * 5.0) * 0.007 * w * gust_amt;
	off.y += sin(clock * 4.3 + id * 2.0 + UV.y * 3.0) * 0.002 * w;
	VERTEX += off;
	v_tint = COLOR.g;
	v_layer = COLOR.r;
}

void fragment(){
	// individual strands across the card, with gaps toward its edges and ragged tips
	float sx = UV.x * 8.0 + UV2.x * 13.0;
	float sid = floor(sx);
	float r = h11(sid + UV2.x * 7.0);
	float f = fract(sx);
	float width = mix(0.75, 1.1, r);
	float strand = 1.0 - smoothstep(width * 0.5 - 0.12, width * 0.5, abs(f - 0.5));
	float core = 1.0 - smoothstep(0.3, 0.45, abs(UV.x - 0.5));
	float tip = 0.8 + r * 0.2;
	float a = max(strand, core) * (1.0 - smoothstep(tip - 0.12, tip, UV.y));
	a *= 1.0 - smoothstep(0.46, 0.5, abs(UV.x - 0.5)) * 0.6;
	a *= smoothstep(0.0, 0.07, UV.y) * 0.55 + 0.45 + step(0.07, UV.y);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = hair * (0.8 + 0.7 * r) * (0.85 + 0.3 * v_tint);
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.35, UV.y));          // darker at the roots
	c = mix(c, c * vec3(1.25, 1.12, 1.0), smoothstep(0.6, 1.0, UV.y) * 0.5); // sun-touched ends
	c *= mix(0.75, 1.0, v_layer);                             // inner layers in shadow
	c *= 0.85 + 0.3 * sin(UV.x * 50.0 + r * 6.0) * 0.5;      // fine strand shading
	ALBEDO = c;
	ROUGHNESS = 0.5 + r * 0.2;
	SPECULAR = 0.45;
	BACKLIGHT = hair * 0.35;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""
