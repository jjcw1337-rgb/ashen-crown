extends SceneTree
## Frames of the archer and his Spirit Beast on the moor from the game camera: walking with it at his side,
## stopping (it settles), a monster coming (it goes for it), a command (the pounce). Needs a display.
##   godot --path . -s tools/pet_clip.gd -- outdir     (then a video from outdir/f0000.png ...)
var g
var n := 0
var out := ""

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frame() -> void:
	await process_frame
	get_root().get_texture().get_image().save_png(out + "/f%04d.png" % n)
	n += 1

func _place(p: Vector3) -> void:
	g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)

## The hero walks for secs toward dir at speed (posed as walking), one frame per 1/15 s.
func _walk(dir: Vector3, speed: float, secs: float) -> void:
	var steps := int(secs * 15.0)
	for i in steps:
		var np: Vector3 = g.hero.global_position + dir * speed / 15.0
		if g.world.is_blocked(np.x, np.z):
			dir = dir.rotated(Vector3.UP, 0.4)
			np = g.hero.global_position + dir * speed / 15.0
		g.hero.cmd_move(np + dir * 2.0) if g.hero.has_method("cmd_move") else null
		_place(np)
		g.hero.rig.rotation.y = atan2(-dir.x, -dir.z)
		g.cam_target = g.hero.global_position
		await create_timer(1.0 / 15.0).timeout
		await _frame()

## Walks along the road (World.path_poly) at speed for secs.
func _road(speed: float, secs: float) -> void:
	var pp: PackedVector2Array = g.world.path_poly
	var hp: Vector3 = g.hero.global_position
	var k := 0
	var bd := 1e9
	for i in pp.size():
		var d := Vector2(hp.x, hp.z).distance_to(pp[i])
		if d < bd:
			bd = d
			k = i
	for i in int(secs * 15.0):
		var nxt: Vector2 = pp[mini(k + 1, pp.size() - 1)]
		var cur := Vector2(g.hero.global_position.x, g.hero.global_position.z)
		if cur.distance_to(nxt) < 1.0:
			k = mini(k + 1, pp.size() - 1)
			nxt = pp[mini(k + 1, pp.size() - 1)]
		var d2 := (nxt - cur).normalized()
		var dir := Vector3(d2.x, 0, d2.y)
		_place(g.hero.global_position + dir * speed / 15.0)
		g.hero.rig.rotation.y = atan2(-dir.x, -dir.z)
		g.hero.move_amt = clampf(speed / 4.8, 0.0, 1.2)
		g.cam_target = g.hero.global_position
		await create_timer(1.0 / 15.0).timeout
		await _frame()
		if i % 15 == 0:
			var b = g.hero.beasts[0]
			print("[clip] %s %.1f m from him, %.1f m/s" % [b.state, b.global_position.distance_to(g.hero.global_position), b.vel.length()])

func _idle(secs: float) -> void:
	for i in int(secs * 15.0):
		await create_timer(1.0 / 15.0).timeout
		await _frame()

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
	g.hero.set_level(12)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	var road: Vector3 = g.world.spawns["road"]
	_place(road)
	await create_timer(1.0).timeout
	g.hero.beasts[0]._reset_to_side()
	g.zoom = 0.6
	var dir: Vector3 = g.world.spawns["road2"] - road
	dir.y = 0
	dir = dir.normalized()
	await _idle(2.0)
	await _road(3.0, 3.0)
	await _road(5.0, 2.5)
	await _idle(2.0)
	# a zombie comes at him
	var zp: Vector3 = g.world.free_spot_near(g.hero.global_position + Vector3(0, 0, 7.0), 1.5)
	var z: Enemy = g.spawn_enemy("zombie", zp, 3)
	z.max_life = 400.0
	z.life = 400.0
	z.aggro = true
	await _idle(4.0)
	# he sends it at another
	var z2: Enemy = g.spawn_enemy("zombie", g.world.free_spot_near(g.hero.global_position + Vector3(6.0, 0, 0), 1.5), 3)
	z2.max_life = 400.0
	z2.life = 400.0
	g.hero.cds["beast"] = 0.0
	g.hero.mana = g.hero.max_mana
	g.test_allskills = true
	g.hero.use_skill("beast", z2.global_position)
	await _idle(4.0)
	print("frames ", n)
	quit()
