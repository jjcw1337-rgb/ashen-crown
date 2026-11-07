extends SceneTree
## Screenshots of sailing through the game's own camera (boat_ride.gd, Game._sail_camera):
##   godot --path . -s tools/sail_shots.gd -- outprefix [quality] [isle] [boat id]
## Casting off from the pier, under way, halfway across, coming in to the island's jetty, alongside it
## with the landing prompt. The boat sails with her own physics; the clock is stepped so it's repeatable.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func shot(out: String, name: String) -> void:
	for i in 6:
		await process_frame
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("saved ", name)
func sail(b: BoatRide, to: Vector2, secs: float, stop_at := 12.0) -> void:
	var t := 0.0
	stop_at *= b.kl
	while t < secs:
		var d := Vector2(b.global_position.x, b.global_position.z).distance_to(to)
		b.drive = {"throttle": 0, "steer": 0.0, "stop": d < stop_at, "point": Vector3(to.x, 0, to.y) if d >= stop_at else null}
		b._sail(1.0 / 30.0)
		t += 1.0 / 30.0
	b._float(0.1)
	b._place_hero(g.hero)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var q := int(args[1]) if args.size() > 1 else 2
	var id: String = args[2] if args.size() > 2 else "lost"
	var boat_id: String = args[3] if args.size() > 3 else "gull"
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.set_quality(q)
	g.ui.close_all()
	g.hero.boats = [boat_id]
	g.hero.sailed = true
	await g.load_zone(0, "coast", "dock")
	var b: BoatRide = g.boat
	g.hero.global_position = Vector3(1.5, 1.05, -0.8)
	await shot(out, "1_moored")
	g._interact(b.inter)
	var isle := Isles.get_isle(id)
	var m: Vector4 = g.isle_mooring(isle, Vector2.ZERO, true)
	var to := Vector2(m.x, m.z)
	sail(b, to, 3.0)
	await shot(out, "2_casting_off")
	sail(b, to, 7.0)
	await shot(out, "3_under_way")
	sail(b, to, 6.0)
	await shot(out, "4_halfway")
	sail(b, to, 6.0)
	await shot(out, "5_coming_in")
	sail(b, to, 6.0)
	await shot(out, "6_alongside")
	quit()
