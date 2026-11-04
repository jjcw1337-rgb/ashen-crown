extends SceneTree
## The Archer's proof range (docs/archer_vfx_standard.md): a small dusk test zone instead of the moor, so a skill
## can be recorded in Forward+ on a machine without a GPU (Mesa lavapipe) in minutes. Five lanes run east, each a
## different ground: grass (the game's living 3D grass), stone (the terrain's flagstones), dirt, wooden planks with
## logs, and dark charred soil in the shadow of a wall. The real ranger (Archer body, his bow) shoots down a lane
## through three real zombies (Data.ENEMIES "zombie", the Meshy model) with the skill's real code path
## (Hero.use_skill: damage, ignite, pierce and the co-op "loose" event are the game's own).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --rendering-method forward_plus \
##     --path . --resolution 1280x720 --fixed-fps 30 -s tools/fire_range.gd -- <outdir> <mode> [lane] [skill]
## modes: game (the game camera: a standing shot then a walking one), follow (a close camera riding beside the
##   arrow), impact (a close camera on the far end: the last foe and the burst), surfaces (impact on every lane),
##   anim (the archer close: side, then three-quarter), still (one frame of the whole range from above)
## lanes: grass stone dirt wood dark (default dirt). Frames: <outdir>/<mode>_<lane>_<take>_NNN.png, each what the
## running game drew (get_root().get_texture().get_image()). Prints the frame cost of the shot.
## The zone itself is tools/fire_range_zone.gd, loaded at run time (a static reference would compile the game's
## scripts before the Sfx autoload exists).
var g
var Z
const LANES := {"grass": -14.0, "stone": -7.0, "dirt": 0.0, "wood": 7.0, "dark": 14.0}
const FOES := [6.0, 10.0, 15.5]

func _initialize():
	Z = load("res://tools/fire_range_zone.gd")
	Z.install()
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

# ---------------------------------------------------------------- the light
func _dusk() -> void:
	var env: Environment = g.env
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.16, 0.2, 0.3)
	sm.sky_horizon_color = Color(0.55, 0.42, 0.34)
	sm.ground_horizon_color = Color(0.3, 0.26, 0.22)
	sm.ground_bottom_color = Color(0.08, 0.08, 0.08)
	sm.sun_angle_max = 20.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.36, 0.34, 0.36)
	env.fog_density = 0.006
	env.fog_height = 1.5
	env.fog_height_density = 0.04
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.8, 0.78, 0.76)
	env.volumetric_fog_length = 48.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	# the low sun in the north-west: the lanes are lit from behind, long shadows run toward the camera
	g.sun.light_color = Color(1.0, 0.7, 0.48)
	g.sun.light_energy = 1.25
	g.sun.rotation_degrees = Vector3(-19, 200, 0)
	g.sun.shadow_enabled = true

# ---------------------------------------------------------------- the shots
func _foe(p: Vector3) -> Node3D:
	var e = g.spawn_enemy("zombie", p, 6)
	e.max_life = 40000.0
	e.life = 40000.0
	e.aggro = false
	e.scripted = 999.0       # stands there for the camera
	e.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
	e.rotation.y = -PI * 0.5 + randf_range(-0.4, 0.4)    # facing the archer
	return e

func _stage(lane: String) -> Array:
	var h = g.hero
	var z: float = LANES[lane]
	for e in g.enemies_near(Vector3(12, 0, 0), 80.0):
		e.queue_free()
	h.global_position = Vector3(0, g.world.height_at(0, z), z)
	h.direct_dir = Vector3.ZERO
	h.moving = false
	h.path = PackedVector3Array()
	h.target = null
	h._face(Vector3.RIGHT)
	await process_frame
	var foes := []
	for k in FOES.size():
		foes.append(_foe(Vector3(FOES[k], 0, z + (k - 1) * 0.12)))   # on his line (the quick shot looses from in front of him)
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.mana = h.max_mana
	await wait(0.6)
	return foes

func _snap(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1] if args.size() > 1 else "game"
	var lane: String = args[2] if args.size() > 2 else "dirt"
	var sk: String = args[3] if args.size() > 3 else "pierce"
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	g.ui.close_all()
	print("[range] loaded in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var h = g.hero
	h.level = 14
	h.recalc()
	g.test_immortal = true
	g.test_allskills = true
	g.ui.visible = false
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
	g.apply_quality(2)
	_dusk()
	get_root().msaa_3d = Viewport.MSAA_2X if mode == "still" else Viewport.MSAA_DISABLED
	for b in h.beasts:
		b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 9999.0
	var cam := Camera3D.new()
	cam.fov = 38
	cam.far = 200.0
	get_root().add_child(cam)
	match mode:
		"game":
			g.zoom = 1.15     # a touch further out than the default
			await _take(out, "game", lane, sk, "stand", null)
			await _take(out, "game", lane, sk, "walk", null)
		"follow":
			await _take(out, "follow", lane, sk, "stand", cam)
		"impact":
			await _take(out, "impact", lane, sk, "stand", cam)
		"surfaces":
			for ln in ["grass", "stone", "dirt", "wood", "dark"]:
				await _take(out, "impact", ln, sk, "stand", cam, 3.6)
		"anim":
			await _take(out, "anim", lane, sk, "side", cam, 2.2)
			await _take(out, "anim", lane, sk, "34", cam, 2.2)
		"lab":
			# the effects alone, no shot: a foe pierced and set alight, then the end burst beside him (quick looks)
			var foes: Array = await _stage(lane)
			var z: float = LANES[lane]
			var AF = load("res://scripts/arrow_fx.gd")
			cam.current = true
			cam.fov = 42
			var at := Vector3(16.5, 0.7, z)
			var sd := -1.0 if lane == "wood" else 1.0
			cam.global_transform = Transform3D(Basis(), at + Vector3(-3.2, 2.0, 5.4 * sd)).looking_at(at + Vector3(0.6, 0, 0), Vector3.UP)
			for f in 45:
				if f == 2:
					AF.pierce(h, "fire", foes[2], Vector3.RIGHT)
					foes[2].ignite(5.0, 3.0, "fire")
					AF.burn(g, foes[2], "fire", 3.0)
				if f == 8:
					AF.finish(h, "fire", Vector3(18.0, 1.3, z), Vector3.RIGHT, false)
				await process_frame
				await RenderingServer.frame_post_draw
				if f % 3 == 0:
					get_root().get_texture().get_image().save_png("%s/lab_%s_%03d.png" % [out, lane, f])
		"lighttest":
			# which lights light the ground here: the arrow module's (with and without shadows) and a plain one
			var AF = load("res://scripts/arrow_fx.gd")
			await _stage(lane)
			var a1 = AF.fire_light(1750.0, 6.0, 8.0, true)
			g.world.fx_root.add_child(a1)
			a1.global_position = Vector3(6, 1.0, -7)
			var a2 = AF.fire_light(1750.0, 6.0, 8.0, false)
			g.world.fx_root.add_child(a2)
			a2.global_position = Vector3(14, 1.0, -7)
			var a3 := OmniLight3D.new()
			a3.light_energy = 6.0
			a3.omni_range = 8.0
			g.world.fx_root.add_child(a3)
			a3.global_position = Vector3(22, 1.0, -7)
			cam.current = true
			cam.global_transform = Transform3D(Basis(), Vector3(14, 16, 8)).looking_at(Vector3(14, 0, -6), Vector3.UP)
			for i in 4:
				await process_frame
			await _snap("%s/lighttest.png" % out)
		"look":
			# the impact camera's view of a lane, nothing fired (checking a lane's light)
			await _stage(lane)
			var zz: float = LANES[lane]
			cam.current = true
			cam.fov = 42
			var at2 := Vector3(16.5, 0.7, zz)
			cam.global_transform = Transform3D(Basis(), at2 + Vector3(-3.2, 2.0, 5.4)).looking_at(at2 + Vector3(0.6, 0, 0), Vector3.UP)
			await _snap("%s/look_%s.png" % [out, lane])
			cam.global_transform = Transform3D(Basis(), Vector3(12, 26, 26)).looking_at(Vector3(12, 0, 6), Vector3.UP)
			await _snap("%s/look_%s_top.png" % [out, lane])
		"still":
			await _stage(lane)
			cam.current = true
			cam.global_transform = Transform3D(Basis(), Vector3(12, 26, 26)).looking_at(Vector3(12, 0, 0), Vector3.UP)
			await _snap("%s/range_overview.png" % out)
	quit()

## The string against the drawing hand, the grip against the bow hand (metres), while he shoots: the nocked
## arrow's nock should sit on his fingers from the nock to the release, the grip in his left fist throughout.
func _hands(h, f: int, take: String) -> void:
	var w: Node3D = h.weapon_node
	if w == null or not is_instance_valid(w) or not w.has_meta("strands") or h.rig == null:
		return
	var AR: GDScript = load("res://scripts/archer.gd")
	var J: Dictionary = h.rig.get_meta("j")
	var kind: String = AR.call("bow_key", Data.BASES[h.equipment["weapon"]["base"]]["kind"])
	var sp: Dictionary = (AR.get("BOW_SPEC") as Dictionary)[kind]
	var fing: Vector3 = (J["at_hand_r"] as Node3D).global_transform * (AR.get("FINGERS") as Vector3)
	var nk: Vector3 = w.global_transform * ((sp["rest"] as Vector3) + (w.get_meta("draw_off", Vector3.ZERO) as Vector3))
	var gp: Vector3 = w.global_transform * (sp["grip"] as Vector3)
	print("[hands] %s f%d atk %.2f style %s  nock-fingers %.3f  grip-lefthand %.3f" % [take, f, (h.atk_t / maxf(h.atk_dur, 0.001)) if h.atk_t >= 0.0 else -1.0, h.atk_style, nk.distance_to(fing), gp.distance_to((J["at_hand_l"] as Node3D).global_position)])

## One take: stage the lane, cast at 0.4 s, record secs of frames from the take's camera.
func _take(out: String, mode: String, lane: String, sk: String, take: String, cam: Camera3D, secs := 3.4) -> void:
	if OS.get_environment("RANGE_SECS") != "":
		secs = float(OS.get_environment("RANGE_SECS"))     # a longer take (Frost Volley runs about 6 s)
	var h = g.hero
	await _stage(lane)
	var z: float = LANES[lane]
	var fps := 30
	var frames := int(secs * fps)
	var cast_at := int(0.4 * fps)
	var aim := Vector3(20.0, 0, z)
	var times: Array = []
	var last := Time.get_ticks_usec()
	for f in frames:
		if take == "walk":
			h.direct_dir = Vector3.RIGHT if f < frames - int(0.6 * fps) else Vector3.ZERO
		if f == cast_at:
			h.use_skill(sk, h.skill_aim(sk, aim))
		match mode:
			"game":
				g.cam.current = true
				# the camera looks ahead of him down the lane (the game's own focus), so the flight's end is in frame
				if not g.has_meta("look_ahead"):
					var mk := Node3D.new()
					g.world.add_child(mk)
					g.set_meta("look_ahead", mk)
				var mk2: Node3D = g.get_meta("look_ahead")
				mk2.global_position = h.global_position + Vector3(7.5, -0.6, 0)
				g.focus_node = mk2
				g.focus_len = 9999.0
				g.focus_t = maxf(g.focus_t, 1.0)
				g.focus_zoom = 1.0
			"follow":
				cam.current = true
				var focus: Vector3 = h.global_position + Vector3(0.8, 1.3, 0)
				if not h.arrows.is_empty() and is_instance_valid(h.arrows[0]["node"]):
					focus = (h.arrows[0]["node"] as Node3D).global_position
					cam.set_meta("last", focus)
				elif cam.has_meta("last") and f > cast_at + 10:
					focus = cam.get_meta("last")
				# beside and a little behind the arrow, low, looking along its flight
				var cp := focus + Vector3(-1.5, 0.55, 2.3)
				cam.fov = 40
				cam.global_transform = Transform3D(Basis(), cp).looking_at(focus + Vector3(1.4, -0.15, 0), Vector3.UP)
			"impact":
				cam.current = true
				cam.fov = 42
				var at := Vector3(16.5, 0.7, z)
				# from the south, except on the planks: the dark lane's wall stands south of them
				var side := -1.0 if lane == "wood" else 1.0
				cam.global_transform = Transform3D(Basis(), at + Vector3(-3.2, 2.0, 5.4 * side)).looking_at(at + Vector3(0.6, 0, 0), Vector3.UP)
			"anim":
				cam.current = true
				cam.fov = 30
				var hp: Vector3 = h.global_position + Vector3(0, 1.15, 0)
				var off := Vector3(0.2, 0.25, 4.2) if take == "side" else Vector3(2.8, 0.6, 2.9)
				cam.global_transform = Transform3D(Basis(), hp + off).looking_at(hp + Vector3(0.35, 0, 0), Vector3.UP)
				_hands(h, f, take)
		if f == cast_at + 1 or (f > cast_at and not h.arrows.is_empty() and not h.has_meta("arrow_logged")):
			if not h.arrows.is_empty() and is_instance_valid(h.arrows[0]["node"]):
				h.set_meta("arrow_logged", true)
				print("[arrow] %s %s f%d from %s dir %s hero %s" % [mode, take, f, str((h.arrows[0]["node"] as Node3D).global_position), str(h.arrows[0]["dir"]), str(h.global_position)])
		await process_frame
		await RenderingServer.frame_post_draw
		# the frame's cost: from the end of the last save to the end of this draw (the PNG write left out)
		times.append((Time.get_ticks_usec() - last) / 1000.0)
		get_root().get_texture().get_image().save_png("%s/%s_%s_%s_%03d.png" % [out, mode, lane, take, f])
		last = Time.get_ticks_usec()
	h.direct_dir = Vector3.ZERO
	if h.has_meta("arrow_logged"):
		h.remove_meta("arrow_logged")
	for e in g.world.enemies_root.get_children():
		if is_instance_valid(e):
			print("[foe] %s %s at %s life %.0f/%.0f" % [mode, take, str(e.global_position), float(e.get("life")), float(e.get("max_life"))])
	# frame cost: the frames before the cast against the frames with the arrow in flight / the burst
	var pre := 0.0
	for i in range(2, cast_at):
		pre += float(times[i])
	pre /= maxf(1.0, cast_at - 2)
	var fl := 0.0
	var mx := 0.0
	for i in range(cast_at + 8, mini(frames, cast_at + 40)):
		fl += float(times[i])
		mx = maxf(mx, float(times[i]))
	fl /= maxf(1.0, mini(frames, cast_at + 40) - (cast_at + 8))
	print("[range] %s %s %s: %.0f ms/frame before the shot, %.0f during (worst %.0f)" % [mode, lane, take, pre, fl, mx])
	await wait(0.3)
