extends SceneTree
## Reject accidental access to the player's data before constructing any game scene.
func _initialize() -> void:
	if not OS.get_user_data_dir().get_file().begins_with("AshenCrown-NightlyAudit-"):
		printerr("AUDIT ERROR: isolated user directory was not applied")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var mode := args[args.find("--audit-mode") + 1]
	if mode == "isolation":
		print("[AUDIT] isolated user directory verified")
		quit()
		return
	var env = load("res://scripts/build_env.gd")
	env.forced = {"env": "local", "cloud": "0"}
	if mode == "kpi":
		if DisplayServer.get_name() != "headless":
			root.grab_focus()
		var game = load("res://main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
	else:
		# Same late bootstrap as the game's tools. Do not continue after set_script.
		var script = load("res://tools/" + mode + ".gd")
		if script == null:
			printerr("AUDIT ERROR: required contract unavailable: " + mode)
			quit(2)
			return
		set_script(script)
		call("_initialize")
