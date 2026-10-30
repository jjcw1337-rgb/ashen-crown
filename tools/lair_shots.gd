extends SceneTree
## Screenshots of the Hollow Sloths' lairs (sloth_lair.gd) from the game camera: Cinder Hollow, Rimefrost
## Glade and Stormcall Ring with their sloths at home. Needs a display.
## Usage: godot --path . -s tools/lair_shots.gd -- outdir [zoom]
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(name: String, frames := 6) -> void:
	for f in frames:
		await process_frame
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/" + name + ".png")
	print("[C] ", name)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var zoom: float = float(args[1]) if args.size() > 1 else 0.9
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
	g.hero.phased = true        # unseen, so they keep to their lairs
	for l in g.world.props_root.get_children().filter(func(n): return n is SlothLair):
		var p: Vector3 = l.global_position + Vector3(0, 0, SlothLair.CLEAR + 2.0)
		g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
		g.focus_on(l, 999.0, zoom)
		await _snap("lair_" + l.element, 120)
	quit()
