class_name ResCache
extends RefCounted
## Main-thread coordinator over Godot's resource cache. One owned background thread loads
## resources sequentially; only finished worker results are collected on the main thread.
## Native loader crashes occurred in the 4.3 threaded-status pilot; the exact native cause
## is unproven. An owned thread gives an explicit completion boundary. No scene-tree work runs there.
const MAX_IN_FLIGHT := 8 # resource roots per bounded batch; still exactly one worker
static var _thread: Thread
static var _held := {}
static var _mesh_parts := {}
static var _mesh_parts_builds := 0
static var _scopes := {}
static var _pending := {}
static var _queue: Array[String] = []
static var _errors := {}
static var _legacy := {} # compatibility pins for unconverted callers, visible in diagnostics
static var _sync_misses := {}
static var _loads_started := 0
static var _batches_started := 0

static func prepare(scope: String, paths: Array) -> void:
	if not _scopes.has(scope):
		_scopes[scope] = {}
	for item in paths:
		var path := str(item)
		_scopes[scope][path] = true
		_errors.erase(path) # a new request may retry a previously failed file
		if _held.has(path) or _pending.has(path) or _queue.has(path):
			continue
		if not ResourceLoader.exists(path):
			_errors[path] = "missing"
		else:
			_queue.append(path)
	pump()

static func pump() -> void:
	if _thread != null:
		if _thread.is_alive(): return
		var loaded: Dictionary = _thread.wait_to_finish()
		_thread = null
		for path in _pending:
			var res: Resource = loaded.get(path)
			if res != null:
				if _owned(path): _held[path] = res
			else:
				_errors[path] = "load failed"
		_pending.clear()
	# Collect several roots per frame instead of requiring a frame for every small file.
	# This diagnostic flag reproduces the previous one-root scheduling policy for paired runs.
	var limit := 1 if OS.get_cmdline_user_args().has("--content-batch-one") else MAX_IN_FLIGHT
	var batch: Array[String] = []
	while batch.size() < limit and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if not _owned(path): continue
		if ResourceLoader.has_cached(path):
			_held[path] = load(path)
			continue
		batch.append(path)
	if batch.is_empty(): return
	if OS.get_cmdline_user_args().has("--content-trace"):
		print("[content] batch ", batch)
	_thread = Thread.new()
	var err := _thread.start(_load_worker.bind(batch))
	if err == OK:
		for path in batch: _pending[path] = true
		_loads_started += batch.size()
		_batches_started += 1
	else:
		_thread = null
		for path in batch: _errors[path] = "request error %d" % err

static func _load_worker(paths: Array[String]) -> Dictionary:
	var loaded := {}
	for path in paths: loaded[path] = ResourceLoader.load(path)
	return loaded

static func status(scope: String) -> Dictionary:
	if not _scopes.has(scope):
		return {"ready": false, "cancelled": true, "pending": 0, "failed": []}
	var failed: Array[String] = []
	var remaining := 0
	for path in _scopes[scope]:
		if _errors.has(path):
			failed.append(path)
		elif not _held.has(path):
			remaining += 1
	return {"ready": remaining == 0 and failed.is_empty(), "cancelled": false,
		"pending": remaining, "failed": failed}

static func wait_ready(tree: SceneTree, scope: String, timeout_s := 60.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while true:
		pump()
		var result := status(scope)
		if result["cancelled"] or result["pending"] == 0:
			return result
		if Time.get_ticks_msec() >= deadline:
			result["timeout"] = true
			return result
		await tree.process_frame
	return {}

static func release(scope: String) -> void:
	_scopes.erase(scope)
	for path in _held.keys():
		if not _owned(path):
			_held.erase(path)
			_mesh_parts.erase(path)
	# An in-flight load finishes normally; pump joins the worker and discards an unowned result.

static func _owned(path: String) -> bool:
	if _legacy.has(path):
		return true
	for paths in _scopes.values():
		if paths.has(path):
			return true
	return false

## Transitional fallback. New gameplay code should acquire a scope before activation.
## Misses are counted by path so an omitted dependency is observable, rather than silently hidden.
static func get_res(path: String) -> Resource:
	if _held.has(path):
		return _held[path]
	_sync_misses[path] = int(_sync_misses.get(path, 0)) + 1
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	if res != null:
		if not _owned(path):
			_legacy[path] = true
		_held[path] = res
	return res

static func inst(path: String) -> Node:
	var ps := get_res(path) as PackedScene
	return ps.instantiate() if ps != null else null

## Immutable fragment recipes derived on the main thread, once per owned scene.
## Keep each mesh's local offset: these glass effects historically use local positions.
## Callers create only the live debris nodes; the temporary imported scene is never rebuilt per burst.
static func mesh_parts(path: String) -> Array:
	if _mesh_parts.has(path): return _mesh_parts[path]
	var scene := get_res(path) as PackedScene
	if scene == null: return []
	var source := scene.instantiate()
	var parts: Array = []
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		parts.append({"mesh": mi.mesh, "position": mi.position})
	source.free()
	_mesh_parts[path] = parts
	_mesh_parts_builds += 1
	return parts

static func hold(paths: Array) -> void:
	for p in paths:
		get_res(str(p))

static func metrics() -> Dictionary:
	return {"held": _held.size(), "scopes": _scopes.size(), "pending": _pending.size(),
		"queued": _queue.size(), "derived_mesh_sets": _mesh_parts.size(), "mesh_parts_builds": _mesh_parts_builds, "legacy_pins": _legacy.size(), "loads_started": _loads_started, "batches_started": _batches_started,
		"sync_misses": _sync_misses.duplicate(), "errors": _errors.duplicate()}

## Only at final teardown; ordinary cancellation is nonblocking and handled by pump().
static func shutdown_if_unused() -> void:
	if not _scopes.is_empty(): return
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_pending.clear()
	_queue.clear()
	# Final application teardown also releases transitional pins and derived recipes.
	# Live consumers retain their own Resource references; no cache owns them now.
	_mesh_parts.clear()
	_held.clear()
	_legacy.clear()
	_errors.clear()
