class_name UI
extends CanvasLayer
## HUD, panels, tooltips and menus.

var game: Node
var hero: Hero
var icons: IconRenderer
var theme_: Theme
var font_title: Font
var font_body: Font

const GOLD := Color(0.86, 0.72, 0.44)
const PANEL_BG := Color(0.055, 0.05, 0.045, 0.95)
const BORDER := Color(0.42, 0.33, 0.2)
const DIM := Color(0.62, 0.58, 0.52)
const CELL := 44

var root: Control
var life_orb: ColorRect
var mana_orb: ColorRect
var life_lbl: Label
var mana_lbl: Label
var xp_bar: HudBar
var stamina_bar: HudBar
var level_medal: HudBar.Medallion
var action_bar: Control
var bar_style := "A"
var skill_slots: Array = []
var belt_slots: Array = []
var target_box: PanelContainer
var target_name: Label
var target_bar: ProgressBar
var zone_lbl: Label
var fps_lbl: Label
var msg_lbl: Label
var msg_t := 0.0
var big_lbl: Label
var big_t := 0.0
var hint_lbl: Label
var dmg_flash: ColorRect
var tooltip: PanelContainer
var tip_box: VBoxContainer
var tip_owner: Control = null

var inv_panel: PanelContainer
var inv_cells: Array = []
var ench_panel: PanelContainer
var ench_rows := {}
var ench_gold: Label
# dragging an inventory item: press, move a few pixels, release over a slot or the world
var drag_idx := -1
var drag_from := Vector2.ZERO
var dragging := false
var drag_ghost: TextureRect
var drag_hint: Label
var drag_hold := false   # tests/screenshots: keep a drag going without a real mouse button
var equip_cells := {}
var gold_lbl: Label
var char_panel: PanelContainer
var char_labels := {}
var plus_btns: Array = []
var shop_panel: PanelContainer
var shop_title: Label
var shop_grid: GridContainer
var shop_items: Array = []
var shop_mode := ""
var stash_panel: PanelContainer
var stash_cells: Array = []
var wp_panel: PanelContainer
var wp_list: VBoxContainer
var dialog_panel: PanelContainer
var dialog_name: Label
var dialog_text: Label
var dialog_btns: HBoxContainer
var gfx_info: Label
var pause_panel: PanelContainer
var gfx_btn: Button
var title_panel: Control
var sound_btn: Button
var join_panel: PanelContainer
var join_list: VBoxContainer
var join_ip: LineEdit
var join_hint: Label
var _join_refresh := 0.0
var death_panel: Control
var victory_panel: Control
var boss_bar_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var boss_ref = null
var minimap: Control
var show_fps := false

func setup(g: Node) -> void:
	game = g
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	icons = IconRenderer.new()
	add_child(icons)
	font_title = _font(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"], 600)
	font_body = _font(["Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "Times New Roman", "serif"], 400)
	theme_ = _make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_
	add_child(root)
	dmg_flash = ColorRect.new()
	dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = "shader_type canvas_item; void fragment(){ vec2 uv = UV - 0.5; uv.x *= 1.4; float v = smoothstep(0.35, 0.8, length(uv)); COLOR = vec4(0.55, 0.0, 0.0, v * COLOR.a * 1.6); }"
	fm.shader = fsh
	dmg_flash.material = fm
	root.add_child(dmg_flash)
	_build_hud()
	_build_inventory()
	_build_character()
	_build_shop()
	_build_stash()
	_build_waypoints()
	_build_dialog()
	_build_pause()
	_build_tooltip()
	_build_title()
	_build_join()
	_build_enchant()
	_build_death()
	_build_victory()

func bind_hero(h: Hero) -> void:
	hero = h
	if not h.stats_changed.is_connected(refresh):
		h.stats_changed.connect(refresh)
	refresh()

func _font(names: Array, weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f

func _box(bg: Color, border: Color, bw: int = 2, radius: int = 2, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	return sb

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, BORDER, 2, 2, 14))
	t.set_stylebox("panel", "Panel", _box(PANEL_BG, BORDER, 2, 2, 0))
	var bn := _box(Color(0.13, 0.1, 0.07), Color(0.5, 0.38, 0.22), 2, 2, 8)
	bn.shadow_size = 0
	var bh := _box(Color(0.22, 0.16, 0.09), Color(0.8, 0.62, 0.34), 2, 2, 8)
	bh.shadow_size = 0
	var bp := _box(Color(0.08, 0.06, 0.04), Color(0.8, 0.62, 0.34), 2, 2, 8)
	bp.shadow_size = 0
	var bd := _box(Color(0.08, 0.07, 0.06), Color(0.25, 0.22, 0.18), 2, 2, 8)
	bd.shadow_size = 0
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(0.9, 0.75, 0.45), 1, 2, 8))
	t.set_color("font_color", "Button", GOLD)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.9, 0.65))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.37, 0.32))
	t.set_font("font", "Button", font_title)
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Label", Color(0.86, 0.83, 0.77))
	var pbg := _box(Color(0.03, 0.03, 0.03, 0.9), Color(0.3, 0.24, 0.15), 1, 1, 0)
	pbg.shadow_size = 0
	t.set_stylebox("background", "ProgressBar", pbg)
	return t

func _label(text: String, size: int = 16, col := Color(0.86, 0.83, 0.77), title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if title:
		l.add_theme_font_override("font", font_title)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _bar(col: Color, h: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, h)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	pb.add_theme_stylebox_override("fill", fill)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb

# ---------------------------------------------------------------- slots
func _slot(size: Vector2, on_click: Callable, on_hover: Callable, placeholder := "") -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	var sb := _box(Color(0.03, 0.03, 0.03, 0.85), Color(0.25, 0.2, 0.13), 1, 1, 0)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	var tr := TextureRect.new()
	tr.name = "icon"
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 2
	tr.offset_top = 2
	tr.offset_right = -2
	tr.offset_bottom = -2
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	var ph := _label(placeholder, 11, Color(0.35, 0.32, 0.28))
	ph.name = "ph"
	ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(ph)
	var cnt := _label("", 13, Color(1, 1, 1))
	cnt.name = "count"
	cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cnt.offset_left = -24
	cnt.offset_top = -20
	cnt.offset_right = -3
	cnt.offset_bottom = -1
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(cnt)
	p.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			if (p.get_node("icon") as TextureRect).texture != null and (ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				click_fx(p)
			on_click.call(ev))
	p.mouse_entered.connect(func(): on_hover.call(p, true))
	p.mouse_exited.connect(func(): on_hover.call(p, false))
	return p

## Little "pop" when an item is clicked: the icon bounces, the slot flashes, gold sparks fly.
func click_fx(p: Control) -> void:
	var tr: TextureRect = p.get_node_or_null("icon")
	if tr:
		tr.pivot_offset = tr.size * 0.5
		var tw := create_tween()
		tw.tween_property(tr, "scale", Vector2(1.28, 1.28), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(tr, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fl := ColorRect.new()
	fl.color = Color(1.0, 0.9, 0.6, 0.45)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(fl)
	var tf := create_tween()
	tf.tween_property(fl, "color:a", 0.0, 0.25)
	tf.tween_callback(fl.queue_free)
	var c := p.get_global_rect().get_center() - root.get_global_rect().position
	for i in 10:
		var sp := ColorRect.new()
		sp.size = Vector2(4, 4)
		sp.color = Color(1.0, 0.82, 0.35) if i % 2 == 0 else Color(1.0, 0.96, 0.8)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.position = c - Vector2(2, 2)
		sp.rotation = randf() * TAU
		root.add_child(sp)
		var a := TAU * i / 10.0 + randf_range(-0.2, 0.2)
		var dist := randf_range(22.0, 38.0)
		var ts := create_tween().set_parallel(true)
		ts.tween_property(sp, "position", sp.position + Vector2(cos(a), sin(a)) * dist, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ts.tween_property(sp, "modulate:a", 0.0, 0.32).set_delay(0.08)
		ts.tween_property(sp, "scale", Vector2(0.3, 0.3), 0.32)
		ts.chain().tween_callback(sp.queue_free)
	Sfx.play("click", -10.0, randf_range(1.1, 1.3))

func _set_slot(p: Panel, it) -> void:
	var tr: TextureRect = p.get_node("icon")
	var ph: Label = p.get_node("ph")
	var cnt: Label = p.get_node("count")
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	if it == null:
		tr.texture = null
		ph.visible = true
		cnt.text = ""
		sb.bg_color = Color(0.03, 0.03, 0.03, 0.85)
		sb.border_color = Color(0.25, 0.2, 0.13)
		p.set_meta("item", null)
		return
	ph.visible = false
	p.set_meta("item", it)
	var c := int(it.get("count", 1))
	cnt.text = str(c) if c > 1 and it["base"] != "gold" else ""
	var r := int(it.get("rarity", 0))
	sb.bg_color = [Color(0.04, 0.04, 0.04, 0.9), Color(0.03, 0.04, 0.1, 0.9), Color(0.09, 0.08, 0.02, 0.9), Color(0.09, 0.06, 0.03, 0.9)][r]
	sb.border_color = Color(0.25, 0.2, 0.13) if r == 0 else (Data.RARITY_COLOR[r] as Color).darkened(0.35)
	var tex := icons.get_icon(it, func(t):
		if is_instance_valid(p) and p.get_meta("item", null) == it:
			tr.texture = t)
	tr.texture = tex

func _hover(p: Control, on: bool, mode: String) -> void:
	if not on:
		if tip_owner == p:
			tooltip.visible = false
			tip_owner = null
		return
	var it = p.get_meta("item", null)
	if it == null:
		tooltip.visible = false
		return
	show_tooltip(Items.tooltip(it, hero.level if hero else 99, mode))
	tip_owner = p

func show_tooltip(lines: Array) -> void:
	for c in tip_box.get_children():
		c.queue_free()
	var first := true
	for ln in lines:
		var l := _label(ln[0], 18 if first else 15, ln[1], first)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip_box.add_child(l)
		first = false
	tooltip.visible = true
	tooltip.reset_size()

func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	var sb := _box(Color(0.02, 0.02, 0.02, 0.94), Color(0.35, 0.28, 0.18), 1, 2, 10)
	tooltip.add_theme_stylebox_override("panel", sb)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip.z_index = 100
	tip_box = VBoxContainer.new()
	tip_box.add_theme_constant_override("separation", 1)
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tip_box)
	root.add_child(tooltip)

# ---------------------------------------------------------------- HUD
func _orb(col: Color, col2: Color) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(150, 150)
	var m := ShaderMaterial.new()
	m.shader = Mats.shader("orb")
	m.set_shader_parameter("liquid", col)
	m.set_shader_parameter("liquid2", col2)
	m.set_shader_parameter("fill", 1.0)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _orb_frame(orb: ColorRect, left: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(176, 176)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.045, 0.04)
	sb.set_corner_radius_all(88)
	sb.border_color = Color(0.5, 0.4, 0.25)
	sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 12
	ring.add_theme_stylebox_override("panel", sb)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ring)
	holder.add_child(orb)
	orb.position = Vector2(13, 13)
	orb.size = Vector2(150, 150)
	return holder

func _build_hud() -> void:
	# bottom bar
	var bottom := Control.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	life_orb = _orb(Color(0.85, 0.06, 0.04), Color(0.35, 0.0, 0.0))
	var lf := _orb_frame(life_orb, true)
	lf.position = Vector2(14, 6)
	bottom.add_child(lf)
	mana_orb = _orb(Color(0.15, 0.3, 1.0), Color(0.02, 0.04, 0.3))
	var mf := _orb_frame(mana_orb, false)
	mf.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mf.position = Vector2(-190, 6)
	bottom.add_child(mf)
	mf.anchor_left = 1.0
	mf.anchor_right = 1.0
	mf.offset_left = -190
	mf.offset_right = -14
	life_lbl = _label("", 14, Color(1, 0.85, 0.8))
	life_lbl.position = Vector2(34, 166)
	life_lbl.custom_minimum_size = Vector2(140, 0)
	life_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(life_lbl)
	mana_lbl = _label("", 14, Color(0.8, 0.85, 1))
	mana_lbl.anchor_left = 1.0
	mana_lbl.anchor_right = 1.0
	mana_lbl.offset_left = -172
	mana_lbl.offset_right = -32
	mana_lbl.offset_top = 166
	mana_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(mana_lbl)
	# centre action bar
	var ua := OS.get_cmdline_user_args()
	var si := ua.find("--barstyle")
	if si >= 0 and si + 1 < ua.size():
		bar_style = ua[si + 1]
	var royal := bar_style == "B"
	var bh := 176 if royal else 156
	var frame := HudBar.Frame.new()
	frame.crest = royal
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -360
	frame.offset_right = 360
	frame.offset_top = -bh - 10
	frame.offset_bottom = -10
	root.add_child(frame)
	action_bar = frame
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 18
	vb.offset_right = -18
	vb.offset_top = 16 if not royal else 34
	vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 9)
	frame.add_child(vb)
	xp_bar = HudBar.new()
	xp_bar.title = "EXPERIENCE"
	xp_bar.tooltip_text = "Experience: fill it to gain a level"
	stamina_bar = HudBar.new()
	stamina_bar.title = "STAMINA"
	stamina_bar.icon = "bolt"
	stamina_bar.ticks = 0
	stamina_bar.tooltip_text = "Stamina: hold Shift to sprint"
	stamina_bar.col_lo = Color(0.03, 0.38, 0.16)
	stamina_bar.col_hi = Color(0.38, 0.95, 0.45)
	stamina_bar.glow = Color(0.55, 1.0, 0.6)
	if royal:
		xp_bar.custom_minimum_size = Vector2(0, 20)
		xp_bar.col_lo = Color(0.5, 0.28, 0.03)
		xp_bar.col_hi = Color(1.0, 0.82, 0.32)
		xp_bar.glow = Color(1.0, 0.85, 0.4)
		stamina_bar.custom_minimum_size = Vector2(0, 18)
		level_medal = HudBar.Medallion.new()
		level_medal.size = Vector2(96, 96)
		level_medal.position = Vector2(360 - 48, -62)
		frame.add_child(level_medal)
	else:
		xp_bar.custom_minimum_size = Vector2(0, 22)
		xp_bar.icon = "star"
		xp_bar.col_lo = Color(0.3, 0.1, 0.58)
		xp_bar.col_hi = Color(0.75, 0.5, 1.0)
		xp_bar.glow = Color(0.85, 0.65, 1.0)
		stamina_bar.custom_minimum_size = Vector2(0, 20)
	vb.add_child(xp_bar)
	if not royal:
		vb.add_child(stamina_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	for i in 4:
		var sk: Dictionary = Data.SKILLS[i]
		var s := _skill_slot(sk)
		hb.add_child(s)
		skill_slots.append(s)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(28, 0)
	hb.add_child(sep)
	for i in 4:
		var idx := i
		var b := _slot(Vector2(60, 60), func(ev): if ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT: hero.drink(idx), func(p, on): _hover(p, on, ""), str(i + 1))
		b.add_child(_keycap(str(i + 1)))
		hb.add_child(b)
		belt_slots.append(b)
	if royal:
		vb.add_child(stamina_bar)
	# top: zone, fps, target, messages
	zone_lbl = _label("", 20, GOLD, true)
	zone_lbl.position = Vector2(20, 14)
	root.add_child(zone_lbl)
	fps_lbl = _label("", 14, Color(0.7, 0.9, 0.6))
	fps_lbl.anchor_left = 1.0
	fps_lbl.anchor_right = 1.0
	fps_lbl.offset_left = -120
	fps_lbl.offset_top = 14
	root.add_child(fps_lbl)
	target_box = PanelContainer.new()
	target_box.anchor_left = 0.5
	target_box.anchor_right = 0.5
	target_box.offset_left = -170
	target_box.offset_right = 170
	target_box.offset_top = 12
	target_box.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.03, 0.85), Color(0.3, 0.24, 0.15), 1, 2, 6))
	target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_box.add_child(tv)
	target_name = _label("", 17, Color(1, 1, 1), true)
	target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(target_name)
	target_bar = _bar(Color(0.65, 0.05, 0.03), 8)
	tv.add_child(target_bar)
	target_box.visible = false
	root.add_child(target_box)
	boss_bar_box = VBoxContainer.new()
	boss_bar_box.anchor_left = 0.5
	boss_bar_box.anchor_right = 0.5
	boss_bar_box.offset_left = -300
	boss_bar_box.offset_right = 300
	boss_bar_box.offset_top = 78
	boss_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_lbl = _label("", 22, Color(0.85, 0.66, 0.38), true)
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_box.add_child(boss_lbl)
	boss_bar = _bar(Color(0.6, 0.03, 0.02), 14)
	boss_bar_box.add_child(boss_bar)
	boss_bar_box.visible = false
	root.add_child(boss_bar_box)
	msg_lbl = _label("", 20, Color(1, 1, 1), true)
	msg_lbl.anchor_left = 0.5
	msg_lbl.anchor_right = 0.5
	msg_lbl.offset_left = -400
	msg_lbl.offset_right = 400
	msg_lbl.anchor_top = 0.62
	msg_lbl.anchor_bottom = 0.62
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg_lbl)
	big_lbl = _label("", 42, GOLD, true)
	big_lbl.anchor_left = 0.5
	big_lbl.anchor_right = 0.5
	big_lbl.offset_left = -600
	big_lbl.offset_right = 600
	big_lbl.anchor_top = 0.2
	big_lbl.anchor_bottom = 0.2
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_lbl.add_theme_constant_override("outline_size", 8)
	root.add_child(big_lbl)
	hint_lbl = _label("", 14, DIM)
	hint_lbl.anchor_left = 0.5
	hint_lbl.anchor_right = 0.5
	hint_lbl.anchor_top = 1.0
	hint_lbl.anchor_bottom = 1.0
	hint_lbl.offset_left = -400
	hint_lbl.offset_right = 400
	hint_lbl.offset_top = -bh - (88 if bar_style == "B" else 40)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.text = "Click: move/attack  ·  Space: swing  ·  Shift: sprint  ·  Right-click: block  ·  QERF: skills  ·  1-4: potions  ·  I/C: inventory/stats  ·  T: portal  ·  Tab: map"
	root.add_child(hint_lbl)
	minimap = Minimap.new()
	minimap.ui = self
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -230
	minimap.offset_right = -18
	minimap.offset_top = 40
	minimap.offset_bottom = 252
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.set_big(false)
	root.add_child(minimap)

## Small gold key-cap in a slot's corner showing its hotkey.
func _keycap(k: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", _box(Color(0.12, 0.09, 0.05, 0.95), Color(0.8, 0.62, 0.32), 1, 3, 0))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.position = Vector2(-5, -6)
	cap.custom_minimum_size = Vector2(17, 17)
	var l := _label(k, 12, Color(1.0, 0.88, 0.55), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap

func _skill_slot(sk: Dictionary) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(60, 60)
	var sb := _box(Color(0.06, 0.05, 0.04, 0.9), Color(0.62, 0.48, 0.26), 2, 4, 0)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	var glyph := SkillGlyph.new()
	glyph.id = sk["id"]
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.name = "glyph"
	p.add_child(glyph)
	var cd := ColorRect.new()
	cd.name = "cd"
	cd.color = Color(0, 0, 0, 0.7)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.anchor_right = 1.0
	cd.anchor_bottom = 1.0
	p.add_child(cd)
	p.add_child(_keycap(sk["key"]))
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box(Color(0.06, 0.1, 0.3, 0.95), Color(0.4, 0.55, 1.0), 1, 6, 0))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := _label(str(sk["mana"]), 11, Color(0.75, 0.82, 1.0), true)
	cost.add_theme_constant_override("outline_size", 0)
	pill.add_child(cost)
	pill.position = Vector2(35, 43)
	pill.custom_minimum_size = Vector2(24, 15)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(pill)
	p.mouse_entered.connect(func():
		var lines := [[sk["name"], GOLD], [sk["desc"], Color(0.85, 0.82, 0.75)], ["Mana: %d   Cooldown: %ss   Unlocks at level %d" % [sk["mana"], str(sk["cd"]), sk["lvl"]], Color(0.55, 0.65, 1.0)]]
		show_tooltip(lines)
		tip_owner = p)
	p.mouse_exited.connect(func():
		tooltip.visible = false
		tip_owner = null)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			game.cast_skill(sk["id"]))
	return p

# ---------------------------------------------------------------- inventory
func _panel(title: String, left: bool, w: int, h: int) -> PanelContainer:
	var p := PanelContainer.new()
	if left:
		p.position = Vector2(24, 60)
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -w - 24
		p.offset_right = -24
		p.offset_top = 60
	p.custom_minimum_size = Vector2(w, h)
	p.visible = false
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.name = "vb"
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := _label(title, 22, GOLD, true)
	t.name = "title"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(34, 30)
	x.pressed.connect(func():
		p.visible = false
		tooltip.visible = false
		if p == shop_panel or p == stash_panel:
			shop_mode = ""
		Sfx.play("click"))
	hb.add_child(x)
	var line := ColorRect.new()
	line.color = Color(0.42, 0.33, 0.2, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	vb.add_child(line)
	return p

func _build_inventory() -> void:
	inv_panel = _panel("Inventory", false, 480, 640)
	var vb: VBoxContainer = inv_panel.get_node("vb")
	var eq := Control.new()
	eq.custom_minimum_size = Vector2(450, 300)
	vb.add_child(eq)
	var layout := {
		"helm": [Vector2(186, 0), Vector2(78, 70), "Helm"],
		"amulet": [Vector2(280, 18), Vector2(44, 44), "Amulet"],
		"weapon": [Vector2(40, 40), Vector2(90, 160), "Weapon"],
		"armor": [Vector2(176, 82), Vector2(98, 130), "Armor"],
		"shield": [Vector2(320, 40), Vector2(90, 160), "Shield"],
		"ring1": [Vector2(130, 222), Vector2(44, 44), "Ring"],
		"belt": [Vector2(186, 224), Vector2(78, 40), "Belt"],
		"ring2": [Vector2(276, 222), Vector2(44, 44), "Ring"],
		"gloves": [Vector2(40, 214), Vector2(78, 76), "Gloves"],
		"boots": [Vector2(332, 214), Vector2(78, 76), "Boots"],
	}
	for k in layout.keys():
		var slot_name: String = k
		var s := _slot(layout[k][1], func(ev):
			if ev.button_index == MOUSE_BUTTON_LEFT:
				hero.unequip(slot_name)
				tooltip.visible = false, func(p, on): _hover(p, on, "equipped"), layout[k][2])
		s.position = layout[k][0]
		eq.add_child(s)
		equip_cells[k] = s
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	vb.add_child(grid)
	for i in 40:
		var idx := i
		var c := _slot(Vector2(CELL, CELL), func(ev): _inv_click(idx, ev), func(p, on): _hover(p, on, "sell" if shop_mode in ["smith", "armor", "alch", "gamble"] else ("stash" if shop_mode == "stash" else "inv")))
		c.gui_input.connect(func(ev: InputEvent): _inv_drag_input(idx, ev))
		grid.add_child(c)
		inv_cells.append(c)
	gold_lbl = _label("", 18, Color(1.0, 0.85, 0.4), true)
	vb.add_child(gold_lbl)
	var help := _label("Click to equip  ·  Drag to move, or out onto the ground to drop  ·  Right-click drink/sell/store", 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(help)

func _inv_click(idx: int, ev: InputEventMouseButton) -> void:
	var it = hero.inventory[idx]
	if it == null:
		return
	tooltip.visible = false
	if ev.button_index == MOUSE_BUTTON_LEFT and ev.ctrl_pressed:
		hero.inventory[idx] = null
		game.drop_item(it, hero.global_position)
		refresh()
		return
	if ev.button_index == MOUSE_BUTTON_LEFT:
		drag_idx = idx
		drag_from = get_viewport().get_mouse_position()
		dragging = false
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		if shop_mode in ["smith", "armor", "alch", "gamble"]:
			hero.inventory[idx] = null
			hero.gold += Items.sell_price(it)
			Sfx.play("gold")
			refresh()
		elif shop_mode == "stash":
			for i in hero.stash.size():
				if hero.stash[i] == null:
					hero.stash[i] = it
					hero.inventory[idx] = null
					Sfx.play("pickup")
					break
			refresh()
		elif not Items.is_equip(it):
			hero.inventory[idx] = null
			if not hero.add_to_inventory(it):
				hero.inventory[idx] = it
			refresh()

func _inv_drag_input(idx: int, ev: InputEvent) -> void:
	if drag_idx != idx:
		return
	if ev is InputEventMouseMotion and not dragging:
		if get_viewport().get_mouse_position().distance_to(drag_from) > 7.0 and hero.inventory[idx] != null:
			_start_drag(idx)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		if dragging:
			_finish_drag()
		else:
			drag_idx = -1
			if hero.inventory[idx] != null:
				hero.equip_from_inventory(idx)
				refresh()

func _start_drag(idx: int) -> void:
	dragging = true
	tooltip.visible = false
	var src: TextureRect = inv_cells[idx].get_node("icon")
	if drag_ghost == null:
		drag_ghost = TextureRect.new()
		drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_ghost.z_index = 100
		root.add_child(drag_ghost)
		drag_hint = _label("", 15, Color(1.0, 0.86, 0.5), true)
		drag_hint.z_index = 100
		drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(drag_hint)
	drag_ghost.texture = src.texture
	drag_ghost.size = Vector2(CELL, CELL) * 1.7
	drag_ghost.pivot_offset = drag_ghost.size * 0.5
	drag_ghost.visible = true
	drag_hint.visible = true
	src.modulate.a = 0.25
	Sfx.play("click", -8.0, 0.8)

func _drag_target() -> Array:
	var mp := get_viewport().get_mouse_position()
	for i in inv_cells.size():
		if (inv_cells[i] as Control).get_global_rect().has_point(mp):
			return ["inv", i]
	if inv_panel.visible:
		for k in equip_cells.keys():
			if (equip_cells[k] as Control).get_global_rect().has_point(mp):
				return ["equip", k]
	for pnl in [inv_panel, char_panel, stash_panel, shop_panel, wp_panel, dialog_panel, action_bar]:
		if pnl and pnl.visible and (pnl as Control).get_global_rect().has_point(mp):
			return ["ui", null]
	return ["ground", null]

func _update_drag(delta: float) -> void:
	if not dragging or drag_ghost == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not drag_hold:
		_finish_drag()
		return
	if drag_ghost.texture == null and drag_idx >= 0:
		drag_ghost.texture = (inv_cells[drag_idx].get_node("icon") as TextureRect).texture
	var mp := get_viewport().get_mouse_position() - root.get_global_rect().position
	drag_ghost.position = mp - drag_ghost.size * 0.5
	drag_ghost.rotation = sin(Time.get_ticks_msec() * 0.008) * 0.08
	var tgt := _drag_target()
	match tgt[0]:
		"ground":
			drag_hint.text = "Drop on the ground"
			drag_ghost.modulate = Color(1.0, 0.85, 0.7, 0.9)
		"inv":
			drag_hint.text = ""
			drag_ghost.modulate = Color(1, 1, 1, 0.9)
		"equip":
			drag_hint.text = "Equip"
			drag_ghost.modulate = Color(0.8, 1.0, 0.8, 0.9)
		_:
			drag_hint.text = ""
			drag_ghost.modulate = Color(1, 1, 1, 0.6)
	drag_hint.position = mp + Vector2(22, 18)

func _finish_drag(forced: Array = []) -> void:
	var idx := drag_idx
	var tgt := forced if not forced.is_empty() else (_drag_target() if dragging else ["ui", null])
	dragging = false
	drag_idx = -1
	if drag_ghost:
		drag_ghost.visible = false
		drag_hint.visible = false
	if idx >= 0 and idx < inv_cells.size():
		(inv_cells[idx].get_node("icon") as TextureRect).modulate.a = 1.0
	if idx < 0 or hero.inventory[idx] == null:
		return
	var it = hero.inventory[idx]
	match tgt[0]:
		"ground":
			hero.inventory[idx] = null
			var fwd: Vector3 = -hero.rig.global_transform.basis.z
			game.drop_item(it, hero.global_position + fwd * 0.6)
			Sfx.play("drop", -2.0, 1.0)
		"inv":
			var j: int = tgt[1]
			if j != idx:
				hero.inventory[idx] = hero.inventory[j]
				hero.inventory[j] = it
				Sfx.play("pickup", -6.0, 1.2)
				click_fx(inv_cells[j])
		"equip":
			hero.equip_from_inventory(idx)
	refresh()

# ---------------------------------------------------------------- character
func _build_character() -> void:
	char_panel = _panel("Character", true, 400, 560)
	var vb: VBoxContainer = char_panel.get_node("vb")
	for k in ["name", "level", "xp", "points"]:
		var l := _label("", 17 if k != "name" else 20, GOLD if k in ["name", "points"] else Color(0.86, 0.83, 0.77), k == "name")
		vb.add_child(l)
		char_labels[k] = l
	var stats := [["str", "Strength"], ["dex", "Dexterity"], ["vit", "Vitality"], ["ene", "Energy"]]
	for s in stats:
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var l := _label(s[1], 17)
		l.custom_minimum_size = Vector2(130, 0)
		hb.add_child(l)
		var v := _label("", 17, Color(1, 1, 1))
		v.custom_minimum_size = Vector2(80, 0)
		hb.add_child(v)
		char_labels[s[0]] = v
		var b := Button.new()
		b.text = "+"
		b.custom_minimum_size = Vector2(34, 28)
		var stat: String = s[0]
		b.pressed.connect(func(): _add_stat(stat))
		hb.add_child(b)
		plus_btns.append(b)
	var line := ColorRect.new()
	line.color = Color(0.42, 0.33, 0.2, 0.6)
	line.custom_minimum_size = Vector2(0, 1)
	vb.add_child(line)
	for k in ["damage", "aspd", "defense", "block", "life", "mana", "res", "ls", "mf"]:
		var l := _label("", 16)
		vb.add_child(l)
		char_labels[k] = l

func _add_stat(stat: String) -> void:
	if hero.stat_points <= 0:
		return
	hero.stat_points -= 1
	match stat:
		"str": hero.str_ += 1
		"dex": hero.dex += 1
		"vit": hero.vit += 1
		"ene": hero.ene += 1
	Sfx.play("click")
	hero.recalc()

# ---------------------------------------------------------------- shops & stash
func _build_shop() -> void:
	shop_panel = _panel("Merchant", true, 480, 560)
	var vb: VBoxContainer = shop_panel.get_node("vb")
	shop_title = shop_panel.get_node("vb").get_child(0).get_node("title")
	var note := _label("Left-click to buy  ·  Right-click your own items to sell", 13, DIM)
	vb.add_child(note)
	shop_grid = GridContainer.new()
	shop_grid.columns = 10
	shop_grid.add_theme_constant_override("h_separation", 2)
	shop_grid.add_theme_constant_override("v_separation", 2)
	vb.add_child(shop_grid)
	for i in 60:
		var idx := i
		var c := _slot(Vector2(CELL, CELL), func(ev): if ev.button_index == MOUSE_BUTTON_LEFT: _buy(idx), func(p, on): _hover(p, on, "gamble" if shop_mode == "gamble" else "buy"))
		shop_grid.add_child(c)

func open_shop(mode: String, title: String, items: Array) -> void:
	shop_mode = mode
	shop_items = items
	shop_title.text = title
	shop_panel.visible = true
	stash_panel.visible = false
	inv_panel.visible = true
	char_panel.visible = false
	_refresh_shop()

func _refresh_shop() -> void:
	for i in shop_grid.get_child_count():
		_set_slot(shop_grid.get_child(i), shop_items[i] if i < shop_items.size() else null)

func _buy(idx: int) -> void:
	if idx >= shop_items.size():
		return
	var it: Dictionary = shop_items[idx]
	var cost := Items.price(it) * (2 if shop_mode == "gamble" else 1)
	if hero.gold < cost:
		message("Not enough gold", Color(1, 0.4, 0.3))
		Sfx.play("deny")
		return
	var bought := it.duplicate(true)
	if shop_mode == "gamble":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var r := rng.randf()
		var rar := 1
		if r < 0.04:
			var cands := []
			for k in Data.UNIQUES.keys():
				if Data.UNIQUES[k]["base"] == it["base"]:
					cands.append(k)
			if cands.size() > 0:
				bought = Items.make_unique(cands[0])
			else:
				rar = 2
		elif r < 0.2:
			rar = 2
		if not bought.has("unique"):
			bought = Items.generate(it["base"], hero.level + 2, rar, rng)
	if not hero.add_to_inventory(bought):
		message("Inventory is full", Color(1, 0.4, 0.3))
		return
	hero.gold -= cost
	Sfx.play("gold")
	if not (Data.BASES[it["base"]]["slot"] == "potion"):
		if shop_mode != "gamble":
			shop_items.remove_at(idx)
	_refresh_shop()
	refresh()

func _build_stash() -> void:
	stash_panel = _panel("Stash", true, 480, 420)
	var vb: VBoxContainer = stash_panel.get_node("vb")
	vb.add_child(_label("Right-click items to move them between stash and inventory", 13, DIM))
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	vb.add_child(grid)
	for i in 60:
		var idx := i
		var c := _slot(Vector2(CELL, CELL), func(ev):
			if ev.button_index == MOUSE_BUTTON_RIGHT or ev.button_index == MOUSE_BUTTON_LEFT:
				var it = hero.stash[idx]
				if it != null:
					for j in hero.inventory.size():
						if hero.inventory[j] == null:
							hero.inventory[j] = it
							hero.stash[idx] = null
							Sfx.play("pickup")
							break
					tooltip.visible = false
					refresh(), func(p, on): _hover(p, on, "stash"))
		grid.add_child(c)
		stash_cells.append(c)

func open_stash() -> void:
	shop_mode = "stash"
	stash_panel.visible = true
	shop_panel.visible = false
	char_panel.visible = false
	inv_panel.visible = true
	refresh()

func _build_waypoints() -> void:
	wp_panel = _panel("Waypoints", true, 380, 380)
	wp_panel.position = Vector2(620, 220)
	wp_list = VBoxContainer.new()
	wp_list.add_theme_constant_override("separation", 6)
	(wp_panel.get_node("vb") as VBoxContainer).add_child(wp_list)

## runs_max >= 0 adds the Act I / A2 / A3 switch (shown at the camp waypoint).
func open_waypoints(entries: Array, cur_run := 0, runs_max := -1) -> void:
	for c in wp_list.get_children():
		c.queue_free()
	for e in entries:
		var b := Button.new()
		b.text = e["label"]
		b.disabled = not e["known"]
		var dest: Dictionary = e
		b.pressed.connect(func():
			wp_panel.visible = false
			game.travel_waypoint(dest))
		wp_list.add_child(b)
	if runs_max >= 0:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 8)
		wp_list.add_child(sp)
		wp_list.add_child(_label("Switch act", 18, GOLD, true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		wp_list.add_child(row)
		var names := ["Act I", "A2", "A3"]
		for d in 3:
			var rb := Button.new()
			rb.custom_minimum_size = Vector2(0, 40)
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if d == cur_run:
				rb.text = names[d] + " (here)"
				rb.disabled = true
			elif d > runs_max:
				rb.text = names[d] + " (locked)"
				rb.disabled = true
				rb.tooltip_text = "Beat the final boss of the act before it to unlock"
			else:
				rb.text = names[d]
			var dd: int = d
			rb.pressed.connect(func():
				wp_panel.visible = false
				game.switch_run(dd))
			row.add_child(rb)
		var hint := _label("Each act keeps its own waypoints and boss. Your knight, gear and gold come with you.", 13, Color(0.65, 0.62, 0.55))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wp_list.add_child(hint)
	wp_panel.visible = true

func _build_dialog() -> void:
	dialog_panel = PanelContainer.new()
	dialog_panel.anchor_left = 0.5
	dialog_panel.anchor_right = 0.5
	dialog_panel.anchor_top = 0.5
	dialog_panel.anchor_bottom = 0.5
	dialog_panel.offset_left = -330
	dialog_panel.offset_right = 330
	dialog_panel.offset_top = -170
	dialog_panel.offset_bottom = 120
	dialog_panel.visible = false
	root.add_child(dialog_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	dialog_panel.add_child(vb)
	dialog_name = _label("", 24, GOLD, true)
	vb.add_child(dialog_name)
	dialog_text = _label("", 17)
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.custom_minimum_size = Vector2(600, 0)
	vb.add_child(dialog_text)
	dialog_btns = HBoxContainer.new()
	dialog_btns.add_theme_constant_override("separation", 10)
	vb.add_child(dialog_btns)

func open_dialog(nm: String, text: String, buttons: Array) -> void:
	dialog_name.text = nm
	dialog_text.text = text
	for c in dialog_btns.get_children():
		c.queue_free()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		var cb: Callable = b[1]
		btn.pressed.connect(func():
			dialog_panel.visible = false
			Sfx.play("click")
			cb.call())
		dialog_btns.add_child(btn)
	dialog_panel.visible = true

func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.anchor_left = 0.5
	pause_panel.anchor_right = 0.5
	pause_panel.anchor_top = 0.5
	pause_panel.anchor_bottom = 0.5
	pause_panel.offset_left = -170
	pause_panel.offset_right = 170
	pause_panel.offset_top = -250
	pause_panel.offset_bottom = 250
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(pause_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pause_panel.add_child(vb)
	var t := _label("Paused", 28, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): game.toggle_pause())
	vb.add_child(resume)
	gfx_btn = Button.new()
	gfx_btn.pressed.connect(func():
		game.set_quality((game.quality + 1) % 4)
		_update_gfx_btn()
		message("Grass and fern density changes when you next enter an area", Color(0.7, 0.8, 1.0)))
	vb.add_child(gfx_btn)
	gfx_info = _label("", 13, Color(0.7, 0.66, 0.58))
	gfx_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gfx_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(gfx_info)
	_update_gfx_btn()
	sound_btn = Button.new()
	sound_btn.pressed.connect(func():
		game.set_sound(not game.sound_on)
		update_sound_btn())
	vb.add_child(sound_btn)
	update_sound_btn()
	var fps := Button.new()
	fps.text = "Toggle FPS counter (F3)"
	fps.pressed.connect(func(): show_fps = not show_fps)
	vb.add_child(fps)
	var save := Button.new()
	save.text = "Save and Quit"
	save.pressed.connect(func():
		game.save_game()
		get_tree().quit())
	vb.add_child(save)

func update_sound_btn() -> void:
	if sound_btn:
		sound_btn.text = "Sound: " + ("On" if game.sound_on else "Off") + "  (F2)"

func _update_gfx_btn() -> void:
	gfx_btn.text = "Graphics: " + ["Low", "Medium", "High", "Ultra"][game.quality]
	if gfx_info:
		gfx_info.text = game.renderer_info()

func _fullscreen_panel(col: Color) -> Control:
	var c := ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.color = col
	c.visible = false
	root.add_child(c)
	return c

func _build_title() -> void:
	title_panel = Control.new()
	title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_panel)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float v = smoothstep(0.0, 0.75, abs(UV.x - 0.5) * 1.4 + abs(UV.y - 0.45) * 0.6); COLOR = vec4(0.0, 0.0, 0.0, 0.35 + v * 0.55); }"
	sm.shader = sh
	shade.material = sm
	title_panel.add_child(shade)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.24
	vb.offset_left = -360
	vb.offset_right = 360
	vb.add_theme_constant_override("separation", 14)
	title_panel.add_child(vb)
	var t := _label("ASHEN CROWN", 76, Color(0.88, 0.7, 0.42), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 12)
	vb.add_child(t)
	var st := _label("Act I  ·  The Ashen Moors", 22, Color(0.75, 0.7, 0.62), true)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(st)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 40)
	vb.add_child(sp)
	var cont := Button.new()
	cont.name = "continue"
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, 46)
	cont.pressed.connect(func(): game.start_game(true))
	vb.add_child(cont)
	var ng := Button.new()
	ng.text = "New Game"
	ng.custom_minimum_size = Vector2(0, 46)
	ng.pressed.connect(func(): game.start_game(false))
	vb.add_child(ng)
	var coop := HBoxContainer.new()
	coop.add_theme_constant_override("separation", 12)
	vb.add_child(coop)
	var hb := Button.new()
	hb.text = "Host Co-op Game"
	hb.custom_minimum_size = Vector2(0, 46)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.pressed.connect(func(): game.start_host())
	coop.add_child(hb)
	var jb := Button.new()
	jb.text = "Join Co-op Game"
	jb.custom_minimum_size = Vector2(0, 46)
	jb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jb.pressed.connect(func(): open_join())
	coop.add_child(jb)
	var q := Button.new()
	q.text = "Quit"
	q.custom_minimum_size = Vector2(0, 46)
	q.pressed.connect(func(): get_tree().quit())
	vb.add_child(q)
	if OS.has_feature("web"):
		# browsers can't use the LAN co-op networking, and there's nothing to quit to
		coop.visible = false
		q.visible = false
		var wn := _label("Playing in the browser. Co-op needs the downloadable Windows version.", 14, Color(0.6, 0.57, 0.5))
		wn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(wn)
	var credit := _label("All models, textures, music and sound are generated in code.", 14, Color(0.5, 0.47, 0.42))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(credit)

func _build_join() -> void:
	join_panel = PanelContainer.new()
	join_panel.anchor_left = 0.5
	join_panel.anchor_right = 0.5
	join_panel.anchor_top = 0.5
	join_panel.anchor_bottom = 0.5
	join_panel.offset_left = -300
	join_panel.offset_right = 300
	join_panel.offset_top = -230
	join_panel.offset_bottom = 230
	join_panel.visible = false
	root.add_child(join_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	join_panel.add_child(vb)
	var t := _label("Join a Co-op Game", 28, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_label("Games on your network:", 16))
	join_list = VBoxContainer.new()
	join_list.custom_minimum_size = Vector2(0, 150)
	join_list.add_theme_constant_override("separation", 6)
	vb.add_child(join_list)
	join_hint = _label("Searching... make sure the other computer has picked Host Co-op Game.", 14, Color(0.7, 0.66, 0.58))
	join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(join_hint)
	vb.add_child(_label("Or type the host's address (shown at the top left of their screen):", 14, Color(0.7, 0.66, 0.58)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	join_ip = LineEdit.new()
	join_ip.placeholder_text = "e.g. 192.168.1.23"
	join_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_ip.custom_minimum_size = Vector2(0, 40)
	join_ip.text_submitted.connect(func(txt): _join_ip(txt))
	row.add_child(join_ip)
	var go := Button.new()
	go.text = "Join"
	go.custom_minimum_size = Vector2(100, 40)
	go.pressed.connect(func(): _join_ip(join_ip.text))
	row.add_child(go)
	var note := _label("Your saved knight comes with you (a new one if you have no save).", 13, Color(0.6, 0.57, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func():
		join_panel.visible = false
		game.net.stop_listening()
		title_panel.visible = true)
	vb.add_child(back)

func open_join() -> void:
	Sfx.play("click")
	title_panel.visible = false
	join_panel.visible = true
	game.net.start_listening()
	_refresh_join()

func _join_ip(txt: String) -> void:
	txt = txt.strip_edges()
	if txt == "":
		return
	join_panel.visible = false
	game.start_join(txt)

func _refresh_join() -> void:
	for c in join_list.get_children():
		c.queue_free()
	var found: Dictionary = game.net.found
	for ip in found.keys():
		var b := Button.new()
		b.text = "%s's game  ·  %s  ·  %s" % [found[ip]["name"], found[ip]["zone"], ip]
		b.custom_minimum_size = Vector2(0, 44)
		var addr: String = ip
		b.pressed.connect(func(): _join_ip(addr))
		join_list.add_child(b)
	join_hint.visible = found.is_empty()

# ---------------------------------------------------------------- armor enchanting
func _build_enchant() -> void:
	ench_panel = _panel("Enchant Armor", true, 560, 600)
	var vb: VBoxContainer = ench_panel.get_node("vb")
	var intro := _label("Pay to bind runes into your worn armor. Each level adds 15% defense and extra life. Up to +10.", 14, DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(520, 0)
	vb.add_child(intro)
	var names := {"helm": "Helm", "armor": "Body armor", "gloves": "Gloves", "boots": "Boots", "belt": "Belt", "shield": "Shield"}
	for k in Items.ENCHANT_SLOTS:
		var slot_name: String = k
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vb.add_child(row)
		var cell := _slot(Vector2(64, 64), func(_ev): pass, func(p, on): _hover(p, on, ""), names[k])
		row.add_child(cell)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		var nm := _label("", 16, GOLD, true)
		info.add_child(nm)
		var st := _label("", 13, Color(0.75, 0.82, 1.0))
		info.add_child(st)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		info.add_child(pips)
		for i in Items.ENCHANT_MAX:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(14, 6)
			pips.add_child(pip)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 48)
		b.pressed.connect(func(): _enchant(slot_name))
		row.add_child(b)
		ench_rows[k] = {"cell": cell, "name": nm, "stats": st, "pips": pips, "btn": b}
	ench_gold = _label("", 18, Color(1.0, 0.85, 0.4), true)
	vb.add_child(ench_gold)

func open_enchant(title: String) -> void:
	close_all()
	(ench_panel.get_node("vb").get_child(0).get_node("title") as Label).text = title + " · Enchanting"
	ench_panel.visible = true
	inv_panel.visible = true
	_refresh_enchant()
	Sfx.play("equip")

func _refresh_enchant() -> void:
	if ench_panel == null or not ench_panel.visible:
		return
	for k in ench_rows.keys():
		var r: Dictionary = ench_rows[k]
		var it = hero.equipment.get(k)
		_set_slot(r["cell"], it)
		var en := int(it.get("ench", 0)) if it != null else 0
		var pips: HBoxContainer = r["pips"]
		for i in pips.get_child_count():
			(pips.get_child(i) as ColorRect).color = Color(0.45, 0.65, 1.0) if i < en else Color(0.14, 0.13, 0.16)
		var b: Button = r["btn"]
		if it == null:
			r["name"].text = "Nothing worn"
			r["stats"].text = ""
			b.text = "—"
			b.disabled = true
			continue
		r["name"].text = ("+%d " % en if en > 0 else "") + it["name"]
		var d_now := Items.defense_of(it)
		if en >= Items.ENCHANT_MAX:
			r["stats"].text = "Defense %d  ·  fully enchanted" % d_now
			b.text = "Maxed"
			b.disabled = true
			continue
		var nxt: Dictionary = it.duplicate(true)
		nxt["ench"] = en + 1
		var cost := Items.enchant_cost(it)
		r["stats"].text = "Defense %d → %d   ·   Life +%d → +%d" % [d_now, Items.defense_of(nxt), Items.enchant_life(it, en), Items.enchant_life(it, en + 1)]
		b.text = "Enchant +%d\n%d gold" % [en + 1, cost]
		b.disabled = hero.gold < cost
	ench_gold.text = "Gold: %d" % hero.gold

func _enchant(slot_name: String) -> void:
	var it = hero.equipment.get(slot_name)
	if not Items.can_enchant(it):
		return
	var cost := Items.enchant_cost(it)
	if hero.gold < cost:
		message("Not enough gold", Color(1, 0.4, 0.3))
		Sfx.play("deny")
		return
	hero.gold -= cost
	it["ench"] = int(it.get("ench", 0)) + 1
	hero.recalc()
	hero.refresh_gear()
	var r: Dictionary = ench_rows[slot_name]
	click_fx(r["cell"])
	_enchant_burst(r["cell"])
	Sfx.play("levelup", -4.0, 1.25)
	message("%s enchanted to +%d!" % [it["name"], it["ench"]], Color(0.6, 0.8, 1.0))
	refresh()
	_refresh_enchant()

## A ring of blue runes-light around the slot.
func _enchant_burst(p: Control) -> void:
	var c := p.get_global_rect().get_center() - root.get_global_rect().position
	for i in 16:
		var sp := ColorRect.new()
		sp.size = Vector2(5, 5)
		sp.color = Color(0.55, 0.75, 1.0) if i % 2 == 0 else Color(0.9, 0.95, 1.0)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.position = c - Vector2(2.5, 2.5)
		sp.rotation = PI * 0.25
		root.add_child(sp)
		var a := TAU * i / 16.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sp, "position", sp.position + Vector2(cos(a), sin(a)) * 60.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "modulate:a", 0.0, 0.5).set_delay(0.15)
		tw.chain().tween_callback(sp.queue_free)

func show_title(has_save: bool) -> void:
	title_panel.visible = true
	(title_panel.find_child("continue", true, false) as Button).disabled = not has_save
	_set_hud(false)

func hide_title() -> void:
	title_panel.visible = false
	_set_hud(true)

func _set_hud(v: bool) -> void:
	for n in [life_orb.get_parent(), mana_orb.get_parent(), life_lbl, mana_lbl, action_bar, zone_lbl, hint_lbl, minimap]:
		n.visible = v

func _build_death() -> void:
	death_panel = _fullscreen_panel(Color(0.15, 0.0, 0.0, 0.55))
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.35
	vb.offset_left = -300
	vb.offset_right = 300
	vb.add_theme_constant_override("separation", 20)
	death_panel.add_child(vb)
	var t := _label("You have died", 56, Color(0.85, 0.12, 0.08), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := _label("You lose 10% of your gold.", 18, DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var b := Button.new()
	b.text = "Return to Town"
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func():
		death_panel.visible = false
		game.respawn())
	vb.add_child(b)

func _build_victory() -> void:
	victory_panel = _fullscreen_panel(Color(0.0, 0.0, 0.0, 0.6))
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.3
	vb.offset_left = -360
	vb.offset_right = 360
	vb.add_theme_constant_override("separation", 18)
	victory_panel.add_child(vb)
	var t := _label("Act I Complete", 58, GOLD, true)
	t.name = "vtitle"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := _label("The Hollow Matron is destroyed and the crypt falls silent.", 19, Color(0.85, 0.82, 0.75))
	s.name = "vsub"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var a2 := Button.new()
	a2.name = "a2btn"
	a2.text = "Begin A2: start over at the camp with your knight"
	a2.custom_minimum_size = Vector2(0, 50)
	a2.pressed.connect(func(): game.start_a2())
	vb.add_child(a2)
	var a2n := _label("Monsters have 20 times the life, damage and armor. Every item they drop is 5 times stronger.", 15, Color(1.0, 0.6, 0.4))
	a2n.name = "a2note"
	a2n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a2n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(a2n)
	var b := Button.new()
	b.text = "Stay and keep exploring"
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func(): victory_panel.visible = false)
	vb.add_child(b)

func show_victory(diff: int) -> void:
	(victory_panel.find_child("vtitle", true, false) as Label).text = ["Act I", "A2", "A3"][clampi(diff, 0, 2)] + " Complete"
	(victory_panel.find_child("vsub", true, false) as Label).text = "The Ashen King crumbles to cinders. His crown rolls across the throne room floor." if diff >= 2 else "The Hollow Matron is destroyed and the crypt falls silent."
	(victory_panel.find_child("a2btn", true, false) as Button).text = ["Begin A2", "Begin A3", "Play A3 again"][clampi(diff, 0, 2)] + ": start over at the camp with your knight"
	(victory_panel.find_child("a2note", true, false) as Label).text = "In A3 the Ashen King replaces the Matron. Monsters are 400 times stronger than Act I, loot 25 times, and the King always drops his sword." if diff >= 1 else "Monsters have 20 times the life, damage and armor. Every item they drop is 5 times stronger."
	victory_panel.visible = true

func _unhandled_key_input(ev: InputEvent) -> void:
	if game and game.paused and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		game.toggle_pause()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- updates
func toggle(panel: Control) -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		tooltip.visible = false
	if panel == inv_panel and not panel.visible:
		shop_panel.visible = false
		stash_panel.visible = false
		shop_mode = ""
	Sfx.play("click")
	refresh()

func close_all() -> bool:
	var any := false
	for p in [inv_panel, char_panel, shop_panel, stash_panel, wp_panel, dialog_panel, ench_panel]:
		if p.visible:
			p.visible = false
			any = true
	shop_mode = ""
	tooltip.visible = false
	return any

func any_panel_open() -> bool:
	return inv_panel.visible or char_panel.visible or shop_panel.visible or stash_panel.visible or wp_panel.visible or dialog_panel.visible or ench_panel.visible

func message(t: String, col := Color(1, 1, 1)) -> void:
	msg_lbl.text = t
	msg_lbl.add_theme_color_override("font_color", col)
	msg_t = 2.5

func big_message(t: String) -> void:
	big_lbl.text = t
	big_t = 4.0

func flash_damage() -> void:
	dmg_flash.color.a = minf(0.28, dmg_flash.color.a + 0.14)

func set_zone(t: String) -> void:
	zone_lbl.text = t
	big_message(t)

func show_target(nm: String, frac: float, col: Color) -> void:
	target_box.visible = true
	target_name.text = nm
	target_name.add_theme_color_override("font_color", col)
	target_bar.value = frac * 100.0

func hide_target() -> void:
	target_box.visible = false

func set_boss(e) -> void:
	boss_ref = e
	boss_bar_box.visible = e != null
	if e:
		boss_lbl.text = e.display_name

func refresh() -> void:
	if hero == null:
		return
	_refresh_enchant()
	life_lbl.text = "Life  %d / %d" % [int(hero.life), int(hero.max_life)]
	mana_lbl.text = "Mana  %d / %d" % [int(hero.mana), int(hero.max_mana)]
	var xpf := float(hero.xp) / maxf(Data.xp_for_level(hero.level), 1.0)
	xp_bar.value = xpf
	xp_bar.detail = "Level %d   ·   %d / %d   (%d%%)" % [hero.level, hero.xp, Data.xp_for_level(hero.level), int(xpf * 100.0)]
	if level_medal:
		level_medal.level = hero.level
		level_medal.xp = xpf
		xp_bar.detail = "%d / %d   (%d%%)" % [hero.xp, Data.xp_for_level(hero.level), int(xpf * 100.0)]
	for i in 4:
		_set_slot(belt_slots[i], hero.belt[i])
	if inv_panel.visible:
		for i in 40:
			_set_slot(inv_cells[i], hero.inventory[i])
		for k in equip_cells.keys():
			_set_slot(equip_cells[k], hero.equipment.get(k))
		gold_lbl.text = "Gold: %d" % hero.gold
	if stash_panel.visible:
		for i in 60:
			_set_slot(stash_cells[i], hero.stash[i])
	if char_panel.visible:
		char_labels["name"].text = "Crusader of Greywatch"
		char_labels["level"].text = "Level %d" % hero.level
		char_labels["xp"].text = "Experience: %d / %d" % [hero.xp, Data.xp_for_level(hero.level)]
		char_labels["points"].text = ("Stat points to spend: %d" % hero.stat_points) if hero.stat_points > 0 else ""
		char_labels["str"].text = "%d" % hero.total_str()
		char_labels["dex"].text = "%d" % hero.total_dex()
		char_labels["vit"].text = "%d" % hero.total_vit()
		char_labels["ene"].text = "%d" % hero.ene
		for b in plus_btns:
			b.disabled = hero.stat_points <= 0
		char_labels["damage"].text = "Damage: %d - %d%s" % [hero.dmg_min, hero.dmg_max, ("  (+%d fire)" % hero.fire_dmg) if hero.fire_dmg > 0 else ""]
		char_labels["aspd"].text = "Attack speed: %.2f" % hero.aspd
		char_labels["defense"].text = "Defense: %d" % hero.armor
		char_labels["block"].text = "Chance to block: %d%%" % int(hero.block_chance)
		char_labels["life"].text = "Life: %d   (regen %.1f/s)" % [int(hero.max_life), hero.regen]
		char_labels["mana"].text = "Mana: %d" % int(hero.max_mana)
		char_labels["res"].text = "All resistances: %d%%" % hero.res
		char_labels["ls"].text = "Life steal: %d%%" % int(hero.ls)
		char_labels["mf"].text = "Magic find: %d%%   Gold find: %d%%" % [hero.mf, hero.gf]

func _process(delta: float) -> void:
	_update_drag(delta)
	if join_panel and join_panel.visible:
		_join_refresh -= delta
		if _join_refresh <= 0.0:
			_join_refresh = 0.5
			_refresh_join()
	if hero:
		stamina_bar.value = hero.stamina / maxf(hero.max_stamina, 1.0)
		stamina_bar.detail = "%d / %d" % [int(hero.stamina), int(hero.max_stamina)]
		if hero.exhausted:
			stamina_bar.title = "WINDED"
			stamina_bar.col_lo = Color(0.45, 0.08, 0.02)
			stamina_bar.col_hi = Color(1.0, 0.45, 0.15)
			stamina_bar.glow = Color(1.0, 0.5, 0.2)
		else:
			stamina_bar.title = "SPRINTING" if hero.running else "STAMINA"
			stamina_bar.col_lo = Color(0.03, 0.38, 0.16)
			stamina_bar.col_hi = Color(0.38, 0.95, 0.45)
			stamina_bar.glow = Color(0.55, 1.0, 0.6)
		stamina_bar.pulse = move_toward(stamina_bar.pulse, 1.0 if hero.running else 0.0, delta * 4.0)
		(life_orb.material as ShaderMaterial).set_shader_parameter("fill", hero.life / hero.max_life)
		(mana_orb.material as ShaderMaterial).set_shader_parameter("fill", hero.mana / hero.max_mana)
		life_lbl.text = "Life  %d / %d" % [int(hero.life), int(hero.max_life)]
		mana_lbl.text = "Mana  %d / %d" % [int(hero.mana), int(hero.max_mana)]
		for i in 4:
			var sk: Dictionary = Data.SKILLS[i]
			var s: Panel = skill_slots[i]
			var cd: ColorRect = s.get_node("cd")
			var locked: bool = hero.level < sk["lvl"]
			var frac: float = 1.0 if locked else clampf(hero.cds[sk["id"]] / maxf(sk["cd"], 0.01), 0.0, 1.0)
			cd.anchor_top = 1.0 - frac
			cd.color = Color(0, 0, 0, 0.82) if locked else Color(0, 0, 0, 0.6)
			(s.get_node("glyph") as SkillGlyph).dim = locked or hero.mana < sk["mana"]
	if msg_t > 0.0:
		msg_t -= delta
		msg_lbl.modulate.a = clampf(msg_t, 0.0, 1.0)
	if big_t > 0.0:
		big_t -= delta
		big_lbl.modulate.a = clampf(big_t, 0.0, 1.0) * clampf((4.0 - big_t) * 2.0, 0.0, 1.0)
	dmg_flash.color.a = maxf(0.0, dmg_flash.color.a - delta * 1.2)
	fps_lbl.visible = show_fps
	if show_fps:
		fps_lbl.text = "%d FPS" % Engine.get_frames_per_second()
	if boss_ref != null:
		if is_instance_valid(boss_ref) and not boss_ref.dead:
			boss_bar.value = boss_ref.life / boss_ref.max_life * 100.0
		else:
			set_boss(null)
	if tooltip.visible:
		var mp := root.get_local_mouse_position()
		var sz := tooltip.size
		var vs := root.size
		var pos := mp + Vector2(18, 18)
		if pos.x + sz.x > vs.x - 8:
			pos.x = mp.x - sz.x - 12
		if pos.y + sz.y > vs.y - 8:
			pos.y = vs.y - sz.y - 8
		tooltip.position = pos
	minimap.queue_redraw()

# ---------------------------------------------------------------- inner widgets
class SkillGlyph extends Control:
	var id := ""
	var dim := false
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1.0, 0.8, 0.4) if not dim else Color(0.4, 0.35, 0.3)
		match id:
			"cleave":
				draw_arc(c + Vector2(0, 8), 16, PI * 1.1, PI * 1.9, 16, col, 4.0, true)
				draw_line(c + Vector2(-10, 10), c + Vector2(10, -12), col, 3.0, true)
			"nova":
				draw_arc(c, 15, 0, TAU, 32, col, 3.0, true)
				draw_arc(c, 8, 0, TAU, 24, col.darkened(0.2), 2.0, true)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * 10, c + Vector2(cos(a), sin(a)) * 19, col, 2.0, true)
			"charge":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -8), c + Vector2(4, -8), c + Vector2(4, -14), c + Vector2(16, 0), c + Vector2(4, 14), c + Vector2(4, 8), c + Vector2(-14, 8)]), col)
			"cry":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -6), c + Vector2(-4, -6), c + Vector2(8, -14), c + Vector2(8, 14), c + Vector2(-4, 6), c + Vector2(-14, 6)]), col)
				draw_arc(c + Vector2(8, 0), 10, -0.8, 0.8, 8, col, 2.0, true)
	func _process(_d: float) -> void:
		queue_redraw()

class Minimap extends Control:
	## Top-down render of the zone with exploration fog, POI icons and a facing arrow.
	var ui
	var view := ColorRect.new()
	var overlay := Control.new()
	var mat := ShaderMaterial.new()
	var map_rect := Rect2(0, 0, 1, 1)
	var fog_img: Image
	var fog_tex: ImageTexture
	var fog_on := false
	var big := false
	var view_m := 80.0
	var _reveal_t := 0.0
	var has_map := false

	func _init() -> void:
		var sh := Shader.new()
		sh.code = MAP_SHADER
		mat.shader = sh
		view.material = mat
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		overlay.draw.connect(func(): _paint(overlay))

	func set_map(tex: Texture2D, rect: Rect2, fog: bool) -> void:
		map_rect = rect
		has_map = tex != null
		mat.set_shader_parameter("map_tex", tex)
		fog_on = fog
		fog_img = Image.create(int(ceil(rect.size.x)), int(ceil(rect.size.y)), false, Image.FORMAT_L8)
		fog_img.fill(Color(0, 0, 0) if fog else Color(1, 1, 1))
		fog_tex = ImageTexture.create_from_image(fog_img)
		mat.set_shader_parameter("fog_tex", fog_tex)
		mat.set_shader_parameter("has_map", 1.0 if has_map else 0.0)

	func set_big(b: bool) -> void:
		big = b
		if big:
			anchor_left = 0.5
			anchor_right = 0.5
			anchor_top = 0.5
			anchor_bottom = 0.5
			offset_left = -330
			offset_right = 330
			offset_top = -350
			offset_bottom = 310
			view_m = clampf(maxf(map_rect.size.x, map_rect.size.y) * 0.95, 60.0, 130.0)
		else:
			anchor_left = 1.0
			anchor_right = 1.0
			anchor_top = 0.0
			anchor_bottom = 0.0
			offset_left = -230
			offset_right = -18
			offset_top = 40
			offset_bottom = 252
			view_m = 80.0

	func _reveal(hp: Vector3) -> void:
		if not fog_on or fog_img == null:
			return
		var cx := int(hp.x - map_rect.position.x)
		var cy := int(hp.z - map_rect.position.y)
		var r := 26
		var changed := false
		for y in range(maxi(0, cy - r), mini(fog_img.get_height(), cy + r + 1)):
			for x in range(maxi(0, cx - r), mini(fog_img.get_width(), cx + r + 1)):
				var d := Vector2(x - cx, y - cy).length()
				if d > r:
					continue
				var v := clampf((r - d) / 6.0, 0.0, 1.0)
				var old := fog_img.get_pixel(x, y).r
				if v > old + 0.02:
					fog_img.set_pixel(x, y, Color(v, v, v))
					changed = true
		if changed:
			fog_tex.update(fog_img)

	func _process(delta: float) -> void:
		var g = ui.game if ui else null
		if g == null or g.hero == null or g.world == null:
			return
		if big:
			view_m = clampf(maxf(map_rect.size.x, map_rect.size.y) * 0.95, 60.0, 130.0)
		var hp: Vector3 = g.hero.global_position
		_reveal_t -= delta
		if _reveal_t <= 0.0:
			_reveal_t = 0.2
			_reveal(hp)
		var cu := Vector2((hp.x - map_rect.position.x) / map_rect.size.x, (hp.z - map_rect.position.y) / map_rect.size.y)
		mat.set_shader_parameter("center_uv", cu)
		mat.set_shader_parameter("span_uv", Vector2(view_m / map_rect.size.x, view_m / map_rect.size.y))
		mat.set_shader_parameter("fog_on", 1.0 if fog_on else 0.0)
		mat.set_shader_parameter("alpha", 0.88 if big else 0.95)
		overlay.queue_redraw()

	func _to_screen(p: Vector3, hp: Vector3) -> Vector2:
		var c := size * 0.5
		return c + Vector2(p.x - hp.x, p.z - hp.z) / view_m * size.x

	func _inside(sp: Vector2) -> bool:
		return sp.distance_to(size * 0.5) < size.x * 0.5 - 8.0

	func _fogged(p: Vector3) -> bool:
		if not fog_on or fog_img == null:
			return false
		var x := int(p.x - map_rect.position.x)
		var y := int(p.z - map_rect.position.y)
		if x < 0 or y < 0 or x >= fog_img.get_width() or y >= fog_img.get_height():
			return true
		return fog_img.get_pixel(x, y).r < 0.3

	func _paint(ci: Control) -> void:
		var g = ui.game if ui else null
		if g == null or g.world == null or g.hero == null:
			return
		var w: World = g.world
		var hp: Vector3 = g.hero.global_position
		var c := size * 0.5
		var rad := size.x * 0.5
		if not has_map:
			ci.draw_circle(c, rad, Color(0.04, 0.04, 0.035, 0.85))
		# exits
		for ex in w.exits:
			var sp := _to_screen(ex["pos"], hp)
			if _inside(sp) and not _fogged(ex["pos"]):
				ci.draw_circle(sp, 7.0, Color(0.05, 0.08, 0.15, 0.9))
				ci.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -5), sp + Vector2(5, 3), sp + Vector2(-5, 3)]), Color(0.45, 0.75, 1.0))
		# points of interest
		for it in w.interactables:
			if not is_instance_valid(it):
				continue
			var sp2 := _to_screen(it.global_position, hp)
			if not _inside(sp2) or _fogged(it.global_position):
				continue
			match it.kind:
				"waypoint":
					var dm := PackedVector2Array([sp2 + Vector2(0, -7), sp2 + Vector2(6, 0), sp2 + Vector2(0, 7), sp2 + Vector2(-6, 0)])
					ci.draw_colored_polygon(dm, Color(0.35, 0.6, 1.0))
					ci.draw_polyline(PackedVector2Array([dm[0], dm[1], dm[2], dm[3], dm[0]]), Color(0.85, 0.92, 1.0), 1.5, true)
				"portal":
					ci.draw_arc(sp2, 6.0, 0, TAU, 20, Color(0.45, 0.7, 1.0), 3.0, true)
				"vendor":
					ci.draw_circle(sp2, 5.0, Color(0.1, 0.07, 0.03))
					ci.draw_circle(sp2, 3.5, Color(1.0, 0.82, 0.4))
				"stash":
					ci.draw_rect(Rect2(sp2 - Vector2(4.5, 3.5), Vector2(9, 7)), Color(0.75, 0.5, 0.22))
					ci.draw_rect(Rect2(sp2 - Vector2(4.5, 3.5), Vector2(9, 7)), Color(0.1, 0.06, 0.02), false, 1.0)
				"shrine":
					var sc := Color(0.5, 0.5, 0.5) if it.used else Color(1.0, 0.55, 0.3)
					ci.draw_circle(sp2, 4.5, Color(0.05, 0.05, 0.05))
					ci.draw_circle(sp2, 3.0, sc)
				"chest":
					if not it.used:
						ci.draw_rect(Rect2(sp2 - Vector2(3.5, 2.5), Vector2(7, 5)), Color(0.85, 0.65, 0.3))
		# co-op partners
		if g.net and g.net.active:
			for a in g.net.puppets():
				if not a.visible:
					continue
				var ap := _to_screen(a.global_position, hp)
				if _inside(ap):
					ci.draw_circle(ap, 6.0, Color(0, 0, 0, 0.7))
					ci.draw_circle(ap, 4.5, a.ally_color)
		# player arrow
		var yaw: float = g.hero.rig.rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		var tip := c + fwd * 9.0
		var arrow := PackedVector2Array([tip, c - fwd * 5.0 + right * 6.0, c - fwd * 2.0, c - fwd * 5.0 - right * 6.0])
		ci.draw_colored_polygon(arrow, Color(0.0, 0.0, 0.0, 0.6))
		var arrow2 := PackedVector2Array()
		for v in arrow:
			arrow2.append(c + (v - c) * 0.78)
		ci.draw_colored_polygon(arrow2, Color(1.0, 0.92, 0.7))
		# frame
		ci.draw_arc(c, rad - 1.0, 0, TAU, 64, Color(0.08, 0.06, 0.04), 5.0, true)
		ci.draw_arc(c, rad - 2.5, 0, TAU, 64, Color(0.62, 0.5, 0.3), 2.0, true)
		ci.draw_arc(c, rad - 6.0, 0, TAU, 64, Color(0.3, 0.24, 0.14, 0.8), 1.0, true)
		for k in 4:
			var a := TAU * k / 4.0
			var p := c + Vector2(sin(a), -cos(a)) * (rad - 2.5)
			ci.draw_circle(p, 4.0 if k == 0 else 3.0, Color(0.62, 0.5, 0.3))
		ci.draw_string(ThemeDB.fallback_font, c + Vector2(-4, -rad + 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.8, 0.55))

	const MAP_SHADER := """
shader_type canvas_item;
uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 center_uv = vec2(0.5);
uniform vec2 span_uv = vec2(0.3);
uniform float fog_on = 0.0;
uniform float has_map = 0.0;
uniform float alpha = 0.95;
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	vec2 muv = center_uv + (UV - 0.5) * span_uv;
	vec3 c = vec3(0.03, 0.03, 0.025);
	if (has_map > 0.5 && muv.x >= 0.0 && muv.y >= 0.0 && muv.x <= 1.0 && muv.y <= 1.0) {
		c = texture(map_tex, muv).rgb;
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(vec3(l), c, 0.9) * 1.5;
		c = pow(c, vec3(0.92));
		float f = fog_on > 0.5 ? texture(fog_tex, muv).r : 1.0;
		c = mix(vec3(0.025, 0.025, 0.02), c, f);
	}
	c *= mix(1.0, 0.45, smoothstep(0.7, 1.0, r));
	COLOR = vec4(c, alpha);
}
"""
