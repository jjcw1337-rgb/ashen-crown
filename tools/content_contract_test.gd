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
		# Attack and run-proc events are presentation families, not selectable skills.
		var allowed := {"attack": true, "run": true}
		var represented := {}
		for event in SkillWarmData.EVENTS.get(cls, []):
			represented[str(event.get("s", ""))] = true
		for skill in Data.skills_for(cls) + Data.run_skills_for(cls) + Data.shared_skills():
			check(represented.has(str(skill.id)), "Skill missing captured preparation event: %s/%s" % [cls, skill.id])
			allowed[str(skill.id)] = true
		for skill_id in represented:
			check(allowed.has(skill_id), "Retired or unknown preparation event: %s/%s" % [cls, skill_id])
	# A cast marker alone does not prepare these skills' impact or delayed burst.
	for skill_id in ["k_whirl", "k_aegis", "k_judgment", "k_rites"]:
		for phase in (["impact", "burst"] if skill_id == "k_aegis" else ["impact"]):
			check(SkillWarmData.EVENTS.get("knight", []).any(func(event): return event.get("s") == skill_id and event.get("e") == phase),
				"Knight preparation missing phase: %s/%s" % [skill_id, phase])
	var solo: Array = catalog.combat(["knight"])
	check(not solo.any(func(p): return str(p).contains("/plague/") or str(p).contains("/arrows/")), "Solo knight must not acquire other classes\' families")
	check(catalog.combat(["archer"]).has(SpiritBeast.WOLF_GLB), "Archer summon must be declared")
	for path in catalog.combat():
		check(not str(path).begins_with("res://assets/models/") or str(path).get_extension() in ["glb", "tscn", "tres"], "Model families must not duplicate imported texture roots: " + str(path))
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
