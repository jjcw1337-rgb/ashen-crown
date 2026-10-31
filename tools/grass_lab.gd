extends SceneTree
## Grass lab: a 60 x 60 m stage with bands of each grass biome (tall meadow, trodden short grass, a dirt
## path, dense meadow, dry grass, woodland undergrowth with rocks), seen from the game's camera
## (Game.CAM_OFFSET, 36 degrees). Five walkers act out a script: walk a loop, sprint back and forth, stop and
## turn, a big beast (radius 1.2), and a pair crossing each other; there are sword swings, a slam, a dash,
## and the wind goes from a breeze to a storm and back to calm. Saves frames, checks the touch field
## (lines up with the world, comes fully back to rest) and prints [GL] lines.
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 960x540 --fixed-fps 15 --path . -s tools/grass_lab.gd -- outdir [quality] [zoomin] [frames t1,t2,..]
var out := "grass_lab"
var q := 2
var zoom := 1.0
var shots: Array = [1.0, 2.55, 4.0, 5.25, 7.2, 8.0, 10.5]
var stage: Node3D
var field: Node
var GF: Script
var GR: Script
var cam: Camera3D
var walkers: Array = []
var t := 0.0
var frame := 0
var shot_i := 0
var done := false
var log_lines: Array = []
var bend_seen := 0.0

const CAM := Vector3(0, 17.0, 16.5)

class Walker extends Node3D:
	var radius := 0.45
	var atk_t := -1.0
	var atk_dur := 0.6
	var atk_style := "over"
	var dead := false
	var rig: Node3D
	var path: Callable
	func setup(r: float, col: Color, h: float) -> void:
		radius = r
		rig = Node3D.new()
		add_child(rig)
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = r * 0.6
		cap.height = h
		mi.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.8
		mi.material_override = m
		mi.position.y = h * 0.5
		rig.add_child(mi)
		var nose := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(r * 0.5, r * 0.3, r * 0.8)
		nose.mesh = bx
		nose.material_override = m
		nose.position = Vector3(0, h * 0.7, -r * 0.7)
		rig.add_child(nose)

class Ctx extends RefCounted:
	var n := FastNoiseLite.new()
	func _init() -> void:
		n.seed = 3
		n.frequency = 0.05
	## bands across x: tall meadow | trodden | path | dense meadow | dry | woodland with rocks
	func grass_ground(x: float, z: float) -> float:
		var e := n.get_noise_2d(x * 2.0, z * 2.0) * 0.8
		if absf(x + 4.0 + e) < 1.2:
			return 0.0                               # the dirt path
		if absf(x + 4.0 + e) < 1.9:
			return 0.35                              # its ragged edge
		for r in ROCKS:
			if Vector2(x, z).distance_to(Vector2(r.x, r.y)) < r.z:
				return 0.0
		return 1.0
	func grass_height(_x: float, _z: float) -> float:
		return 0.0
	func grass_biome(x: float, z: float) -> Dictionary:
		var e := n.get_noise_2d(x, z) * 1.5
		var xx := x + e
		var w := {}
		w["meadow"] = 1.0 - smoothstep(-11.0, -9.0, xx) + smoothstep(-2.0, 0.0, xx) * (1.0 - smoothstep(4.0, 6.0, xx))
		w["trampled"] = smoothstep(-11.0, -9.0, xx) * (1.0 - smoothstep(-7.0, -5.5, xx))
		w["verge"] = (1.0 - absf(clampf((xx + 4.0) / 3.0, -1.0, 1.0)))
		w["dry"] = smoothstep(4.0, 6.0, xx) * (1.0 - smoothstep(9.0, 11.0, xx))
		w["woodland"] = smoothstep(9.0, 11.0, xx)
		return w
	const ROCKS := [Vector3(12, -3, 1.0), Vector3(13, 4, 0.7), Vector3(11.5, 9, 1.2)]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: q = int(a[1])
	if a.has("zoomin"): zoom = 0.6
	var fi := a.find("frames")
	if fi >= 0 and fi + 1 < a.size():
		shots = []
		for s in a[fi + 1].split(","):
			shots.append(float(s))
	DirAccess.make_dir_recursive_absolute(out)
	GF = load("res://scripts/grass_field.gd")
	GR = load("res://scripts/grass.gd")
	load("res://scripts/mats.gd").ensure_globals()
	stage = Node3D.new()
	get_root().add_child(stage)
	_stage()
	field = GF.new()
	field.movers_fn = func() -> Array: return walkers
	stage.add_child(field)
	field.set_wind("moor", 0.01)
	_aim(Vector3.ZERO)
	var ctx := Ctx.new()
	var moor: Dictionary = GR.ACT1
	var n := 0
	if not OS.get_cmdline_user_args().has("fieldonly"):
		n = GR.scatter(stage, Rect2(-30, -32, 60, 62), ctx, moor, q, 1234)
	_log("quality %d, clumps %d" % [q, n])
	if OS.get_cmdline_user_args().has("debugtouch"):
		for m in GR.material(moor):
			(m as ShaderMaterial).set_shader_parameter("debug_touch", true)
	_walkers()

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.6, 0.66, 0.72)
	e.fog_density = 0.006
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pm.subdivide_width = 1
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND
	gm.shader = sh
	ground.material_override = gm
	stage.add_child(ground)
	for r in Ctx.ROCKS:
		var rk := MeshInstance3D.new()
		var props: Script = load("res://scripts/props.gd")
		rk.mesh = props.rock_mesh(3, r.z * 0.8)
		rk.material_override = props.stone()
		rk.position = Vector3(r.x, 0, r.y)
		stage.add_child(rk)
	cam = Camera3D.new()
	cam.fov = 36.0
	stage.add_child(cam)
	_aim(Vector3(0, 0, 0))

func _aim(target: Vector3) -> void:
	var pos := target + CAM * zoom
	cam.transform = Transform3D(Basis.looking_at(target + Vector3(0, 1.0, 0) - pos, Vector3.UP), pos)
	if field:
		field.center = target
		field.cam_pos = cam.position

func _walkers() -> void:
	# 1: walks a loop through the dense meadow, swings at t 2.4 and 6.2
	_add(0.45, Color(0.7, 0.2, 0.15), 1.8, func(tt: float) -> Vector3:
		return Vector3(1.0 + cos(tt * 0.9) * 2.5, 0, 0.5 + sin(tt * 0.9) * 2.5))
	# 2: sprints back and forth across the tall meadow and the trodden band (7.6 m/s)
	_add(0.45, Color(0.2, 0.3, 0.75), 1.8, func(tt: float) -> Vector3:
		var k := pingpong(tt * 7.6, 11.0)
		return Vector3(-12.5 + k, 0, -4.5))
	# 3: walks, stops, turns, walks on (stop-and-go through the dry grass)
	_add(0.45, Color(0.85, 0.75, 0.2), 1.8, func(tt: float) -> Vector3:
		var seg := fmod(tt, 4.0)
		var leg := int(tt / 4.0) % 2
		var p := clampf(seg / 2.0, 0.0, 1.0) * 6.0
		return Vector3(4.5 + (p if leg == 0 else 6.0 - p) * 0.8, 0, 3.0 + (0.0 if leg == 0 else 1.5)))
	# 4: a big beast plodding through the woodland and back into the dry grass
	_add(1.2, Color(0.3, 0.25, 0.2), 2.4, func(tt: float) -> Vector3:
		return Vector3(12.0 - pingpong(tt * 1.6, 7.0), 0, -7.0 + tt * 0.5))
	# 5: crosses walker 1's loop near the centre (characters close together), then dashes at 15 m/s
	_add(0.45, Color(0.6, 0.6, 0.65), 1.8, func(tt: float) -> Vector3:
		var x := -2.0 + minf(tt, 7.0) * 0.9 + clampf(tt - 7.0, 0.0, 0.4) * 15.0 + maxf(tt - 7.4, 0.0) * 0.9
		return Vector3(x, 0, 4.5 - tt * 0.35))

func _add(r: float, col: Color, h: float, path: Callable) -> void:
	var w := Walker.new()
	w.setup(r, col, h)
	w.path = path
	stage.add_child(w)
	w.position = path.call(0.0)
	walkers.append(w)

func _process(delta: float) -> bool:
	if done:
		return true
	frame += 1
	if frame < 3:
		return false   # the field's two viewports start at rest
	t += delta
	for w in walkers:
		var wk := w as Walker
		var stop := t > 9.0   # everyone stands still at the end: the grass must come back
		var p: Vector3 = wk.path.call(minf(t, 9.0))
		var d := p - wk.position
		d.y = 0
		if d.length() > 0.001 and not stop:
			wk.rig.rotation.y = atan2(-d.x, -d.z)
		wk.position = p
	# swings by walker 1, a slam beside walker 3, a dash by walker 5
	var w1 := walkers[0] as Walker
	w1.atk_t = -1.0
	for st in [2.4, 6.2]:
		if t >= st and t < st + w1.atk_dur:
			w1.atk_t = t - st
	if absf(t - 5.0) < delta * 0.5:
		GF.impulse(Vector3(7.0, 0, -1.5), 3.2, 0.85)
		_log("slam at t 5.0")
	if absf(t - 3.0) < delta * 0.5:
		field.set_wind("storm", 1.5)
		_log("wind -> storm")
	if absf(t - 7.0) < delta * 0.5:
		field.set_wind("calm", 2.0)
		_log("wind -> calm")
	# the field: how bent is the grass right under walker 2 (sprinting), and does it line up?
	if absf(t - 4.0) < delta * 0.5:
		_check_alignment()
	if shot_i < shots.size() and t >= float(shots[shot_i]):
		var img: Image = get_root().get_texture().get_image()
		var f := "%s/lab_%02d_t%.1f.png" % [out, shot_i, t]
		if img:
			img.save_png(f)
			_log("saved " + f)
		shot_i += 1
	var ui := OS.get_cmdline_user_args().find("until")
	if ui >= 0 and t >= float(OS.get_cmdline_user_args()[ui + 1]):
		done = true
		quit()
		return false
	if t >= 12.0:
		_check_rest()
		var fl := FileAccess.open(out + "/lab_log.txt", FileAccess.WRITE)
		for l in log_lines:
			fl.store_line(l)
		fl.close()
		done = true
		quit()
	return false

func _field_img() -> Image:
	return field.shown_image()

## Where the sprinter is, the field must be bent; at the mirror-image spot (z flipped round the field's
## centre) it must not be. A flip between how the field is written and read would show here.
func _check_alignment() -> void:
	var img := _field_img()
	var rect: Vector4 = field.shown_rect
	if img == null:
		_log("FIELD: no image")
		return
	var w2 := walkers[1] as Walker
	var p := w2.position
	var here := _bend_at(img, rect, p.x, p.z)
	var mirror_z := rect.y + rect.z - (p.z - rect.y)
	var there := _bend_at(img, rect, p.x, mirror_z)
	var mirror_x := rect.x + rect.z - (p.x - rect.x)
	var there_x := _bend_at(img, rect, mirror_x, p.z)
	var big := 0.0
	var at := Vector2i.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var b := Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0).length()
			if b > big:
				big = b
				at = Vector2i(x, y)
	var wat := Vector2(rect.x + (at.x + 0.5) / img.get_width() * rect.z, rect.y + (at.y + 0.5) / img.get_height() * rect.z)
	_log("FIELD align: bend beside sprinter %.2f, at z-mirror %.2f, at x-mirror %.2f, max anywhere %.2f at pixel %s = world %s; image %dx%d rect %s" % [here, there, there_x, big, at, wat, img.get_width(), img.get_height(), rect])
	var ws := []
	for w in walkers:
		ws.append(Vector2((w as Walker).position.x, (w as Walker).position.z).snapped(Vector2(0.1, 0.1)))
	_log("FIELD walkers at %s" % [ws])
	if OS.get_cmdline_user_args().has("fieldonly"):
		done = true
		quit()

func _bend_at(img: Image, rect: Vector4, x: float, z: float) -> float:
	var u := (x - rect.x) / rect.z
	var v := (z - rect.y) / rect.z
	var best := 0.0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var px := clampi(int(u * img.get_width()) + dx, 0, img.get_width() - 1)
			var py := clampi(int(v * img.get_height()) + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(px, py)
			best = maxf(best, Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0).length())
	return best

## Three seconds after everyone stopped (only standing presses remain), grass away from the walkers
## must be fully back at rest.
func _check_rest() -> void:
	var img := _field_img()
	var rect: Vector4 = field.shown_rect
	if img == null:
		return
	var worst := 0.0
	var moving := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var wx := rect.x + (x + 0.5) / img.get_width() * rect.z
			var wz := rect.y + (y + 0.5) / img.get_height() * rect.z
			var near := false
			for w in walkers:
				var wp: Vector3 = (w as Walker).position
				if Vector2(wx - wp.x, wz - wp.z).length() < (w as Walker).radius * 1.6 + 0.6:
					near = true
					break
			if near:
				continue
			var c := img.get_pixel(x, y)
			worst = maxf(worst, Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0).length())
			moving = maxf(moving, Vector2(c.b * 2.0 - 1.0, c.a * 2.0 - 1.0).length() * 6.0)
	_log("FIELD rest: worst leftover bend away from walkers %.3f (8-bit step 0.008), velocity %.3f" % [worst, moving])

func _log(s: String) -> void:
	print("[GL] ", s)
	log_lines.append(s)

const GROUND := """
shader_type spatial;
varying vec3 wp;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float n = vn(wp.xz * 0.6) * 0.6 + vn(wp.xz * 3.0) * 0.4;
	// the moor's terrain colours (World.MOOR_TERRAIN col_a/col_b/col_path, in linear light)
	vec3 moss = mix(vec3(0.0152, 0.0284, 0.0039), vec3(0.0331, 0.0398, 0.0079), n) * 1.6;
	vec3 dirt = mix(vec3(0.0508, 0.0368, 0.0222), vec3(0.075, 0.055, 0.035), n) * 1.6;
	float e = (vn(wp.xz * 0.1) - 0.5) * 1.6;
	float path = 1.0 - smoothstep(1.0, 1.9, abs(wp.x + 4.0 + e));
	ALBEDO = mix(moss, dirt, path);
	ROUGHNESS = 0.95;
}
"""
