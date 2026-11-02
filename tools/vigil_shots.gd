extends SceneTree
## Screenshots of the Last Flame (vigil.gd) from the game's camera: the camp's Vigil Gate, the sanctum before a
## vigil, a wave fighting for the flame (and `frames` frames of it for a GIF, every third frame):
##   godot --path . -s tools/vigil_shots.gd -- outdir [frames] [class]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func shot(path: String) -> void:
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _inter(kind: String):
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == kind:
			return t
	return null

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/vigil"
	var nf: int = int(a[1]) if a.size() > 1 else 40
	var cls: String = a[2] if a.size() > 2 else "demon"
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.ui.close_all()
	g.test_immortal = true
	g.hero.set_level(12)
	if g.cur_zone != "town":
		await g.load_zone(0, "town", "start")
	var gate = _inter("vigil_gate")
	var gp: Vector3 = gate.global_position
	g.hero.global_position = g.world.free_spot_near(gp + Vector3(-2.5, 0, -2.5), 1.0)
	await frames(200)
	shot(out + "/vigil_camp_gate.png")
	g._interact(gate)
	while g.cur_zone != "vigil" or g._busy:
		await process_frame
	var v = g.world.get_meta("vigil")
	g.hero.global_position = g.world.free_spot_near(v.CENTER + Vector3(2.5, 0, 5.0), 1.0)
	await frames(60)
	shot(out + "/vigil_sanctum.png")
	# a vigil, straight to wave 3
	v.begin()
	v.wave = 2
	v.t = 0.2
	await frames(30)
	g.hero.global_position = g.world.free_spot_near(v.CENTER + Vector3(1.5, 0, -3.0), 1.0)
	var k := 0
	var t0 := Time.get_ticks_msec()
	var fi := 0
	while Time.get_ticks_msec() - t0 < 60000 and fi < nf:
		k += 1
		var z = null
		var bd := INF
		for e in g.world.enemies_root.get_children():
			if "pvp_pid" in e and not e.dead and e.pvp_pid == 0:
				var d: float = e.global_position.distance_to(g.hero.global_position)
				if d < bd:
					bd = d
					z = e
		if z != null and bd < 7.0:
			if k % 150 == 0 and g.hero.cls == "demon":
				g.hero.mana = g.hero.max_mana
				g.hero.use_skill("fists", z.global_position)
			elif g.hero.target != z:
				g.hero.target = z
		if k > 420 and k % 3 == 0:
			shot("%s/mode_frame_%03d.png" % [out, fi])
			fi += 1
		if k == 400:
			shot(out + "/vigil_wave.png")
		await process_frame
	await frames(20)
	shot(out + "/vigil_fight.png")
	quit()
