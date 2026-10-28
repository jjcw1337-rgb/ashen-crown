class_name Warlock
extends RefCounted
## The Warlock class: a pale sorcerer in a long black-green robe and a deep hood, fel fire
## burning in the off hand and a grimoire floating at the shoulder. Like the Wraith and the
## Demon it reuses the knight's skeleton and joints (so Anim.pose, weapon grips and co-op
## puppets all work) and adds its own pieces.

## The gnome warlock: a model generated with Meshy from a Meshy concept image, rigged in Blender
## (tools/blender/gnome_warlock.py) on this joint layout (model space, Godot axes, 1.2 m to the hat's
## tip before "scale"). His arms were modelled out in an A-pose: "aim" turns their rest down the arm
## so the hero's animation hangs them naturally. "stride" quickens his steps to his short legs.
const GNOME := {"glb": "res://assets/models/gnome_warlock.glb", "scale": 1.55, "stride": 1.55, "layout": {
	"hips": ["", Vector3(0, 0.33, 0)], "torso": ["hips", Vector3(0, 0.4, 0)], "head": ["torso", Vector3(0, 0.64, -0.03)],
	"hat": ["head", Vector3(0, 0.8, 0.01)], "beard": ["head", Vector3(0, 0.6, -0.12)],
	"sh_r": ["torso", Vector3(0.19, 0.6, 0)], "el_r": ["sh_r", Vector3(0.31, 0.5, -0.02)], "hand_r": ["el_r", Vector3(0.41, 0.42, -0.04)],
	"sh_l": ["torso", Vector3(-0.19, 0.6, 0)], "el_l": ["sh_l", Vector3(-0.31, 0.5, -0.02)], "hand_l": ["el_l", Vector3(-0.41, 0.42, -0.04)],
	"leg_r": ["hips", Vector3(0.11, 0.3, 0)], "knee_r": ["leg_r", Vector3(0.14, 0.17, -0.01)],
	"leg_l": ["hips", Vector3(-0.11, 0.3, 0)], "knee_l": ["leg_l", Vector3(-0.14, 0.17, -0.01)],
}, "aim": {"sh_r": "el_r", "el_r": "hand_r", "hand_r": "=el_r", "sh_l": "el_l", "el_l": "hand_l", "hand_l": "=el_l"}}

## The gnome's robes and hat, recoloured from the model's dark green (it vanished against grass).
const CLOAK := Color(0.36, 0.1, 0.5)
## The black horns on his hat, recoloured (only above the brim, so boots and belt stay black).
const HORNS := Color(0.75, 0.06, 0.04)
## His glowing footprints.
const PRINT := Color(0.35, 1.0, 0.3)

const FEL := Color(0.35, 1.0, 0.3)
const PALE := Color(0.8, 1.0, 0.7)
const DEEP := Color(0.05, 0.35, 0.08)

static func default_gear() -> Dictionary:
	return {"fel": FEL, "robe": Color(0.05, 0.08, 0.055), "skin": Color(0.6, 0.64, 0.56)}

## The knight body dressed as a warlock: robe to the ankles, dark cloth, pale skin, fel trim.
static func body_gear(g: Dictionary) -> Dictionary:
	var k := Knight.default_gear()
	k["armor"] = "quilted"
	k["robe"] = true
	k["cloth"] = g["robe"]
	k["quilt"] = (g["robe"] as Color).lightened(0.05)
	k["cape"] = (g["robe"] as Color).darkened(0.35)
	k["emblem"] = g["robe"]
	k["trim"] = g["fel"]
	k["glow"] = (g["fel"] as Color).darkened(0.4)
	k["leather"] = Color(0.1, 0.08, 0.06)
	k["skin"] = g["skin"]
	k["hair"] = Color(0.03, 0.035, 0.03)
	k["gloves"] = ""
	k["boots"] = ""
	k["coif"] = false
	return k

## True when the gnome's model is in the project (else the Warlock is the robed knight body).
static func gnome() -> bool:
	return ResourceLoader.exists(GNOME["glb"])

static func build(g: Dictionary) -> Node3D:
	if gnome():
		return _build_gnome(g)
	var root := Knight.build(body_gear(g))
	root.set_meta("warlock", true)
	_extras(root, g)
	return root

static func rebuild_body(root: Node3D, g: Dictionary) -> void:
	if not root.has_meta("gnome"):
		Knight.rebuild_body(root, body_gear(g))
	for m in root.get_meta("fel_mats", []):
		(m as ShaderMaterial).set_shader_parameter("color", g["fel"])

static func _extras(root: Node3D, g: Dictionary) -> void:
	var J: Dictionary = root.get_meta("j")
	var fel: Color = g["fel"]
	var mats := []
	var glow := Mats.glow_unique(fel, 1.2)
	mats.append(glow)
	var cloth := (Mats.mat((g["robe"] as Color).darkened(0.2), 0.95) as StandardMaterial3D).duplicate() as StandardMaterial3D
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hd: Node3D = J["head"]
	# a deep hood, tipped back so the face shows, with a glowing rim and a drooping peak
	var hood := Models.N(hd, "hood", Vector3(0, 0.095, 0.03), Vector3(38, 0, 0))
	var dome := Models.P(hood, Geo.sph(0.14, 18, 0.5), cloth, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.25, 1.12))
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim := Mats.glow_unique(fel, 0.9)
	mats.append(rim)
	Models.P(hood, Geo.torus(0.136, 0.15, 32, 4), rim, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.4, 1.12))
	Models.P(hood, Geo.cone(0.075, 0.17, 10), cloth, Vector3(0, 0.2, 0.03), Vector3(28, 0, 0))
	# the cowl falls from the hood over the shoulders
	Models.seg(hd, Vector3(0, 0.02, 0.09), Vector3(0, -0.14, 0.13), 0.12, 0.19, cloth, 14)
	# small black horns pushing up through the hood, fel-tipped
	var horn := Mats.mat(Color(0.05, 0.05, 0.045), 0.4, 0.3)
	for side in [1, -1]:
		var prev := Vector3(side * 0.085, 0.17, 0.0)
		var dir := Vector3(side * 0.55, 0.75, 0.35).normalized()
		var r := 0.024
		for i in 5:
			var nxt := prev + dir * 0.04
			var s := Models.seg(hd, prev, nxt, r, r * 0.8, horn, 8)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			prev = nxt
			r *= 0.8
			dir = (dir + Vector3(0, -0.12, 0.25)).normalized()
		Models.seg(hd, prev, prev + dir * 0.035, r, 0.001, glow, 6)
	# burning green eyes
	for sx in [-1, 1]:
		Models.P(hd, Geo.sph(0.013, 8), Mats.glow(PALE, 6.0), Vector3(0.036 * sx, 0.125, -0.094), Vector3.ZERO, Vector3(1.5, 0.65, 1.0))
	# fel fire cupped in the off hand
	var hl: Node3D = J["hand_l"]
	var core := Models.P(hl, Geo.sph(0.03, 10), Mats.glow(fel, 1.3), Vector3(0, -0.1, -0.04))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame := fel_flame(0.8, fel)
	flame.position = Vector3(0, -0.1, -0.04)
	hl.add_child(flame)
	# the grimoire: floats behind the left shoulder, bobbing and turning slowly
	var book := Models.N(root, "grimoire", Vector3(-0.48, 1.3, 0.12))
	var cover := Mats.mat(Color(0.12, 0.05, 0.04), 0.7)
	var pages := Mats.mat(Color(0.75, 0.7, 0.55), 0.95)
	Models.P(book, Geo.box(0.2, 0.012, 0.26), cover, Vector3(0, -0.026, 0))
	Models.P(book, Geo.box(0.2, 0.012, 0.26), cover, Vector3(0, 0.026, 0))
	Models.P(book, Geo.box(0.185, 0.04, 0.245), pages, Vector3(0.006, 0, 0))
	Models.P(book, Geo.box(0.014, 0.064, 0.26), cover, Vector3(-0.1, 0, 0))
	var sig := Mats.glow_unique(fel, 1.1)
	mats.append(sig)
	Models.P(book, Geo.torus(0.045, 0.056, 20, 4), sig, Vector3(0.01, 0.034, 0))
	Models.P(book, Geo.sph(0.018, 8), sig, Vector3(0.01, 0.034, 0))
	var motes := fel_flame(0.35, fel, true)
	book.add_child(motes)
	root.set_meta("fel_mats", mats)
	root.set_meta("warlock_anim", {"book": book, "flame": flame, "energy": mats.map(func(m): return float(m.get_shader_parameter("energy"))), "power": 0.0})

static func _build_gnome(g: Dictionary) -> Node3D:
	var root := Goblin.imported_rig(GNOME["layout"], GNOME["glb"], "gnome_warlock", GNOME["aim"])
	var J: Dictionary = root.get_meta("j")
	var body: MeshInstance3D = root.get_node("Skeleton/Body")
	var src_mat: Material = body.mesh.surface_get_material(0)
	body.mesh = _hat_masked(body.mesh)
	body.material_override = cloak_mat(src_mat, CLOAK)
	# weapons and shields are made at a human's size: hold them a little smaller
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.05, -0.01), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.05, -0.01))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.05, -0.08, 0), Vector3(0, 70, 0))
	J["chest"] = Models.N(J["torso"], "chest", Vector3(0, 0.14, -0.13), Vector3(-75, 0, 0))
	for k in ["grip_r", "grip_l", "mount_l", "chest"]:
		(J[k] as Node3D).scale = Vector3.ONE * 0.55
	root.scale = Vector3.ONE * float(GNOME["scale"])
	root.set_meta("h", 0.5)
	root.set_meta("stride", GNOME["stride"])
	root.set_meta("warlock", true)
	root.set_meta("gnome", true)
	var fel: Color = g["fel"]
	var mats := []
	# his eyes burn green in the model's own texture; a faint light under the brim helps them read
	var hd: Node3D = J["head"]
	var el := OmniLight3D.new()
	el.light_color = fel
	el.light_energy = 0.25
	el.omni_range = 0.35
	el.position = Vector3(0, 0.1, -0.16)
	hd.add_child(el)
	# fel fire cupped in the off hand
	var hl: Node3D = J["hand_l"]
	var glow := Mats.glow_unique(fel, 1.3)
	mats.append(glow)
	var core := Models.P(hl, Geo.sph(0.024, 10), glow, Vector3(0, -0.06, -0.03))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame := fel_flame(0.6, fel)
	flame.position = Vector3(0, -0.06, -0.03)
	hl.add_child(flame)
	var hlight := OmniLight3D.new()
	hlight.light_color = fel
	hlight.light_energy = 0.45
	hlight.omni_range = 1.1
	hlight.position = Vector3(0, -0.06, -0.03)
	hl.add_child(hlight)
	# a soft fel glow rides with him, so the dark robes read against a dark moor
	var aura := OmniLight3D.new()
	aura.light_color = Color(0.85, 0.78, 1.0)
	aura.light_energy = 1.3
	aura.omni_range = 2.0
	aura.position = Vector3(0.2, 1.25, 0.45)
	root.add_child(aura)
	# the grimoire floats at his shoulder, as for the robed Warlock
	var book := Models.N(root, "grimoire", Vector3(-0.44, 0.7, 0.14))
	book.scale = Vector3.ONE * 0.7
	var cover := Mats.mat(Color(0.12, 0.05, 0.04), 0.7)
	var pages := Mats.mat(Color(0.75, 0.7, 0.55), 0.95)
	Models.P(book, Geo.box(0.2, 0.012, 0.26), cover, Vector3(0, -0.026, 0))
	Models.P(book, Geo.box(0.2, 0.012, 0.26), cover, Vector3(0, 0.026, 0))
	Models.P(book, Geo.box(0.185, 0.04, 0.245), pages, Vector3(0.006, 0, 0))
	Models.P(book, Geo.box(0.014, 0.064, 0.26), cover, Vector3(-0.1, 0, 0))
	var sig := Mats.glow_unique(fel, 1.1)
	mats.append(sig)
	Models.P(book, Geo.torus(0.045, 0.056, 20, 4), sig, Vector3(0.01, 0.034, 0))
	Models.P(book, Geo.sph(0.018, 8), sig, Vector3(0.01, 0.034, 0))
	book.add_child(fel_flame(0.35, fel, true))
	root.set_meta("fel_mats", mats)
	root.set_meta("warlock_anim", {"book": book, "flame": flame, "energy": mats.map(func(m): return float(m.get_shader_parameter("energy"))), "power": 0.0,
		"book_at": Vector3(-0.44, 0.7, 0.14)})
	return root

static var _cloak_shader: Shader
static var _masked: ArrayMesh

## The body mesh with a vertex-colour mask on the hat (red = above the brim), so the shader can
## turn the horns red without touching the black boots, belt and pauldrons. Made once.
static func _hat_masked(mesh: Mesh) -> Mesh:
	if _masked != null:
		return _masked
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(v.size())
		for i in v.size():
			cols[i] = Color(smoothstep(0.82, 0.86, v[i].y), 0.0, 0.0, 1.0)
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, mesh.surface_get_material(si))
	out.set_meta("imported", true)
	_masked = out
	return out

## The gnome's own textures with the dark green cloth (robes, hat) turned to `col`; the bright
## fel-green runes, skin, beard, leather and metal keep their colours.
static func cloak_mat(src: Material, col: Color) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var sm := src as StandardMaterial3D
	if _cloak_shader == null:
		_cloak_shader = Shader.new()
		_cloak_shader.code = CLOAK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cloak_shader
	m.set_shader_parameter("albedo_tex", sm.albedo_texture)
	m.set_shader_parameter("normal_tex", sm.normal_texture)
	m.set_shader_parameter("orm_tex", sm.roughness_texture)
	m.set_shader_parameter("cloak", col)
	m.set_shader_parameter("horns", HORNS)
	return m

const CLOAK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 cloak : source_color = vec3(0.36, 0.1, 0.5);
uniform vec3 horns : source_color = vec3(0.75, 0.06, 0.04);
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	// dark, greenish, not grey: the robes and hat (the runes are bright, so they stay fel green)
	float green = smoothstep(0.17, 0.24, h.x) * (1.0 - smoothstep(0.5, 0.58, h.x));
	float dark = 1.0 - smoothstep(0.16, 0.3, h.z);
	float m = green * dark * smoothstep(0.08, 0.2, h.y);
	vec3 t = rgb2hsv(cloak);
	vec3 rc = hsv2rgb(vec3(t.x, clamp(h.y * 1.2, t.y * 0.8, 0.95), max(h.z * 2.6, t.z * 0.3)));
	vec3 col = mix(c, rc, m);
	// the hat's horns: dark and grey (the hat itself is green, so it is excluded), above the brim
	float horn = COLOR.r * (1.0 - smoothstep(0.18, 0.32, h.y)) * (1.0 - smoothstep(0.25, 0.45, h.z));
	vec3 th = rgb2hsv(horns);
	col = mix(col, hsv2rgb(vec3(th.x, th.y, max(h.z * 3.5, th.z * 0.35))), horn);
	ALBEDO = col;
	vec3 orm = texture(orm_tex, UV).rgb;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	RIM = 0.35;
	RIM_TINT = 0.6;
}
"""

## Green fel fire (or, with motes, a slow drift of sparks). Additive particles in world space.
static func fel_flame(s: float, col: Color, motes := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10 if motes else int(14 * s) + 4
	p.lifetime = 1.4 if motes else 0.6
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12 if motes else 0.05 * s
	pm.direction = Vector3.UP
	pm.spread = 25.0 if motes else 12.0
	pm.initial_velocity_min = 0.05 if motes else 0.4 * s
	pm.initial_velocity_max = 0.2 if motes else 0.9 * s
	pm.gravity = Vector3(0, 0.3 if motes else 1.4 * s, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(col.r * 0.8, col.g * 0.9, col.b * 0.7, 0.55))
	g.add_point(0.35, Color(col.r * 0.3, col.g * 0.6, col.b * 0.3, 0.4))
	g.set_color(1, Color(0.0, 0.2, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05) if motes else Vector2(0.15, 0.22) * s
	q.material = Mats.particle_mat(true, Color.WHITE)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## The grimoire bobs and turns, drifting further out while the Warlock moves. Under Fel
## Covenant (power 1) the horns, hood rim and sigil burn brighter and the hand-fire swells.
## phase: the stride phase (footsteps and the hat's hop); free: not attacking, casting or channelling.
static func animate(root: Node3D, t: float, move: float, power := 0.0, phase := 0.0, free := true) -> void:
	if not root.has_meta("warlock_anim"):
		return
	var a: Dictionary = root.get_meta("warlock_anim")
	var pw: float = move_toward(float(a["power"]), power, 0.05)
	if pw != float(a["power"]) or pw > 0.0:
		a["power"] = pw
		var mats: Array = root.get_meta("fel_mats")
		var base: Array = a["energy"]
		var flick := 1.0 + 0.15 * sin(t * 11.0) * pw
		for i in mats.size():
			(mats[i] as ShaderMaterial).set_shader_parameter("energy", float(base[i]) * (1.0 + 1.2 * pw) * flick)
		(a["flame"] as Node3D).scale = Vector3.ONE * (1.0 + 0.8 * pw)
	if root.has_meta("gnome"):
		_gnome_sway(root, t, move, phase, free)
	var book: Node3D = a["book"]
	var at: Vector3 = a.get("book_at", Vector3(-0.48, 1.3, 0.12))
	book.position = at + Vector3(-move * 0.06, sin(t * 1.8) * 0.05, move * 0.1)
	book.rotation = Vector3(0.35 + sin(t * 1.3) * 0.08, 0.5 + sin(t * 0.7) * 0.25, -0.25 + sin(t * 1.1) * 0.06)

## The gnome's hat and beard lag behind his body on springs: the tall hat tips back when he sets
## off and nods forward when he stops, bounces on his footfalls and swings out on turns; the beard
## follows the swing of his chest a beat late.
static func _gnome_sway(root: Node3D, t: float, move: float, phase := 0.0, free := true) -> void:
	var J: Dictionary = root.get_meta("j")
	if not root.has_meta("sway"):
		root.set_meta("sway", {})
	var D: Dictionary = root.get_meta("sway")
	var dt := clampf(t - float(D.get("t", t)), 0.0, 0.05)
	D["t"] = t
	if dt <= 0.0:
		return
	var torso: Node3D = J["torso"]
	var head: Node3D = J["head"]
	var hips: Node3D = J["hips"]
	var yaw: float = root.get_parent().global_rotation.y if root.get_parent() is Node3D else root.rotation.y
	yaw += root.rotation.y
	var yv := wrapf(yaw - float(D.get("yaw", yaw)), -PI, PI) / dt
	D["yaw"] = yaw
	var acc := (move - float(D.get("mv", move))) / dt
	D["mv"] = move
	var hy: float = hips.position.y
	var vy := (hy - float(D.get("hy", hy))) / dt
	D["hy"] = hy
	var tilt: float = torso.rotation.x + head.rotation.x
	var tv := (tilt - float(D.get("tilt", tilt))) / dt
	D["tilt"] = tilt
	Anim.kick(D, "hx", clampf(acc * 0.05 - vy * 0.6 - tv * 0.25, -3.0, 3.0) * dt * 20.0)
	Anim.kick(D, "hz", clampf(yv * 0.05, -2.0, 2.0) * dt * 20.0)
	var hat: Node3D = J["hat"]
	hat.rotation = Vector3(Anim.spring(D, "hx", -0.06 * move, 70.0, 0.18, dt), sin(t * 0.6) * 0.04,
		Anim.spring(D, "hz", sin(t * 0.9) * 0.025, 70.0, 0.2, dt))
	var beard: Node3D = J["beard"]
	beard.rotation = Vector3(Anim.spring(D, "bx", -tilt * 0.6 + 0.08 * move, 90.0, 0.3, dt),
		0.0, Anim.spring(D, "bz", -torso.rotation.z * 0.8 + clampf(-yv * 0.03, -0.25, 0.25), 90.0, 0.3, dt))
	# the hat hops on every footfall: up as a foot pushes off, a springy drop as it lands
	if not D.has("hat_rest"):
		D["hat_rest"] = hat.position
	var run := clampf(move, 0.0, 1.3)
	var hop := absf(sin(phase)) * 0.05 * run
	hat.position = (D["hat_rest"] as Vector3) + Vector3(0, Anim.spring(D, "hop", hop, 220.0, 0.25, dt), 0)
	# running, he holds his weapon (or bare fist) high on the right and waves it back and forth
	var hold := Anim.spring(D, "hold", 1.0 if free and move > 0.35 else 0.0, 60.0, 0.9, dt)
	if hold > 0.01:
		var wave := sin(phase * 0.5 + t * 1.5)
		var sh: Node3D = J["sh_r"]
		var el: Node3D = J["el_r"]
		sh.rotation = sh.rotation.lerp(Vector3(2.85 + 0.1 * sin(phase), 0.1 * wave, 0.75 + 0.35 * wave), hold)
		el.rotation = el.rotation.lerp(Vector3(0.2 + 0.15 * wave, 0.0, 0.0), hold)
	if root.has_method("sync"):
		root.sync()
	_footprint(root, D, phase, move)

## A glowing green footprint where each foot lands; it fades away by the next step or two.
static func _footprint(root: Node3D, D: Dictionary, phase: float, move: float) -> void:
	var step := int(floorf(phase / PI))
	var last: int = D.get("step", step)
	D["step"] = step
	if step == last or move < 0.25 or not root.is_inside_tree():
		return
	var J: Dictionary = root.get_meta("j")
	var knee: Node3D = J["knee_l"] if step % 2 == 0 else J["knee_r"]
	var host := root.get_parent() as Node3D
	var at: Vector3 = knee.global_position
	at.y = (host.global_position.y if host != null else 0.0) + 0.015
	var fwd := -root.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p := Node3D.new()
	# in the world, not on the walker, so the print stays where it was left
	var holder: Node = host.get_parent() if host != null and host.get_parent() != null else root
	holder.add_child(p)
	p.global_position = at + fwd * 0.04
	p.rotation.y = atan2(-fwd.x, -fwd.z)
	var m := Mats.glow_unique(PRINT, 2.2)
	# a curled gnome boot: heel, sole and a pointed toe hooking to one side
	var side := 1.0 if step % 2 == 0 else -1.0
	for part in [[Vector3(0, 0, 0.07), 0.05, Vector3(1.0, 0.05, 1.0)], [Vector3(0, 0, -0.03), 0.06, Vector3(0.9, 0.05, 1.3)],
			[Vector3(side * 0.03, 0, -0.13), 0.035, Vector3(0.9, 0.05, 1.4)]]:
		var mi := Models.P(p, Geo.sph(part[1], 12), m, part[0], Vector3.ZERO, part[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := p.create_tween()
	tw.tween_method(func(e: float): m.set_shader_parameter("energy", e), 2.2, 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.queue_free)
