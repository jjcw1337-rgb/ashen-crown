extends SceneTree
## The Path of Exile controls (Dodge, Game.dodge_roll, the left click, default binds), every class:
##   godot --headless --path . -s tools/controls_test.gd
## Space rolls the way the keys point (toward the pointer with no key), about DG.DIST, for stamina; blows
## miss early in the roll and land after it; the roll drops a swing in progress; the body is upright again after;
## a puppet tumbles too and the event hurts nothing. Left click on open ground attacks where he stands; on a foe
## while standing still he walks up and strikes; click-to-move (the option) walks again. Right mouse is the first
## skill on a new character, and an old save's Block on right mouse becomes it.

var g
var fails := 0
var DG       # dodge.gd, loaded at run time (a static reference compiles the game's classes before the Sfx autoload)

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[K] " + ("ok   " if ok else "FAIL ") + what)

func wait(n: int) -> void:
	for i in n:
		await process_frame

## Waits t seconds of game time (the frame rate may be anything).
func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	g._unhandled_input(e)

func _run() -> void:
	DG = load("res://scripts/dodge.gd")
	await wait(30)
	while g._busy:
		await wait(5)
	g.start_game(false)
	await wait(10)
	while g._busy:
		await wait(5)
	g.ui.close_all()
	var h = g.hero
	g.click_move = false
	check(h.bound("lmb") == "attack" and h.bound("rmb") == h.skill_list()[0]["id"], "left mouse attacks, right mouse is the first skill (%s)" % h.bound("rmb"))
	# an old save: Block on right mouse
	var sv: Dictionary = h.to_save()
	sv.erase("binds_v")
	sv["binds"]["rmb"] = "block"
	h.from_save(sv)
	check(h.bound("rmb") == h.skill_list()[0]["id"], "an old save's Block on right mouse becomes the first skill")
	sv = h.to_save()
	sv["binds"]["rmb"] = "block"
	h.from_save(sv)
	check(h.bound("rmb") == "block", "a choice made since is kept")
	h.binds = h.default_binds()

	for cls in ["knight", "wraith", "demon", "warlock", "plague", "archer"]:
		await _roll_class(cls)

	# the left click
	h.set_class("knight")
	h.new_character()
	await wait(5)
	var p0: Vector3 = h.global_position
	g.ground_pt = p0 + Vector3(4, 0, 0)
	g.hovered = null
	h.atk_t = -1.0
	_click()
	await wait(1)
	check(h.atk_t >= 0.0 and h.path.is_empty() and not h.moving, "left click on open ground: he swings where he stands")
	await secs(1.0)
	check(h.global_position.distance_to(p0) < 0.6, "and doesn't walk there (%.2f m)" % h.global_position.distance_to(p0))
	g.click_move = true
	h.atk_t = -1.0
	_click()
	await secs(0.6)
	check(h.global_position.distance_to(p0) > 1.0, "with click-to-move on, the click walks him there")
	g.click_move = false
	g.lmb_held = false
	print("[K] done, %d failed" % fails)
	quit()

func _click() -> void:
	# (Game._unhandled_input reads the pointer through _update_hover: move the pointer over the test's point)
	var gp: Vector3 = g.ground_pt
	var mv := InputEventMouseMotion.new()
	mv.position = g.cam.unproject_position(gp)
	get_root().push_input(mv)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = mv.position
	g._unhandled_input(e)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	g._input(u)

func _roll_class(cls: String) -> void:
	var h = g.hero
	h.set_class(cls)
	h.new_character()
	await wait(10)
	g.test_immortal = false
	h.life = h.max_life
	h.stamina = h.max_stamina
	h.global_position = _open_ground()
	await wait(2)
	var p0: Vector3 = h.global_position
	var st0: float = h.stamina
	# a swing in progress, then Space with D held: he rolls right (+x) and the swing is gone
	h.swipe_attack(p0 + Vector3(0, 0, -3))
	key(KEY_D, true)
	await wait(1)      # (parsed input reaches Input on the next frame)
	p0 = h.global_position
	key(KEY_SPACE, true)
	await wait(1)
	check(h.roll_t >= 0.0 and h.atk_t < 0.0, "%s: Space rolls and drops the swing" % cls)
	check(st0 - h.stamina >= DG.STAMINA - 0.5, "%s: it costs stamina (%.0f)" % [cls, st0 - h.stamina])
	key(KEY_D, false)
	var l0: float = h.life
	h.take_hit(30.0, h.global_position + Vector3(1, 0, 0))
	check(h.life == l0, "%s: a blow early in the roll misses" % cls)
	var tumble := 0.0
	var end := Time.get_ticks_msec() + 900
	while Time.get_ticks_msec() < end:
		await process_frame
		tumble = maxf(tumble, absf(h.rig.rotation.x))
	key(KEY_SPACE, false)
	var moved: Vector3 = h.global_position - p0
	check(moved.x > DG.DIST * 0.7 and absf(moved.z) < 1.0, "%s: rolled %.1f m the way the keys point (%.1f off it)" % [cls, moved.x, moved.z])
	check(cls == "wraith" or tumble > 2.0, "%s: the body tumbled (%.1f rad)" % [cls, tumble])
	check(h.roll_t < 0.0 and (cls == "wraith" or absf(h.rig.rotation.x) < 0.01) and h.rig.position.length() < 0.3, "%s: and is upright after" % cls)
	for i in 6:      # (a shield can block a blow by chance)
		h.take_hit(4.0, h.global_position + Vector3(1, 0, 0))
	check(h.life < l0, "%s: after it, blows land again" % cls)
	h.life = h.max_life
	# no key: toward the pointer
	await secs(0.3)
	h.global_position = _open_ground()
	await wait(2)
	var p1: Vector3 = h.global_position
	check(DG.start(h, h.dir_to(p1 + Vector3(0, 0, 5))), "%s: rolls toward the pointer with no key held" % cls)
	await secs(0.9)
	check((h.global_position - p1).z > DG.DIST * 0.7, "%s: %.1f m toward it" % [cls, (h.global_position - p1).z])
	# no stamina, no roll
	await secs(0.3)
	h.stamina = 2.0
	check(not DG.start(h, Vector3.RIGHT), "%s: no stamina, no roll" % cls)
	# a partner's view: the puppet tumbles, and the event hurts nothing
	var pup = load("res://scripts/hero.gd").new()
	pup.puppet = true
	pup.peer_id = 98
	g.add_child(pup)
	pup.setup(g)
	pup.set_class(cls)
	pup.global_position = h.global_position + Vector3(3, 0, 0)
	pup.net_pos = pup.global_position
	pup.net_has = true
	var pl: float = pup.life
	load("res://scripts/skill_fx.gd").play(pup, {"s": "roll", "e": "start", "d": Vector3.LEFT})
	var pt := 0.0
	var pend := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < pend:
		await process_frame
		pt = maxf(pt, absf(pup.rig.rotation.x))
	check(cls == "wraith" or pt > 1.0, "%s: a partner sees him tumble" % cls)
	await secs(0.6)
	check(pup.roll_t < 0.0 and pup.life == pl, "%s: the puppet's roll ends by itself, nothing hurt" % cls)
	pup.queue_free()
	h.stamina = h.max_stamina

## A spot with 5 m of open ground to the east and the south (the camp has tents and a fire in the way).
func _open_ground() -> Vector3:
	var c: Vector3 = g.hero.global_position
	for r in [0.0, 6.0, 12.0, 18.0, 24.0]:
		for k in 12:
			var p: Vector3 = c + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			p.y = g.world.height_at(p.x, p.z)
			var e: Vector3 = g.world.move(p, Vector3(5, 0, 0))
			var s: Vector3 = g.world.move(p, Vector3(0, 0, 5))
			var nudge: Vector3 = g.world.move(p, Vector3(0.02, 0, 0))     # (inside a footprint, the first step pushes out)
			if (nudge - p).length() < 0.05 and absf((e - p).length() - 5.0) < 0.1 and absf((s - p).length() - 5.0) < 0.1:
				return p
	return c
