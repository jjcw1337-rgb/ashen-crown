extends SceneTree
## Normal-clock BG completion through a local lobby worker. BotBrain uses ordinary
## movement, attacks, earned skills and belt items. No teleports, healing grants,
## invulnerability, forced portal/clock or direct extraction/result calls.
## --broker http://127.0.0.1:PORT --out ABSOLUTE_DIRECTORY
var g
var brain: BotBrain
var out := ""
var failed := false
var distance_walked := 0.0
var previous := Vector3.ZERO
var invalid_nodes := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().get_file().begins_with("AshenCrown-") or not args.has("--broker") or not args.has("--out"):
		quit(2)
		return
	var broker: String = args[args.find("--broker") + 1]
	if not broker.begins_with("http://127.0.0.1:"):
		quit(2)
		return
	out = args[args.find("--out") + 1]
	DirAccess.make_dir_recursive_absolute(out)
	BuildEnv.forced = {"env": "local", "cloud": "0", "lobby_url": broker}
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://bg_journey_characters/"
	g.old_save = g.char_dir + "absent.json"
	root.add_child(g)
	current_scene = g
	RenderingServer.frame_pre_draw.connect(_finite_transforms)
	brain = BotBrain.new()
	_run()

func _finite_transforms() -> void:
	if not is_instance_valid(g) or g._busy or not g.bg_mode: return
	var bow: Node3D = g.hero.weapon_node
	if not is_instance_valid(bow): return
	for node in bow.get_meta("strands", []):
		if node.transform.is_finite() or invalid_nodes.has(node.get_instance_id()): continue
		invalid_nodes[node.get_instance_id()] = true
		check(false, "bow strand remains finite")
		print("[JOURNEY INVALID] ", node.get_path(), " local=", node.transform, " script=", node.get_script())

func check(ok: bool, label: String) -> bool:
	print("[JOURNEY] ", "ok " if ok else "FAIL ", label)
	failed = failed or not ok
	return ok

func until(test: Callable, seconds := 120.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		g._intro_skip = true
		if test.call(): return true
		await process_frame
	return false

func press(scope: Node, button_name: String) -> bool:
	var button := scope.find_child(button_name, true, false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "usable " + button_name): return false
	button.pressed.emit()
	return true

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))

func nearest(radius := 18.0):
	var best = null
	for e in g.enemies_near(g.hero.global_position, radius):
		if not e.dead and (best == null or e.global_position.distance_to(g.hero.global_position) < best.global_position.distance_to(g.hero.global_position)):
			best = e
	return best

func tick() -> void:
	var now: Vector3 = g.hero.global_position
	distance_walked += now.distance_to(previous)
	previous = now
	brain.think(g.hero, func(_h): return nearest(), g.get_process_delta_time())
	await process_frame

func walk(at: Vector3, limit := 120.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit * 1000)
	var next_move := 0
	while Time.get_ticks_msec() < deadline and not g.hero.dead and g.bg_mode:
		if Vector2(g.hero.global_position.x - at.x, g.hero.global_position.z - at.z).length() < 1.8:
			g.hero.target = null
			g.hero.bot_hold = false
			g.hero.moving = false
			return true
		if nearest() == null and Time.get_ticks_msec() >= next_move:
			g.hero.cmd_move(at)
			next_move = Time.get_ticks_msec() + 500
		await tick()
	return check(false, "walk reached destination without death: " + str(at))

func _run() -> void:
	Engine.max_fps = 60
	if not check(await until(func(): return g.world != null and not g._busy and not g._intro_playing), "home ready"):
		await finish(); return
	Survivors.dir = "user://bg_journey_survivors/"
	DirAccess.make_dir_recursive_absolute(Survivors.dir)
	for name in DirAccess.get_files_at(Survivors.dir): DirAccess.remove_absolute(Survivors.dir + name)
	var c = g.lobby_client
	c.auth = "Bearer dev-bg-journey"
	c.identity = c.auth.sha256_text().substr(0, 24)
	c.run_class = "archer"
	c.open("battlegrounds")
	await until(func(): return c.loaded)
	if not press(c.view, "create"): await finish(); return
	if not check(await until(func(): return not c.room.is_empty()), "created lobby"): await finish(); return
	await shot("lobby")
	if not press(c.view, "ready"): await finish(); return
	if not check(await until(func(): return c.room.get("members", {}).get(c.identity, {}).get("ready", false)), "ready acknowledged"): await finish(); return
	if not press(c.view, "start"): await finish(); return
	if not check(await until(func(): return (g.net.welcomed and not g.net.loading and not g._busy and g.cur_zone == "bg") or (c.match_id == "" and not c.last_error.is_empty()), 180) and g.net.welcomed and g.cur_zone == "bg", "entered worker"): await finish(); return
	print("[JOURNEY PREPARATION] ", JSON.stringify(g.preparation_phases))
	check(g.char_id == "" and c.character == "run_archer", "lobby run identity does not create a story-save ID")
	check(g.hero.cls == "archer" and g.hero.level == 0 and not Battlegrounds.fast, "fresh Archer on normal raid clock")
	check(not g.test_immortal and not g.test_onehit and not g.test_allskills, "ordinary combat rules")
	previous = g.hero.global_position
	await process_frame
	check(g.ui.hud.get_node("bg_hud").is_visible_in_tree(), "raid instructions remain visible on the network client")
	await shot("arrival")
	var bells: Array = g.world.interactables.filter(func(t): return t.kind == "bell")
	bells.sort_custom(func(a, b): return a.global_position.distance_to(g.hero.global_position) < b.global_position.distance_to(g.hero.global_position))
	if not await walk(bells[0].global_position): await finish(); return
	g._interact(bells[0])
	if not check(await until(func(): return g.bg_raid.get("state", "") == "raid", 45), "bell starts raid"): await finish(); return
	var camps: Array = Camps.all(g.world).filter(func(x): return x.tier == 1)
	camps.sort_custom(func(a, b): return a.pos.distance_to(g.hero.global_position) < b.pos.distance_to(g.hero.global_position))
	var camp: Dictionary = camps[0]
	print("[JOURNEY] route camp ", camp.name)
	var chest = camp.chest_node
	if not await walk(chest.global_position, 180): await finish(); return
	check(not g.chest_sealed(chest), "ordinary combat cleared " + str(camp.name))
	await shot("camp-cleared")
	g._interact(chest)
	if not check(await until(func(): return g.ui.run_ui.mode == "offer", 15), "earned upgrade offer"): await finish(); return
	await process_frame
	check(not g.ui.msg_lbl.is_visible_in_tree(), "level-up message does not cover upgrade choices")
	await shot("upgrade")
	var choices: Array = g.ui.run_ui.find_children("*", "Button", true, false).filter(func(b): return b.text.to_lower() == "choose" and b.is_visible_in_tree())
	if not check(not choices.is_empty(), "upgrade has Choose button"): await finish(); return
	choices[0].pressed.emit()
	await process_frame
	check(g.hero.run.skills.size() + g.hero.run.passives.size() > 0, "earned upgrade applied")
	# Items use the normal walking/pickup path; gear already occupying a slot is optional.
	for item in g.world.items_root.get_children():
		if not is_instance_valid(item) or not item is GroundItem or item.global_position.distance_to(chest.global_position) > 15: continue
		if not await walk(item.global_position, 30): await finish(); return
		g._pickup(item)
		await process_frame
		g.ui.run_ui.close()
	var deadline := Time.get_ticks_msec() + 500000
	while g.bg_raid.get("open", []).is_empty() and Time.get_ticks_msec() < deadline and not g.hero.dead:
		await tick()
	if not check(not g.hero.dead and not g.bg_raid.get("open", []).is_empty(), "survived until portals open on normal clock"): await finish(); return
	var portals: Array = Battlegrounds.portal_list(g.world)
	var open: Array = []
	for index in g.bg_raid["open"]: open.append(portals[int(index)])
	open.sort_custom(func(a, b): return a.global_position.distance_to(g.hero.global_position) < b.global_position.distance_to(g.hero.global_position))
	print("[JOURNEY] portal route ", open[0].global_position)
	if not await walk(open[0].global_position, 240): await finish(); return
	await shot("portal")
	g._interact(open[0])
	if not check(await until(func(): return not g.bg_mode and g.ui.run_ui.mode == "results", 30), "server confirmed extraction"): await finish(); return
	await shot("survived")
	if not press(g.ui.run_ui, "save"): await finish(); return
	check(Survivors.list().size() == 1, "survivor saved once")
	if not press(g.ui.run_ui, "return"): await finish(); return
	check(await until(func(): return not g._busy and not g.net.active and g.ui.title_panel.visible), "Return closes connection and reaches home")
	check(distance_walked > 40, "walked %.1f metres without teleport" % distance_walked)
	await shot("returned")
	await finish()

func finish() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_finite_transforms): RenderingServer.frame_pre_draw.disconnect(_finite_transforms)
	g.net.shutdown()
	g.queue_free()
	for i in 12: await process_frame
	print("[JOURNEY] done, ", 1 if failed else 0, " failure(s)")
	quit(1 if failed else 0)
