extends SceneTree
## Frames of a walk through the Hollow Crypt from the game camera: the hero sets off from a spawn room, down the
## corridor to the next room, through the treasure room's chokepoint into the great hall and up to its seal, the
## Extraction Portals shown open on the way. For a clip: run with --fixed-fps 30 and join the frames with ffmpeg.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1152x648 --fixed-fps 30 --path . -s tools/crypt_clip.gd -- outdir [frames]
##   ffmpeg -framerate 30 -i outdir/f_%04d.png -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 20 crypt.mp4
var g
var out := ""
var frames := 300

func _initialize():
	var a := OS.get_cmdline_user_args()
	out = a[0]
	if a.size() > 1 and a[1].is_valid_int():
		frames = int(a[1])
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	g._intro_skip = true          # (the trailer would play a minute first)
	_run()

## Holds the WASD keys that point the hero along `d` (eight ways), as a player would: the game reads the keys
## every frame (Game.wasd_dir) and overrode a direction set on the hero directly, so he never left the spawn room.
var _held := {}
func _steer(d: Vector3) -> void:
	var want := {}
	if d.length() > 0.1:
		if d.x > 0.38: want[KEY_D] = true
		elif d.x < -0.38: want[KEY_A] = true
		if d.z > 0.38: want[KEY_S] = true
		elif d.z < -0.38: want[KEY_W] = true
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var on := want.has(k)
		if on != _held.has(k):
			var e := InputEventKey.new()
			e.keycode = k
			e.physical_keycode = k
			e.pressed = on
			Input.parse_input_event(e)
			if on:
				_held[k] = true
			else:
				_held.erase(k)

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	# (the quality once the game has its environment: set before, it failed on a missing one)
	g.set_quality(int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("quality") + 1]) if OS.get_cmdline_user_args().has("quality") else 0)
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.test_immortal = true
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	for p in Battlegrounds.portal_list(g.world):
		p.data["open"] = true
		var m = p.get_node_or_null("Model")
		if m:
			m.visible = true
	Battlegrounds.sync_gates(g)
	# the route: the spawn room (0, 0), its neighbour (1, 0) east along the ring, then the north side's treasure room
	# (the one with the chest) and straight south through its chokepoint into the hall
	var rooms: Array = g.world.floor_rects.slice(0, 12)
	var hall: Rect2 = g.world.floor_rects[12]
	var r0: Rect2 = rooms[0]
	var r1: Rect2 = rooms[1]
	var r2: Rect2 = rooms[2]
	var treasure: Rect2 = r1
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == "chest":
			var q := Vector2(t.global_position.x, t.global_position.z)
			if r1.has_point(q):
				treasure = r1
			elif r2.has_point(q):
				treasure = r2
	var route: Array = [Vector3(r1.get_center().x, 0, r1.get_center().y)]
	if treasure == r2:
		route.append(Vector3(r2.get_center().x, 0, r2.get_center().y))
	route.append(Vector3(treasure.get_center().x, 0, treasure.end.y - 1.5))
	route.append(Vector3(treasure.get_center().x, 0, hall.position.y + 2.0))
	route.append(Vector3(hall.get_center().x, 0, hall.get_center().y + 3.0))
	var start := Vector3(r0.get_center().x, 0, r0.get_center().y)
	g.hero.global_position = g.world.free_spot_near(start, 0.4)
	g.cam_target = g.hero.global_position
	g.cam_pivot.position = g.hero.global_position
	for f in 20:
		await process_frame
	var leg := 0
	for f in frames:
		var want := Vector3.ZERO
		if leg < route.size():
			var goal: Vector3 = route[leg]
			var d: Vector3 = goal - g.hero.global_position
			d.y = 0.0
			if d.length() < 1.2:
				leg += 1
			else:
				want = d.normalized()
		_steer(want)
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/f_%04d.png" % [out, f])
	_steer(Vector3.ZERO)
	print("[CLIP] %d frames, reached leg %d of %d" % [frames, leg, route.size()])
	quit()
