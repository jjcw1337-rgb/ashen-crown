extends SceneTree
## Scene census for the visual overhaul (headless, no GPU needed):
##   godot --headless --path . -s tools/visual_audit/scene_census.gd -- out_dir [zone ...]
## Zones: bg sandbox (default: all). For each zone it builds the
## world exactly as the game does, then walks every GeometryInstance3D, light, particle system and decal and
## writes <out_dir>/<zone>.json plus a printed summary: triangles (LOD0) x instances, how many LOD levels each
## mesh has, multimeshes whose bounds are so big they can't be culled or LOD-ed (one draw for the whole map),
## shadow casters, lights with shadows, particle counts. Groups rows by the mesh's resource path or the node's
## name pattern so the same prop placed 200 times is one row. Used for the visual audit of 2026-11-02 (in git history) and before/after.

var g
var out_dir := "build/visual_audit"
const ZONES := {
	"bg": [0, "bg"], "sandbox": [0, "sandbox"],
}

func _initialize():
	var args := OS.get_cmdline_user_args()
	var zones: Array = []
	if args.size() > 0:
		out_dir = args[0]
	for i in range(1, args.size()):
		zones.append(args[i])
	if zones.is_empty():
		zones = ZONES.keys()
	DirAccess.make_dir_recursive_absolute(out_dir)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run(zones)

func _run(zones: Array) -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	for z in zones:
		if not ZONES.has(z):
			print("[CENSUS] unknown zone ", z)
			continue
		var spec: Array = ZONES[z]
		var t0 := Time.get_ticks_msec()
		await g.load_zone(0, spec[1], "start")
		for i in 3:
			await process_frame
		var ms := Time.get_ticks_msec() - t0
		_census(z, ms)
	quit()

static var _headless := DisplayServer.get_name() == "headless"
static var _labels := {}

## Names for meshes built in code, from the game's own caches (Flora, Geo, Grass).
static func build_labels() -> void:
	_labels.clear()
	# loaded by path at run time: naming the classes here would compile them before the Sfx autoload exists
	var caches := {"Flora": ["flora", "_cache"], "Geo": ["geo", "_cache"],
		"Grass": ["grass", "_meshes"], "GrassGlb": ["grass", "_glb"]}
	for cname in caches.keys():
		var sc: GDScript = load("res://scripts/%s.gd" % caches[cname][0])
		var d = sc.get(caches[cname][1])
		if not (d is Dictionary):
			continue
		for k in (d as Dictionary).keys():
			var v = d[k]
			if v is Mesh:
				_labels[(v as Mesh).get_instance_id()] = "%s:%s" % [cname, str(k).get_file()]
			elif v is Array:
				for i in (v as Array).size():
					if (v as Array)[i] is Mesh:
						_labels[((v as Array)[i] as Mesh).get_instance_id()] = "%s:%s[%d]" % [cname, str(k).get_file(), i]

static func _surface_lods(mesh: Mesh, si: int) -> int:
	if not (mesh is ArrayMesh) or _headless:
		return -1
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), si)
	if d.has("lods"):
		return (d["lods"] as Array).size()
	return 0

static func mesh_info(mesh: Mesh) -> Dictionary:
	var tris := 0
	var lods := 99
	var mats := []
	for si in mesh.get_surface_count():
		var arr_tris := 0
		if mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			var ic := am.surface_get_array_index_len(si)
			arr_tris = (ic if ic > 0 else am.surface_get_array_len(si)) / 3
		else:
			var arr := mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			var vtx = arr[Mesh.ARRAY_VERTEX]
			arr_tris = ((idx as PackedInt32Array).size() if idx != null else (vtx as PackedVector3Array).size()) / 3
		tris += arr_tris
		lods = mini(lods, _surface_lods(mesh, si))
		var m := mesh.surface_get_material(si)
		mats.append(_mat_name(m))
	if mesh.get_surface_count() == 0:
		lods = 0
	return {"tris": tris, "lods": lods, "surfaces": mesh.get_surface_count(), "mats": mats}

static func _mat_name(m: Material) -> String:
	if m == null:
		return "none"
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return "shader:?"
		var p := sh.resource_path
		if p != "":
			return "shader:" + p.get_file()
		var code := sh.code
		return "shader:%s" % str(code.hash()).substr(0, 6)
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		var bits := []
		if s.albedo_texture:
			bits.append("alb")
		if s.normal_enabled and s.normal_texture:
			bits.append("nrm")
		if s.roughness_texture or s.metallic_texture:
			bits.append("rm")
		if s.ao_enabled:
			bits.append("ao")
		if s.emission_enabled:
			bits.append("emi")
		if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			bits.append("alpha%d" % s.transparency)
		if s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			bits.append("unshaded")
		return "std:" + (",".join(bits) if not bits.is_empty() else "flat")
	return m.get_class()

## A short key for grouping: the mesh's resource path if it came from a file, else the node name without digits
## and the parent's name.
static func _key(n: Node, mesh: Mesh) -> String:
	if mesh and mesh.resource_path != "" and not mesh.resource_path.contains("::"):
		return mesh.resource_path.get_file()
	if mesh and _labels.has(mesh.get_instance_id()):
		return _labels[mesh.get_instance_id()]
	if mesh and mesh.resource_path.contains("::"):
		return mesh.resource_path.get_file().get_slice("::", 0) + " (sub)"
	var nm := String(n.name)
	var re := RegEx.new()
	re.compile("[-0-9@]+")
	nm = re.sub(nm, "#", true)
	var par := n.get_parent()
	var pn := String(par.name) if par else ""
	pn = re.sub(pn, "#", true)
	var src := ""
	var p: Node = n
	for i in 6:
		if p == null:
			break
		var sc = p.get_script()
		if sc != null and (sc as Script).resource_path != "":
			src = (sc as Script).resource_path.get_file().get_basename()
			break
		p = p.get_parent()
	return "%s/%s%s" % [pn, nm, (" (" + src + ")") if src != "" else ""]

func _census(zone: String, load_ms: int) -> void:
	var root: Node = g.world
	build_labels()
	var rows := {}
	var lights := {"omni": 0, "spot": 0, "dir": 0, "shadowed": 0, "omni_shadowed": 0}
	var particles := {"gpu": 0, "cpu": 0, "amount": 0}
	var decals := 0
	var big_mm := []
	var totals := {"tris_lod0": 0, "tris_shadow_lod0": 0, "instances": 0, "nodes": 0, "geom": 0, "no_lod_tris": 0}
	var all_nodes: Array = [root]
	# the hero and his effects are outside the world node: count them too
	all_nodes.append(g.hero)
	var seen := {}
	for base in all_nodes:
		if base == null:
			continue
		var list: Array = base.find_children("*", "Node", true, false)
		list.append(base)
		for n in list:
			if seen.has(n):
				continue
			seen[n] = true
			totals["nodes"] = int(totals["nodes"]) + 1
			if n is Light3D:
				var l := n as Light3D
				if not l.is_visible_in_tree():
					continue
				if l is OmniLight3D:
					lights["omni"] = int(lights["omni"]) + 1
				elif l is SpotLight3D:
					lights["spot"] = int(lights["spot"]) + 1
				else:
					lights["dir"] = int(lights["dir"]) + 1
				if l.shadow_enabled:
					lights["shadowed"] = int(lights["shadowed"]) + 1
					if l is OmniLight3D:
						lights["omni_shadowed"] = int(lights["omni_shadowed"]) + 1
				continue
			if n is Decal:
				decals += 1
				continue
			if n is GPUParticles3D:
				particles["gpu"] = int(particles["gpu"]) + 1
				particles["amount"] = int(particles["amount"]) + (n as GPUParticles3D).amount
				continue
			if n is CPUParticles3D:
				particles["cpu"] = int(particles["cpu"]) + 1
				particles["amount"] = int(particles["amount"]) + (n as CPUParticles3D).amount
				continue
			if not (n is GeometryInstance3D):
				continue
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var mesh: Mesh = null
			var inst := 1
			var aabb := AABB()
			var is_mm := false
			if gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
			elif gi is MultiMeshInstance3D:
				var mm := (gi as MultiMeshInstance3D).multimesh
				if mm == null:
					continue
				mesh = mm.mesh
				inst = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				is_mm = true
			if mesh == null:
				continue
			aabb = gi.global_transform * gi.get_aabb()
			var info := mesh_info(mesh)
			var key := _key(gi, mesh)
			if not _labels.has(mesh.get_instance_id()) and (mesh.resource_path == "" or mesh.resource_path.contains("::")):
				key += " [%d tris]" % int(info["tris"])
			if is_mm:
				key = "MM " + key
			var shadow := gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var r: Dictionary = rows.get(key, {"key": key, "nodes": 0, "instances": 0, "tris_each": info["tris"], "tris_total": 0,
				"lods": info["lods"], "shadow": shadow, "mats": info["mats"], "max_extent": 0.0, "vis_end": gi.visibility_range_end,
				"multimesh": is_mm, "surfaces": info["surfaces"]})
			r["nodes"] = int(r["nodes"]) + 1
			r["instances"] = int(r["instances"]) + inst
			r["tris_total"] = int(r["tris_total"]) + int(info["tris"]) * inst
			var ext := maxf(aabb.size.x, aabb.size.z)
			r["max_extent"] = maxf(float(r["max_extent"]), ext)
			rows[key] = r
			totals["geom"] = int(totals["geom"]) + 1
			totals["instances"] = int(totals["instances"]) + inst
			totals["tris_lod0"] = int(totals["tris_lod0"]) + int(info["tris"]) * inst
			if shadow:
				totals["tris_shadow_lod0"] = int(totals["tris_shadow_lod0"]) + int(info["tris"]) * inst
			if int(info["lods"]) <= 0 and int(info["tris"]) >= 2000:
				totals["no_lod_tris"] = int(totals["no_lod_tris"]) + int(info["tris"]) * inst
			if is_mm and ext > 70.0 and int(info["tris"]) * inst > 50000:
				big_mm.append({"key": key, "extent": snappedf(ext, 0.1), "instances": inst, "tris_each": info["tris"], "lods": info["lods"], "shadow": shadow})
	var list := rows.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tris_total"]) > int(b["tris_total"]))
	var out := {"zone": zone, "load_ms": load_ms, "totals": totals, "lights": lights, "particles": particles, "decals": decals,
		"unculled_multimeshes": big_mm, "rows": list}
	var f := FileAccess.open(out_dir.path_join(zone + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("[CENSUS] %s: load %d ms, %d nodes, %d geometry, %d instances, %s tris LOD0 (%s shadow casting), %s in meshes with no LOD" % [
		zone, load_ms, totals["nodes"], totals["geom"], totals["instances"], _m(totals["tris_lod0"]), _m(totals["tris_shadow_lod0"]), _m(totals["no_lod_tris"])])
	print("[CENSUS] %s: lights omni %d spot %d dir %d, shadowed %d (omni %d); particles gpu %d cpu %d (%d max); decals %d" % [
		zone, lights["omni"], lights["spot"], lights["dir"], lights["shadowed"], lights["omni_shadowed"], particles["gpu"], particles["cpu"], particles["amount"], decals])
	for b in big_mm:
		print("[CENSUS] %s: UNCULLED multimesh %s: %.0f m wide, %d x %d tris, lods %d, shadow %s" % [zone, b["key"], b["extent"], b["instances"], b["tris_each"], b["lods"], b["shadow"]])
	for i in mini(14, list.size()):
		var r: Dictionary = list[i]
		print("[CENSUS] %s:   %8s tris  %4d x %6d  lods %d  %s%s  %s" % [zone, _m(r["tris_total"]), r["instances"], r["tris_each"], r["lods"],
			"shadow " if r["shadow"] else "", "MM" if r["multimesh"] else "", r["key"]])

static func _m(v) -> String:
	var x := float(v)
	if x >= 1e6:
		return "%.2fM" % (x / 1e6)
	if x >= 1e3:
		return "%.0fk" % (x / 1e3)
	return str(int(x))
