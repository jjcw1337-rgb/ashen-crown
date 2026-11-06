class_name TitleStage
extends SubViewportContainer
## The title screen's world (UI._build_title): the Gate of the Ashen Crown at dusk. A ruined cathedral gate,
## broken arcades, a fallen colossus and a giant crown half-sunk in the ash, fog banks, falling ash, braziers.
## The chosen character (a co-op puppet in their own saved gear, as on the class picker) stands alone in the
## gate's light, between two braziers, no dais (Blaine, 2026-11-05: "remove the two daises and show only the
## selected character"). The camera drifts; hovering the hero leans in and lights them up (their class's
## signature move); `enter` plays the short move in. It renders in its own World3D, and only while it is showing (`active`).
## Blockout: every piece here is procedural or an existing asset; GATE/ARCADE/COLOSSUS/CROWN are the spots the
## Meshy models replace.

signal hovering(which: String)     # "continue" (the hero) or ""
signal clicked(which: String)

const HOME := Vector3(0.0, 0.0, 4.6)     # where the chosen hero stands, before the gate's arch
## The Meshy models (concept image, then image-to-3D; prepared by tools/blender/prep_prop.py): the gate 18 m
## high, the arcade 8 m, the colossus 10 m, the crown 1 m. Without them the procedural stand-ins are built.
const MODEL_DIR := "res://assets/models/title/"
const FACE := PI                          # bodies face -z; the camera is on +z
const WARM := Color(1.0, 0.66, 0.36)
## 16:9's horizontal field of view at the 40° vertical one, kept on narrower screens
const H_FOV := 64.0
const COLD := Color(0.55, 0.78, 1.0)

var game: Node
var vp: SubViewport
var cam: Camera3D
var root3d: Node3D
var env: Environment
var moon: DirectionalLight3D
var hero: Hero                            # the last character, or null
var has_char := false
var focus := ""                           # the hovered side
var entering := ""                        # set by enter(): the camera is moving into a choice
var covered: Callable                     # true while something opaque is over the stage: stop drawing
var cards := {}                           # (the old Continue/New cards, hidden; kept placed for UI's API)
var t := 0.0
var _lean := 0.0                          # -1 left .. 1 right, eased
var _push := 0.0                          # 0..1 the move into a choice
var _spot := {}                           # side -> SpotLight3D
var _key := {}                            # side -> OmniLight3D in front of the dais
var _flames: Array[OmniLight3D] = []
var _sig_t := -1.0
var _sig_cool := 0.0
var _flash_t := 9.0
var _flash := 0.0

func setup(g: Node) -> void:
	game = g
	if OS.get_cmdline_user_args().has("--server"):     # (dedicated servers and match workers; headless tests still need the stage)
		set_process(false)
		return
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.handle_input_locally = false
	var q: int = int(game.quality)
	vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else (Viewport.MSAA_4X if q >= 2 else Viewport.MSAA_2X)
	vp.positional_shadow_atlas_size = 0
	# sharp, not soft: full resolution, full mesh detail, no blurring anti-aliasing (MSAA only),
	# anisotropic filtering, and a light sharpening pass over the result (SHARPEN_SHADER)
	vp.scaling_3d_scale = 1.0
	vp.mesh_lod_threshold = 0.0
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	var shm := ShaderMaterial.new()
	var shs := Shader.new()
	shs.code = SHARPEN_SHADER
	shm.shader = shs
	material = shm
	add_child(vp)
	root3d = Node3D.new()
	vp.add_child(root3d)
	_environment(q)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 220.0
	root3d.add_child(cam)
	_ground()
	_gate()
	_arcades()
	_monuments()
	_hero_lights(HOME, WARM)
	_trees()
	_fog_banks()
	_ash(q)
	_place_camera(0.0)

# ---------------------------------------------------------------- world
func _environment(q: int) -> void:
	var forward: bool = RenderingServer.get_rendering_device() != null
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.03, 0.035, 0.06)
	sm.sky_horizon_color = Color(0.32, 0.17, 0.12)
	sm.sky_curve = 0.09
	sm.ground_horizon_color = Color(0.16, 0.09, 0.07)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sm.sun_angle_max = 8.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.3, 0.27, 0.32)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.14, 0.13)
	env.fog_light_energy = 0.9
	env.fog_density = 0.016
	env.fog_sky_affect = 0.35
	env.fog_height = 0.6
	env.fog_height_density = 0.12
	env.ssao_enabled = forward and q >= 2
	env.ssao_intensity = 1.6
	env.volumetric_fog_enabled = forward and q >= 2
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.75, 0.68, 0.66)
	env.volumetric_fog_emission = Color(0.05, 0.03, 0.03)
	env.volumetric_fog_length = 60.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.9
	we.environment = env
	root3d.add_child(we)
	# the moon, low behind the gate: rims everything toward the camera
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.68, 0.9)
	moon.light_energy = 0.7
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.rotation_degrees = Vector3(-24, 160, 0)
	root3d.add_child(moon)
	# a weak warm fill from the front so faces never go black
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.72, 0.5)
	fill.light_energy = 0.18
	fill.rotation_degrees = Vector3(-30, -10, 0)
	root3d.add_child(fill)

static func has_model(n: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + n + ".glb")

func _model(n: String, pos: Vector3, rot_deg: Vector3, scl: float, tint := Color.WHITE) -> Node3D:
	var m: Node3D = (load(MODEL_DIR + n + ".glb") as PackedScene).instantiate()
	# its own materials, copied: sooted down to the game's palette, and anisotropic filtering so the stone
	# stays crisp where it's seen at a slant
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src:
				var dm := src.duplicate() as BaseMaterial3D
				dm.albedo_color = src.albedo_color * tint
				dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mi.set_surface_override_material(si, dm)
	m.name = n.capitalize()
	m.position = pos
	m.rotation_degrees = rot_deg
	m.scale = Vector3.ONE * scl
	root3d.add_child(m)
	return m

func _stone() -> Material:
	return Mats.world(Color(0.27, 0.25, 0.24), Color(0.17, 0.16, 0.16), 0.92, 1.1, 0.18, Color(0.16, 0.2, 0.12), false)

func _stone_dark() -> Material:
	return Mats.world(Color(0.19, 0.18, 0.18), Color(0.11, 0.1, 0.1), 0.94, 0.9, 0.1, Color(0.14, 0.17, 0.1), false)

func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	g.mesh = pm
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	m.shader = sh
	g.material_override = m
	root3d.add_child(g)

## The great gate: a cathedral front with a pointed archway, a rose window, two buttress towers and a broken
## top; a warm glow of the lands beyond inside the arch. (Meshy replaces this: GATE.)
func _gate() -> void:
	if has_model("gate"):
		_model("gate", Vector3(0, -0.05, -12.0), Vector3(0, GATE_YAW, 0), 1.0, SOOT)
		_gate_light(Vector3(0, 0, -12.0))
		for sx: int in [-1, 1]:
			var tp := Vector3(sx * 3.6, 2.6, -8.3)
			Models.P(root3d, Geo.cyl(0.06, 0.03, 0.6, 6), Mats.mat(Color(0.08, 0.07, 0.07), 0.5, 0.7), tp + Vector3(0, -0.3, 0), Vector3(sx * -20, 0, 0))
			Props.fire(root3d, tp + Vector3(0, 0.05, 0.1), 0.45, Color(1.0, 0.55, 0.2), false, false, true, "torch")
			var tl := OmniLight3D.new()
			tl.light_color = Color(1.0, 0.6, 0.3)
			tl.light_energy = 1.4
			tl.omni_range = 7.0
			tl.position = tp + Vector3(0, 0.4, 0.8)
			root3d.add_child(tl)
			_flames.append(tl)
		return
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 0, -9.0)
	root3d.add_child(gate)
	var st := _stone()
	var sd := _stone_dark()
	Models.P(gate, pointed_arch(12.0, 12.5, 1.6, 4.6, 8.6), st, Vector3(0, 0, 0))
	# jambs: the arch's moulded edge, stepped back in three orders
	for k in 3:
		var s := 4.6 + 0.7 * (k + 1)
		Models.P(gate, pointed_arch(s + 0.5, 8.6 + 0.6 * (k + 1) + 0.4, 0.5, s, 8.6 + 0.6 * (k + 1)), sd, Vector3(0, 0, 0.8 + 0.25 * (3 - k)))
	# rose window over the arch
	Models.P(gate, Geo.torus(1.3, 1.65, 32, 10), sd, Vector3(0, 10.6, 0.85), Vector3(90, 0, 0))
	var rose := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(2.7, 2.7)
	rose.mesh = rq
	var rm := ShaderMaterial.new()
	var rsh := Shader.new()
	rsh.code = ROSE_SHADER
	rm.shader = rsh
	rose.material_override = rm
	rose.position = Vector3(0, 10.6, 0.7)
	gate.add_child(rose)
	# buttress towers, stepped, with broken tops
	for sx: int in [-1, 1]:
		var x := sx * 7.1
		Models.P(gate, Geo.box(2.6, 15.5, 3.0), st, Vector3(x, 7.75, 0.3))
		Models.P(gate, Geo.box(3.1, 1.2, 3.5), sd, Vector3(x, 0.6, 0.3))
		Models.P(gate, Geo.box(2.9, 0.5, 3.3), sd, Vector3(x, 6.5, 0.3))
		Models.P(gate, Geo.box(2.9, 0.5, 3.3), sd, Vector3(x, 11.5, 0.3))
		for k in 3:
			var hk := 1.0 + 0.9 * float((k + (1 if sx > 0 else 0)) % 3)
			Models.P(gate, Geo.box(0.7, hk, 0.7), st, Vector3(x - 0.95 + k * 0.95, 15.5 + hk * 0.5, 1.3))
		# pinnacle on one, snapped off on the other
		if sx < 0:
			Models.P(gate, Geo.cone(0.9, 3.2, 6), sd, Vector3(x, 17.6, 0.3))
	# the gable's ragged top
	for i in 9:
		var x2 := -5.0 + i * 1.25
		var hh := 1.6 - absf(x2) * 0.22 + (0.6 if i % 3 == 0 else 0.0) - (1.0 if i == 6 or i == 7 else 0.0)
		if hh > 0.1:
			Models.P(gate, Geo.box(1.2, hh, 1.4), st, Vector3(x2, 12.5 + hh * 0.5, 0.0))
	# the light beyond the arch
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(5.0, 9.0)
	glow.mesh = gq
	var gm := ShaderMaterial.new()
	var gsh := Shader.new()
	gsh.code = BEYOND_SHADER
	gm.shader = gsh
	glow.material_override = gm
	glow.position = Vector3(0, 4.4, -0.7)
	gate.add_child(glow)
	var beyond := OmniLight3D.new()
	beyond.light_color = Color(1.0, 0.5, 0.22)
	beyond.light_energy = 2.2
	beyond.omni_range = 10.0
	beyond.position = Vector3(0, 2.5, 1.8)
	gate.add_child(beyond)
	_flames.append(beyond)
	# a path of steps up to it
	for k in 3:
		Models.P(gate, Geo.box(7.0 - k * 0.8, 0.18, 1.0), sd, Vector3(0, 0.09 + k * 0.18, 2.6 - k * 0.8))

const GATE_YAW := 0.0
const SOOT := Color(0.72, 0.66, 0.62)
## The glow of the lands beyond inside the arch, and its light on the court.
func _gate_light(at: Vector3) -> void:
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(14.0, 14.0)
	glow.mesh = gq
	var gm := ShaderMaterial.new()
	var gsh := Shader.new()
	gsh.code = BACKDROP_SHADER
	gm.shader = gsh
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = at + Vector3(0, 7.0, -4.6)
	root3d.add_child(glow)
	var beyond := OmniLight3D.new()
	beyond.light_color = Color(1.0, 0.5, 0.22)
	beyond.light_energy = 2.2
	beyond.omni_range = 11.0
	beyond.position = at + Vector3(0, 2.6, 3.6)
	root3d.add_child(beyond)
	_flames.push_front(beyond)

## Broken arcades running back on both sides: pointed bays, some fallen. (Meshy replaces these: ARCADE.)
func _arcades() -> void:
	if has_model("arcade"):
		_model("arcade", Vector3(-14.5, -0.05, -3.0), Vector3(0, 70, 0), 1.0, SOOT)
		_model("arcade", Vector3(14.5, -0.05, -3.0), Vector3(0, -70, 0), 1.0, SOOT)
		return
	var st := _stone()
	var sd := _stone_dark()
	for sx: int in [-1, 1]:
		var row := Node3D.new()
		row.name = "Arcade"
		row.position = Vector3(sx * 8.6, 0, -1.5)
		row.rotation.y = sx * deg_to_rad(-28.0)
		root3d.add_child(row)
		for i in 4:
			var z := -i * 4.2
			var broken := (i == 2 and sx < 0) or (i == 1 and sx > 0)
			var bay := Models.P(row, pointed_arch(4.2, 7.0 if not broken else 4.4, 0.9, 2.8, 5.4), st, Vector3(0, 0, z), Vector3(0, 90, 0))
			if broken:
				bay.scale = Vector3(1, 1, 1)
				Models.P(row, Geo.box(1.0, 0.7, 1.4), sd, Vector3(0.8 * sx, 0.35, z + 1.1), Vector3(0, 20, 12))
				Models.P(row, Geo.box(0.8, 0.6, 0.9), sd, Vector3(1.4 * sx, 0.3, z - 0.6), Vector3(10, 50, 0))
			# piers between bays
			Models.P(row, Geo.box(1.2, 7.6 if not broken else 5.0, 1.2), sd, Vector3(0, (7.6 if not broken else 5.0) * 0.5, z + 2.1))
		# a lone column out front, snapped
		Models.P(row, Geo.cyl(0.38, 0.42, 3.1, 14), st, Vector3(sx * 1.8, 1.55, 3.6))
		Models.P(row, Geo.cyl(0.4, 0.4, 0.9, 14), st, Vector3(sx * 2.6, 0.38, 4.6), Vector3(0, 0, 90))

## The fallen colossus (a crowned king; the knight statue, huge, in dark stone, sunk to the chest and leaning)
## and the giant crown lying in the ash. (Meshy replaces these: COLOSSUS, CROWN.)
func _monuments() -> void:
	if has_model("colossus") and has_model("crown"):
		# the fallen king, sunk to the chest in the ash and leaning; his crown lying huge on the other side
		_model("colossus", Vector3(-12.5, -2.2, -15.5), Vector3(-3, 34, 7), 1.35, SOOT)
		_model("crown", Vector3(11.5, -0.35, -13.0), Vector3(6, -22, 16), 4.2)
		# a cold light picking out the king's face and a warm glint on the crown
		var kl := OmniLight3D.new()
		kl.light_color = Color(0.6, 0.68, 0.9)
		kl.light_energy = 1.6
		kl.omni_range = 9.0
		kl.position = Vector3(-9.5, 9.0, -9.5)
		root3d.add_child(kl)
		var cl := OmniLight3D.new()
		cl.light_color = Color(1.0, 0.6, 0.3)
		cl.light_energy = 2.4
		cl.omni_range = 7.0
		cl.position = Vector3(10.0, 3.4, -9.0)
		root3d.add_child(cl)
		return
	var sd := Mats.world(Color(0.24, 0.23, 0.23), Color(0.13, 0.12, 0.12), 0.95, 0.5, 0.25, Color(0.14, 0.18, 0.1), false)
	if ResourceLoader.exists(Roman.STATUE_GLB):
		var col := Node3D.new()
		col.name = "Colossus"
		col.position = Vector3(-17.0, -4.5, -27.0)
		col.rotation_degrees = Vector3(-6, 32, 14)
		col.scale = Vector3.ONE * 8.0
		root3d.add_child(col)
		var body: Node3D = (load(Roman.STATUE_GLB) as PackedScene).instantiate()
		col.add_child(body)
		for n in body.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = sd
		# its crown, still on
		_crown(col, Vector3(0, 1.86, 0), 0.13, Vector3(-8, 0, 4))
	var big := Node3D.new()
	big.name = "Crown"
	big.position = Vector3(15.0, -0.9, -19.0)
	big.rotation_degrees = Vector3(62, -30, 8)
	root3d.add_child(big)
	_crown(big, Vector3.ZERO, 3.4, Vector3.ZERO)

func _crown(parent: Node3D, at: Vector3, r: float, rot: Vector3) -> void:
	var gold := Mats.mat(Color(0.3, 0.23, 0.12), 0.5, 0.85)
	var c := Node3D.new()
	c.position = at
	c.rotation_degrees = rot
	parent.add_child(c)
	Models.P(c, Geo.cyl(r, r * 1.04, r * 0.32, 28), gold, Vector3(0, r * 0.16, 0))
	Models.P(c, Geo.torus(r * 0.96, r * 1.1, 28, 8), gold, Vector3(0, 0.02, 0))
	for i in 8:
		if i == 3:
			continue   # one point broken off
		var a := TAU * i / 8.0
		var p := Vector3(cos(a) * r, r * 0.32, sin(a) * r)
		Models.P(c, Geo.cone(r * 0.2, r * (0.7 if i % 2 == 0 else 0.45), 5), gold, p + Vector3(0, r * (0.35 if i % 2 == 0 else 0.22), 0))

## A round stone dais, three steps, a brazier each side behind it, and a spotlight over it.
## The hero's place: two braziers either side and behind, a spot from above, a warm key in front and a cold rim
## behind (no dais: the hero stands on the gate's flagstones).
func _hero_lights(at: Vector3, col: Color) -> void:
	for sx: int in [-1, 1]:
		var b := at + Vector3(sx * 2.3, 0, -1.1)
		Models.P(root3d, Geo.cyl(0.08, 0.12, 1.3, 8), Mats.mat(Color(0.08, 0.07, 0.07), 0.5, 0.7), b + Vector3(0, 0.65, 0))
		Models.P(root3d, Geo.cyl(0.36, 0.14, 0.3, 12), Mats.mat(Color(0.1, 0.09, 0.08), 0.45, 0.75), b + Vector3(0, 1.42, 0))
		var fcol := Color(1.0, 0.55, 0.2)
		Props.fire(root3d, b + Vector3(0, 1.55, 0), 0.65, fcol, false, false, true, "brazier")
		var l := OmniLight3D.new()
		l.light_color = fcol.lightened(0.15)
		l.light_energy = 1.4
		l.omni_range = 5.5
		l.position = b + Vector3(0, 1.9, 0.25)
		root3d.add_child(l)
		_flames.append(l)
	var sp := SpotLight3D.new()
	sp.light_color = col
	sp.spot_angle = 22.0
	sp.spot_range = 12.0
	sp.light_energy = 1.8
	sp.shadow_enabled = true
	root3d.add_child(sp)
	sp.look_at_from_position(at + Vector3(0.4, 7.5, 3.2), at + Vector3(0, 0.6, 0))
	_spot["continue"] = sp
	var key := OmniLight3D.new()
	key.name = "key_continue"
	key.light_color = col.lerp(Color.WHITE, 0.35)
	key.light_energy = 2.8
	key.omni_range = 5.6
	key.position = at + Vector3(0.7, 2.0, 2.0)
	root3d.add_child(key)
	_key["continue"] = key
	# the dusk through the arch behind, as a cold rim on the shoulders
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.62, 0.72, 1.0)
	rim.light_energy = 1.6
	rim.omni_range = 3.6
	rim.position = at + Vector3(-0.4, 2.2, -1.4)
	root3d.add_child(rim)

func _trees() -> void:
	var path := "res://assets/models/trees/deadtree.glb"
	if not ResourceLoader.exists(path):
		return
	var m: Mesh = ForestCamp.mesh(path)
	for spec in [[Vector3(-12.5, 0, -6.5), 0.85, 20.0], [Vector3(13.5, 0, -4.0), 0.75, 140.0], [Vector3(-22, 0, -15), 1.1, 70.0], [Vector3(22, 0, -12), 1.0, 250.0], [Vector3(-7.5, 0, -20), 0.9, 300.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = spec[0]
		mi.rotation_degrees = Vector3(0, spec[2], 0)
		mi.scale = Vector3.ONE * float(spec[1])
		root3d.add_child(mi)

## Soft banks of ground fog drifting across, in front of and behind the daises.
func _fog_banks() -> void:
	var sh := Shader.new()
	sh.code = FOG_SHADER
	for spec in [[Vector3(-7, 0.8, 5.0), 14.0, 0.2], [Vector3(7, 0.7, 4.4), 12.0, 0.18], [Vector3(-12, 1.6, -9), 22.0, 0.3], [Vector3(12, 1.6, -10), 22.0, 0.3], [Vector3(-18, 2.4, -22), 30.0, 0.4], [Vector3(18, 2.4, -24), 30.0, 0.4]]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(float(spec[1]), 3.2)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("alpha", float(spec[2]))
		m.set_shader_parameter("seed", randf() * 10.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = spec[0]
		root3d.add_child(mi)

## Ash drifting down over everything, and embers rising from the gate.
func _ash(q: int) -> void:
	var ash := GPUParticles3D.new()
	ash.amount = 420 if q >= 2 else 180
	ash.lifetime = 9.0
	ash.preprocess = 9.0
	ash.visibility_aabb = AABB(Vector3(-24, -8, -20), Vector3(48, 20, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.5, 12)
	pm.direction = Vector3(0.4, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.12, -0.25, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.72, 0.7, 0.0))
	g.add_point(0.15, Color(0.75, 0.72, 0.7, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.58, 0.56, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ash.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.045, 0.045)
	qm.material = Mats.particle_mat(false)
	ash.draw_pass_1 = qm
	ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ash.position = Vector3(0, 9.0, -2.0)
	root3d.add_child(ash)
	var emb := GPUParticles3D.new()
	emb.amount = 70 if q >= 2 else 30
	emb.lifetime = 5.0
	emb.preprocess = 5.0
	emb.visibility_aabb = AABB(Vector3(-10, -1, -6), Vector3(20, 16, 12))
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(6, 0.2, 3)
	em.direction = Vector3.UP
	em.spread = 20.0
	em.initial_velocity_min = 0.5
	em.initial_velocity_max = 1.4
	em.gravity = Vector3(0.15, 0.1, 0)
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 0.8
	em.scale_min = 0.4
	em.scale_max = 1.0
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.55, 0.2, 0.0))
	eg.add_point(0.1, Color(1.0, 0.55, 0.2, 1.0))
	eg.set_color(eg.get_point_count() - 1, Color(1.0, 0.3, 0.1, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = eg
	em.color_ramp = egt
	emb.process_material = em
	var eq := QuadMesh.new()
	eq.size = Vector2(0.05, 0.05)
	eq.material = Mats.particle_mat(true, Color(2.5, 2.5, 2.5))
	emb.draw_pass_1 = eq
	emb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emb.position = Vector3(0, 0.2, -5.0)
	root3d.add_child(emb)

# ---------------------------------------------------------------- the last character
## Shows the character a save describes ({} for none): `gear` is Hero.net_gear()'s shape (equipment plus
## "_cls" and "_helm"), read from the save without touching it.
func show_character(gear: Dictionary) -> void:
	if root3d == null: return
	if hero != null:
		hero.queue_free()
		hero = null
	has_char = not gear.is_empty()
	if not has_char:
		return
	hero = Hero.new()
	hero.puppet = true
	hero.name = "TitleHero"
	root3d.add_child(hero)
	hero.setup(game)
	hero.apply_net_gear(gear)
	if Dragon.is_dragon(hero.cls):
		hero.rig.scale = Vector3.ONE * Dragon.stage_scale(hero.cls)    # a dragon shrunk onto the dais like the class picker's
	var home := HOME
	hero.global_position = home
	hero.net_pos = home
	hero.net_yaw = FACE
	hero.rig.rotation.y = FACE
	hero.net_has = true
	hero.net_st = _idle_st()
	hero.light.light_energy = 0.25
	_sig_t = -1.0

func _idle_st() -> Dictionary:
	return {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}

func _animate_hero(delta: float) -> void:
	if hero == null:
		return
	var home := HOME
	_sig_cool = maxf(_sig_cool - delta, 0.0)
	if focus == "continue" and _sig_t < 0.0 and _sig_cool <= 0.0:
		_sig_t = 0.0
	if _sig_t >= 0.0:
		# hovered: their class's signature move, once (ClassStage.SIGNATURE), then a few seconds' rest
		var sig: Array = ClassStage.SIGNATURE.get(hero.cls, ["cleave", 1.1, 0.5, ""])
		_sig_t += delta
		var a := clampf(_sig_t / float(sig[1]), 0.0, 1.0)
		var st := _idle_st()
		st["style"] = str(sig[0])
		st["atk"] = a
		hero.net_st = st
		hero.net_yaw = FACE
		hero.net_pos = home + Vector3(0, sin(a * PI) * 0.15 if hero.cls == "knight" else 0.0, 0.1)
		if a >= 1.0:
			_sig_t = -1.0
			_sig_cool = 3.5
		return
	# idle: breathing (Anim's idle), the weight shifting, looking about, now and then straight at you
	var ph := t * 0.45
	var look := sin(ph) * 0.24 + sin(ph * 2.3 + 1.0) * 0.08
	if fmod(t, 9.0) < 1.8 or focus == "continue":
		look = 0.0
	hero.net_yaw = FACE + look
	hero.net_pos = home + Vector3(sin(ph * 0.7) * 0.03, 0, 0)
	hero.net_st = _idle_st()

# ---------------------------------------------------------------- interaction
func set_focus(which: String) -> void:
	if which == focus or entering != "":
		return
	focus = which
	hovering.emit(which)

## The camera's move into a choice; returns when it has gone far enough to cut away.
func enter(which: String) -> void:
	entering = which
	_sig_t = -1.0
	var tw := create_tween()
	tw.tween_property(self, "_push", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished

## Back to the plain view (the title shown again).
func reset() -> void:
	entering = ""
	_push = 0.0
	focus = ""

## The side under a point of this control: "continue" over the hero, else "".
func side_at(p: Vector2) -> String:
	return "continue" if dais_rect("continue").has_point(p) else ""

## The screen rectangle (this control's space) round the hero's place.
func dais_rect(_side: String) -> Rect2:
	var at: Vector3 = HOME
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	var feet := cam.unproject_position(at) * sc
	var head := cam.unproject_position(at + Vector3(0, 2.6, 0)) * sc
	var edge := cam.unproject_position(at + Vector3(0.9, 0, 0)) * sc
	var half := absf(edge.x - feet.x)
	return Rect2(Vector2(feet.x - half, head.y), Vector2(half * 2.0, feet.y - head.y + 12.0))

## Where the hero's feet are on screen (the old cards hung under it).
func dais_foot(_side: String) -> Vector2:
	var at: Vector3 = HOME
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	return cam.unproject_position(at + Vector3(0, 0, 1.75)) * sc

func _gui_input(ev: InputEvent) -> void:
	if entering != "":
		return
	if ev is InputEventMouseMotion:
		var s := side_at((ev as InputEventMouseMotion).position)
		if s == "continue" and not has_char:
			s = ""
		set_focus(s)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if s != "" else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var s2 := side_at((ev as InputEventMouseButton).position)
		if s2 == "continue" and not has_char:
			s2 = ""
		if s2 != "":
			accept_event()
			clicked.emit(s2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and focus != "" and entering == "":
		set_focus("")

# ---------------------------------------------------------------- every frame
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		# hidden (the game is being played): stop rendering the title's 3D scene, which otherwise draws on unseen
		# every frame at full resolution
		if vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var hide: bool = covered.is_valid() and bool(covered.call())
	var mode := SubViewport.UPDATE_DISABLED if hide else SubViewport.UPDATE_ALWAYS
	if vp.render_target_update_mode != mode:
		vp.render_target_update_mode = mode
	if hide:
		return
	t += delta
	var target := 0.0
	var f := entering if entering != "" else focus
	if f == "continue":
		target = 1.0     # hovered: lean in a little
	_lean = lerpf(_lean, target, 1.0 - exp(-delta * 3.0))
	_place_camera(delta)
	# the hero's lights answer the hover
	var lspot: SpotLight3D = _spot["continue"]
	lspot.light_energy = move_toward(lspot.light_energy, 0.0 if not has_char else (4.2 if f == "continue" else 2.4), delta * 8.0)
	(_key["continue"] as OmniLight3D).light_energy = move_toward((_key["continue"] as OmniLight3D).light_energy, 0.0 if not has_char else (3.8 if f == "continue" else 2.8), delta * 6.0)
	# fire flicker
	for i in _flames.size():
		var l: OmniLight3D = _flames[i]
		var base: float = 2.2 if i == 0 else 1.4
		l.light_energy = base * (0.85 + 0.1 * sin(t * 9.0 + i * 2.1) + 0.06 * sin(t * 23.0 + i * 5.3))
	# heat lightning far off now and then; the moon breathes
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash_t = randf_range(14.0, 30.0)
		_flash = 1.0
	_flash = maxf(_flash - delta * 2.2, 0.0)
	var flick := _flash * (0.6 + 0.4 * sin(t * 40.0))
	moon.light_energy = 0.7 + 0.08 * sin(t * 0.3) + flick * 0.9
	env.background_energy_multiplier = 1.0 + flick * 1.6
	_animate_hero(delta)
	_place_cards()

## The camera: a slow drift, leaning toward the hovered side; `_push` carries it into the chosen dais.
## The multiplayer lobby's closer view of the hero (meta "lobby_zoom" 0..1, eased in and out).
var _lobby_zoom := 0.0

func _place_camera(_delta: float) -> void:
	var want: float = float(get_meta("lobby_zoom")) if has_meta("lobby_zoom") else 0.0
	_lobby_zoom = move_toward(_lobby_zoom, want, _delta * 1.6)
	var aspect := float(vp.size.x) / maxf(float(vp.size.y), 1.0) if vp.size.y > 0 else 16.0 / 9.0
	# narrower than 16:9 (4:3, 5:4, 16:10): keep 16:9's width of view, so both daises stay in the same
	# places across, and tilt up a little so they sit as low on the screen as they do on 16:9
	var narrow := clampf((16.0 / 9.0) / aspect, 1.0, 1.6)
	if narrow > 1.001:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = H_FOV
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 40.0
	var back := 15.5
	var drift := Vector3(sin(t * 0.11) * 0.5, sin(t * 0.17) * 0.18, sin(t * 0.07) * 0.3)
	back -= _lean * 1.2
	var pos := Vector3(0.0, 2.1, back) + drift
	var look := Vector3(0.0, 2.7 + (narrow - 1.0) * 4.0, -4.0) + drift * 0.3
	if _push > 0.0 and entering != "":
		var at: Vector3 = HOME + Vector3(0, 1.4, 0)
		var close := at + Vector3(0, 0.4, 4.0)
		var e := _push * _push
		pos = pos.lerp(close, e)
		look = look.lerp(at, e)
	if _lobby_zoom > 0.0:
		var ez := _lobby_zoom * _lobby_zoom * (3.0 - 2.0 * _lobby_zoom)
		pos = pos.lerp(HOME + Vector3(0.0, 1.7, 7.2), ez)
		look = look.lerp(HOME + Vector3(0.0, 1.25, 0.0), ez)
	cam.look_at_from_position(pos, look)
	_frame()

## The picture's centre moved into the room left of the character sidebar (TitleHome.mid, at the home screen's
## scale) by shifting the camera's frustum, not the camera: the hero stays in line with the arch behind him.
func _frame() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var k := minf(1.0, minf(size.x / 1440.0, size.y / 800.0))
	# (the multiplayer lobby stands the hero elsewhere: MpLobbyView.STAGE_MID)
	var m: float = float(get_meta("frame_mid")) if has_meta("frame_mid") else TitleHome.mid()
	var shift := -m * k / size.x          # a fraction of the width: the picture moves left
	var near := 0.05
	cam.near = near
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	var fov := deg_to_rad(cam.fov)
	cam.size = 2.0 * near * tan(fov * 0.5)
	var width := cam.size * (size.x / size.y if cam.keep_aspect == Camera3D.KEEP_HEIGHT else 1.0)
	cam.frustum_offset = Vector2(shift * width, 0.0)

func _place_cards() -> void:
	for side in cards:
		var c: Control = cards[side]
		if not is_instance_valid(c):
			continue
		var p := dais_foot(side)
		var w := c.size.x
		var x := clampf(p.x - w * 0.5, 16.0, size.x - w - 16.0)
		var y := clampf(p.y + 6.0, size.y * 0.5, size.y - c.size.y - 96.0)
		c.position = Vector2(x, y)

# ---------------------------------------------------------------- meshes
## A wall `w` wide, `h` tall, `d` deep with a pointed (equilateral gothic) opening `span` wide whose apex is
## `crown` high, centred, on the ground. Faces +z/-z.
static func pointed_arch(w: float, h: float, d: float, span: float, crown: float) -> Mesh:
	var key := "parch%.2f_%.2f_%.2f_%.2f_%.2f" % [w, h, d, span, crown]
	var r := span
	var spring := maxf(crown - span * 0.866, 0.2)
	var hs := span * 0.5
	var pts := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(-hs, 0), Vector2(-hs, spring)])
	# left arc: centred on the right springing point, from angle PI up to the apex (2PI/3)
	for i in range(1, 10):
		var a := PI - (PI / 3.0) * i / 10.0
		pts.append(Vector2(hs + cos(a) * r, spring + sin(a) * r))
	pts.append(Vector2(0, spring + span * 0.866))
	# right arc: centred on the left springing point, from the apex (PI/3) down to 0
	for i in range(1, 10):
		var a2 := PI / 3.0 - (PI / 3.0) * i / 10.0
		pts.append(Vector2(-hs + cos(a2) * r, spring + sin(a2) * r))
	pts.append_array([Vector2(hs, spring), Vector2(hs, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Vector2(-w * 0.5, h)])
	return Geo.extrude(pts, d, key)

# ---------------------------------------------------------------- shaders
## A light contrast-adaptive sharpen over the stage's image: each pixel pushed away from its neighbours'
## average, held inside their range so edges get crisper without halos.
const SHARPEN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.45;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, UV).rgb;
	vec3 n = texture(TEXTURE, UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(TEXTURE, UV + vec2(0.0, px.y)).rgb;
	vec3 w = texture(TEXTURE, UV + vec2(-px.x, 0.0)).rgb;
	vec3 e = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb;
	vec3 mn = min(c, min(min(n, s), min(w, e)));
	vec3 mx = max(c, max(max(n, s), max(w, e)));
	vec3 sharp = c + (c * 4.0 - (n + s + w + e)) * amount;
	COLOR = vec4(clamp(sharp, mn, mx), 1.0);
}
"""

const GROUND_SHADER := """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	// ash and dirt everywhere, cracked flagstones on the court before the gate
	float nn = n(wp.xz * 0.35) * 0.6 + n(wp.xz * 1.7) * 0.3 + n(wp.xz * 6.0) * 0.1;
	vec3 ash = mix(vec3(0.075, 0.068, 0.064), vec3(0.15, 0.14, 0.13), nn);
	vec2 p = wp.xz * vec2(0.9, 0.9);
	vec2 c = floor(p + vec2(floor(p.y) * 0.5, 0.0));
	vec2 f = fract(p + vec2(floor(p.y) * 0.5, 0.0));
	float seam = smoothstep(0.0, 0.06, f.x) * smoothstep(0.0, 0.06, f.y) * smoothstep(1.0, 0.94, f.x) * smoothstep(1.0, 0.94, f.y);
	vec3 slab = vec3(0.16, 0.15, 0.145) * (0.7 + h(c) * 0.45) * mix(0.35, 1.0, seam);
	float court = (1.0 - smoothstep(6.5, 9.5, abs(wp.x))) * (1.0 - smoothstep(4.0, 7.0, wp.z)) * smoothstep(-12.0, -9.0, wp.z);
	court *= smoothstep(0.25, 0.55, n(wp.xz * 0.5) + court * 0.3);
	ALBEDO = mix(ash, slab, court);
	ROUGHNESS = 0.93;
}
"""

const ROSE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float petals = 0.5 + 0.5 * cos(a * 8.0);
	float tracery = smoothstep(0.04, 0.0, abs(r - 0.55)) + smoothstep(0.05, 0.0, abs(fract(a * 8.0 / 6.2832) - 0.5) - 0.44) * step(0.18, r);
	vec3 glass = mix(vec3(0.9, 0.35, 0.12), vec3(0.6, 0.12, 0.08), petals) * (1.0 - r * 0.5);
	float on = step(r, 0.98);
	ALBEDO = mix(glass * 1.6, vec3(0.03), clamp(tracery, 0.0, 1.0));
	ALPHA = on;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

const BEYOND_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
	float y = UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	vec3 c = mix(vec3(1.0, 0.45, 0.15), vec3(0.4, 0.12, 0.08), 1.0 - y);
	float a = (1.0 - x * x) * smoothstep(0.0, 0.25, y) * (0.75 + 0.25 * sin(TIME * 0.7));
	ALBEDO = c * a * 1.3;
}
"""

## What shows through the open gate: a burning dusk over far hills, fog lying in the valley.
const BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
float h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float n(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h(i), h(i + 1.0), f); }
void fragment() {
	float y = 1.0 - UV.y;                       // 0 at the bottom
	vec3 sky = mix(vec3(1.0, 0.52, 0.2), vec3(0.35, 0.1, 0.07), smoothstep(0.08, 0.75, y));
	sky *= 1.0 + 0.08 * sin(TIME * 0.6);
	float hills = 0.06 + n(UV.x * 5.0) * 0.07 + n(UV.x * 13.0) * 0.025;
	float land = step(y, hills);
	vec3 c = mix(sky * 1.5, vec3(0.05, 0.03, 0.025), land);
	float mist = smoothstep(hills + 0.05, hills - 0.02, y) * 0.5 + smoothstep(0.12, 0.0, y) * 0.3;
	c = mix(c, vec3(0.55, 0.3, 0.2), mist * 0.5);
	ALBEDO = c;
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float alpha = 0.25;
uniform float seed = 0.0;
uniform sampler2D depth_tex : hint_depth_texture;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV * vec2(4.0, 1.0) + vec2(TIME * 0.025 + seed, seed);
	float f = n(uv * 2.0) * 0.6 + n(uv * 4.3 + 7.0) * 0.4;
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.45, UV.y) * smoothstep(1.0, 0.55, UV.y);
	ALBEDO = vec3(0.2, 0.16, 0.16);
	ALPHA = clamp(f * edge * alpha * 1.6, 0.0, 1.0);
}
"""
