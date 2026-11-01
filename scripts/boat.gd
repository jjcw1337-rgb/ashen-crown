class_name Boat
extends RefCounted
## Boats (Data.BOATS): what a boat looks like. The sailing (riding the waves, steering, the wake) is the
## BoatRide node (boat_ride.gd); this file only builds models, so the shop's preview, the boat moored
## at the pier and the one you sail are the same.
##
## The Gull: a single-masted cutter about 7.4 m long. A planked clinker hull (lofted from cross-sections:
## a fine bow, full middle, a narrow transom; the sheer rising toward the bow), a painted band under the
## gunwale and tar below the waterline, a deck with a hatch, a bowsprit, a mast with a gaff mainsail
## and a jib (cloth that ripples), standing rigging, a rudder and tiller, a lantern on the stern, barrels
## and rope on deck. The bow is toward -z (Godot's forward), the waterline at y = 0.

const LENGTH := 7.4
const BEAM := 2.5
const SHEER := 1.05          # gunwale height above the waterline amidships
const DRAFT := 0.55          # keel depth below the waterline amidships

static var _cache := {}

## A boat's size: Data.BOATS keys "length", "beam", "sheer" and "draft" (metres), the Gull's when left out.
## BoatRide scales its shallow-water probes, the helm, the wake and the spray by these, so a bigger boat sails
## the same way. tools/blender/prep_boat.py prints them for an imported model.
static func dims(id: String) -> Dictionary:
	var spec: Dictionary = Data.BOATS.get(id, Data.BOATS["gull"])
	return {"length": float(spec.get("length", LENGTH)), "beam": float(spec.get("beam", BEAM)),
		"sheer": float(spec.get("sheer", SHEER)), "draft": float(spec.get("draft", DRAFT))}

## A boat's model by id (Data.BOATS). A boat with a "glb" (a Meshy or Blender model prepared by
## tools/blender/prep_boat.py: bow toward -z, waterline at y = 0) loads that file; a missing file falls back to
## the Gull built in code, so a boat can be swapped for a better model by changing one path.
static func model(id: String) -> Node3D:
	var spec: Dictionary = Data.BOATS.get(id, Data.BOATS["gull"])
	if spec.has("glb"):
		var imported := _glb_model(id, spec)
		if imported != null:
			return imported
	var root := Node3D.new()
	root.name = "Boat"
	var paint: Color = spec.get("paint", Color(0.16, 0.3, 0.42))
	var hull := MeshInstance3D.new()
	hull.name = "hull"
	hull.mesh = hull_mesh()
	hull.material_override = hull_mat(paint)
	root.add_child(hull)
	var wd := Props.wood()
	var wdd := Props.wood_dark()
	# deck, hatch, thwart
	var deck := MeshInstance3D.new()
	deck.name = "deck"
	deck.mesh = deck_mesh()
	deck.material_override = deck_mat()
	root.add_child(deck)
	Models.P(root, Geo.box(0.9, 0.22, 1.1), wdd, Vector3(0, SHEER - 0.05, 0.3))
	Models.P(root, Geo.box(0.95, 0.04, 1.15), wd, Vector3(0, SHEER + 0.07, 0.3))
	# keel and stem post, sternpost
	Models.seg(root, Vector3(0, -DRAFT - 0.05, LENGTH * 0.42), Vector3(0, -DRAFT - 0.05, -LENGTH * 0.34), 0.07, 0.07, wdd, 5)
	Models.seg(root, Vector3(0, -DRAFT + 0.05, -LENGTH * 0.35), Vector3(0, SHEER + 0.55, -LENGTH * 0.5 - 0.15), 0.08, 0.06, wdd, 6)
	# bowsprit
	var bs_a := Vector3(0, SHEER + 0.35, -LENGTH * 0.42)
	var bs_b := Vector3(0, SHEER + 0.6, -LENGTH * 0.5 - 1.6)
	Models.seg(root, bs_a, bs_b, 0.07, 0.05, wd, 7)
	# rudder and tiller
	Models.P(root, Geo.box(0.07, 1.25, 0.65), wdd, Vector3(0, 0.0, LENGTH * 0.5 + 0.18))
	Models.seg(root, Vector3(0, SHEER + 0.2, LENGTH * 0.5 + 0.2), Vector3(0, SHEER + 0.42, LENGTH * 0.5 - 1.15), 0.045, 0.035, wd, 6)
	# the mast, boom and gaff
	var mz := -LENGTH * 0.12
	var mast_top := Vector3(0, SHEER + 7.6, mz)
	Models.seg(root, Vector3(0, SHEER - 0.6, mz), mast_top, 0.11, 0.07, wd, 8)
	var boom_a := Vector3(0, SHEER + 1.35, mz + 0.1)
	var boom_b := Vector3(0.25, SHEER + 1.55, LENGTH * 0.5 + 0.4)
	Models.seg(root, boom_a, boom_b, 0.07, 0.06, wd, 7)
	var gaff_a := Vector3(0, SHEER + 5.4, mz + 0.1)
	var gaff_b := Vector3(0.2, SHEER + 7.0, LENGTH * 0.34)
	Models.seg(root, gaff_a, gaff_b, 0.055, 0.045, wd, 7)
	# sails: the gaff main and the jib, canvas that ripples in the wind (the cloth shader)
	var canvas := ShaderMaterial.new()
	canvas.shader = Mats.shader("cloth")
	canvas.set_shader_parameter("albedo", Color(0.86, 0.82, 0.7))
	canvas.set_shader_parameter("trim", Color(0.6, 0.38, 0.2))
	canvas.set_shader_parameter("wave", 0.35)
	canvas.set_shader_parameter("edges", 0.0)
	var main := MeshInstance3D.new()
	main.name = "mainsail"
	main.mesh = sail_mesh([boom_a + Vector3(0, 0.05, 0.1), boom_b + Vector3(0, 0.05, -0.1), gaff_b - Vector3(0, 0.08, 0.1), gaff_a - Vector3(0, 0.05, -0.1)], 0.35)
	main.material_override = canvas
	root.add_child(main)
	var jib := MeshInstance3D.new()
	jib.name = "jib"
	var jib_head := mast_top - Vector3(0, 1.0, 0)
	jib.mesh = sail_mesh([bs_b + Vector3(0, 0.1, 0.25), Vector3(0.15, SHEER + 0.7, mz - 0.6), jib_head + Vector3(0, -0.2, -0.15), jib_head + Vector3(0, -0.2, -0.15)], 0.25)
	jib.material_override = canvas
	root.add_child(jib)
	# standing rigging: forestay, backstay, shrouds, the halyards
	var rope := Mats.world(Color(0.42, 0.36, 0.26), Color(0.3, 0.25, 0.18), 0.95, 3.0)
	for line in [[mast_top, bs_b], [mast_top, Vector3(0, SHEER + 0.3, LENGTH * 0.5)], [mast_top - Vector3(0, 0.4, 0), Vector3(-BEAM * 0.47, SHEER + 0.05, mz + 0.4)],
			[mast_top - Vector3(0, 0.4, 0), Vector3(BEAM * 0.47, SHEER + 0.05, mz + 0.4)], [mast_top - Vector3(0, 0.4, 0), Vector3(-BEAM * 0.45, SHEER + 0.05, mz + 1.3)],
			[mast_top - Vector3(0, 0.4, 0), Vector3(BEAM * 0.45, SHEER + 0.05, mz + 1.3)], [gaff_b, boom_b + Vector3(0, 0.1, 0)], [mast_top, gaff_b - Vector3(0, 0.1, 0.6)]]:
		Models.seg(root, line[0], line[1], 0.014, 0.014, rope, 4)
	# lantern on a post at the stern, its light
	Models.seg(root, Vector3(-0.6, SHEER, LENGTH * 0.44), Vector3(-0.6, SHEER + 1.3, LENGTH * 0.44), 0.035, 0.03, wdd, 5)
	Models.P(root, Geo.box(0.18, 0.24, 0.18), Props.iron(), Vector3(-0.6, SHEER + 1.42, LENGTH * 0.44))
	var lamp := OmniLight3D.new()
	lamp.name = "lamp"
	lamp.light_color = Color(1.0, 0.72, 0.38)
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	root.add_child(lamp)
	lamp.position = Vector3(-0.6, SHEER + 1.42, LENGTH * 0.44)
	var glow := Models.P(root, Geo.box(0.11, 0.14, 0.11), Mats.mat(Color(1.0, 0.75, 0.4), 0.5, 0.0, Color(1.0, 0.65, 0.3), 3.0), Vector3(-0.6, SHEER + 1.42, LENGTH * 0.44))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# cargo: barrels lashed by the mast, a coil of rope, a crate
	Props.barrel(root, Vector3(0.62, SHEER - 0.18, mz + 0.9))
	Props.barrel(root, Vector3(-0.6, SHEER - 0.18, mz + 1.0))
	Props.crate(root, Vector3(0.35, SHEER - 0.2, LENGTH * 0.28), 0.9)
	Models.P(root, Geo.torus(0.12, 0.28, 14, 6), rope, Vector3(-0.45, SHEER - 0.12, LENGTH * 0.3))
	root.set_meta("boat", id)
	return root

## An imported boat: the glb, plus its lanterns' lights (spec "lamps": [[Vector3 position, energy], ...]).
static func _glb_model(id: String, spec: Dictionary) -> Node3D:
	var path := str(spec["glb"])
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var root := Node3D.new()
	root.name = "Boat"
	var body := ps.instantiate() as Node3D
	body.name = "model"
	root.add_child(body)
	var li := 0
	for lp in spec.get("lamps", []):
		var lamp := OmniLight3D.new()
		lamp.name = "lamp%d" % li
		li += 1
		lamp.light_color = Color(1.0, 0.72, 0.38)
		lamp.light_energy = float(lp[1])
		lamp.omni_range = 6.0
		root.add_child(lamp)
		lamp.position = lp[0]
	root.set_meta("boat", id)
	return root

# ---------------------------------------------------------------- hull
## Half-breadth, sheer and keel at t (0 = stern, 1 = bow).
static func _sec(t: float) -> Vector3:
	var b := BEAM * 0.5 * pow(sin(PI * (0.2 + 0.8 * t)), 0.75)
	b = maxf(b, BEAM * 0.5 * 0.62 * (1.0 - smoothstep(0.0, 0.25, t)))   # the transom keeps some width
	b *= 1.0 - smoothstep(0.82, 1.0, t) * 0.92
	var sheer := SHEER + 0.35 * pow(t, 2.2) + 0.12 * pow(1.0 - t, 3.0)
	var keel := DRAFT * (0.55 + 0.45 * sin(PI * clampf(t * 1.05, 0.0, 1.0)))
	return Vector3(b, sheer, keel)

## The hull: girth u (0 keel .. 1 gunwale) by length t, both sides, plus the transom. UV = (u, t) for
## the plank shader.
static func hull_mesh() -> Mesh:
	if _cache.has("hull"):
		return _cache["hull"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nt := 36
	var nu := 14
	var pts := []
	for i in nt + 1:
		var t := float(i) / nt
		var s := _sec(t)
		var row := []
		for j in nu + 1:
			var u := float(j) / nu
			var x := s.x * pow(sin(u * PI * 0.5), 0.65)
			var y := -s.z + (s.y + s.z) * (1.0 - cos(u * PI * 0.5))
			row.append(Vector3(x, y, LENGTH * (0.5 - t)))
		pts.append(row)
	for side in [-1.0, 1.0]:
		for i in nt:
			for j in nu:
				var a: Vector3 = pts[i][j]
				var b: Vector3 = pts[i + 1][j]
				var c: Vector3 = pts[i + 1][j + 1]
				var d: Vector3 = pts[i][j + 1]
				a.x *= side; b.x *= side; c.x *= side; d.x *= side
				var ua := Vector2(float(j) / nu, float(i) / nt)
				var ub := Vector2(float(j) / nu, float(i + 1) / nt)
				var uc := Vector2(float(j + 1) / nu, float(i + 1) / nt)
				var ud := Vector2(float(j + 1) / nu, float(i) / nt)
				var tri := [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]
				if side < 0.0:
					tri = [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]
				for v in tri:
					st.set_uv(v[1])
					st.add_vertex(v[0])
	# the transom: a flat board across the stern
	var row0: Array = pts[0]
	for j in nu:
		var p0: Vector3 = row0[j]
		var p1: Vector3 = row0[j + 1]
		for v in [[Vector3(-p0.x, p0.y, p0.z), Vector2(0.98, 0.0)], [Vector3(p0.x, p0.y, p0.z), Vector2(0.98, 0.0)], [Vector3(p1.x, p1.y, p1.z), Vector2(0.99, 0.0)],
				[Vector3(-p0.x, p0.y, p0.z), Vector2(0.98, 0.0)], [Vector3(p1.x, p1.y, p1.z), Vector2(0.99, 0.0)], [Vector3(-p1.x, p1.y, p1.z), Vector2(0.99, 0.0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	st.generate_normals()
	var m := st.commit()
	_cache["hull"] = m
	return m

## The deck: a plank floor just under the gunwale over the hull's outline.
static func deck_mesh() -> Mesh:
	if _cache.has("deck"):
		return _cache["deck"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nt := 30
	for i in nt:
		var t0 := float(i) / nt
		var t1 := float(i + 1) / nt
		var s0 := _sec(t0)
		var s1 := _sec(t1)
		var y0 := s0.y - 0.22
		var y1 := s1.y - 0.22
		var w0 := s0.x * 0.94
		var w1 := s1.x * 0.94
		var a := Vector3(-w0, y0, LENGTH * (0.5 - t0))
		var b := Vector3(w0, y0, LENGTH * (0.5 - t0))
		var c := Vector3(w1, y1, LENGTH * (0.5 - t1))
		var d := Vector3(-w1, y1, LENGTH * (0.5 - t1))
		for v in [[a, Vector2(0, t0)], [c, Vector2(1, t1)], [b, Vector2(1, t0)], [a, Vector2(0, t0)], [d, Vector2(0, t1)], [c, Vector2(1, t1)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var m := st.commit()
	_cache["deck"] = m
	return m

## A sail between four corners (tack, clew, peak, throat), bellied out by `belly`, UV for the cloth
## shader (UV.y up the sail, so its free leech ripples most).
static func sail_mesh(c: Array, belly: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var p: Vector3 = c[2]
	var q: Vector3 = c[3]
	var grid := []
	for i in n + 1:
		var row := []
		var v := float(i) / n
		for j in n + 1:
			var u := float(j) / n
			var bottom := a.lerp(b, u)
			var top := q.lerp(p, u)
			var pt := bottom.lerp(top, v)
			pt.x += belly * sin(u * PI) * sin(v * PI * 0.9 + 0.1)
			row.append(pt)
		grid.append(row)
	for i in n:
		for j in n:
			var v00: Vector3 = grid[i][j]
			var v10: Vector3 = grid[i][j + 1]
			var v11: Vector3 = grid[i + 1][j + 1]
			var v01: Vector3 = grid[i + 1][j]
			var u0 := float(j) / n
			var u1 := float(j + 1) / n
			var w0 := float(i) / n
			var w1 := float(i + 1) / n
			for vv in [[v00, Vector2(u0, w0)], [v10, Vector2(u1, w0)], [v11, Vector2(u1, w1)], [v00, Vector2(u0, w0)], [v11, Vector2(u1, w1)], [v01, Vector2(u0, w1)]]:
				st.set_uv(vv[1])
				st.add_vertex(vv[0])
	st.generate_normals()
	return st.commit()

static func hull_mat(paint: Color) -> ShaderMaterial:
	var key := "hullmat" + paint.to_html()
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = HULL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("paint", paint)
	_cache[key] = m
	return m

static func deck_mat() -> ShaderMaterial:
	if _cache.has("deckmat"):
		return _cache["deckmat"]
	var sh := Shader.new()
	sh.code = DECK_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["deckmat"] = m
	return m

## Clinker planks: overlapping strakes along the girth (each lap a dark line and a lighter edge), grain
## along the length, a painted band under the gunwale, black tar below the waterline, wear and salt.
const HULL_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 paint : source_color = vec3(0.16, 0.3, 0.42);
varying vec3 lp;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y); }
void vertex(){ lp = VERTEX; }
void fragment(){
	float strakes = 11.0;
	float s = UV.x * strakes;
	float id = floor(s);
	float f = fract(s);
	float lap = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.9, 1.0, f) * 0.6);
	float grain = vn(vec2(UV.y * 90.0 + id * 7.3, f * 3.0 + id)) * 0.5 + vn(vec2(UV.y * 260.0, f * 9.0 + id * 3.1)) * 0.25;
	vec3 wood = mix(vec3(0.33, 0.22, 0.13), vec3(0.45, 0.31, 0.18), h21(vec2(id, 3.0)));
	wood *= 0.78 + grain * 0.4;
	vec3 c = wood * mix(0.45, 1.0, lap);
	// the painted band under the gunwale, chipped
	float band = step(0.8, UV.x) * step(UV.x, 0.93);
	float chip = step(0.72, vn(vec2(UV.y * 40.0, UV.x * 30.0)));
	c = mix(c, paint * (0.8 + grain * 0.25) * mix(0.55, 1.0, lap), band * (1.0 - chip * 0.7));
	// tar below the waterline, a weedy green line at it, salt stains above
	float wl = smoothstep(0.08, -0.02, lp.y + (vn(vec2(UV.y * 20.0, 0.0)) - 0.5) * 0.04);
	c = mix(c, vec3(0.05, 0.045, 0.04) * (0.8 + grain * 0.3), wl);
	c = mix(c, vec3(0.12, 0.16, 0.08), (1.0 - smoothstep(0.0, 0.07, abs(lp.y - 0.05))) * 0.6);
	c = mix(c, vec3(0.62, 0.6, 0.55), smoothstep(0.6, 0.85, vn(vec2(UV.y * 12.0, UV.x * 6.0))) * smoothstep(0.1, 0.5, lp.y) * 0.18);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.45, wl);
}
"""

const DECK_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y); }
void fragment(){
	float s = UV.x * 12.0;
	float id = floor(s);
	float seam = smoothstep(0.0, 0.06, fract(s)) * smoothstep(1.0, 0.94, fract(s));
	float butt = step(0.97, fract(UV.y * 3.0 + h21(vec2(id, 1.0))));
	float grain = vn(vec2(UV.y * 120.0, fract(s) * 4.0 + id * 5.0));
	vec3 c = mix(vec3(0.42, 0.33, 0.22), vec3(0.52, 0.41, 0.28), h21(vec2(id, 7.0))) * (0.8 + grain * 0.3);
	c *= mix(0.35, 1.0, seam) * (1.0 - butt * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.88;
}
"""
