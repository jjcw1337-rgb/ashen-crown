extends SceneTree
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		quit(1)
func run() -> void:
	var cache = load("res://scripts/res_cache.gd")
	var paths: Array = []
	for i in 8:
		var path := "user://cache_fixture_%d.tres" % i
		var resource := Resource.new()
		check(ResourceSaver.save(resource, path) == OK, "fixture save")
		paths.append(path)
		resource = null
	var preexisting: Resource = load(paths[0])
	print("prepare a")
	cache.prepare("a", paths)
	print("prepare b")
	cache.prepare("b", paths)
	check(cache.metrics().pending <= cache.MAX_IN_FLIGHT, "bounded concurrency")
	var ready: Dictionary = await cache.wait_ready(self, "a")
	check(ready.ready, "async preparation")
	check(cache.status("b").ready, "coalesced readiness")
	check(cache.metrics().loads_started == 7, "no duplicate requests")
	check(cache.metrics().batches_started == 1, "seven uncached roots share one bounded worker batch")
	var first: Resource = cache.get_res(paths[0])
	check(first == cache.get_res(paths[0]), "identity")
	check(cache.metrics().sync_misses.is_empty(), "no synchronous miss")
	cache.release("a")
	check(cache.status("b").ready, "other owner remains")
	var weak: WeakRef = weakref(first)
	cache.release("b")
	check(cache.metrics().held == 0 and weak.get_ref() != null, "live consumer retained")
	first = null
	preexisting = null
	await process_frame
	check(weak.get_ref() == null, "released after last consumer")
	print("cancel phase")
	cache.prepare("cancel", paths)
	cache.release("cancel")
	for i in 100:
		cache.pump()
		await process_frame
		if cache.metrics().pending == 0:
			break
	check(cache.metrics().held == 0 and cache.metrics().pending == 0, "cancel drains without retention")
	check(cache.status("cancel").cancelled, "cancel reports cancellation")
	cache.prepare("missing", ["user://missing_cache_fixture.tres"])
	check(not cache.status("missing").ready and cache.status("missing").failed.size() == 1, "missing is not ready")
	cache.release("missing")
	cache.get_res(paths[0])
	check(cache.metrics().legacy_pins == 1, "fallback owns a transitional pin")
	cache.shutdown_if_unused()
	check(cache.metrics().held == 0 and cache.metrics().legacy_pins == 0, "final shutdown releases transitional pins")
	for path in paths:
		DirAccess.remove_absolute(path)
	print("[CACHE TEST] %d checks" % checks)
	quit()
