extends SceneTree
## Source-renderer contract: opening a solo world to co-op prepares every class before admission.
## Runs locally without opening Steam/ENet or using real characters.
var g
var failed := 0
func _initialize() -> void:
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	call_deferred("run")
func _process(_dt: float) -> bool:
	if is_instance_valid(g): g._intro_skip = true
	return false
func check(ok: bool, label: String) -> void:
	print("[HOST CONTENT] ", "ok " if ok else "FAIL ", label)
	if not ok: failed += 1
func run() -> void:
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://content_host_test/"
	g.old_save = "user://content_host_test/absent.json"
	root.add_child(g)
	current_scene = g
	while g._busy or g.world == null or not g.ui.title_panel.visible:
		await process_frame
	check(not await g.prepare_host_presentation(), "title cannot open admission")
	await g.start_game(false, "knight", "", "Host readiness test")
	g.ui.close_all()
	var world_id: int = g.world.get_instance_id()
	var char_id: String = g.char_id
	check(await g.prepare_host_presentation(), "solo to online preparation completes")
	check(g.world.get_instance_id() == world_id and g.char_id == char_id, "world and character preserved")
	check(not g.net.active and not g._busy and not g.loading.visible, "transport still closed and loading restored")
	if DisplayServer.get_name() != "headless":
		check(ResCache.status(g._combat_scope).ready, "online combat scope ready")
		var warmed := true
		for cls in SkillWarmData.EVENTS:
			warmed = warmed and SkillWarm._done.has(SkillWarm.context(g) + ":" + str(cls))
		check(warmed, "all late-arrival classes prepared")
		var batches: int = ResCache.metrics().batches_started
		check(await g.prepare_host_presentation(), "repeat preparation succeeds")
		check(ResCache.metrics().batches_started == batches, "repeat preparation reuses resources")
		var args := OS.get_cmdline_user_args()
		if args.has("--capture"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[args.find("--capture") + 1])
	await g.exit_to_title()
	check(g._combat_scope == "" and SkillWarm._kept.is_empty(), "title releases combat ownership and warm materials")
	g.queue_free()
	for i in 8: await process_frame
	check(ResCache.metrics().scopes == 0 and ResCache.metrics().pending == 0, "teardown has no owned or pending resources")
	quit(0 if failed == 0 else 1)
