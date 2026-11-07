class_name ResCache
extends RefCounted
## The game's one loader (docs/systems/loading.md). Everything a screen, zone or effect needs from disk goes through
## here, in one of two ways:
##
##   prepare(scope, paths)   ahead of time, under a loading screen or the intro: Godot's threaded loader reads the
##                           files on its worker pool, many at once (game/systems/loading/tests/load_bench.gd, 4.4.1: the camp's 163 files
##                           1.2 s in parallel against 3.1 s frozen on the main thread and 11 s on one worker thread).
##                           `wait_ready` awaits a scope frame by frame so the screen keeps drawing; `release` lets a
##                           scope's files go when its zone is left.
##   get_res(path) / inst()  at the moment of use. Returns a prepared file at once; otherwise loads it on the main
##                           thread (a stall, counted in `misses` so a missing list entry shows) and keeps it for the
##                           session: an effect's model would otherwise be dropped with the effect and parsed again
##                           on every cast (each Archer arrow 14-17 ms, the frame-time audit of 2026-11-05).
##
## Lists are exact (recorded or declared paths, never whole folders: a folder pulls in files nobody uses and their video
## memory). `pump` runs every frame from Game._process; it only collects finished files, nothing else runs off-thread.

static var _held := {}        # path -> Resource: everything loaded, until no scope or session pin keeps it
static var _pinned := {}      # path -> true: loaded at the moment of use (get_res), kept for the session
static var _scopes := {}      # scope -> {path: true}
static var _pending := {}     # path -> true: requested from the threaded loader, not collected yet
static var _failed := {}      # path -> true
static var misses := {}       # path -> count: get_res had to load it on the main thread

## Ask for `paths` on the loader's threads, owned by `scope` (a name: "boot", "zone:<id>"). Paths already held join
## the scope at once; a path that doesn't exist is skipped (a stale list only costs speed).
static func prepare(scope: String, paths: Array) -> void:
	if not _scopes.has(scope):
		_scopes[scope] = {}
	for item in paths:
		var p := str(item)
		if p == "" or _scopes[scope].has(p):
			continue
		_scopes[scope][p] = true
		if _held.has(p) or _pending.has(p):
			continue
		if ResourceLoader.has_cached(p):
			_held[p] = ResourceLoader.load(p)      # (already in memory: no read, just a reference)
		elif not ResourceLoader.exists(p) or OS.has_feature("web"):
			_scopes[scope].erase(p)                # (the web build has no loader threads; its builds load as they go)
		elif ResourceLoader.load_threaded_request(p, "", true) == OK:
			_pending[p] = true
		else:
			_failed[p] = true

## Collect the files the loader's threads have finished. Every frame (Game._process) and while waiting.
static func pump() -> void:
	if _pending.is_empty():
		return
	for p in _pending.keys():
		match ResourceLoader.load_threaded_get_status(p):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass
			ResourceLoader.THREAD_LOAD_LOADED:
				_pending.erase(p)
				var r := ResourceLoader.load_threaded_get(p)
				if _owned(p):
					_held[p] = r
			_:
				_pending.erase(p)
				_failed[p] = true

## How far a scope is: {"ready", "left", "failed"}. An unknown scope is ready (nothing was asked).
static func status(scope: String) -> Dictionary:
	var left := 0
	var failed := 0
	for p in _scopes.get(scope, {}):
		if _failed.has(p):
			failed += 1
		elif not _held.has(p):
			left += 1
	return {"ready": left == 0, "left": left, "failed": failed, "total": (_scopes.get(scope, {}) as Dictionary).size()}

## Await a scope a frame at a time (the screen keeps drawing), at most `max_s`. `on_progress(fraction)` each frame.
static func wait_ready(tree: SceneTree, scope: String, max_s := 30.0, on_progress := Callable()) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while true:
		pump()
		var st := status(scope)
		if on_progress.is_valid() and int(st["total"]) > 0:
			on_progress.call(1.0 - float(st["left"]) / float(st["total"]))
		if st["ready"] or Time.get_ticks_msec() - t0 > int(max_s * 1000.0):
			return st
		await tree.process_frame
	return {}

## A scope is done with (its zone left, the boot over). Its files stay only if another scope or a session pin keeps
## them; a file still loading is dropped when it finishes.
static func release(scope: String) -> void:
	if not _scopes.has(scope):
		return
	var paths: Dictionary = _scopes[scope]
	_scopes.erase(scope)
	for p in paths:
		if _held.has(p) and not _owned(p):
			_held.erase(p)

static func _owned(p: String) -> bool:
	if _pinned.has(p):
		return true
	for s in _scopes:
		if (_scopes[s] as Dictionary).has(p):
			return true
	return false

## The resource at `path` (null if it isn't there): prepared, or loaded now and kept for the session.
static func get_res(path: String) -> Resource:
	if _held.has(path):
		_pinned[path] = true
		return _held[path]
	if _pending.has(path):
		pump()
		if _held.has(path):
			_pinned[path] = true
			return _held[path]
	misses[path] = int(misses.get(path, 0)) + 1
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	_held[path] = r
	_pinned[path] = true
	return r

## A new instance of the scene at `path` (null if it isn't there).
static func inst(path: String) -> Node:
	var ps := get_res(path) as PackedScene
	return ps.instantiate() if ps != null else null

## Load `paths` now and keep them for the session (a loading screen calls it), so the first use finds them held.
static func hold(paths: Array) -> void:
	for p in paths:
		get_res(str(p))

## What the loader holds (tests and tools).
static func metrics() -> Dictionary:
	return {"held": _held.size(), "pinned": _pinned.size(), "scopes": _scopes.keys(), "pending": _pending.size(),
		"failed": _failed.size(), "misses": misses.size()}
