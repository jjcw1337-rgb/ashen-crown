extends SceneTree
## A quick look at an ArrowFx preset's projectile and trail without the game: it flies across a dark floor past
## a close camera, frames saved. Needs a display:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 --fixed-fps 30 \
##     -s game/heroes/archer/tools/arrow_fx_lab.gd -- <outdir> [kind=fire] [frames=30]
var out := ""
var fx_root: Node3D
var cam: Camera3D
var world: SceneTree
var AFx    # arrow_fx.gd loaded at run time (a static reference compiles it, and its Sfx, before the autoload exists)    # the module asks game.world.fx_root: here both are this script

func height_at(_x: float, _z: float) -> float:
	return 0.0

func _initialize():
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var kind: String = args[1] if args.size() > 1 else "fire"
	var frames: int = int(args[2]) if args.size() > 2 else 30
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.4, 0.38)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.environment = e
	root.add_child(env)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.2, 0.17)
	fm.roughness = 0.9
	floor.material_override = fm
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.4
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.5, 2.4, 3.6)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	cam.fov = 42
	world = self
	fx_root = Node3D.new()
	root.add_child(fx_root)
	_run(kind, frames)

func _run(kind: String, frames: int) -> void:
	var dir := Vector3(-1, 0, 0)
	AFx = load("res://scripts/arrow_fx.gd")
	var n: Node3D = AFx.projectile(kind, null)
	fx_root.add_child(n)
	n.global_position = Vector3(3.5, 1.3, 0)
	n.look_at(n.global_position + dir, Vector3.UP)
	var a := {"node": n, "dir": dir, "kind": kind, "pts": []}
	var dt := 1.0 / 30.0
	for f in frames:
		await process_frame
		n.global_position += dir * 6.0 * dt      # slowed, so the frames show it
		AFx.fly(a, n, dt, self)
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/lab_%03d.png" % [out, f])
	quit()
