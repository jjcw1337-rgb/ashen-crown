extends SceneTree
## Screenshots of woodcutting and tempering, from the game camera (needs a display; xvfb works, colours are
## llvmpipe's): a harvestable oak with its blaze, mid-chop (the notch, chips), the fall, the logs on the ground,
## the stump; the Ashen Heartwood; then the camp's furnace cold, and the furnace window heating a weapon.
## (No static types from the game here: a -s tool compiles before the Sfx autoload exists.)
## Usage: xvfb-run -a godot --rendering-driver opengl3 --path . --fixed-fps 30 -s tools/woodcut_shots.gd -- outdir [class]
var g
var out := "/tmp/woodcut"

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		if g.world != null:
			for e in g.world.enemies_root.get_children():
				e.queue_free()
		await process_frame

func shot(name: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[S] ", name)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var cls := args[1] if args.size() > 1 else "knight"
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.test_immortal = true
	g.ui.close_all()
	await g.load_zone(0, "wild", "start")
	# software GL under xvfb: the Low preset and no shadows make the frames bearable
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	await frames(10)
	var h = load("res://scripts/harvest.gd").of(g.world)
	var oak = null
	var heart = null
	for t in h.trees:
		if t.tkind == "oak" and oak == null:
			oak = t
		if t.tkind == "heart" and heart == null:
			heart = t
	g.zoom = 0.75
	# the oak, from where you'd walk up to it
	g.hero.global_position = oak.global_position + Vector3(oak.radius + 3.0, 0, 1.5)
	await frames(40)
	g.ui.close_all()
	await shot("01_oak")
	g.hero.global_position = oak.global_position + Vector3(oak.radius - 0.15, 0, 0)
	g.hero.start_chop(oak)
	# mid-swing, the axe back
	var guard := 0
	while not (g.hero.atk_skill == "chop" and g.hero.atk_t / g.hero.atk_dur > 0.38) and guard < 300:
		await frames(1)
		guard += 1
	await shot("02_windup")
	while not (g.hero.atk_skill == "chop" and g.hero.atk_t / g.hero.atk_dur > 0.57) and guard < 600:
		await frames(1)
		guard += 1
	await shot("03_bite")
	while oak.hp > 1.5 and guard < 6000:
		await frames(1)
		guard += 1
	await frames(10)
	await shot("04_notch")
	while oak.state == "stand" and guard < 9000:
		await frames(1)
		guard += 1
	await frames(20)
	await shot("05_falling")
	await frames(25)
	await shot("06_crash")
	await frames(40)
	await shot("07_logs")
	await frames(120)
	await shot("08_stump")
	# Ashen Heartwood
	g.hero.global_position = heart.global_position + Vector3(heart.radius + 2.0, 0, 1.0)
	await frames(40)
	await shot("09_heartwood")
	# the furnace
	await g.load_zone(0, "town", "start")
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	await frames(10)
	var f = null
	for t in g.world.interactables:
		if t.kind == "furnace":
			f = t
	g.hero.global_position = f.global_position + f.global_transform.basis * Vector3(0.4, 0, 3.0)
	g.ui.close_all()
	await frames(40)
	await shot("10_furnace_cold")
	g.hero.inventory.fill(null)
	g.hero.add_to_inventory(Items.resource("oak_log", 30))
	g.hero.add_to_inventory(Items.resource("pine_log", 18))
	g.hero.add_to_inventory(Items.resource("heartwood", 3))
	g.hero.gold = 5000
	g._interact(f)
	await frames(20)
	await shot("11_window_ready")
	f.load_fuel(g.hero, "oak_log", 14)
	f.ignite(g.hero)
	for i in 300:
		f.step(0.1)
	await frames(30)
	await shot("12_window_heating")
	g.ui.close_all()
	await frames(20)
	await shot("13_furnace_hot")
	quit()
