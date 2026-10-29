extends SceneTree
## Checks the F8 testing switches: immortal blocks damage, one-hit kill kills, nothing else changes.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false)
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	var h = g.hero
	var lvl: int = h.level
	var dmg := [h.dmg_min, h.dmg_max]
	g.ui.toggle(g.ui.test_panel)
	print("[T] panel visible: ", g.ui.test_panel.visible)
	g.test_immortal = true
	var l0: float = h.life
	h.take_hit(50.0, h.global_position + Vector3(1, 0, 0))
	print("[T] immortal: life ", l0, " -> ", h.life)
	g.test_immortal = false
	h.take_hit(20.0, h.global_position + Vector3(1, 0, 0))
	print("[T] normal: life now ", h.life, " (should be lower)")
	var e = null
	for c in g.world.get_node("Enemies").get_children():
		if not c.dead:
			e = c
			break
	g.test_onehit = true
	e.take_damage(1.0, 0.0, h.global_position, 0.0, false)
	print("[T] one-hit: enemy ", e.kind, " dead=", e.dead)
	g.test_stamina = true
	h.stamina = 0.0
	h.sprint = true
	h.cmd_move(h.global_position + Vector3(20, 0, 0))
	await create_timer(1.5).timeout
	print("[T] infinite stamina: ", int(h.stamina), "/", int(h.max_stamina), " winded=", h.exhausted)
	h.sprint = false
	g.test_stamina = false
	# super speed: a walk across open ground covers TEST_FAST times the distance
	for fast in [false, true]:
		g.test_fast = fast
		h.target = null
		var p0: Vector3 = h.global_position
		h.cmd_move(p0 + Vector3(-60, 0, 0))
		var t0 := Time.get_ticks_msec()
		await create_timer(1.0).timeout
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		var d0 := Vector2(h.global_position.x - p0.x, h.global_position.z - p0.z).length()
		print("[T] super speed %s: %.1f m/s" % [fast, d0 / secs])
		h.moving = false
		h.path = PackedVector3Array()
	g.test_fast = false
	# all skills: a level-1 hero can cast the level-10 skill
	var last: Dictionary = h.skill_list()[3]
	h.mana = h.max_mana
	print("[T] level-%d skill at level 1 without switch: %s" % [last["lvl"], h.use_skill(last["id"], h.global_position)])
	g.test_allskills = true
	h.mana = h.max_mana
	print("[T] ... with Unlock all skills: %s" % h.use_skill(last["id"], h.global_position))
	await create_timer(1.0).timeout
	g.test_allskills = false
	print("[T] unchanged: level ", lvl, "->", h.level, " dmg ", dmg, "->", [h.dmg_min, h.dmg_max])
	var pts: int = h.stat_points
	h.set_level(20)
	print("[T] set level 20: level=", h.level, " stat points +", h.stat_points - pts, " life=", int(h.life), "/", int(h.max_life))
	h.set_level(5)
	print("[T] set level 5: level=", h.level)
	quit()
