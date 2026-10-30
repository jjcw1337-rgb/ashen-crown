extends SceneTree
## Frames of the archer's skills from the game camera (Fire Arrow, Frost Volley, Storm Snare, his wolf):
## outdir/<skill>_N.png. Needs a display.   godot --path . -s tools/archer_shots.gd -- outdir
var g
var out := ""

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(nm: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png(out + "/" + nm + ".png")

func _foe(p: Vector3) -> Enemy:
	var e: Enemy = g.spawn_enemy("zombie", g.world.free_spot_near(p, 1.0), 3)
	e.max_life = 3000.0
	e.life = 3000.0
	e.set_process(true)
	return e

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	g.difficulty = 0
	await g.load_zone(0, "wild", "start")
	g.ui.close_all()
	g.test_immortal = true
	g.test_allskills = true
	g.hero.set_level(14)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var p0: Vector3 = g.world.spawns["road"]
	g.hero.global_position = Vector3(p0.x, g.world.height_at(p0.x, p0.z), p0.z)
	g.zoom = 0.7
	await create_timer(1.5).timeout
	var fwd := Vector3(1, 0, 0)
	g.hero.rig.rotation.y = atan2(-fwd.x, -fwd.z)
	var line := []
	for k in 3:
		var e := _foe(g.hero.global_position + fwd * (5.0 + k * 2.5))
		e.aggro = false
		e.set_process(false)
		line.append(e)
	g.hero.mana = g.hero.max_mana
	g.hero.use_skill("pierce", g.hero.global_position + fwd * 12.0)
	for i in 8:
		await create_timer(0.06).timeout
		await _snap("fire_%d" % i)
	await create_timer(0.8).timeout
	await _snap("fire_burning")
	for e in line:
		e.queue_free()
	var at: Vector3 = g.hero.global_position + Vector3(0, 0, -7.0)
	for k in 3:
		var e2 := _foe(at + Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 2.0)
		e2.set_process(false)
	g.hero.cds["volley"] = 0.0
	g.hero.mana = g.hero.max_mana
	g.hero.use_skill("volley", at)
	for i in 6:
		await create_timer(0.2).timeout
		await _snap("frost_%d" % i)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var trap: Vector3 = g.hero.global_position + Vector3(4.0, 0, -3.0)
	g.hero.cds["snare"] = 0.0
	g.hero.mana = g.hero.max_mana
	g.hero.use_skill("snare", trap)
	await create_timer(0.7).timeout
	var on := _foe(trap + Vector3(3, 0, 0))
	on.set_process(false)
	for k in 3:
		var o := _foe(trap + Vector3(cos(k * 2.0) * 4.0, 0, sin(k * 2.0) * 4.0))
		o.set_process(false)
	on.global_position = trap
	for i in 5:
		await create_timer(0.05).timeout
		await _snap("storm_%d" % i)
	quit()
