class_name FurnaceUI
extends Control
## The furnace window (UI.open_furnace), in the inventory's iron frame beside the bag: the weapon to temper, the
## fire seen through the furnace mouth (coloured and sized by the heat, the weapon glowing in it, a ring for the
## soak), a thermometer with the five bands and the target, the fuel (what's in the bag, what's loaded, what the
## charge needs) and Ignite / Bellows / Quench. Right-click a weapon in the bag to put it before the fire, a log to
## load it (Shift: five). It reads and drives a Furnace (furnace.gd); it holds no state of its own.

const SIZE := Vector2(620, 590)
const SCALE := 0.26
const WOODS := ["oak_log", "pine_log", "heartwood"]

var ui: UI
var furnace: Furnace = null
var weapon_slot: Panel
var pick_row: HBoxContainer
var fire: FireView
var gauge: Gauge
var wname: Label
var wline: Label
var charge_lbl: Label
var status_lbl: Label
var fuel_rows := {}
var ignite_btn: Button
var bellows_btn: Button
var quench_btn: Button
var unload_btn: Button
var _flash := 0.0

func build(u: UI) -> void:
	ui = u
	custom_minimum_size = SIZE
	size = SIZE
	position = Vector2(24, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var trim := int(178 * SCALE)
	var iron := TextureRect.new()
	iron.texture = UI._scaled_tex(UI.INV_TEX["iron"], SCALE)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(trim, trim)
	iron.size = SIZE - Vector2(trim * 2, trim * 2 - 2)
	iron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(iron)
	var frame := NinePatchRect.new()
	frame.texture = UI._scaled_tex(UI.INV_TEX["frame"], SCALE)
	var pm := int(UI.INV_PATCH * SCALE)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		frame.set_patch_margin(side, pm)
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.draw_center = false
	frame.size = SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var plate := TextureRect.new()
	plate.texture = load(UI.INV_TEX["plate"])
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(170, 30)
	plate.position = Vector2((SIZE.x - 170) * 0.5, 11)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var title := ui._label("FURNACE", 14, UI.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = plate.position
	title.size = plate.size
	add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_color_override("font_color", Color(0.85, 0.7, 0.42))
	x.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	x.add_theme_font_size_override("font_size", 16)
	x.position = Vector2(SIZE.x * 0.5 + 92, 12)
	x.size = Vector2(28, 28)
	x.pressed.connect(func():
		visible = false
		Harvest.sfx().play("click"))
	add_child(x)

	# --- the weapon (left)
	var wl := ui._label("WEAPON", 12, UI.DIM, true)
	wl.position = Vector2(54, 62)
	add_child(wl)
	weapon_slot = ui._slot(Vector2(92, 92), func(_ev): pass, func(p, on): ui._hover(p, on, ""), "", true)
	weapon_slot.position = Vector2(44, 84)
	add_child(weapon_slot)
	wname = ui._label("", 14, UI.GOLD, true)
	wname.position = Vector2(30, 182)
	wname.size = Vector2(130, 40)
	wname.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wname)
	wline = ui._label("", 12, Color(1.0, 0.66, 0.34))
	wline.position = Vector2(26, 222)
	wline.size = Vector2(140, 76)
	wline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wline)
	var pl := ui._label("Or pick:", 11, UI.DIM)
	pl.position = Vector2(36, 300)
	add_child(pl)
	pick_row = HBoxContainer.new()
	pick_row.position = Vector2(34, 316)
	pick_row.add_theme_constant_override("separation", 4)
	add_child(pick_row)

	# --- the fire (middle)
	fire = FireView.new()
	fire.position = Vector2(176, 60)
	fire.size = Vector2(270, 290)
	fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fire)

	# --- the thermometer (right)
	gauge = Gauge.new()
	gauge.position = Vector2(470, 58)
	gauge.size = Vector2(110, 300)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gauge)

	# --- the fuel and the charge (bottom)
	var fl := ui._label("FUEL", 12, UI.DIM, true)
	fl.position = Vector2(44, 362)
	add_child(fl)
	for i in WOODS.size():
		var b: String = WOODS[i]
		var row := Control.new()
		row.position = Vector2(44 + i * 182, 382)
		row.size = Vector2(176, 52)
		add_child(row)
		var s := ui._slot(Vector2(48, 48), func(_ev): pass, func(p, on): ui._hover(p, on, ""), "", true)
		row.add_child(s)
		ui._set_slot(s, Items.resource(b, 1))
		var nm := ui._label(Data.BASES[b]["name"], 12, (Data.BASES[b]["color"] as Color).lerp(Color.WHITE, 0.4))
		nm.position = Vector2(54, 0)
		row.add_child(nm)
		var have := ui._label("", 11, UI.DIM)
		have.position = Vector2(54, 16)
		row.add_child(have)
		var b1 := _button("+1", Vector2(54, 30), Vector2(34, 20))
		b1.pressed.connect(func(): _load(b, 1))
		row.add_child(b1)
		var b5 := _button("+5", Vector2(92, 30), Vector2(34, 20))
		b5.pressed.connect(func(): _load(b, 5))
		row.add_child(b5)
		fuel_rows[b] = {"have": have, "b1": b1, "b5": b5, "slot": s}
	charge_lbl = ui._label("", 13, Color(0.9, 0.82, 0.66))
	charge_lbl.position = Vector2(44, 440)
	charge_lbl.size = Vector2(540, 20)
	add_child(charge_lbl)
	ignite_btn = _button("Ignite", Vector2(44, 468), Vector2(126, 34))
	ignite_btn.pressed.connect(_ignite)
	add_child(ignite_btn)
	bellows_btn = _button("Bellows (hold)", Vector2(178, 468), Vector2(150, 34))
	bellows_btn.button_down.connect(func(): if furnace: furnace.bellows = true)
	bellows_btn.button_up.connect(func(): if furnace: furnace.bellows = false)
	add_child(bellows_btn)
	quench_btn = _button("Quench", Vector2(336, 468), Vector2(126, 34))
	quench_btn.pressed.connect(_quench)
	add_child(quench_btn)
	unload_btn = _button("Unload", Vector2(470, 468), Vector2(106, 34))
	unload_btn.pressed.connect(func():
		if furnace:
			furnace.unload(ui.hero)
			Harvest.sfx().play("pickup")
			ui.refresh())
	add_child(unload_btn)
	status_lbl = ui._label("", 13, Color(0.82, 0.76, 0.64))
	status_lbl.position = Vector2(44, 512)
	status_lbl.size = Vector2(540, 22)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status_lbl)
	visibility_changed.connect(func():
		if not visible:
			if ui.shop_mode == "furnace":
				ui.shop_mode = ""
			if furnace != null and is_instance_valid(furnace):
				furnace.bellows = false
				furnace.abandon(ui.hero)
			ui.refresh())

func _button(t: String, at: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.position = at
	b.size = sz
	b.add_theme_font_size_override("font_size", 13)
	var sb := ui._box(Color(0.1, 0.07, 0.05, 0.95), Color(0.55, 0.4, 0.22), 1, 3, 4)
	var sh := ui._box(Color(0.2, 0.12, 0.06, 0.95), Color(0.95, 0.65, 0.3), 1, 3, 4)
	var sd := ui._box(Color(0.06, 0.05, 0.04, 0.8), Color(0.3, 0.25, 0.18), 1, 3, 4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_color_override("font_color", Color(0.95, 0.82, 0.6))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.34))
	return b

func open(f: Furnace) -> void:
	furnace = f
	# the weapon in hand comes to the fire first
	var w = ui.hero.equipment.get("weapon")
	if f.session == "idle" and w != null and Items.can_temper(w):
		f.choose(w)
	visible = true
	_refresh_picks()
	_refresh()

## Right-click in the bag while the furnace is open: a weapon before the fire, a log into the hopper.
func bag_click(idx: int, shift: bool) -> void:
	var it = ui.hero.inventory[idx]
	if it == null or furnace == null:
		return
	if Items.is_resource(it) and Data.BASES[it["base"]].has("fuel"):
		_load(str(it["base"]), 5 if shift else 1)
	elif Data.BASES[it["base"]]["slot"] == "weapon":
		_choose(it)
	else:
		ui.message("The furnace takes weapons and wood.", Color(1, 0.6, 0.35))
		Harvest.sfx().play("deny")

func _choose(it) -> void:
	var why := furnace.choose(it)
	if why != "":
		ui.message(why, Color(1, 0.6, 0.35))
		Harvest.sfx().play("deny")
	else:
		Harvest.sfx().play("equip", -4.0, 0.85)
	_refresh()

func _load(b: String, n: int) -> void:
	var got := furnace.load_fuel(ui.hero, b, n)
	if got <= 0:
		ui.message("No %s to load." % Data.BASES[b]["name"] if ui.hero.count_of(b) == 0 else "The hopper is full.", Color(1, 0.6, 0.35))
		Harvest.sfx().play("deny")
		return
	Harvest.snd("log_pickup", furnace.global_position + Vector3(0, 1, 0), -2.0, 0.9)
	fire.flare = 0.3
	ui.refresh()

func _ignite() -> void:
	var why := furnace.ignite(ui.hero)
	if why != "":
		ui.message(why, Color(1, 0.6, 0.35))
		Harvest.sfx().play("deny")
		return
	Harvest.sfx().play_at("fire_erupt", furnace.global_position + Vector3(0, 1, 0), -4.0, 0.8)
	Harvest.sfx().play("bonfire_open", -6.0, 0.85)
	fire.flare = 1.0
	ui.message("The fire takes. Bring it to %s heat." % str(furnace.cost["band"]).to_lower(), Color(1.0, 0.7, 0.35))
	ui.refresh()

func _quench() -> void:
	var it = furnace.item
	if it == null:
		return
	var ok := furnace.quench(ui.hero)
	var at: Vector3 = furnace.global_position + furnace.global_transform.basis * Vector3(-0.95, 0.4, 1.35)
	Harvest.sfx().play_at("ice_shatter", at, -10.0, 0.55)
	Harvest.sfx().play_at("fuse", at, -4.0, 0.6)
	var fxr: Node3D = ui.game.world.fx_root
	Fx.burst(fxr, at + Vector3(0, 0.3, 0), Color(0.85, 0.88, 0.9, 0.6), 30, 2.0, 0.6, 1.6, false, 1.2, 40.0, Vector3.UP)
	if ok:
		var lv := int(it.get("temper", 0))
		Harvest.sfx().play("levelup", -6.0, 0.8)
		Harvest.sfx().play_at("anvil", at, -2.0, 0.9)
		Fx.flash(fxr, at, Color(1.0, 0.6, 0.25), 5.0, 0.5, 6.0)
		ui.big_message("%s  ·  Tempered +%d" % [it["name"], lv])
		ui.message("The steel takes the temper: +%d%% damage, +%d damage." % [lv * Items.TEMPER_ED, lv], Color(1.0, 0.7, 0.35))
		_flash = 1.0
	else:
		Harvest.sfx().play("deny", -4.0, 0.7)
		ui.message("Quenched too soon. The steel didn't take the temper; the wood is spent.", Color(1, 0.55, 0.35))
	ui.hero.refresh_gear()
	ui.refresh()
	_refresh_picks()
	_refresh()

func _refresh_picks() -> void:
	for c in pick_row.get_children():
		c.queue_free()
	var cands := []
	var w = ui.hero.equipment.get("weapon")
	if w != null:
		cands.append(w)
	for it in ui.hero.inventory:
		if it != null and Data.BASES[it["base"]]["slot"] == "weapon":
			cands.append(it)
	for it in cands.slice(0, 3):
		var s := ui._slot(Vector2(40, 40), func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				_choose(it), func(p, on): ui._hover(p, on, ""), "", true)
		ui._set_slot(s, it)
		pick_row.add_child(s)

func _process(delta: float) -> void:
	if not visible or furnace == null or not is_instance_valid(furnace):
		return
	_flash = maxf(0.0, _flash - delta)
	_refresh()

func _refresh() -> void:
	var f := furnace
	var hero: Hero = ui.hero
	var it = f.item
	if not weapon_slot.has_meta("item") or weapon_slot.get_meta("item") != it:
		ui._set_slot(weapon_slot, it)
	if it == null:
		wname.text = "No weapon"
		wline.text = "Right-click a weapon in your bag, or pick one below."
	else:
		wname.text = ("+%d " % int(it.get("temper", 0)) if int(it.get("temper", 0)) > 0 else "") + str(it["name"])
		var n := int(f.cost["level"])
		var dn: Array = Items.damage_of(it)
		var nxt: Dictionary = it.duplicate(true)
		nxt["temper"] = n
		var dx: Array = Items.damage_of(nxt)
		wline.text = "Temper +%d → +%d\nDamage %d-%d → %d-%d\n%s heat, %.0f s soak" % [n - 1, n, dn[0], dn[1], dx[0], dx[1], f.cost["band"], float(f.cost["soak"])]
	for b in WOODS:
		var r: Dictionary = fuel_rows[b]
		(r["have"] as Label).text = "%d in bag · %d loaded" % [hero.count_of(b), f.hopper_count(b)]
		(r["b1"] as Button).disabled = hero.count_of(b) <= 0
		(r["b5"] as Button).disabled = hero.count_of(b) <= 0
	if it != null:
		var need_h := int(f.cost["heart"])
		charge_lbl.text = "Charge: %d / %d logs%s   ·   Fee: %d gold%s" % [f.hopper.size(), int(f.cost["logs"]),
			("   ·   Heartwood %d / %d" % [f.hopper.count("heartwood"), need_h]) if need_h > 0 else "", int(f.cost["gold"]),
			"   ·   Burning on: %d" % f.spent.size() if not f.spent.is_empty() else ""]
	else:
		charge_lbl.text = "Loaded: %d logs%s" % [f.hopper.size(), ("   ·   Burning on: %d" % f.spent.size()) if not f.spent.is_empty() else ""]
	ignite_btn.disabled = f.session != "ready"
	bellows_btn.disabled = not f.lit
	quench_btn.disabled = f.session != "heating"
	unload_btn.disabled = f.session == "heating" or f.hopper.is_empty()
	var need_t := float(f.cost.get("temp", 0.0)) if it != null else 0.0
	var soak_k := clampf(f.soak / maxf(0.1, float(f.cost.get("soak", 1.0))), 0.0, 1.0) if it != null else 0.0
	match f.session:
		"idle":
			status_lbl.text = "Choose a weapon to temper." if f.temp < 300.0 else "The fire burns on: %d °C." % int(f.temp)
		"ready":
			var m := f.missing(hero)
			if m == "" and int(f.cost["heart"]) > 0:
				m = "Charged. Wood burns in the order loaded: oak first to raise the fire, then the Heartwood."
			status_lbl.text = m if m != "" else "Charged. Ignite the furnace."
		"heating":
			if soak_k >= 1.0:
				status_lbl.text = "It's taken the heat. Quench it now!"
			elif f.temp >= need_t:
				status_lbl.text = "Soaking in the heat: %d%%  (keep it at %d °C or more)" % [int(soak_k * 100.0), int(need_t)]
			elif not f.lit:
				status_lbl.text = "The fire has died. Load more wood, or quench (it will fail)."
			else:
				var cap := f.fuel_cap()
				if cap < need_t:
					status_lbl.text = "This wood can't burn that hot (it stops at %d °C). It needs %s." % [int(cap), "Ashen Heartwood" if need_t > 1240.0 else "oak"]
				else:
					status_lbl.text = "Heating: %d °C of %d °C. Work the bellows to push it." % [int(f.temp), int(need_t)]
	fire.heat = f.heat01()
	fire.col = Furnace.heat_color(f.temp)
	fire.lit = f.lit
	fire.soak = soak_k if it != null and f.session == "heating" else -1.0
	fire.item_tex = (weapon_slot.get_node("icon") as TextureRect).texture if f.session == "heating" else null
	fire.glow = clampf((f.temp - 450.0) / 950.0, 0.0, 1.0) * (0.35 + 0.65 * soak_k)
	fire.done = _flash
	gauge.temp = f.temp
	gauge.target = need_t
	gauge.cap = f.fuel_cap() if f.lit else 0.0
	gauge.queue_redraw()

# ---------------------------------------------------------------- the fire through the mouth
class FireView extends Control:
	var heat := 0.0
	var col := Color(1, 0.4, 0.1)
	var lit := false
	var soak := -1.0
	var glow := 0.0
	var flare := 0.0
	var done := 0.0
	var item_tex: Texture2D = null
	var _rect: ColorRect
	var _t := 0.0
	func _ready() -> void:
		_rect = ColorRect.new()
		_rect.position = Vector2(30, 34)
		_rect.size = size - Vector2(60, 64)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = MOUTH_SHADER
		m.shader = sh
		_rect.material = m
		add_child(_rect)
		_front = Control.new()
		_front.set_anchors_preset(Control.PRESET_FULL_RECT)
		_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_front.draw.connect(_draw_front)
		add_child(_front)
	var _front: Control
	func _process(delta: float) -> void:
		_t += delta
		flare = maxf(0.0, flare - delta * 1.5)
		var m := _rect.material as ShaderMaterial
		m.set_shader_parameter("heat", clampf(heat + flare * 0.15, 0.0, 1.0))
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("lit", 1.0 if lit else 0.0)
		queue_redraw()
		_front.queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# the stone arch round the mouth
		var stone := Color(0.22, 0.2, 0.18)
		var dark := Color(0.08, 0.07, 0.065)
		draw_rect(Rect2(0, 0, w, h), dark)
		for row in 9:
			for k in 6:
				var bx := k * w / 5.0 - (w / 10.0 if row % 2 == 1 else 0.0)
				var by := row * h / 9.0
				var r := Rect2(bx + 2, by + 2, w / 5.0 - 4, h / 9.0 - 4)
				var shade := 0.85 + fmod(float(row * 7 + k * 13), 5.0) * 0.05
				draw_rect(r, stone * shade)
		# the opening: a lit rim round where the fire (the shader rect, drawn over this) burns
		var o := Rect2(30, 34, w - 60, h - 64)
		var rim := col * clampf(heat * 1.8, 0.0, 1.0)
		draw_rect(o.grow(4), Color(rim.r, rim.g, rim.b, 0.35 * heat + 0.05), false, 4.0)
	## Over the fire: the weapon in the heat, its glow, the soak ring, a flash on success, embers.
	func _draw_front() -> void:
		var w := size.x
		var h := size.y
		var o := Rect2(30, 34, w - 60, h - 64)
		# the weapon held in the heat
		if item_tex != null:
			var s := Vector2(96, 96)
			var c := o.get_center() + Vector2(0, 18)
			_front.draw_texture_rect(item_tex, Rect2(c - s * 0.5, s), false, Color(0.55, 0.5, 0.48, 1))
			if glow > 0.01:
				_front.draw_texture_rect(item_tex, Rect2(c - s * 0.5, s), false, Color(col.r * 2.0, col.g * 1.6, col.b * 1.2, glow * 0.9))
		# the soak ring
		if soak >= 0.0:
			var c2 := o.get_center() + Vector2(0, 18)
			_front.draw_arc(c2, 62, 0, TAU, 48, Color(0, 0, 0, 0.45), 6.0)
			_front.draw_arc(c2, 62, -PI * 0.5, -PI * 0.5 + TAU * soak, 48, Color(1.0, 0.75, 0.35, 0.95) if soak < 1.0 else Color(1.0, 0.95, 0.75), 6.0)
		if done > 0.0:
			_front.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.75, 0.4, done * 0.35))
		# embers drifting up over the stone
		if heat > 0.25:
			for e in 18:
				var ph := fmod(_t * (0.25 + fmod(e * 0.37, 0.3)) + e * 0.173, 1.0)
				var ex := o.position.x + fmod(e * 37.7, o.size.x) + sin(_t * 2.0 + e) * 8.0
				var ey := o.end.y - ph * (h * 0.9)
				_front.draw_circle(Vector2(ex, ey), 1.6 + heat, Color(col.r, col.g * 0.9, col.b * 0.6, (1.0 - ph) * heat))

	const MOUTH_SHADER := """
shader_type canvas_item;
uniform float heat = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.4, 0.1);
uniform float lit = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fbm(vec2 p){ float a = 0.5; float s = 0.0; for (int i = 0; i < 5; i++) { s += vn(p) * a; p *= 2.02; a *= 0.5; } return s; }
void fragment(){
	vec2 uv = UV;
	float y = 1.0 - uv.y;
	float t = TIME * (1.2 + heat * 2.0);
	// heat shimmer: the whole view wavers more as it gets hotter
	uv.x += (vn(vec2(uv.y * 8.0, TIME * 3.0)) - 0.5) * 0.02 * heat;
	float n = fbm(vec2(uv.x * 4.0, y * 3.0 - t));
	float tall = 0.15 + heat * 0.95 * (0.4 + 0.6 * lit);
	float flame = smoothstep(tall, tall * 0.2, y + n * 0.45 - 0.05);
	float coals = smoothstep(0.22, 0.0, y) * (0.55 + 0.45 * vn(vec2(uv.x * 14.0, TIME * 0.6)));
	float core = flame * smoothstep(0.4, 0.95, n + (1.0 - y) * 0.35);
	vec3 base = vec3(0.025, 0.02, 0.018);
	vec3 c = base;
	c += col * flame * (0.5 + heat) * 1.3;
	c += vec3(1.0, 0.95, 0.85) * core * core * heat * 1.2;
	c += col * coals * clamp(heat * 2.0, 0.0, 1.0) * 1.4;
	// the back of the firebox, lit
	c += col * 0.12 * heat * (1.0 - y);
	COLOR = vec4(c, 1.0);
}
"""

# ---------------------------------------------------------------- the thermometer
class Gauge extends Control:
	var temp := 20.0
	var target := 0.0
	var cap := 0.0
	func _ty(t: float) -> float:
		var top := 18.0
		var bot := size.y - 30.0
		return lerpf(bot, top, clampf((t - 20.0) / (Furnace.MAX_T - 20.0), 0.0, 1.0))
	func _draw() -> void:
		var x := 18.0
		var bw := 22.0
		var top := _ty(Furnace.MAX_T)
		var bot := _ty(20.0)
		# the tube: a dark well, the bands painted beside it
		draw_rect(Rect2(x - 3, top - 3, bw + 6, bot - top + 6), Color(0.1, 0.08, 0.06))
		draw_rect(Rect2(x, top, bw, bot - top), Color(0.03, 0.025, 0.02))
		var steps := 60
		for i in steps:
			var t0 := 20.0 + (Furnace.MAX_T - 20.0) * i / float(steps)
			var t1 := 20.0 + (Furnace.MAX_T - 20.0) * (i + 1) / float(steps)
			if t0 > temp:
				break
			var y0 := _ty(minf(t1, temp))
			var y1 := _ty(t0)
			draw_rect(Rect2(x + 3, y0, bw - 6, y1 - y0 + 0.5), Furnace.heat_color(maxf(t0, 420.0)))
		# the bulb
		draw_circle(Vector2(x + bw * 0.5, bot + 12), 13, Color(0.1, 0.08, 0.06))
		draw_circle(Vector2(x + bw * 0.5, bot + 12), 10, Furnace.heat_color(maxf(temp, 420.0)) if temp > 200.0 else Color(0.2, 0.06, 0.03))
		# band ticks and names
		var f := ThemeDB.fallback_font
		for i in Items.TEMPER_BANDS.size():
			var bt: float = Items.TEMPER_BANDS[i]
			var y := _ty(bt)
			var on := temp >= bt
			var c := Furnace.heat_color(bt + 1.0)
			draw_line(Vector2(x + bw + 2, y), Vector2(x + bw + 10, y), c, 2.0)
			draw_string(f, Vector2(x + bw + 13, y + 4), "+%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c if on else c.darkened(0.5))
			draw_string(f, Vector2(x + bw + 34, y + 4), "%d°" % int(bt), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.64, 0.55) if on else Color(0.45, 0.4, 0.34))
		# the target, and the most this fuel can give
		if target > 0.0:
			var yt := _ty(target)
			draw_line(Vector2(x - 8, yt), Vector2(x + bw + 8, yt), Color(1.0, 0.92, 0.6), 2.0)
			draw_string(f, Vector2(x - 16, yt - 4), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.6))
		if cap > 20.0 and cap < Furnace.MAX_T:
			var yc := _ty(cap)
			for k in 4:
				draw_line(Vector2(x + k * 6, yc), Vector2(x + k * 6 + 3, yc), Color(0.6, 0.75, 1.0, 0.8), 1.5)
		draw_string(f, Vector2(0, size.y - 2), "%d °C" % int(temp), HORIZONTAL_ALIGNMENT_LEFT, int(size.x), 15, Furnace.heat_color(maxf(temp, 500.0)).lerp(Color.WHITE, 0.3))
