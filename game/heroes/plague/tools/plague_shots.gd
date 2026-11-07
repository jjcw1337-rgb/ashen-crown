extends SceneTree
## Screenshots of the Plague Doctor in the game: standing, each skill at its moment (the flask in flight, the cloud,
## the fuse and the blast, the trap set and sprung, the dome), under the game camera or closer.
##   xvfb-run -a godot --rendering-driver opengl3 --fixed-fps 10 --resolution 1280x720 --path . -s game/heroes/plague/tools/plague_shots.gd -- <outdir> [close]
var g
var out := "/tmp/plague_shots"
var close := false
const FPS := 10.0                  # run with --fixed-fps 10: software rendering is slow, so few frames

func sec(t: float) -> int:
	return maxi(1, int(round(t * FPS)))

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	close = a.has("close")
	DirAccess.make_dir_recursive_absolute(out)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[S] ", name)

func _foe(at: Vector3) -> Enemy:
	var e: Enemy = g.spawn_enemy("zombie", at, 3)
	e.max_life = 50000.0
	e.life = e.max_life
	e.set_process(false)
	return e

func _cast(h, id: String, at: Vector3) -> void:
	h.cds[id] = 0.0
	h.mana = h.max_mana
	h.use_skill(id, at)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "plague")
	g.test_immortal = true
	await g.load_zone(0, "bg", "start")
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	g.ui.close_all()
	var h = g.hero
	h.level = 14
	h.recalc()
	g.apply_quality(0)
	if close:
		g.zoom = 0.6
		g.focus_zoom = 0.75
	await frames(sec(1.0))
	await snap("01_stand")
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	var side: Vector3 = fwd.cross(Vector3.UP)
	var p0: Vector3 = h.global_position
	var spot: Vector3 = g.world.free_spot_near(p0 + fwd * 6.0, 1.0)
	for k in 3:
		_foe(g.world.free_spot_near(spot + side * (k - 1) * 1.4, 0.5))
	await frames(sec(0.2))
	# Toxic Flask: the wind-up, the flask in the air, the cloud
	_cast(h, "toxic", spot)
	await frames(sec(0.85 * 0.4))
	await snap("02_flask_windup")
	await frames(sec(0.85 * 0.25))
	await snap("03_flask_flight")
	await frames(sec(1.1))
	await snap("04_cloud")
	# Volatile Mixture: the crouch, then the fuse on the ground, then the blast igniting the cloud
	_cast(h, "volatile", spot + side * 0.5)
	await frames(sec(1.25 * 0.35))
	await snap("05_volatile_crouch")
	await frames(sec(1.25 * 0.3 + 0.5))
	await snap("06_volatile_fuse")
	await frames(sec(0.45))
	await snap("07_blast")
	await frames(sec(2.0))
	# Pestilent Trap: kneeling to set it, then a foe springs it
	var tspot: Vector3 = g.world.free_spot_near(p0 + side * 3.5 + fwd * 1.5, 1.0)
	_cast(h, "trap", tspot)
	await frames(sec(0.45))
	await snap("08_trap_kneel")
	await frames(sec(1.3))
	await snap("09_trap_set")
	var e2 := _foe(tspot + Vector3(0.3, 0, 0))
	await frames(sec(0.25))
	await snap("10_trap_sprung")
	await frames(sec(2.5))
	# The Last Epidemic: the slam, the dome rising, the dome at full strength
	for k in 6:
		var a := TAU * k / 6.0
		_foe(g.world.free_spot_near(h.global_position + Vector3(cos(a), 0, sin(a)) * 5.0, 0.6))
	_cast(h, "epidemic", h.global_position)
	await frames(sec(1.2 * 0.5))
	await snap("11_epidemic_slam")
	await frames(sec(1.2 * 0.55))
	await snap("12_dome_rise")
	await frames(sec(1.1 * 0.7))
	await snap("13_dome_arms")
	await frames(sec(1.5))
	await snap("14_dome")
	quit()
