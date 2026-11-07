extends SceneTree
## Screenshots of Halvar's furnace (furnace.gd) and its window (furnace_ui.gd): cold, the window charged, the window
## with the fire at yellow heat and the weapon soaking, the furnace roaring. Needs a display (xvfb; llvmpipe colours).
## (No static types from the game here: a -s tool compiles before the Sfx autoload exists.)
## Usage: xvfb-run -a godot --rendering-driver opengl3 --path . --fixed-fps 30 -s tools/furnace_shot.gd -- outdir
var g
var out := "/tmp/furnace"

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
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
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	var f = null
	for t in g.world.interactables:
		if t.kind == "furnace":
			f = t
	g.ui.close_all()
	g.zoom = 0.7
	g.hero.global_position = f.global_position + f.global_transform.basis * Vector3(-0.6, 0, 3.2)
	await frames(12)
	await shot("10_furnace_cold")
	g.hero.inventory.fill(null)
	g.hero.add_to_inventory(Items.resource("oak_log", 30))
	g.hero.add_to_inventory(Items.resource("pine_log", 18))
	g.hero.add_to_inventory(Items.resource("heartwood", 3))
	g.hero.gold = 5000
	g._interact(f)
	f.load_fuel(g.hero, "oak_log", 9)
	await frames(10)
	await shot("11_window_charged")
	f.ignite(g.hero)
	for i in 600:
		f.step(0.1)
	f.soak = float(f.cost["soak"]) * 0.6
	await frames(12)
	await shot("12_window_heating")
	g.ui.furnace_ui.visible = false
	g.ui.inv_panel.visible = false
	f.lit = true
	f.hopper.append_array(["oak_log", "oak_log", "oak_log"])
	f.bellows = true
	await frames(12)
	await shot("13_furnace_hot")
	quit()
