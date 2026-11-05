class_name ZonePreload
extends RefCounted
## A zone's model files loaded on worker threads from the moment the loading screen goes up (nightly 2026-11-05):
## World.build loaded each .glb on the main thread as it reached it (the Act I camp: 50 of them, 4.3 s of its build;
## the grand waypoint alone 1.1 s). Requested here in parallel before the old zone is freed, each `load()` in the
## build then finds its file loaded or finishing (a load of a path already loading on a thread waits for it).
## The lists (ZonePreloadData.PATHS, by "run:zone") are recorded from the built zones: run the game with
## `-- --kpi <scenario> out.json --preload-record` (or any zone with the flag) and `python3 tools/zone_preload_gen.py`
## turns user://zone_preload_record.json into scripts/zone_preload_data.gd. A stale list only costs speed: a path
## that's gone is skipped, one that's missing is loaded on the main thread as before.

const RECORD := "user://zone_preload_record.json"

static func key(run: int, zone: String) -> String:
	return "%d:%s" % [run, zone]

## Ask for the zone's files on worker threads; returns the paths requested (hand them to finish()).
static func start(run: int, zone: String) -> PackedStringArray:
	var out := PackedStringArray()
	if OS.has_feature("web"):
		return out
	for p in ZonePreloadData.PATHS.get(key(run, zone), []):
		var ps := str(p)
		if ResourceLoader.has_cached(ps) or not ResourceLoader.exists(ps):
			continue
		if ResourceLoader.load_threaded_request(ps, "", true) == OK:
			out.append(ps)
	return out

## Close the threaded requests (the build has the resources by now; this only collects them).
static func finish(paths: PackedStringArray) -> void:
	for p in paths:
		ResourceLoader.load_threaded_get(p)

## (tools) Which .glb files the built zone uses: every instanced scene's file and every mesh's source scene, found
## through the imported file's name (`<file>-<md5 of the source path>.scn`).
static func record(world: Node, run: int, zone: String) -> void:
	var by_imported := {}
	for p in _glbs("res://assets/models"):
		by_imported["%s-%s.scn" % [p.get_file(), p.md5_text()]] = p
	var used := {}
	for n in world.find_children("*", "", true, false):
		var sf: String = n.scene_file_path
		if sf.ends_with(".glb"):
			used[sf] = true
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			m = (n as MultiMeshInstance3D).multimesh.mesh
		if m != null and m.resource_path.contains(".godot/imported/"):
			var f := m.resource_path.get_file().split("::")[0]
			if by_imported.has(f):
				used[by_imported[f]] = true
	var all := {}
	if FileAccess.file_exists(RECORD):
		var d = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
		if d is Dictionary:
			all = d
	var keys := used.keys()
	keys.sort()
	all[key(run, zone)] = keys
	var fo := FileAccess.open(RECORD, FileAccess.WRITE)
	fo.store_string(JSON.stringify(all, " "))
	print("[preload] recorded %s: %d files" % [key(run, zone), keys.size()])

static func _glbs(dir: String) -> Array:
	var res := []
	var d := DirAccess.open(dir)
	if d == null:
		return res
	for f in d.get_files():
		if f.ends_with(".glb"):
			res.append(dir + "/" + f)
	for s in d.get_directories():
		res.append_array(_glbs(dir + "/" + s))
	return res
