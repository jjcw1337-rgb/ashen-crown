extends SceneTree
## Screenshots of the islands' Meshy landmarks (assets/models/isles/, Isles.prop) in their zones:
##   godot --path . -s tools/isle_props_shot.gd -- outprefix [quality] [isle]
## Each landmark from the game camera with the hero beside it, then from a wider, higher view.
var g
var cam: Camera3D
const SPOTS := [["ruins", "poi_temple"], ["lost", "poi_monolith"], ["bleak", "poi_wreck"], ["merchant", "poi_yard"], ["merchant", "poi_beacon"]]
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(out: String, name: String, frames := 10) -> void:
	for i in frames:
		await process_frame
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)
func look(from: Vector3, to: Vector3, fov := 50.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		get_root().add_child(cam)
	cam.far = 1600.0
	cam.near = 0.3
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.current = true
func game_cam() -> void:
	if cam:
		cam.current = false
	g.cam.current = true
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var q := int(args[1]) if args.size() > 1 else 2
	var only: String = args[2] if args.size() > 2 else ""
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.set_quality(q)
	g.ui.close_all()
	for s in SPOTS:
		if only != "" and only != s[0]:
			continue
		if g.cur_zone != Isles.zone_of(s[0]):
			await g.load_zone(0, Isles.zone_of(s[0]), "start")
		g.ui.visible = false
		var p: Vector3 = g.world.spawns[s[1]]
		g.hero.global_position = p
		game_cam()
		await shot(out, "%s_%s" % [s[0], s[1]], 14)
		look(p + Vector3(22.0, 14.0, 22.0), p + Vector3(0, 5.0, 0))
		await shot(out, "%s_%s_wide" % [s[0], s[1]])
	quit()
