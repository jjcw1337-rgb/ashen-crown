extends SceneTree
## Stages a candidate boss model (any .glb) in King Grubb's vault, lit like the game, next to the
## hero, and saves screenshots: the gameplay camera, a closer three-quarter view and the face.
## Doesn't touch the game's data: a mock-up for picking a model before wiring it in.
## Usage: -- res://path/model.glb out_prefix [height_m]
var g

func _initialize():
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var out: String = args[1]
	var hgt := float(args[2]) if args.size() > 2 else 2.3
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "lair", "boss_room")
	g.test_immortal = true
	# the real boss stays (hidden) so the room is lit and staged as in play; the candidate stands in his place
	var boss: Enemy = null
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.boss:
			boss = e
	var at: Vector3 = boss.global_position
	for e in g.world.enemies_root.get_children():
		if e is Enemy:
			e.visible = e.kind == "grabber"
			e.set_process(false)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	g.world.add_child(model)
	var aabb := _aabb(model)
	var s := hgt / maxf(aabb.size.y, 0.001)
	model.scale = Vector3.ONE * s
	model.global_position = at - Vector3(0, aabb.position.y * s, 0)
	# turn it toward the hero's spot (models disagree on which way is forward: pass "flip")
	model.rotation.y = 0.35 + (PI if args.has("flip") else 0.0)
	# the boss's lights: a warm key in front, a cold rim behind
	for spec in [[Vector3(1.2, hgt * 1.4, 2.2), Color(1.0, 0.78, 0.5), 2.0], [Vector3(-0.6, hgt * 1.3, -1.8), Color(0.45, 0.6, 1.0), 2.6]]:
		var l := OmniLight3D.new()
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.omni_range = 6.0
		g.world.add_child(l)
		l.global_position = at + spec[0]
	var anim := model.find_children("*", "AnimationPlayer", true, false)
	if not anim.is_empty():
		var ap: AnimationPlayer = anim[0]
		var names := ap.get_animation_list()
		if not names.is_empty():
			ap.play(names[0])
	var h = g.hero
	h.global_position = g.world.free_spot_near(at + Vector3(0.4, 0, 3.2), 0.5)
	h.rotation.y = 0.0
	g.playing = true
	for shot in [["game", 1.0], ["close", 0.55]]:
		g.zoom = shot[1]
		for f in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out + "_" + shot[0] + ".png")
	# a portrait: our own camera on the head
	var cam := Camera3D.new()
	g.world.add_child(cam)
	var top := at + Vector3(0, hgt * 0.82, 0)
	cam.global_position = top + Vector3(0.6, 0.15, 2.2) * (hgt / 2.3)
	cam.look_at(top, Vector3.UP)
	cam.fov = 35
	cam.make_current()
	g.ui.visible = false
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "_face.png")
	print("[V] saved ", out, " scale ", s, " aabb ", aabb)
	quit()

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var b: AABB = m.get_aabb()
		var xf: Transform3D = Transform3D.IDENTITY
		var p: Node = m
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		b = xf * b
		out = b if first else out.merge(b)
		first = false
	return out
