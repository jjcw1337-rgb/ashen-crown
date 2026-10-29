extends SceneTree
## Frames of the forest camp's shopkeepers (ForestCamp) side by side, each playing one of its clips, for a
## preview clip. Needs a display. Usage: godot --fixed-fps 30 -s tools/npc_clip.gd -- outdir [work|talk|idle]
func _initialize():
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "work"
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.1, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root3.add_child(sun)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 2.0
	warm.omni_range = 12.0
	warm.position = Vector3(0, 2.5, 3.5)
	root3.add_child(warm)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = Mats.mat(Color(0.18, 0.16, 0.12), 0.95)
	root3.add_child(ground)
	var keepers := [["maeve", ForestCamp.SHOPS[0]["clips"]], ["grisold", ForestCamp.SHOPS[1]["clips"]],
		["hedda", ForestCamp.SHOPS[2]["clips"]], ["tarrow", ForestCamp.SHOPS[3]["clips"]],
		["roth", {"idle": "Idle", "work": ["Short_Breathe_and_Look_Around"], "talk": "Talk_Passionately"}]]
	var players := []
	var x := -4.4
	for k in keepers:
		var m: Node3D = (load(ForestCamp.NPC_DIR + k[0] + ".glb") as PackedScene).instantiate()
		root3.add_child(m)
		m.position = Vector3(x, 0, 0)
		x += 2.2
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		var clips: Dictionary = k[1]
		var name: String = clips["work"][0] if which == "work" else String(clips[which])
		ap.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		ap.play(name)
		players.append(ap)
		for sh in ForestCamp.SHOPS:
			if sh["npc"] == k[0] and sh.has("hold"):
				ForestCamp.hold(m, sh["hold"])
		print("[N] ", k[0], " plays ", name)
	var cam := Camera3D.new()
	cam.fov = 32
	root3.add_child(cam)
	cam.transform = Transform3D(Basis(), Vector3(0, 2.2, 7.6)).looking_at(Vector3(0, 1.0, 0))
	for f in 90:
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/n%03d.png" % [out, f])
	quit()
