extends SceneTree
func _initialize() -> void:
	for path in ["res://tools/mp_test.gd", "res://tools/plague_mp_test.gd", "res://tools/title_test.gd", "res://tools/vendor_test.gd", "res://tools/nightly_net_drop_test.gd", "res://tools/archer_sweep_test.gd", "res://tools/camp_reach_test.gd", "res://scripts/warlock_hex.gd", "res://scripts/warlock_harrow_fx.gd", "res://scripts/codex.gd", "res://scripts/codex_book.gd", "res://tools/bg_journey_test.gd", "res://scripts/forest_life.gd", "res://scripts/knight_skills.gd", "res://scripts/knight_fx.gd", "res://tools/skill_warm_capture.gd", "res://tools/run_talents_test.gd", "res://scripts/run_talents.gd", "res://tools/arena_survivor_test.gd", "res://tools/sandbox_lobby_test.gd", "res://tools/bg_test.gd", "res://tools/bg_pvp_test.gd", "res://scripts/forest_camp.gd", "res://tools/content_world_test.gd", "res://scripts/terrain_build.gd", "res://scripts/surface_materials.gd", "res://scripts/res_cache.gd", "res://scripts/content_catalog.gd", "res://scripts/grass.gd", "res://scripts/game.gd", "res://scripts/pvp_stress.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			push_error("Cannot instantiate " + path)
			quit(1)
			return
	print("[PARSE] scripts load")
	quit()
