extends SceneTree
## A strip of the moor's kingsroad (flagstones, dirt shoulders, grass) under a sun, seen from the game camera, without
## loading a zone: for judging the terrain shader quickly. Needs a display (xvfb + software Vulkan is fine):
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 -s tools/visual_audit/terrain_lab.gd \
##     -- out_prefix [zoom ...]
## Writes out_prefix_<zoom>.png for each zoom (default 0.62 and 0.35; the game's camera offset times the zoom).
const CAM_OFFSET := Vector3(0, 17.0, 16.5)

func _initialize():
	_run()

func _strip_mesh(half: float, step: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / step)
	for j in n:
		for i in n:
			var quad := []
			for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var x := -half + (i + c.x) * step
				var z := -half + (j + c.y) * step
				var road := x + sin(z * 0.11) * 1.2
				var dirt := 1.0 - smoothstep(1.8, 2.4, absf(road))
				var cob := 1.0 - smoothstep(1.4, 1.75, absf(road))
				quad.append([Vector3(x, 0, z), Color(dirt, 0.0, cob, 1.0)])
			for q in quad:
				st.set_color(q[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
	return st.commit()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "/tmp/terrain_lab"
	var zooms: Array = []
	for k in range(1, args.size()):
		zooms.append(float(args[k]))
	if zooms.is_empty():
		zooms = [0.62, 0.35]
	var M: GDScript = load("res://scripts/mats.gd")
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var mi := MeshInstance3D.new()
	mi.mesh = _strip_mesh(14.0, 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = M.call("shader", "terrain")
	var cols := {"col_a": Color(0.15, 0.2, 0.08), "col_b": Color(0.21, 0.23, 0.11), "col_accent": Color(0.28, 0.3, 0.13),
		"col_path": Color(0.25, 0.21, 0.16), "col_cliff": Color(0.3, 0.3, 0.28), "wet": 0.3, "cob_shade": 0.72}
	for k in cols:
		mat.set_shader_parameter(k, cols[k])
	mi.material_override = mat
	root3.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	root3.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 36.0
	root3.add_child(cam)
	cam.make_current()
	for z in zooms:
		cam.position = CAM_OFFSET * float(z)
		cam.basis = Basis.looking_at(Vector3(0, 0.3, 0) - cam.position, Vector3.UP)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [prefix, str(z)]
		get_root().get_texture().get_image().save_png(path)
		print("[LAB] ", path)
	quit()
