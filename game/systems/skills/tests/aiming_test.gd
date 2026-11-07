extends SceneTree
## Click to cast for area skills (Aiming, AimIndicator, the glue in Game._use_bind and the left click), one process:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/systems/skills/tests/aiming_test.gd
## An area skill's key arms it and spends nothing; he walks while it is armed; the left click casts it at the spot
## (mana spent then, no swing); Esc or its key again lets it go; another key does its own thing (another area skill
## arms instead); a skill that isn't ready doesn't arm and says why; every other skill casts on its key; quick cast
## casts area skills on the key again (saved, in the pause menu); the circle is the skill's own radius (its codex
## number, a constant in its code, widened by its rite) and sits where the cast lands, red past the range.

var g
var fails := 0
var AM                 # aiming.gd, loaded at run time (a static reference compiles the game's classes before Sfx)

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[C] " + ("ok   " if ok else "FAIL ") + what)

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

## A key held or let go (what Input.is_key_pressed sees: WASD).
func hold(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

## A key pressed once, straight to the game's handler (parse_input_event would hand it to it a second time).
func tap(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	g._unhandled_input(e)

## The pointer on a spot (headless has no pointer to move: the game's own update of it, Game._process, is held while
## the test aims by hand; the AimIndicator, its child, still runs).
func point_at(p: Vector3) -> void:
	g.set_process(false)
	g.hero.cursor = p
	await wait(2)

## The game's pointer again (headless: wherever the screen's corner falls on the ground).
func real_pointer() -> void:
	g.set_process(true)
	await wait(3)

func click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = get_root().get_mouse_position()
	g._unhandled_input(e)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	g._input(u)

## Done with whatever he was doing, full mana, nothing recharging, nothing armed.
func fresh() -> void:
	var h = g.hero
	var end := Time.get_ticks_msec() + 4000
	while h.atk_t >= 0.0 and Time.get_ticks_msec() < end:
		await process_frame
	await wait(2)
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	g.aiming.cancel()
	g.ui.msg_lbl.text = ""

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	AM = load("res://game/systems/skills/aiming.gd")
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	g.test_immortal = true
	g.test_allskills = true
	var h = g.hero
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	h.level = 12
	h.recalc()
	h.global_position = _open_ground()
	for b in h.beasts:
		b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 9999.0
	await secs(1.0)      # (the camera catches up)
	var aim = g.aiming
	var ind = g.get_node("AimIndicator")
	var was_on: bool = aim.click_cast
	aim.click_cast = true       # (the setting itself, not saved: its saving is checked at the end)
	h.binds["Q"] = "volley"
	h.binds["E"] = "pierce"
	h.binds["R"] = "snare"
	check(AM.is_area("volley") and not AM.is_area("pierce") and not AM.is_area("snare") and not AM.is_area("beast"),
		"Frost Volley is an area skill (its codex \"aoe\"); Fire Arrow, Thunderstep and Spirit Beast aren't")

	# the key arms it and spends nothing
	await fresh()
	var m0: float = h.mana
	tap(KEY_Q)
	await wait(2)
	check(aim.skill == "volley", "Q (Frost Volley) arms it")
	check(h.mana >= m0 - 0.01 and h.cds.get("volley", 0.0) <= 0.0 and h.atk_skill != "volley", "and casts nothing: no mana, no cooldown, no shot")
	for i in 5:
		g._use_bind("Q", false)      # (the key held down)
	check(aim.skill == "volley" and h.mana >= m0 - 0.01, "holding the key neither casts it nor lets it go")

	# he walks while it is armed
	var p0: Vector3 = h.global_position
	hold(KEY_D, true)
	await secs(0.6)
	hold(KEY_D, false)
	await secs(0.5)
	check(flat(h.global_position, p0) > 1.5 and aim.skill == "volley", "he walks with D while it is armed (%.1f m), still armed" % flat(h.global_position, p0))

	# the look: the range round him and the circle as big as the area, where it lands
	var spot: Vector3 = h.global_position + Vector3(0, 0, -6)
	spot.y = g.world.height_at(spot.x, spot.z)
	await point_at(spot)
	var r_rules: float = load("res://game/systems/skills/skill.gd").num("volley", "radius", -1.0)
	check(ind.ring != null and ind.ring.visible and ind.spot.visible, "the indicator shows: the range ring and the landing circle")
	check(is_equal_approx(ind.spot_r, r_rules) and absf(ind.spot_rim_radius() - r_rules) < 0.01,
		"the circle's radius is Frost Volley's own (%.2f m drawn, its codex k.radius %.2f)" % [ind.spot_rim_radius(), r_rules])
	check(flat(ind.spot_at, spot) < 0.05 and not ind.spot_far, "it sits under the pointer, in range")
	h.tfx["volley_size"] = 30.0
	await wait(2)
	check(is_equal_approx(ind.spot_r, r_rules * 1.3) and absf(ind.spot_rim_radius() - r_rules * 1.3) < 0.01,
		"Hailstorm (+30%% volley_size) widens it as it widens the rain (%.2f m)" % ind.spot_rim_radius())
	h.tfx.erase("volley_size")
	var far: Vector3 = h.global_position + Vector3(0, 0, -22)
	await point_at(far)
	var reach: float = AM.reach("volley")
	check(ind.spot_far and absf(flat(ind.spot_at, h.global_position) - reach) < 0.1,
		"past its range (%.0f m) it turns red and sits at the range's edge, where the cast lands (%.1f m)" % [reach, flat(ind.spot_at, h.global_position)])

	# the click casts it there: mana and cooldown then, no swing, no walk
	await point_at(spot)
	var m1: float = h.mana
	var want: Vector3 = h.skill_aim("volley", spot)
	aim.confirm(spot)
	await wait(1)
	check(h.atk_skill == "volley" and h.atk_t >= 0.0, "the click casts Frost Volley")
	check(absf(m1 - h.mana - h.skill_cost("volley")) < 1.0, "its mana is spent at the click (%.0f)" % (m1 - h.mana))
	check(flat(h.atk_aim, want) < 0.05 and flat(h.atk_aim, spot) < 0.05, "at the spot the circle showed, under the pointer")
	await real_pointer()
	var p1: Vector3 = h.global_position
	await secs(0.3)
	check(not aim.armed() and not g.lmb_held and flat(h.global_position, p1) < 0.2, "and that's all: let go, no held swing, no walk")
	check(not ind.spot.visible and not ind.ring.visible, "the indicator is gone")

	# the real left click (Game._unhandled_input) with the game's own pointer: it casts where the circle is (at the
	# range's edge when the pointer is past it), and doesn't swing or walk
	await fresh()
	tap(KEY_Q)
	await wait(3)
	var shown: Vector3 = ind.spot_at
	var m2: float = h.mana
	click()
	await wait(1)
	check(h.atk_skill == "volley" and absf(m2 - h.mana - h.skill_cost("volley")) < 1.0 and flat(h.atk_aim, shown) < 0.1 and not aim.armed(),
		"the left click casts it where the circle was (%.1f m off, %s)" % [flat(h.atk_aim, h.global_position), "past the range: at its edge" if ind.spot_far else "in range"])
	var p2: Vector3 = h.global_position
	await secs(0.3)
	check(not g.lmb_held and flat(h.global_position, p2) < 0.2, "and the click neither swings on nor walks")

	# Esc and the key again let it go, nothing spent
	await fresh()
	m0 = h.mana
	tap(KEY_Q)
	tap(KEY_ESCAPE)
	await wait(2)
	check(not aim.armed() and h.mana >= m0 - 0.01 and not g.paused, "Esc lets it go (no pause menu), nothing spent")
	tap(KEY_Q)
	tap(KEY_Q)
	await wait(2)
	check(not aim.armed() and h.mana >= m0 - 0.01 and h.atk_skill != "volley", "its key again lets it go, nothing spent")

	# another key: does its own thing
	tap(KEY_Q)
	tap(KEY_E)
	await wait(1)
	check(not aim.armed() and h.atk_skill == "pierce", "Fire Arrow's key while it's armed lets it go and shoots Fire Arrow")

	# a skill on a mouse button is cast by its own click (the button is the click); that click lets an armed aim go
	await fresh()
	var rmb: String = h.bound("rmb")
	h.binds["rmb"] = "volley"
	g._use_bind("rmb", true)
	await wait(1)
	check(not aim.armed() and h.atk_skill == "volley", "Frost Volley on right mouse casts on its click")
	await fresh()
	h.binds["rmb"] = "pierce"
	tap(KEY_Q)
	g._use_bind("rmb", true)
	await wait(1)
	check(not aim.armed() and h.atk_skill == "pierce", "right mouse (Fire Arrow) while Frost Volley is armed lets it go and shoots")
	h.binds["rmb"] = rmb

	# a skill that isn't on the "aoe" list casts on its key, as always
	await fresh()
	tap(KEY_E)
	await wait(1)
	check(h.atk_skill == "pierce" and not aim.armed(), "Fire Arrow (not an area) still shoots on its key")
	await fresh()
	tap(KEY_R)
	await wait(1)
	check(h.atk_skill == "snare" and not aim.armed(), "Thunderstep (movement) still goes on its key")

	# not ready: the cast's own message, not armed
	await fresh()
	h.cds["volley"] = 5.0
	tap(KEY_Q)
	check(not aim.armed() and g.ui.msg_lbl.text == "Frost Volley is recharging", "recharging: not armed, \"%s\"" % g.ui.msg_lbl.text)
	await fresh()
	h.mana = 0.0
	tap(KEY_Q)
	check(not aim.armed() and g.ui.msg_lbl.text == "Not enough mana", "no mana: not armed, \"%s\"" % g.ui.msg_lbl.text)

	# quick cast: area skills cast on the key again
	await fresh()
	aim.click_cast = false
	m0 = h.mana
	tap(KEY_Q)
	await wait(1)
	check(not aim.armed() and h.atk_skill == "volley" and h.mana < m0, "quick cast: Q casts Frost Volley at once")
	aim.click_cast = true

	# another hero's area skills: one arms another; radii from the constants in their code
	await fresh()
	h.set_class("plague")
	h.new_character()
	h.level = 12
	h.recalc()
	await wait(5)
	await fresh()
	h.binds["Q"] = "toxic"
	h.binds["E"] = "swarm"
	tap(KEY_Q)
	check(aim.skill == "toxic", "the Plague Doctor's vial arms")
	tap(KEY_E)
	check(aim.skill == "swarm", "Swarmcraft's key while it's armed arms Swarmcraft instead")
	var PL = load("res://game/heroes/plague/plague.gd")
	await point_at(h.global_position + Vector3(0, 0, -5))
	check(is_equal_approx(ind.spot_r, float(PL.SWARM_R)), "its circle is Plague.SWARM_R (%.1f m)" % ind.spot_r)
	await real_pointer()
	var radii := {"toxic": PL.CLOUD_R, "bloom": PL.BLOOM_R, "experiment": PL.EXP_R,
		"hurl": load("res://scripts/demon_skills.gd").HURL_R, "grasp": load("res://scripts/wraith_skills.gd").GRASP_R,
		"u_barrage": load("res://scripts/doug_skills.gd").BARRAGE_R, "a_barrage": load("res://game/systems/skills/skill.gd").num("a_barrage", "radius", -1.0)}
	var wrong := []
	for id in radii:
		if not is_equal_approx(AM.base_radius(id), float(radii[id])):
			wrong.append("%s %.2f != %.2f" % [id, AM.base_radius(id), float(radii[id])])
	check(wrong.is_empty(), "every area's radius is the number its rules hit with %s" % (str(wrong) if not wrong.is_empty() else "(%d checked)" % radii.size()))
	var bad := []
	for s in Data.SKILLS + Data.RUN_SKILLS:
		if AM.is_area(str(s["id"])) and (AM.base_radius(str(s["id"])) <= 0.0 or AM.reach(str(s["id"])) <= 0.0):
			bad.append(str(s["id"]))
	check(bad.is_empty(), "every area skill has a radius and a range %s" % str(bad))
	g.aiming.cancel()

	# the setting: saved, and in the pause menu
	var cf := ConfigFile.new()
	var had := cf.load(g.SETTINGS_PATH) == OK and cf.has_section_key(AM.SECTION, AM.KEY)
	var old = cf.get_value(AM.SECTION, AM.KEY, null) if had else null
	aim.set_click_cast(false)
	check(g._load_setting(AM.SECTION, AM.KEY, true) == false, "quick cast is saved in settings.cfg")
	g.toggle_pause()
	await wait(2)
	var btn: Button = g.ui.pause_panel.find_child("aoe_cast", true, false)
	check(btn != null and btn.text == "AoE skills: Quick cast", "the pause menu's settings show it (\"%s\")" % (btn.text if btn != null else "none"))
	if btn != null:
		btn.pressed.emit()
		check(aim.click_cast and btn.text == "AoE skills: Click to cast", "and its button switches back to click to cast")
	g.toggle_pause()
	# (put the player's own setting back)
	var cf2 := ConfigFile.new()
	cf2.load(g.SETTINGS_PATH)
	if had:
		cf2.set_value(AM.SECTION, AM.KEY, old)
	elif cf2.has_section_key(AM.SECTION, AM.KEY):
		cf2.erase_section_key(AM.SECTION, AM.KEY)
	cf2.save(g.SETTINGS_PATH)
	aim.click_cast = was_on
	print("[C] done, %d failed" % fails)
	quit()

## A spot with open ground round it (the camp has tents and a fire in the way).
func _open_ground() -> Vector3:
	var c: Vector3 = g.hero.global_position
	for r in [0.0, 6.0, 12.0, 18.0, 24.0]:
		for k in 12:
			var p: Vector3 = c + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			p.y = g.world.height_at(p.x, p.z)
			var ok := true
			for d in [Vector3(6, 0, 0), Vector3(0, 0, 6), Vector3(-6, 0, 0), Vector3(0, 0, -6)]:
				if absf((g.world.move(p, d) - p).length() - 6.0) > 0.1:
					ok = false
			if ok:
				return p
	return c
