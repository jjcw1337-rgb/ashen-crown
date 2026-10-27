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
	print("[T] unchanged: level ", lvl, "->", h.level, " dmg ", dmg, "->", [h.dmg_min, h.dmg_max])
	quit()
