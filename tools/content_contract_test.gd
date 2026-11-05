extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run() -> void:
	var catalog = load("res://scripts/content_catalog.gd")
	for cls in Data.CLASSES:
		check(catalog.CLASS_ROOTS.has(cls), "Class missing content declaration: " + cls)
		check(SkillWarmData.EVENTS.has(cls), "Class missing visual preparation recipe: " + cls)
	for path in catalog.combat():
		check(ResourceLoader.exists(path), "Missing combat dependency: " + path)
	for run_i in 3:
		for zone in ["town", "wild", "lair", "coast", "bg", "arena", "vigil", "sandbox"]:
			var paths: Array = catalog.zone(run_i, zone)
			check(not paths.is_empty(), "Missing zone dependencies: " + zone)
			for path in paths:
				check(ResourceLoader.exists(path), "Missing zone dependency: " + path)
	for isle in Isles.ISLANDS:
		check(not catalog.zone(0, Isles.zone_of(isle.id)).is_empty(), "Missing island dependencies")
	print("[CONTENT CONTRACT] %d checks / %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
