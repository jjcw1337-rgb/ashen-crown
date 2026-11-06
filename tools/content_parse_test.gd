extends SceneTree
func _initialize() -> void:
	for path in ["res://scripts/surface_materials.gd", "res://scripts/res_cache.gd", "res://scripts/content_catalog.gd", "res://scripts/grass.gd", "res://scripts/game.gd", "res://scripts/pvp_stress.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			push_error("Cannot instantiate " + path)
			quit(1)
			return
	print("[PARSE] scripts load")
	quit()
