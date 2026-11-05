class_name ZonePreload
extends RefCounted
## Tooling for recording exact world dependencies. ContentCatalog uses the recorded paths
## alongside declared families; all runtime preparation is owned by ResCache.

const RECORD := "user://zone_preload_record.json"

static func key(run: int, zone: String) -> String:
	return "%d:%s" % [run, zone]

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
