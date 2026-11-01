extends SceneTree
## Every kind of fire side by side on the moor at dusk, the old particle fire (Props.fire_legacy) or the new
## simulated fire (FireFx), with the hero and a monster standing in their light. Needs a display (xvfb) and
## --fixed-fps 30:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s tools/fire_compare.gd -- <outdir> [new|old] [close|wide|game] [frames]
## Writes <outdir>/<mode>_<view>_NNN.png. Kinds left to right: torch, brazier, campfire, bonfire, ground, building,
## magic, and a burning monster.
var g
const KINDS := ["torch", "brazier", "campfire", "bonfire", "ground", "building", "magic"]

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode: String = args[1] if args.size() > 1 else "new"
	var view: String = args[2] if args.size() > 2 else "wide"
	var frames: int = int(args[3]) if args.size() > 3 else 45
	Props.use_legacy_fire = mode == "old"
	InfernalFx.force_tier = 2
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	g.test_immortal = true
	g.ui.visible = false
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
	g.apply_quality(0)
	g.sun.shadow_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	# dusk: the fires should carry the light
	g.sun.light_energy *= 0.25
	g.env.ambient_light_energy *= 0.35
	for e in g.enemies_near(g.hero.global_position, 80.0):
		e.queue_free()
	await process_frame
	var h = g.hero
	var home: Vector3 = h.global_position
	var row := home + Vector3(-7.2, 0, -4.0)
	var fx: Node3D = g.world.fx_root
	for i in KINDS.size():
		var p := row + Vector3(i * 2.4, 0, 0)
		p.y = g.world.height_at(p.x, p.z)
		var kind: String = KINDS[i]
		var size: float = {"torch": 0.6, "brazier": 1.0, "campfire": 1.1, "bonfire": 1.6, "ground": 0.9, "building": 1.3, "magic": 0.6}[kind]
		var lift: float = {"torch": 1.7, "brazier": 0.95, "magic": 1.1}.get(kind, 0.0)
		var col := Color(1.0, 0.5, 0.18) if kind != "magic" else Color(1.0, 0.25, 0.08)
		if kind == "torch":
			var post := MeshInstance3D.new()
			post.mesh = Geo.cyl(0.05, 0.06, 1.7, 8)
			post.material_override = Mats.mat(Color(0.25, 0.17, 0.1), 0.9)
			fx.add_child(post)
			post.global_position = p + Vector3(0, 0.85, 0)
		elif kind == "brazier" or kind == "magic":
			var bowl := MeshInstance3D.new()
			bowl.mesh = Geo.cyl(0.32, 0.18, lift, 10)
			bowl.material_override = Mats.mat(Color(0.12, 0.11, 0.1), 0.5, 0.6)
			fx.add_child(bowl)
			bowl.global_position = p + Vector3(0, lift * 0.5, 0)
		var holder := Node3D.new()
		fx.add_child(holder)
		holder.global_position = p
		Props.fire(holder, Vector3(0, lift, 0), size, col, true, false, true, kind)
	# a monster burning (the old ignite or the new "burning" fire)
	var zp: Vector3 = row + Vector3(KINDS.size() * 2.4, 0, 0)
	var z = g.spawn_enemy("zombie", g.world.free_spot_near(zp, 0.5), 10)
	z.aggro = false
	z.scripted = 999.0
	z.max_life = 99999.0
	z.life = 99999.0
	await process_frame
	DemonFx.ignite(fx, z)
	# the hero stands among them, lit
	h.global_position = row + Vector3(3.6 * 2.4 * 0.5, 0, 1.4)
	h.global_position.y = g.world.height_at(h.global_position.x, h.global_position.z)
	h._face(Vector3(0, 0, 1))
	var cam := Camera3D.new()
	get_root().add_child(cam)
	await wait(1.2)
	var mid: Vector3 = row + Vector3((KINDS.size()) * 2.4 * 0.5, 0, 0)
	for f in frames:
		if f % 40 == 0:
			DemonFx.ignite(fx, z)      # keep it alight
		match view:
			"close":
				cam.current = true
				cam.fov = 40
				# walk along the row, a fire or two at a time
				var t := float(f) / maxf(frames - 1, 1)
				var c: Vector3 = row + Vector3(lerpf(0.0, (KINDS.size()) * 2.4, t), 1.2, 0)
				cam.global_transform = Transform3D(Basis(), c + Vector3(0, 0.9, 4.6)).looking_at(c)
			"wide":
				cam.current = true
				cam.fov = 50
				cam.global_transform = Transform3D(Basis(), mid + Vector3(0, 4.0, 12.5)).looking_at(mid + Vector3(0, 0.9, 0))
			_:
				g.cam.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out, mode, view, f])
	quit()
