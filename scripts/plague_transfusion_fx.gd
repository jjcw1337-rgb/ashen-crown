class_name PlagueTransfusionFx
extends RefCounted
## Transfusion's look (the Plague Doctor's G; gameplay in plague.gd): his experimental apparatus.
##
## The apparatus is the Meshy model assets/models/plague/apparatus.glb (concept, image-to-3D, prep_prop.py: a riveted
## brass frame with two glass serum tanks, copper tubes, gauges, a harness and a needle on a hose), strapped to his
## back for the length of the skill: it unfolds onto him, the hose runs to his left forearm (`Hose`, redrawn each
## frame between the two bones), and as blows land the serum in the tanks rises and glows (`soak`: the tank lights
## and the shimmer round him grow with how full they are). A glassy shimmer shows everyone he is soaking damage
## (`SHELL_SHADER`: a fresnel rim of glass over the Meshy painting of red veins in cracked glass, glass_veins, laid
## round him triplanar and mirror-tiled, crawling slowly upward, the veins filling with serum and pulsing as the tanks
## fill; sparks where hits land). Steam is the Mantaflow vapour (PlagueSmoke): a hiss of it as the needle goes in, a
## vent of it at the end as the tubes drain and the apparatus folds away (`finish`), and a column of it, red, rising
## through him as what he soaked comes back as healing.

const APP_GLB := "res://assets/models/plague/apparatus.glb"
const VEINS_TEX := "res://assets/textures/plague/glass_veins_mask.png"
const HOSE_TEX := "res://assets/textures/plague/hose_albedo.png"
const SERUM := Color(0.9, 0.18, 0.14)

static func attach(h: Hero) -> Node3D:
	var root := Node3D.new()
	root.name = "pd_transfusion"
	if h.rig == null or not h.rig.has_meta("j"):
		h.add_child(root)
		return root
	var J: Dictionary = h.rig.get_meta("j")
	var torso: Node3D = J.get("at_torso", h)
	torso.add_child(root)
	var app := Node3D.new()
	root.add_child(app)
	if ResourceLoader.exists(APP_GLB):
		app.add_child((load(APP_GLB) as PackedScene).instantiate())
	# on his back (the rig faces -z), its tanks outward, hanging from the shoulders
	app.position = Vector3(0, -0.32, 0.2)
	app.rotation = Vector3(0, 0, 0)
	app.scale = Vector3(0.01, 0.01, 0.01)
	app.name = "app"
	var tw := app.create_tween()
	tw.tween_property(app, "scale", Vector3.ONE * 0.95, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var lamp := OmniLight3D.new()
	lamp.name = "serum"
	lamp.light_color = SERUM
	lamp.light_energy = 0.4
	lamp.omni_range = 1.4
	lamp.position = Vector3(0, -0.1, 0.32)
	root.add_child(lamp)
	var bubbles := Fx.aura(root, Color(1.0, 0.45, 0.35, 0.9), 14, 0.3, 0.012, 0.6, 0.6, 0.06, 15.0, Vector3(0, -0.2, 0.3))
	bubbles.name = "bubbles"
	# the hose to his left forearm
	var hose := Hose.new()
	hose.name = "hose"
	hose.from_node = app
	hose.to_node = J.get("at_hand_l", J.get("at_hand_r", null))
	h.game.world.fx_root.add_child(hose)
	root.set_meta("hose", hose)
	# the shimmer: a glassy shell round him
	var shell := MeshInstance3D.new()
	shell.name = "shell"
	var sm := SphereMesh.new()
	sm.radius = 0.75
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	shell.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = _shell_shader()
	mat.set_shader_parameter("fill", 0.0)
	mat.set_shader_parameter("amt", 0.0)
	mat.set_shader_parameter("veins", PlagueVialFx._tex(VEINS_TEX))
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(shell)
	shell.position = Vector3(0, 1.0, 0)
	root.set_meta("shell", shell)
	var tw2 := shell.create_tween()
	tw2.tween_method(func(v: float) -> void: mat.set_shader_parameter("amt", v), 0.0, 1.0, 0.25)
	# the needle going in: a hiss and a burst of steam at his arm, and off the apparatus's valves
	if J.has("at_hand_l"):
		PlagueSmoke.puffs(h.game.world.fx_root, (J["at_hand_l"] as Node3D).global_position, PlagueSmoke.VAPOUR, Color(0.92, 0.92, 0.96, 0.55), 6, 0.45, 0.8, 1.2, 0.05, 0.6, 60.0)
	PlagueSmoke.puffs(h.game.world.fx_root, torso.global_position + Vector3(0, 0.2, 0), PlagueSmoke.VAPOUR, Color(0.92, 0.92, 0.96, 0.45), 5, 0.6, 0.9, 1.0, 0.1, 0.8, 40.0)
	return root

## The tanks fill (0..1 of what they can hold): the serum glows brighter, the shimmer thickens, a spark of glass.
static func soak(root: Node, fill: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	var lamp: OmniLight3D = (root as Node3D).get_node_or_null("serum")
	if lamp != null:
		lamp.light_energy = 0.4 + clampf(fill, 0.0, 1.0) * 2.4
	if (root as Node3D).has_meta("shell"):
		var shell: MeshInstance3D = root.get_meta("shell")
		if is_instance_valid(shell):
			(shell.material_override as ShaderMaterial).set_shader_parameter("fill", clampf(fill, 0.0, 1.0))
			Fx.burst(shell, shell.global_position + Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.6), randf_range(-0.5, 0.5)), Color(1.0, 0.75, 0.7), 6, 2.0, 0.02, 0.25, true, -3.0)

## The end: steam vents, the tubes drain, the apparatus folds away; a heal pulse if he soaked anything.
static func finish(root: Node, healed: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	var r := root as Node3D
	# the vent: the apparatus blows off its steam as it folds away (in the world, so it outlives the apparatus)
	var vroot := _world_fx(r)
	PlagueSmoke.puffs(vroot, r.global_position + Vector3(0, 0.3, 0), PlagueSmoke.VAPOUR, Color(0.92, 0.92, 0.96, 0.6), 12, 0.9, 1.3, 2.2, 0.2, 0.9, 55.0)
	if healed:
		# what he soaked comes back: a column of red vapour rising through him, sparks, a flash
		PlagueSmoke.puffs(vroot, r.global_position + Vector3(0, -0.7, 0), PlagueSmoke.VAPOUR, Color(1.0, 0.42, 0.36, 0.55), 12, 0.75, 1.1, 1.0, 0.3, 2.6, 18.0)
		Fx.burst(r, r.global_position + Vector3(0, -0.6, 0), SERUM.lightened(0.3), 24, 1.2, 0.06, 0.9, true, 2.5)
		Fx.flash(r, r.global_position, SERUM, 2.5, 0.4, 2.5)
	var app: Node3D = r.get_node_or_null("app")
	if app != null:
		var tw := app.create_tween()
		tw.tween_interval(0.25)
		tw.tween_property(app, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	var lamp: OmniLight3D = r.get_node_or_null("serum")
	if lamp != null:
		lamp.create_tween().tween_property(lamp, "light_energy", 0.0, 0.4)
	if r.has_meta("hose"):
		var hose = r.get_meta("hose")
		if is_instance_valid(hose):
			(hose as Node).queue_free()
	if r.has_meta("shell"):
		var shell = r.get_meta("shell")
		if is_instance_valid(shell):
			var mat: ShaderMaterial = (shell as MeshInstance3D).material_override
			var tw2 := (shell as Node).create_tween()
			tw2.tween_method(func(v: float) -> void: mat.set_shader_parameter("amt", v), 1.0, 0.0, 0.35)
			tw2.tween_callback((shell as Node).queue_free)
	Fx._free_later(r, 0.8)

## The world's effects root above a node on the hero (or the node itself).
static func _world_fx(n: Node) -> Node3D:
	var p := n
	while p != null and not (p is Hero):
		p = p.get_parent()
	if p != null and (p as Hero).game != null and (p as Hero).game.world != null:
		return (p as Hero).game.world.fx_root
	return n as Node3D

## The hose from the apparatus to his forearm: a sagging tube redrawn every frame, serum pulsing along it.
class Hose extends MeshInstance3D:
	var from_node: Node3D
	var to_node: Node3D
	var t := 0.0
	var textured := false
	func _ready() -> void:
		mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.3
		m.emission_enabled = true
		var tex := PlagueVialFx._tex(PlagueTransfusionFx.HOSE_TEX)
		if tex != null:
			# the Meshy painting of a braided leather-and-brass hose with glass windows of serum, tiled along it
			m.albedo_texture = tex
			m.texture_repeat = true
			m.emission = PlagueTransfusionFx.SERUM * 0.08
			textured = true
		else:
			m.emission = PlagueTransfusionFx.SERUM * 0.35
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	func _process(delta: float) -> void:
		t += delta
		if from_node == null or to_node == null or not is_instance_valid(from_node) or not is_instance_valid(to_node):
			queue_free()
			return
		var a := from_node.global_position + Vector3(0, 0.2, 0)
		var b := to_node.global_position
		var im: ImmediateMesh = mesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := 14
		var cam := get_viewport().get_camera_3d()
		# the painting is 8:1, the hose 2.4 cm thick: a tile every 19 cm along it
		var tiles := a.distance_to(b) / (0.024 * 8.0)
		for i in n + 1:
			var u := float(i) / n
			var p := a.lerp(b, u) + Vector3(0, -sin(u * PI) * 0.18, 0)
			var side := Vector3.RIGHT
			if cam != null:
				side = (cam.global_position - p).cross(b - a).normalized() * 0.012
			var pulse := 0.5 + 0.5 * sin(u * 18.0 - t * 14.0)
			var c := Color(0.35, 0.22, 0.12).lerp(PlagueTransfusionFx.SERUM, pulse * 0.8)
			if textured:
				c = Color(1, 1, 1).lerp(Color(1.0, 0.62, 0.56), pulse * 0.6)     # the serum's pulse running along it
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(u * tiles, 0.0))
			im.surface_add_vertex(p - side)
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(u * tiles, 1.0))
			im.surface_add_vertex(p + side)
		im.surface_end()

static var _ssh: Shader
static func _shell_shader() -> Shader:
	if _ssh != null:
		return _ssh
	_ssh = Shader.new()
	_ssh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;
uniform float fill = 0.0;
uniform float amt = 1.0;
uniform sampler2D veins : filter_linear_mipmap;
varying vec3 lp;
varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
// mirrored tiling (a triangle wave), so the painting's edges meet themselves without a seam
vec2 mirror(vec2 uv) { return 1.0 - abs(1.0 - mod(uv, 2.0)); }
// the painting laid round him from three sides, blended by which way the skin faces
vec4 tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	return texture(veins, mirror(p.zy)) * w.x + texture(veins, mirror(p.xz)) * w.y + texture(veins, mirror(p.xy)) * w.z;
}
void fragment() {
	// the rim of a glassy skin, and the painted veins in it crawling slowly upward, filling with serum (pulsing)
	// as the tanks fill: the middle stays nearly clear so he reads through it
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec4 v = tri(lp * 0.8 + vec3(0.0, -TIME * 0.1, 0.0), ln);
	float vein = v.r;
	float crack = v.g;
	float pulse = 0.65 + 0.35 * sin(TIME * 5.0 - lp.y * 5.0);
	vec3 glass = vec3(0.85, 0.9, 0.95);
	vec3 serum = vec3(1.0, 0.26, 0.2);
	ALBEDO = mix(glass, serum, clamp(0.2 + vein * 1.2 * pulse + fill * 0.3, 0.0, 1.0));
	float a = rim * (0.2 + 0.25 * fill) + vein * (0.3 + 0.5 * fill) * pulse * (0.5 + 0.5 * rim) + crack * rim * 0.3;
	ALPHA = clamp(a, 0.0, 0.8) * amt;
}
"""
	return _ssh
