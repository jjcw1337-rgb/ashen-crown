extends SceneTree
## Screenshots of a run character's windows (RunUI, the multiplayer look): the build window, a gear swap and a camp
## upgrade offer, for an archer and a plague doctor. `-- outdir [WxH]` (needs a display).
var g
var out := "user://run_ui"

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func shot(name: String) -> void:
	for i in 8:
		await process_frame
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[SHOT] ", out.path_join(name + ".png"))

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	await g.load_zone(0, "wild", "start")
	g.ui.hide_title()
	var RB = load("res://game/items/run_build.gd")
	var I = load("res://game/items/items.gd")
	for cls in ["archer", "plague"]:
		var h = g.hero
		h.set_class(cls)
		h.start_run()
		h.add_xp(RB.xp_for(0) + RB.xp_for(1) + RB.xp_for(2) + 20)
		g.ui.close_all()
		g.ui.run_ui.open_build()
		await shot(cls + "_build_empty")
		var pool: Array = RB.skill_pool(cls)
		for i in mini(7, pool.size()):
			h.run.add_skill(str(pool[i]["id"]), h.binds)
		h.run.passives = {"g_hide": 2, "g_instinct": 1}
		for p in RB.passive_pool(cls):
			if p.has("tree") and not p.has("needs"):
				h.run.passives[p["id"]] = 1
				break
		h.run.camps = 4
		h.run_changed()
		g.ui.run_ui.open_build()
		await shot(cls + "_build")
		var r2 = RB.new()
		h.run.skills = h.run.skills.slice(0, 2)
		h.run.check_binds(h.binds)
		g.ui.run_ui.open_offer("camp_shot", 3, "Moss Hollow")
		await shot(cls + "_offer")
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var w: Dictionary = I.generate(RB.weapon_base(cls, 13, rng), 13, 2, rng)
		g.ui.run_ui.open_swap(w, null)
		await shot(cls + "_swap")
		g.ui.run_ui.close()
	quit(0)
