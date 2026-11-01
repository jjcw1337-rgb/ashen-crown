class_name WaypointGrand
extends Node3D
## The camp's grand waypoint, BLOCKOUT (test-waypoint, stage 1 of the waypoint overhaul).
## Simple shapes at true scale to judge layout, size and the read from the game camera before any Meshy
## models are made: a three-tier stone dais with carved rune channels, a floating rune crystal over a light
## column, four blue-fire braziers, two hooded guardian statues with spears, two red banners, a broken back
## wall and two warm torches in front. Local +z faces the camera (travellers arrive on that side).
## `SOLIDS` lists the colliders (local x, z, radius) that World.add_waypoint turns into circles.

const RUNE := Color(0.35, 0.72, 1.0)
const DAIS_R := 4.85          # outer step radius
const TOP_Y := 0.36           # walking height of the inner dais

const SOLIDS := [
	# braziers on the middle step
	[2.76, 2.76, 0.45], [-2.76, 2.76, 0.45], [2.76, -2.76, 0.45], [-2.76, -2.76, 0.45],
	# guardian statues' plinths
	[4.4, -4.0, 0.85], [-4.4, -4.0, 0.85],
	# banner poles, torches, the crystal's socket
	[1.7, -5.3, 0.15], [-1.7, -5.3, 0.15], [5.0, 3.0, 0.18], [-5.0, 3.0, 0.18], [0.0, 0.0, 0.6],
]

const IDLE := 0.35           # rune glow with nobody near (a soft cyan: the old stone's white blaze read as UI)
const NEAR := 1.7            # rune glow with a hero on the dais
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
	beam_mat = Mats.glow_unique(Color(0.45, 0.78, 1.0), 1.4, 0.6)

	# --- the dais: three worn steps, each edged with dressed blocks
	var tiers := [[DAIS_R, 0.06], [4.15, 0.18], [3.45, 0.30]]
	for t in tiers:
		Models.P(self, Geo.cyl(t[0] - 0.08, t[0], 0.12, 56), stone, Vector3(0, t[1], 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for ti in tiers.size():
		var r: float = tiers[ti][0] - 0.24
		var n := int(TAU * r / 0.85)
		for i in n:
			var a := TAU * (i + rng.randf_range(-0.08, 0.08)) / n
			var blk := Models.P(self, Geo.box(0.78, 0.13, 0.42), stone if i % 3 else stone_d,
					Vector3(cos(a) * r, tiers[ti][1] + rng.randf_range(0.0, 0.02), sin(a) * r),
					Vector3(rng.randf_range(-1.5, 1.5), -rad_to_deg(a) + 90.0, 0))
			blk.scale = Vector3(rng.randf_range(0.9, 1.05), 1, 1)
	# the carved inner floor
	Models.P(self, Geo.cyl(3.1, 3.1, 0.03, 56), floor_m, Vector3(0, TOP_Y + 0.005, 0))

	# --- rune channels: three rings, glyphs between them, eight spokes
	for rr in [[2.8, 0.09], [2.0, 0.07], [1.08, 0.06]]:
		var rm := Mats.glow_unique(RUNE, IDLE)
		ring_mats.append(rm)
		var ring := Models.P(self, Geo.torus(rr[0] - rr[1], rr[0], 72, 4), rm, Vector3(0, TOP_Y + 0.025, 0))
		ring.scale = Vector3(1, 0.25, 1)
	for i in 28:
		var a := TAU * i / 28.0
		var g := Models.N(self, "glyph", Vector3(cos(a) * 2.4, TOP_Y + 0.025, sin(a) * 2.4), Vector3(0, -rad_to_deg(a), 0))
		Models.P(g, Geo.box(0.05, 0.012, 0.34), rune_mat)
		Models.P(g, Geo.box(0.05, 0.012, 0.2), rune_mat, Vector3(0, 0, 0.05 * (i % 3 - 1)), Vector3(0, 90 if i % 2 else 45, 0))
	for i in 16:
		var a := TAU * (i + 0.5) / 16.0
		Models.P(self, Geo.box(0.04, 0.012, 0.22), rune_mat, Vector3(cos(a) * 1.55, TOP_Y + 0.025, sin(a) * 1.55),
				Vector3(0, -rad_to_deg(a) + (30 if i % 2 else -30), 0))
	for i in 8:
		var a := TAU * i / 8.0
		Models.P(self, Geo.box(0.035, 0.012, 0.85), rune_mat, Vector3(cos(a) * 1.54, TOP_Y + 0.025, sin(a) * 1.54),
				Vector3(0, -rad_to_deg(a) + 90.0, 0))

	# --- the socket, the light column and the floating crystal
	Models.P(self, Geo.cyl(0.48, 0.66, 0.22, 8), stone_d, Vector3(0, TOP_Y + 0.11, 0))
	Models.P(self, Geo.torus(0.36, 0.44, 24, 4), rune_mat, Vector3(0, TOP_Y + 0.23, 0)).scale = Vector3(1, 0.3, 1)
	Models.P(self, Geo.cyl(0.1, 0.2, 2.3, 12), beam_mat, Vector3(0, TOP_Y + 1.35, 0))
	Models.P(self, Geo.cyl(0.32, 0.5, 2.6, 16), Mats.glow(Color(0.3, 0.55, 1.0), 0.25, 0.7), Vector3(0, TOP_Y + 1.4, 0))
	crystal = Models.N(self, "crystal", Vector3(0, 3.0, 0))
	var cm := Mats.mat(Color(0.18, 0.34, 0.7), 0.08, 0.2, Color(0.35, 0.65, 1.0), 1.4)
	Models.P(crystal, Geo.cyl(0.0, 0.44, 1.15, 6), cm, Vector3(0, 0.575, 0))
	Models.P(crystal, Geo.cyl(0.44, 0.0, 0.75, 6), cm, Vector3(0, -0.375, 0))
	Models.P(crystal, Geo.sph(0.2, 10), Mats.glow(Color(0.75, 0.9, 1.0), 2.5), Vector3(0, 0.05, 0))
	# a carved rune on its face, toward the camera
	Models.P(crystal, Geo.box(0.04, 0.42, 0.02), rune_mat, Vector3(0, 0.12, 0.33), Vector3(-17, 0, 0))
	Models.P(crystal, Geo.box(0.26, 0.04, 0.02), rune_mat, Vector3(0, 0.2, 0.31), Vector3(-17, 0, 0))
	shards = Models.N(self, "shards", Vector3(0, 3.0, 0))
	for i in 5:
		var a := TAU * i / 5.0
		Models.P(shards, Geo.cyl(0.0, 0.09, 0.42, 5), cm, Vector3(cos(a) * 0.95, sin(a * 2.0) * 0.25, sin(a) * 0.95),
				Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-25, 25)))
	light = OmniLight3D.new()
	light.light_color = Color(0.42, 0.66, 1.0)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.light_volumetric_fog_energy = 2.0
	light.position = Vector3(0, 2.4, 0)
	light.set_meta("base", light.light_energy)
	light.add_to_group(Grade.SHADOW_GROUP)
	add_child(light)

	# --- four braziers with blue fire on the middle step
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var b := Models.N(self, "brazier", Vector3(cos(a) * 3.9, 0.24, sin(a) * 3.9))
		Models.P(b, Geo.box(0.8, 0.28, 0.8), stone_d, Vector3(0, 0.14, 0))
		Models.P(b, Geo.lathe([Vector2(0.0, 0.28), Vector2(0.3, 0.28), Vector2(0.22, 0.4), Vector2(0.17, 0.85),
				Vector2(0.24, 0.95), Vector2(0.0, 0.95)], 10, "wp_brazier_col"), stone, Vector3.ZERO)
		Models.P(b, Geo.lathe([Vector2(0.12, 0.95), Vector2(0.42, 1.08), Vector2(0.5, 1.22), Vector2(0.44, 1.22),
				Vector2(0.36, 1.12), Vector2(0.0, 1.1)], 16, "wp_brazier_bowl"), iron, Vector3.ZERO)
		# blue spirit-fire (Props.fire's flames start warm white, so these are their own): a dense core, licking
		# tongues, a few sparks, and a small light on the stones
		Fx.aura(b, Color(0.55, 0.8, 1.0), 22, 0.9, 0.16, 0.55, 1.8, 0.12, 12.0, Vector3(0, 1.16, 0))
		Fx.aura(b, Color(0.2, 0.45, 1.0), 16, 1.3, 0.26, 0.8, 1.2, 0.2, 20.0, Vector3(0, 1.2, 0))
		Fx.aura(b, Color(0.7, 0.9, 1.0), 6, 1.8, 0.04, 1.6, 0.8, 0.2, 30.0, Vector3(0, 1.3, 0))
		var bl := OmniLight3D.new()
		bl.light_color = Color(0.35, 0.6, 1.0)
		bl.light_energy = 0.8
		bl.omni_range = 3.2
		bl.position = Vector3(0, 1.5, 0)
		bl.set_meta("base", 0.8)
		bl.add_to_group("flicker")
		b.add_child(bl)

	# --- two hooded guardians with spears, on plinths at the back corners, facing the dais
	for sx in [-1.0, 1.0]:
		var s := Models.N(self, "guardian", Vector3(4.4 * sx, 0, -4.0), Vector3(0, -22.0 * sx, 0))
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
		Models.P(bn, Geo.cyl(0.05, 0.06, 4.4, 8), iron, Vector3(0, 2.2, 0))
		Models.P(bn, Geo.cyl(0.0, 0.08, 0.3, 4), iron, Vector3(0, 4.55, 0))
		Models.P(bn, Geo.box(1.1, 0.06, 0.06), iron, Vector3(0, 4.0, 0))
		Models.P(bn, Geo.box(0.95, 2.1, 0.03), cloth, Vector3(0, 2.92, 0.05))
		Models.P(bn, Geo.box(0.08, 0.7, 0.04), gold, Vector3(0, 3.1, 0.08))
		Models.P(bn, Geo.box(0.42, 0.08, 0.04), gold, Vector3(0, 3.25, 0.08))
		Models.P(bn, Geo.prism(0.95, 0.35, 0.03), cloth, Vector3(0, 1.7, 0.05), Vector3(0, 0, 180))

	# --- a broken stone wall arcing round the back, framing the dais
	for i in 9:
		var a := deg_to_rad(205.0 + i * 16.25)
		if i == 4:
			continue  # gap behind the crystal, between the banners
		var hgt := rng.randf_range(0.45, 1.25) if i not in [0, 8] else rng.randf_range(1.6, 2.2)
		Models.P(self, Geo.box(1.25, hgt, 0.55), stone if i % 2 else stone_d,
				Vector3(cos(a) * 6.2, hgt * 0.5, sin(a) * 6.2), Vector3(0, -rad_to_deg(a) + 90.0, rng.randf_range(-3, 3)))
	# toppled pillar drums
	for d in [[-3.2, -6.4, 0.0], [3.6, -6.6, 1.2], [6.1, -1.4, 0.6]]:
		Models.P(self, Geo.cyl(0.34, 0.36, 0.7, 10), stone, Vector3(d[0], 0.34, d[1]), Vector3(90, rad_to_deg(d[2]), 0))

	# --- two warm iron torches flanking the approach
	for sx in [-1.0, 1.0]:
		var tp := Models.N(self, "torch", Vector3(5.0 * sx, 0, 3.0))
		Models.P(tp, Geo.cyl(0.04, 0.06, 1.9, 6), iron, Vector3(0, 0.95, 0))
		Models.P(tp, Geo.lathe([Vector2(0.04, 1.85), Vector2(0.17, 2.05), Vector2(0.2, 2.15), Vector2(0.0, 2.1)], 8, "wp_torch_cup"), iron)
		Props.fire(tp, Vector3(0, 2.12, 0), 0.4, Color(1.0, 0.55, 0.2), true, false, true)

	# motes of energy drifting up off the dais
	motes = Fx.aura(self, Color(0.45, 0.75, 1.0), 36, 0.35, 0.05, 3.2, 0.25, 2.6, 15.0, Vector3(0, TOP_Y + 0.15, 0))

## The activation burst (a hero arrives by it, or opens the travel window at it).
func pulse() -> void:
	_flash = 1.0
	var root := get_parent() as Node3D
	if root == null:
		return
	Fx.ring(root, global_position + Vector3(0, TOP_Y + 0.05, 0), 3.2, RUNE, 0.7, 0.2)
	Fx.burst(root, global_position + Vector3(0, 1.0, 0), Color(0.5, 0.8, 1.0), 30, 3.5, 0.08, 1.0, true, 1.5, 35.0)
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
		ring_mats[i].set_shader_parameter("energy", lerpf(IDLE, NEAR, on) * (0.8 + 0.35 * ph) + _flash * 2.5)
	rune_mat.set_shader_parameter("energy", lerpf(IDLE * 0.8, NEAR * 0.85, smoothstep(0.3, 1.0, _wake)) * (0.85 + 0.25 * pulse_w) + _flash * 2.0)
	beam_mat.set_shader_parameter("energy", lerpf(0.7, 1.9, _wake) + _flash * 3.0)
	_spin += delta * lerpf(0.3, 1.3, _wake) + delta * _flash * 4.0
	crystal.rotation.y = _spin
	crystal.position.y = 3.0 + sin(_t * 1.1) * lerpf(0.1, 0.18, _wake)
	shards.rotation.y = -_spin * 1.6
	shards.position.y = crystal.position.y
	shards.scale = Vector3.ONE * lerpf(1.0, 1.25, _wake) * (1.0 + _flash * 0.3)
	light.light_energy = float(light.get_meta("base")) * lerpf(0.6, 1.25, _wake) * (0.9 + 0.15 * pulse_w) + _flash * 3.0
	motes.amount_ratio = lerpf(0.35, 1.0, _wake)
