extends SceneTree
## Frames of the Plague Doctor's six skills in a row, for the gameplay video. Needs a display (xvfb) and
## --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s tools/plague_kit_clip.gd -- <outdir> [skills,comma,separated|all] [view game|close] [quality]
## Each skill gets its own fresh pack and its own seconds (`PLAN`); frames are numbered straight through
## (<outdir>/f_NNNN.png) and <outdir>/segments.txt lists where each skill starts, for titles.
var g

## skill -> [seconds, foes, foes fight back]
const PLAN := {
	"toxic": [4.0, 4, false],
	"swarm": [5.5, 4, true],
	"bloom": [5.5, 3, false],
	"fog": [4.0, 3, true],
	"transfusion": [4.0, 4, true],
	"experiment": [10.5, 5, true],
}

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "all"
	var view: String = args[2] if args.size() > 2 else "game"
	var quality: int = int(args[3]) if args.size() > 3 else 0
	var skills: Array = PLAN.keys() if which == "all" else Array(which.split(","))
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "plague")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	var h = g.hero
	h.level = 24
	h.recalc()
	g.test_immortal = true
	g.zoom = 0.66
	g.ui.visible = false
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.4)
	g.apply_quality(quality)
	if quality == 0:
		g.sun.shadow_enabled = false
		get_root().msaa_3d = Viewport.MSAA_DISABLED
	var cam := Camera3D.new()
	cam.fov = 40
	cam.near = 3.5      # the close view sits ~9.5 m off: cut the bushes between it and him
	get_root().add_child(cam)
	var seg := FileAccess.open(out + "/segments.txt", FileAccess.WRITE)
	var fno := 0
	var home: Vector3 = h.global_position
	for sk in skills:
		var plan: Array = PLAN[sk]
		for e in g.enemies_near(home, 80.0):
			e.queue_free()
		if h.pd != null:
			h.pd.clear()
		await process_frame
		h.global_position = home
		h.life = h.max_life
		h.mana = h.max_mana
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h._face(Vector3(0, 0, -1))
		var foes := []
		var n: int = plan[1]
		var dist := 6.5 if sk != "transfusion" and sk != "fog" else 2.2
		for i in n:
			var a := -0.7 + 1.4 * float(i) / maxf(n - 1, 1)
			var p: Vector3 = home + Vector3(sin(a) * dist, 0, -cos(a) * dist) + Vector3(0, 0, -0.6 * (i % 2))
			p = g.world.free_spot_near(p, 0.5)
			var e = g.spawn_enemy("zombie" if i % 3 != 2 else "fallen", p, 24)
			e.max_life = 6000.0
			e.life = 6000.0
			if not bool(plan[2]):
				e.aggro = false
				e.scripted = 99.0
			foes.append(e)
		await wait(0.3)
		seg.store_line("%d %s" % [fno, sk])
		var frames: int = int(float(plan[0]) * 30.0)
		var center: Vector3 = home + Vector3(0, 0, -dist)
		for f in frames:
			var live := foes.filter(func(e): return is_instance_valid(e) and not e.dead)
			var aim: Vector3 = center
			if not live.is_empty():
				aim = live[(f / 40) % live.size()].global_position
			match sk:
				"toxic":
					if f == 6 or f == 62:
						_use(h, "toxic", aim)
				"swarm":
					if f == 6:
						_use(h, "swarm", center)
					if f == 80:
						_use(h, "swarm", center + Vector3(2.5, 0, 1.0))
				"bloom":
					if f == 6:
						_use(h, "bloom", center)
				"fog":
					if f == 8:
						_use(h, "fog", center)
				"transfusion":
					if f == 10:
						_use(h, "transfusion", h.global_position)
				"experiment":
					if f == 6:
						_use(h, "experiment", center + Vector3(0, 0, 1.0))
			if view == "close":
				cam.current = true
				var c: Vector3 = center.lerp(h.global_position, 0.4)
				cam.global_transform = Transform3D(Basis(), c + Vector3(6.5, 4.2, 5.5)).looking_at(c + Vector3(0, 0.6, 0))
			else:
				g.cam.current = true
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/f_%04d.png" % [out, fno])
			fno += 1
	seg.close()
	quit()

func _use(h, id: String, at: Vector3) -> void:
	h.cds[id] = 0.0
	h.mana = h.max_mana
	h.cursor = at
	h.use_skill(id, h.skill_aim(id, at))
