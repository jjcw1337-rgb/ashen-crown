extends SceneTree
## Screenshots of the Hollow Crypt (Battlegrounds.build, zone "bg") from the game camera: a spawn room, a corridor,
## a treasure room's chest, a portal room (its Extraction Portal shown open), the great hall from its chokepoint
## and from its middle, then a high overview. Builds the zone alone (no server): the layout is the same one the
## dedicated server builds, so the stills show what a raider sees. Needs a display.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 1152x648 --path . -s tools/crypt_shots.gd -- outdir [monsters] [only name,name]
## `monsters` keeps the monsters (they come for the hero); `only` takes a subset of the shot names.
var g
var out := ""
var only: Array = []

func _initialize():
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var oi := a.find("only")
	if oi >= 0 and oi + 1 < a.size():
		only = a[oi + 1].split(",")
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _snap(name: String, frames := 8) -> void:
	if not only.is_empty() and not only.has(name):
		return
	for f in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("[C] ", name)

## The twelve rooms of Battlegrounds.build in its cell order, and the hall (floor_rects[12]).
func _rooms() -> Array:
	return g.world.floor_rects.slice(0, 12)

func _portal_rooms() -> Array:
	var rs := _rooms()
	var out_r := []
	for p in Battlegrounds.portal_list(g.world):
		for r in rs:
			if (r as Rect2).has_point(Vector2(p.global_position.x, p.global_position.z)):
				out_r.append(r)
	return out_r

func _place(p: Vector3) -> void:
	p = g.world.free_spot_near(p, 0.4)
	p.y = g.world.height_at(p.x, p.z)
	g.hero.global_position = p
	g.hero.target = null
	g.hero.moving = false
	g.cam_target = p
	g.cam_pivot.position = p

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.test_immortal = true
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	if not OS.get_cmdline_user_args().has("monsters"):
		for e in g.world.enemies_root.get_children():
			e.queue_free()
	for p in Battlegrounds.portal_list(g.world):
		p.data["open"] = true
		var m = p.get_node_or_null("Model")
		if m:
			m.visible = true
	# shaders compile on the first frames: let the scene settle before the first still
	for f in 20:
		await process_frame
	var rooms := _rooms()
	var hall: Rect2 = g.world.floor_rects[12]
	var r0: Rect2 = rooms[0]
	_place(Vector3(r0.get_center().x, 0, r0.get_center().y))
	await _snap("spawn")
	var r1: Rect2 = rooms[1]
	var mid := (r0.get_center() + r1.get_center()) * 0.5
	_place(Vector3(mid.x, 0, mid.y))
	await _snap("corridor")
	var prs := _portal_rooms()
	if not prs.is_empty():
		var pr: Rect2 = prs[0]
		_place(Vector3(pr.get_center().x, 0, pr.get_center().y + 2.5))
		await _snap("portal")
	# a treasure room: a side room that holds a chest
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == "chest" and not hall.has_point(Vector2(t.global_position.x, t.global_position.z)):
			_place(t.global_position + Vector3(0, 0, 2.2))
			await _snap("treasure")
			break
	# the hall from the north chokepoint, then from its middle
	_place(Vector3(hall.get_center().x, 0, hall.position.y + 2.0))
	await _snap("hall_edge")
	_place(Vector3(hall.get_center().x, 0, hall.get_center().y))
	await _snap("hall")
	if only.is_empty() or only.has("overview"):
		g.ui.root.visible = false
		var cam: Camera3D = g.get_viewport().get_camera_3d()
		g.set_process(false)
		cam.global_transform = Transform3D(Basis(), Vector3(0, 95, 70)).looking_at(Vector3(0, 0, -2))
		cam.fov = 55
		await _snap("overview", 4)
	quit()
