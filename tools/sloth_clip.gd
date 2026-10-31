extends SceneTree
## A clip of one Hollow Sloth fighting on the Act I moor, from the game camera zoomed in: it roams, sees
## the knight, rears up, stares and roars, and uses its three skills (sweep, slam, pounce) with its
## element's effects. Saves numbered PNG frames; run with --fixed-fps 30 for real-time motion.
## Usage: godot --fixed-fps 30 --path . -s tools/sloth_clip.gd -- outdir fire|ice|storm
var g
var out := ""
var f := 0
var keep_every := 2

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		if f % keep_every == 0:
			get_root().get_texture().get_image().save_png("%s/f%04d.png" % [out, f / keep_every])
		f += 1

func _hero_at(s, d: float, side := 0.0) -> void:
	# south of it (toward the camera), so it faces us
	s.rig.rotation.y = PI
	var fwd: Vector3 = -s.rig.global_transform.basis.z
	var p: Vector3 = s.global_position + fwd * d + s.rig.global_transform.basis.x * side
	p = g.world.free_spot_near(p, 0.5)
	g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
	g.hero.rig.rotation.y = atan2(p.x - s.global_position.x, p.z - s.global_position.z)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var v: String = args[1] if args.size() > 1 else "fire"
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	g.test_immortal = true
	await g.load_zone(0, "wild", "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.hint_lbl.visible = false
	var s = g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.def.get("variant", "") == v)[0]
	# out on the road, everything else cleared away
	var rp: Vector2 = g.world.path_poly[int(g.world.path_poly.size() * 0.35)]
	s.global_position = Vector3(rp.x, g.world.height_at(rp.x, rp.y), rp.y)
	for e in g.world.enemies_root.get_children():
		if e != s and e is Enemy:
			e.queue_free()
	s.sloth.goal = s.global_position + Vector3(0, 0, 40)
	s.sloth.goal_t = 60.0
	s.sloth.idle_t = 99.0
	await process_frame
	g.focus_on(s, 999.0, 0.5)
	# roaming, unseen
	g.hero.phased = true
	_hero_at(s, 9.0, 4.0)
	g.hero.set_process(false)
	await _frames(70)
	# it sees him: rise, stare, roar, drop
	g.hero.phased = false
	_hero_at(s, 8.0)
	await _frames(180)
	# its three skills, one after another
	for m in ["sloth_sweep", "sloth_slam", "sloth_pounce"]:
		_hero_at(s, 2.6 if m != "sloth_pounce" else 8.0)
		s.sloth.queue.clear()
		s.sloth.move = ""
		s.atk_t = -1.0
		var to: Vector3 = g.hero.global_position - s.global_position
		s.rig.rotation.y = atan2(-to.x, -to.z)
		if m == "sloth_pounce":
			s.sloth.pounce_from = s.global_position
			s.sloth.pounce_to = g.hero.global_position - to.normalized() * (s.radius + 0.6)
		s.sloth._start(m)
		s.cooldown = 9.0
		await _frames(int(s.atk_dur * 30.0) + 30)
	print("saved %d frames" % (f / keep_every))
	quit()
