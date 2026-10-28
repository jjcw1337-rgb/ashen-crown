extends SceneTree
## Records the gnome Warlock running around town (run with Godot's movie writer):
##   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie out/f.png -s tools/gnome_clip.gd
## He jogs a loop past the waypoint and the stalls, then sprints back; the movie ends by itself.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func go(p: Vector3, sprint := false) -> void:
	var h = g.hero
	h.sprint = sprint
	h._set_goal(g.world.free_spot_near(p, 0.6), false)
	for i in 400:
		await process_frame
		if h.global_position.distance_to(h.move_goal) < 0.8 or not h.moving:
			break
func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "warlock")
	g.ui.close_all()
	await g.load_zone(0, "town", "start")
	g.ui.close_all()
	g.zoom = 0.6
	await wait(1.5)
	var s: Vector3 = g.world.spawns["start"]
	await go(s + Vector3(-7, 0, 4))
	await go(s + Vector3(-9, 0, -6))
	await go(s + Vector3(0, 0, -9))
	await go(s + Vector3(8, 0, -5), true)
	await go(s + Vector3(4, 0, 3), true)
	g.hero.sprint = false
	await wait(1.2)
	quit()
