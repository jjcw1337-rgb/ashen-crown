extends SceneTree
## Stamina out of combat (jj, 2026-11-02): in a fight (and COMBAT_SECS after) sprinting drains it at the normal rate;
## the longer the hero stays out of combat the slower it drains and the faster it refills, up to CALM_MAX (5x)
## CALM_RAMP s later; a blow taken or struck, or a monster on him, puts him back in the fight.
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[T] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var h: Hero = g.hero
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await process_frame
	h.combat_t = 0.0
	check(is_equal_approx(h.calm(), 1.0), "in combat: rested x1 (%.2f)" % h.calm())
	h.combat_t = h.COMBAT_SECS + h.CALM_RAMP * 0.5
	check(h.calm() > 2.5 and h.calm() < 3.5, "half way out: rested x%.1f" % h.calm())
	h.combat_t = 999.0
	check(is_equal_approx(h.calm(), h.CALM_MAX), "long out of combat: rested x%.1f" % h.calm())
	# sprinting: how far the bar falls in a second, in and out of a fight
	var drain := func(out: bool) -> float:
		h.stamina = h.max_stamina
		h.exhausted = false
		_key(KEY_SHIFT, true)
		_key(KEY_D, true)
		await process_frame
		var s0: float = h.stamina
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1000:
			h.combat_t = 999.0 if out else 0.0
			await process_frame
		_key(KEY_SHIFT, false)
		_key(KEY_D, false)
		return s0 - h.stamina
	var d_in: float = await drain.call(false)
	var d_out: float = await drain.call(true)
	check(d_in > 8.0, "sprinting in combat drains it (%.1f a second)" % d_in)
	check(d_out > 0.0 and d_in / d_out > 4.0, "out of combat it lasts about 5x longer (%.1f vs %.1f a second)" % [d_out, d_in])
	# a blow puts him back in the fight
	h.combat_t = 999.0
	h.take_hit(1.0, h.global_position + Vector3(1, 0, 0))
	check(h.combat_t < 0.5 and is_equal_approx(h.calm(), 1.0), "a blow taken: back in combat")
	# a monster after him, close by, too
	h.combat_t = 999.0
	var e: Enemy = g.spawn_enemy("zombie", h.global_position + Vector3(6, 0, 0), 1)
	e.aggro = true
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 800:
		await process_frame
	check(h.combat_t < 1.0, "a monster on him: in combat (%.1f s)" % h.combat_t)
	print("[T] done, %d failed" % fails)
	quit()
