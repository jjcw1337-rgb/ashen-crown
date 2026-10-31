extends SceneTree
## Frames of the title screen's motion: hovering Continue (the lean, the light, the signature move), then the
## move into it. Run with --fixed-fps 30 so frames are evenly spaced:
##   xvfb-run -a godot --rendering-driver opengl3 --fixed-fps 30 --resolution 960x540 --path . -s tools/title_clip.gd -- outdir
var g
const DIR := "user://clip_title_characters/"
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	g.char_dir = DIR
	g.old_save = DIR + "none.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + "aldric.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "Aldric", "hero": {"cls": "knight", "level": 14, "equipment": {"weapon": Items.make("short_sword"), "shield": Items.make("buckler")}}, "played": 1}))
	f.close()
	g.ui.show_title()
	await _frames(20)
	var k := 0
	g.ui.title_stage.set_focus("continue")
	g.ui._title_hover("continue")
	for i in 8:
		await _frames(6)
		get_root().get_texture().get_image().save_png("%s/f%02d.png" % [out, k])
		k += 1
	# the move into Continue (without starting the game)
	var tw: Tween = g.ui.create_tween()
	tw.tween_property(g.ui._title_fade, "color", Color(0, 0, 0, 1), 0.3).set_delay(0.25)
	g.ui.title_stage.enter("continue")
	for i in 6:
		await _frames(3)
		get_root().get_texture().get_image().save_png("%s/f%02d.png" % [out, k])
		k += 1
	print("saved ", k, " frames")
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fn)
	DirAccess.remove_absolute(DIR)
	quit()
