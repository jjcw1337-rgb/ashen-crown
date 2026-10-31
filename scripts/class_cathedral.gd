class_name ClassCathedral
## The New Character screen's set (ClassStage): a ruined gothic cathedral hall. Each hero stands on its own
## carved stone plinth (runes glowing in its colour) in a shaft of light coloured by its power, a tattered
## banner with its emblem hangs above it, candles burn at the plinths and ash drifts through the hall. Behind:
## pointed windows letting in cold light, rows of pillars, fallen stones. `build` returns the materials
## ClassStage drives: "shafts" and "glows" (cls -> ShaderMaterial, uniform `power`).

const HALL_W := 32.0
const WALL_Z := -9.5

## homes: cls -> feet position on top of its plinth; radii: cls -> plinth radius.
static func build(root: Node3D, homes: Dictionary, radii: Dictionary, accents: Dictionary, emblems: Dictionary) -> Dictionary:
	var shafts := {}
	var glows := {}
	_floor(root)
	_hall(root)
	var seed := 0.0
	for c: String in homes:
		var home: Vector3 = homes[c]
		var r: float = radii[c]
		var col: Color = accents[c]
		glows[c] = _plinth(root, Vector3(home.x, 0.0, home.z), r, home.y, col)
		shafts[c] = _shaft(root, home, r, col)
		_banner(root, Vector3(home.x, 3.7, home.z - 1.7), col, int(emblems.get(c, 0)), seed)
		_candles(root, Vector3(home.x, 0.0, home.z), r, seed)
		seed += 1.7
	_candelabra(root, Vector3(-6.3, 0.0, -0.6))
	_candelabra(root, Vector3(6.3, 0.0, -0.6))
	_ash(root)
	return {"shafts": shafts, "glows": glows}

# --- floor, walls, pillars ---------------------------------------------------------------------------------

static func _floor(root: Node3D) -> void:
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALL_W, 22.0)
	fl.mesh = pm
	fl.material_override = _shader_mat(FLOOR_SHADER)
	fl.position = Vector3(0, 0, -2.5)
	root.add_child(fl)
	# fallen stones and a toppled column drum among the rubble at the sides
	var rubble: Array = [[-5.0, 1.1, 0.35], [-4.4, 1.6, 0.2], [-5.6, 0.2, 0.25], [4.7, 1.3, 0.3], [5.3, 0.6, 0.22],
		[4.2, 2.0, 0.18], [-3.2, -3.2, 0.3], [3.0, -3.6, 0.35], [-6.4, 2.3, 0.4], [6.6, 2.1, 0.32]]
	var sm := _shader_mat(STONE_SHADER)
	for i in rubble.size():
		var e: Array = rubble[i]
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s: float = e[2]
		bm.size = Vector3(s * 1.6, s, s * 1.2)
		b.mesh = bm
		b.material_override = sm
		b.position = Vector3(float(e[0]), s * 0.4, float(e[1]))
		b.rotation = Vector3(0.3 * sin(i * 2.1), i * 1.3, 0.25 * cos(i * 1.7))
		root.add_child(b)
	var drum := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 0.42
	dc.bottom_radius = 0.42
	dc.height = 1.5
	drum.mesh = dc
	drum.material_override = sm
	drum.position = Vector3(-5.2, 0.4, 2.6)
	drum.rotation = Vector3(0, 0.6, PI * 0.5)
	root.add_child(drum)

static func _hall(root: Node3D) -> void:
	var stone := _shader_mat(STONE_SHADER)
	# the back wall, with three pointed windows of cold light
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(HALL_W, 16.0, 0.6)
	wall.mesh = wb
	wall.material_override = stone
	wall.position = Vector3(0, 8.0, WALL_Z)
	root.add_child(wall)
	for e: Array in [[0.0, 3.6, 9.5], [-5.4, 2.8, 7.6], [5.4, 2.8, 7.6]]:
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(float(e[1]), float(e[2]))
		w.mesh = q
		var wm := _shader_mat(WINDOW_SHADER)
		wm.set_shader_parameter("aspect", float(e[2]) / (float(e[1]) * 0.5))
		w.material_override = wm
		w.position = Vector3(float(e[0]), 1.4 + float(e[2]) * 0.5, WALL_Z + 0.31)
		root.add_child(w)
	var moon := OmniLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.85)
	moon.light_energy = 1.6
	moon.omni_range = 10.0
	moon.position = Vector3(0, 6.0, WALL_Z + 2.0)
	root.add_child(moon)
	# rows of pillars down both sides, the nearest framing the stage
	for sx: int in [-1, 1]:
		for e: Array in [[5.6, -7.2, 0.48], [6.4, -4.2, 0.52], [7.4, -1.2, 0.58], [8.8, 2.2, 0.7]]:
			_pillar(root, Vector3(sx * float(e[0]), 0.0, float(e[1])), float(e[2]), stone)

static func _pillar(root: Node3D, at: Vector3, r: float, mat: Material) -> void:
	var p := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 12.0
	cm.radial_segments = 12
	p.mesh = cm
	p.material_override = mat
	p.position = at + Vector3(0, 6.0, 0)
	root.add_child(p)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(r * 2.6, 0.45, r * 2.6)
	base.mesh = bb
	base.material_override = mat
	base.position = at + Vector3(0, 0.22, 0)
	root.add_child(base)

# --- plinths and light -------------------------------------------------------------------------------------

## A hexagonal carved plinth: a broad foot, the body with a glowing rune in a panel on each face, a cap whose
## rim glows. Returns the glow material (its `power` is driven by ClassStage).
static func _plinth(root: Node3D, at: Vector3, r: float, top: float, col: Color) -> ShaderMaterial:
	var stone := _shader_mat(STONE_SHADER)
	var glow := _shader_mat(PLINTH_SHADER)
	glow.set_shader_parameter("glow", col)
	glow.set_shader_parameter("body_h", top - 0.24)
	glow.set_shader_parameter("power", 0.2)
	var foot := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = r * 1.12
	fm.bottom_radius = r * 1.2
	fm.height = 0.12
	fm.radial_segments = 6
	foot.mesh = fm
	foot.material_override = stone
	foot.position = at + Vector3(0, 0.06, 0)
	root.add_child(foot)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = r
	bm.bottom_radius = r
	bm.height = top - 0.24
	bm.radial_segments = 6
	body.mesh = bm
	body.material_override = glow
	body.position = at + Vector3(0, 0.12 + (top - 0.24) * 0.5, 0)
	root.add_child(body)
	var cap := MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = r * 1.08
	cmesh.bottom_radius = r * 1.04
	cmesh.height = 0.12
	cmesh.radial_segments = 6
	cap.mesh = cmesh
	var cm := _shader_mat(CAP_SHADER)
	cm.set_shader_parameter("glow", col)
	cm.set_shader_parameter("rad", r * 1.08)
	cm.set_shader_parameter("power", 0.2)
	cap.material_override = cm
	cap.position = at + Vector3(0, top - 0.06, 0)
	root.add_child(cap)
	# the cap shares the glow's power through a second reference
	glow.set_meta("cap", cm)
	return glow

## The coloured shaft of light falling on a plinth: a soft cone drawn additively, dust motes drifting in it.
static func _shaft(root: Node3D, home: Vector3, r: float, col: Color) -> ShaderMaterial:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.4
	cm.bottom_radius = r * 1.15
	cm.height = 8.0
	cm.radial_segments = 24
	cm.cap_top = false
	cm.cap_bottom = false
	m.mesh = cm
	var sm := _shader_mat(SHAFT_SHADER)
	sm.set_shader_parameter("col", col)
	sm.set_shader_parameter("power", 0.2)
	m.material_override = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(home.x, home.y + 4.0 - 0.05, home.z - 0.45)
	root.add_child(m)
	return sm

# --- banners, candles, ash ---------------------------------------------------------------------------------

## A tattered banner on an iron rod, swaying a little, its emblem (Emblem ids in BANNER_SHADER) in the colour.
static func _banner(root: Node3D, at: Vector3, col: Color, emblem: int, seed: float) -> void:
	var b := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 1.9)
	q.subdivide_width = 4
	q.subdivide_depth = 16
	b.mesh = q
	var bm := _shader_mat(BANNER_SHADER)
	bm.set_shader_parameter("cloth", col.darkened(0.8).lerp(Color(0.08, 0.07, 0.06), 0.35))
	bm.set_shader_parameter("mark", col.lerp(Color(0.85, 0.7, 0.4), 0.25))
	bm.set_shader_parameter("emblem", emblem)
	bm.set_shader_parameter("seed", seed)
	b.material_override = bm
	b.position = at
	root.add_child(b)
	var rod := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.025
	rc.bottom_radius = 0.025
	rc.height = 1.2
	rod.mesh = rc
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.12, 0.1, 0.08)
	rm.metallic = 0.7
	rm.roughness = 0.45
	rod.material_override = rm
	rod.position = at + Vector3(0, 0.97, 0.02)
	rod.rotation = Vector3(0, 0, PI * 0.5)
	root.add_child(rod)

## Three candles of different heights at the foot of a plinth, either side.
static func _candles(root: Node3D, at: Vector3, r: float, seed: float) -> void:
	var spots: Array = [[-1.0, 0.55, 0.32], [-1.0, 0.75, 0.2], [1.0, 0.6, 0.26]]
	for i in spots.size():
		var e: Array = spots[i]
		var side: float = e[0]
		var p := at + Vector3(side * (r * 1.32 + float(e[1]) * 0.18), 0.0, r * 0.75 - i * 0.12)
		_candle(root, p, float(e[2]), seed + i)

static func _candle(root: Node3D, p: Vector3, h: float, seed: float) -> void:
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.045
	cm.height = h
	cm.radial_segments = 10
	c.mesh = cm
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.86, 0.8, 0.66)
	wax.roughness = 0.6
	wax.emission_enabled = true
	wax.emission = Color(1.0, 0.6, 0.25)
	wax.emission_energy_multiplier = 0.25
	c.material_override = wax
	c.position = p + Vector3(0, h * 0.5, 0)
	root.add_child(c)
	var f := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.15)
	f.mesh = q
	var fm := _shader_mat(FLAME_SHADER)
	fm.set_shader_parameter("seed", seed)
	f.material_override = fm
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.position = p + Vector3(0, h + 0.07, 0)
	root.add_child(f)

## A tall iron candle stand with five candles and the warm light they give.
static func _candelabra(root: Node3D, at: Vector3) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.1, 0.09, 0.08)
	iron.metallic = 0.75
	iron.roughness = 0.4
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.03
	pc.bottom_radius = 0.05
	pc.height = 1.5
	pole.mesh = pc
	pole.material_override = iron
	pole.position = at + Vector3(0, 0.75, 0)
	root.add_child(pole)
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.7, 0.03, 0.05)
	bar.mesh = bb
	bar.material_override = iron
	bar.position = at + Vector3(0, 1.5, 0)
	root.add_child(bar)
	for k in 5:
		var x := (k - 2) * 0.16
		_candle(root, at + Vector3(x, 1.52, 0), 0.16 + 0.06 * float(2 - absi(k - 2)), 3.0 + k)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = 1.3
	l.omni_range = 4.5
	l.position = at + Vector3(0, 1.9, 0.3)
	l.set_meta("flicker", true)
	root.add_child(l)

## Grey ash drifting down through the hall, and a few embers glowing among it.
static func _ash(root: Node3D) -> void:
	for ember: bool in [false, true]:
		var p := GPUParticles3D.new()
		p.amount = 70 if ember else 320
		p.lifetime = 14.0
		p.preprocess = 14.0
		p.visibility_aabb = AABB(Vector3(-10, -2, -8), Vector3(20, 12, 14))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(9.0, 3.5, 4.0)
		pm.direction = Vector3(0.15, -1, 0)
		pm.spread = 35.0
		pm.initial_velocity_min = 0.08
		pm.initial_velocity_max = 0.25
		pm.gravity = Vector3(0, -0.05 if not ember else 0.02, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.4
		pm.turbulence_noise_scale = 2.5
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.03) if not ember else Vector2(0.025, 0.025)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if ember:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.0, 0.55, 0.2, 0.9)
		else:
			m.albedo_color = Color(0.62, 0.58, 0.55, 0.55)
		q.material = m
		p.draw_pass_1 = q
		p.position = Vector3(0, 3.8, -0.8)
		root.add_child(p)

static func _shader_mat(code: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	sm.shader = sh
	return sm

# --- shaders -----------------------------------------------------------------------------------------------

const NOISE := """
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
"""

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
""" + NOISE + """
void fragment() {
	vec2 p = wp.xz * vec2(1.1, 1.4);
	vec2 c = floor(p);
	vec2 f = fract(p);
	float seam = smoothstep(0.0, 0.04, f.x) * smoothstep(0.0, 0.04, f.y) * smoothstep(1.0, 0.96, f.x) * smoothstep(1.0, 0.96, f.y);
	float shade = 0.7 + h21(c) * 0.4;
	float grime = vnoise(wp.xz * 0.7) * 0.5 + vnoise(wp.xz * 3.0) * 0.25;
	float crack = smoothstep(0.03, 0.0, abs(vnoise(wp.xz * 1.3 + 7.0) - 0.5)) * 0.6;
	float fade = 1.0 - smoothstep(6.0, 9.5, length(wp.xz * vec2(0.8, 1.2)));
	vec3 base = vec3(0.13, 0.12, 0.11) * shade * (0.75 + grime * 0.5);
	ALBEDO = base * mix(0.35, 1.0, seam) * (1.0 - crack) * mix(0.25, 1.0, fade);
	ROUGHNESS = 0.6 + grime * 0.3;
	SPECULAR = 0.35;
}
"""

const STONE_SHADER := """
shader_type spatial;
varying vec3 wp;
varying vec3 wn;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
""" + NOISE + """
void fragment() {
	// ashlar blocks on walls and pillars, worn stone everywhere
	vec2 q = abs(wn.x) > abs(wn.z) ? wp.zy : wp.xy;
	if (abs(wn.y) > 0.6) q = wp.xz;
	q *= vec2(0.9, 1.7);
	q.x += floor(q.y) * 0.5;
	vec2 f = fract(q);
	float seam = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.07, f.y) * smoothstep(1.0, 0.95, f.x) * smoothstep(1.0, 0.93, f.y);
	float n = vnoise(wp.xy * 2.0 + wp.z) * 0.5 + vnoise(wp.zy * 6.0) * 0.3;
	vec3 c = vec3(0.15, 0.14, 0.13) * (0.82 + h21(floor(q)) * 0.22) * (0.65 + n * 0.6);
	ALBEDO = c * mix(0.62, 1.0, seam);
	ROUGHNESS = 0.85;
}
"""

const PLINTH_SHADER := """
shader_type spatial;
uniform vec4 glow : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float power = 0.5;
uniform float body_h = 0.3;
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
""" + NOISE + """
void fragment() {
	float side = 1.0 - abs(ln.y);
	float ang = atan(lp.z, lp.x) + 3.14159 / 6.0;
	float u = fract(ang / (6.28318 / 6.0)) * 2.0 - 1.0;   // across the face, -1..1
	float v = lp.y / body_h * 2.0;                         // up the face, -1..1
	// a recessed panel on each face
	float panel = step(abs(u), 0.72) * step(abs(v), 0.66);
	float rim = panel * (1.0 - step(abs(u), 0.64) * step(abs(v), 0.56));
	// a rune in the panel: a stave with two branches and a hook
	vec2 g = vec2(u / 0.5, v / 0.5);
	float w = 0.09;
	float rune = step(abs(g.x), w) * step(abs(g.y), 0.95);
	rune = max(rune, step(abs(g.y - 0.55 - g.x * 0.8), w * 1.3) * step(0.0, g.x) * step(g.x, 0.55));
	rune = max(rune, step(abs(g.y - 0.1 + g.x * 0.8), w * 1.3) * step(g.x, 0.0) * step(-0.55, g.x));
	rune = max(rune, step(abs(g.y + 0.55 - g.x * 0.6), w * 1.3) * step(0.0, g.x) * step(g.x, 0.5));
	rune *= panel * step(abs(g.y), 1.0);
	float n = vnoise(lp.xy * 9.0 + lp.z * 4.0) * 0.4 + vnoise(lp.zy * 22.0) * 0.2;
	vec3 stone = vec3(0.2, 0.185, 0.17) * (0.7 + n);
	stone *= mix(1.0, 0.55, panel - rim) * mix(1.0, 1.25, rim);
	ALBEDO = stone * mix(1.0, 0.3, rune);
	ROUGHNESS = 0.8;
	EMISSION = glow.rgb * (rune * (0.8 + 2.4 * power) + panel * 0.06 * power) * side;
}
"""

const CAP_SHADER := """
shader_type spatial;
uniform vec4 glow : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float power = 0.5;
uniform float rad = 0.6;
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
""" + NOISE + """
void fragment() {
	float r = length(lp.xz) / rad;
	float top = step(0.5, ln.y);
	// a carved ring near the edge of the top, glowing; the hero stands in a pool of the light
	float ring = smoothstep(0.035, 0.0, abs(r - 0.8)) * top;
	float pool = (1.0 - smoothstep(0.0, 0.75, r)) * top;
	float n = vnoise(lp.xz * 14.0) * 0.35;
	ALBEDO = vec3(0.24, 0.22, 0.2) * (0.75 + n) * mix(1.0, 0.5, ring);
	ROUGHNESS = 0.7;
	EMISSION = glow.rgb * (ring * (1.0 + 3.0 * power) + pool * 0.35 * power);
}
"""

const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float power = 0.5;
varying vec3 lp;
void vertex() { lp = VERTEX; }
""" + NOISE + """
void fragment() {
	float y = clamp(lp.y / 8.0 + 0.5, 0.0, 1.0);          // 0 at the plinth, 1 high up
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = edge * edge;
	float fall = smoothstep(1.0, 0.1, y) * smoothstep(0.0, 0.05, y);
	// slow streaks in the light and dust motes drifting down it
	float ang = atan(lp.x, lp.z);
	float streak = 0.75 + 0.25 * vnoise(vec2(ang * 3.0, lp.y * 0.6 - TIME * 0.15));
	vec2 g = vec2(ang * 9.0, lp.y * 9.0 + TIME * 0.7);
	float dust = step(0.975, h21(floor(g))) * smoothstep(0.5, 0.0, length(fract(g) - 0.5)) * 2.0;
	ALBEDO = col.rgb * (soft * fall * streak * 0.34 + dust * soft * fall * 0.7) * (0.25 + power * 1.25);
}
"""

const WINDOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float aspect = 4.0;   // height / half-width
varying vec2 uv2;
void vertex() { uv2 = UV; }
""" + NOISE + """
void fragment() {
	vec2 p = vec2(uv2.x * 2.0 - 1.0, (1.0 - uv2.y) * aspect);   // x -1..1, y 0..aspect from the sill
	float spring = aspect - 1.75;                                // where the pointed arch starts
	bool inside = abs(p.x) < 1.0 && p.y < spring;
	if (p.y >= spring) inside = length(p - vec2(-1.0, spring)) < 2.0 && length(p - vec2(1.0, spring)) < 2.0;
	if (!inside) discard;
	// stone frame round the opening, a mullion, a transom and a round light in the head
	float frame = 0.0;
	float inner_x = abs(p.x) < 0.86 ? 1.0 : 0.0;
	if (p.y >= spring) inner_x = (length(p - vec2(-1.0, spring)) < 1.86 && length(p - vec2(1.0, spring)) < 1.86) ? 1.0 : 0.0;
	frame = 1.0 - inner_x * step(0.12, p.y);
	float mull = step(abs(p.x), 0.06) * step(p.y, spring + 0.2);
	float tran = step(abs(p.y - spring * 0.55), 0.05);
	float rose = smoothstep(0.06, 0.0, abs(length(p - vec2(0.0, spring + 0.85)) - 0.4));
	float lead = step(0.94, fract(p.y * 1.6 + floor(p.x * 3.0) * 0.5)) + step(0.94, fract(p.x * 2.4));
	float stone = clamp(frame + mull + tran + rose, 0.0, 1.0);
	// cold light through dusty, broken glass; panes vary
	vec2 pane = floor(vec2(p.x * 2.4, p.y * 1.6));
	float tint = h21(pane);
	vec3 glass = mix(vec3(0.32, 0.42, 0.6), vec3(0.45, 0.5, 0.62), tint) * (0.7 + 0.3 * vnoise(p * 3.0));
	if (tint > 0.86) glass = vec3(0.04, 0.05, 0.07);            // broken panes, dark
	float hi = smoothstep(0.0, aspect, p.y);
	ALBEDO = mix(glass * (0.65 + 0.5 * hi) * (1.0 - clamp(lead, 0.0, 1.0) * 0.8), vec3(0.06, 0.055, 0.05), stone);
}
"""

const BANNER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 cloth : source_color = vec4(0.3, 0.1, 0.1, 1.0);
uniform vec4 mark : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform int emblem = 0;   // 0 diamond, 1 cross, 2 hood, 3 horns, 4 hat, 5 arrow
uniform float seed = 0.0;
""" + NOISE + """
void vertex() {
	float hang = UV.y;                                      // 0 at the rod, 1 at the hem
	VERTEX.z += sin(TIME * 1.1 + UV.y * 3.5 + seed) * 0.07 * hang;
	VERTEX.x += sin(TIME * 0.7 + UV.y * 2.5 + seed * 2.0) * 0.03 * hang;
}
float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return step(length(pa - ba * t), w);
}
void fragment() {
	vec2 uv = UV;
	// a ragged, torn hem with a notch in the middle, and moth holes
	float hem = 0.8 + 0.08 * vnoise(vec2(uv.x * 7.0 + seed, 0.0)) + 0.05 * sin(uv.x * 19.0 + seed * 3.0) - 0.12 * smoothstep(0.18, 0.0, abs(uv.x - 0.5));
	if (uv.y > hem) discard;
	if (vnoise(uv * vec2(9.0, 14.0) + seed) > 0.78 && uv.y > 0.45) discard;
	vec3 c = cloth.rgb * (0.75 + 0.35 * vnoise(uv * vec2(40.0, 90.0)));
	c *= 0.7 + 0.3 * (0.5 + 0.5 * sin(uv.x * 17.0 + sin(uv.y * 3.0)));   // folds
	c *= 1.0 - 0.45 * smoothstep(0.55, 0.8, uv.y);                      // grimy, scorched hem
	// a gold border and the emblem
	float border = step(uv.x, 0.06) + step(0.94, uv.x) + step(uv.y, 0.04);
	vec2 p = vec2((uv.x - 0.5) * 3.1, (0.3 - uv.y) * 6.6);              // emblem space, centred
	float e = 0.0;
	if (emblem == 1) {
		e = max(step(abs(p.x), 0.11) * step(abs(p.y + 0.15), 0.85), step(abs(p.y - 0.25), 0.11) * step(abs(p.x), 0.5));
	} else if (emblem == 2) {
		e = step(abs(length(p - vec2(0.0, 0.1)) - 0.45), 0.08) * step(-0.3, p.y);
		e = max(e, step(length(p - vec2(-0.16, 0.12)), 0.07) + step(length(p - vec2(0.16, 0.12)), 0.07));
		e = max(e, seg(p, vec2(-0.45, 0.1), vec2(-0.6, -0.75), 0.07) + seg(p, vec2(0.45, 0.1), vec2(0.6, -0.75), 0.07));
	} else if (emblem == 3) {
		e = seg(p, vec2(-0.2, -0.1), vec2(-0.55, 0.65), 0.08) + seg(p, vec2(0.2, -0.1), vec2(0.55, 0.65), 0.08);
		e = max(e, step(abs(length(p - vec2(0.0, -0.3)) - 0.28), 0.07));
	} else if (emblem == 4) {
		e = seg(p, vec2(-0.6, -0.45), vec2(0.6, -0.45), 0.07) + seg(p, vec2(-0.4, -0.45), vec2(0.05, 0.75), 0.07) + seg(p, vec2(0.4, -0.45), vec2(0.05, 0.75), 0.07);
		e = max(e, step(length(p - vec2(0.3, 0.1)), 0.1));
	} else if (emblem == 5) {
		e = seg(p, vec2(0.0, -0.8), vec2(0.0, 0.7), 0.06) + seg(p, vec2(0.0, 0.75), vec2(-0.25, 0.4), 0.07) + seg(p, vec2(0.0, 0.75), vec2(0.25, 0.4), 0.07);
		e = max(e, seg(p, vec2(0.0, -0.8), vec2(-0.2, -0.55), 0.05) + seg(p, vec2(0.0, -0.8), vec2(0.2, -0.55), 0.05));
		e = max(e, step(abs(length(p) - 0.7), 0.05) * step(p.x, 0.0));
	} else {
		e = step(abs(abs(p.x) + abs(p.y) - 0.5), 0.07) + step(length(p), 0.13);
	}
	e = clamp(e, 0.0, 1.0);
	vec3 gold = vec3(0.55, 0.42, 0.18);
	ALBEDO = mix(mix(c, gold, clamp(border, 0.0, 1.0) * 0.7), mark.rgb * 0.55, e * 0.85);
	EMISSION = mark.rgb * e * 0.12;
	ROUGHNESS = 0.95;
}
"""

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float seed = 0.0;
void vertex() {
	// always faces the camera (a billboard), and flickers
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float fl = 0.85 + 0.15 * sin(TIME * 13.0 + seed * 5.0) * sin(TIME * 7.3 + seed);
	VERTEX.y *= fl;
	VERTEX.x += sin(TIME * 5.0 + seed) * 0.006 * (UV.y < 0.5 ? 1.0 : 0.0);
}
void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float body = 1.0 - smoothstep(0.0, 1.0, length(vec2(p.x * 1.6, (p.y - 0.32) * (p.y > 0.32 ? 0.75 : 2.2))));
	vec3 c = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.92, 0.65), smoothstep(0.3, 0.8, body));
	ALBEDO = c * body * 2.2;
}
"""
