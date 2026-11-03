class_name StashDais
extends Node3D
## The raid stash chest's dais (jj: "redo the entire thing using the parameters for the waypoints with more detail"):
## built the way the camp's grand waypoint is (WaypointGrand), at about two fifths of its size. The stone is
## modelled in Blender (tools/blender/camp/build_stash_dais.py: three tiers of dressed, bevelled, chipped blocks, a
## floor of flagstones laid in rings with carved channels between them, an octagonal plinth the chest stands on)
## under the waypoint's wet stone (WaypointGrand.wet_stone_code); glowing rings lie in the channels and on the steps'
## lips, the waypoint's rune lettering (rune_rings.png, RUNE_FLOOR_SHADER) is inlaid in the floor, in embers instead
## of the waypoint's cyan; four of the waypoint's Meshy fire bowls burn round it with the game's fire. It wakes as
## a hero comes near (the channels light outer to inner, the lettering brightens, pulses run out over it), and
## `burst()` (the chest opening, Battlegrounds.stash_fx) floods it and sends a ring of light out from the chest.

const MODEL := "res://assets/models/crypt/stash_dais.glb"
const BOWL := "res://assets/models/waypoint/firebowl.glb"
const EMBER := Color(1.0, 0.24, 0.03)        # deep: the glow shaders multiply it by energy
const EMBER_CORE := Color(1.0, 0.66, 0.32)
const TOP_Y := 0.27          # the floor's walking height (build_stash_dais.py FLOOR_Y)
const PLINTH_Y := 0.34       # the chest's plinth top (FLOOR_Y + 0.07)
const GROOVE_Y := 0.245
const CHANNELS := [[0.925, 0.03], [1.21, 0.035]]      # channel radius and half width (the gaps between the floor rings)
const LIPS := [[1.75, 0.185], [2.05, 0.095]]          # the lower steps' edges
const R := 2.05              # outer radius
const SOLID_R := 1.9         # its footprint
const BOWL_R := 2.32
const BOWL_SCALE := 0.62
const RUNE_SCALE := 0.4      # the waypoint's 7 m rune disc at this size
const IDLE := 0.28
const NEAR := 0.75
const WAKE_R := 9.0

var ring_mats: Array[ShaderMaterial] = []
var edge_mats: Array[ShaderMaterial] = []
var spoke_mat: ShaderMaterial
var rune_floor: ShaderMaterial
var _t := 0.0
var _wake := 0.0
var _flash := 0.0
var _wave := -1.0
var _wave_t := 2.0

static func has_model() -> bool:
	return ResourceLoader.exists(MODEL)

static func make() -> StashDais:
	var d := StashDais.new()
	d.name = "StashDais"
	d._build()
	return d

static func _stone(c1: Color, c2: Color, rough: float, scale: float, moss: float, wet: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WaypointGrand._shader("wet_stone", WaypointGrand.wet_stone_code())
	m.set_shader_parameter("albedo", c1)
	m.set_shader_parameter("albedo2", c2)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("moss_col", Props.MOSS)
	m.set_shader_parameter("occlude", 1.0)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("emission", Color.BLACK)
	m.set_shader_parameter("emission_energy", 0.0)
	m.set_shader_parameter("grain", 0.0)
	m.set_shader_parameter("wet", wet)
	return m

func _build() -> void:
	var stone := _stone(Color(0.25, 0.24, 0.24), Color(0.15, 0.14, 0.14), 0.9, 1.8, 0.3, 0.45)
	var floor_m := _stone(Color(0.23, 0.22, 0.22), Color(0.14, 0.13, 0.13), 0.78, 3.0, 0.08, 0.7)
	var plinth_m := _stone(Color(0.19, 0.18, 0.18), Color(0.11, 0.1, 0.1), 0.85, 2.4, 0.15, 0.5)
	var groove_m := Mats.world(Color(0.08, 0.05, 0.04), Color(0.04, 0.03, 0.02), 0.6, 3.0, 0.0, Props.MOSS, false)
	var dais: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(dais)
	for n in dais.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var nm := str(mi.name).to_lower() + str(mi.get_parent().name).to_lower()
		if nm.contains("groove"):
			mi.material_override = groove_m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif nm.contains("floor"):
			mi.material_override = floor_m
		elif nm.contains("socket"):
			mi.material_override = plinth_m
		else:
			mi.material_override = stone
	# the channels' glow, the steps' lips, the spokes across the inner ring
	for c in CHANNELS:
		var rm := Mats.glow_unique(EMBER, IDLE)
		ring_mats.append(rm)
		var ring := Models.P(self, Geo.torus(c[0] - c[1], c[0] + c[1] - 0.008, 64, 4), rm, Vector3(0, GROOVE_Y, 0))
		ring.scale = Vector3(1, 0.25, 1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for e in LIPS:
		var em := Mats.glow_unique(EMBER, IDLE * 0.4)
		edge_mats.append(em)
		var edge := Models.P(self, Geo.torus(e[0] - 0.025, e[0], 80, 4), em, Vector3(0, e[1], 0))
		edge.scale = Vector3(1, 0.2, 1)
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spoke_mat = Mats.glow_unique(EMBER, IDLE)
	for i in 8:
		var a := TAU * i / 8.0
		Models.P(self, Geo.box(0.03, 0.012, 0.22), spoke_mat, Vector3(cos(a) * 1.065, GROOVE_Y + 0.01, sin(a) * 1.065),
				Vector3(0, -rad_to_deg(a) + 90.0, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the rune lettering inlaid in the floor (the waypoint's, in embers)
	if ResourceLoader.exists(WaypointGrand.RUNES_TEX):
		rune_floor = ShaderMaterial.new()
		rune_floor.shader = WaypointGrand._shader("rune_floor", WaypointGrand.RUNE_FLOOR_SHADER)
		rune_floor.set_shader_parameter("runes", load(WaypointGrand.RUNES_TEX))
		rune_floor.set_shader_parameter("glow", EMBER)
		rune_floor.set_shader_parameter("core", EMBER_CORE)
		var pm := PlaneMesh.new()
		pm.size = Vector2(WaypointGrand.RUNES_SPAN, WaypointGrand.RUNES_SPAN)
		var disc := MeshInstance3D.new()
		disc.mesh = pm
		disc.material_override = rune_floor
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.scale = Vector3(RUNE_SCALE, 1, RUNE_SCALE)
		disc.position = Vector3(0, TOP_Y + 0.008, 0)
		add_child(disc)
	# four fire bowls round it, the waypoint's, with the game's fire (unlit but for the one shared glow below)
	if ResourceLoader.exists(BOWL):
		for i in 4:
			var a := TAU * (i + 0.5) / 4.0
			var fb := Node3D.new()
			fb.name = "bowl%d" % i
			fb.position = Vector3(cos(a) * BOWL_R, 0, sin(a) * BOWL_R)
			add_child(fb)
			var bm: Node3D = (load(BOWL) as PackedScene).instantiate()
			bm.scale = Vector3.ONE * BOWL_SCALE
			bm.rotation.y = -a
			fb.add_child(bm)
			var top := WaypointGrand._bounds(bm).end.y * BOWL_SCALE - 0.14 * BOWL_SCALE
			Props.fire(fb, Vector3(0, top, 0), 0.7, Color(1.0, 0.5, 0.18), false, false, true, "brazier")
	var lt := OmniLight3D.new()
	lt.name = "dais_light"
	lt.light_color = Color(1.0, 0.45, 0.18)
	lt.light_energy = 1.2
	lt.omni_range = 5.5
	lt.position = Vector3(0, 1.6, 0)
	add_child(lt)

## The chest opened: everything flares and a ring of light runs out from the middle.
func burst() -> void:
	_flash = 1.0
	_wave = 0.0

func _nearest_hero() -> float:
	var best := INF
	for h in get_tree().get_nodes_in_group("hero"):
		if h is Node3D:
			best = minf(best, (h as Node3D).global_position.distance_to(global_position))
	return best

func _process(delta: float) -> void:
	_t += delta
	var d := _nearest_hero()
	var want := clampf(1.0 - (d - 2.5) / (WAKE_R - 2.5), 0.0, 1.0)
	_wake = move_toward(_wake, want, delta * (0.9 if want > _wake else 0.4))
	_flash = maxf(_flash - delta * 0.7, 0.0)
	for i in ring_mats.size():
		var on := smoothstep((1 - i) * 0.3, (1 - i) * 0.3 + 0.5, _wake)
		var ph := 0.5 + 0.5 * sin(_t * 2.0 - i * 1.1)
		ring_mats[i].set_shader_parameter("energy", lerpf(IDLE, NEAR, on) * (0.8 + 0.3 * ph) + _flash * 1.4)
	spoke_mat.set_shader_parameter("energy", lerpf(IDLE * 0.8, NEAR, _wake) * (0.85 + 0.2 * sin(_t * 1.7)) + _flash * 1.2)
	for i in edge_mats.size():
		edge_mats[i].set_shader_parameter("energy", lerpf(0.08, 0.28, _wake) * (0.85 + 0.15 * sin(_t * 1.5 + i * 2.0)) + _flash * 0.8)
	if rune_floor:
		var names := ["e_outer", "e_great", "e_ornate", "e_inner"]
		for i in 4:
			var ph2 := 0.5 + 0.5 * sin(_t * 1.6 - i * 1.1)
			rune_floor.set_shader_parameter(names[i], lerpf(0.45, 0.95, _wake) * (0.88 + 0.12 * ph2) + _flash * 1.6)
		rune_floor.set_shader_parameter("rot_outer", _t * 0.015)
		rune_floor.set_shader_parameter("rot_inner", -_t * 0.03)
		_wave_t -= delta
		if _wave < 0.0 and _wave_t <= 0.0:
			_wave = 0.0
			_wave_t = lerpf(7.0, 3.0, _wake) + randf() * 1.5
		if _wave >= 0.0:
			_wave += delta * (3.4 if _flash < 0.5 else 4.5)
			if _wave > 4.2:
				_wave = -1.0
		# (the shader's radii are the waypoint's 7 m disc: our disc is scaled by RUNE_SCALE)
		rune_floor.set_shader_parameter("wave_r", _wave if _wave >= 0.0 else -10.0)
	var lt: OmniLight3D = get_node_or_null("dais_light")
	if lt:
		lt.light_energy = lerpf(0.8, 1.5, _wake) * (0.9 + 0.1 * sin(_t * 9.0) * sin(_t * 5.3)) + _flash * 2.5
