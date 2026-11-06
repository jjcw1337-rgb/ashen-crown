extends SceneTree
## The Plague Doctor's poison cloud, the Last Epidemic's dome or three kills' blood on a strip of moor road at night, with four figures
## standing in it, seen from the game camera, without loading a zone: for judging those effects in a minute.
## Needs a display (xvfb + software Vulkan is fine) and a fixed frame rate, so the effect's time is exact:
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 --fixed-fps 30 \
##     -s tools/visual_audit/fx_lab.gd -- out_prefix [cloud|dome|death|levelup] [tier] [seconds ...]
## Writes out_prefix_<cloud|dome>_<seconds>.png (default 0.6, 1.5 and 3.0 s after it appears; tier 2 = High).
## Scripts are loaded at run time (they need the Sfx autoload).
const CAM_OFFSET := Vector3(0, 17.0, 16.5)

func _initialize():
	_run()

func _strip_mesh(half: float, step: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / step)
	for j in n:
		for i in n:
			for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var x := -half + (i + c.x) * step
				var z := -half + (j + c.y) * step
				var road := x - 1.5 + sin(z * 0.11) * 1.2
				var dirt := 1.0 - smoothstep(1.8, 2.4, absf(road))
				var cob := 1.0 - smoothstep(1.4, 1.75, absf(road))
				st.set_color(Color(dirt, 0.0, cob, 1.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(x, 0, z))
	return st.commit()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "/tmp/fx_lab"
	var what: String = args[1] if args.size() > 1 else "cloud"
	var tier := int(args[2]) if args.size() > 2 else 2
	var times: Array = []
	for k in range(3, args.size()):
		times.append(float(args[k]))
	if times.is_empty():
		times = [0.6, 1.5, 3.0]
	var M: GDScript = load("res://scripts/mats.gd")
	var IF: GDScript = load("res://scripts/infernal_fx.gd")
	var PF: GDScript = load("res://game/heroes/plague/plague_fx.gd")
	var PL: GDScript = load("res://game/heroes/plague/plague.gd")
	IF.set("force_tier", tier)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var ground := MeshInstance3D.new()
	ground.mesh = _strip_mesh(16.0, 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = M.call("shader", "terrain")
	var cols := {"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
		"col_path": Color(0.25, 0.21, 0.16), "col_cliff": Color(0.3, 0.3, 0.28), "wet": 0.3, "cob_shade": 0.72}
	for k in cols:
		mat.set_shader_parameter(k, cols[k])
	ground.material_override = mat
	root3.add_child(ground)
	# night on the moor: a cold moon, a dim ambient, a warm torch off to one side
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52, 30, 0)
	moon.light_energy = 0.32
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.shadow_enabled = true
	root3.add_child(moon)
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.62, 0.3)
	torch.light_energy = 2.0
	torch.omni_range = 9.0
	torch.position = Vector3(6.5, 2.2, 3.0)
	root3.add_child(torch)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	# four figures for scale (and to see the fog round their legs)
	var fig_mat := StandardMaterial3D.new()
	fig_mat.albedo_color = Color(0.32, 0.3, 0.27)
	for p: Vector3 in [Vector3(-1.2, 0, -0.8), Vector3(1.0, 0, 0.4), Vector3(0.2, 0, -2.0), Vector3(2.6, 0, 2.2)]:
		var f := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.75
		f.mesh = cap
		f.material_override = fig_mat
		f.position = p + Vector3(0, 0.875, 0)
		root3.add_child(f)
	var cam := Camera3D.new()
	cam.fov = 36.0
	root3.add_child(cam)
	cam.make_current()
	var zoom := 0.62 if what == "cloud" else 0.9
	cam.position = CAM_OFFSET * zoom
	cam.basis = Basis.looking_at(Vector3(0, 0.3, 0) - cam.position, Vector3.UP)
	for f in 3:
		await process_frame
	# the effect, built as plague.gd builds it (or a kill's blood: Fx.splat and Fx.gore, as enemy.gd's death)
	var fx := Node3D.new()
	root3.add_child(fx)
	fx.global_position = Vector3.ZERO
	if what == "death" or what == "levelup":
		var FX: GDScript = load("res://scripts/fx.gd")
		var HF: GDScript = load("res://scripts/holy_fx.gd")
		if what == "levelup":
			HF.call("level_up", null, fx, Vector3(1.0, 0.0, 0.4))
		for k in (3 if what == "death" else 0):
			var at := Vector3(-2.0 + k * 2.0, 0.0, 1.2 - k * 0.6)
			var col: Color = [Color(0.4, 0.0, 0.0), Color(0.35, 0.03, 0.02), Color(0.15, 0.35, 0.05)][k]
			FX.call("splat", fx, at, col, 0.6 + 0.4)
			FX.call("gore", fx, at + Vector3(0, 1.2, 0), col, 0.4)
		var t0 := 0.0
		for want in times:
			while t0 + 0.0001 < float(want):
				await process_frame
				t0 += 1.0 / 30.0
			await RenderingServer.frame_post_draw
			var path0 := "%s_%s_%s.png" % [prefix, what, str(want)]
			get_root().get_texture().get_image().save_png(path0)
			print("[FXLAB] ", path0)
		quit()
		return
	var r := 3.0 if what == "cloud" else 9.0
	var col: Color = PL.get_script_constant_map()["TOXIC" if what == "cloud" else "MIASMA"]
	PF.call("miasma", fx, Vector3.ZERO, r, col)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.8
	l.omni_range = r * 1.3
	l.position = Vector3(0, 0.8, 0)
	fx.add_child(l)
	if what == "dome":
		var shell := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 1.1
		s.is_hemisphere = true
		s.radial_segments = 48
		s.rings = 16
		shell.mesh = s
		var sh := ShaderMaterial.new()
		sh.shader = PL.call("_dome_shader")
		sh.set_shader_parameter("col", col)
		sh.set_shader_parameter("amt", 1.0)
		shell.material_override = sh
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx.add_child(shell)
		PF.call("dome_rim", fx, Vector3.ZERO, r, Color(0.55, 1.0, 0.25))
	var t := 0.0
	for want in times:
		while t + 0.0001 < float(want):
			await process_frame
			t += 1.0 / 30.0
		await RenderingServer.frame_post_draw
		var path := "%s_%s_%s.png" % [prefix, what, str(want)]
		get_root().get_texture().get_image().save_png(path)
		print("[FXLAB] ", path)
	quit()
