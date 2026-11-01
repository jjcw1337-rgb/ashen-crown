extends SceneTree
## Screenshots of the sea's finishing touches: the coast's sea chart on the corner map (at the pier and
## under sail), the big map, gulls and a leaping fish, the Bleak Isle's fog bank seen from the water, and
## its murky water and low fog ashore:
##   godot --path . -s tools/sea_life_shot.gd -- outprefix [quality] [fog]   (fog: only the fog bank, use quality 2+)
var g
var cam: Camera3D
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(out: String, name: String, frames := 8) -> void:
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
func sail(b: BoatRide, to: Vector2, secs: float) -> void:
	var t := 0.0
	while t < secs:
		b.drive = {"throttle": 0, "steer": 0.0, "stop": false, "point": Vector3(to.x, 0, to.y)}
		b._sail(1.0 / 30.0)
		t += 1.0 / 30.0
	b._float(0.1)
	b._place_hero(g.hero)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var q := int(args[1]) if args.size() > 1 else 2
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.set_quality(q)
	g.ui.close_all()
	g.hero.boats = ["gull"]
	g.hero.sailed = true
	await g.load_zone(0, "coast", "dock")
	if args.size() > 2 and args[2] == "fog":
		# only the Bleak Isle's fog bank from the water (Forward+ High: volumetric fog)
		var bi := Isles.get_isle("bleak")
		var mm: Vector4 = g.isle_mooring(bi, Vector2.ZERO, true)
		var cc := Isles.centre(bi)
		var fr := Vector2(mm.x, mm.z).lerp(Vector2.ZERO, 0.55)
		g.ui.visible = false
		look(Vector3(fr.x, 6.0, fr.y), Vector3(cc.x, 6.0, cc.y), 45.0)
		await shot(out, "fog_bank", 12)
		quit()
		return
	print("chart: ", g.ui.minimap.chart, " rect ", g.ui.minimap.map_rect)
	await shot(out, "1_pier_chart", 20)
	var b: BoatRide = g.boat
	g._interact(b.inter)
	var bleak := Isles.get_isle("bleak")
	var m: Vector4 = g.isle_mooring(bleak, Vector2.ZERO, true)
	sail(b, Vector2(m.x, m.z), 9.0)
	await shot(out, "2_sailing_chart", 40)
	g.ui.minimap.set_big(true)
	await shot(out, "2b_big_chart", 10)
	g.ui.minimap.set_big(false)
	# gulls round the boat and a fish leaping off the bow
	var birds: Birds = g.world.get_node("birds")
	print("gulls: sea %s, flocks %d" % [birds.sea, birds.flocks.size()])
	for f in birds.flocks:
		f["pos"] = b.global_position + Vector3(randf_range(-8, 8), 6.0, randf_range(-8, 8))
		for bd in f["birds"]:
			(bd as Node3D).position = f["pos"]
	# frames are slow in software GL: keep asking for a fish until one is in the air
	for i in 40:
		if birds.fishes.size() > 0:
			break
		birds._fish_t = 0.0
		await process_frame
	var fish := birds.fishes.size()
	var fp: Vector3 = b.global_position
	if fish > 0:
		fp = (birds.fishes[0]["node"] as Node3D).global_position
	print("fish leaping: ", fish)
	look(b.global_position + Vector3(9.0, 5.0, 9.0), (b.global_position + fp) * 0.5 + Vector3(0, 2.5, 0), 55.0)
	await shot(out, "3_gulls_fish", 2)
	game_cam()
	# the Bleak Isle's fog bank from the water
	var ce := Isles.centre(bleak)
	var from := Vector2(m.x, m.z).lerp(Vector2.ZERO, 0.55)
	look(Vector3(from.x, 6.0, from.y), Vector3(ce.x, 6.0, ce.y), 45.0)
	await shot(out, "4_bleak_from_sea", 12)
	# ashore: murky water and low fog
	await g.load_zone(0, "isle_bleak", "start")
	g.ui.visible = false
	game_cam()
	await shot(out, "5_bleak_jetty", 16)
	var ju: Vector2 = Isles.jetty_end(bleak) + Vector2(50.0, 20.0)
	var jp: Vector3 = Isles.at(g.world, bleak, Vector2.ZERO, ju)
	look(Vector3(jp.x, 8.0, jp.z), Vector3(0, 6.0, 0))
	await shot(out, "6_bleak_offshore", 12)
	quit()
