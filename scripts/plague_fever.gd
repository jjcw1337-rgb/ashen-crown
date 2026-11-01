class_name PlagueFever
extends RefCounted
## What Blight and Fever look like on a foe (the Plague Doctor's shared mechanic; the rules are in plague.gd).
## Blight: small sickly pips circling over the head, one per stack. Fever: the foe sweats a yellow-green vapour,
## glows from inside and a thin halo of feverish light pulses round it, so everyone (the victim most of all)
## sees the danger. The nodes are the foe's own children, gone when it is.

const BLIGHT_COL := Color(0.62, 0.9, 0.28)
const FEVER_COL := Color(0.95, 0.85, 0.35)

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
	root.position = Vector3(0, hgt * 2.0 + 0.45, 0)
	for i in n:
		var m := MeshInstance3D.new()
		m.mesh = Geo.sph(0.055, 8)
		m.material_override = Mats.glow(BLIGHT_COL, 2.2)
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
	var sweat := Fx.aura(root, Color(FEVER_COL.r, FEVER_COL.g, FEVER_COL.b, 0.45), 18, 0.5, 0.12, 1.1, 0.8, rad * 0.6 + 0.15, 40.0, Vector3(0, hgt * 1.1, 0), false)
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

## The Blight pips wheel slowly over the head.
class Pips extends Node3D:
	var count := 1
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		var i := 0
		for c in get_children():
			var a := t * 2.2 + TAU * float(i) / maxf(count, 1)
			(c as Node3D).position = Vector3(cos(a) * 0.22, sin(t * 4.0 + i) * 0.03, sin(a) * 0.22)
			i += 1
