class_name PlagueFever
extends RefCounted
## What Blight and Fever look like on a foe (the Plague Doctor's shared mechanic; the rules are in plague.gd).
## Blight: the Meshy blight mark (a stone medallion with a glowing fly sigil, keyed off black) wheeling over the head,
## one per stack. Fever: the foe sweats a yellow-green vapour (the Mantaflow vapour book, PlagueSmoke), glows from
## inside and a thin halo of feverish light pulses round its feet, so everyone (the victim most of all) sees the
## danger. The nodes are the foe's own children, gone when it is.

const BLIGHT_COL := Color(0.62, 0.9, 0.28)
const FEVER_COL := Color(0.95, 0.85, 0.35)
const MARK_TEX := "res://assets/textures/plague/blight_mark.png"
const MARK_SIZE := 0.3

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
		old.queue_free()
	var hgt: float = float(e.get("height")) if e.get("height") != null else 1.0
	var rad: float = float(e.get("radius")) if e.get("radius") != null else 0.5
	var root := Node3D.new()
	root.name = "pd_fever"
	e.add_child(root)
	var sweat := PlagueSmoke.vapour(root, Color(FEVER_COL.r, FEVER_COL.g, FEVER_COL.b, 0.42), 12, 0.75, 1.3, 0.7, rad * 0.55 + 0.12, Vector3(0, hgt * 1.0, 0), FEVER_COL * 0.18)
	sweat.name = "sweat"
	var l := OmniLight3D.new()
	l.light_color = FEVER_COL
	l.light_energy = 0.9
	l.omni_range = 1.6 + rad
	l.position = Vector3(0, hgt * 1.0, 0)
	root.add_child(l)
	var halo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rad + 0.25
	tm.outer_radius = rad + 0.32
	tm.rings = 40
	halo.mesh = tm
	halo.material_override = Mats.glow_unique(FEVER_COL, 1.6)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, 0.08, 0)
	root.add_child(halo)
	var tw := root.create_tween().set_loops(int(ceil(secs / 0.6)))
	tw.tween_property(l, "light_energy", 0.3, 0.3)
	tw.tween_property(l, "light_energy", 0.9, 0.3)
	Fx._free_later(root, secs)

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
