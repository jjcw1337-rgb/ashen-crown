extends SceneTree
## One simulated smoke book (DemonKitFx.smoke) played on bare ground under the game camera, saved at a few moments:
## checks how a card stands, where it is anchored and how it blends. Needs a display and fixed frames:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 960x540 --fixed-fps 30 \
##     -s tools/_late.gd -- res://tools/smoke_book_shot.gd <outprefix> <kind> [size m] [secs per pass] [zoom]
## Writes <outprefix>_<kind>_<frame>.png at 0.1 s steps through the book (a loop: through one pass).

func _initialize():
	_run()

func _run() -> void:
	var args: Array = Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("res://"))
	var out: String = args[0] if args.size() > 0 else "/tmp/smoke"
	var kind: String = args[1] if args.size() > 1 else "impact"
	var size: float = float(args[2]) if args.size() > 2 else 6.0
	var secs: float = float(args[3]) if args.size() > 3 else 2.0
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# the moor's mist (fog must not wash over a card: SMOKE_SHADER has fog_disabled)
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.56, 0.52)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-35, -60, 0)
	root.add_child(sun)
	# moor-coloured ground, a post for scale (1.8 m, like a man) beside where it lands
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.23, 0.25, 0.17)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 1.8, 0.3)
	post.mesh = bm
	post.position = Vector3(size * 0.45, 0.9, 1.0)
	root.add_child(post)
	# the game camera: its offset at the usual zoom, looking down at 44 degrees
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	var zoom: float = float(args[4]) if args.size() > 4 else 0.62
	var off := Vector3(0, 17.0, 16.5) * zoom
	cam.global_transform = Transform3D(Basis(), off).looking_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	var kfx = load("res://scripts/demon_kit_fx.gd")
	var b: Array = kfx.BOOKS[kind]
	var loop: bool = kind in ["comet", "steam"]
	var at := Vector3(0, 1.4, 0) if kind == "comet" else Vector3.ZERO
	var card = kfx.smoke(root, at, kind, size, secs, loop, Color.WHITE, Vector3(1, -0.25, -0.4))
	var steps := int(secs * 10.0)
	for i in steps + 1:
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s_%s_%02d.png" % [out, kind, i])
		if not is_instance_valid(card):
			break
	print("[smoke shot] ", kind, " frames ", steps + 1, " book ", b[0])
	quit()
