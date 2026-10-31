class_name Coast
extends RefCounted
## Act I: the Mournwater Coast, west of the camp: the mainland shore and its dock, the open sea and
## its five islands (isles.gd). Work in progress (test-ocean branch): the zone builder lands next.

static func build(w: World) -> void:
	w.bounds = Rect2(-40, -40, 80, 80)
	w.theme = {"name": "coast"}
	w.spawns["start"] = Vector3.ZERO
	w._rasterize()
	w._build_terrain(World.MOOR_TERRAIN)
