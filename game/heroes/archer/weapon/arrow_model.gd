class_name ArrowModel
extends RefCounted
## The archer's arrows as models, for the looks that show them (ArrowFx's flight, Frost Volley's rain, Arrow Storm).

## The arrows are Meshy models (tools/blender/prep_arrow.py, head toward -Z): "war" (black-shafted, barbed: his
## plain shots), "fire" (red-fletched: Fire Arrow, burning in flight), "frost" (the glacier arrow: an ice
## head and ice-blade fletching on a rimed shaft, Frost Volley's, FrostVolleyFx). A faint streak behind each so it reads from the high camera. Without the files, a shaft and head.
const ARROW_GLB := "res://game/heroes/archer/weapon/arrows/%s.glb"
const FIRE := Color(1.0, 0.45, 0.12)
const FROST := Color(0.55, 0.8, 1.0)
const STORM := Color(0.6, 0.75, 1.0)

static func make(kind: String, bare := false) -> Node3D:
	var root := Node3D.new()
	var path := ARROW_GLB % kind
	if ResourceLoader.exists(path):
		var m: Node3D = ResCache.inst(path)
		root.add_child(m)
	else:
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.014
		cm.bottom_radius = cm.top_radius
		cm.height = 0.72
		shaft.mesh = cm
		shaft.rotation_degrees = Vector3(90, 0, 0)
		shaft.material_override = Mats.mat(Color(0.28, 0.2, 0.12), 0.8)
		root.add_child(shaft)
		var head := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.0
		hm.bottom_radius = 0.035
		hm.height = 0.09
		head.mesh = hm
		head.rotation_degrees = Vector3(-90, 0, 0)
		head.position = Vector3(0, 0, -0.4)
		head.material_override = Mats.mat(Color(0.5, 0.5, 0.52), 0.35, 0.9)
		root.add_child(head)
	if bare:
		return root       # ArrowFx lays its own layers on it
	var col: Color = {"fire": FIRE, "frost": FROST}.get(kind, Color(0.9, 0.85, 0.7))
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.04 if kind != "war" else 0.022
	gm.bottom_radius = 0.0
	gm.height = 1.6 if kind != "war" else 1.1
	glow.mesh = gm
	glow.rotation_degrees = Vector3(90, 0, 0)
	glow.position = Vector3(0, 0, 0.75)
	glow.material_override = Mats.glow(col, 1.3 if kind != "war" else 0.5, 0.0, 0.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	if kind == "fire":
		Fx.aura(root, FIRE, 18, 0.5, 0.09, 0.35, 0.8, 0.06, 30.0, Vector3(0, 0, -0.3))
	return root
