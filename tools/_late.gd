extends SceneTree
## Runs another tool script after the autoloads exist (a static reference to Hero and co. compiles them before the
## Sfx autoload in some containers: "Identifier not found: Sfx"). Usage: godot --headless --path . -s tools/_late.gd -- res://tools/x_test.gd [args]
func _initialize():
	var a := OS.get_cmdline_user_args()
	var path := ""
	for x in a:
		if x.begins_with("res://"):
			path = x
	var s: Script = load(path)
	set_script(s)
	call("_initialize")
