class_name BrazierCoals
extends Node3D
## What burns inside a waypoint brazier's bowl: fractured dark basalt stones and sapphire crystals, an ember bed
## under them, energy running through the cracks, sparks between the fragments and heat shimmer above. Built from
## `assets/models/waypoint/coals.glb` (tools/blender/waypoint/rock_library.py): a library of unique pieces
## (`lib/rock_NN_l0|l1`, `frag_NN_*`, `cry_NN_*`, two LODs each, one baked atlas for the stones and one for the
## crystals: albedo, normal, AO + roughness, and a crack / vein mask in the emissive map) and four piles settled in
## the real bowl with rigid-body physics (`arr_K`: one Empty per stone, named `iNN_<piece>`, its transform the
## instance, in the brazier node's frame at the game's scale). One call per brazier from WaypointGrand:
##   BrazierCoals.build(brazier_node, pile_index, fire_root)
## Each pile is merged into one mesh per material (stones, crystals), at LOD0 for close views and LOD1 beyond
## `LOD_DIST`, the LOD1 copy being the only shadow caster; plus the bed. Every frame the pile reads the flame's own
## flicker from the fire's light (`FireLight`, animated by Game's flicker loop) so the glow in the cracks, the veins
## and the embers move with the flame. Without the glb a small code-built pile stands in (`_fallback`).
## Per vertex, COLOR carries per-stone data written at merge time: r = this stone's glow weight (most stones 0:
## the contrast of dark stone and lit crystal is the point), g = its phase.

const GLB := "res://assets/models/waypoint/coals.glb"
const LOD_DIST := 13.0           # LOD0 nearer than this (close-ups, zoomed in), LOD1 beyond (the gameplay camera)
const FLOOR_Y := 1.2134          # the cleaned brazier's dish floor in the brazier node's frame (clean_bowl.py x 1.15)
const BED_R := 0.345             # the ember bed's radius (the dish out to the wall's foot)
const GLOW_SHARE := 0.3          # about this share of the stones carry energy in their cracks
const TINT := 0.78               # the stone atlas a little darker than baked: cold charcoal under the blue light

static var _lib := {}            # piece -> {"l0": Mesh, "l1": Mesh, "kind": String}
static var _piles := []          # per pile: [{"piece": String, "xf": Transform3D}]
static var _tex := {}            # "rock"/"cry" -> {"alb", "nrm", "orm", "glow"} textures from the glb
static var _loaded := false
static var _shaders := {}

var pile := 0
var fire_light: OmniLight3D
var mats: Array[ShaderMaterial] = []
var _t := 0.0
var _flick := 1.0

static func build(parent: Node3D, index: int, fire_root: Node3D) -> BrazierCoals:
	var c := BrazierCoals.new()
	c.name = "coals"
	c.pile = index
	if fire_root != null:
		c.fire_light = fire_root.get_node_or_null("FireLight") as OmniLight3D
	parent.add_child(c)
	c._build()
	return c

# ---------------------------------------------------------------- the library
static func _load() -> bool:
	if _loaded:
		return not _lib.is_empty()
	_loaded = true
	if not ResourceLoader.exists(GLB):
		return false
	var scene := (load(GLB) as PackedScene).instantiate()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var nm := str(mi.name)
		if nm.length() < 4 or not (nm.ends_with("_l0") or nm.ends_with("_l1")):
			continue
		var piece := nm.substr(0, nm.length() - 3)
		var lod := nm.substr(nm.length() - 2)
		if not _lib.has(piece):
			_lib[piece] = {"kind": piece.split("_")[0]}
		_lib[piece][lod] = mi.mesh
		var grp := "cry" if piece.begins_with("cry") else "rock"
		if not _tex.has(grp):
			var m := mi.mesh.surface_get_material(0)
			if m is StandardMaterial3D:
				var sm: StandardMaterial3D = m
				_tex[grp] = {"alb": sm.albedo_texture, "nrm": sm.normal_texture, "orm": sm.roughness_texture if sm.roughness_texture else sm.metallic_texture, "glow": sm.emission_texture, "ao": sm.ao_texture}
	_piles.clear()
	var k := 0
	while true:
		var arr := scene.find_child("arr_%d" % k, true, false) as Node3D
		if arr == null:
			break
		var inst := []
		for e in arr.get_children():
			if not (e is Node3D):
				continue
			var en := str(e.name)
			var piece := ""
			if e.has_meta("piece"):
				piece = str(e.get_meta("piece"))
			else:
				var us := en.find("_")
				piece = en.substr(us + 1) if us >= 0 else en
			if _lib.has(piece):
				inst.append({"piece": piece, "xf": (e as Node3D).transform})
		_piles.append(inst)
		k += 1
	scene.free()
	return not _lib.is_empty()

static func _shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		match key:
			"rock":
				s.code = ROCK_SHADER
			"cry":
				s.code = CRYSTAL_SHADER.replace("//REFRACT", "")
			"cry_plain":
				s.code = CRYSTAL_SHADER
			"bed":
				s.code = BED_SHADER
		_shaders[key] = s
	return _shaders[key]

## Each stone's glow weight (r: 0 for most, the contrast is the point) and phase (g), one colour per instance,
## the same for both LODs.
static func _colors(inst: Array, rng: RandomNumberGenerator) -> PackedColorArray:
	var out := PackedColorArray()
	for it in inst:
		var p: Dictionary = _lib[it["piece"]]
		var glow := 0.0
		if p["kind"] != "cry" and rng.randf() < GLOW_SHARE:
			glow = rng.randf_range(0.35, 1.0)
		out.append(Color(glow, rng.randf(), 0.0, 1.0))
	return out

## The merged mesh of one pile at one LOD: every instance's surface transformed into the brazier's frame, with
## the stone's glow weight and phase in the vertex colour. kind: "rock" (stones and fragments) or "cry".
static func _merge(inst: Array, lod: String, kind: String, cols_in: PackedColorArray) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in inst.size():
		var it: Dictionary = inst[k]
		var p: Dictionary = _lib[it["piece"]]
		var is_cry: bool = p["kind"] == "cry"
		if is_cry != (kind == "cry"):
			continue
		var mesh: Mesh = p.get(lod, p.get("l0"))
		if mesh == null:
			continue
		var xf: Transform3D = it["xf"]
		var rot := Transform3D(xf.basis, Vector3.ZERO)
		var col := cols_in[k]
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var ind: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var base := verts.size()
			verts.append_array(xf * v)
			var bn: PackedVector3Array = rot * n
			for i in bn.size():
				bn[i] = bn[i].normalized()
			norms.append_array(bn)
			uvs.append_array(uv)
			var cc := PackedColorArray()
			cc.resize(v.size())
			cc.fill(col)
			cols.append_array(cc)
			if ind.is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in ind.size():
					idx.append(base + ind[i])
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# tangents for the normal map (SurfaceTool does it in C++)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_tangents()
	return st.commit()

func _mat(kind: String, game) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var t: Dictionary = _tex.get(kind, {})
	if kind == "cry":
		var refract: bool = game != null and InfernalFx.tier(game) >= 2 and bool(game.is_forward())
		m.shader = _shader("cry" if refract else "cry_plain")
		m.set_shader_parameter("refract_amt", 0.05 if refract else 0.0)
		m.set_shader_parameter("noise_tex", InfernalFx.noise())
	else:
		m.shader = _shader("rock")
		m.set_shader_parameter("tint", TINT)
	if t.has("alb") and t["alb"] != null:
		m.set_shader_parameter("alb_tex", t["alb"])
	if t.has("nrm") and t["nrm"] != null:
		m.set_shader_parameter("nrm_tex", t["nrm"])
	if t.has("orm") and t["orm"] != null:
		m.set_shader_parameter("orm_tex", t["orm"])
	if t.has("glow") and t["glow"] != null:
		m.set_shader_parameter("glow_tex", t["glow"])
	m.set_shader_parameter("fire", 1.0)
	m.set_shader_parameter("heart", Vector3(0, FLOOR_Y + 0.06, 0))
	mats.append(m)
	return m

func _build() -> void:
	var ml := Engine.get_main_loop() as SceneTree
	var game = ml.root.get_node_or_null("Game") if ml != null else null
	var tr: int = InfernalFx.tier(game) if game != null else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 4421 + pile * 97
	if not _load() or _piles.is_empty():
		_fallback(rng)
	else:
		var inst: Array = _piles[pile % _piles.size()]
		var cols := _colors(inst, rng)
		for kind in ["rock", "cry"]:
			var m0 := _merge(inst, "l0", kind, cols)
			var m1 := _merge(inst, "l1", kind, cols)
			if m0 == null:
				continue
			var mat := _mat(kind, game)
			var near := MeshInstance3D.new()
			near.name = kind + "_l0"
			near.mesh = m0
			near.material_override = mat
			near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			near.visibility_range_end = LOD_DIST
			near.visibility_range_end_margin = 0.5
			add_child(near)
			if m1 != null:
				var far := MeshInstance3D.new()
				far.name = kind + "_l1"
				far.mesh = m1
				far.material_override = mat
				far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				far.visibility_range_begin = LOD_DIST
				far.visibility_range_begin_margin = 0.5
				add_child(far)
				var sh := MeshInstance3D.new()
				sh.name = kind + "_shadow"
				sh.mesh = m1
				sh.material_override = mat
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				add_child(sh)
	_bed()
	# sparks jumping between the fragments and motes drifting up out of the gaps (Medium and up)
	if tr >= 1:
		var sp := InfernalFx.particles(self, Vector3.ZERO, {"amount": 7, "life": 0.55, "one_shot": false, "randomness": 0.9,
			"shape": "sphere", "r": 0.17, "dir": Vector3.UP, "spread": 70.0, "vel": [0.25, 0.9], "gravity": -2.5,
			"scale": [0.3, 0.8], "size": 0.016, "damping": [0.5, 1.5],
			"colors": [[0.0, Color(0.95, 0.98, 1.0)], [0.3, Color(0.45, 0.75, 1.0)], [1.0, Color(0.2, 0.3, 1.0, 0.0)]]})
		sp.name = "sparks"
		sp.position = Vector3(0, FLOOR_Y + 0.1, 0)
		sp.local_coords = true
		var mo := InfernalFx.particles(self, Vector3.ZERO, {"amount": 9, "life": 2.6, "one_shot": false, "randomness": 0.8,
			"shape": "sphere", "r": 0.2, "dir": Vector3.UP, "spread": 20.0, "vel": [0.12, 0.3], "gravity": 0.08,
			"scale": [0.4, 1.0], "size": 0.014, "turb": 0.6,
			"colors": [[0.0, Color(0.5, 0.75, 1.0, 0.0)], [0.2, Color(0.5, 0.78, 1.0)], [0.7, Color(0.25, 0.4, 1.0)], [1.0, Color(0.15, 0.2, 0.9, 0.0)]]})
		mo.name = "motes"
		mo.position = Vector3(0, FLOOR_Y + 0.09, 0)
		mo.local_coords = true
	# heat shimmer right over the stones, where the flames rise (Forward+, High and Ultra)
	if game != null and InfernalFx.haze_ok(game):
		var hz := InfernalFx.glow(self, global_position, 0.55, InfernalFx.haze_mat(0.007, true))
		hz.name = "haze"
		hz.position = Vector3(0, FLOOR_Y + 0.3, 0)
	set_process(true)

## The ember bed under the stones: an ash layer on the dish's floor, cracked, with blue embers breathing in the
## cracks and the heart of the fire glowing up through the middle; seen in the gaps between stones.
func _bed() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 8
	var segs := 36
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + pile
	var pts: Array[Vector3] = []
	pts.append(Vector3(0, FLOOR_Y + 0.011, 0))
	for i in range(1, rings + 1):
		var r := BED_R * pow(float(i) / rings, 1.2)
		for s in segs:
			var a := TAU * s / segs
			var y := FLOOR_Y + 0.011 + 0.026 * pow(r / BED_R, 2.2) + rng.randf_range(-0.003, 0.003) * (1.0 - float(i) / rings)
			pts.append(Vector3(cos(a) * r, y, sin(a) * r))
	for p in pts:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x, p.z) * 2.0 + Vector2(0.5, 0.5))
		st.add_vertex(p)
	for s in segs:
		st.add_index(0)
		st.add_index(1 + (s + 1) % segs)
		st.add_index(1 + s)
	for i in range(1, rings):
		for s in segs:
			var a0 := 1 + (i - 1) * segs + s
			var a1 := 1 + (i - 1) * segs + (s + 1) % segs
			var b0 := 1 + i * segs + s
			var b1 := 1 + i * segs + (s + 1) % segs
			st.add_index(a0); st.add_index(a1); st.add_index(b0)
			st.add_index(a1); st.add_index(b1); st.add_index(b0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "bed"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = _shader("bed")
	m.set_shader_parameter("cells_tex", InfernalFx.cells())
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("fire", 1.0)
	m.set_shader_parameter("seed", float(pile) * 1.37)
	mats.append(m)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Without the library: a few dark stones and a crystal or two built from primitives (never shipped; keeps the
## waypoint whole on a checkout without the glb).
func _fallback(rng: RandomNumberGenerator) -> void:
	var stone := Mats.world(Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06), 0.92, 4.0, 0.0)
	var cry := Mats.mat(Color(0.05, 0.14, 0.45), 0.12, 0.0, Color(0.15, 0.4, 1.0), 0.8)
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.25)
		var s := rng.randf_range(0.035, 0.09)
		var mi := Models.P(self, Geo.sph(s * 0.5, 6), stone, Vector3(cos(a) * r, FLOOR_Y + s * 0.4, sin(a) * r),
				Vector3(rng.randf_range(0, 360), rng.randf_range(0, 360), 0), Vector3(1.0, rng.randf_range(0.5, 0.8), rng.randf_range(0.7, 1.1)))
		mi.name = "stone%d" % i
	for i in 3:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.04, 0.16)
		var h := rng.randf_range(0.08, 0.15)
		Models.P(self, Geo.cyl(0.0, 0.02, h, 6), cry, Vector3(cos(a) * r, FLOOR_Y + 0.06 + h * 0.5, sin(a) * r),
				Vector3(rng.randf_range(-25, 25), rng.randf_range(0, 360), rng.randf_range(-25, 25)))

func _process(delta: float) -> void:
	_t += delta
	# the flame's own flicker (Game's flicker loop drives the fire's light every frame): the cracks, veins and
	# embers follow it, so the light in the bowl is one thing
	var f := 1.0
	if fire_light != null and is_instance_valid(fire_light) and fire_light.has_meta("base"):
		var b := float(fire_light.get_meta("base"))
		if b > 0.0:
			f = fire_light.light_energy / b
	else:
		f = 0.8 + 0.1 * sin(_t * 7.1 + pile) + 0.07 * sin(_t * 13.7 + pile * 2.1)
	_flick = lerpf(_flick, f, minf(1.0, delta * 18.0))
	for m in mats:
		m.set_shader_parameter("fire", _flick)

# ---------------------------------------------------------------- shaders
## The stones: the baked PBR atlas (albedo, normal, AO + roughness) and the crack mask (R of the glow map) lit as
## energy that runs along the cracks of the stones that carry it (COLOR.r, phase COLOR.g), flickering with the
## flame (`fire`); the fire's heart and the ember bed warm the faces turned to them from inside (`heart`).
const ROCK_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap;
uniform vec3 glow_col : source_color = vec3(0.12, 0.42, 1.0);
uniform vec3 hot_col : source_color = vec3(0.75, 0.92, 1.0);
uniform vec3 heart = vec3(0.0, 1.27, 0.0);
uniform float fire = 1.0;
uniform float tint = 0.8;
varying vec3 lpos;
varying vec3 lnrm;
varying vec4 vcol;
void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	vcol = COLOR;
}
void fragment() {
	vec3 alb = texture(alb_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float crack_m = texture(glow_tex, UV).r;
	ALBEDO = alb * tint;
	ROUGHNESS = clamp(orm.g, 0.3, 1.0);
	METALLIC = 0.0;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = texture(nrm_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	// energy travelling through the cracks: a slow wave along the stone, in this stone's own phase, then the
	// flame's flicker on top; brighter cracks go cyan-white
	float ph = vcol.g * 6.2832;
	float travel = 0.5 + 0.5 * sin(TIME * 1.6 + ph + lpos.y * 22.0 + lpos.x * 11.0 - lpos.z * 7.0);
	travel = 0.35 + 0.65 * travel * travel;
	float crack = crack_m * vcol.r * travel;
	float fl = clamp(fire, 0.3, 1.3);
	vec3 em = glow_col * crack * (1.5 + 2.5 * fl) + hot_col * crack * crack * fl * 2.0;
	// the heart of the fire and the ember bed light the stones from inside: faces turned toward the heart, near it
	vec3 to_h = heart - lpos;
	float d = length(to_h);
	float face = clamp(dot(normalize(lnrm), to_h / max(d, 0.001)), 0.0, 1.0);
	float under = clamp(-lnrm.y, 0.0, 1.0) * clamp(1.0 - (lpos.y - heart.y + 0.06) / 0.1, 0.0, 1.0);
	float heat = (face * clamp(1.0 - d / 0.3, 0.0, 1.0) * 0.5 + under * 0.4) * fl * fl;
	em += glow_col * heat * (0.45 + 0.55 * orm.r) * 0.8;
	EMISSION = em;
}
"""

## The crystals: a deep sapphire body under the baked atlas (Meshy's inclusions on the cluster chunks, procedural
## cloud on the prisms), low varied roughness so the flame's light plays on the facets, a fresnel rim, a fake
## interior (noise sampled along the view ray, so it parallaxes inside), the veins (G of the glow map) pulsing and
## running along the prism, and on High / Ultra a refraction of what stands behind it (the //REFRACT lines).
const CRYSTAL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D glow_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
//REFRACT uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.01, 0.045, 0.22);
uniform vec3 vein : source_color = vec3(0.3, 0.72, 1.0);
uniform vec3 heart = vec3(0.0, 1.27, 0.0);
uniform float fire = 1.0;
uniform float refract_amt = 0.0;
varying vec3 lpos;
varying vec4 vcol;
varying vec3 vdir_l;
void vertex() {
	lpos = VERTEX;
	vcol = COLOR;
	// the view direction in the crystal's own frame, for the interior parallax
	vec3 cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vdir_l = normalize(cam_l - VERTEX);
}
void fragment() {
	vec3 alb = texture(alb_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float veins = texture(glow_tex, UV).g;
	float fl = clamp(fire, 0.3, 1.3);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	// inside: two layers of cloud at different depths, drifting the other way as the view moves
	float in1 = texture(noise_tex, lpos.xz * 9.0 + lpos.y * 3.0 + vdir_l.xz * 0.06 + vec2(0.0, TIME * 0.015)).r;
	float in2 = texture(noise_tex, lpos.xy * 7.0 + lpos.z * 2.0 - vdir_l.xy * 0.14 + 3.1).r;
	float cloud = in1 * 0.6 + in2 * 0.4;
	vec3 body = mix(deep, alb, 0.6) * (0.65 + 0.7 * cloud);
	//REFRACT vec2 off = (normalize(NORMAL).xy) * refract_amt * (1.0 - fres * 0.5);
	//REFRACT vec3 behind = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999))).rgb;
	//REFRACT body = mix(body, behind * vec3(0.45, 0.65, 1.0) + deep * 0.5, 0.3 * (1.0 - fres));
	ALBEDO = body;
	ROUGHNESS = clamp(0.1 + 0.12 * in2 + orm.g * 0.15, 0.06, 0.5);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	NORMAL_MAP = texture(nrm_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	// the veins pulse and run up the prism; the glow deep inside breathes with the fire; a cold rim
	float pulse = 0.55 + 0.45 * sin(TIME * 1.25 + vcol.g * 6.2832 + lpos.y * 28.0);
	vec3 em = vein * veins * pulse * (0.7 + 1.5 * fl);
	em += deep * 3.5 * in2 * in1 * (0.4 + 0.6 * fl);
	em += vein * fres * 0.3 * fl;
	// the fire's heart lights the crystal from below
	vec3 to_h = heart - lpos;
	float d = length(to_h);
	em += deep * 4.0 * clamp(1.0 - d / 0.26, 0.0, 1.0) * fl * fl;
	EMISSION = em;
}
"""

## The ember bed: ash over the dish, cracked into plates whose edges glow blue, more toward the middle where the
## heart of the fire burns up through it; it breathes with the flame.
const BED_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D cells_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 ash : source_color = vec3(0.045, 0.045, 0.05);
uniform vec3 ember : source_color = vec3(0.1, 0.4, 1.0);
uniform vec3 hot : source_color = vec3(0.8, 0.93, 1.0);
uniform float fire = 1.0;
uniform float seed = 0.0;
varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	vec2 p = lpos.xz + vec2(seed * 0.37, seed * 0.11);
	float cells = texture(cells_tex, p * 7.0).r;
	float crack = 1.0 - smoothstep(0.0, 0.11, cells);
	float n = texture(noise_tex, p * 2.5 + vec2(TIME * 0.03, -TIME * 0.02)).r;
	float grain = texture(noise_tex, p * 16.0).r;
	float r = length(lpos.xz);
	float centre = 1.0 - smoothstep(0.02, 0.26, r);
	float fl = clamp(fire, 0.3, 1.3);
	float glow = crack * (0.35 + 0.65 * n) * (0.3 + 0.7 * centre) + centre * centre * 0.6;
	glow *= fl;
	ALBEDO = ash * (0.6 + 0.8 * grain) * (1.0 - 0.5 * crack);
	ROUGHNESS = 0.95;
	EMISSION = ember * glow * 3.5 + hot * glow * glow * 2.5;
}
"""
