extends SceneTree
## Screenshot of the skill picker (click a bar slot) with one skill hovered.
## Needs a display. Usage: godot -s tools/picker_shot.gd -- out.png [slot] [class]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var slot: String = args[1] if args.size() > 1 else "Q"
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, args[2] if args.size() > 2 else "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.hero.set_level(4)
	g.hero.recalc()
	g.ui.refresh_skill_slots()
	await process_frame
	g.ui._choose_skill(slot)
	for f in 20:
		await process_frame
	# hover the second skill
	var cards: Array = []
	for c in g.ui.skill_picker.find_children("*", "PanelContainer", true, false):
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			cards.append(c)
	if cards.size() > 1:
		cards[1].mouse_entered.emit()
		Input.warp_mouse(cards[1].get_global_rect().get_center())
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[0])
	print("[S] saved ", cards.size())
	quit()
