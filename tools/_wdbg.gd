extends SceneTree
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.set_quality(int(OS.get_cmdline_user_args()[1]))
	await g.load_zone(0, "coast", "dock")
	g.ui.visible = false
	g.hero.global_position = Vector3(8.0, 1.05, 0.5)
	for i in 12:
		await process_frame
	var oc = g.world.get_node("Ocean")
	print("OCEAN pos ", oc.global_position, " mesh ", oc.mesh_i.mesh, " shader ", oc.mat.shader, " vis ", oc.mesh_i.visible, " inside ", oc.mesh_i.is_visible_in_tree())
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
