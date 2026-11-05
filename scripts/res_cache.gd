class_name ResCache
extends RefCounted
## Models and textures that skills and gear load while the game runs, held for the whole session (the frame-time
## audit, Blaine 2026-11-05). Godot's ResourceLoader only keeps a resource while something references it, so an
## effect's model went with the effect and the next cast parsed the file again on the main thread: every Archer
## arrow reloaded its glb (14-17 ms a shot), the Plague Doctor's flask, swarm, censer and vat their models.

static var _held := {}

## The resource at `path` (null if it isn't there), loaded once.
static func get_res(path: String) -> Resource:
	if not _held.has(path):
		_held[path] = load(path) if ResourceLoader.exists(path) else null
	return _held[path]

## A new instance of the scene at `path` (null if it isn't there).
static func inst(path: String) -> Node:
	var ps := get_res(path) as PackedScene
	return ps.instantiate() if ps != null else null

## Load `paths` now (a loading screen calls it), so the first use finds them held.
static func hold(paths: Array) -> void:
	for p in paths:
		get_res(str(p))
