extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var catalog = load("res://scripts/content_catalog.gd")
	var paths: Array = catalog.combat()
	print("[CATALOG] paths ", paths.size())
	ResCache.prepare("test", paths)
	var status := await ResCache.wait_ready(self, "test", 180.0)
	print("[CATALOG] ", status, " / ", ResCache.metrics())
	ResCache.release("test")
	await process_frame
	quit(0 if status.ready else 1)
