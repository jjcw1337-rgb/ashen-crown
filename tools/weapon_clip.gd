extends SceneTree
## Frames of the knight running and swinging, from the game camera zoomed right in, to look at how his
## weapon moves (every frame kept). Usage: godot --fixed-fps 30 --path . -s tools/weapon_clip.gd -- outdir [armored]
var g
var out := ""
var f := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frames(n: int, each: Callable = Callable()) -> void:
	for i in n:
		if each.is_valid():
			each.call(i)
		await process_frame
		get_root().get_texture().get_image().save_png("%s/f%04d.png" % [out, f])
		f += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.test_immortal = true
	g.ui.close_all()
	g.ui.hint_lbl.visible = false
	g.hero.equipment["weapon"] = Items.make("broad_sword", 0, 1)
	if args.has("armored"):
		g.hero.equipment["armor"] = {"base": "chain_mail", "rarity": 0, "affixes": [], "stats": {}}
	g.hero.recalc()
	g.hero.refresh_gear()
	await process_frame
	g.focus_on(g.hero, 999.0, 0.32)
	var c: Vector3 = g.hero.global_position
	# run in a circle
	await _frames(45, func(i):
		var a: float = i * 0.12
		g.hero.cmd_move(c + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), true))
	# stand and swing
	g.hero.cmd_move(g.hero.global_position)
	await _frames(45, func(i):
		if i % 15 == 0:
			g.hero.swipe_attack(g.hero.global_position + Vector3(0, 0, -3)))
	print("saved %d frames" % f)
	quit()
