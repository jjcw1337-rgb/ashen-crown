extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func snapshot(w: World) -> Dictionary:
	var grass := {}
	for node in w.find_children("Grass_*", "MultiMeshInstance3D", true, false):
		grass[str(node.name)] = hash((node as MultiMeshInstance3D).multimesh.buffer)
	var inter: Array = []
	for item in w.interactables:
		inter.append([item.kind, item.position])
	return {"grass": grass, "spawns": w.enemy_spawns.duplicate(true), "obstacles": w.obstacles.duplicate(true), "inter": inter}
func build(scheduled: bool, zone: String) -> Dictionary:
	seed(420042)
	var w := World.new()
	w.process_mode = Node.PROCESS_MODE_DISABLED
	w.run = 0
	w.oak_forest = true
	w.fort = true
	w.living_grass = true
	w.scheduled_build = scheduled
	World.detail = 1
	root.add_child(w)
	await w.build(0, zone, 4207)
	var result := snapshot(w)
	print("[WORLD] scheduled=", scheduled, " zone=", zone, " grass nodes=", result.grass.size(), " ", w.construction_metrics)
	w.queue_free()
	for i in 10: await process_frame
	return result
func run() -> void:
	Mats.ensure_globals()
	var zone := "wild"
	var args := OS.get_cmdline_user_args()
	if args.has("--zone"): zone = args[args.find("--zone") + 1]
	var a := await build(false, zone)
	var b := await build(true, zone)
	var same := a == b
	for key in a:
		print("[PARITY] ", key, "=", a[key] == b[key])
	quit(0 if same else 1)
