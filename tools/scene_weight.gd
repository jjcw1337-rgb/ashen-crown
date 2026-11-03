extends SceneTree
## What the imported .glb scenes are made of (for the download size): per scene its meshes' vertices, triangles,
## vertex attributes (tangents, UV2, colours, bones) and animations' tracks and keys, largest first.
##   godot --headless --path . -s tools/scene_weight.gd -- [out.txt]
func _initialize():
	var rows := []
	for p in _glbs("res://assets/models"):
		var ps = load(p)
		if not (ps is PackedScene):
			continue
		var n: Node = ps.instantiate()
		var r := {"path": p, "v": 0, "t": 0, "tan": 0, "uv2": 0, "col": 0, "bones": 0, "blend": 0, "anims": 0, "keys": 0, "lods": 0}
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			if m == null:
				continue
			for s in m.get_surface_count():
				var fmt := (m as ArrayMesh).surface_get_format(s) if m is ArrayMesh else 0
				var arr := m.surface_get_arrays(s)
				var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				r["v"] += nv
				var idx = arr[Mesh.ARRAY_INDEX]
				r["t"] += (idx.size() / 3) if idx != null else nv / 3
				if fmt & Mesh.ARRAY_FORMAT_TANGENT: r["tan"] += nv
				if fmt & Mesh.ARRAY_FORMAT_TEX_UV2: r["uv2"] += nv
				if fmt & Mesh.ARRAY_FORMAT_COLOR: r["col"] += nv
				if fmt & Mesh.ARRAY_FORMAT_BONES: r["bones"] += nv
				if m is ArrayMesh:
					r["blend"] += (m as ArrayMesh).get_blend_shape_count()
		for ap in n.find_children("*", "AnimationPlayer", true, false):
			for lib_name in ap.get_animation_library_list():
				var lib: AnimationLibrary = ap.get_animation_library(lib_name)
				for an in lib.get_animation_list():
					var a: Animation = lib.get_animation(an)
					r["anims"] += 1
					for ti in a.get_track_count():
						r["keys"] += a.track_get_key_count(ti)
		n.free()
		rows.append(r)
	rows.sort_custom(func(a, b): return int(a["v"]) > int(b["v"]))
	var out := ""
	var tot := {"v": 0, "t": 0, "tan": 0, "uv2": 0, "col": 0, "bones": 0, "keys": 0}
	for r in rows:
		out += "%-60s v %7d t %7d tan %7d uv2 %7d col %7d bones %7d anims %3d keys %8d\n" % [r["path"], r["v"], r["t"], r["tan"], r["uv2"], r["col"], r["bones"], r["anims"], r["keys"]]
		for k in tot:
			tot[k] += int(r[k])
	out += "TOTAL %s\n" % str(tot)
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		var fo := FileAccess.open(a[0], FileAccess.WRITE)
		fo.store_string(out)
	print(out)
	quit()

func _glbs(dir: String) -> Array:
	var res := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".glb"):
			res.append(dir + "/" + f)
	for s in d.get_directories():
		res.append_array(_glbs(dir + "/" + s))
	return res
