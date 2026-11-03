class_name CryptProps
extends RefCounted
## The crypt's set pieces: Meshy props re-baked onto clean UVs by tools/blender/battlegrounds/rebake_crypt_prop.py
## into assets/models/crypt/ (sarcophagus, pillar, archway, bones, sconce, brazier, niche; concepts and raw models in
## the Battlegrounds plan), the knight statue carved in crypt stone, and the Hollow Crypt's walls. World's shared
## crypt helpers (_pillar, _sarcophagus, _bones, _wall_torch) draw these when the files are there and keep their
## code-built props otherwise, so A3's crypt gets them too. Nothing here changes a footprint or draws on World.rng:
## the dedicated server builds the same layout from the same rolls, and every module below sits inside the rock
## cells, flush with the wall or protruding less than a hero's radius (World.BODY_R), where a hero can never stand.
##
## Battlegrounds only: `walls` turns some of World.crypt_shell's wall blocks (the transforms it rolled; given back
## minus the cells used) into ossuary niches, tomb alcoves with sarcophagi, statue alcoves and braziers in the hall;
## `wall_meshes` draws the rest in tiles under `wall_material`, the textured crypt stone
## (tools/blender/battlegrounds/make_tile_textures.py), and `lay_floor` the flagstones; `chest` and `candles` are the
## raid's chests and floor candles (World._chest, World._candles, on their old footprints and rolls); `torch_light`
## makes a wall torch light the floor; `portal_glow` is the Extraction Portal's light inside its rune archway
## (`archway`); `dress` adds the rubble, cobwebs, the dust in the air and the hall's floor seal (no collision, own RNG).

const DIR := "res://assets/models/crypt/"
const TEX := "res://assets/textures/crypt/"
const STATUE := "res://assets/models/knight_statue.glb"
const RUNE := Color(0.3, 0.55, 1.0)          # the Extraction Portals' cold light (Fx.portal_model's blue)
const WALL_SEED := 90210                      # the modules' own RNG (never World.rng)
const PILLAR_H := 4.0                         # pillar.glb as prepared (--xy 0.6: slim enough for the 0.55 m circle)
const SARC_LEN := 2.3                         # sarcophagus.glb: long along its x, 1.12 wide, 1.37 tall
const NICHE_H := 1.96                         # niche.glb: 1 m wide, 0.67 deep
const NICHE_D := 0.67
const SCONCE_CUP := Vector3(0.0, 0.46, 0.06)  # where the torch flame stands in sconce.glb (its own frame)
const BRAZIER_TOP := 0.5
const TORCH_ENERGY := 2.4                     # the Hollow Crypt's wall torches (torch_light)
const TORCH_RANGE := 8.5
const PILLAR_SKIN := 0.31                     # pillar.glb's shaft: 0.30 m from its axis to each flat face
const TILE := 12.0                            # floor and wall meshes are cut into tiles this size (lights per mesh)
const CANDLE_WICKS := [Vector3(-0.2638, 0.271, -0.0086), Vector3(-0.1733, 0.2579, -0.0072), Vector3(-0.0988, 0.2816, -0.0115),
	Vector3(-0.0542, 0.2228, 0.0349), Vector3(-0.0033, 0.3058, -0.0115), Vector3(0.0543, 0.2242, 0.0351),
	Vector3(0.0991, 0.2933, -0.0109), Vector3(0.1736, 0.2645, -0.0106), Vector3(0.2563, 0.2685, -0.0101)]

static var _cache := {}

static func has(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".glb")

## A fresh instance of a prepared model, or null without the file.
static func model(name: String) -> Node3D:
	if not has(name):
		return null
	return (load(DIR + name + ".glb") as PackedScene).instantiate()

## The model's bounds in its own frame (it isn't in the tree yet, so the transforms are walked by hand).
static func bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

static func _no_shadow(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------- the pieces World's crypt helpers use
## A pillar `h` metres tall: the Meshy pillar scaled to the height, no wider than as prepared (its base fits the
## 0.55 m collision circle World._pillar adds).
static func pillar(h: float) -> Node3D:
	var m := model("pillar")
	if m == null:
		return null
	var k := h / PILLAR_H
	m.scale = Vector3(minf(k, 1.0), k, minf(k, 1.0))
	see_through(m)
	return m

## A sarcophagus lying along z (World._sarcophagus' box footprint is 1.2 x 2.4 with the length along z).
static func sarcophagus() -> Node3D:
	var m := model("sarcophagus")
	if m == null:
		return null
	m.rotation.y = PI * 0.5
	see_through(m)
	return m

static func bones(yaw: float) -> Node3D:
	var m := model("bones")
	if m == null:
		return null
	m.rotation.y = yaw
	m.scale = Vector3.ONE * 0.85
	_no_shadow(m)
	return m

## The iron wall sconce: its back plate toward -z (the wall), its cup toward the room. The flame goes at SCONCE_CUP.
static func sconce() -> Node3D:
	return model("sconce")

## A wall torch's light in the Hollow Crypt: a warm pool that reaches the floor in front of its wall. The torch
## preset at the sconce's size lit 3.9 m, a patch of wall, and left the rooms to the hero's own light.
static func torch_light(fire: Node3D) -> void:
	var l := fire.get_node_or_null("FireLight") as OmniLight3D
	if l == null:
		return
	l.light_energy = TORCH_ENERGY
	l.omni_range = TORCH_RANGE
	l.set_meta("base", TORCH_ENERGY)
	l.position.z += 0.35          # out from the wall: the pool lands on the floor, not only on the stones behind it

static func brazier() -> Node3D:
	return model("brazier")

## The Extraction Portal's rune gate: its opening faces +z / -z (the camera looks through it). The runes' glow is
## the material's emission (baked from Meshy's blue paint): `set_runes` lights or dims them.
static func archway() -> Node3D:
	var m := model("archway")
	if m == null:
		return null
	see_through(m, true)
	set_runes(m, 0.0)
	return m

## Lights a gate's runes (the blue Meshy painted into its arch, picked out of the colour by SEE_SHADER), 0 = dark.
static func set_runes(arch: Node3D, energy: float) -> void:
	for n in arch.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si in mi.get_surface_override_material_count():
			var sm := mi.get_surface_override_material(si) as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("rune_energy", energy)

# ---------------------------------------------------------------- the see-through
const SEE_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform vec3 player_pos;
global uniform float occlude_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float normal_depth = 1.0;
uniform float use_normal = 1.0;
uniform vec3 rune_col : source_color = vec3(0.3, 0.55, 1.0);
uniform float rune_energy = 0.0;
varying vec3 wpos;
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float dith(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a) + 0.03125; }
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	// the see-through near the player, as the walls and the code-built props have (Mats PROP_SHADER)
	vec3 d = wpos - player_pos;
	float h = wpos.y - player_pos.y;
	float along = d.z - occlude_k * (h - 1.0);
	float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
	cover *= step(0.9, h) * step(0.2, d.z);
	if (cover * 0.9 > dith(FRAGCOORD.xy)) { discard; }
	vec3 c = texture(albedo_tex, UV).rgb;
	ALBEDO = c * albedo.rgb;
	vec4 mr = texture(mr_tex, UV);
	ROUGHNESS = mr.g * roughness;
	METALLIC = mr.b * metallic;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	if (rune_energy > 0.0) {
		// the runes Meshy painted blue into the stone light up
		float rune = smoothstep(0.05, 0.16, c.b - max(c.r, c.g));
		EMISSION = rune_col * rune * rune_energy * (0.85 + 0.15 * sin(TIME * 2.3 + wpos.y * 3.0));
	}
}
"""

## Gives a Meshy prop the see-through near the player that the crypt's walls and code-built props have: its
## imported materials (albedo, normal and the glTF metal-rough map) redrawn by SEE_SHADER. The tall pieces needed it:
## a hall pillar between the camera and the hero hid him. `own` = materials of its own (a gate's runes are lit
## one gate at a time); otherwise shared by every prop drawn from the same imported material.
static func see_through(root: Node3D, own := false) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var key := "see_%d" % src.get_instance_id()
			var sm: ShaderMaterial = null
			if not own and _cache.has(key):
				sm = _cache[key]
			else:
				sm = ShaderMaterial.new()
				if not _cache.has("see_shader"):
					var sh := Shader.new()
					sh.code = SEE_SHADER
					_cache["see_shader"] = sh
				sm.shader = _cache["see_shader"]
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("albedo", src.albedo_color)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("use_normal", 1.0 if src.normal_enabled and src.normal_texture != null else 0.0)
				sm.set_shader_parameter("normal_depth", src.normal_scale)
				sm.set_shader_parameter("mr_tex", src.roughness_texture if src.roughness_texture != null else src.metallic_texture)
				sm.set_shader_parameter("roughness", src.roughness)
				sm.set_shader_parameter("metallic", src.metallic)
				sm.set_shader_parameter("rune_col", Vector3(RUNE.r, RUNE.g, RUNE.b))
				if not own:
					_cache[key] = sm
			mi.set_surface_override_material(si, sm)

## An ossuary niche: 1 m wide, its shelves of bones facing +z.
static func niche() -> Node3D:
	return model("niche")

## A row of nine melted candles on a stone slab (candles.glb: Meshy, its modelled flames cut away by
## tools/blender/battlegrounds/cut_flames.py, which wrote CANDLE_WICKS), each wick burning FireFx's candle flame,
## one light for the row. The row runs along x, its short candles toward +z.
static func candles() -> Node3D:
	var m := model("candles")
	if m == null:
		return null
	var root := Models.N(null, "candles")
	root.add_child(m)
	for wk in CANDLE_WICKS:
		FireFx.make(root, (wk as Vector3) + Vector3(0, 0.004, 0), "candle", 0.16, Color(1.0, 0.72, 0.35), false, false, false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.66, 0.32)
	l.light_energy = 0.95
	l.omni_range = 4.2
	l.omni_attenuation = 1.3
	l.position = Vector3(0, 0.55, 0.25)
	l.add_to_group("flicker")
	l.set_meta("base", 0.95)
	l.set_meta("fire", 0.3)
	root.add_child(l)
	return root

## The Hollow Crypt's chest: the Meshy iron-bound chest (chest.glb, prepared at its game size, 1 m long), its
## skull lock toward +z, under the same footprint node World._chest gave the old stash chest (0.68 x 0.42 at 0.75
## scale), so the collision the server builds is unchanged.
static func chest(yaw_deg: float) -> Node3D:
	var m := model("chest")
	if m == null:
		return null
	var root := Props.footprint(Models.N(null, "stash", Vector3.ZERO, Vector3(0, yaw_deg, 0)), Vector2(0.68, 0.42))
	root.scale = Vector3.ONE * 0.75
	m.scale = Vector3.ONE / 0.75
	root.add_child(m)
	# its weathered grey wood a shade lighter, and a faint warm glint over it: in the raid's dark the loot sat unseen
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null:
			continue
		var key := "chest_%d" % src.get_instance_id()
		if not _cache.has(key):
			var lit: StandardMaterial3D = src.duplicate()
			lit.albedo_color = Color(1.3, 1.24, 1.16)
			_cache[key] = lit
		mi.set_surface_override_material(0, _cache[key])
	var l := OmniLight3D.new()
	l.name = "Glint"
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 0.6
	l.omni_range = 2.6
	l.omni_attenuation = 1.4
	l.position = Vector3(0, 0.95, 0.35)
	m.add_child(l)
	return root

## A dead king in crypt stone: the Meshy knight statue (Roman.STATUE_GLB) under the crypt's dark stone.
static func statue(h: float) -> Node3D:
	if not ResourceLoader.exists(STATUE):
		return null
	var fig := Node3D.new()
	var body: Node3D = (load(STATUE) as PackedScene).instantiate()
	fig.add_child(body)
	body.rotation.y = PI          # the glb faces +z; a statue faces its alcove's front like Roman.statue
	var sm := Mats.world(Color(0.3, 0.3, 0.31), Color(0.19, 0.19, 0.2), 0.85, 1.7, 0.35, Props.MOSS)
	var top := 0.0
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = sm
		top = maxf(top, (mi as MeshInstance3D).get_aabb().end.y)
	body.scale = Vector3.ONE * (h / maxf(top, 0.1))
	return fig

# ---------------------------------------------------------------- the Hollow Crypt's walls (Battlegrounds)
## World.crypt_shell (theme "bg") hands over the wall blocks' transforms, one per rock cell along the floor's edges
## (origin = the cell's centre at half its height; the heights and yaws World.rng rolled), and the rooms the map was
## built from (metas "bg_rooms": cell -> Rect2, "bg_hall": Rect2). Returns the transforms to draw as plain wall. The
## cells taken become, with their own RNG: a tomb alcove with a sarcophagus in the middle of each room's north
## wall, ossuary niches on the north wall's flanks and on the east and west walls, and in the hall three statue
## alcoves along the north wall and braziers on the east and west walls. Each alcove keeps the rock behind it
## (back slabs and a lintel from the same wall blocks) so nothing opens onto the void.
static func walls(w: World, wall_xf: Array) -> Array:
	if not w.has_meta("bg_rooms") or not w.has_meta("bg_hall"):
		return wall_xf
	var rooms: Dictionary = w.get_meta("bg_rooms")
	var hall: Rect2 = w.get_meta("bg_hall")
	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED
	var keep: Array = wall_xf.duplicate()
	var taken := {}                 # index in wall_xf -> true
	var extra: Array = []           # replacement blocks (lintels, back slabs)
	var rects: Array = rooms.values()
	rects.append(hall)
	for r in rects:
		var is_hall: bool = r == hall
		var rr: Rect2 = r
		# the torches on this room's north wall (World._wall_torch spots, Battlegrounds.build): keep clear of them
		var torches: Array = []
		if is_hall:
			for k in 4:
				torches.append(lerpf(rr.position.x + 4.0, rr.end.x - 4.0, k / 3.0))
		else:
			for k in 2:
				torches.append(lerpf(rr.position.x + 2.0, rr.end.x - 2.0, 0.25 + k * 0.5))
		# --- north wall: cells in the first rock row, floor right below them
		var north: Array = _wall_cells(w, wall_xf, taken, rr, "n")
		if is_hall:
			for sx in [-8.7, 0.0, 8.7]:
				var ci := _nearest_run(north, rr.get_center().x + sx, 2, torches, 1.0)
				if not ci.is_empty():
					_statue_alcove(w, wall_xf, ci, Vector3(0, 0, 1), taken, extra, rng)
		else:
			var ci := _nearest_run(north, rr.get_center().x, 3, torches, 0.9)
			if not ci.is_empty():
				_tomb_alcove(w, wall_xf, ci, Vector3(0, 0, 1), taken, extra, rng)
		# ossuary niches on the north wall's flanks (between a torch and the corner)
		for side in [-1.0, 1.0]:
			var want: float = rr.get_center().x + float(side) * (rr.size.x * 0.5 - 2.6)
			var ci2 := _nearest_run(north, want, 1, torches, 0.9)
			if not ci2.is_empty() and rng.randf() < (0.8 if not is_hall else 0.6):
				_niche(w, wall_xf, ci2[0], Vector3(0, 0, 1), taken, extra, rng)
		# --- east and west walls: niches (braziers in the hall)
		for ew in ["w", "e"]:
			var dir := Vector3(1, 0, 0) if ew == "w" else Vector3(-1, 0, 0)
			var cells: Array = _wall_cells(w, wall_xf, taken, rr, ew)
			if cells.is_empty():
				continue
			if is_hall:
				for sz in [-9.0, 0.0, 9.0]:
					var ci3 := _nearest_run(cells, rr.get_center().y + sz, 2, [], 0.0)
					if not ci3.is_empty():
						_brazier_alcove(w, wall_xf, ci3, dir, taken, extra, rng)
			else:
				var n := 1 if rr.size.y < 13.0 else 2
				for k in n:
					var want_z := lerpf(rr.position.y + 2.5, rr.end.y - 2.5, 0.5 if n == 1 else (0.25 + k * 0.5))
					var ci4 := _nearest_run(cells, want_z, 1, [], 0.0)
					if not ci4.is_empty() and rng.randf() < 0.85:
						_niche(w, wall_xf, ci4[0], dir, taken, extra, rng)
	var out: Array = []
	for i in keep.size():
		if not taken.has(i):
			out.append(keep[i])
	out.append_array(extra)
	return out

## The wall blocks lining one side of `r` ("n" = the row just north of it, "w"/"e" = the column just west/east),
## facing the room's floor, as [index into wall_xf, along-the-wall coordinate]; sorted along the wall.
static func _wall_cells(w: World, wall_xf: Array, taken: Dictionary, r: Rect2, side: String) -> Array:
	var out: Array = []
	for i in wall_xf.size():
		if taken.has(i):
			continue
		var o: Vector3 = (wall_xf[i] as Transform3D).origin
		match side:
			"n":
				if o.z < r.position.y and o.z > r.position.y - 1.05 and o.x >= r.position.x + 0.7 and o.x <= r.end.x - 0.7 and w.is_floor(o.x, o.z + 1.0):
					out.append([i, o.x])
			"w":
				if o.x < r.position.x and o.x > r.position.x - 1.05 and o.z >= r.position.y + 0.7 and o.z <= r.end.y - 0.7 and w.is_floor(o.x + 1.0, o.z):
					out.append([i, o.z])
			"e":
				if o.x > r.end.x and o.x < r.end.x + 1.05 and o.z >= r.position.y + 0.7 and o.z <= r.end.y - 0.7 and w.is_floor(o.x - 1.0, o.z):
					out.append([i, o.z])
	out.sort_custom(func(a, b) -> bool: return float(a[1]) < float(b[1]))
	return out

## `n` consecutive cells (1 m apart) nearest to `at` along the wall, none within `clear` of a torch; [] if none.
static func _nearest_run(cells: Array, at: float, n: int, torches: Array, clear: float) -> Array:
	var best: Array = []
	var bd := INF
	for s in range(0, cells.size() - n + 1):
		var ok := true
		for k in n:
			if k > 0 and absf(float(cells[s + k][1]) - float(cells[s + k - 1][1])) > 1.3:
				ok = false
			for t in torches:
				if absf(float(cells[s + k][1]) - float(t)) < clear:
					ok = false
		if not ok:
			continue
		var mid := (float(cells[s][1]) + float(cells[s + n - 1][1])) * 0.5
		var d := absf(mid - at)
		if d < bd:
			bd = d
			best = []
			for k in n:
				best.append(int(cells[s + k][0]))
	return best

## The room-facing boundary of a wall cell and the frame of a module standing in it: `dir` points into the room.
static func _cell_face(xf: Transform3D, dir: Vector3) -> Vector3:
	return Vector3(xf.origin.x, 0.0, xf.origin.z) + dir * 0.51

static func _yaw(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)

## Blocks that fill a cell back from the module: a slab `thick` deep at the cell's back, and (lintel) the wall over
## the opening from `open_h` up to the cell's height.
static func _back_slab(xf: Transform3D, dir: Vector3, thick: float, extra: Array) -> void:
	var hh := xf.origin.y * 2.0
	var c := Vector3(xf.origin.x, hh * 0.5, xf.origin.z) - dir * (0.51 - thick * 0.5)
	var b := Basis(Vector3.UP, _yaw(dir)).scaled(Vector3(1.02, hh, thick))
	extra.append(Transform3D(b, c))

static func _lintel(cells: Array, wall_xf: Array, dir: Vector3, open_h: float, extra: Array) -> void:
	var hh := INF
	var c := Vector3.ZERO
	for i in cells:
		var xf: Transform3D = wall_xf[i]
		hh = minf(hh, xf.origin.y * 2.0)
		c += Vector3(xf.origin.x, 0.0, xf.origin.z)
	c /= cells.size()
	if hh <= open_h + 0.05:
		return
	var width := cells.size() * 1.02
	var b := Basis(Vector3.UP, _yaw(dir)).scaled(Vector3(width, hh - open_h, 1.02))
	extra.append(Transform3D(b, Vector3(c.x, open_h + (hh - open_h) * 0.5, c.z)))

## An ossuary niche in one cell: the module flush with the wall, the rock closed behind and above it, sometimes a
## candle burning on its middle shelf.
static func _niche(w: World, wall_xf: Array, i: int, dir: Vector3, taken: Dictionary, extra: Array, rng: RandomNumberGenerator) -> void:
	var m := niche()
	if m == null:
		return
	var xf: Transform3D = wall_xf[i]
	taken[i] = true
	var face := _cell_face(xf, dir)
	var root := Models.N(null, "niche")
	root.add_child(m)
	w._place(root, face - dir * (NICHE_D * 0.5))
	root.rotation.y = _yaw(dir)
	_back_slab(xf, dir, 1.02 - NICHE_D, extra)
	_lintel([i], wall_xf, dir, NICHE_H, extra)
	if rng.randf() < 0.45:
		var cp := Vector3(rng.randf_range(-0.2, 0.2), 1.05, NICHE_D * 0.5 - 0.22)
		Props.fire(root, cp, 0.28, Color(1.0, 0.72, 0.35), true, false, false, "candle")

## A tomb alcove over `cells` (three): a sarcophagus lying along the wall, protruding a hand's breadth into the
## room, the rock closed behind it and a lintel over the opening.
static func _tomb_alcove(w: World, wall_xf: Array, cells: Array, dir: Vector3, taken: Dictionary, extra: Array, rng: RandomNumberGenerator) -> void:
	var m := model("sarcophagus")
	if m == null:
		return
	var c := Vector3.ZERO
	for i in cells:
		taken[i] = true
		c += _cell_face(wall_xf[i], dir)
	c /= cells.size()
	var root := Models.N(null, "tomb")
	root.add_child(m)
	m.rotation.y = 0.0 if rng.randf() < 0.5 else PI      # (it lies along x, the wall's line; the head to either side)
	w._place(root, c - dir * 0.3)
	root.rotation.y = _yaw(dir)
	for i in cells:
		_back_slab(wall_xf[i], dir, 0.16, extra)
	_lintel(cells, wall_xf, dir, 2.25, extra)

## A dead king in his alcove (two cells wide), a candle at his feet.
static func _statue_alcove(w: World, wall_xf: Array, cells: Array, dir: Vector3, taken: Dictionary, extra: Array, rng: RandomNumberGenerator) -> void:
	var fig := statue(2.3)
	if fig == null:
		return
	var c := Vector3.ZERO
	for i in cells:
		taken[i] = true
		c += _cell_face(wall_xf[i], dir)
	c /= cells.size()
	var root := Models.N(null, "king")
	var sm := Mats.world(Color(0.26, 0.26, 0.27), Color(0.17, 0.17, 0.18), 0.9, 1.6, 0.3, Props.MOSS)
	Models.P(root, Geo.box(1.7, 0.3, 0.9), sm, Vector3(0, 0.15, 0))
	fig.position = Vector3(0, 0.3, 0.05)
	root.add_child(fig)
	w._place(root, c - dir * 0.42)
	root.rotation.y = _yaw(dir)
	for i in cells:
		_back_slab(wall_xf[i], dir, 0.12, extra)
	_lintel(cells, wall_xf, dir, 2.75, extra)
	if rng.randf() < 0.7:
		Props.fire(root, Vector3(0.55, 0.3, 0.42), 0.28, Color(1.0, 0.72, 0.35), true, false, false, "candle")
	# a cold light falling on the dead king from under the lintel, the seal's blue (the alcove read as a black hole)
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.68, 1.0)
	l.light_energy = 0.9
	l.omni_range = 3.6
	l.omni_attenuation = 1.5
	l.position = Vector3(0, 2.5, 0.9)
	root.add_child(l)

## A brazier burning in a two-cell alcove of the hall's wall.
static func _brazier_alcove(w: World, wall_xf: Array, cells: Array, dir: Vector3, taken: Dictionary, extra: Array, _rng: RandomNumberGenerator) -> void:
	var m := brazier()
	if m == null:
		return
	var c := Vector3.ZERO
	for i in cells:
		taken[i] = true
		c += _cell_face(wall_xf[i], dir)
	c /= cells.size()
	var root := Models.N(null, "brazier")
	root.add_child(m)
	w._place(root, c - dir * 0.42)
	root.rotation.y = _yaw(dir)
	for i in cells:
		_back_slab(wall_xf[i], dir, 0.12, extra)
	_lintel(cells, wall_xf, dir, 2.5, extra)
	Props.fire(root, Vector3(0, BRAZIER_TOP, 0), 1.0, Color(1.0, 0.45, 0.16), true, false, true, "brazier")

# ---------------------------------------------------------------- materials
const WALL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform vec3 player_pos;
global uniform float occlude_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.5;          // texture repeats per metre
uniform float roughness = 0.92;
uniform vec3 tint : source_color = vec3(1.0);
uniform float moss = 0.35;
uniform vec3 moss_col : source_color = vec3(0.2, 0.28, 0.12);
uniform float occlude = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float dith(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a) + 0.03125; }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
float fbm3(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<3;i++){ v+=a*vnoise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment(){
	if (occlude > 0.5) {
		// the see-through near the player, as every prop has (Mats PROP_SHADER)
		vec3 d = wpos - player_pos;
		float h = wpos.y - player_pos.y;
		float along = d.z - occlude_k * (h - 1.0);
		float cover = (1.0 - smoothstep(1.6, 3.2, abs(along))) * (1.0 - smoothstep(2.2, 3.6, abs(d.x)));
		cover *= step(0.9, h) * step(0.2, d.z);
		if (cover * 0.9 > dith(FRAGCOORD.xy)) { discard; }
	}
	// world-space mapping, the side that faces the normal (every wall block is axis-aligned, give or take a degree):
	// u runs to the right of someone facing the wall, v down the wall (the image's top at the top), so the normal
	// map's tangent frame is t (right) and up
	vec3 an = abs(wnorm);
	vec2 uv;
	vec3 t;
	vec3 bt;
	if (an.y > 0.6) { uv = wpos.xz; t = vec3(1.0, 0.0, 0.0); bt = vec3(0.0, 0.0, -1.0); }
	else if (an.x > an.z) { uv = vec2(-wpos.z * sign(wnorm.x), -wpos.y); t = vec3(0.0, 0.0, -sign(wnorm.x)); bt = vec3(0.0, 1.0, 0.0); }
	else { uv = vec2(wpos.x * sign(wnorm.z), -wpos.y); t = vec3(sign(wnorm.z), 0.0, 0.0); bt = vec3(0.0, 1.0, 0.0); }
	uv *= tile;
	vec3 col = texture(albedo_tex, uv).rgb * tint;
	// slow variation across the room so no two blocks read the same, grime toward the floor, moss in the damp
	float big = fbm3(wpos.xz * 0.11 + wpos.y * 0.05);
	col *= 0.82 + big * 0.36;
	col *= mix(0.72, 1.0, smoothstep(0.0, 1.1, wpos.y));
	float mossf = moss * smoothstep(0.45, 0.85, fbm3(wpos.xz * 0.6 + wpos.y * 0.9 + 7.0) + (1.0 - smoothstep(0.3, 1.6, wpos.y)) * 0.25);
	col = mix(col, moss_col * (0.75 + big * 0.5), clamp(mossf, 0.0, 0.85));
	ALBEDO = col;
	vec3 nm = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 wn = normalize(wnorm);
	vec3 n = normalize(t * nm.x + bt * nm.y + wn * nm.z * 1.4);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = roughness - mossf * 0.1;
	METALLIC = 0.0;
}
"""

## The Hollow Crypt's wall: baked stone blocks (TEX wall_albedo / wall_normal), else the crypt's old procedural stone.
static func wall_material() -> Material:
	if _cache.has("wall"):
		return _cache["wall"]
	var m: Material
	if ResourceLoader.exists(TEX + "wall_albedo.png") and ResourceLoader.exists(TEX + "wall_normal.png"):
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WALL_SHADER
		sm.shader = sh
		sm.set_shader_parameter("albedo_tex", load(TEX + "wall_albedo.png"))
		sm.set_shader_parameter("normal_tex", load(TEX + "wall_normal.png"))
		sm.set_shader_parameter("tile", 0.5)
		sm.set_shader_parameter("tint", Vector3(0.92, 0.9, 0.86))
		m = sm
	else:
		m = Mats.world(Color(0.36, 0.34, 0.31), Color(0.24, 0.23, 0.21), 0.92, 2.2, 0.3, Color(0.14, 0.16, 0.09))
	_cache["wall"] = m
	return m

const FLOOR_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.33;         // texture repeats per metre (3 m flagstone tiles)
uniform float roughness = 0.9;
uniform vec3 tint : source_color = vec3(1.0);
varying vec3 wpos;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
float fbm3(vec2 p){ float v=0.0; float a=0.5; for(int i=0;i<3;i++){ v+=a*vnoise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
void vertex(){
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	vec2 uv = wpos.xz * tile;
	vec3 col = texture(albedo_tex, uv).rgb * tint;
	// damp, dark patches and lighter dust across the floor, slow enough never to repeat with the stone
	float big = fbm3(wpos.xz * 0.09 + 3.0);
	float damp = smoothstep(0.55, 0.8, fbm3(wpos.xz * 0.21 + 11.0));
	col *= 0.78 + big * 0.42;
	col = mix(col, col * vec3(0.55, 0.6, 0.62), damp * 0.7);
	ALBEDO = col;
	vec3 nm = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3(nm.x, nm.z * 1.3, -nm.y));      // the map's up is the floor's -z (the texture's v runs down the image)
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ROUGHNESS = roughness - damp * 0.45;
	METALLIC = 0.0;
}
"""

## The Hollow Crypt's flagstone floor: quads over the floor cells (World's 1 m grid), a hair above the terrain,
## under the flagstone textures (TEX floor_albedo / floor_normal); nothing without them (the terrain's own crypt
## floor shows then). In tiles of TILE metres, one mesh each, like the walls (wall_meshes): the OpenGL renderer
## lights an instance by at most eight lights, and the hall alone has more than that.
static func lay_floor(w: World) -> void:
	if not (ResourceLoader.exists(TEX + "floor_albedo.png") and ResourceLoader.exists(TEX + "floor_normal.png")):
		return
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	sm.shader = sh
	sm.set_shader_parameter("albedo_tex", load(TEX + "floor_albedo.png"))
	sm.set_shader_parameter("normal_tex", load(TEX + "floor_normal.png"))
	sm.set_shader_parameter("tile", 0.33)
	sm.set_shader_parameter("tint", Vector3(0.9, 0.9, 0.88))
	var y := 0.015
	var h := World.CELL * 0.5 + 0.02
	# the Ossuary's rooms and ways only (the floors below keep their own ground), over their bounding box
	var rects: Array = []
	for r in w.floor_rects:
		var rr: Rect2 = r
		if BgFloors.floor_of(Vector3(rr.get_center().x, 0.0, rr.get_center().y)) == 1:
			rects.append(rr)
	if rects.is_empty():
		return
	var bb: Rect2 = rects[0]
	for r in rects:
		bb = bb.merge(r)
	var i0 := maxi(0, int(floor((bb.position.x - w.origin.x) / World.CELL)))
	var i1 := mini(w.gw - 1, int(ceil((bb.end.x - w.origin.x) / World.CELL)))
	var j0 := maxi(0, int(floor((bb.position.y - w.origin.y) / World.CELL)))
	var j1 := mini(w.gh - 1, int(ceil((bb.end.y - w.origin.y) / World.CELL)))
	var tiles := {}      # Vector2i tile -> SurfaceTool
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var cx: float = w.origin.x + (i + 0.5) * World.CELL
			var cz: float = w.origin.y + (j + 0.5) * World.CELL
			var inside := false
			for r in rects:
				if (r as Rect2).has_point(Vector2(cx, cz)):
					inside = true
					break
			if not inside:
				continue
			var key := Vector2i(floori(cx / TILE), floori(cz / TILE))
			if not tiles.has(key):
				var nst := SurfaceTool.new()
				nst.begin(Mesh.PRIMITIVE_TRIANGLES)
				tiles[key] = nst
			var st: SurfaceTool = tiles[key]
			var vs := [Vector3(cx - h, y, cz - h), Vector3(cx + h, y, cz - h), Vector3(cx + h, y, cz + h), Vector3(cx - h, y, cz + h)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(vs[k].x, vs[k].z))
				st.add_vertex(vs[k])
	for key in tiles:
		var mi := MeshInstance3D.new()
		mi.mesh = (tiles[key] as SurfaceTool).commit()
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "crypt_floor_%d_%d" % [key.x, key.y]
		w.props_root.add_child(mi)

## The plain wall blocks (what `walls` leaves) in tiles of TILE metres, one MultiMesh each, under the crypt stone:
## one MultiMesh round the whole crypt took only eight of its torches in the OpenGL renderer.
static func wall_meshes(w: World, wall_xf: Array) -> void:
	var tiles := {}
	for xf in wall_xf:
		var o: Vector3 = (xf as Transform3D).origin
		var key := Vector2i(floori(o.x / TILE), floori(o.z / TILE))
		if not tiles.has(key):
			tiles[key] = []
		(tiles[key] as Array).append(xf)
	var mesh := Geo.box(1.02, 1.0, 1.02)
	var wm := wall_material()
	for key in tiles:
		Props.multimesh(w.props_root, mesh, tiles[key]).material_override = wm

# ---------------------------------------------------------------- the Extraction Portal
const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color = vec3(0.3, 0.55, 1.0);
uniform float energy = 1.0;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// (energy above ~1 summed to a white oval: the swirl is the portal, the core only a cold heart in it)
	float swirl = vnoise(vec2(a * 2.2 + TIME * 0.7 + r * 4.0, r * 6.0 - TIME * 1.3));
	float swirl2 = vnoise(vec2(a * 3.7 - TIME * 1.1, r * 9.0 + TIME * 0.6));
	float arms = smoothstep(0.35, 0.85, vnoise(vec2(a * 1.6 - r * 5.0 + TIME * 1.6, r * 2.0)));
	float edge = 1.0 - smoothstep(0.78, 1.0, r);
	float rim = smoothstep(0.55, 0.92, r) * edge;
	float core = exp(-r * r * 5.0);
	float v = edge * (0.2 + 0.55 * swirl * swirl2 + 0.45 * arms) + rim * 0.5 + core * 0.45;
	vec3 c = mix(col * 0.8, vec3(0.75, 0.9, 1.0), core * 0.6 + arms * 0.2);
	ALBEDO = c * v * energy;
	ALPHA = clamp(v, 0.0, 1.0) * edge;
}
"""

## The light in an open Extraction Portal: a tall oval of cold swirling light standing in the gate's opening (the
## Inter's "Model", hidden until the portal opens), its motes and its light. Fx.portal_model's shape without the
## ring: the archway is the frame now.
static func portal_glow() -> Node3D:
	var root := Node3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.55, 2.55)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PORTAL_SHADER
	sm.shader = sh
	sm.set_shader_parameter("col", Vector3(RUNE.r, RUNE.g, RUNE.b))
	for side in [0.0, PI]:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = sm
		mi.position = Vector3(0, 1.5, 0.02 if side == 0.0 else -0.02)
		mi.rotation.y = side
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 1.2, 0.15)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, 0.35, 0)
	var g := Gradient.new()
	g.set_color(0, Color(RUNE.r, RUNE.g, RUNE.b, 0.0))
	g.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	g.add_point(0.3, Color(RUNE.r, RUNE.g, RUNE.b, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	qm.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = qm
	p.position = Vector3(0, 1.5, 0)
	root.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.7, 1.0)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.position = Vector3(0, 1.6, 0.6)
	l.add_to_group("flicker")
	l.set_meta("base", 2.2)
	root.add_child(l)
	return root

# ---------------------------------------------------------------- dressing
## Small rubble at the feet of the walls, cobwebs in the corners, and the hall's floor seal. Own RNG; nothing solid.
static func dress(w: World) -> void:
	if not w.has_meta("bg_rooms") or not w.has_meta("bg_hall"):
		return
	var rooms: Dictionary = w.get_meta("bg_rooms")
	var hall: Rect2 = w.get_meta("bg_hall")
	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED + 1
	lay_floor(w)
	# rubble: chips of the walls' stone along the room edges (MultiMesh, no collision: ankle-high)
	var xfs := {}
	var rects: Array = rooms.values()
	rects.append(hall)
	for r in rects:
		var rr: Rect2 = r
		var n := int(rr.size.x * rr.size.y * 0.035)
		for k in n:
			var along := rng.randf()
			var side := rng.randi() % 4
			var p := Vector3.ZERO
			var inset := rng.randf_range(0.15, 0.9)
			match side:
				0: p = Vector3(lerpf(rr.position.x, rr.end.x, along), 0, rr.position.y + inset)
				1: p = Vector3(lerpf(rr.position.x, rr.end.x, along), 0, rr.end.y - inset)
				2: p = Vector3(rr.position.x + inset, 0, lerpf(rr.position.y, rr.end.y, along))
				_: p = Vector3(rr.end.x - inset, 0, lerpf(rr.position.y, rr.end.y, along))
			if not w.is_floor(p.x, p.z) or w.is_near_obstacle(p, 0.6):
				continue
			var v := rng.randi_range(0, 3)
			if not xfs.has(v):
				xfs[v] = []
			var s := rng.randf_range(0.08, 0.26)
			(xfs[v] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.5), s * 0.7, s)), Vector3(p.x, w.height_at(p.x, p.z) + s * 0.1, p.z)))
	for v in xfs:
		Props.multimesh(w.props_root, Props.rock_mesh(60 + int(v), 0.3), xfs[v], false).material_override = Mats.world(Color(0.33, 0.31, 0.29), Color(0.2, 0.19, 0.18), 0.95, 2.0, 0.2, Props.MOSS)
	# the hall's floor seal under the champion, and torches on its pillars
	var seal := floor_seal()
	if seal:
		var hc := hall.get_center()
		w.props_root.add_child(seal)
		seal.position = Vector3(hc.x, 0.03, hc.y)
	hall_torches(w, hall)
	# cobwebs where a wall meets a corner, hanging in the torchlight
	var web := cobweb_mesh()
	if web != null:
		var wxf: Array = []
		for r in rects:
			var rr: Rect2 = r
			for corner in [Vector2(rr.position.x, rr.position.y), Vector2(rr.end.x, rr.position.y)]:
				if rng.randf() < 0.65:
					var inward := Vector2(1.0 if corner.x == rr.position.x else -1.0, 1.0)
					var p := Vector3(corner.x + inward.x * 0.32, rng.randf_range(2.2, 2.7), corner.y + inward.y * 0.32)
					var yaw := -PI * 0.25 if inward.x > 0.0 else PI * 0.25
					var s := rng.randf_range(0.8, 1.3)
					wxf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), p))
		if not wxf.is_empty():
			var mmi := Props.multimesh(w.props_root, web, wxf, false)
			mmi.material_override = cobweb_material()
	# dust hanging in the air of every room and the hall, seen where the light catches it
	for r in rects:
		dust(w, r)
	void_frame(w)

## Black beyond the crypt's rock, level with the rock's black tops: the ground the terrain runs on past the map's
## edge showed as grey stone at the edge of the screen in the corner rooms.
static func void_frame(w: World) -> void:
	var b := w.bounds
	var far := 160.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.0, 0.0, 0.0)
	for r in [Rect2(b.position.x - far, b.position.y - far, b.size.x + far * 2.0, far), Rect2(b.position.x - far, b.end.y, b.size.x + far * 2.0, far),
			Rect2(b.position.x - far, b.position.y, far, b.size.y), Rect2(b.end.x, b.position.y, far, b.size.y)]:
		var rr: Rect2 = r
		var pm := PlaneMesh.new()
		pm.size = rr.size
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(rr.get_center().x, 3.1, rr.get_center().y)
		mi.name = "void"
		w.props_root.add_child(mi)

## Torches in sconces on every other pillar of the hall's ring (Battlegrounds.build's twelve, 11.5 m out), on the
## face that looks most toward the seal: the middle of the hall had only the seal's glow, and the pillars stood black
## against the north wall's torches. The sconces sit on the pillar's skin (PILLAR_SKIN), so no footprint grows.
static func hall_torches(w: World, hall: Rect2) -> void:
	if not has("sconce") or not has("pillar"):
		return
	var hc := hall.get_center()
	for i in range(0, 12, 2):
		var a := TAU * i / 12.0
		var p := Vector3(hc.x + cos(a) * 11.5, 0.0, hc.y + sin(a) * 11.5)
		var inward := Vector3(-cos(a), 0.0, -sin(a))
		var face := Vector3(signf(inward.x), 0.0, 0.0) if absf(inward.x) > absf(inward.z) else Vector3(0.0, 0.0, signf(inward.z))
		var g := Node3D.new()
		g.name = "pillar_torch"
		w.props_root.add_child(g)
		g.position = Vector3(p.x, w.height_at(p.x, p.z), p.z) + face * PILLAR_SKIN
		g.rotation.y = _yaw(face)
		var mm := sconce()
		mm.position = Vector3(0, 2.1, 0)
		g.add_child(mm)
		torch_light(Props.fire(g, Vector3(0, 2.1, 0) + SCONCE_CUP, 0.6, Color(1.0, 0.5, 0.2), true, false, false, "torch"))

## Dust in a room's air: motes drifting slowly, lit like everything else, so they show in the torchlight and the
## hero's light and vanish in the dark between.
static func dust(w: World, r: Rect2) -> void:
	var p := GPUParticles3D.new()
	p.name = "dust"
	p.amount = int(clampf(r.size.x * r.size.y * 0.22, 30.0, 200.0))
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.visibility_aabb = AABB(Vector3(-r.size.x * 0.5 - 1.0, -1.6, -r.size.y * 0.5 - 1.0), Vector3(r.size.x + 2.0, 4.4, r.size.y + 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r.size.x * 0.5, 1.25, r.size.y * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.07
	pm.gravity = Vector3(0, -0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_noise_speed = Vector3(0.04, 0.015, 0.04)
	pm.scale_min = 0.45
	pm.scale_max = 1.25
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	q.material = dust_material()
	p.draw_pass_1 = q
	p.position = Vector3(r.get_center().x, 1.5, r.get_center().y)
	w.props_root.add_child(p)

static func dust_material() -> Material:
	if _cache.has("dust"):
		return _cache["dust"]
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.84, 0.76, 0.5)
	m.albedo_texture = dot
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_cache["dust"] = m
	return m

## A cobweb: a triangular card spanning a corner (its texture TEX cobweb.png, Meshy; none without it).
static func cobweb_mesh() -> Mesh:
	if not ResourceLoader.exists(TEX + "cobweb.png"):
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a square card 1 m across, hung from its top corner: the texture's web fills it
	var vs := [Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, -0.5, 0)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[i])
		st.add_vertex(vs[i])
	return st.commit()

static func cobweb_material() -> Material:
	if _cache.has("web"):
		return _cache["web"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "cobweb.png")
	m.albedo_color = Color(0.85, 0.85, 0.82, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_cache["web"] = m
	return m

const SEAL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D emit_tex : source_color, filter_linear_mipmap;
uniform float energy = 1.35;
float hash21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),u.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),u.x), u.y); }
void fragment(){
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * 0.8;
	ALPHA = a.a;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// the runes breathe, and a slow wave of light runs out from the skull through the rings
	float wave = smoothstep(0.18, 0.0, abs(r - fract(TIME * 0.12) * 1.1));
	float flick = 0.8 + 0.2 * vnoise(vec2(atan(p.y, p.x) * 3.0, TIME * 0.7));
	float pulse = (0.7 + 0.3 * sin(TIME * 0.9)) * flick + wave * 0.9;
	EMISSION = texture(emit_tex, UV).rgb * energy * pulse;
	ROUGHNESS = 0.8;
}
"""

## The great hall's floor seal: the Meshy-painted stone seal (TEX seal.png, its edge cut out in the alpha) laid on the
## flagstones, its runes lit (seal_emit.png: the painting's blue alone), breathing, a wave of light running out from
## the skull now and then. A quad on the flat floor rather than a Decal: the OpenGL renderer draws no decals.
static func floor_seal() -> Node3D:
	if not ResourceLoader.exists(TEX + "seal.png"):
		return null
	var q := QuadMesh.new()
	q.size = Vector2(11.0, 11.0)
	q.orientation = PlaneMesh.FACE_Y
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEAL_SHADER
	sm.shader = sh
	sm.set_shader_parameter("albedo_tex", load(TEX + "seal.png"))
	if ResourceLoader.exists(TEX + "seal_emit.png"):
		sm.set_shader_parameter("emit_tex", load(TEX + "seal_emit.png"))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	mi.name = "seal"
	var l := OmniLight3D.new()
	l.light_color = Color(RUNE.r, RUNE.g, RUNE.b)
	l.light_energy = 0.9
	l.omni_range = 7.5
	l.omni_attenuation = 1.6
	l.position = Vector3(0, 0.6, 0)
	mi.add_child(l)
	return mi
