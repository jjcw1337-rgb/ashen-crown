extends SceneTree
## Aiming: keyboard actions go where the hero faces for every class, with a light assist onto
## an enemy near that line; "self" skills don't turn the hero; "point" skills use the cursor.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "warlock")
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	var h = g.hero
	h.level = 12
	h.recalc()
	g.test_immortal = true
	var foes: Array = g.enemies_near(h.global_position, 400.0)
	var e = foes[0]
	# stand 8 m from a lone-ish enemy
	h.global_position = g.world.free_spot_near(e.global_position + Vector3(8, 0, 0), 0.5)
	await create_timer(0.1).timeout
	var to_e: Vector3 = e.global_position - h.global_position
	to_e.y = 0
	to_e = to_e.normalized()
	var cursor_away: Vector3 = h.global_position - to_e * 6.0
	# facing roughly at it (20 deg off): assist bends onto it, cursor is ignored
	h._face(to_e.rotated(Vector3.UP, 0.35))
	var a: Vector3 = h.skill_aim("blight", cursor_away)
	print("[A] facing 20 deg off the enemy: blight aims at it %s (cursor behind ignored %s)" % [a.distance_to(e.global_position) < 0.01, a.distance_to(cursor_away) > 3.0])
	# facing away: straight ahead, no assist
	h._face(-to_e)
	a = h.skill_aim("blight", e.global_position)
	var ahead: Vector3 = h.global_position - to_e * 15.0
	print("[A] facing away: blight goes straight ahead %s" % (Vector2(a.x, a.z).distance_to(Vector2(ahead.x, ahead.z)) < 0.01))
	# the bolt really flies that way
	h.mana = h.max_mana
	h.use_skill("blight", a)
	await create_timer(0.5).timeout
	var bd: Vector3 = h.bolts[0]["dir"] if not h.bolts.is_empty() else Vector3.ZERO
	print("[A] bolt flies the way the hero faces: %s" % (bd.dot(-to_e) > 0.99))
	# self skills don't turn the hero
	await create_timer(1.0).timeout
	h._face(Vector3(1, 0, 0))
	var f0: Vector3 = h.facing()
	var sa: Vector3 = h.skill_aim("shackles", h.global_position + Vector3(-5, 0, 0))
	h.mana = h.max_mana
	h.use_skill("shackles", sa)
	print("[A] self skill keeps facing: %s" % (h.facing().dot(f0) > 0.99))
	# every class: every skill declares how it aims, facing skills have a range
	var bad := []
	for s in Data.SKILLS:
		var aim: String = s.get("aim", "")
		if not aim in ["facing", "self", "point"] or aim == "facing" and not s.has("range"):
			bad.append(s["id"])
	print("[A] skills with a valid aim: %d/%d %s" % [Data.SKILLS.size() - bad.size(), Data.SKILLS.size(), str(bad)])
	# melee: Space swing bends onto an enemy beside the line, within reach
	await create_timer(1.0).timeout
	h.global_position = g.world.free_spot_near(e.global_position + Vector3(1.8, 0, 0), 0.3)
	await create_timer(0.1).timeout
	var side: Vector3 = (e.global_position - h.global_position)
	side.y = 0
	h._face(side.normalized().rotated(Vector3.UP, 0.6))
	var ma: Vector3 = h.aim_ahead(h.reach() + 1.5)
	print("[A] swing 34 deg off a close enemy bends onto it: %s" % (ma.distance_to(e.global_position) < 0.01))
	quit()
