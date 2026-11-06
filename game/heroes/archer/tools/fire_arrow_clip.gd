extends SceneTree
## Proof-of-quality recording of an Archer skill (docs/systems/effects.md, the quality bar): the ranger staged on the moor
## with three monsters in a line ahead of him, the skill fired standing and then while walking, every frame
## saved from the game camera and from a close camera that follows the arrow. Needs a display (xvfb) and
## --fixed-fps 30 so the frames are 1/30 s apart whatever the software renderer takes:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 30 -s game/heroes/archer/tools/fire_arrow_clip.gd -- <outdir> [skill=pierce] [game|close|both] [fps=30] [quality=1]
## Writes <outdir>/<skill>_<view>_<stand|walk>_NNN.png. The frames are what the running game drew
## (get_viewport().get_texture().get_image()), never composited.
var g
const SECS := {"pierce": 3.6, "volley": 3.2, "snare": 2.4, "beast": 2.4}
var modes := ["stand", "walk"]

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _foe(p: Vector3) -> Node3D:
	var e = g.spawn_enemy("zombie", g.world.free_spot_near(p, 0.6), 6)
	e.max_life = 4000.0
	e.life = 4000.0
	e.aggro = false
	e.scripted = 99.0       # stands there for the camera
	return e

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var sk: String = args[1] if args.size() > 1 else "pierce"
	var view: String = args[2] if args.size() > 2 else "both"
	var fps: int = int(args[3]) if args.size() > 3 else 30
	var qual: int = int(args[4]) if args.size() > 4 else 1
	if args.size() > 5:
		modes = [args[5]]       # stand or walk alone (a quick look)
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	g.ui.close_all()
	g.difficulty = 0
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	var h = g.hero
	h.level = 14
	h.recalc()
	g.test_immortal = true
	g.test_allskills = true
	g.ui.visible = false
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
	# software GL: a low preset, no shadows, no multisampling; the glow stays (the effects are HDR)
	g.apply_quality(qual)
	g.sun.shadow_enabled = false
	if OS.get_cmdline_user_args().has("--nofog"):
		g.env.fog_enabled = false
		g.env.volumetric_fog_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	g.zoom = 1.22      # a touch further out than the game's default, so the whole flight (18 m) stays in frame
	for e in g.enemies_near(h.global_position, 80.0):
		e.queue_free()
	for b in h.beasts:
		b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 9999.0
	await process_frame
	var close := Camera3D.new()
	close.fov = 34
	get_root().add_child(close)
	var views: Array = ["game", "close"] if view == "both" else [view]
	# the shot goes down the road from the "road" spawn (its direction there), clear of the trees
	var poly: PackedVector2Array = g.world.path_poly
	var i0 := int(poly.size() * 0.22)
	var rd: Vector2 = (poly[mini(i0 + 2, poly.size() - 1)] - poly[maxi(i0 - 2, 0)]).normalized()
	var fwd := Vector3(rd.x, 0, rd.y)
	var secs: float = float(SECS.get(sk, 2.6))
	for v in views:
		for mode in modes:
			var home: Vector3 = g.world.spawns["road"]
			home = Vector3(home.x, g.world.height_at(home.x, home.z), home.z)
			h.global_position = home
			h.direct_dir = Vector3.ZERO
			h.moving = false
			h.path = PackedVector3Array()
			h._face(fwd)
			for e in g.enemies_near(home, 80.0):
				e.queue_free()
			await process_frame
			var foes := []
			for k in 3:
				foes.append(_foe(home + fwd * (5.5 + k * 2.6) + Vector3((k - 1) * 0.5, 0, 0)))
			await wait(0.7)
			for k in h.cds.keys():
				h.cds[k] = 0.0
			h.mana = h.max_mana
			var aim: Vector3 = home + fwd * 12.0
			var frames: int = int(secs * fps)
			var cast_at := int(0.4 * fps)
			for f in frames:
				if mode == "walk":
					# he walks on the line of the shot, loosing as he goes (the aimed walk)
					h.direct_dir = fwd if f < frames - int(0.4 * fps) else Vector3.ZERO
				if f == cast_at:
					h.use_skill(sk, h.skill_aim(sk, aim))
				if v == "close":
					close.current = true
					# the camera follows the arrow in flight, else looks over his shoulder at the line
					var focus: Vector3 = h.global_position + Vector3(0, 1.2, 0) + fwd * 2.2
					if not h.arrows.is_empty():
						var n = h.arrows[0]["node"]
						if is_instance_valid(n):
							focus = n.global_position
					# from his right, a little ahead and above, looking across the line of the shot
					var cp := focus + Vector3(4.2, 2.1, -1.4)
					close.global_transform = Transform3D(Basis(), cp).looking_at(focus + Vector3(0, -0.15, -0.8), Vector3.UP)
				else:
					g.cam.current = true
				await process_frame
				await RenderingServer.frame_post_draw
				get_root().get_texture().get_image().save_png("%s/%s_%s_%s_%03d.png" % [out, sk, v, mode, f])
			h.direct_dir = Vector3.ZERO
			await wait(0.5)
	quit()
