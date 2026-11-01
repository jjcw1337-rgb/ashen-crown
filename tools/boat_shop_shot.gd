extends SceneTree
## Screenshots of Osric Saltmarrow's boatyard and his boat window:
##   godot --path . -s tools/boat_shop_shot.gd -- outprefix [quality]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(out: String, name: String, frames := 10) -> void:
	for i in frames:
		await process_frame
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.set_quality(int(args[1]) if args.size() > 1 else 2)
	g.ui.close_all()
	await g.load_zone(0, "coast", "from_town")
	var w = g.world
	var osric: Inter = null
	for it in w.interactables:
		if str(it.data.get("role", "")) == "shipwright":
			osric = it
	g.hero.global_position = w.spawns["shipwright"] + Vector3(-2.0, 0, 2.5)
	await shot(out, "boatyard", 16)
	g.hero.global_position = Vector3(9.0, 1.05, 0.0)
	await shot(out, "moored", 10)
	g.hero.gold = 520
	g.hero.global_position = w.spawns["shipwright"]
	g.ui.boat_shop.open(osric, "gull")
	await shot(out, "window", 16)
	quit()
