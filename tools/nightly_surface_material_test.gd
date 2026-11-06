extends SceneTree
## Reproduces Godot #85817 with cached meshes, mixed overrides and sibling deletion.
## check_functional_log.py / CI must reject renderer errors even when assertions pass.
var checks := 0
var failures := 0
var retained: Array[Mesh] = []
class CustomMesh extends SurfaceMaterials:
	var marker := 42
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func make_pair(parent: Node3D, custom: bool) -> Array:
	var shared := StandardMaterial3D.new()
	var surface := StandardMaterial3D.new()
	var refs := [weakref(shared), weakref(surface)]
	for i in 2:
		var mi := CustomMesh.new() if custom else MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		retained.append(mi.mesh)
		mi.material_override = shared
		if i == 1:
			SurfaceMaterials.assign(mi, 0, surface)
			check(mi.get_surface_override_material(0) == surface, "surface identity preserved")
			check(mi.material_override == shared, "whole-instance override preserved")
			check(not custom or mi.marker == 42, "custom mesh behavior preserved")
		parent.add_child(mi)
	return refs
func run() -> void:
	for custom in [false, true]:
		for immediate in [false, true]:
			for repeat in 3:
				var parent := Node3D.new()
				root.add_child(parent)
				var refs := make_pair(parent, custom)
				await process_frame
				var mi := parent.get_child(1) as MeshInstance3D
				parent.remove_child(mi)
				parent.add_child(mi)
				check(mi.get_surface_override_material(0) != null, "reparent retains live material")
				if immediate: parent.free()
				else: parent.queue_free()
				for frame in 3: await process_frame
				for ref in refs: check(ref.get_ref() == null, "materials released despite cached mesh")
	check(retained.size() == 24, "all shared meshes survive instance deletion")
	retained.clear()
	for frame in 3: await process_frame
	print("[SURFACE] %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
