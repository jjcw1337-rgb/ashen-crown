extends SceneTree
## Frames of the knight's mocap model playing one clip (knight_mocap.glb): -- outdir clip [side|front|34] [frames]
func _initialize():
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var clip: String = a[1]
	var view: String = a[2] if a.size() > 2 else "side"
	var n: int = int(a[3]) if a.size() > 3 else 24
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.33, 0.36, 0.41)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -40, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.26, 0.28, 0.21), 0.95)
	root3.add_child(ground)
	var k: Node3D = (load("res://assets/models/knight_mocap.glb") as PackedScene).instantiate()
	root3.add_child(k)
	var ap: AnimationPlayer = k.find_children("*", "AnimationPlayer", true, false)[0]
	print("clips: ", ap.get_animation_list())
	ap.play(clip)
	ap.pause()
	var len: float = ap.current_animation_length
	var cam := Camera3D.new()
	cam.fov = 30
	root3.add_child(cam)
	var pos: Vector3 = {"side": Vector3(4.6, 1.2, 0.0), "front": Vector3(0.0, 1.3, 4.6), "34": Vector3(3.2, 1.6, 3.2)}[view]
	cam.transform = Transform3D(Basis(), pos).looking_at(Vector3(0, 0.95, 0))
	for f in n:
		ap.seek(len * f / n, true)
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/%s_%s_%02d.png" % [out, clip, view, f])
	print("len ", len)
	quit()
