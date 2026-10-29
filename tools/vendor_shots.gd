extends SceneTree
## Screenshots of a camp trader from the game camera (with their nameplate), their trade window, and
## the window's portrait on its own. Needs a display.
## Usage: godot -s tools/vendor_shots.gd -- outdir [smith|armor|alch|gamble]
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
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	var args := OS.get_cmdline_user_args()
	var role: String = args[1] if args.size() > 1 else "smith"
	var v: Inter = null
	for it in g.world.interactables:
		if it.kind == "vendor" and it.data.get("role", "") == role:
			v = it
	var fwd := Vector3(sin(v.home_yaw), 0, cos(v.home_yaw))
	g.hero.global_position = g.world.free_spot_near(v.global_position + fwd * 4.5, 0.4)
	await _snap("near_" + role, 40)
	g._interact(v)
	for b in g.ui.dialog_btns.get_children():
		if b is Button and (b as Button).text == "Trade":
			(b as Button).pressed.emit()
	await _snap("trade_" + role, 30)
	var pt: VendorUI.Portrait = g.ui.shop_face.get_child(0)
	pt.vp.get_texture().get_image().save_png(args[0] + "/portrait_" + role + ".png")
	quit()
