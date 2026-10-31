class_name Grass
extends RefCounted
## The living grass: 3D blades built in code, moved by the wind and parted by whoever walks through them.
##
## Species (`SPECIES`) are clumps of curved, tapered blades with their own height, width, curve,
## stiffness and colour range (plus seed heads, flowers, clover leaves or broad leaves for some); each
## is built at two levels of detail (LOD1: about half the blades, wider and with fewer segments) in two
## variants. Biomes (`BIOMES`) mix species with a density and a height; a zone answers three questions
## for any spot (the `ctx` object: `grass_ground(x, z)` 0..1, `grass_height(x, z)`, `grass_biome(x, z)`
## weights by biome) and the biome weights blend smoothly, so meadow fades into woodland undergrowth or a
## dry patch with no seams. Clumps go into MultiMesh chunks (`CHUNK` m); per instance custom data carries
## shade, extra dryness and a random value.
##
## The shader (`SHADER`) bends every blade from its root by the wind (gust fronts rolling along
## `wind_dir`, a sway per clump with its own phase, flutter at the tips; stiff species move less) plus
## the touch field (GrassField). Far away it thins smoothly (instances shrink away by their random value,
## no popping) and LOD0/LOD1 cross-fade per instance in a band. Light passes through the blades, normals
## are rounded across each blade, roots are shaded, and dry patches drift across the field.
##
## Add a species: an entry in SPECIES (and in some biome's "mix"). Add a biome: an entry in BIOMES and a
## weight for it from the zone's `grass_biome`.

const CHUNK := 20.0
## clumps per square metre at density 1 on the High preset; presets scale it
const BASE_DENSITY := 7.0
const QUALITY_DENSITY := [0.4, 0.65, 1.0, 1.35]
## camera distances: LOD0 -> LOD1 cross-fade band, and the far thinning (start, end), per preset
const LOD_BAND := [Vector2(24, 28), Vector2(27, 31), Vector2(30, 35), Vector2(34, 40)]
const FADE := [Vector2(28, 40), Vector2(36, 50), Vector2(44, 60), Vector2(55, 76)]
## Act I's grass colours, matched to the painted clumps the moor had before (their roots, middles and
## tips, a little darker since these blades are lit by the scene and the paintings had light baked in)
const ACT1 := {"base_col": Color(0.15, 0.2, 0.1), "tip_col": Color(0.41, 0.46, 0.27), "dry_col": Color(0.5, 0.45, 0.3), "wind": 1.0}
## the tallest grass stays below a character's hip at the game's camera
const MAX_HEIGHT := 0.75

## Species. h/w/curve/flex/dry are [min, max]; "radius" is the clump's footprint; "segs" blade segments at
## LOD0. Optional: "heads" (seed-head stems), "flowers" (chance per clump), "clover" (leaf trios),
## "lush" (darker, bluer green), "dry_chance" (share of blades dead/straw), "broken" (snapped tips).
const SPECIES := {
	"meadow": {"blades": 26, "skirt": 18, "radius": 0.28, "h": [0.2, 0.4], "w": [0.02, 0.032], "curve": [0.25, 0.6], "segs": 3,
		"flex": [0.7, 1.0], "dry": [0.0, 0.15], "dry_chance": 0.08, "flowers": 0.22},
	"tall": {"blades": 14, "skirt": 8, "radius": 0.2, "h": [0.42, 0.68], "w": [0.016, 0.026], "curve": [0.25, 0.6], "segs": 4,
		"flex": [0.85, 1.0], "dry": [0.15, 0.4], "heads": 4},
	"tussock": {"blades": 34, "skirt": 10, "radius": 0.12, "h": [0.26, 0.48], "w": [0.014, 0.022], "curve": [0.5, 0.95], "segs": 3,
		"flex": [0.5, 0.75], "dry": [0.1, 0.3], "dry_chance": 0.3},
	"dry": {"blades": 22, "skirt": 12, "radius": 0.24, "h": [0.22, 0.44], "w": [0.016, 0.026], "curve": [0.15, 0.45], "segs": 3,
		"flex": [0.35, 0.6], "dry": [0.75, 1.0], "broken": 0.2},
	"moss": {"blades": 34, "radius": 0.26, "h": [0.03, 0.07], "w": [0.012, 0.02], "curve": [0.2, 0.5], "segs": 2,
		"flex": [0.1, 0.25], "dry": [0.0, 0.08], "lush": 1.0, "clover": 6},
	"weed": {"blades": 7, "radius": 0.08, "h": [0.15, 0.28], "w": [0.05, 0.08], "curve": [0.55, 0.9], "segs": 3,
		"flex": [0.4, 0.6], "dry": [0.0, 0.1], "lush": 0.8},
	"sparse": {"blades": 12, "skirt": 6, "radius": 0.18, "h": [0.1, 0.22], "w": [0.016, 0.024], "curve": [0.15, 0.5], "segs": 2,
		"flex": [0.5, 0.8], "dry": [0.1, 0.45]},
}

## Biomes: density (x BASE_DENSITY), species mix, height scale, shade (darker under trees), dryness.
const BIOMES := {
	"meadow": {"density": 1.15, "height": 1.0, "shade": 0.0, "dry": 0.0,
		"mix": {"meadow": 0.5, "tall": 0.14, "tussock": 0.14, "sparse": 0.07, "dry": 0.06, "weed": 0.05, "moss": 0.04}},
	"woodland": {"density": 0.85, "height": 0.9, "shade": 0.45, "dry": 0.0,
		"mix": {"moss": 0.32, "weed": 0.2, "meadow": 0.28, "sparse": 0.15, "tall": 0.05}},
	"dry": {"density": 0.75, "height": 0.95, "shade": 0.0, "dry": 0.45,
		"mix": {"dry": 0.55, "sparse": 0.2, "tussock": 0.2, "weed": 0.05}},
	"verge": {"density": 0.55, "height": 0.7, "shade": 0.0, "dry": 0.15,
		"mix": {"sparse": 0.55, "meadow": 0.25, "dry": 0.12, "weed": 0.08}},
	"trampled": {"density": 0.75, "height": 0.7, "shade": 0.1, "dry": 0.1,
		"mix": {"sparse": 0.45, "meadow": 0.35, "moss": 0.15, "weed": 0.05}},
	"ruins": {"density": 0.9, "height": 1.05, "shade": 0.15, "dry": 0.1,
		"mix": {"weed": 0.3, "tall": 0.2, "meadow": 0.25, "moss": 0.15, "dry": 0.1}},
}

const VARIANTS := 2

static var _meshes := {}
static var _shader: Shader = null
static var _mats := {}
static var quality := 2

# ---------------------------------------------------------------- placement
## Covers `area` (x/z rect) with grass for the zone `ctx`. `colors` are the zone's grass colours
## (base_col, tip_col, dry_col); `q` the graphics preset. Adds MultiMeshInstance3D chunks under `parent`
## (group "grass", meta "grass3d") and returns how many clumps went in.
static func scatter(parent: Node3D, area: Rect2, ctx: Object, colors: Dictionary, q: int, seed_v: int, shadows := true) -> int:
	quality = clampi(q, 0, 3)
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var clump_n := FastNoiseLite.new()
	clump_n.seed = seed_v + 11
	clump_n.frequency = 0.11
	clump_n.fractal_octaves = 2
	var dens := BASE_DENSITY * float(QUALITY_DENSITY[quality])
	# per chunk, species, variant ("cx,cz,species,variant"): 16 floats per instance (3x4 transform + custom)
	var buckets := {}
	var count := 0
	var cell := 1.0
	var nx := int(ceil(area.size.x / cell))
	var nz := int(ceil(area.size.y / cell))
	var keys: Array = SPECIES.keys()
	for j in nz:
		for i in nx:
			var cx := area.position.x + (i + rng.randf()) * cell
			var cz := area.position.y + (j + rng.randf()) * cell
			var g: float = ctx.grass_ground(cx, cz)
			if g <= 0.02:
				continue
			var bw: Dictionary = ctx.grass_biome(cx, cz)
			# blend the biomes: density, height, shade, dryness and the species mix
			var d := 0.0
			var hs := 0.0
			var shade := 0.0
			var dry := 0.0
			var mix := {}
			var wsum := 0.0
			for b in bw.keys():
				var w := float(bw[b])
				if w <= 0.0 or not BIOMES.has(b):
					continue
				var bd: Dictionary = BIOMES[b]
				wsum += w
				d += float(bd["density"]) * w
				hs += float(bd["height"]) * w
				shade += float(bd["shade"]) * w
				dry += float(bd["dry"]) * w
				var bm: Dictionary = bd["mix"]
				for s in bm.keys():
					mix[s] = float(mix.get(s, 0.0)) + float(bm[s]) * w
			if wsum <= 0.0:
				continue
			d /= wsum
			hs /= wsum
			shade /= wsum
			dry /= wsum
			# clumpy, irregular cover: denser drifts and thinner gaps, never a grid
			var cn := clump_n.get_noise_2d(cx, cz)
			var local := dens * d * g * clampf(0.9 + cn * 0.5, 0.5, 1.3)
			var n := int(local)
			if rng.randf() < local - n:
				n += 1
			var gy: float = ctx.grass_height(cx, cz)
			for k in n:
				var x := cx + rng.randf_range(-0.6, 0.6)
				var z := cz + rng.randf_range(-0.6, 0.6)
				var sp := _pick(mix, rng, keys)
				var v := rng.randi() % VARIANTS
				var s := rng.randf_range(0.75, 1.25)
				var sh := s * hs * rng.randf_range(0.85, 1.15)
				var spec: Dictionary = SPECIES[sp]
				var top: float = float(spec["h"][1]) * sh
				if top > MAX_HEIGHT:
					sh *= MAX_HEIGHT / top
				var yaw := rng.randf() * TAU
				var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, sh, s))
				var key := "%d,%d,%s,%d" % [int(floor(x / CHUNK)), int(floor(z / CHUNK)), sp, v]
				if not buckets.has(key):
					buckets[key] = []
				var arr: Array = buckets[key]
				var y := gy - 0.02
				arr.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, z,
					clampf(shade + rng.randf_range(-0.08, 0.08), 0.0, 1.0), clampf(dry + rng.randf_range(-0.1, 0.1), 0.0, 1.0), rng.randf(), 0.0])
				count += 1
	var mat := material(colors)
	var lod: Vector2 = LOD_BAND[quality]
	var fade: Vector2 = FADE[quality]
	var half := CHUNK * 0.75
	for key in buckets.keys():
		var arr := PackedFloat32Array(buckets[key])
		var parts: PackedStringArray = String(key).split(",")
		for l in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh(parts[2], int(parts[3]), l)
			mm.instance_count = arr.size() / 16
			mm.buffer = arr
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat[l]
			mmi.position = Vector3.ZERO
			# shadows only from the near, detailed grass, and only on Ultra (as before): grass shading grass on
			# lower presets darkens the field more than it grounds it, and costs a second pass
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and l == 0 and quality >= 3) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_set_ranges(mmi, l, lod, fade, half)
			mmi.set_meta("grass3d", l)
			mmi.add_to_group("grass")
			mmi.name = "Grass_%s_%s_%s%s_L%d" % [parts[0], parts[1], parts[2], parts[3], l]
			parent.add_child(mmi)
	print("Grass: %d clumps in %d chunks (preset %d) in %d ms" % [count, buckets.size(), quality, Time.get_ticks_msec() - t0])
	return count

static func _set_ranges(mmi: GeometryInstance3D, l: int, lod: Vector2, fade: Vector2, half: float) -> void:
	# whole chunks drop out only where the shader has already thinned or swapped every clump in them
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if l == 0:
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_end = lod.y + half
	else:
		mmi.visibility_range_begin = maxf(0.0, lod.x - half)
		mmi.visibility_range_end = fade.y + half
	mmi.visibility_range_end_margin = 2.0
	mmi.visibility_range_begin_margin = 2.0

## A new preset's distances for grass already in the world (density changes on the next zone load).
static func apply_quality(root: Node, q: int) -> void:
	quality = clampi(q, 0, 3)
	var lod: Vector2 = LOD_BAND[quality]
	var fade: Vector2 = FADE[quality]
	for m in _mats.values():
		for l in 2:
			(m[l] as ShaderMaterial).set_shader_parameter("lod_band", lod)
			(m[l] as ShaderMaterial).set_shader_parameter("fade", fade)
	for g in root.get_tree().get_nodes_in_group("grass"):
		if g.has_meta("grass3d"):
			var l := int(g.get_meta("grass3d"))
			_set_ranges(g as GeometryInstance3D, l, lod, fade, CHUNK * 0.75)
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (l == 0 and quality >= 3) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _pick(mix: Dictionary, rng: RandomNumberGenerator, keys: Array) -> String:
	var total := 0.0
	for s in mix.keys():
		total += float(mix[s])
	var r := rng.randf() * total
	for s in mix.keys():
		r -= float(mix[s])
		if r <= 0.0:
			return String(s)
	return String(keys[0])

# ---------------------------------------------------------------- materials
## The two materials (LOD0, LOD1) for a zone's grass colours.
static func material(colors: Dictionary) -> Array:
	var base: Color = colors.get("base_col", Color(0.12, 0.16, 0.06))
	var tip: Color = colors.get("tip_col", Color(0.27, 0.32, 0.13))
	var dryc: Color = colors.get("dry_col", Color(0.36, 0.35, 0.18))
	var key := "%s|%s|%s|%d" % [base.to_html(), tip.to_html(), dryc.to_html(), quality]
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var out := []
	for l in 2:
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("base_col", base)
		m.set_shader_parameter("tip_col", tip)
		m.set_shader_parameter("dry_col", dryc)
		m.set_shader_parameter("lod_side", float(l))
		m.set_shader_parameter("lod_band", LOD_BAND[quality])
		m.set_shader_parameter("fade", FADE[quality])
		m.set_shader_parameter("wind_mult", float(colors.get("wind", 1.0)))
		out.append(m)
	_mats[key] = out
	return out

# ---------------------------------------------------------------- meshes
## One species clump at LOD `l` (0 full, 1 about half the blades, wider, fewer segments), variant `v`.
static func mesh(sp: String, v: int, l: int) -> ArrayMesh:
	var key := "%s_%d_%d" % [sp, v, l]
	if _meshes.has(key):
		return _meshes[key]
	var spec: Dictionary = SPECIES[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sp) + v * 7919
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := int(spec["blades"])
	var segs := int(spec["segs"])
	if l == 1:
		segs = maxi(1, segs - 1)
	var lush := float(spec.get("lush", 0.0))
	for i in blades:
		# every blade's numbers are drawn at both LODs, so LOD1 is a subset of the same clump
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * float(spec["radius"])
		var root := Vector3(cos(a) * rr, 0, sin(a) * rr)
		var h := rng.randf_range(spec["h"][0], spec["h"][1])
		var w := rng.randf_range(spec["w"][0], spec["w"][1])
		var curve := rng.randf_range(spec["curve"][0], spec["curve"][1])
		var flex := rng.randf_range(spec["flex"][0], spec["flex"][1])
		var dry := rng.randf_range(spec["dry"][0], spec["dry"][1])
		if rng.randf() < float(spec.get("dry_chance", 0.0)):
			dry = rng.randf_range(0.7, 1.0)
		var bright := rng.randf_range(0.35, 0.65)
		var face := rng.randf() * TAU
		# blades lean out from the clump's heart, with some scatter
		var out := Vector3(root.x, 0, root.z).normalized() if rr > 0.01 else Vector3(cos(face), 0, sin(face))
		var lean := (out + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))).normalized()
		var twist := rng.randf_range(-0.8, 0.8)
		var phase := rng.randf()
		var broken := rng.randf() < float(spec.get("broken", 0.0))
		var kr := rng.randf()
		if l == 1 and kr >= 0.55:
			continue
		var ww := w * (1.6 if l == 1 else 1.0)
		if broken:
			h *= 0.65
		_blade(st, root, face, lean, h, ww, curve, segs, flex, phase, dry, bright, lush, twist, not broken)
	# a skirt of short blades lying out low round the clump: cheap (one triangle each), it covers the soil
	# between clumps the way real undergrowth does
	if spec.has("skirt"):
		for i in int(spec["skirt"]):
			var a := rng.randf() * TAU
			var rr := lerpf(0.4, 1.7, sqrt(rng.randf())) * float(spec["radius"])
			var root := Vector3(cos(a) * rr, 0, sin(a) * rr)
			var lean := (Vector3(cos(a), 0, sin(a)) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))).normalized()
			var h := rng.randf_range(0.05, 0.12)
			var dry := rng.randf_range(spec["dry"][0], spec["dry"][1]) * 0.5
			var kr := rng.randf()
			if l == 1 and kr >= 0.5:
				continue
			_blade(st, root, rng.randf() * TAU, lean, h, rng.randf_range(0.03, 0.045), rng.randf_range(0.9, 1.3), 1,
				rng.randf_range(0.2, 0.4), rng.randf(), dry, rng.randf_range(0.3, 0.55), 0.3, 0.0, true)
	if spec.has("heads"):
		for i in int(spec["heads"]):
			var a := rng.randf() * TAU
			var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, float(spec["radius"]) * 0.6)
			var h := float(spec["h"][1]) * rng.randf_range(0.95, 1.15)
			var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var curve := rng.randf_range(0.1, 0.35)
			var phase := rng.randf()
			var head := Color(rng.randf_range(0.5, 0.62), rng.randf_range(0.44, 0.52), rng.randf_range(0.28, 0.34), 0.5)
			if l == 1 and i % 2 == 1:
				continue
			_seed_head(st, root, lean, h, curve, phase, head, l)
	if spec.has("clover"):
		for i in int(spec["clover"]):
			var a := rng.randf() * TAU
			var c := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.03, float(spec["radius"]))
			var hh := rng.randf_range(0.03, 0.08)
			if l == 1 and i % 2 == 1:
				continue
			_clover(st, c, hh, rng)
	if l == 0 and spec.has("flowers") and v == 0:
		# variant 0 of a flowering species carries a couple of small moorland flowers
		var fcols := [Color(0.92, 0.9, 0.82), Color(0.95, 0.82, 0.3), Color(0.62, 0.42, 0.7), Color(0.85, 0.85, 0.95)]
		for i in 2:
			var a := rng.randf() * TAU
			var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.03, 0.14)
			var top := base + Vector3(rng.randf_range(-0.04, 0.04), float(spec["h"][1]) * rng.randf_range(0.9, 1.2), rng.randf_range(-0.04, 0.04))
			var fc: Color = fcols[(hash(sp) + i * 3 + v) % fcols.size()]
			_flower(st, base, top, fc, rng.randf_range(0.022, 0.032), rng.randf())
	var m := st.commit()
	_meshes[key] = m
	return m

## One blade: a curved, tapered strip of `segs` segments ending in a point (or a ragged snapped end),
## its normals rounded across the blade so it shades like a fold rather than a flat card.
## UV.y = height along the blade (0 root .. 1 tip), UV2 = (flexibility, phase);
## COLOR = (dryness, brightness, lushness, 1 = blade).
static func _blade(st: SurfaceTool, root: Vector3, face: float, lean: Vector3, h: float, w: float, curve: float, segs: int,
		flex: float, phase: float, dry: float, bright: float, lush: float, twist: float, pointed: bool) -> void:
	var rows: Array = []
	for s in segs + 1:
		var t := float(s) / segs
		var p := root + lean * curve * h * t * t + Vector3.UP * h * t * (1.0 - 0.3 * curve * curve * t * t)
		var tw := face + twist * t
		var side := Vector3(cos(tw), 0, sin(tw))
		# widest a little above the root, tapering to the tip
		var wt := w * (lerpf(0.7, 1.0, t / 0.15) if t < 0.15 else 1.0 - pow((t - 0.15) / 0.85, 1.5) * (0.95 if pointed else 0.55))
		var tan := (lean * curve * 2.0 * t + Vector3.UP * (1.0 - 0.9 * curve * curve * t * t)).normalized()
		var n0 := side.cross(tan).normalized()
		rows.append([p, side, wt, n0, t])
	var col := Color(dry, bright, lush, 1.0)
	for s in segs:
		var r0: Array = rows[s]
		var r1: Array = rows[s + 1]
		var last := s == segs - 1 and pointed
		var l0: Vector3 = r0[0] - r0[1] * r0[2] * 0.5
		var q0: Vector3 = r0[0] + r0[1] * r0[2] * 0.5
		var l1: Vector3 = r1[0] - r1[1] * r1[2] * 0.5
		var q1: Vector3 = r1[0] + r1[1] * r1[2] * 0.5
		var nl0: Vector3 = ((r0[3] as Vector3) * 0.8 - (r0[1] as Vector3) * 0.6).normalized()
		var nr0: Vector3 = ((r0[3] as Vector3) * 0.8 + (r0[1] as Vector3) * 0.6).normalized()
		var nl1: Vector3 = ((r1[3] as Vector3) * 0.8 - (r1[1] as Vector3) * 0.6).normalized()
		var nr1: Vector3 = ((r1[3] as Vector3) * 0.8 + (r1[1] as Vector3) * 0.6).normalized()
		var t0: float = r0[4]
		var t1: float = r1[4]
		if last:
			var tip: Vector3 = r1[0]
			_v(st, l0, nl0, Vector2(0, t0), flex, phase, col)
			_v(st, q0, nr0, Vector2(1, t0), flex, phase, col)
			_v(st, tip, r1[3], Vector2(0.5, t1), flex, phase, col)
		else:
			_v(st, l0, nl0, Vector2(0, t0), flex, phase, col)
			_v(st, q0, nr0, Vector2(1, t0), flex, phase, col)
			_v(st, q1, nr1, Vector2(1, t1), flex, phase, col)
			_v(st, l0, nl0, Vector2(0, t0), flex, phase, col)
			_v(st, q1, nr1, Vector2(1, t1), flex, phase, col)
			_v(st, l1, nl1, Vector2(0, t1), flex, phase, col)

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, flex: float, phase: float, col: Color) -> void:
	st.set_color(col)
	st.set_uv(uv)
	st.set_uv2(Vector2(flex, phase))
	st.set_normal(n)
	st.add_vertex(p)

## A tall stem with a spindle of seeds at the top (two crossed strips), the colour as given.
static func _seed_head(st: SurfaceTool, root: Vector3, lean: Vector3, h: float, curve: float, phase: float, col: Color, l: int) -> void:
	var face := atan2(lean.z, lean.x) + PI * 0.5
	_blade(st, root, face, lean, h * 0.82, 0.005 if l == 0 else 0.008, curve, 3 if l == 0 else 2, 1.0, phase, 0.55, 0.45, 0.0, 0.0, false)
	var t0 := 0.82
	var p0 := root + lean * curve * h * t0 * t0 + Vector3.UP * h * t0
	var dir := (lean * curve * 2.0 * t0 * 0.6 + Vector3.UP).normalized()
	var p1 := p0 + dir * h * 0.2
	for k in (2 if l == 0 else 1):
		var side := Vector3(cos(face + k * PI * 0.5), 0, sin(face + k * PI * 0.5)) * 0.009
		var mid := p0.lerp(p1, 0.4)
		var n := side.cross(dir).normalized()
		for q in [[p0, Vector2(0.5, 0.82)], [mid - side, Vector2(0, 0.9)], [p1, Vector2(0.5, 1.0)], [p0, Vector2(0.5, 0.82)], [p1, Vector2(0.5, 1.0)], [mid + side, Vector2(1, 0.9)]]:
			_v(st, q[0], n, q[1], 1.0, phase, col)

## Three round leaflets just above the ground (clover in the moss).
static func _clover(st: SurfaceTool, c: Vector3, hh: float, rng: RandomNumberGenerator) -> void:
	var a0 := rng.randf() * TAU
	var col := Color(0.0, rng.randf_range(0.4, 0.6), 0.9, 1.0)
	var phase := rng.randf()
	for k in 3:
		var a := a0 + k * TAU / 3.0
		var d := Vector3(cos(a), 0.25, sin(a)).normalized()
		var s := Vector3(-sin(a), 0, cos(a))
		var r := 0.022
		var b := c + Vector3(0, hh, 0)
		var m := b + d * r
		var tip := b + d * r * 1.9
		for q in [[b, 0.0], [m - s * r * 0.8, 0.5], [tip, 1.0], [b, 0.0], [tip, 1.0], [m + s * r * 0.8, 0.5]]:
			_v(st, q[0], Vector3.UP, Vector2(0.5, 0.6 + 0.4 * float(q[1])), 0.15, phase, col)

## A thin stem with a five-petalled head, the petals in the colour as given (alpha 0 = as-is).
static func _flower(st: SurfaceTool, base: Vector3, top: Vector3, fc: Color, pr: float, phase: float) -> void:
	var stem := Vector3(0.0035, 0, 0)
	var sc := Color(0.1, 0.5, 0.3, 1.0)
	for q in [[base - stem, 0.0], [base + stem, 0.0], [top + stem, 1.0], [base - stem, 0.0], [top + stem, 1.0], [top - stem, 1.0]]:
		_v(st, q[0], Vector3(0, 0, 1), Vector2(0.5, q[1]), 0.9, phase, sc)
	var pc := Color(fc.r, fc.g, fc.b, 0.0)
	for k in 5:
		var a0 := TAU * k / 5.0
		var a1 := TAU * (k + 0.5) / 5.0
		var a2 := TAU * (k + 1) / 5.0
		var tip := top + Vector3(cos(a1), 0.25, sin(a1)) * pr
		for p in [top + Vector3(0, 0.006, 0), top + Vector3(cos(a0), 0.15, sin(a0)) * pr * 0.55, tip, top + Vector3(0, 0.006, 0), tip, top + Vector3(cos(a2), 0.15, sin(a2)) * pr * 0.55]:
			_v(st, p, Vector3.UP, Vector2(0.5, 1.0), 0.9, phase, pc)

# ---------------------------------------------------------------- shader
const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
uniform vec3 base_col : source_color = vec3(0.12, 0.16, 0.06);
uniform vec3 tip_col : source_color = vec3(0.27, 0.32, 0.13);
uniform vec3 dry_col : source_color = vec3(0.36, 0.35, 0.18);
uniform float wind_mult = 1.0;
uniform float lod_side = 0.0;
uniform vec2 lod_band = vec2(30.0, 35.0);
uniform vec2 fade = vec2(44.0, 60.0);
uniform bool debug_touch = false;
global uniform sampler2D grass_field : filter_linear, repeat_disable;
global uniform vec4 grass_field_rect;
global uniform vec3 grass_cam;
global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_gust;
global uniform float wind_phase;
global uniform float snow_amt;
global uniform float ash_amt;
varying float hgt;
varying vec4 vc;
varying float gust;
varying float shade;
varying float dryx;
varying float rnd;
varying vec3 wpos;
varying float press;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){
	hgt = UV.y;
	vc = COLOR;
	vec3 o = MODEL_MATRIX[3].xyz;
	shade = INSTANCE_CUSTOM.x;
	dryx = INSTANCE_CUSTOM.y;
	rnd = INSTANCE_CUSTOM.z;
	float flex = UV2.x;
	float ph = UV2.y;
	// distance from the game camera (a global, so the shadow pass agrees): far clumps shrink away by
	// their random value, and LOD0/LOD1 hand each clump over at its own distance inside the band
	float dist = length(grass_cam - o);
	float keep = 1.0 - smoothstep(fade.x, fade.y, dist);
	float scl = clamp((keep - rnd) * 6.0 + 0.15, 0.0, 1.0);
	if (keep >= 0.999) { scl = 1.0; }
	float x = smoothstep(lod_band.x, lod_band.y, dist);
	float r2 = fract(rnd * 7.13 + 0.37);
	float mine = lod_side < 0.5 ? step(x, r2) : step(r2, x - 0.0001);
	scl *= mine;
	vec3 rel = VERTEX - o;
	rel *= scl;
	float h = max(rel.y, 0.0);
	// ---- wind: gust fronts rolling along the wind, a sway per clump, flutter at the tips
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	vec2 wp = vec2(dot(o.xz, wd), dot(o.xz, vec2(-wd.y, wd.x)));
	gust = vn(vec2(wp.x - wind_phase, wp.y * 0.35) * 0.09) * 0.65 + vn(vec2(wp.x - wind_phase * 1.3, wp.y) * 0.31) * 0.35;
	float ws = wind_strength * wind_mult * (1.0 - snow_amt * 0.5);
	float g = smoothstep(0.35, 0.85, gust);
	vec2 bend = wd * ws * (0.12 + g * 0.75 * wind_gust) * flex;
	float sw = sin(TIME * (1.6 + rnd * 0.8) + ph * 6.28 + wp.x * 0.45) * (0.05 + 0.1 * ws) * flex;
	bend += vec2(-wd.y, wd.x) * sw * 0.6 + wd * sw * 0.5;
	float flick = sin(TIME * 7.0 + ph * 40.0 + o.x * 3.0) * 0.035 * ws * flex * hgt;
	bend += vec2(flick, -flick * 0.6);
	// ---- touch: the field's bend under this part of the clump (per vertex, so the blades nearest a leg
	// bend most and the clump parts instead of leaning as one)
	vec2 fuv = (o.xz + rel.xz * (1.0 - hgt * 0.5) - grass_field_rect.xy) / grass_field_rect.z;
	vec2 touch = vec2(0.0);
	if (grass_field_rect.w > 0.0 && fuv.x > 0.0 && fuv.y > 0.0 && fuv.x < 1.0 && fuv.y < 1.0) {
		vec4 f = textureLod(grass_field, fuv, 0.0);
		float edge = smoothstep(0.0, 0.06, min(min(fuv.x, fuv.y), min(1.0 - fuv.x, 1.0 - fuv.y)));
		touch = (f.rg * 2.0 - 1.0) * grass_field_rect.w * edge * (0.65 + 0.35 * flex);
	}
	press = length(touch);
	bend *= 1.0 - clamp(press * 1.2, 0.0, 0.8);
	bend += touch * 1.4;
	float bl = length(bend);
	if (bl > 1.4) { bend *= 1.4 / bl; bl = 1.4; }
	// ---- bend each vertex about the root, keeping the blade's length (the tip swings down as it leans)
	float k = hgt;
	rel.xz += bend * h * k * 1.1;
	rel.y -= h * (bl * bl) * 0.42 * k;
	rel.y -= snow_amt * 0.16;
	rel.y *= 1.0 - ash_amt * 0.4;
	VERTEX = o + rel;
	// lean the normals with the bend, and toward the sky so the field shades as one soft surface
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.7) + vec3(bend.x, 0.0, bend.y) * 0.35);
	wpos = VERTEX;
}
void fragment(){
	if (snow_amt > 0.0 && hgt < snow_amt * 0.5) { discard; }
	// both faces of a blade share its sky-leaning normal: the engine flips it for the back face, which
	// would point it at the ground and leave every other blade dark
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 c;
	if (vc.a < 0.75) {
		// petals and seed heads keep their own colour
		if (vc.a < 0.25 && (snow_amt > 0.5 || ash_amt > 0.5)) { discard; }
		c = vc.rgb * (0.85 + rnd * 0.25);
		ROUGHNESS = 0.7;
		SPECULAR = 0.2;
		BACKLIGHT = c * 0.45;
	} else {
		float patch = vn(wpos.xz * 0.09 + 3.1) * 0.7 + vn(wpos.xz * 0.7) * 0.3;
		float d = clamp(vc.r + dryx * 0.8 + smoothstep(0.62, 0.9, patch) * 0.2, 0.0, 1.0);
		vec3 green = mix(base_col, tip_col, smoothstep(0.0, 0.95, hgt));
		// lush species are darker and bluer
		green = mix(green, green * vec3(0.72, 0.9, 0.85), vc.b * 0.7);
		vec3 straw = mix(dry_col * 0.65, dry_col * 1.0, hgt);
		straw = mix(straw, vec3(dot(straw, vec3(0.3, 0.5, 0.2))), 0.25);
		c = mix(green, straw, d);
		c *= 0.8 + vc.g * 0.4;
		c *= 0.9 + rnd * 0.18;
		// roots in the clump's shade, shade under trees, sun catching the gusts
		c *= mix(0.6, 1.0, smoothstep(0.0, 0.45, hgt));
		c *= 1.0 - shade * 0.42;
		c *= 1.0 + (gust - 0.5) * 0.14 * hgt;
		// grass pressed flat shows its paler underside
		c = mix(c, c * vec3(1.12, 1.1, 0.95), clamp(press, 0.0, 1.0) * 0.35 * hgt);
		if (ash_amt > 0.0) {
			c = mix(c, mix(vec3(0.06, 0.05, 0.04), vec3(0.3, 0.27, 0.23), hgt), ash_amt * 0.92);
		}
		if (snow_amt > 0.0) {
			c = mix(c, vec3(0.42, 0.38, 0.26), snow_amt * 0.6);
			c = mix(c, vec3(0.86, 0.9, 0.96), snow_amt * smoothstep(0.75, 1.0, hgt) * 0.75);
		}
		// a touch less saturated in the light: real grass greys toward the sky's colour where it shines
		c = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), 0.18);
		ROUGHNESS = mix(0.7, 0.88, d);
		SPECULAR = mix(0.2, 0.1, d);
		// thin blades let the low sun through, most at the tips
		BACKLIGHT = c * mix(0.2, 0.55, hgt) * (1.0 - d * 0.4);
	}
	if (debug_touch) { c = mix(c, vec3(1.0, 0.0, 0.0), clamp(press * 2.0, 0.0, 1.0)); }
	ALBEDO = c;
	AO = mix(0.55, 1.0, smoothstep(0.0, 0.6, hgt));
	AO_LIGHT_AFFECT = 0.55;
}
"""
