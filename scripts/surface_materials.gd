class_name SurfaceMaterials
extends MeshInstance3D
## Safe per-instance surface overrides for shared/cached meshes (Godot #85817).
## Godot may flush dirty instances while deleting a sibling. Drop the renderer's
## references BEFORE MeshInstance3D releases these materials in its destructor.
## No mesh duplication, global material pins, or change to living instances.

static func assign(target: MeshInstance3D, surface: int, material: Material) -> void:
	if not target is SurfaceMaterials:
		if target.get_script() != null:
			push_error("Surface override owner must inherit SurfaceMaterials: " + str(target.name))
			return
		target.set_script(SurfaceMaterials)
	target.set_surface_override_material(surface, material)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for surface in get_surface_override_material_count():
			set_surface_override_material(surface, null)
