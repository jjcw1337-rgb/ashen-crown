class_name WaypointGrand
extends Node3D
## The camp's grand waypoint (waypoint overhaul): a three-tier stone dais whose floor's rings and spokes are carved
## rune channels with the glow down in them, a floating rune crystal over a light column, four blue-fire braziers,
## two hooded guardian statues with spears, two red banners, a broken back wall ending in rune-carved pillars, and
## two warm torches in front. Local +z faces the camera (travellers arrive on that side).
## Models (`DIR`): `dais.glb` modelled by tools/blender/waypoint/build_dais.py (steps, floor, groove, socket: the
## game's stone material goes on); Meshy pieces re-baked by tools/blender/camp/rebake_prop.py (crystal split into
## socket / crystal / shards and the brazier's and torch's modelled flames cut by tools/blender/waypoint/split_parts.py):
## crystal, brazier, guardian, banner, torch, pillar. Each one missing falls back to its code-built blockout.
## `SOLIDS` lists the colliders (local x, z, radius) that World.add_waypoint turns into circles.

const DIR := "res://assets/models/waypoint/"
const RUNE := Color(0.04, 0.3, 1.0)     # deep cyan: the fx shader multiplies it by energy, so pale tints clip to white
const RUNE_CORE := Color(0.36, 0.74, 1.0)  # the heart of a glowing stroke
const RUNES_TEX := "res://assets/textures/waypoint/rune_rings.png"   # tools/waypoint_runes.py
const RUNES_SPAN := 7.0                   # metres the rune texture covers (+-3.5 m round the centre)
const DAIS_R := 4.85          # outer step radius
const TOP_Y := 0.36           # walking height of the inner dais

const SOLIDS := [
	# braziers on the middle step
	[2.76, 2.76, 0.45], [-2.76, 2.76, 0.45], [2.76, -2.76, 0.45], [-2.76, -2.76, 0.45],
	# guardian statues' plinths (GUARDIAN_AT), standing in the back wall's breaks
	[4.9, -4.5, 0.85], [-4.9, -4.5, 0.85],
	# banner poles (two a side, BANNERS), the torches in the wall's gap, the fire bowls flanking the approach
	# (FIRE_BOWLS), the crystal's socket
	[2.1, -5.3, 0.2], [-2.1, -5.3, 0.2], [3.45, -4.55, 0.2], [-3.45, -4.55, 0.2],
	[0.8, -6.0, 0.2], [-0.8, -6.0, 0.2], [4.7, 4.3, 0.5], [-4.7, 4.3, 0.5], [0.0, 0.0, 0.65],
	# the broken back wall (WALL_R, WALL_A0 + i * WALL_STEP; gaps at 1, 4 and 7) and its two end pillars
	[-5.62, -2.62, 0.75], [-3.05, -5.4, 0.6], [-1.25, -6.07, 0.6],
	[1.25, -6.07, 0.6], [3.05, -5.4, 0.6], [5.62, -2.62, 0.75],
]
const GUARDIAN_AT := Vector3(4.9, 0.0, -4.5)
const BANNERS := [[2.1, -5.3, 1.0], [3.45, -4.55, 0.9]]     # x, z, scale (mirrored each side)
const FIRE_BOWLS := Vector3(4.7, 0.0, 4.3)
const TORCH_AT := Vector3(0.8, 0.0, -6.0)
const BOWL_SCALE := 1.32
const CRY_SCALE := 0.72      # crystal.glb is 3 m tall with a 2 m socket: fit the socket inside the inner channel
const CRY_GROW := 2.08       # the crystal and its shards bigger than the socket's scale: the centrepiece must read
                             # (the crystal piece is 2 m tall as modelled: 0.72 * 2.08 = 3 m, the picture's size)
const CRY_Y := 3.35          # the crystal's heart: its foot a metre and a half over the socket, in the column
const COLUMN_TOP := 14.0     # the column of light fades out up here (off the top of the game's frame)
const ARCS := 8              # lightning arcs crawling over the crystal
const BRAZIER_SCALE := 1.15
const WALL_R := 6.2
const WALL_A0 := 205.0
const WALL_STEP := 16.25

const IDLE := 0.22           # rune glow with nobody near (a soft cyan: the old stone's white blaze read as UI)
const NEAR := 0.55           # rune glow with a hero on the dais
const RUNES_IDLE := 0.55     # the lettering's energy with nobody near (RUNE_FLOOR_SHADER)
const RUNES_NEAR := 0.82     # and with a hero on the dais
const WAKE_R := 11.0         # a hero inside this starts waking it; fully awake at 3.5 m

var crystal: Node3D
var shards: Node3D
var rune_mat: ShaderMaterial           # glyphs, spokes and the socket ring
var rune_floor: ShaderMaterial         # the lettering rings on the flagstones (RUNE_FLOOR_SHADER)
var ring_mats: Array[ShaderMaterial] = []   # outer, middle, inner channel: they light one after another
var edge_mats: Array[ShaderMaterial] = []   # the lower steps' lit lips
var _wave := -1.0            # the pulse ring running out over the runes: its radius (m), < 0 none
var _wave_t := 2.0           # seconds to the next pulse
var crystal_mats: Array[ShaderMaterial] = []   # the crystal's and the shards' glass (CRYSTAL_SHADER)
var column_mats: Array[ShaderMaterial] = []    # the column's core and sheath
var bolt_mat: ShaderMaterial                   # lightning up the column
var glow_mats: Array = []                      # the socket's blaze and the crystal's heart (glow sprites)
var arcs: Array = []                           # {m, n, t, hold}: the arcs over the crystal
var column_sparks: GPUParticles3D
var motes_high: GPUParticles3D
var mist: GPUParticles3D
var fog_mats: Array = []                        # the FogVolumes' materials (High/Ultra: the shaft in the air)
var light_low: OmniLight3D
var wet_mats: Array[ShaderMaterial] = []            # the dais stone with rain on it (wet_stone)
var mirrors: Array = []                         # [local pos, colour, strength]: the fires the puddles mirror
var light: OmniLight3D
var motes: GPUParticles3D
var _t := 0.0
var _wake := 0.0             # 0 asleep .. 1 a hero on the dais (smoothed)
var _flash := 0.0            # the arrival / activation burst, decaying
var _spin := 0.0
var _arrival_checked := false
var hearts: Array[ShaderMaterial] = []   # the braziers' white-hot hearts (glow), flickering
var _cry_y := 3.0            # the crystal's resting height (from its model when there is one)
var _sh_y := 3.0

static var _shaders := {}

static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

## A soft glow sprite (InfernalFx's glow quad) placed in the parent's own frame (we're built before we're in the tree,
## so InfernalFx.glow's global placing can't be used).
static func _glow_quad(parent: Node3D, pos: Vector3, size: float, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = InfernalFx.quad()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	parent.add_child(mi)
	mi.position = pos
	mi.scale = Vector3.ONE * size
	return mi

static func _glb(name: String) -> Node3D:
	var path := DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()

## The model's bounds in its own frame (it isn't in the tree yet, so the transforms are walked by hand).
static func _bounds(root: Node3D) -> AABB:
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

## Place a model piece under `parent` (no shadows from the tiny ones; `cast` off for flat glow-adjacent parts).
func _put(parent: Node3D, name: String, pos: Vector3, yaw_deg := 0.0, s := 1.0) -> Node3D:
	var m := _glb(name)
	if m == null:
		return null
	parent.add_child(m)
	m.position = pos
	m.rotation_degrees.y = yaw_deg
	m.scale = Vector3.ONE * s
	return m

static func build() -> WaypointGrand:
	var w := WaypointGrand.new()
	w.name = "waypoint"
	w._build()
	return w

func _build() -> void:
	var stone := wet_stone(Color(0.27, 0.27, 0.28), Color(0.16, 0.16, 0.17), 0.92, 1.3, 0.45, Props.MOSS, true, 0.55)
	var stone_d := Mats.world(Color(0.19, 0.19, 0.2), Color(0.12, 0.12, 0.13), 0.9, 2.2, 0.2, Props.MOSS)
	var floor_m := wet_stone(Color(0.26, 0.26, 0.28), Color(0.16, 0.16, 0.18), 0.75, 2.6, 0.1, Props.MOSS, false, 0.8)
	var iron := Mats.mat(Color(0.12, 0.11, 0.1), 0.55, 0.85)
	var statue_m := Mats.world(Color(0.34, 0.33, 0.31), Color(0.2, 0.2, 0.19), 0.9, 1.7, 0.4, Props.MOSS)
	rune_mat = Mats.glow_unique(RUNE, 1.1)

	# --- the dais: the Blender model (steps, flagstone floor, the channels' floor) under the game's stone, else
	# the blockout's three steps
	var dais := _glb("dais")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var groove_y := TOP_Y + 0.025       # where the rune meshes sit: in the channels, or on the blockout's floor
	if dais:
		add_child(dais)
		var groove_m := Mats.world(Color(0.07, 0.08, 0.1), Color(0.04, 0.05, 0.06), 0.6, 3.0, 0.0, Props.MOSS, false)
		for n in dais.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			var nm := str(mi.name).to_lower() + str(mi.get_parent().name).to_lower()
			if nm.contains("groove"):
				mi.material_override = groove_m
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif nm.contains("floor"):
				mi.material_override = floor_m
			elif nm.contains("socket"):
				mi.material_override = stone_d
				mi.set_meta("wp_socket", true)
			else:
				mi.material_override = stone
		groove_y = 0.335
	else:
		var tiers := [[DAIS_R, 0.06], [4.15, 0.18], [3.45, 0.30]]
		for t in tiers:
			Models.P(self, Geo.cyl(t[0] - 0.08, t[0], 0.12, 56), stone, Vector3(0, t[1], 0))
		for ti in tiers.size():
			var r: float = tiers[ti][0] - 0.24
			var n := int(TAU * r / 0.85)
			for i in n:
				var a := TAU * (i + rng.randf_range(-0.08, 0.08)) / n
				var blk := Models.P(self, Geo.box(0.78, 0.13, 0.42), stone if i % 3 else stone_d,
						Vector3(cos(a) * r, tiers[ti][1] + rng.randf_range(0.0, 0.02), sin(a) * r),
						Vector3(rng.randf_range(-1.5, 1.5), -rad_to_deg(a) + 90.0, 0))
				blk.scale = Vector3(rng.randf_range(0.9, 1.05), 1, 1)
		Models.P(self, Geo.cyl(3.1, 3.1, 0.03, 56), floor_m, Vector3(0, TOP_Y + 0.005, 0))

	# --- rune channels: three rings and eight spokes (in the carved channels: build_dais.py's FLOOR_RINGS gaps
	# 1.01-1.09, 1.92-2.02, 2.70-2.82 and its spokes), glyphs inlaid between the outer two
	var chans := [[2.8, 0.085], [2.0, 0.07], [1.08, 0.06]] if dais else [[2.8, 0.09], [2.0, 0.07], [1.08, 0.06]]
	for rr in chans:
		var rm := Mats.glow_unique(RUNE, IDLE)
		ring_mats.append(rm)
		var ring := Models.P(self, Geo.torus(rr[0] - rr[1], rr[0] - (0.012 if dais else 0.0), 72, 4), rm, Vector3(0, groove_y, 0))
		ring.scale = Vector3(1, 0.25, 1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the two lower steps' edges lit faintly (the picture's steps glow along their lips)
	for er in [[4.13, 0.245], [4.83, 0.125]]:
		var em := Mats.glow_unique(RUNE, IDLE * 0.5)
		edge_mats.append(em)
		var edge := Models.P(self, Geo.torus(er[0] - 0.03, er[0], 96, 4), em, Vector3(0, er[1], 0))
		edge.scale = Vector3(1, 0.2, 1)
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the rune lettering: rings of glowing glyphs and ornament on the flagstones (tools/waypoint_runes.py draws
	# them, one band per channel), lit from inside their carved strokes by RUNE_FLOOR_SHADER
	if ResourceLoader.exists(RUNES_TEX):
		rune_floor = ShaderMaterial.new()
		rune_floor.shader = _shader("rune_floor", RUNE_FLOOR_SHADER)
		rune_floor.set_shader_parameter("runes", load(RUNES_TEX))
		rune_floor.set_shader_parameter("glow", RUNE)
		rune_floor.set_shader_parameter("core", RUNE_CORE)
		var pm := PlaneMesh.new()
		pm.size = Vector2(RUNES_SPAN, RUNES_SPAN)
		var disc := MeshInstance3D.new()
		disc.mesh = pm
		disc.material_override = rune_floor
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.position = Vector3(0, TOP_Y + 0.012, 0)
		disc.extra_cull_margin = 1.0
		add_child(disc)
	else:
		var glyph_y := TOP_Y + (0.013 if dais else 0.025)
		for i in 28:
			var a := TAU * i / 28.0
			var g := Models.N(self, "glyph", Vector3(cos(a) * 2.36, glyph_y, sin(a) * 2.36), Vector3(0, -rad_to_deg(a), 0))
			Models.P(g, Geo.box(0.05, 0.012, 0.34), rune_mat)
			Models.P(g, Geo.box(0.05, 0.012, 0.2), rune_mat, Vector3(0, 0, 0.05 * (i % 3 - 1)), Vector3(0, 90 if i % 2 else 45, 0))
	if not dais:
		for i in 16:
			var a := TAU * (i + 0.5) / 16.0
			Models.P(self, Geo.box(0.04, 0.012, 0.22), rune_mat, Vector3(cos(a) * 1.55, TOP_Y + 0.025, sin(a) * 1.55),
					Vector3(0, -rad_to_deg(a) + (30 if i % 2 else -30), 0))
	for i in 8:
		var a := TAU * i / 8.0
		Models.P(self, Geo.box(0.035, 0.012, 0.8), rune_mat, Vector3(cos(a) * 1.505, groove_y, sin(a) * 1.505),
				Vector3(0, -rad_to_deg(a) + 90.0, 0))

	# --- the socket, the light column and the floating crystal (Meshy: its own carved socket, the crystal and the
	# orbiting shards; the dais's plain socket hides under it)
	var cm := Mats.mat(Color(0.06, 0.16, 0.45), 0.08, 0.3, Color(0.12, 0.42, 1.0), 0.65)
	var cry := _glb("crystal")
	crystal = Models.N(self, "crystal", Vector3(0, CRY_Y, 0))
	shards = Models.N(self, "shards", Vector3(0, CRY_Y - 0.3, 0))
	var socket_top := TOP_Y + 0.4
	if cry:
		var holder := Models.N(self, "crystal_model", Vector3(0, TOP_Y - 0.02, 0))
		holder.scale = Vector3.ONE * CRY_SCALE
		holder.add_child(cry)
		for n in cry.find_children("*", "Node3D", true, false):
			var nm := str(n.name).to_lower()
			if nm == "crystal" or nm == "shards":
				var piece: Node3D = n
				piece.get_parent().remove_child(piece)
				var host: Node3D = crystal if nm == "crystal" else shards
				host.scale = Vector3.ONE * CRY_SCALE * CRY_GROW
				host.add_child(piece)
				piece.position = Vector3.ZERO
				for g in piece.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# the rune crystal: dark faceted glass with the light inside it (CRYSTAL_SHADER on Meshy's texture)
				for g in piece.find_children("*", "MeshInstance3D", true, false):
					var mi: MeshInstance3D = g
					var base := mi.get_active_material(0)
					var cmat := ShaderMaterial.new()
					cmat.shader = _shader("crystal", CRYSTAL_SHADER)
					if base is StandardMaterial3D and (base as StandardMaterial3D).albedo_texture:
						cmat.set_shader_parameter("tex", (base as StandardMaterial3D).albedo_texture)
					cmat.set_shader_parameter("noise_tex", InfernalFx.noise())
					cmat.set_shader_parameter("cells_tex", InfernalFx.cells())
					cmat.set_shader_parameter("shard", 1.0 if nm == "shards" else 0.0)
					mi.material_override = cmat
					crystal_mats.append(cmat)
			elif nm == "socket":
				socket_top = TOP_Y - 0.02 + _bounds(n).end.y * CRY_SCALE
		for g in cry.find_children("*", "MeshInstance3D", true, false):
			var smi: MeshInstance3D = g
			var sb := smi.get_active_material(0)
			if sb is StandardMaterial3D and smi.material_override == null:
				var sm2: StandardMaterial3D = (sb as StandardMaterial3D).duplicate()
				sm2.albedo_color = Color(0.62, 0.64, 0.7)
				smi.material_override = sm2
		if dais:
			for n in dais.find_children("*", "MeshInstance3D", true, false):
				if n.has_meta("wp_socket"):
					(n as MeshInstance3D).visible = false
	else:
		Models.P(self, Geo.cyl(0.48, 0.66, 0.22, 8), stone_d, Vector3(0, TOP_Y + 0.11, 0))
		Models.P(self, Geo.torus(0.36, 0.44, 24, 4), rune_mat, Vector3(0, TOP_Y + 0.23, 0)).scale = Vector3(1, 0.3, 1)
		socket_top = TOP_Y + 0.25
		var k := CRY_SCALE * CRY_GROW
		Models.P(crystal, Geo.cyl(0.0, 0.44 * k, 1.15 * k, 6), cm, Vector3(0, 0.575 * k, 0))
		Models.P(crystal, Geo.cyl(0.44 * k, 0.0, 0.75 * k, 6), cm, Vector3(0, -0.375 * k, 0))
		Models.P(crystal, Geo.sph(0.2 * k, 10), Mats.glow(Color(0.45, 0.78, 1.0), 1.3), Vector3(0, 0.05, 0))
		Models.P(crystal, Geo.box(0.04, 0.42, 0.02), rune_mat, Vector3(0, 0.12, 0.33 * k), Vector3(-17, 0, 0))
		Models.P(crystal, Geo.box(0.26, 0.04, 0.02), rune_mat, Vector3(0, 0.2, 0.31 * k), Vector3(-17, 0, 0))
		for i in 5:
			var a := TAU * i / 5.0
			Models.P(shards, Geo.cyl(0.0, 0.09, 0.42, 5), cm, Vector3(cos(a) * 0.95 * k, sin(a * 2.0) * 0.25, sin(a) * 0.95 * k),
					Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-25, 25)))
	_cry_y = crystal.position.y
	_sh_y = shards.position.y
	# the column of light: a core shaft from the socket up through the crystal and on into the sky, a wider
	# sheath of slower light round it, and lightning crawling up both (COLUMN_SHADER, BOLTS_SHADER); its foot
	# blazes in the socket
	var col_h := COLUMN_TOP - socket_top
	var col_y := (COLUMN_TOP + socket_top) * 0.5
	column_mats.clear()
	for spec in [[0.14, 0.2, 1.0, 1.0, 1.0], [0.8, 0.5, 1.6, 0.55, 2.2]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = spec[0]
		cyl.bottom_radius = spec[1]
		cyl.height = col_h
		cyl.radial_segments = 20
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var m := ShaderMaterial.new()
		m.shader = _shader("column", COLUMN_SHADER)
		m.set_shader_parameter("noise_tex", InfernalFx.noise())
		m.set_shader_parameter("energy", spec[2])
		m.set_shader_parameter("rise", spec[3])
		m.set_shader_parameter("detail", spec[4])
		m.set_shader_parameter("col_a", RUNE)
		m.set_shader_parameter("col_b", RUNE_CORE)
		# the crystal's zone along the column (0 bottom .. 1 top): the shaft dims there so the glass reads
		var k := CRY_SCALE * CRY_GROW
		m.set_shader_parameter("dip", Vector2((CRY_Y - 1.0 * k - socket_top) / col_h, (CRY_Y + 1.0 * k - socket_top) / col_h))
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, col_y, 0)
		mi.extra_cull_margin = 2.0
		add_child(mi)
		column_mats.append(m)
	var bolts := CylinderMesh.new()
	bolts.top_radius = 0.5
	bolts.bottom_radius = 0.5
	bolts.height = col_h
	bolts.radial_segments = 24
	bolts.rings = 1
	bolts.cap_top = false
	bolts.cap_bottom = false
	bolt_mat = ShaderMaterial.new()
	bolt_mat.shader = _shader("bolts", BOLTS_SHADER)
	bolt_mat.set_shader_parameter("noise_tex", InfernalFx.noise())
	bolt_mat.set_shader_parameter("col_a", RUNE)
	bolt_mat.set_shader_parameter("col_b", RUNE_CORE)
	var bolt_mi := MeshInstance3D.new()
	bolt_mi.mesh = bolts
	bolt_mi.material_override = bolt_mat
	bolt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt_mi.position = Vector3(0, col_y, 0)
	bolt_mi.extra_cull_margin = 2.0
	add_child(bolt_mi)
	# on High and Ultra (volumetric fog) the shaft also glows in the air itself: a FogVolume up the column, and a
	# wider, thinner cold haze lying over the dais
	# (FogVolume is Forward+ only: the OpenGL renderer and the browser log an error for it, so none there)
	var fogs: Array = [] if RenderingServer.get_rendering_device() == null else [
			[Vector3(1.6, col_h, 1.6), col_y, 0.25, Color(0.1, 0.35, 1.0) * 0.9, 0.5],
			[Vector3(13.0, 3.0, 13.0), TOP_Y + 1.0, 0.045, Color(0.05, 0.16, 0.45) * 0.3, 0.8]]
	for fspec in fogs:
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		fv.size = fspec[0]
		var fm := FogMaterial.new()
		fm.density = fspec[2]
		fm.albedo = Color(0.5, 0.65, 0.9)
		fm.emission = fspec[3]
		fm.edge_fade = fspec[4]
		fv.material = fm
		fv.position = Vector3(0, fspec[1], 0)
		add_child(fv)
		fog_mats.append(fm)
	# arcs crackling over the crystal: quads round it, each a bolt that strikes, holds a moment and is gone
	for i in ARCS:
		var q := MeshInstance3D.new()
		q.mesh = InfernalFx.quad()
		var am := ShaderMaterial.new()
		am.shader = _shader("arc", ARC_SHADER)
		am.set_shader_parameter("noise_tex", InfernalFx.noise())
		am.set_shader_parameter("col_a", RUNE)
		am.set_shader_parameter("col_b", RUNE_CORE)
		am.set_shader_parameter("seed", randf() * 20.0)
		am.set_shader_parameter("life", 0.0)
		q.material_override = am
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.extra_cull_margin = 2.0
		var a := TAU * i / ARCS
		q.position = Vector3(cos(a) * 0.4, randf_range(-0.9, 0.9), sin(a) * 0.4)
		q.rotation = Vector3(randf_range(-0.5, 0.5), -a + PI * 0.5, randf_range(-0.6, 0.6))
		q.scale = Vector3(1.25, 1.0, 1.0)
		crystal.add_child(q)
		arcs.append({"m": am, "n": q, "t": randf() * 1.5, "hold": 0.0})
	# the socket's blaze: a glow in the socket's mouth and a hot core in the crystal's heart
	var foot := _glow_quad(self, Vector3(0, socket_top + 0.05, 0), 1.3, InfernalFx.glow_mat(Color(0.4, 0.7, 1.0), 1.0, 2.6))
	glow_mats.append(foot.material_override)
	var cry_heart := _glow_quad(crystal, Vector3.ZERO, 2.6 / (CRY_SCALE * CRY_GROW), InfernalFx.glow_mat(Color(0.3, 0.6, 1.0), 0.55, 3.2))
	glow_mats.append(cry_heart.material_override)
	# sparks rising inside the column and motes drifting round the crystal
	column_sparks = Fx.aura(self, Color(0.5, 0.8, 1.0), 48, 3.2, 0.045, 2.4, 1.2, 0.18, 8.0, Vector3(0, socket_top + 0.2, 0))
	motes_high = Fx.aura(self, Color(0.3, 0.6, 1.0), 40, 0.5, 0.07, 3.0, 0.1, 1.4, 60.0, Vector3(0, CRY_Y - 0.5, 0))
	light = OmniLight3D.new()
	light.light_color = Color(0.4, 0.64, 1.0)
	light.light_energy = 4.8
	light.omni_range = 15.0
	light.omni_attenuation = 1.1
	light.light_volumetric_fog_energy = 3.0
	light.position = Vector3(0, _cry_y - 0.4, 0)
	light.set_meta("base", light.light_energy)
	light.add_to_group(Grade.SHADOW_GROUP)
	add_child(light)
	# the rune floor's own light: low, so it rakes up the steps, the statues and whoever stands on the dais
	light_low = OmniLight3D.new()
	light_low.light_color = Color(0.25, 0.5, 1.0)
	light_low.light_energy = 3.0
	light_low.omni_range = 11.0
	light_low.omni_attenuation = 1.4
	light_low.light_volumetric_fog_energy = 1.0
	light_low.position = Vector3(0, TOP_Y + 0.9, 0)
	light_low.set_meta("base", light_low.light_energy)
	add_child(light_low)

	# --- four braziers with blue fire on the middle step
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var b := Models.N(self, "brazier", Vector3(cos(a) * 3.9, 0.24, sin(a) * 3.9))
		var fire_y := 1.16
		var bm := _put(b, "brazier", Vector3.ZERO, rad_to_deg(-a) - 90.0, BRAZIER_SCALE)
		if bm:
			fire_y = _bounds(bm).end.y * BRAZIER_SCALE - 0.1
		else:
			Models.P(b, Geo.box(0.8, 0.28, 0.8), stone_d, Vector3(0, 0.14, 0))
			Models.P(b, Geo.lathe([Vector2(0.0, 0.28), Vector2(0.3, 0.28), Vector2(0.22, 0.4), Vector2(0.17, 0.85),
					Vector2(0.24, 0.95), Vector2(0.0, 0.95)], 10, "wp_brazier_col"), stone, Vector3.ZERO)
			Models.P(b, Geo.lathe([Vector2(0.12, 0.95), Vector2(0.42, 1.08), Vector2(0.5, 1.22), Vector2(0.44, 1.22),
					Vector2(0.36, 1.12), Vector2(0.0, 1.1)], 16, "wp_brazier_bowl"), iron, Vector3.ZERO)
		# blue spirit-fire: the game's simulated fire (FireFx "spirit": a Mantaflow fire rendered violet / electric
		# blue / cyan-white, played on flame particles so no two flames are in step), blue embers and sparks, and a
		# cold flickering light on the stones
		if ResourceLoader.exists(FireFx.BOOKS["spirit"]):
			var fire := FireFx.make(b, Vector3(0, fire_y - 0.06, 0), "spirit", 0.85, Color(0.3, 0.55, 1.0), true, false, false)
			# the fire's cold light may cast shadows (Grade gives the nearest lights the preset's shadow budget)
			var fl := fire.get_node_or_null("FireLight")
			if fl:
				fl.add_to_group(Grade.SHADOW_GROUP)
			# the white-hot heart down in the bowl, breathing with the fire (see _process)
			var heart := MeshInstance3D.new()
			heart.mesh = InfernalFx.quad()
			var hm := InfernalFx.glow_mat(Color(0.32, 0.62, 1.0), 1.1, 2.6)
			heart.material_override = hm
			heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			heart.extra_cull_margin = 2.0
			heart.position = Vector3(0, fire_y + 0.06, 0)
			heart.scale = Vector3.ONE * 0.75
			b.add_child(heart)
			hearts.append(hm)
		else:
			# without the spirit book the simulated fire would be the orange body book: keep the particle flames
			Fx.aura(b, Color(0.3, 0.62, 1.0, 0.9), 18, 0.9, 0.17, 0.55, 1.8, 0.12, 12.0, Vector3(0, fire_y, 0), false)
			Fx.aura(b, Color(0.06, 0.28, 0.95, 0.75), 12, 1.3, 0.28, 0.8, 1.2, 0.2, 20.0, Vector3(0, fire_y + 0.04, 0), false)
			Fx.aura(b, Color(0.1, 0.4, 1.0), 6, 1.8, 0.04, 1.6, 0.8, 0.2, 30.0, Vector3(0, fire_y + 0.14, 0))
	# the braziers' blue fire mirrored in the dais's puddles (wet_stone): the fire sits where its node is
	for n in get_children():
		if str(n.name).begins_with("brazier"):
			var bz: Node3D = n
			var fy := 1.16
			for c in bz.get_children():
				if c is Node3D and (str(c.name) == "Fire" or c is GPUParticles3D):
					fy = (c as Node3D).position.y
					break
			mirrors.append([bz.position + Vector3(0, fy + 0.2, 0), Color(0.3, 0.55, 1.0), 0.9])

	# --- two hooded guardians with spears, on plinths at the back corners, facing the dais
	for sx in [-1.0, 1.0]:
		var s := Models.N(self, "guardian", Vector3(GUARDIAN_AT.x * sx, 0, GUARDIAN_AT.z), Vector3(0, -24.0 * sx, 0))
		if _put(s, "guardian", Vector3.ZERO, 0.0):
			continue
		Models.P(s, Geo.box(1.5, 0.35, 1.5), stone_d, Vector3(0, 0.175, 0))
		Models.P(s, Geo.box(1.2, 1.0, 1.2), stone, Vector3(0, 0.85, 0))
		Models.P(s, Geo.box(1.45, 0.16, 1.45), stone_d, Vector3(0, 1.43, 0))
		var f := Models.N(s, "figure", Vector3(0, 1.51, 0))
		Models.P(f, Geo.cyl(0.3, 0.62, 2.1, 12), statue_m, Vector3(0, 1.05, 0))            # robe
		Models.P(f, Geo.sph(0.42, 12), statue_m, Vector3(0, 2.12, 0), Vector3.ZERO, Vector3(1.3, 0.75, 0.9))  # shoulders
		Models.P(f, Geo.sph(0.31, 12), statue_m, Vector3(0, 2.5, 0.02), Vector3(-8, 0, 0), Vector3(1.0, 1.2, 1.1))  # hood
		Models.P(f, Geo.sph(0.2, 10), Mats.mat(Color(0.03, 0.03, 0.04), 1.0), Vector3(0, 2.43, 0.17), Vector3.ZERO, Vector3(1, 1.2, 0.6))  # shadowed face
		Models.P(f, Geo.cap(0.12, 0.95), statue_m, Vector3(0.36 * sx, 1.75, 0.18), Vector3(-30, 0, 18 * sx))  # spear arm
		Models.P(f, Geo.cap(0.11, 0.8), statue_m, Vector3(-0.3 * sx, 1.7, 0.22), Vector3(-55, 0, -25 * sx))  # other arm across
		Models.P(f, Geo.cyl(0.035, 0.045, 4.3, 6), iron, Vector3(0.52 * sx, 1.9, 0.32))     # spear shaft
		Models.P(f, Geo.cyl(0.0, 0.1, 0.5, 4), iron, Vector3(0.52 * sx, 4.3, 0.32))         # spearhead

	# --- four red banners along the back, two a side between the torches and the guardians
	var cloth := Mats.mat(Color(0.42, 0.05, 0.04), 0.9)
	var gold := Mats.mat(Color(0.75, 0.55, 0.22), 0.35, 0.9)
	for bi in 4:
		var sx := -1.0 if bi < 2 else 1.0
		var spec: Array = BANNERS[bi % 2]
		var bn := Models.N(self, "banner", Vector3(spec[0] * sx, 0, spec[1]), Vector3(0, 8.0 * sx * (bi % 2), 0))
		var bmod := _put(bn, "banner", Vector3.ZERO, 0.0, spec[2])
		if bmod:
			# Meshy's cloth is a dark oxblood that the crystal's cold light turns navy: warm it so it stays red
			for g in bmod.find_children("*", "MeshInstance3D", true, false):
				var bmi: MeshInstance3D = g
				var bb := bmi.get_active_material(0)
				if bb is StandardMaterial3D:
					var bm2: StandardMaterial3D = (bb as StandardMaterial3D).duplicate()
					bm2.albedo_color = Color(1.9, 1.05, 0.9)
					bmi.material_override = bm2
			continue
		Models.P(bn, Geo.cyl(0.05, 0.06, 4.4, 8), iron, Vector3(0, 2.2, 0))
		Models.P(bn, Geo.cyl(0.0, 0.08, 0.3, 4), iron, Vector3(0, 4.55, 0))
		Models.P(bn, Geo.box(1.1, 0.06, 0.06), iron, Vector3(0, 4.0, 0))
		Models.P(bn, Geo.box(0.95, 2.1, 0.03), cloth, Vector3(0, 2.92, 0.05))
		Models.P(bn, Geo.box(0.08, 0.7, 0.04), gold, Vector3(0, 3.1, 0.08))
		Models.P(bn, Geo.box(0.42, 0.08, 0.04), gold, Vector3(0, 3.25, 0.08))
		Models.P(bn, Geo.prism(0.95, 0.35, 0.03), cloth, Vector3(0, 1.7, 0.05), Vector3(0, 0, 180))

	# --- a broken stone wall arcing round the back, framing the dais
	var pillars := ResourceLoader.exists(DIR + "pillar.glb")
	for i in 9:
		var a := deg_to_rad(WALL_A0 + i * WALL_STEP)
		if i == 4 or i == 1 or i == 7:
			continue  # gaps: behind the crystal, between the banners, and where the guardians stand
		var at := Vector3(cos(a) * WALL_R, 0, sin(a) * WALL_R)
		if pillars and i in [0, 8]:
			# the wall's ends: the rune-carved ruined pillar, turned so its runes face the dais
			_put(self, "pillar", at, rad_to_deg(atan2(-at.x, -at.z)) + (25.0 if i == 0 else -25.0))
			continue
		var hgt := rng.randf_range(0.45, 1.25) if i not in [0, 8] else rng.randf_range(1.6, 2.2)
		Models.P(self, Geo.box(1.25, hgt, 0.55), stone if i % 2 else stone_d,
				at + Vector3(0, hgt * 0.5, 0), Vector3(0, -rad_to_deg(a) + 90.0, rng.randf_range(-3, 3)))
	if not pillars:
		# toppled pillar drums
		for d in [[-3.2, -6.4, 0.0], [3.6, -6.6, 1.2], [6.1, -1.4, 0.6]]:
			Models.P(self, Geo.cyl(0.34, 0.36, 0.7, 10), stone, Vector3(d[0], 0.34, d[1]), Vector3(90, rad_to_deg(d[2]), 0))

	# --- two fire bowls flanking the approach: the brazier's stone column and iron bowl with a real fire
	for sx in [-1.0, 1.0]:
		var fb := Models.N(self, "firebowl", Vector3(FIRE_BOWLS.x * sx, 0, FIRE_BOWLS.z))
		var bowl_y := 1.16 * BOWL_SCALE
		var fbm := _put(fb, "brazier", Vector3.ZERO, 180.0 + 20.0 * sx, BOWL_SCALE)
		if fbm:
			bowl_y = _bounds(fbm).end.y * BOWL_SCALE - 0.08
		else:
			Models.P(fb, Geo.box(0.9, 0.3, 0.9), stone_d, Vector3(0, 0.15, 0))
			Models.P(fb, Geo.cyl(0.2, 0.3, 1.0, 10), stone, Vector3(0, 0.8, 0))
			Models.P(fb, Geo.lathe([Vector2(0.12, 1.3), Vector2(0.5, 1.42), Vector2(0.58, 1.58), Vector2(0.5, 1.58),
					Vector2(0.42, 1.46), Vector2(0.0, 1.44)], 16, "wp_bowl"), iron, Vector3.ZERO)
			bowl_y = 1.5
		var wf := Props.fire(fb, Vector3(0, bowl_y, 0), 0.8, Color(1.0, 0.55, 0.2), true, false, true, "brazier")
		var wl := wf.get_node_or_null("FireLight")
		if wl:
			wl.add_to_group(Grade.SHADOW_GROUP)
		mirrors.append([fb.position + Vector3(0, bowl_y + 0.3, 0), Color(1.0, 0.5, 0.18), 1.0])

	# --- two warm iron torches in the wall's gap behind the crystal
	for sx in [-1.0, 1.0]:
		var tp := Models.N(self, "torch", Vector3(TORCH_AT.x * sx, 0, TORCH_AT.z))
		var flame_y := 2.12
		var tm := _put(tp, "torch", Vector3.ZERO, 0.0)
		if tm:
			flame_y = _bounds(tm).end.y - 0.04
		else:
			Models.P(tp, Geo.cyl(0.04, 0.06, 1.9, 6), iron, Vector3(0, 0.95, 0))
			Models.P(tp, Geo.lathe([Vector2(0.04, 1.85), Vector2(0.17, 2.05), Vector2(0.2, 2.15), Vector2(0.0, 2.1)], 8, "wp_torch_cup"), iron)
		Props.fire(tp, Vector3(0, flame_y, 0), 0.4, Color(1.0, 0.55, 0.2), true, false, true)
		mirrors.append([tp.position + Vector3(0, flame_y + 0.15, 0), Color(1.0, 0.5, 0.18), 0.8])

	# motes of energy drifting up off the dais, slow and sparse, and a few brighter ones spiralling up the column
	motes = Fx.aura(self, Color(0.2, 0.5, 1.0), 44, 0.3, 0.06, 4.5, 0.12, 3.0, 20.0, Vector3(0, TOP_Y + 0.1, 0))
	# low mist creeping over the steps and the paving round the dais: big slow soft puffs (InfernalFx's smoke
	# shader in a cold grey-blue, lit faintly from the column), a veil rather than smoke
	var mm := InfernalFx.smoke_mat(0.35, 0.4)
	mm.set_shader_parameter("smoke", Color(0.5, 0.58, 0.7))
	mm.set_shader_parameter("glow_col", Color(0.2, 0.45, 1.0))
	var mq := QuadMesh.new()
	mq.size = Vector2(4.2, 4.2)
	mq.material = mm
	mist = InfernalFx.particles(self, Vector3(0, 0.35, 0), {"amount": 34, "life": 11.0, "one_shot": false, "explosive": 0.0,
		"randomness": 0.6, "shape": "ring", "r": 5.6, "r_in": 2.4, "dir": Vector3(1, 0.05, 0), "spread": 180.0,
		"vel": [0.12, 0.3], "gravity": 0.01, "damping": [0.02, 0.06], "scale": [0.8, 1.3], "grow": [0.7, 1.25],
		"angle": true, "spin": 3.0, "mesh": mq,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.75)], [0.7, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]]})
	mist.visibility_aabb = AABB(Vector3(-9, -1, -9), Vector3(18, 5, 18))
	mist.preprocess = 9.0
	motes.preprocess = 4.0
	motes_high.preprocess = 3.0
	column_sparks.preprocess = 2.0

## The activation burst (a hero arrives by it, or opens the travel window at it).
func pulse() -> void:
	_flash = 1.0
	var root := get_parent() as Node3D
	if root == null:
		return
	Fx.ring(root, global_position + Vector3(0, TOP_Y + 0.05, 0), 3.2, RUNE, 0.7, 0.2)
	Fx.burst(root, global_position + Vector3(0, 1.0, 0), Color(0.2, 0.55, 1.0), 30, 3.5, 0.08, 1.0, true, 1.5, 35.0)
	Fx.flash(root, global_position + Vector3(0, 2.2, 0), Color(0.45, 0.7, 1.0), 3.5, 0.9, 9.0)

func _nearest_hero() -> float:
	var best := INF
	for h in get_tree().get_nodes_in_group("hero"):
		if h is Node3D:
			best = minf(best, (h as Node3D).global_position.distance_to(global_position))
	return best

func _process(delta: float) -> void:
	_t += delta
	var d := _nearest_hero()
	if not _arrival_checked and _t > 0.4:
		_arrival_checked = true
		if d < 4.5:
			pulse()   # arrived by this waypoint
	var want := clampf(1.0 - (d - 3.5) / (WAKE_R - 3.5), 0.0, 1.0)
	_wake = move_toward(_wake, want, delta * (0.9 if want > _wake else 0.4))
	_flash = maxf(_flash - delta * 1.1, 0.0)
	var pulse_w := 0.5 + 0.5 * sin(_t * (1.4 + _wake * 1.6))
	# the channels light outer -> inner as a hero comes closer, each riding its own phase of the pulse
	for i in ring_mats.size():
		var on := smoothstep(i * 0.25, i * 0.25 + 0.5, _wake)
		var ph := 0.5 + 0.5 * sin(_t * 2.2 - i * 0.9)
		ring_mats[i].set_shader_parameter("energy", lerpf(IDLE, NEAR, on) * (0.8 + 0.3 * ph) + _flash * 0.8)
	rune_mat.set_shader_parameter("energy", lerpf(IDLE * 0.8, NEAR * 0.85, smoothstep(0.3, 1.0, _wake)) * (0.85 + 0.2 * pulse_w) + _flash * 0.6)
	for i in edge_mats.size():
		edge_mats[i].set_shader_parameter("energy", lerpf(0.09, 0.26, _wake) * (0.85 + 0.15 * sin(_t * 1.6 + i * 2.0)) + _flash * 0.5)
	if rune_floor:
		# the lettering: lit always (the camp's centrepiece), brighter band by band as a hero comes, outer first
		var names := ["e_outer", "e_great", "e_ornate", "e_inner"]
		for i in 4:
			var on := smoothstep(i * 0.2, i * 0.2 + 0.45, _wake)
			var ph := 0.5 + 0.5 * sin(_t * 1.6 - i * 1.1)
			rune_floor.set_shader_parameter(names[i], lerpf(RUNES_IDLE, RUNES_NEAR, on) * (0.88 + 0.12 * ph) + _flash * 1.2)
		rune_floor.set_shader_parameter("rot_outer", _t * 0.012 + _spin * 0.01)
		rune_floor.set_shader_parameter("rot_inner", -_t * 0.03 - _spin * 0.02)
		# a pulse running out from the socket over the runes, oftener with a hero near
		_wave_t -= delta
		if _wave < 0.0 and _wave_t <= 0.0:
			_wave = 0.0
			_wave_t = lerpf(7.0, 3.2, _wake) + randf() * 1.5
		if _wave >= 0.0:
			_wave += delta * 3.4
			if _wave > 4.2:
				_wave = -1.0
		if _flash > 0.9:
			_wave = 0.0
		rune_floor.set_shader_parameter("wave_r", _wave if _wave >= 0.0 else -10.0)
	# the crystal, the column and the arcs
	var cry_e := lerpf(0.75, 1.3, _wake) * (0.92 + 0.08 * pulse_w) + _flash * 1.5
	for cmat in crystal_mats:
		cmat.set_shader_parameter("energy", cry_e)
	for i in column_mats.size():
		column_mats[i].set_shader_parameter("energy", (1.0 if i == 0 else 0.42) * (lerpf(0.7, 1.25, _wake) + _flash * 1.2))
	bolt_mat.set_shader_parameter("energy", lerpf(0.6, 1.2, _wake) + _flash * 1.5)
	for gm in glow_mats:
		gm.set_shader_parameter("energy", lerpf(0.7, 1.1, _wake) * (0.9 + 0.1 * pulse_w) + _flash * 1.2)
	for arc in arcs:
		arc["t"] -= delta
		var am: ShaderMaterial = arc["m"]
		if arc["hold"] > 0.0:
			arc["hold"] -= delta
			am.set_shader_parameter("life", clampf(arc["hold"] / 0.12, 0.0, 1.0) * (0.75 + 0.25 * sin(_t * 61.0)))
			if arc["hold"] <= 0.0:
				am.set_shader_parameter("life", 0.0)
		elif arc["t"] <= 0.0:
			# a new strike: new path, somewhere else round the crystal, then quiet for a while
			am.set_shader_parameter("seed", randf() * 20.0)
			var q: Node3D = arc["n"]
			var a := randf() * TAU
			q.position = Vector3(cos(a) * 0.4, randf_range(-0.85, 0.85), sin(a) * 0.4)
			q.rotation = Vector3(randf_range(-0.5, 0.5), -a + PI * 0.5, randf_range(-0.7, 0.7))
			arc["hold"] = randf_range(0.14, 0.4)
			arc["t"] = randf_range(0.3, 1.8) / lerpf(0.6, 1.6, _wake) * (0.25 if _flash > 0.3 else 1.0)
	light_low.light_energy = float(light_low.get_meta("base")) * lerpf(0.65, 1.2, _wake) * (0.92 + 0.08 * pulse_w) + _flash * 2.0
	column_sparks.amount_ratio = lerpf(0.5, 1.0, _wake)
	for fm in fog_mats:
		var fmat: FogMaterial = fm
		if not fmat.has_meta("base"):
			fmat.set_meta("base", fmat.emission)
		fmat.emission = (fmat.get_meta("base") as Color) * (lerpf(0.7, 1.15, _wake) * (0.94 + 0.06 * pulse_w) + _flash * 1.5)
	_spin += delta * lerpf(0.3, 1.3, _wake) + delta * _flash * 4.0
	crystal.rotation.y = _spin
	var bob := sin(_t * 1.1) * lerpf(0.1, 0.18, _wake)
	crystal.position.y = _cry_y + bob
	shards.rotation.y = -_spin * 1.6
	shards.position.y = _sh_y + bob
	shards.scale = Vector3.ONE * CRY_SCALE * CRY_GROW * lerpf(1.0, 1.2, _wake) * (1.0 + _flash * 0.3)
	light.light_energy = float(light.get_meta("base")) * lerpf(0.6, 1.25, _wake) * (0.9 + 0.15 * pulse_w) + _flash * 3.0
	motes.amount_ratio = lerpf(0.35, 1.0, _wake)
	for i in hearts.size():
		var fl := 0.8 + 0.12 * sin(_t * 7.3 + i * 1.9) + 0.08 * sin(_t * 13.1 + i * 4.3)
		hearts[i].set_shader_parameter("energy", 1.1 * fl + _flash * 0.6)

## The rune floor: a plane over the dais's top sampling tools/waypoint_runes.py's masks (R the outer rim ring and
## the inner ring, G the great ring, B the ornate band), each band with its own energy and turn. A stroke is lit
## from its heart (`core`, the sharp mask) out through a halo (`glow`, the mask's blurred mips), and the stone
## round it is darkened a little, so the lettering reads as carved grooves with light down in them. A pulse ring
## (`wave_r`) runs out over the runes now and then, and a slow shimmer travels round the rings.
const RUNE_FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D runes : filter_linear_mipmap, repeat_disable;
uniform vec3 glow : source_color = vec3(0.04, 0.3, 1.0);
uniform vec3 core : source_color = vec3(0.62, 0.9, 1.0);
uniform float span = 7.0;
uniform float e_outer = 0.6;
uniform float e_great = 0.6;
uniform float e_ornate = 0.6;
uniform float e_inner = 0.6;
uniform float rot_outer = 0.0;
uniform float rot_great = 0.0;
uniform float rot_inner = 0.0;
uniform float wave_r = -10.0;
uniform float wave_w = 0.55;
uniform float carve = 0.45;
varying vec2 pm;
vec2 turn(vec2 p, float a) { float c = cos(a); float s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }
void vertex() {
	pm = (UV - 0.5) * span;
}
void fragment() {
	float r = length(pm);
	float ang = atan(pm.y, pm.x);
	// each band sampled with its own turn: sharp mask, a tight halo and a wide one
	vec2 uvo = turn(pm, rot_outer) / span + 0.5;
	vec2 uvg = turn(pm, rot_great) / span + 0.5;
	vec2 uvi = turn(pm, rot_inner) / span + 0.5;
	vec2 uvb = pm / span + 0.5;
	vec3 m = vec3(0.0); vec3 h1 = vec3(0.0); vec3 h2 = vec3(0.0);
	if (r > 2.74) {
		m.r = texture(runes, uvo).r; h1.r = textureLod(runes, uvo, 2.5).r; h2.r = textureLod(runes, uvo, 5.0).r;
	} else if (r < 1.06) {
		m.r = texture(runes, uvi).r; h1.r = textureLod(runes, uvi, 2.5).r; h2.r = textureLod(runes, uvi, 5.0).r;
	}
	if (r > 1.95 && r < 2.78) {
		m.g = texture(runes, uvg).g; h1.g = textureLod(runes, uvg, 2.5).g; h2.g = textureLod(runes, uvg, 5.0).g;
	}
	if (r > 1.04 && r < 1.98) {
		m.b = texture(runes, uvb).b; h1.b = textureLod(runes, uvb, 2.5).b; h2.b = textureLod(runes, uvb, 5.0).b;
	}
	// the bands' energies
	float eo = r > 2.0 ? e_outer : e_inner;
	vec3 e = vec3(eo, e_great, e_ornate);
	// a shimmer travelling round the rings, and the pulse ring running outward
	float shimmer = 0.86 + 0.14 * sin(TIME * 1.7 - ang * 3.0 + r * 2.5) * sin(TIME * 0.9 + ang * 2.0);
	float wave = exp(-pow((r - wave_r) / wave_w, 2.0)) * step(0.0, wave_r);
	e = (e * shimmer + wave * 1.4);
	float mk = dot(m, e);
	float halo = dot(h1, e) * 0.4 + dot(h2, e) * 0.12;
	// colour: the heart of a stroke pale and bright, the halo round it deep blue and never white
	vec3 col = mix(glow, core, smoothstep(0.35, 1.0, mk)) * mk * 1.25 + glow * halo;
	float lit = mk * 1.25 + halo;
	// the carved groove: the stone darkened round each stroke where the light is faint
	float groove = smoothstep(0.03, 0.3, dot(h1, vec3(1.0))) * (1.0 - clamp(mk, 0.0, 1.0));
	float dark = carve * groove * (1.0 - clamp(lit * 0.6, 0.0, 1.0));
	// coverage follows the light up to 1; past that the colour itself brightens (into the bloom) at half rate
	float a = clamp(lit, 0.0, 1.0);
	float at = clamp(a + dark, 0.0, 1.0);
	vec3 pure = col / max(lit, 0.001);
	float inten = a + 0.5 * max(lit - 1.0, 0.0);
	ALBEDO = at > 0.001 ? pure * inten / at : vec3(0.0);
	ALPHA = at;
}
"""

## The rune crystal and its shards on Meshy's texture: the blue glass darkened to a deep faceted navy, the pale
## cracks and the rune it painted taken as the light inside (`veins`), energy crawling through the facets along
## cell borders, a cold rim, the heart brightest; `energy` from the wake and the flash.
const CRYSTAL_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cells_tex : repeat_enable, filter_linear_mipmap;
uniform float energy = 1.0;
uniform float shard = 0.0;
uniform vec3 deep : source_color = vec3(0.012, 0.03, 0.12);
uniform vec3 glow : source_color = vec3(0.08, 0.4, 1.0);
uniform vec3 core : source_color = vec3(0.62, 0.9, 1.0);
varying vec3 lpos;
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	vec3 t = texture(tex, UV).rgb;
	float lum = dot(t, vec3(0.3, 0.59, 0.11));
	float veins = smoothstep(0.42, 0.78, lum);
	// energy crawling along the facets: cell borders scrolling up the crystal, flickering
	vec2 cuv = vec2(lpos.x * 0.8 + lpos.z * 0.6, lpos.y * 0.45 - TIME * 0.22);
	float cell = texture(cells_tex, cuv).r;
	float fl = texture(noise_tex, vec2(TIME * 0.9, lpos.y * 0.3 + lpos.x * 0.2)).r;
	float crawl = smoothstep(0.1, 0.0, cell) * smoothstep(0.35, 0.75, fl);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float heart = 1.0 - smoothstep(0.15, 0.95, length(lpos * vec3(1.6, 0.75, 1.6)));
	ALBEDO = mix(deep, t * 0.35, 0.25);
	ROUGHNESS = 0.16;
	SPECULAR = 0.65;
	float e = energy;
	if (shard > 0.5) {
		EMISSION = glow * (0.5 + veins * 0.9 + fres * 0.6) * e + core * veins * 0.3 * e;
	} else {
		EMISSION = glow * (veins * 2.6 + fres * 1.1 + heart * 0.35 + 0.05) * e + core * (crawl * 1.6 + veins * (0.4 + heart * 0.9)) * e;
	}
}
"""

## The column of light: on a cylinder's side (UV.y 0 at the top .. 0.5 at the bottom), streaks of noise rising,
## the shaft brightest through its middle (facing the view) and soft at its silhouette, fading toward the top.
const COLUMN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.04, 0.3, 1.0);
uniform vec3 col_b : source_color = vec3(0.62, 0.9, 1.0);
uniform float energy = 1.0;
uniform float rise = 1.0;
uniform float detail = 1.0;
uniform vec2 dip = vec2(-1.0, -1.0);
void fragment() {
	float h = 1.0 - UV.y * 2.0;
	float in_dip = smoothstep(dip.x - 0.04, dip.x + 0.04, h) * (1.0 - smoothstep(dip.y - 0.04, dip.y + 0.04, h));
	float n1 = texture(noise_tex, vec2(UV.x * 3.0 * detail, h * 0.4 * detail - TIME * 0.4 * rise)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 7.0 * detail + 0.3, h * 1.1 * detail - TIME * 0.85 * rise)).r;
	float streak = smoothstep(0.3, 0.85, n1 * 0.6 + n2 * 0.5);
	float facing = abs(dot(NORMAL, VIEW));
	float body = pow(facing, 1.4);
	float top_fade = 1.0 - smoothstep(0.62, 1.0, h);
	float bot_fade = smoothstep(0.0, 0.05, h);
	float a = (0.25 + 0.75 * streak) * body * top_fade * bot_fade * energy * 0.6 * (1.0 - 0.82 * in_dip);
	vec3 c = mix(col_a, col_b, clamp(streak * 0.5 + 0.4 * pow(facing, 4.0) * (1.0 - h * 0.6), 0.0, 1.0));
	ALBEDO = c * (0.65 + 0.4 * energy);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

## Lightning up the column: three bolts wandering up the cylinder (UV.x round it), each jumping to a new path and
## flickering on and off on its own clock, brightest low down, fading with the column's top.
const BOLTS_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.04, 0.3, 1.0);
uniform vec3 col_b : source_color = vec3(0.62, 0.9, 1.0);
uniform float energy = 1.0;
float bolt(vec2 uv, float id, out float core) {
	float h = 1.0 - uv.y * 2.0;
	float tick = floor(TIME * 9.0 + id * 3.0);
	float u0 = fract(id * 0.618 + floor(TIME * 0.7 + id) * 0.371);
	float w = (texture(noise_tex, vec2(h * 1.8 + id * 3.1, tick * 0.173)).r - 0.5) * 0.3
		+ (texture(noise_tex, vec2(h * 7.5 + id * 7.7, tick * 0.29)).r - 0.5) * 0.09;
	float du = abs(fract(uv.x - u0 - w + 0.5) - 0.5) * 3.14;
	core = exp(-du * du / 0.0036);
	float g = exp(-du / 0.18);
	float gate = smoothstep(0.44, 0.52, texture(noise_tex, vec2(TIME * 1.9 + id * 5.3, id * 0.37)).r);
	float tall = 1.0 - smoothstep(0.6, 1.0, h);
	return (core * 2.2 + g * 0.7) * gate * tall;
}
void fragment() {
	float c0; float c1; float c2;
	float b = bolt(UV, 1.0, c0) + bolt(UV, 2.0, c1) + bolt(UV, 3.0, c2);
	float core = c0 + c1 + c2;
	float h = 1.0 - UV.y * 2.0;
	ALBEDO = mix(col_a, col_b, clamp(core, 0.0, 1.0)) * (1.2 + 0.8 * energy);
	ALPHA = clamp(b * energy * smoothstep(0.0, 0.06, h), 0.0, 1.0);
}
"""

## An arc over the crystal: a quad with one bolt across it (pinned at both ends, wandering by `seed`), a fork
## off it, lit by `life` (0 off .. 1 the strike).
const ARC_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.04, 0.3, 1.0);
uniform vec3 col_b : source_color = vec3(0.62, 0.9, 1.0);
uniform float seed = 0.0;
uniform float life = 0.0;
void fragment() {
	vec2 p = UV;
	float n = (texture(noise_tex, vec2(p.x * 1.6 + seed, seed * 0.37)).r - 0.5) * 0.6
		+ (texture(noise_tex, vec2(p.x * 6.0 + seed * 2.0, seed * 0.71)).r - 0.5) * 0.2
		+ (texture(noise_tex, vec2(p.x * 22.0 + seed * 3.0, seed * 0.13)).r - 0.5) * 0.06;
	float y = 0.5 + n * sin(p.x * 3.14159);
	float d = abs(p.y - y);
	float core = exp(-d * d / 0.0025);
	float g = exp(-d * 12.0);
	float ends = smoothstep(0.0, 0.1, p.x) * smoothstep(1.0, 0.9, p.x);
	float yf = y + (p.x - 0.45) * 0.9 * sign(n + 0.001);
	float df = abs(p.y - yf);
	float fork = exp(-df * df / 0.0015) * smoothstep(0.45, 0.5, p.x) * smoothstep(0.9, 0.55, p.x) * 0.7;
	float a = (core + g * 0.3 + fork) * ends * life;
	ALBEDO = mix(col_a, col_b, clamp((core + fork) * 0.7, 0.0, 1.0)) * 1.3;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

## Wet stone: the game's prop shader (Mats.PROP_SHADER) with rain still standing on the dais. Large-scale noise
## lays puddles (glassy, dark) in damp stone (darker, less rough), and the puddles mirror the lights the camera
## would see in them without screen-space reflections: the column of light (a vertical line through `col_axis`,
## bright where the reflected ray passes near it) and up to eight fires (`fire0..7`: x, y, z, strength, their
## colour in `fire_col0..7`), so the wet paving catches the blue and the orange on every graphics preset.
static func wet_stone_code() -> String:
	var code := Mats.PROP_SHADER
	code = code.replace("varying vec3 wnorm;", """varying vec3 wnorm;
uniform float wet = 0.6;
uniform float puddle_scale = 0.32;
uniform vec4 col_axis = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec3 col_col : source_color = vec3(0.1, 0.4, 1.0);
uniform vec4 fire0 = vec4(0.0); uniform vec4 fire1 = vec4(0.0); uniform vec4 fire2 = vec4(0.0); uniform vec4 fire3 = vec4(0.0);
uniform vec4 fire4 = vec4(0.0); uniform vec4 fire5 = vec4(0.0); uniform vec4 fire6 = vec4(0.0); uniform vec4 fire7 = vec4(0.0);
uniform vec3 fire_col0 : source_color = vec3(0.0); uniform vec3 fire_col1 : source_color = vec3(0.0);
uniform vec3 fire_col2 : source_color = vec3(0.0); uniform vec3 fire_col3 : source_color = vec3(0.0);
uniform vec3 fire_col4 : source_color = vec3(0.0); uniform vec3 fire_col5 : source_color = vec3(0.0);
uniform vec3 fire_col6 : source_color = vec3(0.0); uniform vec3 fire_col7 : source_color = vec3(0.0);
float fire_refl(vec3 p, vec3 R, vec4 f) {
	if (f.w <= 0.0) { return 0.0; }
	vec3 d = f.xyz - p;
	float t = dot(d, R);
	if (t <= 0.0) { return 0.0; }
	float miss = length(d - R * t);
	return exp(-miss * miss / 0.09) * f.w / (1.0 + t * 0.25);
}
""")
	code = code.replace("	ALBEDO = col;\n	ROUGHNESS = mix(clamp(roughness + (n2 - 0.5) * 0.2, 0.05, 1.0), 0.6, snowc);", """	float wetn = fbm(wpos.xz * puddle_scale + 7.3);
	float puddle = smoothstep(0.54, 0.6, wetn) * wet;
	float damp = smoothstep(0.3, 0.56, wetn) * wet;
	col *= 1.0 - 0.22 * damp - 0.3 * puddle;
	ALBEDO = col;
	float rgh = mix(clamp(roughness + (n2 - 0.5) * 0.2, 0.05, 1.0), 0.6, snowc);
	rgh = mix(rgh, rgh * 0.75, damp);
	ROUGHNESS = mix(rgh, 0.05, puddle);""")
	code = code.replace("	EMISSION = emission * emission_energy + vec3(1.0, 0.34, 0.07) * ember * pulse * 2.4;", """	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(normalize(wnorm), 0.0)).xyz, puddle));
	vec3 Vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 Nw = normalize(mix(normalize(wnorm), pn, 0.35 * (1.0 - puddle)));
	vec3 R = reflect(-Vw, Nw);
	vec3 mirror = vec3(0.0);
	if (col_axis.w > 0.0 && R.y > 0.02) {
		vec2 d2 = normalize(R.xz + vec2(1e-5, 0.0));
		vec2 st = wpos.xz - col_axis.xy;
		float along = -dot(st, d2);
		float dist = abs(st.x * d2.y - st.y * d2.x);
		float hit_y = wpos.y + R.y * along / max(length(R.xz), 1e-3);
		float tall = smoothstep(0.5, 1.2, hit_y) * (1.0 - smoothstep(4.0, 10.0, hit_y));
		mirror += col_col * exp(-dist * dist / 0.1) * col_axis.w * tall * step(0.0, along);
	}
	mirror += fire_col0 * fire_refl(wpos, R, fire0) + fire_col1 * fire_refl(wpos, R, fire1)
		+ fire_col2 * fire_refl(wpos, R, fire2) + fire_col3 * fire_refl(wpos, R, fire3)
		+ fire_col4 * fire_refl(wpos, R, fire4) + fire_col5 * fire_refl(wpos, R, fire5)
		+ fire_col6 * fire_refl(wpos, R, fire6) + fire_col7 * fire_refl(wpos, R, fire7);
	EMISSION = emission * emission_energy + vec3(1.0, 0.34, 0.07) * ember * pulse * 2.4 + mirror * (puddle * 1.1 + damp * 0.22);""")
	return code

## A wet variant of Mats.world (same parameters), its own material (the puddles' mirrors are set per waypoint).
func wet_stone(c1: Color, c2: Color, rough: float, scale: float, moss: float, moss_col: Color, occlude: bool, wet: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("wet_stone", wet_stone_code())
	m.set_shader_parameter("albedo", c1)
	m.set_shader_parameter("albedo2", c2)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("moss_col", moss_col)
	m.set_shader_parameter("occlude", 1.0 if occlude else 0.0)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("emission", Color.BLACK)
	m.set_shader_parameter("emission_energy", 0.0)
	m.set_shader_parameter("grain", 0.0)
	m.set_shader_parameter("wet", wet)
	wet_mats.append(m)
	return m

## Tell the wet stone where its mirrors are (local positions: the material is in the waypoint's own frame only
## once it is in the tree, so this runs from _ready).
func _set_mirrors() -> void:
	var o := global_position
	for m in wet_mats:
		m.set_shader_parameter("col_axis", Vector4(o.x, o.z, 0.0, 1.0))
		m.set_shader_parameter("col_col", Color(0.12, 0.42, 1.0))
		for i in mini(mirrors.size(), 8):
			var f: Array = mirrors[i]
			var p: Vector3 = o + f[0]
			m.set_shader_parameter("fire%d" % i, Vector4(p.x, p.y, p.z, f[2]))
			m.set_shader_parameter("fire_col%d" % i, f[1])

func _ready() -> void:
	_set_mirrors()
