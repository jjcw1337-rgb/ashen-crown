extends SceneTree
## Screenshots of the inventory window (UI._build_inventory) with gear on and a stocked bag, and the window
## alone at full size. Needs a display. Usage: godot --path . -s tools/inventory_shot.gd -- outdir
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var h = g.hero
	h.equipment["weapon"] = Items.generate("broad_sword", 10, 2, r)
	h.equipment["shield"] = Items.generate(Items.pick_base(10, r, "shield"), 10, 1, r)
	h.equipment["helm"] = Items.generate("great_helm", 10, 0, r)
	h.equipment["armor"] = Items.generate(Items.pick_base(10, r, "armor"), 10, 1, r)
	h.equipment["gloves"] = Items.generate(Items.pick_base(10, r, "gloves"), 10, 0, r)
	h.equipment["boots"] = Items.generate(Items.pick_base(10, r, "boots"), 10, 2, r)
	h.equipment["belt"] = Items.generate(Items.pick_base(10, r, "belt"), 10, 0, r)
	h.equipment["ring1"] = Items.generate("ring", 10, 1, r)
	h.equipment["amulet"] = Items.generate("amulet", 10, 2, r)
	for i in 17:
		h.inventory[(i * 7) % 40] = Items.random_drop(10, 250, r)
	h.gold = 12480
	h.recalc()
	h.refresh_gear()
	g.ui.toggle(g.ui.inv_panel) if g.ui.has_method("toggle") else null
	g.ui.inv_panel.visible = true
	g.ui.refresh()
	for f in 50:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(out + "/inventory_screen.png")
	var rc: Rect2 = g.ui.inv_panel.get_global_rect()
	var k: float = img.get_width() / get_root().get_visible_rect().size.x
	img.get_region(Rect2i(rc.position * k, rc.size * k)).save_png(out + "/inventory.png")
	print("[I] saved, window %s" % rc)
	quit()
