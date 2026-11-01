class_name PlagueTransfusionFx
extends RefCounted
## Transfusion's look (the Plague Doctor's G; gameplay in plague.gd): his experimental apparatus.
##
## The apparatus is the Meshy model assets/models/plague/apparatus.glb (concept, image-to-3D, prep_prop.py: a riveted
## brass frame with two glass serum tanks, copper tubes, gauges, a harness and a needle on a hose), strapped to his
## back for the length of the skill: it unfolds onto him, the hose runs to his left forearm (`Hose`, redrawn each
## frame between the two bones), and as blows land the serum in the tanks rises and glows (`soak`: the tank lights
## and the shimmer round him grow with how full they are). A glassy shimmer (`SHELL_SHADER`: fresnel with flowing
## veins, sparking where hits land) shows everyone he is soaking damage. The end vents steam, drains the tubes and
## folds the apparatus away (`finish`); a healing pulse rises through him when what he soaked comes back.

const APP_GLB := "res://assets/models/plague/apparatus.glb"
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
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(shell)
	shell.position = Vector3(0, 1.0, 0)
	root.set_meta("shell", shell)
	var tw2 := shell.create_tween()
	tw2.tween_method(func(v: float) -> void: mat.set_shader_parameter("amt", v), 0.0, 1.0, 0.25)
	# the needle going in: a hiss and a burst of steam at his arm
	if J.has("at_hand_l"):
		Fx.burst(h.game.world.fx_root, (J["at_hand_l"] as Node3D).global_position, Color(0.9, 0.9, 0.95, 0.6), 12, 1.2, 0.12, 0.5, false, 0.5)
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
	Fx.burst(r, r.global_position + Vector3(0, 0.3, 0), Color(0.92, 0.92, 0.95, 0.55), 26, 1.8, 0.3, 1.0, false, 0.8, 50.0)
	if healed:
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

## The hose from the apparatus to his forearm: a sagging tube redrawn every frame, serum pulsing along it.
class Hose extends MeshInstance3D:
	var from_node: Node3D
	var to_node: Node3D
	var t := 0.0
	func _ready() -> void:
		mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.3
		m.emission_enabled = true
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
		for i in n + 1:
			var u := float(i) / n
			var p := a.lerp(b, u) + Vector3(0, -sin(u * PI) * 0.18, 0)
			var side := Vector3.RIGHT
			if cam != null:
				side = (cam.global_position - p).cross(b - a).normalized() * 0.012
			var pulse := 0.5 + 0.5 * sin(u * 18.0 - t * 14.0)
			var c := Color(0.35, 0.22, 0.12).lerp(PlagueTransfusionFx.SERUM, pulse * 0.8)
			im.surface_set_color(c)
			im.surface_add_vertex(p - side)
			im.surface_set_color(c)
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
varying vec3 lp;
void vertex() { lp = VERTEX; }
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	// only the rim of a glassy skin shows, veined, reddening as the tanks fill: the middle stays clear
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float veins = pow(1.0 - abs(noise(lp * 5.0 + vec3(0.0, -TIME * 1.5, 0.0)) * 2.0 - 1.0), 8.0);
	vec3 glass = vec3(0.85, 0.9, 0.95);
	vec3 serum = vec3(1.0, 0.35, 0.28);
	ALBEDO = mix(glass, serum, 0.35 + 0.65 * fill);
	ALPHA = clamp(rim * (0.35 + veins * 0.5 + fill * 0.3), 0.0, 0.7) * amt;
}
"""
	return _ssh
