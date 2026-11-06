extends SceneTree
## Frames of the Warlock (the jungle void spirit) and every skill of hers in the game, for judging the look:
## the body close up (idle, floating, casting), then each skill cast at a pack of zombies on the moor, a few frames
## each. Needs a display (on a Mac it just opens a window).
##   godot --path . --fixed-fps 30 --resolution 1280x720 -s tools/warlock_showcase.gd -- <out_dir> [skill,skill|all] [quality 0-3] [zoom]
var g
var out := ""
var shots := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

## The middle of the screen (she and the pack), at full resolution.
func snap(nm: String) -> void:
	await process_frame
	var im := get_root().get_texture().get_image()
	var w := im.get_width()
	var hh := im.get_height()
	im = im.get_region(Rect2i(int(w * 0.22), int(hh * 0.02), int(w * 0.56), int(hh * 0.8)))
	im.save_png("%s/%s.png" % [out, nm])
	shots += 1

func frames(nm: String, n: int, gap: float) -> void:
	for i in n:
		await create_timer(gap).timeout
		await snap("%s_%d" % [nm, i])

func pack(h, n: int, dist := 6.0) -> Array:
	# (east of her, in the camera's view)
	for e in g.enemies_near(h.global_position, 40.0):
		e.queue_free()
	await process_frame
	var out_e := []
	for i in n:
		var a := -0.9 + 1.8 * float(i) / maxf(1.0, n - 1.0)
		var p: Vector3 = h.global_position + Vector3(sin(a) * dist * 0.6, 0, -cos(a) * dist)
		var e = g.spawn_enemy("zombie", g.world.free_spot_near(p, 0.5), 3)
		e.max_life = 100000.0
		e.life = e.max_life
		e.aggro = false
		out_e.append(e)
	await create_timer(0.3).timeout
	return out_e

func cast(h, id: String, at: Vector3) -> void:
	h.mana = h.max_mana
	h.cds[id] = 0.0
	h.use_skill(id, at)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "/tmp/warlock_show"
	var only: String = a[1] if a.size() > 1 else "all"
	var q := int(a[2]) if a.size() > 2 else 2
	var zoom := float(a[3]) if a.size() > 3 else 0.5
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "warlock")
	g.apply_quality(q)
	g.ui.close_all()
	var h = g.hero
	h.level = 20
	h.recalc()
	g.test_immortal = true
	g.test_allskills = true
	await g.travel(0, "wild", "start")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui._set_hud(false)
	var home: Vector3 = h.global_position
	# the body
	if only == "all" or only.contains("body"):
		g.zoom = 0.35
		h._face(Vector3(0, 0, 1))
		await create_timer(1.0).timeout
		await snap("body_idle")
		h.cmd_move(h.global_position + Vector3(6, 0, 4))
		await frames("body_float", 3, 0.25)
		await create_timer(1.0).timeout
	g.zoom = zoom
	var ids: Array = ["w_corruption", "w_unending", "w_festering", "w_leeching", "w_reckoning", "w_malediction",
		"w_terrify", "w_effigy", "w_darkwind", "w_crowstorm", "w_leechbolt", "w_harvest", "w_soulfeast", "drain", "blight", "shackles", "covenant"]
	for id in ids:
		if only != "all" and not only.split(",").has(id):
			continue
		h.global_position = home
		h.path = PackedVector3Array()
		h.moving = false
		h._face(Vector3(0, 0, -1))
		var es: Array = await pack(h, 5, 6.0 if id != "w_effigy" else 9.0)
		var target: Vector3 = es[2].global_position
		if id == "w_effigy":
			target = h.global_position + (target - h.global_position) * 0.75
		if id == "w_reckoning" or id == "w_malediction":
			for c in ["w_corruption", "w_unending", "w_leeching"]:
				cast(h, c, target)
				await create_timer(0.7).timeout
		cast(h, id, target)
		await frames(id, 5 if id in ["w_crowstorm", "w_soulfeast", "w_darkwind", "drain"] else 4, 0.22)
		if id == "drain":
			WarlockSkills.end_drain(h)
		await create_timer(0.8).timeout
	# a shield
	h.wl["shield"] = 0.0
	h.tfx["overheal_shield"] = 20.0
	WarlockHex.heal(h, h.max_life * 2.0)
	await create_timer(0.4).timeout
	await snap("shield")
	print("[SHOW] %d frames in %s" % [shots, out])
	quit()
