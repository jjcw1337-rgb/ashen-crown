class_name PlagueFever
extends RefCounted
## What Blight and Fever look like on a foe (the Plague Doctor's shared mechanic; the rules are in plague.gd).
## Blight: the Meshy blight mark (a stone medallion with a glowing fly sigil, keyed off black) wheeling over the head,
## one per stack. Fever: the foe sweats a yellow-green vapour (the Mantaflow vapour book, PlagueSmoke), glows from
## inside and the Meshy ring of fever (light, sweat and steam, painted top-down) throbs on the ground round its feet,
## so everyone (the victim most of all) sees the danger. The nodes are the foe's own children, gone when it is.

const BLIGHT_COL := Color(0.62, 0.9, 0.28)
const FEVER_COL := Color(0.95, 0.85, 0.35)
const MARK_TEX := "res://game/heroes/plague/shared/blight_mark.png"
const MARK_SIZE := 0.3
## Fever's ring at the feet: a Meshy painting of a ring of feverish light, sweat and steam (game/heroes/plague/build/
## ground_decal.py keyed it off black)
const RING_TEX := "res://game/heroes/plague/shared/fever_ring_albedo.png"

static var _mark: StandardMaterial3D
static var _quad: QuadMesh

static func _mark_mesh() -> QuadMesh:
	if _quad != null:
		return _quad
	_mark = StandardMaterial3D.new()
	_mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var tex := PlagueVialFx._tex(MARK_TEX)
	if tex != null:
		_mark.albedo_texture = tex
	else:
		_mark.albedo_color = BLIGHT_COL
	_quad = QuadMesh.new()
	_quad.size = Vector2(MARK_SIZE, MARK_SIZE)
	_quad.material = _mark
	return _quad

## Shows `n` Blight stacks (0 removes them).
static func stacks(e: Node3D, n: int) -> void:
	if e == null or not is_instance_valid(e):
		return
	var old := e.get_node_or_null("pd_blight")
	if old != null:
		# out of the tree at once: a node only queued for freeing still holds the name, and the new one would be
		# renamed and never found again (its marks would stay up for good)
		e.remove_child(old)
		old.queue_free()
	if n <= 0:
		return
	var root := Pips.new()
	root.name = "pd_blight"
	var hgt: float = float(e.get("height")) if e.get("height") != null else 1.0
	root.position = Vector3(0, hgt * 2.0 + 0.5, 0)
	for i in n:
		var m := MeshInstance3D.new()
		m.mesh = _mark_mesh()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
	root.count = n
	e.add_child(root)

## The foe turns Feverish for `secs`.
static func fever(e: Node3D, secs: float) -> void:
	if e == null or not is_instance_valid(e):
		return
	var old := e.get_node_or_null("pd_fever")
	if old != null:
		e.remove_child(old)
		old.queue_free()
	var hgt: float = float(e.get("height")) if e.get("height") != null else 1.0
	var rad: float = float(e.get("radius")) if e.get("radius") != null else 0.5
	var root := Node3D.new()
	root.name = "pd_fever"
	e.add_child(root)
	# the Blight marks burst into it: a spray of feverish sparks where they wheeled
	Fx.burst(root, e.global_position + Vector3(0, hgt * 2.0 + 0.5, 0), FEVER_COL, 18, 2.6, 0.05, 0.6, true, -4.0)
	var sweat := PlagueSmoke.vapour(root, Color(FEVER_COL.r, FEVER_COL.g, FEVER_COL.b, 0.42), 12, 0.75, 1.3, 0.7, rad * 0.55 + 0.12, Vector3(0, hgt * 1.0, 0), FEVER_COL * 0.18)
	sweat.name = "sweat"
	var l := OmniLight3D.new()
	l.light_color = FEVER_COL
	l.light_energy = 0.9
	l.omni_range = 1.6 + rad
	l.position = Vector3(0, hgt * 1.0, 0)
	root.add_child(l)
	var halo := MeshInstance3D.new()
	var ring_tex := PlagueVialFx._tex(RING_TEX)
	if ring_tex != null:
		# the painted ring of fever on the ground round its feet, turning slowly and throbbing
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * (rad * 2.0 + 1.3)
		halo.mesh = pm
		var sm := ShaderMaterial.new()
		sm.shader = _ring_shader()
		sm.set_shader_parameter("tex", ring_tex)
		sm.set_shader_parameter("col", FEVER_COL)
		halo.material_override = sm
		halo.position = Vector3(0, 0.07, 0)
	else:
		var tm := TorusMesh.new()
		tm.inner_radius = rad + 0.25
		tm.outer_radius = rad + 0.32
		tm.rings = 40
		halo.mesh = tm
		halo.material_override = Mats.glow_unique(FEVER_COL, 1.6)
		halo.position = Vector3(0, 0.08, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var tw := root.create_tween().set_loops(int(ceil(secs / 0.6)))
	tw.tween_property(l, "light_energy", 0.3, 0.3)
	tw.tween_property(l, "light_energy", 0.9, 0.3)
	Fx._free_later(root, secs)

static var _rsh: Shader
static func _ring_shader() -> Shader:
	if _rsh != null:
		return _rsh
	_rsh = Shader.new()
	_rsh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 col : source_color;
void fragment() {
	vec2 p = UV - 0.5;
	float a = TIME * 0.35;
	vec2 q = vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y) + 0.5;
	vec4 c = texture(tex, q);
	float throb = 0.75 + 0.25 * sin(TIME * 6.0);
	ALBEDO = mix(c.rgb, col.rgb * dot(c.rgb, vec3(0.4, 0.45, 0.15)) * 1.6, 0.35) * (0.85 + 0.35 * throb);
	ALPHA = clamp(c.a * (0.65 + 0.35 * throb), 0.0, 1.0);
}
"""
	return _rsh

## The Blight marks wheel slowly over the head, bobbing.
class Pips extends Node3D:
	var count := 1
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		var i := 0
		var rr := 0.0 if count <= 1 else 0.26
		for c in get_children():
			var a := t * 1.6 + TAU * float(i) / maxf(count, 1)
			(c as Node3D).position = Vector3(cos(a) * rr, sin(t * 3.0 + i) * 0.04, sin(a) * rr)
			i += 1
