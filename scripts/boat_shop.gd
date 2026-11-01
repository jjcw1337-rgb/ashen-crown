class_name BoatShop
extends RefCounted
## The shipwright's window (Osric Saltmarrow on the Mournwater Coast; Game._vendor_talk opens it): in the
## trade window's style, headed by his live portrait, name, trade and greeting and your purse; then the
## boat itself turning slowly on the water, its name, price, a short description, what it can do, how to
## sail it, and Buy (or "She's yours" once bought). Boats are Data.BOATS; owning one is Hero.boats (saved).
## Built once by UI (ui.boat_panel); open(it) fills it for a shipwright.

var ui
var panel: PanelContainer
var face: PanelContainer
var who: Label
var role: Label
var greet: Label
var purse: Label
var stage: SubViewportContainer
var vp: SubViewport
var turn: Node3D
var name_lbl: Label
var price_lbl: Label
var desc: Label
var stats: Label
var howto: Label
var buy_btn: Button
var boat_id := "gull"
var keeper: Inter

func build(u) -> PanelContainer:
	ui = u
	panel = ui._panel("Shipwright", true, 560, 700)
	panel.name = "boat_panel"
	var vb: VBoxContainer = panel.get_node("vb")
	var title: Label = vb.get_child(0).get_node("title")
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", ui.DIM)
	# the shipwright: portrait, name, trade, greeting, your purse
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	face = PanelContainer.new()
	face.add_theme_stylebox_override("panel", ui._box(Color(0.07, 0.05, 0.035), Color(0.62, 0.48, 0.26), 2, 4, 2))
	face.custom_minimum_size = Vector2(120, 140)
	head.add_child(face)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	head.add_child(info)
	who = ui._label("", 24, ui.GOLD, true)
	info.add_child(who)
	role = ui._label("", 13, Color(0.74, 0.66, 0.52))
	info.add_child(role)
	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.43, 0.24, 0.5)
	rule.custom_minimum_size = Vector2(0, 1)
	info.add_child(rule)
	greet = ui._label("", 14, Color(0.86, 0.82, 0.74))
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.custom_minimum_size = Vector2(300, 0)
	greet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(greet)
	var pbox := PanelContainer.new()
	pbox.add_theme_stylebox_override("panel", ui._box(Color(0.03, 0.025, 0.02, 0.9), Color(0.4, 0.31, 0.17), 1, 3, 6))
	info.add_child(pbox)
	purse = ui._label("", 17, Color(1.0, 0.85, 0.4), true)
	pbox.add_child(purse)
	# the boat on the water, turning slowly
	var sframe := PanelContainer.new()
	sframe.add_theme_stylebox_override("panel", ui._box(Color(0.05, 0.07, 0.08), Color(0.62, 0.48, 0.26), 2, 4, 0))
	vb.add_child(sframe)
	stage = SubViewportContainer.new()
	stage.stretch = true
	stage.custom_minimum_size = Vector2(520, 220)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sframe.add_child(stage)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
	vp.size = Vector2i(520, 220)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	stage.add_child(vp)
	# name, price, description, stats
	var nrow := HBoxContainer.new()
	vb.add_child(nrow)
	name_lbl = ui._label("", 26, ui.GOLD, true)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(name_lbl)
	price_lbl = ui._label("", 20, Color(1.0, 0.85, 0.4), true)
	nrow.add_child(price_lbl)
	desc = ui._label("", 15, Color(0.86, 0.82, 0.74))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(520, 0)
	vb.add_child(desc)
	stats = ui._label("", 14, Color(0.7, 0.8, 0.86))
	vb.add_child(stats)
	var hb := PanelContainer.new()
	hb.add_theme_stylebox_override("panel", ui._box(Color(0.04, 0.035, 0.03, 0.85), Color(0.35, 0.28, 0.17), 1, 3, 8))
	vb.add_child(hb)
	howto = ui._label("", 13, Color(0.8, 0.76, 0.68))
	howto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	howto.custom_minimum_size = Vector2(500, 0)
	hb.add_child(howto)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	brow.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(brow)
	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(110, 38)
	leave.pressed.connect(func():
		Sfx.play("click")
		close())
	brow.add_child(leave)
	buy_btn = Button.new()
	buy_btn.custom_minimum_size = Vector2(200, 38)
	buy_btn.pressed.connect(func(): _buy())
	brow.add_child(buy_btn)
	return panel

## Opens the window for a shipwright (his portrait and the boat he sells).
func open(it: Inter, id := "gull") -> void:
	keeper = it
	boat_id = id
	for c in face.get_children():
		c.queue_free()
	var pt := VendorUI.Portrait.new()
	face.add_child(pt)
	pt.setup(it)
	who.text = it.label
	role.text = VendorUI.title_for(it).to_upper()
	_stage()
	ui.trade_with = it
	panel.visible = true
	refresh()

func close() -> void:
	panel.visible = false

## Words, price, your purse and the button, from the boat and what the hero owns now.
func refresh() -> void:
	var spec: Dictionary = Data.BOATS[boat_id]
	var hero: Hero = ui.hero
	var owned: bool = hero != null and hero.owns_boat(boat_id)
	var price := int(spec["price"])
	var can: bool = hero != null and hero.gold >= price
	purse.text = "Your gold:  %d" % (hero.gold if hero else 0)
	name_lbl.text = str(spec["name"])
	price_lbl.text = "Yours" if owned else "%d gold" % price
	price_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6) if owned else (Color(1.0, 0.85, 0.4) if can else Color(1.0, 0.4, 0.3)))
	desc.text = str(spec["desc"])
	stats.text = "Speed %d  ·  Crew %d  ·  Reaches all five isles of the Mournwater" % [int(spec["speed"]), int(spec["crew"])]
	howto.text = "How to sail her:  click her at the end of the pier to go aboard.  W / S  sail on and ease off (or hold the left mouse button where you want to go),  A / D  steer,  Space  heave to.  Bring her alongside any island's jetty and press  E  (or click the jetty) to step ashore; she waits there for you and comes back with you to this pier."
	if owned:
		greet.text = "“She's yours, and she's a good one. Treat her kindly and she'll bring you home.”"
		buy_btn.text = "She's yours"
		buy_btn.disabled = true
	else:
		greet.text = "“Looking to cross the Mournwater? Nothing out there but the five isles and whatever lives on them, and the only way there is by boat. I've one finished, the best I've built.”" if can else "“She's not cheap, I'll grant you. Come back with %d gold and she's yours. The isles will keep.”" % price
		buy_btn.text = "Buy for %d gold" % price
		buy_btn.disabled = false

func _buy() -> void:
	var spec: Dictionary = Data.BOATS[boat_id]
	var hero: Hero = ui.hero
	if hero == null or hero.owns_boat(boat_id):
		return
	var price := int(spec["price"])
	if hero.gold < price:
		ui.message("Not enough gold", Color(1, 0.4, 0.3))
		Sfx.play("deny")
		refresh()
		return
	ui.game.buy_boat(boat_id)
	refresh()

## The little studio: the boat on a dark sea, lit warm from one side, turning slowly.
func _stage() -> void:
	for c in vp.get_children():
		c.queue_free()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 40, 0)
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 210, 0)
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.1
	vp.add_child(rim)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.04, 0.12, 0.15)
	sm.roughness = 0.12
	sm.metallic_specular = 0.7
	sea.material_override = sm
	vp.add_child(sea)
	turn = Node3D.new()
	vp.add_child(turn)
	var b := Boat.model(boat_id)
	turn.add_child(b)
	b.position = Vector3(0, -0.15, 0)
	var cam := Camera3D.new()
	cam.fov = 32
	vp.add_child(cam)
	var kk := float(Boat.dims(boat_id)["length"]) / Boat.LENGTH   # a bigger boat: the camera stands back
	cam.look_at_from_position(Vector3(13.0, 5.2, 0.0) * kk, Vector3(0, 2.4, 0) * kk)
	var spin := func(dt: float) -> void:
		if is_instance_valid(turn) and panel.visible:
			turn.rotation.y += dt * 0.35
			turn.position.y = sin(Time.get_ticks_msec() * 0.0012) * 0.06
			turn.rotation.z = sin(Time.get_ticks_msec() * 0.0009) * 0.03
	turn.set_meta("spin", spin)

## Called by UI every frame while open: turn the boat, follow the purse.
func tick(dt: float) -> void:
	if not panel.visible:
		return
	if turn and turn.has_meta("spin"):
		(turn.get_meta("spin") as Callable).call(dt)
