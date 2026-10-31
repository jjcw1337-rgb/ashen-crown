extends SceneTree
## Screenshots of a Hollow Sloth (sloth.gd) on the Act I moor from the game camera: roaming on all
## fours, risen up to stare, roaring, and the slam. Needs a display.
## Usage: godot -s tools/sloth_shots.gd -- outdir
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

## Holds the sloth in one timed move at progress k (its brain paused), and the hero beside it.
func _hold(s, style: String, k: float) -> void:
	s.atk_style = style
	s.atk_dur = 1.0
	s.atk_t = k
	s.set_process(false)
	s._pose({"time": 2.0, "phase": 0.0, "move": 0.0, "atk": k, "style": style, "hit": 0.0})

func _run() -> void:
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
	var s = g.world.enemies_root.get_children().filter(func(e): return e is Enemy and e.kind == "sloth")[0]
	# out on the road, in the open
	var rp: Vector2 = g.world.path_poly[int(g.world.path_poly.size() * 0.35)]
	s.global_position = Vector3(rp.x, g.world.height_at(rp.x, rp.y), rp.y)
	s.sloth.goal = s.global_position + Vector3(0, 0, -40)
	s.sloth.goal_t = 60.0
	# others nearby out of the way
	for e in g.enemies_near(s.global_position, 30.0):
		if e != s:
			e.queue_free()
	await process_frame
	var fwd: Vector3 = -s.rig.global_transform.basis.z
	var side: Vector3 = s.rig.global_transform.basis.x
	var hp: Vector3 = g.world.free_spot_near(s.global_position + fwd * 6.0 + side * 3.0, 1.0)
	g.hero.global_position = Vector3(hp.x, g.world.height_at(hp.x, hp.z), hp.z)
	g.hero.rig.rotation.y = atan2(hp.x - s.global_position.x, hp.z - s.global_position.z)
	g.hero.set_process(false)
	g.hero.phased = true          # unseen, so it just roams by
	# roaming: let it walk a little first
	s.sloth.idle_t = 99.0
	await _snap("roam", 90)
	_hold(s, "sloth_stare", 0.5)
	await _snap("stare", 20)
	_hold(s, "sloth_roar", 0.45)
	await _snap("roar", 20)
	_hold(s, "sloth_slam", 0.47)
	await _snap("slam", 20)
	_hold(s, "sloth_pounce", 0.47)
	await _snap("pounce", 20)
	quit()
