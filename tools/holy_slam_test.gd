extends SceneTree
## Holy Slam (knight Q) lands on the cursor: cast at points 2 m and 5 m away (and 9 m, past its 6 m
## range) and check where the blow lands, and that a monster at the cursor is hit, knocked back and
## stunned. Prints [S] lines.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	while g._busy:
		await wait(5)
	g.start_game(false)
	await wait(10)
	while g._busy:
		await wait(5)
	g.ui.close_all()
	await g.load_zone(0, "wild", "from_town")
	await wait(10)
	var h = g.hero
	h.vit = 400
	h.recalc()
	h.mana = h.max_mana
	for d in [2.0, 5.0, 9.0]:
		var start: Vector3 = g.world.free_spot_near(h.global_position, 0.5)
		h.global_position = start
		await wait(2)
		var dir := Vector3(1, 0, 0)
		var aim: Vector3 = start + dir * d
		var foe = null
		var bd := 999.0
		for e in g.enemies_near(start, 60.0):
			if not e.dead and not e.boss and e.global_position.distance_to(start) < bd:
				bd = e.global_position.distance_to(start)
				foe = e
		var hp0 := 0.0
		if foe != null:
			foe.global_position = g.world.free_spot_near(aim, 0.2)
			foe.set_physics_process(false)
			hp0 = foe.life
		var foe_at: Vector3 = foe.global_position if foe != null else aim
		h.mana = h.max_mana
		h.cds["cleave"] = 0.0
		var ok: bool = h.use_skill("cleave", aim)
		var landed := Vector3.ZERO
		for f in 90:
			await process_frame
			if h.impact_done and landed == Vector3.ZERO:
				landed = h.global_position - h.rig.global_transform.basis.z * h.slam_reach
		var miss := Vector2(landed.x - aim.x, landed.z - aim.z).length()
		var want := minf(d, 6.0)
		var flat := Vector2(landed.x - start.x, landed.z - start.z).length()
		print("[S] cast %.0f m: ok=%s blow landed %.1f m out (want %.1f), %.2f m from the cursor" % [d, ok, flat, want, miss])
		if foe != null and is_instance_valid(foe):
			print("[S]   foe at the cursor: hit=%s knocked back %.2f m stunned=%s" % [foe.life < hp0 or foe.dead, Vector2(foe.global_position.x - foe_at.x, foe.global_position.z - foe_at.z).length(), foe.stun_t > 0.0 if "stun_t" in foe else "?"])
			foe.set_physics_process(true)
	quit()
