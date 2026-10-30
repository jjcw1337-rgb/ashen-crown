extends SceneTree
## A screenshot of the camp's bonfire window (UI.open_burn) beside a stocked inventory. Needs a display.
## Usage: godot --path . -s tools/bonfire_shot.gd -- out.png
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 12:
		g.hero.inventory[i * 3 % 40] = Items.random_drop(8, 200, r)
	for t in g.world.interactables:
		if t.kind == "bonfire":
			g.hero.global_position = t.global_position + Vector3(0, 0, 3.4)
			g._interact(t)
	for f in 40:
		await process_frame
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
