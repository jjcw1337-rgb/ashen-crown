extends SceneTree
## King Grubb and his Gold Grabbers next to a knight, for checking the models and poses.
## Usage: -- out.png [face|side|back] [calm|atk=<style>:<0..1>|walk|carry]
var extra: Array = []

func _initialize():
	var args := OS.get_cmdline_user_args()
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.025, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.44, 0.45, 0.52)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	root3.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	root3.add_child(key)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.7, 0.35)
	warm.light_energy = 3.0
	warm.omni_range = 9.0
	warm.position = Vector3(-2.5, 2.5, 2.5)
	root3.add_child(warm)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = Mats.world(Color(0.22, 0.2, 0.19), Color(0.14, 0.13, 0.12), 0.9, 1.4, 0.0, Props.MOSS, false)
	root3.add_child(ground)
	var mound := MeshInstance3D.new()
	mound.mesh = Goblin.mound_mesh(1.4, 0.6)
	mound.material_override = Goblin.coin_mat()
	mound.position = Vector3(-2.2, 0, -1.8)
	root3.add_child(mound)
	var pile := Goblin.pile(30)
	root3.add_child(pile)
	pile.position = Vector3(1.5, 0, 1.6)
	var king := Goblin.build("mutant")
	root3.add_child(king)
	if args.has("compare"):
		# the code-built body on the left, the Blender one (king) on the right
		Goblin.use_blender = false
		var coded := Goblin.build("king")
		Goblin.use_blender = true
		root3.add_child(coded)
		coded.position = Vector3(-1.6, 0, 0)
		coded.rotation_degrees.y = 200
		king.position = Vector3(1.0, 0, 0)
		extra.append(coded)
	king.rotation_degrees.y = 200 if not args.has("side") else 270
	if args.has("back"):
		king.rotation_degrees.y = 20
	var grabbers := []
	var nogrub := args.has("compare")
	for i in (0 if nogrub else 3):
		var g := Goblin.build("grabber")
		root3.add_child(g)
		g.position = Vector3(-1.8 + i * 1.5, 0, 1.4 + (i % 2) * 0.5)
		g.rotation_degrees.y = 190 + i * 15
		grabbers.append(g)
	var hero := Knight.build(Knight.default_gear())
	root3.add_child(hero)
	hero.position = Vector3(2.4, 0, 0.6)
	hero.rotation_degrees.y = 150
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0.3, 2.3, 5.6)).looking_at(Vector3(0.0, 1.1, 0))
	cam.fov = 45
	if args.has("face"):
		cam.transform = Transform3D(Basis(), Vector3(0.35, 2.0, 1.5)).looking_at(Vector3(0.0, 1.75, 0))
		cam.fov = 40
	if args.has("iso"):
		cam.transform = Transform3D(Basis(), Vector3(0.0, 9.0, 8.0)).looking_at(Vector3(0.0, 0.8, 0))
		cam.fov = 40
	var style := ""
	var at := -1.0
	for a in args:
		if a.begins_with("atk="):
			var parts: PackedStringArray = a.substr(4).split(":")
			style = parts[0]
			at = float(parts[1]) if parts.size() > 1 else 0.4
	if args.has("carry"):
		for g in grabbers:
			g.set_meta("carry", true)
	var frames := 40
	for f in frames:
		var t := 2.0 + f / 30.0
		var walk := args.has("walk")
		var st := {"time": t, "phase": t * 6.0 if walk else 0.0, "move": 1.0 if walk else 0.0, "aggro": not args.has("calm")}
		if at >= 0.0:
			st["atk"] = at
			st["style"] = style
		if not args.has("nopose"):
			Anim.pose(king, st)
			for x in extra:
				Anim.pose(x, st)
		for g in grabbers:
			Anim.pose(g, {"time": t + g.position.x, "phase": t * 9.0 if walk or args.has("carry") else 0.0, "move": 1.0 if walk or args.has("carry") else 0.0, "aggro": true})
		Anim.pose(hero, {"time": 1.0 + f / 30.0, "phase": 0.0, "move": 0.0})
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("saved")
	quit()
