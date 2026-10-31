class_name GroundItem
extends Node3D
## An item lying on the ground, with its 3D model, name label and rarity beam.

var item: Dictionary
var label: Label3D
var model: Node3D
var _t := 0.0
var _toss := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var hovered := false
var radius := 0.8

func setup(it: Dictionary, from: Vector3, to: Vector3) -> void:
	item = it
	_from = from
	_to = to
	global_position = from
	var slot: String = Data.BASES[it["base"]]["slot"]
	model = Models.item_model(it)
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(model)
	model.rotation_degrees = Models.ground_pose(slot)
	holder.position.y = Models.ground_lift(slot)
	holder.rotation.y = randf() * TAU
	var big := slot in ["ring", "amulet", "potion", "gold"]
	if big:
		holder.scale = Vector3.ONE * 1.6
	label = Label3D.new()
	label.text = it["name"]
	label.modulate = Data.RARITY_COLOR[int(it.get("rarity", 0))]
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 0.75, 0)
	label.visible = int(it.get("rarity", 0)) > 0 or slot == "gold" or slot == "material"
	add_child(label)
	if slot == "material":
		_material_glow(Data.BASES[it["base"]])
		return
	var r := int(it.get("rarity", 0))
	if r >= 2:
		var beam := MeshInstance3D.new()
		beam.mesh = Geo.cyl(0.12, 0.25, 4.0, 12)
		beam.material_override = Mats.glow(Data.RARITY_COLOR[r], 1.6, 1.2, 0.6)
		beam.position = Vector3(0, 2.0, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
	if r >= 1:
		var l := OmniLight3D.new()
		l.light_color = Data.RARITY_COLOR[r]
		l.light_energy = 0.5 if r == 1 else 1.0
		l.omni_range = 2.5
		l.position = Vector3(0, 0.5, 0)
		add_child(l)

## A Hollow Sloth's material on the ground: a tall beam and a pulsing light in its colour, and its
## element rising off it (embers, frost mist, sparks); the label in its colour.
var _light: OmniLight3D
func _material_glow(b: Dictionary) -> void:
	var col: Color = b["color"]
	label.modulate = col.lerp(Color.WHITE, 0.25)
	label.text = "✦ " + item["name"] + " ✦"
	var beam := MeshInstance3D.new()
	beam.mesh = Geo.cyl(0.1, 0.3, 6.0, 12)
	beam.material_override = Mats.glow(col, 2.2, 1.2, 0.6)
	beam.position = Vector3(0, 3.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.6
	_light.omni_range = 3.5
	_light.position = Vector3(0, 0.5, 0)
	add_child(_light)
	match b["kind"]:
		"ember": Fx.aura(self, Color(1.0, 0.45, 0.08, 0.9), 28, 0.9, 0.07, 1.3, 0.8, 0.12, 25.0, Vector3(0, 0.2, 0), false)
		"talon": Fx.aura(self, Color(0.7, 0.9, 1.0, 0.6), 18, 0.25, 0.22, 1.8, -0.05, 0.2, 80.0, Vector3(0, 0.15, 0))
		_: Fx.aura(self, Color(0.42, 0.28, 0.6), 22, 1.6, 0.05, 0.35, 0.0, 0.18, 180.0, Vector3(0, 0.2, 0))

func set_hover(h: bool, show_all: bool) -> void:
	hovered = h
	label.visible = h or show_all or int(item.get("rarity", 0)) > 0 or item["base"] == "gold" or Items.is_material(item)
	label.modulate.a = 1.0
	label.font_size = 44 if h else 36

func _process(delta: float) -> void:
	_t += delta
	if _light:
		_light.light_energy = 1.3 + 0.6 * sin(_t * 3.0) + 0.2 * sin(_t * 7.3)
	if _toss < 1.0:
		_toss = minf(1.0, _toss + delta * 1.8)
		var p := _from.lerp(_to, _toss)
		p.y += sin(_toss * PI) * 1.6
		global_position = p
		rotation.x = (1.0 - _toss) * 8.0
		if _toss >= 1.0:
			rotation.x = 0.0
			Sfx.play("drop", -6.0, randf_range(0.9, 1.2))
