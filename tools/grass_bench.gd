extends SceneTree
## Grass benchmark and screenshots from the game camera: stands the hero in open grass on the Act I moor
## (off the road, away from trees), lets it settle, then measures a run of frames: CPU frame time, draw
## calls, primitives and visible objects (Performance monitors), and saves a screenshot.
## Run with a display (software GL works, slowly):
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 --path . -s tools/grass_bench.gd -- out_prefix [quality 0-3] [frames] [zoomin|zoomout] [walk]
## Prints [GB] lines and writes <out_prefix>.png and <out_prefix>.txt.
var g
var prefix := "grass_bench"
var q := 2
var frames := 60
var zoom := 1.0
var walk := false

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: prefix = a[0]
	if a.size() > 1: q = int(a[1])
	if a.size() > 2: frames = int(a[2])
	if a.has("zoomin"): zoom = 0.6
	if a.has("zoomout"): zoom = 1.3
	walk = a.has("walk")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	g.set_quality(q)
	await g.start_game(false, "knight")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	g.test_immortal = true
	var spot := _open_grass(g.world)
	g.hero.global_position = spot
	g.cam_target = spot
	g.zoom = zoom
	# no monsters near the stage: they would change the numbers from run to run
	for e in g.world.enemies_root.get_children():
		if e.global_position.distance_to(spot) < 40.0:
			e.queue_free()
	for i in 20:
		await process_frame
	var t_proc := 0.0
	var t_max := 0.0
	var dc := 0.0
	var prims := 0.0
	var objs := 0.0
	var t0 := Time.get_ticks_usec()
	for i in frames:
		if walk:
			var ang := float(i) / frames * TAU
			g.hero.global_position = spot + Vector3(cos(ang), 0, sin(ang)) * 3.0
		await process_frame
		var pt := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		t_proc += pt
		t_max = maxf(t_max, pt)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	var grass_inst := 0
	var grass_mmi := 0
	for mmi in g.get_tree().get_nodes_in_group("grass"):
		grass_mmi += 1
		grass_inst += (mmi as MultiMeshInstance3D).multimesh.instance_count
	var lines := [
		"quality %d (%s), zoom %.1f, %d frames, spot %s" % [q, g.QUALITY_NAMES[q], zoom, frames, spot],
		"wall ms/frame %.1f (this machine's renderer), process ms avg %.2f max %.2f" % [wall, t_proc / frames, t_max],
		"draw calls %.0f, primitives %.0f, objects %.0f" % [dc / frames, prims / frames, objs / frames],
		"grass nodes %d, grass instances %d" % [grass_mmi, grass_inst],
	]
	var f := FileAccess.open(prefix + ".txt", FileAccess.WRITE)
	for l in lines:
		print("[GB] ", l)
		f.store_line(l)
	f.close()
	var img := g.get_viewport().get_texture().get_image()
	img.save_png(prefix + ".png")
	print("[GB] saved ", prefix + ".png")
	quit()

## The grassiest open spot near the start: 9-16 m off the road, nothing solid within 4 m.
func _open_grass(w) -> Vector3:
	var start: Vector3 = w.spawns.get("start", Vector3.ZERO)
	var best := start
	var best_s := -1.0
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 600:
		var p := start + Vector3(r.randf_range(-40, 40), 0, r.randf_range(-40, 40))
		var d: float = w.path_dist(p.x, p.z)
		if d < 9.0 or d > 16.0 or w.is_blocked(p.x, p.z) or w.is_near_obstacle(p, 4.0):
			continue
		if w.dirt_at(p.x, p.z) + w.cobble_at(p.x, p.z) > 0.05:
			continue
		var s := 40.0 - p.distance_to(start)
		if s > best_s:
			best_s = s
			best = p
	best.y = w.height_at(best.x, best.z)
	return best
