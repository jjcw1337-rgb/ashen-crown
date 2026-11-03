extends SceneTree
## Screenshots of the shared stash's window (UI._build_stash) in each tab look (UI.STASH_STYLES: plaques, ribbons,
## gems), stocked, with the bag beside it: the whole screen and the window alone. Needs a display.
## Usage: godot --path . -s tools/stash_shot.gd -- outdir [style]
var g

func _initialize():
	DirAccess.remove_absolute(SharedStash.TEST_PATH)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var styles: Array = [a[1]] if a.size() > 1 else ["plaques", "ribbons", "gems"]     # (UI.STASH_STYLES)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var h = g.hero
	h.set_level(18)
	for i in 14:
		h.inventory[(i * 3) % 40] = Items.random_drop(18, 300, r)
	# the stash: tab I well stocked (rares, uniques, potions, a material), the others with a few each
	var st: SharedStash = g.stash
	var uniq := Data.UNIQUES.keys()
	for i in 34:
		var it: Dictionary
		if i % 9 == 0 and not uniq.is_empty():
			it = Items.make_unique(str(uniq[(i / 9) % uniq.size()]))
		elif i % 7 == 3:
			it = Items.potion(["hp_potion", "mp_potion"][i % 2]) if Data.BASES.has("hp_potion") else Items.random_drop(18, 400, r)
		else:
			it = Items.random_drop(18, 400, r)
		st.tabs[0][(i * 17) % 60] = it
	for t in range(1, 5):
		for i in 3 + t * 4:
			st.tabs[t][(i * 11 + t) % 60] = Items.random_drop(18, 300, r)
	if Data.BASES.has("cinderheart"):
		st.tabs[0][59] = Items.make("cinderheart", 0, 1)
	st.save()
	g.cur_zone = "town"
	g.ui.open_stash()
	for s in styles:
		g.ui.set_stash_style(s)
		g.ui.stash_tab = 0
		g.ui.refresh()
		for f in 90:          # (the item icons render over the first frames)
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out + "/stash_%s_screen.png" % s)
		var rc: Rect2 = g.ui.stash_panel.get_global_rect()
		var k: float = img.get_width() / get_root().get_visible_rect().size.x
		img.get_region(Rect2i(rc.position * k, rc.size * k)).save_png(out + "/stash_%s.png" % s)
		print("[SS] %s saved, window %s" % [s, rc])
	DirAccess.remove_absolute(SharedStash.TEST_PATH)
	quit()
