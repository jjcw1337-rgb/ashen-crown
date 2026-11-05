extends SceneTree
## Resource-only diagnostic. Does not instantiate or render; not a shader-warm benchmark.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path := "res://assets/models/arrows/fire.glb"
	var cached_before := ResourceLoader.has_cached(path)
	var start := Time.get_ticks_usec()
	var first := ResCache.get_res(path)
	var miss_us := Time.get_ticks_usec() - start
	if first == null:
		push_error("Resource probe could not load fire arrow")
		quit(1)
		return
	var same := true
	start = Time.get_ticks_usec()
	for i in 1000:
		same = same and ResCache.get_res(path) == first
	var hits_us := Time.get_ticks_usec() - start
	var weak: WeakRef = weakref(first)
	first = null
	var retained := weak.get_ref() != null and ResourceLoader.has_cached(path)
	ResCache._held.clear()
	await process_frame
	var released := weak.get_ref() == null
	var result := {"cached_before": cached_before, "first_get_us": miss_us,
		"thousand_hits_us": hits_us, "same_resource": same, "retained_by_cache": retained,
		"released_after_clear": released}
	print("[CACHE] ", JSON.stringify(result))
	quit(0 if same and retained and released and not cached_before else 1)
