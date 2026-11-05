extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene: PackedScene = load(PlagueExperimentFx.CREATURE_GLB)
	var node := scene.instantiate()
	var animations: Array = []
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		for library in ap.get_animation_library_list():
			for name in ap.get_animation_library(library).get_animation_list():
				animations.append(ap.get_animation_library(library).get_animation(name))
	for pass_i in 5:
		var start := Time.get_ticks_usec()
		for a in animations: ForestCamp._pin_root(a)
		print("[ANIMATION PREP] pass=", pass_i, " animations=", animations.size(), " us=", Time.get_ticks_usec() - start)
	node.free()
	quit()
