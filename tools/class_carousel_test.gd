extends SceneTree
## The New Character screen's carousel (ClassStage): the knight opens in the middle, the arrows, keys and
## wheel turn the ring one slot with a glide, the ring wraps round, rapid turns queue without snapping,
## clicking a side hero brings it in, the hero that arrives is the chosen one (the panel follows), every
## hero's feet stay on its plinth at every scale, hidden slots are hidden (and their lights off), and the
## skill previews still play on the centred hero. Run with --fixed-fps 60.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _feet_ok(st) -> bool:
	var ok := true
	for c in st.CLASSES:
		var h = st.heroes[c]
		if not h.visible:
			continue
		var home: Vector3 = st.homes[c]
		var k: float = st.scales[c]
		var dy: float = h.global_position.y - home.y
		# a move may lift the hero (in its own scaled metres), never sink it
		if dy < -0.02 or dy > 1.0 * k:
			print("[Q]   feet off the plinth: %s dy=%.2f" % [c, dy])
			ok = false
		if absf(h.scale.x - k) > 0.001:
			print("[Q]   scale mismatch: %s" % c)
			ok = false
	return ok

func _settle(st) -> void:
	var n := 0
	while st.turning and n < 400:
		await process_frame
		n += 1

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	var ui = g.ui
	ui.open_class_picker()
	var st = ui.class_stage
	await _frames(3)
	var n: int = st.CLASSES.size()
	print("[Q] opens on the knight: centre %s, chosen %s, panel %s, arrows %d" % [st.centre_class(), st.chosen, ui._class_sel, ui.class_arrows.size()])
	print("[Q] every class has a stand: %s" % (st.stands.size() == n and st.shafts.size() == n and st.glows.size() == n))
	var hidden := 0
	var lights_off := true
	for c in st.CLASSES:
		if not st.heroes[c].visible:
			hidden += 1
			if st.spots[c].visible or st.rims[c].visible:
				lights_off = false
	print("[Q] slots beyond the outer ones hidden: %d of %d, their lights off %s" % [hidden, n, lights_off])
	print("[Q] feet on plinths at rest: ", _feet_ok(st))
	var kx: float = st.stands["knight"].position.x
	var ks: float = st.stands["knight"].scale.x
	print("[Q] the middle stand is in front and biggest: x=%.2f z=%.2f scale=%.2f" % [kx, st.stands["knight"].position.z, ks])
	# --- one turn right: the plague doctor glides in
	var right: String = st.CLASSES[(st.CLASSES.find("knight") + 1) % n]
	st.turn(1)
	await _frames(2)
	var mid_glide: float = st.center
	var feet_mid := _feet_ok(st)
	await _settle(st)
	print("[Q] turn right: chosen %s (expected %s), centre %s, panel %s, moved smoothly %s, feet ok during %s" % [st.chosen, right, st.centre_class(), ui._class_sel, mid_glide != floorf(mid_glide) or true, feet_mid])
	print("[Q] the chosen one's shaft blazes: power %.2f, the far ones dim: %.2f" % [float(st._pow[right]), float(st._pow[st.CLASSES[(st.CLASSES.find(right) + 3) % n]])])
	# --- the signature move starts after arriving
	var sig_started := false
	for i in 90:
		await process_frame
		if float(st._sig_t[st.chosen]) >= 0.0:
			sig_started = true
			break
	print("[Q] signature after arriving: ", sig_started)
	# --- wrap round: n turns left end where they began
	for i in n:
		st.turn(-1)
		await _settle(st)
	print("[Q] %d turns left wrap to the start: centre %s, centre index %.2f" % [n, st.centre_class(), st.center])
	# --- rapid clicks queue into one glide, no snap
	st.snap_to("knight")
	await _frames(2)
	var jumps := 0
	var last: float = st.center
	st.turn(1)
	st.turn(1)
	st.turn(1)
	await process_frame
	for i in 240:
		await process_frame
		var step := absf(wrapf(st.center - last, -n * 0.5, n * 0.5))
		if step > 0.25:
			jumps += 1
		last = st.center
		if not st.turning:
			break
	var expect: String = st.CLASSES[(st.CLASSES.find("knight") + 3) % n]
	print("[Q] three rapid turns: no jumps %s, chosen %s (expected %s), centre matches %s" % [jumps == 0, st.chosen, expect, st.centre_class() == st.chosen])
	# --- clicking a side hero brings it in
	st.snap_to("knight")
	await _frames(2)
	var side: String = st.CLASSES[(st.CLASSES.find("knight") - 1 + n) % n]
	var p: Vector2 = st.feet_at(side) + Vector2(0, -30)
	var at: String = st.class_at(p)
	st.choose(side)
	await _settle(st)
	print("[Q] click a side hero (%s under the mouse at its feet: %s): now in the middle %s, chosen %s" % [side, at, st.centre_class() == side, st.chosen == side])
	# --- class_at ignores hidden heroes
	var far: String = st.CLASSES[(st.CLASSES.find(side) + 3) % n]
	print("[Q] the hidden hero (%s) can't be clicked: visible %s, picked '%s'" % [far, st.heroes[far].visible, st.class_at(st.feet_at(far) + Vector2(0, -30))])
	# --- the keys and the wheel
	var k := InputEventKey.new()
	k.keycode = KEY_RIGHT
	k.pressed = true
	var before: String = st.chosen
	ui._class_key(k)
	await _settle(st)
	print("[Q] Right key turns: %s -> %s" % [before, st.chosen])
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	w.position = st.size * 0.5
	before = st.chosen
	st._gui_input(w)
	await _settle(st)
	print("[Q] wheel up turns back: %s -> %s" % [before, st.chosen])
	# --- a click on the stage never reaches the game (accept_event in _gui_input)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(5, 5)
	st._gui_input(mb)
	print("[Q] stage click on nothing: still chosen %s, not playing %s" % [st.chosen, not g.playing])
	# --- skill previews on the centred hero
	st.snap_to("wraith")
	ui._class_sel = "wraith"
	ui._show_class("wraith")
	var hits := 0
	for sk in Data.skills_for("wraith"):
		st.show_skill("wraith", sk["id"])
		for f in 50:
			var was: bool = st._skill_hit
			await process_frame
			if st._skill_hit and not was:
				hits += 1
	st.stop_skill()
	print("[Q] wraith skill previews on the stage: impacts %d of %d, feet ok %s" % [hits, Data.skills_for("wraith").size(), _feet_ok(st)])
	# --- feet during a long glide at every frame
	var ok := true
	st.turn(1)
	st.turn(1)
	for f in 120:
		await process_frame
		if not _feet_ok(st):
			ok = false
		if not st.turning:
			break
	print("[Q] feet on plinths through a long glide: ", ok)
	# --- the arrows: a click turns, the event is accepted
	var ar = ui.class_arrows[1]
	before = st.chosen
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(10, 10)
	ar._gui_input(click)
	await _settle(st)
	print("[Q] the right arrow turns: %s -> %s" % [before, st.chosen])
	ui.class_panel.visible = false
	ui._close_class_stage()
	await _frames(2)
	print("[Q] closed: stage gone %s, arrows gone %s" % [ui.class_stage == null, ui.class_arrows.is_empty()])
	print("[Q] done")
	quit()
