extends SceneTree
## Exercise actual PvP builders against declared roots; source lists alone cannot prove coverage.
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("[WORLD CONTENT] ", "ok " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	Mats.ensure_globals()
	World.detail = 1
	var catalog = load("res://scripts/content_catalog.gd")
	for zone in ["arena", "bg"]:
		var scope: String = "world-contract:" + zone
		ResCache.prepare(scope, catalog.zone(0, zone))
		var ready := await ResCache.wait_ready(self, scope)
		check(ready.ready, zone + " dependencies ready")
		var before: Dictionary = ResCache.metrics().sync_misses
		var w := World.new()
		w.process_mode = Node.PROCESS_MODE_DISABLED
		w.run = 0
		w.oak_forest = true
		w.fort = true
		w.living_grass = true
		root.add_child(w)
		await w.build(0, zone, 4207)
		var misses := {}
		for path in ResCache.metrics().sync_misses:
			var count := int(ResCache.metrics().sync_misses[path]) - int(before.get(path, 0))
			if count > 0: misses[path] = count
		check(misses.is_empty(), zone + " builds without undeclared cache requests: " + str(misses))
		check(not w.spawns.is_empty(), zone + " has player spawns")
		w.queue_free()
		for i in 10: await process_frame
		ResCache.release(scope)
	ResCache.shutdown_if_unused()
	check(ResCache.metrics().scopes == 0 and ResCache.metrics().pending == 0, "no content owners or jobs after teardown")
	print("[WORLD CONTENT] done, ", failures, " failed")
	quit(1 if failures else 0)
