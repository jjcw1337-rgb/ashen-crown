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
const DAIS_R := 4.85          # outer step radius
const TOP_Y := 0.36           # walking height of the inner dais

const SOLIDS := [
	# braziers on the middle step
	[2.76, 2.76, 0.45], [-2.76, 2.76, 0.45], [2.76, -2.76, 0.45], [-2.76, -2.76, 0.45],
	# guardian statues' plinths
	[4.4, -4.0, 0.85], [-4.4, -4.0, 0.85],
	# banner poles, torches, the crystal's socket
	[1.7, -5.3, 0.2], [-1.7, -5.3, 0.2], [5.0, 3.0, 0.25], [-5.0, 3.0, 0.25], [0.0, 0.0, 0.65],
	# the broken back wall (WALL_R, WALL_A0 + i * WALL_STEP, the gap at 4) and its two end pillars
	[-5.62, -2.62, 0.75], [-4.55, -4.35, 0.6], [-3.05, -5.4, 0.6], [-1.25, -6.07, 0.6],
	[1.25, -6.07, 0.6], [3.05, -5.4, 0.6], [4.55, -4.35, 0.6], [5.62, -2.62, 0.75],
]
const CRY_SCALE := 0.72      # crystal.glb is 3 m tall with a 2 m socket: fit the socket inside the inner channel
const CRY_LIFT := 0.35       # and float the crystal (and its shards) higher than modelled, over the light column
const CRY_GROW := 1.45       # the crystal and its shards bigger than the socket's scale: the centrepiece must read
const BRAZIER_SCALE := 1.15
const WALL_R := 6.2
const WALL_A0 := 205.0
const WALL_STEP := 16.25

const IDLE := 0.22           # rune glow with nobody near (a soft cyan: the old stone's white blaze read as UI)
const NEAR := 0.55           # rune glow with a hero on the dais
const WAKE_R := 11.0         # a hero inside this starts waking it; fully awake at 3.5 m

var crystal: Node3D
var shards: Node3D
var rune_mat: ShaderMaterial           # glyphs, spokes and the socket ring
var ring_mats: Array[ShaderMaterial] = []   # outer, middle, inner channel: they light one after another
var beam_mat: ShaderMaterial
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
	var stone := Mats.world(Color(0.27, 0.27, 0.28), Color(0.16, 0.16, 0.17), 0.92, 1.3, 0.45, Props.MOSS)
	var stone_d := Mats.world(Color(0.19, 0.19, 0.2), Color(0.12, 0.12, 0.13), 0.9, 2.2, 0.2, Props.MOSS)
	var floor_m := Mats.world(Color(0.22, 0.22, 0.24), Color(0.14, 0.14, 0.16), 0.75, 2.6, 0.1, Props.MOSS, false)
	var iron := Mats.mat(Color(0.12, 0.11, 0.1), 0.55, 0.85)
	var statue_m := Mats.world(Color(0.34, 0.33, 0.31), Color(0.2, 0.2, 0.19), 0.9, 1.7, 0.4, Props.MOSS)
	rune_mat = Mats.glow_unique(RUNE, 1.1)
	beam_mat = Mats.glow_unique(Color(0.05, 0.3, 1.0), 0.45, 0.6)

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
	crystal = Models.N(self, "crystal", Vector3(0, 3.0, 0))
	shards = Models.N(self, "shards", Vector3(0, 3.0, 0))
	if cry:
		var holder := Models.N(self, "crystal_model", Vector3(0, TOP_Y - 0.02, 0))
		holder.scale = Vector3.ONE * CRY_SCALE
		holder.add_child(cry)
		for n in cry.find_children("*", "Node3D", true, false):
			var nm := str(n.name).to_lower()
			if nm == "crystal" or nm == "shards":
				var piece: Node3D = n
				var at := holder.position + piece.position * CRY_SCALE + Vector3(0, CRY_LIFT, 0)
				piece.get_parent().remove_child(piece)
				var host: Node3D = crystal if nm == "crystal" else shards
				host.position = at
				host.scale = Vector3.ONE * CRY_SCALE * CRY_GROW
				host.add_child(piece)
				piece.position = Vector3.ZERO
				for g in piece.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if nm == "crystal":
					# a cold glow from inside: the baked texture's runes and facets, lit
					for g in piece.find_children("*", "MeshInstance3D", true, false):
						var mi: MeshInstance3D = g
						var base := mi.get_active_material(0)
						if base is StandardMaterial3D:
							var m2: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
							m2.emission_enabled = true
							m2.emission = Color(0.1, 0.32, 0.9)
							m2.emission_energy_multiplier = 0.55
							m2.roughness = 0.12
							mi.material_override = m2
		for g in cry.find_children("*", "MeshInstance3D", true, false):
			var smi: MeshInstance3D = g
			var sb := smi.get_active_material(0)
			if sb is StandardMaterial3D and smi.material_override == null:
				var sm2: StandardMaterial3D = (sb as StandardMaterial3D).duplicate()
				sm2.albedo_color = Color(0.62, 0.64, 0.7)
				smi.material_override = sm2
		_cry_y = crystal.position.y
		_sh_y = shards.position.y
		if dais:
			for n in dais.find_children("*", "MeshInstance3D", true, false):
				if n.has_meta("wp_socket"):
					(n as MeshInstance3D).visible = false
		Models.P(self, Geo.cyl(0.08, 0.16, _cry_y - TOP_Y - 0.4, 12), beam_mat, Vector3(0, (TOP_Y + 0.4 + _cry_y) * 0.5, 0))
	else:
		Models.P(self, Geo.cyl(0.48, 0.66, 0.22, 8), stone_d, Vector3(0, TOP_Y + 0.11, 0))
		Models.P(self, Geo.torus(0.36, 0.44, 24, 4), rune_mat, Vector3(0, TOP_Y + 0.23, 0)).scale = Vector3(1, 0.3, 1)
		Models.P(self, Geo.cyl(0.1, 0.2, 2.3, 12), beam_mat, Vector3(0, TOP_Y + 1.35, 0))
		Models.P(crystal, Geo.cyl(0.0, 0.44, 1.15, 6), cm, Vector3(0, 0.575, 0))
		Models.P(crystal, Geo.cyl(0.44, 0.0, 0.75, 6), cm, Vector3(0, -0.375, 0))
		Models.P(crystal, Geo.sph(0.2, 10), Mats.glow(Color(0.45, 0.78, 1.0), 1.3), Vector3(0, 0.05, 0))
		Models.P(crystal, Geo.box(0.04, 0.42, 0.02), rune_mat, Vector3(0, 0.12, 0.33), Vector3(-17, 0, 0))
		Models.P(crystal, Geo.box(0.26, 0.04, 0.02), rune_mat, Vector3(0, 0.2, 0.31), Vector3(-17, 0, 0))
		for i in 5:
			var a := TAU * i / 5.0
			Models.P(shards, Geo.cyl(0.0, 0.09, 0.42, 5), cm, Vector3(cos(a) * 0.95, sin(a * 2.0) * 0.25, sin(a) * 0.95),
					Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-25, 25)))
	Models.P(self, Geo.cyl(0.32, 0.5, 2.6, 16), Mats.glow(Color(0.15, 0.4, 1.0), 0.12, 0.7), Vector3(0, TOP_Y + 1.4, 0))
	light = OmniLight3D.new()
	light.light_color = Color(0.42, 0.66, 1.0)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.light_volumetric_fog_energy = 2.0
	light.position = Vector3(0, _cry_y - 0.6, 0)
	light.set_meta("base", light.light_energy)
	light.add_to_group(Grade.SHADOW_GROUP)
	add_child(light)

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
			var hm := InfernalFx.glow_mat(Color(0.1, 0.38, 1.0), 0.45, 3.0)
			heart.material_override = hm
			heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			heart.extra_cull_margin = 2.0
			heart.position = Vector3(0, fire_y + 0.02, 0)      # low: the bowl's rim hides its lower half
			heart.scale = Vector3.ONE * 0.5
			b.add_child(heart)
			hearts.append(hm)
		else:
			# without the spirit book the simulated fire would be the orange body book: keep the particle flames
			Fx.aura(b, Color(0.3, 0.62, 1.0, 0.9), 18, 0.9, 0.17, 0.55, 1.8, 0.12, 12.0, Vector3(0, fire_y, 0), false)
			Fx.aura(b, Color(0.06, 0.28, 0.95, 0.75), 12, 1.3, 0.28, 0.8, 1.2, 0.2, 20.0, Vector3(0, fire_y + 0.04, 0), false)
			Fx.aura(b, Color(0.1, 0.4, 1.0), 6, 1.8, 0.04, 1.6, 0.8, 0.2, 30.0, Vector3(0, fire_y + 0.14, 0))

	# --- two hooded guardians with spears, on plinths at the back corners, facing the dais
	for sx in [-1.0, 1.0]:
		var s := Models.N(self, "guardian", Vector3(4.4 * sx, 0, -4.0), Vector3(0, -22.0 * sx, 0))
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

	# --- two red banners between the guardians
	var cloth := Mats.mat(Color(0.42, 0.05, 0.04), 0.9)
	var gold := Mats.mat(Color(0.75, 0.55, 0.22), 0.35, 0.9)
	for sx in [-1.0, 1.0]:
		var bn := Models.N(self, "banner", Vector3(1.7 * sx, 0, -5.3))
		var bmod := _put(bn, "banner", Vector3.ZERO, 0.0)
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
		if i == 4:
			continue  # gap behind the crystal, between the banners
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

	# --- two warm iron torches flanking the approach
	for sx in [-1.0, 1.0]:
		var tp := Models.N(self, "torch", Vector3(5.0 * sx, 0, 3.0))
		var flame_y := 2.12
		var tm := _put(tp, "torch", Vector3.ZERO, 0.0)
		if tm:
			flame_y = _bounds(tm).end.y - 0.04
		else:
			Models.P(tp, Geo.cyl(0.04, 0.06, 1.9, 6), iron, Vector3(0, 0.95, 0))
			Models.P(tp, Geo.lathe([Vector2(0.04, 1.85), Vector2(0.17, 2.05), Vector2(0.2, 2.15), Vector2(0.0, 2.1)], 8, "wp_torch_cup"), iron)
		Props.fire(tp, Vector3(0, flame_y, 0), 0.4, Color(1.0, 0.55, 0.2), true, false, true)

	# motes of energy drifting up off the dais
	motes = Fx.aura(self, Color(0.15, 0.45, 1.0), 36, 0.35, 0.05, 3.2, 0.25, 2.6, 15.0, Vector3(0, TOP_Y + 0.15, 0))

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
	beam_mat.set_shader_parameter("energy", lerpf(0.25, 0.55, _wake) + _flash * 0.8)
	_spin += delta * lerpf(0.3, 1.3, _wake) + delta * _flash * 4.0
	crystal.rotation.y = _spin
	var bob := sin(_t * 1.1) * lerpf(0.1, 0.18, _wake)
	crystal.position.y = _cry_y + bob
	shards.rotation.y = -_spin * 1.6
	shards.position.y = _sh_y + bob
	shards.scale = Vector3.ONE * lerpf(1.0, 1.25, _wake) * (1.0 + _flash * 0.3)
	light.light_energy = float(light.get_meta("base")) * lerpf(0.6, 1.25, _wake) * (0.9 + 0.15 * pulse_w) + _flash * 3.0
	motes.amount_ratio = lerpf(0.35, 1.0, _wake)
	for i in hearts.size():
		var fl := 0.8 + 0.12 * sin(_t * 7.3 + i * 1.9) + 0.08 * sin(_t * 13.1 + i * 4.3)
		hearts[i].set_shader_parameter("energy", 0.45 * fl + _flash * 0.3)
