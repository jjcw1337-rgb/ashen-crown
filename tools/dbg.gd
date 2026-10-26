extends SceneTree
func _initialize():
	var w := World.new()
	get_root().add_child(w)
	var t := Time.get_ticks_msec()
	w.build(0, "wild", 4207)
	print("build ms ", Time.get_ticks_msec() - t)
	var g = w.props_root.get_node_or_null("Grass")
	print("grass ", g.multimesh.instance_count if g else -1)
	print("enemy packs ", w.enemy_spawns.size(), " obstacles ", w.obstacles.size())
	print("dirt at start ", w.dirt_at(0, -6), " at 20,-50 ", w.dirt_at(20, -50))
	quit()
