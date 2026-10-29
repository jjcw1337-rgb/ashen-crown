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
var life_globe: Globe
var _slots_hero = null
var mana_globe: Globe
var mana_orb: ColorRect
var life_lbl: Label
var mana_lbl: Label
var xp_bar: HudBar
var _xp_bonus_on := false   # the XP bonus countdown is showing on xp_bar
var stamina_bar: HudBar
var level_medal: HudBar.Medallion
var action_bar: Control
var bar_style := "A"
var skill_slots := {}        # bar slot ("lmb", "rmb", "Q".."V") -> its Control
var skills_panel: PanelContainer
var talent_panel: PanelContainer
var talent_cols: HBoxContainer
var talent_head: Label
var talent_badge: Button       # over the bar while talent points wait to be spent
var _talent_hover := ""
var _talent_shown := ""        # what the open talents window shows (rebuilt when it changes)
var _skill_drag_from := ""     # the bar slot a skill is being dragged off ("" from the skills window)
var _skill_dragged := false
var skill_rows: VBoxContainer
const BAR_TEX := {"frame": "res://assets/textures/ui/bar_frame.png", "slot": "res://assets/textures/ui/slot.png", "slot_big": "res://assets/textures/ui/slot_big.png"}
var skill_hb: HBoxContainer
var class_panel: Control
## Title screen: the saved characters (play / delete), and the new character's name.
var chars_panel: Control
var chars_list: VBoxContainer
var name_edit: LineEdit
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
var skill_picker: Control = null
const BIND_KEYS_UI := ["Q", "E", "R", "F", "G", "V"]

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
var helm_btn: Button
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
var test_panel: PanelContainer
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
	_build_test_panel()
	_build_skills_panel()
	_build_talent_panel()
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
		if is_instance_valid(p) and (p.get_meta("item") if p.has_meta("item") else null) == it:
			tr.texture = t)
	tr.texture = tex

func _hover(p: Control, on: bool, mode: String) -> void:
	if not on:
		if tip_owner == p:
			tooltip.visible = false
			tip_owner = null
		return
	var it = (p.get_meta("item") if p.has_meta("item") else null)
	if it == null:
		tooltip.visible = false
		return
	show_tooltip(Items.tooltip(it, hero.level if hero else 99, mode))
	tip_owner = p

func show_tooltip(lines: Array) -> void:
	for c in tip_box.get_children():
		tip_box.remove_child(c)      # out now, so the box sizes to the new lines only
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
	# life and mana globes (scripts/globe.gd): liquid that surges, ripples, swirls and pulses
	life_globe = Globe.new()
	life_globe.kind = "life"
	life_globe.ref_max = 120.0      # a level-1 hero's life; more makes the globe bigger
	life_globe.size = Vector2(230, 230)
	life_globe.position = Vector2(-4, -36)
	bottom.add_child(life_globe)
	mana_globe = Globe.new()
	mana_globe.kind = "mana"
	mana_globe.ref_max = 40.0
	mana_globe.anchor_left = 1.0
	mana_globe.anchor_right = 1.0
	mana_globe.offset_left = -226
	mana_globe.offset_right = 4
	mana_globe.offset_top = -36
	mana_globe.offset_bottom = 194
	bottom.add_child(mana_globe)
	life_orb = ColorRect.new()      # kept for older code paths; the globes draw themselves
	mana_orb = ColorRect.new()
	life_orb.visible = false
	mana_orb.visible = false
	bottom.add_child(life_orb)
	bottom.add_child(mana_orb)
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
	# centre action bar: the Meshy-painted iron frame (a 9-slice), XP and stamina along the top, and one
	# row of slots: three hotkeys, the two mouse-button skills in big crested sockets, three more
	# hotkeys, then the potion belt
	var bh := 214
	var frame := NinePatchRect.new()
	frame.texture = load(BAR_TEX["frame"])
	frame.patch_margin_left = 62
	frame.patch_margin_right = 62
	frame.patch_margin_top = 62
	frame.patch_margin_bottom = 62
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -450
	frame.offset_right = 450
	frame.offset_top = -bh - 4
	frame.offset_bottom = -4
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(frame)
	action_bar = frame
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 40
	vb.offset_right = -40
	vb.offset_top = 30
	vb.offset_bottom = -24
	vb.add_theme_constant_override("separation", 7)
	frame.add_child(vb)
	xp_bar = HudBar.new()
	xp_bar.title = "EXPERIENCE"
	xp_bar.tooltip_text = "Experience: fill it to gain a level"
	xp_bar.custom_minimum_size = Vector2(0, 18)
	xp_bar.icon = "star"
	xp_bar.col_lo = Color(0.5, 0.28, 0.03)
	xp_bar.col_hi = Color(1.0, 0.82, 0.32)
	xp_bar.glow = Color(1.0, 0.85, 0.4)
	stamina_bar = HudBar.new()
	stamina_bar.title = "STAMINA"
	stamina_bar.icon = "bolt"
	stamina_bar.ticks = 0
	stamina_bar.tooltip_text = "Stamina: hold Shift to sprint"
	stamina_bar.custom_minimum_size = Vector2(0, 14)
	stamina_bar.font_size = 11
	stamina_bar.col_lo = Color(0.03, 0.38, 0.16)
	stamina_bar.col_hi = Color(0.38, 0.95, 0.45)
	stamina_bar.glow = Color(0.55, 1.0, 0.6)
	vb.add_child(xp_bar)
	vb.add_child(stamina_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	skill_hb = hb
	skill_slots = {}
	for slot in ["Q", "E", "R", "_", "lmb", "rmb", "_", "F", "G", "V"]:
		if slot == "_":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(12, 0)
			hb.add_child(gap)
			continue
		var s := _bar_slot(slot)
		hb.add_child(s)
		skill_slots[slot] = s
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(18, 0)
	hb.add_child(sep)
	talent_badge = Button.new()
	talent_badge.anchor_left = 0.5
	talent_badge.anchor_right = 0.5
	talent_badge.anchor_top = 1.0
	talent_badge.anchor_bottom = 1.0
	talent_badge.offset_left = -130
	talent_badge.offset_right = 130
	talent_badge.offset_top = -bh - 40
	talent_badge.offset_bottom = -bh - 8
	talent_badge.add_theme_font_size_override("font_size", 15)
	talent_badge.visible = false
	talent_badge.pressed.connect(func(): toggle(talent_panel))
	root.add_child(talent_badge)
	for i in 4:
		var idx := i
		var b := _slot(Vector2(50, 50), func(ev): if ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT: hero.drink(idx), func(p, on): _hover(p, on, ""), str(i + 1))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_child(_keycap(str(i + 1)))
		hb.add_child(b)
		belt_slots.append(b)
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
	hint_lbl.offset_top = -bh - 52
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.text = "Left / right mouse and Q E R F G V: your skills (K to set them)  ·  N: talents  ·  Space: swing  ·  Shift: sprint  ·  1-4: potions  ·  I/C: inventory/stats  ·  T: portal  ·  Tab: map"
	root.add_child(hint_lbl)
	minimap = Minimap.new()
	minimap.ui = self
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -230
	minimap.offset_right = -18
	minimap.offset_top = 40
	minimap.offset_bottom = 252
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

## Rebuild the bar's skill slots from the hero's bindings (after a class change, a load or a rebind).
func refresh_skill_slots() -> void:
	if skill_hb == null or skill_slots.is_empty():
		return
	for slot in skill_slots.keys():
		var old: Control = skill_slots[slot]
		var s := _bar_slot(slot)
		skill_hb.add_child(s)
		skill_hb.move_child(s, old.get_index())
		old.queue_free()
		skill_slots[slot] = s
	tooltip.visible = false
	if skills_panel and skills_panel.visible:
		_fill_skills_panel()
	# the standard globes, unless this class is a special character with its own (Data.CLASSES "hud")
	if hero and life_globe and life_globe.mat:
		var hud: Dictionary = Data.CLASSES.get(hero.cls, {}).get("hud", {})
		life_globe.set_style(hud)
		mana_globe.set_style(hud)

const SLOT_NAMES := {"lmb": "Left mouse", "rmb": "Right mouse"}

## One bar slot: the Meshy socket, the bound skill's glyph, a cooldown shade, the key and the mana cost.
## Click it to choose what goes there.
func _bar_slot(slot: String) -> Control:
	var big := slot == "lmb" or slot == "rmb"
	var id: String = hero.bound(slot) if hero else ""
	var sk := Data.skill_def(id)
	var p := Control.new()
	p.custom_minimum_size = Vector2(84, 94) if big else Vector2(62, 64)
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	var bg := TextureRect.new()
	bg.texture = load(BAR_TEX["slot_big" if big else "slot"])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(bg)
	# the socket's hole: where the glyph and cooldown sit
	var hole := Control.new()
	hole.name = "hole"
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole.anchor_right = 1.0
	hole.anchor_bottom = 1.0
	if big:
		hole.offset_left = 21; hole.offset_right = -21; hole.offset_top = 32; hole.offset_bottom = -18
	else:
		hole.offset_left = 13; hole.offset_right = -13; hole.offset_top = 15; hole.offset_bottom = -13
	p.add_child(hole)
	var glyph := SkillGlyph.new()
	glyph.id = id
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.name = "glyph"
	glyph.scale_to = 0.62 if not big else 0.75
	hole.add_child(glyph)
	var cd := ColorRect.new()
	cd.name = "cd"
	cd.color = Color(0, 0, 0, 0.7)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.anchor_right = 1.0
	cd.anchor_bottom = 1.0
	cd.anchor_top = 1.0
	hole.add_child(cd)
	var cap := _keycap("L" if slot == "lmb" else ("R" if slot == "rmb" else slot))
	cap.position = Vector2(-4, -4) if not big else Vector2(-2, 6)
	p.add_child(cap)
	if not sk.is_empty() and int(sk["mana"]) > 0:
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", _box(Color(0.06, 0.1, 0.3, 0.95), Color(0.4, 0.55, 1.0), 1, 6, 0))
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost := _label(str(int(round(hero.skill_cost(id)))), 10, Color(0.75, 0.82, 1.0), true)
		cost.add_theme_constant_override("outline_size", 0)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.add_child(cost)
		pill.custom_minimum_size = Vector2(20, 13)
		pill.position = Vector2(p.custom_minimum_size.x - 24, p.custom_minimum_size.y - 16)
		p.add_child(pill)
	p.mouse_entered.connect(func():
		var where: String = SLOT_NAMES.get(slot, "Key " + slot)
		var lines := []
		if sk.is_empty():
			lines = [[where + ": empty", GOLD], ["Click to put a skill here, or drag one from the skills window (K)", DIM]]
		else:
			lines = [[sk["name"] + "   (" + where + ")", GOLD], [sk["desc"], Color(0.85, 0.82, 0.75)]]
			if int(sk["mana"]) > 0 or float(sk["cd"]) > 0.0:
				lines.append(["Mana: %d   Cooldown: %ss   Unlocks at level %d" % [int(round(hero.skill_cost(id))), str(snappedf(hero.skill_cd(id), 0.1)), sk["lvl"]], Color(0.55, 0.65, 1.0)])
			lines.append(["Click to change  ·  drag to move or swap  ·  drag off the bar to clear", DIM])
		show_tooltip(lines)
		tip_owner = p)
	p.mouse_exited.connect(func():
		tooltip.visible = false
		tip_owner = null)
	# drag a skill to another slot (they swap) or off the bar (cleared); a click without a drag opens the menu
	p.set_drag_forwarding(func(_at: Vector2): return _skill_drag(p, id, slot),
		func(_at: Vector2, data): return data is Dictionary and data.has("skill"),
		func(_at: Vector2, data): drop_skill(data, slot))
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and (ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
			if ev.pressed:
				_skill_dragged = false
			elif not _skill_dragged:
				_choose_skill(slot))
	return p

## Start dragging a skill (from a bar slot, or from the skills window when from_slot is "").
func _skill_drag(src: Control, id: String, from_slot: String) -> Variant:
	var sk := Data.skill_def(id)
	if sk.is_empty() or hero == null or (hero.level < int(sk["lvl"]) and not game.test_allskills):
		return null
	_skill_dragged = true
	_skill_drag_from = from_slot
	tooltip.visible = false
	var pv := Control.new()
	var bg := TextureRect.new()
	bg.texture = load(BAR_TEX["slot"])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(62, 64)
	bg.position = -bg.size * 0.5
	bg.modulate.a = 0.85
	pv.add_child(bg)
	var g := SkillGlyph.new()
	g.id = id
	g.size = Vector2(38, 38)
	g.position = -g.size * 0.5 + Vector2(0, 1)
	pv.add_child(g)
	src.set_drag_preview(pv)
	return {"skill": id, "from": from_slot}

## A skill dropped on a bar slot: it goes there; dragged from another slot, the two swap.
func drop_skill(data: Dictionary, slot: String) -> void:
	var id: String = data.get("skill", "")
	var from: String = data.get("from", "")
	_skill_drag_from = ""
	if from == slot:
		return
	var here := hero.bound(slot)
	hero.bind(slot, id)
	if from != "":
		hero.bind(from, here if (here != "" or from != "lmb") else "attack")
	Sfx.play("click")

func _notification(what: int) -> void:
	# a skill dragged off the bar and let go anywhere but a slot is taken off
	if what == NOTIFICATION_DRAG_END and _skill_drag_from != "":
		var from := _skill_drag_from
		_skill_drag_from = ""
		if not get_viewport().gui_is_drag_successful() and hero and from != "lmb" \
				and not action_bar.get_global_rect().has_point(get_viewport().get_mouse_position()):
			hero.bind(from, "")
			Sfx.play("click")

## A menu of every skill the class knows, to put on a bar slot.
## The skill picker: click a bar slot and this rises above it in the bar's own iron frame, one socket per
## skill this class knows (name, mana, which key has it now, locked ones greyed with their level).
## Click one to put it on the slot; click outside or press Esc to close.
func _choose_skill(slot: String) -> void:
	close_skill_picker()
	tooltip.visible = false
	var where: String = SLOT_NAMES.get(slot, "Key " + slot)
	var cover := Control.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_skill_picker())
	root.add_child(cover)
	skill_picker = cover
	var frame := NinePatchRect.new()
	frame.texture = load(BAR_TEX["frame"])
	for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]:
		frame.set(m, 62)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.modulate.a = 0.0
	cover.add_child(frame)
	# the frame's middle is open, so a dark backing sits inside it
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", _box(Color(0.03, 0.025, 0.02, 0.96), Color(0.2, 0.15, 0.09), 1, 4, 0))
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.offset_left = 22; back.offset_right = -22; back.offset_top = 22; back.offset_bottom = -22
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(back)
	var vb := VBoxContainer.new()
	vb.position = Vector2(40, 34)
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(vb)
	# header: the slot's keycap and what is being chosen
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var capwrap := Control.new()
	capwrap.custom_minimum_size = Vector2(20, 20)
	capwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _keycap("L" if slot == "lmb" else ("R" if slot == "rmb" else slot))
	cap.position = Vector2(0, 1)
	capwrap.add_child(cap)
	hb.add_child(capwrap)
	hb.add_child(_label("CHOOSE A SKILL FOR " + where.to_upper(), 17, GOLD, true))
	vb.add_child(hb)
	var rule := ColorRect.new()
	rule.color = Color(0.86, 0.72, 0.44, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(rule)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skills: Array = Data.skills_known(hero.cls)
	var n := skills.size() + (0 if slot == "lmb" else 1)
	grid.columns = mini(n, 8)
	vb.add_child(grid)
	for sk in skills:
		grid.add_child(_picker_card(slot, sk))
	if slot != "lmb":
		grid.add_child(_picker_card(slot, {}))
	var foot := _label("Tip: drag skills between slots to swap them  ·  drag one off the bar to clear it", 11, DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(foot)
	# size the frame around its contents once laid out, then stand it on the clicked slot, kept on screen
	_place_picker.call_deferred(frame, vb, slot)
	Sfx.play("click")

func _place_picker(frame: NinePatchRect, vb: VBoxContainer, slot: String) -> void:
	if not is_instance_valid(frame):
		return
	var inner := vb.get_combined_minimum_size()
	vb.size = inner
	var sz := inner + Vector2(80, 64)
	frame.size = sz
	var src: Control = skill_slots.get(slot)
	var vp := get_viewport().get_visible_rect().size
	var at := Vector2(vp.x * 0.5, vp.y - 220)
	if src:
		var r := src.get_global_rect()
		at = Vector2(r.get_center().x, (action_bar.get_global_rect().position.y if action_bar else r.position.y) + 10)
	frame.position = Vector2(clampf(at.x - sz.x * 0.5, 8, vp.x - sz.x - 8), maxf(8, at.y - sz.y))
	# rise in from the slot
	frame.pivot_offset = Vector2(clampf(at.x - frame.position.x, 0, sz.x), sz.y)
	frame.scale = Vector2(0.92, 0.85)
	var tw := frame.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.18)
	tw.tween_property(frame, "modulate:a", 1.0, 0.12)

func close_skill_picker() -> bool:
	if skill_picker == null or not is_instance_valid(skill_picker):
		skill_picker = null
		return false
	skill_picker.queue_free()
	skill_picker = null
	tooltip.visible = false
	tip_owner = null
	return true

## One skill in the picker (an empty dictionary is the "clear this slot" socket).
func _picker_card(slot: String, sk: Dictionary) -> Control:
	var id: String = sk.get("id", "")
	var locked: bool = not sk.is_empty() and hero.level < int(sk["lvl"]) and not game.test_allskills
	var current := hero.bound(slot) == id
	var on_key := ""
	if id != "":
		for k in ["lmb", "rmb", "Q", "E", "R", "F", "G", "V"]:
			if k != slot and hero.bound(k) == id:
				on_key = "L" if k == "lmb" else ("R" if k == "rmb" else k)
				break
	var card := PanelContainer.new()
	var idle := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 1, 6, 4)
	var cur := _box(Color(0.35, 0.25, 0.08, 0.35), Color(1.0, 0.82, 0.4), 2, 6, 4)
	var hot := _box(Color(0.3, 0.22, 0.1, 0.3), Color(0.86, 0.72, 0.44, 0.8), 1, 6, 4)
	card.add_theme_stylebox_override("panel", cur if current else idle)
	card.custom_minimum_size = Vector2(86, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var sock := Control.new()
	sock.custom_minimum_size = Vector2(62, 64)
	sock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sock)
	var bg := TextureRect.new()
	bg.texture = load(BAR_TEX["slot"])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sock.add_child(bg)
	var hole := Control.new()
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole.anchor_right = 1.0
	hole.anchor_bottom = 1.0
	hole.offset_left = 13; hole.offset_right = -13; hole.offset_top = 15; hole.offset_bottom = -13
	sock.add_child(hole)
	if id != "":
		var g := SkillGlyph.new()
		g.id = id
		g.scale_to = 0.62
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hole.add_child(g)
	else:
		var x := _label("×", 26, Color(0.6, 0.5, 0.4), true)
		x.set_anchors_preset(Control.PRESET_FULL_RECT)
		x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hole.add_child(x)
	if locked:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.62)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hole.add_child(shade)
		var lv := _label("LV %d" % int(sk["lvl"]), 12, Color(0.95, 0.5, 0.35), true)
		lv.set_anchors_preset(Control.PRESET_FULL_RECT)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hole.add_child(lv)
	elif id != "" and int(sk["mana"]) > 0:
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", _box(Color(0.06, 0.1, 0.3, 0.95), Color(0.4, 0.55, 1.0), 1, 6, 0))
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost := _label(str(int(round(hero.skill_cost(id)))), 10, Color(0.75, 0.82, 1.0), true)
		cost.add_theme_constant_override("outline_size", 0)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.add_child(cost)
		pill.custom_minimum_size = Vector2(20, 13)
		pill.position = Vector2(38, 48)
		sock.add_child(pill)
	if on_key != "":
		var kc := _keycap(on_key)
		kc.modulate = Color(1, 1, 1, 0.85)
		kc.position = Vector2(-4, -4)
		sock.add_child(kc)
	var nm := _label(sk.get("name", "Empty"), 13, Color(1.0, 0.86, 0.5) if current else (Color(0.5, 0.47, 0.42) if locked else Color(0.88, 0.84, 0.76)), current)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.custom_minimum_size = Vector2(80, 0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(nm)
	if current:
		var tag := _label("EQUIPPED", 10, GOLD, true)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tag)
		var tw := card.create_tween().set_loops()
		tw.tween_property(card, "self_modulate", Color(1.25, 1.15, 0.9), 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(card, "self_modulate", Color(1, 1, 1), 0.8).set_trans(Tween.TRANS_SINE)
	var where: String = SLOT_NAMES.get(slot, "key " + slot)
	card.mouse_entered.connect(func():
		if not current:
			card.add_theme_stylebox_override("panel", hot)
		sock.pivot_offset = sock.size * 0.5
		sock.create_tween().tween_property(sock, "scale", Vector2(1.08, 1.08), 0.08)
		var lines := []
		if id == "":
			lines = [["Empty", GOLD], ["Take the skill off " + where, DIM]]
		else:
			lines = [[sk["name"], GOLD], [sk["desc"], Color(0.85, 0.82, 0.75)]]
			if int(sk["mana"]) > 0 or float(sk["cd"]) > 0.0:
				lines.append(["Mana: %d   Cooldown: %ss" % [int(round(hero.skill_cost(id))), str(snappedf(hero.skill_cd(id), 0.1))], Color(0.55, 0.65, 1.0)])
			if locked:
				lines.append(["Unlocks at level %d" % int(sk["lvl"]), Color(0.95, 0.5, 0.35)])
			elif current:
				lines.append(["Already on " + where, GOLD])
			elif on_key != "" and BIND_KEYS_UI.has(slot):
				lines.append(["Click to move it from %s to %s" % [on_key, where], DIM])
			else:
				lines.append(["Click to put it on " + where, DIM])
		show_tooltip(lines)
		tip_owner = card)
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", cur if current else idle)
		sock.create_tween().tween_property(sock, "scale", Vector2.ONE, 0.1)
		tooltip.visible = false
		tip_owner = null)
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if locked:
				message("%s unlocks at level %d" % [sk["name"], int(sk["lvl"])], Color(0.95, 0.5, 0.35))
				return
			hero.bind(slot, id)
			Sfx.play("click")
			close_skill_picker())
	return card

# ---------------------------------------------------------------- skills window (K)
## Every skill the class knows, with buttons to put each on the left or right mouse button or a
## hotkey. Hovering a skill and pressing Q E R F G V also binds it.
var _hover_skill := ""
func _build_skills_panel() -> void:
	skills_panel = _panel("Skills", true, 560, 420)
	var vb: VBoxContainer = skills_panel.get_node("vb")
	var help := _label("Drag a skill onto the bar, use the buttons, or hover a skill and press Q, E, R, F, G or V.", 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(520, 0)
	vb.add_child(help)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(540, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var tb := Button.new()
	tb.text = "Talents (N)"
	tb.pressed.connect(func(): toggle(talent_panel))
	vb.add_child(tb)
	skill_rows = VBoxContainer.new()
	skill_rows.add_theme_constant_override("separation", 8)
	skill_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(skill_rows)
	skills_panel.visibility_changed.connect(func():
		if skills_panel.visible:
			_fill_skills_panel())

func _fill_skills_panel() -> void:
	for c in skill_rows.get_children():
		c.queue_free()
	for sk in Data.skills_known(hero.cls):
		var id: String = sk["id"]
		var locked: bool = hero.level < int(sk["lvl"]) and not game.test_allskills
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _box(Color(0.05, 0.045, 0.04, 0.9), Color(0.32, 0.25, 0.15), 1, 4, 6))
		row.mouse_entered.connect(func(): _hover_skill = id)
		row.mouse_exited.connect(func(): if _hover_skill == id: _hover_skill = "")
		row.set_drag_forwarding(func(_at: Vector2): return _skill_drag(row, id, ""), Callable(), Callable())
		skill_rows.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ibg := TextureRect.new()
		ibg.texture = load(BAR_TEX["slot"])
		ibg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ibg.set_anchors_preset(Control.PRESET_FULL_RECT)
		ibg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(ibg)
		var g := SkillGlyph.new()
		g.id = id
		g.dim = locked
		g.scale_to = 0.55
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.offset_left = 9; g.offset_right = -9; g.offset_top = 11; g.offset_bottom = -9
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(g)
		hb.add_child(icon)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tv)
		var head := str(sk["name"])
		if locked:
			head += "   (unlocks at level %d)" % sk["lvl"]
		elif int(sk["mana"]) > 0:
			head += "   %d mana" % int(round(hero.skill_cost(id))) + ("   %ss cooldown" % str(snappedf(hero.skill_cd(id), 0.1)) if float(sk["cd"]) > 0.0 else "")
		tv.add_child(_label(head, 15, GOLD if not locked else DIM, true))
		var d := _label(str(sk["desc"]), 12, Color(0.8, 0.77, 0.7))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(250, 0)
		tv.add_child(d)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		hb.add_child(grid)
		for slot in ["lmb", "rmb", "Q", "E", "R", "F", "G", "V"]:
			var b := Button.new()
			b.text = "L" if slot == "lmb" else ("R🖱" if slot == "rmb" else slot)
			if slot == "lmb":
				b.text = "LMB"
			elif slot == "rmb":
				b.text = "RMB"
			b.custom_minimum_size = Vector2(40, 28)
			b.toggle_mode = true
			b.button_pressed = hero.bound(slot) == id
			b.disabled = locked
			b.tooltip_text = "Put %s on %s" % [sk["name"], SLOT_NAMES.get(slot, "key " + slot)]
			var sl: String = slot
			b.pressed.connect(func():
				hero.bind(sl, "" if (hero.bound(sl) == id and sl != "lmb") else id)
				Sfx.play("click"))
			grid.add_child(b)

## In the skills window, hovering a skill and pressing a hotkey binds it there.
func skills_hotkey(key: String) -> bool:
	if skills_panel == null or not skills_panel.visible or _hover_skill == "":
		return false
	var sk := Data.skill_def(_hover_skill)
	if sk.is_empty() or (hero.level < int(sk["lvl"]) and not game.test_allskills):
		return true
	hero.bind(key, _hover_skill)
	Sfx.play("click")
	return true

# ---------------------------------------------------------------- talents window (N)
## Three trees side by side, four rows each; left click learns a rank, right click gives it back.
func _build_talent_panel() -> void:
	talent_panel = _panel("Talents", true, 960, 600)
	var vb: VBoxContainer = talent_panel.get_node("vb")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	talent_head = _label("", 17, GOLD, true)
	talent_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(talent_head)
	var auto := Button.new()
	auto.text = "Auto-assign"
	auto.tooltip_text = "Spend your free points on a suggested build"
	auto.pressed.connect(func():
		hero.auto_talents()
		Sfx.play("click"))
	top.add_child(auto)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Take back every point (free)"
	reset.pressed.connect(func():
		hero.reset_talents()
		Sfx.play("click"))
	top.add_child(reset)
	talent_cols = HBoxContainer.new()
	talent_cols.add_theme_constant_override("separation", 12)
	vb.add_child(talent_cols)
	var help := _label("Left click: learn a rank   ·   Right click: take it back   ·   A row opens once enough points are spent above it in the same tree. One point each level.", 12, DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(help)
	talent_panel.visibility_changed.connect(func():
		if talent_panel.visible:
			skills_panel.visible = false
			_fill_talents()
		else:
			_talent_hover = ""
		if hero:
			refresh())

const TALENT_ICON := "res://assets/textures/talents/%s.png"
static var _grey: ShaderMaterial

## Shut or untaken talents: the painted icon drained of colour and darkened.
static func _grey_mat() -> ShaderMaterial:
	if _grey == null:
		_grey = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item; void fragment(){ vec4 c = texture(TEXTURE, UV); float l = dot(c.rgb, vec3(0.3, 0.59, 0.11)); COLOR = vec4(vec3(l * 0.55), c.a); }"
		_grey.shader = sh
	return _grey

func _talent_sig() -> String:
	return "%s %s %d" % [hero.cls, str(hero.talents), hero.level]

func _fill_talents() -> void:
	_talent_shown = _talent_sig()
	for c in talent_cols.get_children():
		talent_cols.remove_child(c)
		c.queue_free()
	var free: int = hero.free_talent_points()
	talent_head.text = ("%d talent point%s to spend" % [free, "" if free == 1 else "s"]) if free > 0 else "No points to spend: you get one each level"
	var ts := Talents.trees(hero.cls)
	for i in ts.size():
		var tree: Dictionary = ts[i]
		var col := PanelContainer.new()
		col.add_theme_stylebox_override("panel", _box(Color(0.05, 0.045, 0.04, 0.9), Color(0.32, 0.25, 0.15), 1, 4, 10))
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		talent_cols.add_child(col)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 0)
		col.add_child(cv)
		var spent := Talents.tree_spent(hero.cls, i, hero.talents)
		var hh := HBoxContainer.new()
		hh.alignment = BoxContainer.ALIGNMENT_CENTER
		hh.add_theme_constant_override("separation", 10)
		cv.add_child(hh)
		var em := TALENT_ICON % ("%s_tree%d" % [hero.cls, i])
		if ResourceLoader.exists(em):
			var emr := TextureRect.new()
			emr.texture = load(em)
			emr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			emr.custom_minimum_size = Vector2(40, 40)
			emr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hh.add_child(emr)
		var head := _label("%s   %d" % [tree["name"], spent], 21, GOLD, true)
		hh.add_child(head)
		var d := _label(tree["desc"], 12, DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(270, 34)
		cv.add_child(d)
		for row in Talents.ROW_REQ.size():
			var open := Talents.row_open(hero.cls, i, row, hero.talents)
			# a shut row says what opens it, just above it
			var need := _label("" if open else "needs %d points in %s" % [Talents.ROW_REQ[row], tree["name"]], 11, Color(0.6, 0.45, 0.3))
			need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			need.custom_minimum_size = Vector2(0, 18)
			need.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			cv.add_child(need)
			var rh := HBoxContainer.new()
			rh.alignment = BoxContainer.ALIGNMENT_CENTER
			rh.add_theme_constant_override("separation", 26)
			cv.add_child(rh)
			for t in tree["talents"]:
				if int(t["row"]) == row:
					rh.add_child(_talent_node(t, i, open))

## One talent: its icon in a socket, ranks taken, a gold rim when a point can go in.
func _talent_node(t: Dictionary, tree: int, open: bool) -> Control:
	var id: String = t["id"]
	var rank := int(hero.talents.get(id, 0))
	var mx := int(t["max"])
	var can := Talents.can_learn(hero.cls, id, hero.talents, hero.free_talent_points())
	var p := Control.new()
	p.custom_minimum_size = Vector2(76, 78)
	p.name = id
	var bg := TextureRect.new()
	bg.texture = load(BAR_TEX["slot"])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = Color(1, 1, 1) if open else Color(0.45, 0.45, 0.45)
	p.add_child(bg)
	# the painted icon (tools/talent_icons.py), else the drawn glyph; greyed until a point can go in
	var g: Control
	var tex := TALENT_ICON % id
	if ResourceLoader.exists(tex):
		var tr := TextureRect.new()
		tr.texture = load(tex)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		if rank == 0 and not can:
			tr.material = _grey_mat()
		g = tr
	else:
		var sg := SkillGlyph.new()
		sg.id = t["icon"]
		sg.dim = rank == 0 and not can
		g = sg
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.offset_left = 10; g.offset_right = -10; g.offset_top = 11; g.offset_bottom = -9
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(g)
	var rim := Panel.new()
	var rim_col := Color(1.0, 0.82, 0.35) if can else (Color(0.45, 0.85, 0.4) if rank >= mx else Color(0, 0, 0, 0))
	var sb := _box(Color(0, 0, 0, 0), rim_col, 2, 6, 0)
	sb.shadow_size = 0
	rim.add_theme_stylebox_override("panel", sb)
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.offset_left = 8; rim.offset_right = -8; rim.offset_top = 9; rim.offset_bottom = -7
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(rim)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.03, 0.95), rim_col if rank > 0 or can else Color(0.3, 0.25, 0.18), 1, 4, 0))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rl := _label("%d/%d" % [rank, mx], 11, GOLD if rank > 0 else DIM, true)
	rl.add_theme_constant_override("outline_size", 0)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(rl)
	pill.custom_minimum_size = Vector2(28, 14)
	pill.position = Vector2(46, 64)
	p.add_child(pill)
	var tip := func():
		var lines := [[t["name"], GOLD], ["Rank %d / %d" % [rank, mx], DIM]]
		if rank > 0:
			lines.append([Talents.describe(t, rank), Color(0.85, 0.82, 0.75)])
		if rank < mx:
			lines.append([("Next rank: " if rank > 0 else "") + Talents.describe(t, rank + 1), Color(0.6, 0.85, 0.55) if rank > 0 else Color(0.85, 0.82, 0.75)])
		if not open:
			lines.append(["Needs %d points in %s" % [Talents.ROW_REQ[int(t["row"])], Talents.trees(hero.cls)[tree]["name"]], Color(1.0, 0.45, 0.35)])
		elif can:
			lines.append(["Left click to learn", DIM])
		if rank > 0:
			lines.append(["Right click to take back", DIM])
		show_tooltip(lines)
		tip_owner = p
	p.mouse_entered.connect(func():
		_talent_hover = id
		tip.call())
	p.mouse_exited.connect(func():
		if _talent_hover == id:
			_talent_hover = ""
		if tip_owner == p:
			tooltip.visible = false
			tip_owner = null)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play("click" if hero.learn_talent(id) else "deny")
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				Sfx.play("click" if hero.unlearn_talent(id) else "deny"))
	# rebuilt under the mouse after a click: keep its tooltip up
	if _talent_hover == id:
		tip.call()
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
	# beside the helm: draw it on the knight or not (its stats stay either way)
	helm_btn = Button.new()
	helm_btn.position = Vector2(92, 8)
	helm_btn.size = Vector2(90, 26)
	helm_btn.add_theme_font_size_override("font_size", 12)
	helm_btn.focus_mode = Control.FOCUS_NONE
	helm_btn.tooltip_text = "Show or hide your helm on your knight. Its stats count either way."
	helm_btn.pressed.connect(func():
		hero.show_helm = not hero.show_helm
		hero.refresh_gear()
		refresh())
	eq.add_child(helm_btn)
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
			hero.equip_from_inventory(idx)
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
	for pnl in [inv_panel, char_panel, stash_panel, shop_panel, wp_panel, dialog_panel, action_bar, skills_panel, talent_panel]:
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
				hero.move_in_inventory(idx, j)
				Sfx.play("pickup", -6.0, 1.2)
				click_fx(inv_cells[j])
		"equip":
			hero.equip_from_inventory(idx)
	refresh()

# ---------------------------------------------------------------- character
# ---------------------------------------------------------------- character sheet (C)
## Meshy-painted: an iron-and-leather panel, a crowned portrait frame round a live view of the hero (a
## second camera on the same world, so it shows the gear he's wearing), a medallion per attribute, and a
## + to spend points. Every line says in plain words what it does; hover for the exact numbers.
const SHEET_TEX := {"panel": "res://assets/textures/ui/sheet_panel.png", "portrait": "res://assets/textures/ui/sheet_portrait.png",
	"str": "res://assets/textures/ui/sheet_str.png", "dex": "res://assets/textures/ui/sheet_dex.png", "vit": "res://assets/textures/ui/sheet_vit.png",
	"ene": "res://assets/textures/ui/sheet_ene.png", "plus": "res://assets/textures/ui/sheet_plus.png", "divider": "res://assets/textures/ui/sheet_divider.png"}
const STAT_INFO := {
	"str": ["Strength", "Hit harder", Color(1.0, 0.55, 0.35)],
	"dex": ["Dexterity", "Attack faster, defend and block better", Color(0.5, 1.0, 0.55)],
	"vit": ["Vitality", "More life and stamina", Color(1.0, 0.4, 0.42)],
	"ene": ["Energy", "More mana for your skills", Color(0.45, 0.7, 1.0)],
}
var sheet_view: SubViewport
var sheet_cam: Camera3D
var sheet_points: PanelContainer
var _sheet_t := 0.0

func _build_character() -> void:
	char_panel = _panel("Character", true, 488, 520)
	var sb := StyleBoxTexture.new()
	sb.texture = load(SHEET_TEX["panel"])
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 100)   # the whole corner piece, never stretched
	# keep everything inside the gold trim, clear of the iron border and its corner pieces
	sb.set_content_margin(SIDE_LEFT, 62)
	sb.set_content_margin(SIDE_RIGHT, 62)
	sb.set_content_margin(SIDE_TOP, 50)
	sb.set_content_margin(SIDE_BOTTOM, 88)   # above the bottom corner pieces
	char_panel.add_theme_stylebox_override("panel", sb)
	var vb: VBoxContainer = char_panel.get_node("vb")
	vb.add_theme_constant_override("separation", 5)
	(vb.get_child(0).get_node("title") as Label).text = ""
	(vb.get_child(1) as Control).visible = false     # the title's underline
	# --- header: the portrait in its crowned frame, the name, class, level and experience
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	var port := Control.new()
	port.custom_minimum_size = Vector2(128, 128)
	head.add_child(port)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	var hole := 128.0 * 0.478
	svc.position = Vector2(64 - hole * 0.5, 128 * 0.56 - hole * 0.5)
	svc.size = Vector2(hole, hole)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port.add_child(svc)
	sheet_view = SubViewport.new()
	sheet_view.size = Vector2i(160, 160)
	sheet_view.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	sheet_view.own_world_3d = false
	svc.add_child(sheet_view)
	sheet_cam = Camera3D.new()
	sheet_cam.fov = 30
	sheet_view.add_child(sheet_cam)
	# a soft key light on the face, so the portrait reads even at dusk or in a crypt
	var key_light := OmniLight3D.new()
	key_light.light_color = Color(1.0, 0.9, 0.78)
	key_light.light_energy = 1.6
	key_light.omni_range = 2.6
	key_light.light_cull_mask = 0xFFFFF
	sheet_cam.add_child(key_light)
	key_light.position = Vector3(0.5, 0.4, 0.0)
	var mask := Panel.new()
	var round_sb := StyleBoxFlat.new()
	round_sb.bg_color = Color(0, 0, 0, 0)
	round_sb.border_color = Color(0.03, 0.025, 0.02)
	round_sb.set_border_width_all(6)
	round_sb.set_corner_radius_all(int(hole * 0.5))
	mask.add_theme_stylebox_override("panel", round_sb)
	mask.position = svc.position - Vector2(4, 4)
	mask.size = svc.size + Vector2(8, 8)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port.add_child(mask)
	var frame := TextureRect.new()
	frame.texture = load(SHEET_TEX["portrait"])
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.size = Vector2(128, 128)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port.add_child(frame)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 3)
	head.add_child(hv)
	var nm := _label("", 24, GOLD, true)
	hv.add_child(nm)
	char_labels["name"] = nm
	var lv := _label("", 16, Color(0.86, 0.83, 0.77))
	hv.add_child(lv)
	char_labels["level"] = lv
	var xpb := ProgressBar.new()
	xpb.custom_minimum_size = Vector2(0, 16)
	xpb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03)
	bg.border_color = Color(0.5, 0.4, 0.22)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.85, 0.62, 0.2)
	fg.set_corner_radius_all(3)
	xpb.add_theme_stylebox_override("background", bg)
	xpb.add_theme_stylebox_override("fill", fg)
	hv.add_child(xpb)
	char_labels["xpbar"] = xpb
	var xpl := _label("", 12, DIM)
	hv.add_child(xpl)
	char_labels["xp"] = xpl
	# --- points to spend: a glowing banner, only when there are some
	sheet_points = PanelContainer.new()
	sheet_points.add_theme_stylebox_override("panel", _box(Color(0.25, 0.17, 0.04, 0.9), Color(1.0, 0.8, 0.35), 1, 6, 6))
	var pl := _label("", 16, Color(1.0, 0.9, 0.55), true)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_points.add_child(pl)
	char_labels["points"] = pl
	vb.add_child(sheet_points)
	# --- the four attributes
	for st in ["str", "dex", "vit", "ene"]:
		vb.add_child(_stat_row(st))
	var div := TextureRect.new()
	div.texture = load(SHEET_TEX["divider"])
	div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	div.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	div.custom_minimum_size = Vector2(0, 22)
	vb.add_child(div)
	# --- what it all adds up to, in two columns; hover each for what it means
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 3)
	# set into a dark inset, clear of the frame's trim and corner pieces
	var inset := PanelContainer.new()
	var isb := _box(Color(0.0, 0.0, 0.0, 0.32), Color(0.42, 0.33, 0.2, 0.45), 1, 4, 0)
	isb.content_margin_left = 12; isb.content_margin_right = 12
	isb.content_margin_top = 6; isb.content_margin_bottom = 6
	inset.add_theme_stylebox_override("panel", isb)
	inset.add_child(grid)
	vb.add_child(inset)
	for k in ["damage", "aspd", "defense", "block", "life", "mana", "res", "ls", "mf", "gf"]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var t := _label(_combat_name(k), 11, DIM)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(t)
		var v := _label("", 14, Color(0.97, 0.94, 0.86), true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(v)
		char_labels[k] = v
		var key: String = k
		cell.mouse_entered.connect(func(): show_tooltip(_combat_tip(key)); tip_owner = cell)
		cell.mouse_exited.connect(func(): tooltip.visible = false; tip_owner = null)
		grid.add_child(cell)

func _combat_name(k: String) -> String:
	return {"damage": "DAMAGE", "aspd": "ATTACK SPEED", "defense": "DEFENSE", "block": "BLOCK CHANCE", "life": "LIFE",
		"mana": "MANA", "res": "RESISTANCES", "ls": "LIFE STEAL", "mf": "MAGIC FIND", "gf": "GOLD FIND"}[k]

func _combat_tip(k: String) -> Array:
	var h = hero
	var cut := int(round(100.0 * float(h.armor) / (120.0 + float(h.armor))))
	match k:
		"damage": return [["Damage", GOLD], ["What each hit of your weapon does, before the monster's defense.", Color(0.88, 0.85, 0.78)],
			["Strength raises it by 1% a point; better weapons raise it most.", Color(0.6, 0.85, 0.6)]]
		"aspd": return [["Attack speed", GOLD], ["How quickly you swing: higher is faster. 1.00 is a normal sword.", Color(0.88, 0.85, 0.78)],
			["Dexterity and \"attack speed\" on gear raise it.", Color(0.6, 0.85, 0.6)]]
		"defense": return [["Defense", GOLD], ["Softens physical blows: right now hits do %d%% less damage." % cut, Color(0.88, 0.85, 0.78)],
			["Comes from your armour, and a little from Dexterity.", Color(0.6, 0.85, 0.6)]]
		"block": return [["Block chance", GOLD], ["With a shield, the chance to stop a blow from the front completely (up to 60%).", Color(0.88, 0.85, 0.78)],
			["Hold your block skill for 80% less damage from the front.", Color(0.6, 0.85, 0.6)]]
		"life": return [["Life", GOLD], ["How much damage you can take. You regain %.1f life a second." % h.regen, Color(0.88, 0.85, 0.78)],
			["Vitality gives 3 a point; each level gives 4.", Color(0.6, 0.85, 0.6)]]
		"mana": return [["Mana", GOLD], ["Spent to use your skills, and slowly refills.", Color(0.88, 0.85, 0.78)],
			["Energy gives 2 a point.", Color(0.6, 0.85, 0.6)]]
		"res": return [["Resistances", GOLD], ["Cuts damage from fire, poison and other magic (up to 75%).", Color(0.88, 0.85, 0.78)],
			["Comes from \"resist\" on gear.", Color(0.6, 0.85, 0.6)]]
		"ls": return [["Life steal", GOLD], ["Heals you for this share of the damage you deal (up to 25%).", Color(0.88, 0.85, 0.78)]]
		"mf": return [["Magic find", GOLD], ["Better odds that monsters drop magic, rare and unique items.", Color(0.88, 0.85, 0.78)]]
		"gf": return [["Gold find", GOLD], ["More gold from every pile you pick up.", Color(0.88, 0.85, 0.78)]]
	return [[k, GOLD]]

## One attribute: its medallion, name, what it does in a few words, its value, and a + to spend a point.
func _stat_row(st: String) -> Control:
	var info: Array = STAT_INFO[st]
	var row := PanelContainer.new()
	var rsb := _box(Color(0.0, 0.0, 0.0, 0.28), Color(0.4, 0.32, 0.18, 0.5), 1, 6, 4)
	row.add_theme_stylebox_override("panel", rsb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = load(SHEET_TEX[st])
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(46, 46)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	tv.add_child(_label(info[0], 18, info[2], true))
	var blurb := _label(info[1], 12, Color(0.78, 0.75, 0.68))
	tv.add_child(blurb)
	var val := _label("", 26, Color(1, 1, 1), true)
	val.custom_minimum_size = Vector2(54, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.pivot_offset = Vector2(27, 16)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(val)
	char_labels[st] = val
	var b := TextureButton.new()
	b.texture_normal = load(SHEET_TEX["plus"])
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(36, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = ""
	b.pressed.connect(func():
		if hero.stat_points <= 0:
			return
		_add_stat(st)
		var tw := val.create_tween()
		val.scale = Vector2(1.35, 1.35)
		val.modulate = Color(1.0, 0.85, 0.4)
		tw.set_parallel(true)
		tw.tween_property(val, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(val, "modulate", Color(1, 1, 1), 0.5)
		show_tooltip(_stat_tip(st)))
	hb.add_child(b)
	plus_btns.append(b)
	row.mouse_entered.connect(func():
		rsb.border_color = Color(info[2].r, info[2].g, info[2].b, 0.9)
		row.add_theme_stylebox_override("panel", rsb)
		show_tooltip(_stat_tip(st))
		tip_owner = row)
	row.mouse_exited.connect(func():
		rsb.border_color = Color(0.4, 0.32, 0.18, 0.5)
		row.add_theme_stylebox_override("panel", rsb)
		tooltip.visible = false
		tip_owner = null)
	return row

## What an attribute does: per point, and what yours adds up to right now.
func _stat_tip(st: String) -> Array:
	var h = hero
	var info: Array = STAT_INFO[st]
	var lines := [[info[0], info[2]]]
	var good := Color(0.55, 0.95, 0.55)
	var plain := Color(0.88, 0.85, 0.78)
	match st:
		"str":
			var v: int = h.total_str()
			lines.append(["Each point: +1% weapon damage.", plain])
			lines.append(["Yours now: +%d%% damage." % v, good])
		"dex":
			var v: int = h.total_dex()
			lines.append(["Each point: a little faster attacks (+0.2%),", plain])
			lines.append(["+1 defense for every 4 points, and +0.1% block with a shield.", plain])
			lines.append(["Yours now: +%.1f%% attack speed, +%d defense, +%.1f%% block." % [v * 0.2, v / 4, v * 0.1], good])
		"vit":
			var v: int = h.total_vit()
			lines.append(["Each point: +3 life and a little more stamina for sprinting.", plain])
			lines.append(["Yours now: +%d life, +%d stamina." % [v * 3, int(v * 0.6)], good])
		"ene":
			lines.append(["Each point: +2 mana for casting skills.", plain])
			lines.append(["Yours now: +%d mana." % (h.ene * 2), good])
	if h.stat_points > 0:
		lines.append(["Click + to spend a point here.", Color(1.0, 0.85, 0.45)])
	return lines

## The portrait's camera: a slow look at the hero's face and shoulders, from the front.
func _sheet_camera(delta: float) -> void:
	if sheet_cam == null or hero == null or not is_instance_valid(hero.rig):
		return
	_sheet_t += delta
	var head: Node3D = hero.J.get("head") if hero.J is Dictionary else null
	var c: Vector3 = head.global_position if head else hero.global_position + Vector3(0, 1.6, 0)
	var fwd: Vector3 = -hero.rig.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, 1)
	var side := fwd.cross(Vector3.UP).normalized()
	var at := c + Vector3(0, -0.12, 0)
	var eye := at + fwd * 1.35 + side * (0.3 + sin(_sheet_t * 0.4) * 0.15) + Vector3(0, 0.1, 0)
	sheet_cam.global_transform = Transform3D(Basis(), eye).looking_at(at)

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
		game.set_quality((game.quality + 1) % (game.max_quality() + 1))
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
	if game.UNLOCK_ALL_ACTS:
		var kit := Button.new()
		kit.text = "Testing panel (F8)"
		kit.pressed.connect(func():
			game.toggle_pause()
			toggle(test_panel))
		vb.add_child(kit)
	var fps := Button.new()
	fps.text = "Toggle FPS counter (F3)"
	fps.pressed.connect(func(): show_fps = not show_fps)
	vb.add_child(fps)
	var to_title := Button.new()
	to_title.text = "Save and Exit to Title"
	to_title.pressed.connect(func(): game.exit_to_title())
	vb.add_child(to_title)
	var save := Button.new()
	save.text = "Save and Quit"
	save.pressed.connect(func():
		game.save_game()
		get_tree().quit())
	vb.add_child(save)

## F8 testing panel: two switches, nothing else in the game changes.
func _build_test_panel() -> void:
	test_panel = PanelContainer.new()
	test_panel.anchor_left = 0.0
	test_panel.anchor_top = 0.0
	test_panel.offset_left = 20
	test_panel.offset_top = 60
	test_panel.offset_right = 330
	test_panel.offset_bottom = 400
	test_panel.visible = false
	test_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(test_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	test_panel.add_child(vb)
	vb.add_child(_label("Testing", 22, GOLD, true))
	var imm := CheckButton.new()
	imm.text = "Immortal (take no damage)"
	imm.button_pressed = game.test_immortal
	imm.toggled.connect(func(on: bool):
		game.test_immortal = on
		message("Immortal " + ("ON" if on else "off"), Color(0.6, 1.0, 0.6) if on else Color(0.8, 0.8, 0.8)))
	vb.add_child(imm)
	var one := CheckButton.new()
	one.text = "One-hit kill"
	one.button_pressed = game.test_onehit
	one.toggled.connect(func(on: bool):
		game.test_onehit = on
		message("One-hit kill " + ("ON" if on else "off"), Color(1.0, 0.7, 0.4) if on else Color(0.8, 0.8, 0.8)))
	vb.add_child(one)
	var sta := CheckButton.new()
	sta.text = "Infinite stamina"
	sta.button_pressed = game.test_stamina
	sta.toggled.connect(func(on: bool):
		game.test_stamina = on
		message("Infinite stamina " + ("ON" if on else "off"), Color(0.5, 1.0, 0.6) if on else Color(0.8, 0.8, 0.8)))
	vb.add_child(sta)
	var allsk := CheckButton.new()
	allsk.text = "Unlock all skills"
	allsk.button_pressed = game.test_allskills
	allsk.toggled.connect(func(on: bool):
		game.test_allskills = on
		message("All skills " + ("unlocked" if on else "back to their levels"), Color(0.6, 0.8, 1.0) if on else Color(0.8, 0.8, 0.8)))
	vb.add_child(allsk)
	# character level: pick a number and press Set
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lv.add_child(_label("Level", 16, Color(0.86, 0.83, 0.77)))
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 99
	spin.step = 1
	spin.custom_minimum_size = Vector2(90, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(spin)
	var setb := Button.new()
	setb.text = "Set"
	setb.custom_minimum_size = Vector2(60, 0)
	setb.pressed.connect(func():
		spin.apply()
		hero.set_level(int(spin.value))
		message("Level set to %d" % hero.level, Color(1.0, 0.85, 0.4)))
	lv.add_child(setb)
	vb.add_child(lv)
	test_panel.visibility_changed.connect(func():
		if test_panel.visible and hero:
			spin.value = hero.level)
	vb.add_child(_label("Level changes are saved; the switches are not.", 13, Color(0.7, 0.66, 0.58)))
	vb.add_child(_label("F8 or Esc to close.", 13, Color(0.7, 0.66, 0.58)))

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
	var chb := Button.new()
	chb.name = "characters"
	chb.text = "Characters"
	chb.custom_minimum_size = Vector2(0, 46)
	chb.pressed.connect(func(): open_characters())
	vb.add_child(chb)
	var ng := Button.new()
	ng.text = "New Character"
	ng.custom_minimum_size = Vector2(0, 46)
	ng.pressed.connect(func(): open_class_picker())
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
	_build_class_picker()
	_build_characters()
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

## New Game: choose a class.
func _build_class_picker() -> void:
	class_panel = Control.new()
	class_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	class_panel.visible = false
	title_panel.add_child(class_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.015, 0.95)
	class_panel.add_child(dim)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -770
	vb.offset_right = 770
	vb.offset_top = -250
	vb.offset_bottom = 250
	vb.add_theme_constant_override("separation", 18)
	class_panel.add_child(vb)
	var t := _label("Choose your path", 40, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var nrow := HBoxContainer.new()
	nrow.alignment = BoxContainer.ALIGNMENT_CENTER
	nrow.add_theme_constant_override("separation", 10)
	vb.add_child(nrow)
	nrow.add_child(_label("Name", 18, Color(0.84, 0.8, 0.74)))
	name_edit = LineEdit.new()
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(260, 40)
	name_edit.placeholder_text = "a name for your hero"
	nrow.add_child(name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
	var accents := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35)}
	for c in ["knight", "wraith", "demon", "warlock"]:
		var d: Dictionary = Data.CLASSES[c]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.05, 0.96), accents[c], 2, 8, 10))
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		card.add_child(cv)
		var nm := _label(d["name"], 30, accents[c], true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		var gl := HBoxContainer.new()
		gl.alignment = BoxContainer.ALIGNMENT_CENTER
		gl.add_theme_constant_override("separation", 6)
		cv.add_child(gl)
		for sk in Data.skills_for(c):
			var g := SkillGlyph.new()
			g.id = sk["id"]
			g.custom_minimum_size = Vector2(48, 48)
			gl.add_child(g)
		var ds := _label(d["desc"], 15, Color(0.84, 0.8, 0.74))
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(300, 0)
		cv.add_child(ds)
		var names := []
		for sk in Data.skills_for(c):
			names.append(sk["name"])
		var sl := _label("  ·  ".join(names), 13, Color(0.6, 0.7, 0.85))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(sl)
		var at := _label("Str %d   Dex %d   Vit %d   Energy %d" % [d["str"], d["dex"], d["vit"], d["ene"]], 13, Color(0.7, 0.66, 0.58))
		cv.add_child(at)
		var go := Button.new()
		go.text = "Play as " + d["name"]
		go.custom_minimum_size = Vector2(0, 48)
		var cls_id: String = c
		go.pressed.connect(func():
			class_panel.visible = false
			game.start_game(false, cls_id, "", name_edit.text))
		cv.add_child(go)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): class_panel.visible = false)
	vb.add_child(back)

func open_class_picker() -> void:
	Sfx.play("click")
	chars_panel.visible = false
	name_edit.text = ""
	class_panel.visible = true

func show_title() -> void:
	title_panel.visible = true
	if class_panel:
		class_panel.visible = false
	if chars_panel:
		chars_panel.visible = false
	var chars: Array = game.list_characters()
	var cont := title_panel.find_child("continue", true, false) as Button
	cont.disabled = chars.is_empty()
	cont.text = "Continue" if chars.is_empty() else "Continue  ·  " + _char_line(chars[0])
	(title_panel.find_child("characters", true, false) as Button).visible = chars.size() > 1
	_set_hud(false)

func _char_line(c: Dictionary) -> String:
	var nm: String = c["name"] if str(c["name"]) != "" else "Unnamed"
	return "%s, level %d %s" % [nm, int(c["level"]), Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]]

## The saved characters: play one, delete one (asks twice), or make a new one.
func _build_characters() -> void:
	chars_panel = Control.new()
	chars_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	chars_panel.visible = false
	title_panel.add_child(chars_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.015, 0.95)
	chars_panel.add_child(dim)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -380
	vb.offset_right = 380
	vb.offset_top = -300
	vb.offset_bottom = 300
	vb.add_theme_constant_override("separation", 16)
	chars_panel.add_child(vb)
	var t := _label("Characters", 40, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	chars_list = VBoxContainer.new()
	chars_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chars_list.add_theme_constant_override("separation", 8)
	sc.add_child(chars_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var nb := Button.new()
	nb.text = "New Character"
	nb.custom_minimum_size = Vector2(200, 42)
	nb.pressed.connect(func(): open_class_picker())
	row.add_child(nb)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 42)
	back.pressed.connect(func(): chars_panel.visible = false)
	row.add_child(back)

func open_characters() -> void:
	Sfx.play("click")
	for c in chars_list.get_children():
		c.queue_free()
	var accents := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35)}
	for c in game.list_characters():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.05, 0.96), accents.get(c["cls"], GOLD), 2, 6, 10))
		chars_list.add_child(card)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		card.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		info.add_child(_label(str(c["name"]) if str(c["name"]) != "" else "Unnamed", 22, accents.get(c["cls"], GOLD), true))
		var run: String = Data.RUNS[int(c["difficulty"])]["name"] if int(c["difficulty"]) < Data.RUNS.size() else ""
		info.add_child(_label("Level %d %s  ·  %s" % [int(c["level"]), Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"], run], 14, Color(0.75, 0.7, 0.62)))
		var id: String = c["id"]
		var play := Button.new()
		play.text = "Play"
		play.custom_minimum_size = Vector2(110, 40)
		play.pressed.connect(func():
			chars_panel.visible = false
			game.start_game(true, "knight", id))
		hb.add_child(play)
		var del := Button.new()
		del.text = "Delete"
		del.custom_minimum_size = Vector2(110, 40)
		del.pressed.connect(func():
			if del.text == "Delete":
				del.text = "Sure?"
				return
			game.delete_character(id)
			open_characters()
			show_title()
			chars_panel.visible = not game.list_characters().is_empty())
		hb.add_child(del)
	chars_panel.visible = true

func hide_title() -> void:
	title_panel.visible = false
	_set_hud(true)

func _set_hud(v: bool) -> void:
	for n in [life_globe, mana_globe, life_lbl, mana_lbl, action_bar, zone_lbl, hint_lbl, minimap]:
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
	var s := _label("King Grubb the Gilded is dead, and his hoard is yours.", 19, Color(0.85, 0.82, 0.75))
	s.name = "vsub"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var a2 := Button.new()
	a2.name = "a2btn"
	a2.text = "Begin A2: start over at the camp with your hero"
	a2.custom_minimum_size = Vector2(0, 50)
	a2.pressed.connect(func(): game.start_a2())
	vb.add_child(a2)
	var a2n := _label(game.run_note(1), 15, Color(1.0, 0.6, 0.4))
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
	(victory_panel.find_child("vsub", true, false) as Label).text = "The Ashen King crumbles to cinders. His crown rolls across the throne room floor." if diff >= 2 else "King Grubb the Gilded is dead, and his hoard is yours."
	(victory_panel.find_child("a2btn", true, false) as Button).text = ["Begin A2", "Begin A3", "Play A3 again"][clampi(diff, 0, 2)] + ": start over at the camp with your hero"
	(victory_panel.find_child("a2note", true, false) as Label).text = ("In A3 the Ashen King takes Grubb's throne and always drops his sword. " + game.run_note(2)) if diff >= 1 else game.run_note(1)
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
	var any := close_skill_picker()
	for p in [inv_panel, char_panel, shop_panel, stash_panel, wp_panel, dialog_panel, ench_panel, test_panel, skills_panel, talent_panel]:
		if p.visible:
			p.visible = false
			any = true
	shop_mode = ""
	tooltip.visible = false
	return any

func any_panel_open() -> bool:
	return inv_panel.visible or char_panel.visible or shop_panel.visible or stash_panel.visible or wp_panel.visible or dialog_panel.visible or ench_panel.visible or skills_panel.visible or talent_panel.visible

func message(t: String, col := Color(1, 1, 1), dur := 2.5) -> void:
	msg_lbl.text = t
	msg_lbl.add_theme_color_override("font_color", col)
	msg_t = dur

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
	# King Grubb: a gold notch where each of his sacks bursts
	for c in boss_bar.get_children():
		c.queue_free()
	if e != null and e.hoard != null:
		for f in Hoard.SPILLS:
			var n := ColorRect.new()
			n.color = Color(1.0, 0.8, 0.3)
			n.anchor_left = f
			n.anchor_right = f
			n.anchor_bottom = 1.0
			n.offset_left = -1
			n.offset_right = 2
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			boss_bar.add_child(n)

## The experience bar's text, with a Sunstar Bloom's or an Experience Shrine's bonus counting down.
func _xp_detail() -> String:
	var need := Data.xp_for_level(hero.level)
	var pct := int(float(hero.xp) / maxf(need, 1.0) * 100.0)
	var t := ("%d / %d   (%d%%)" % [hero.xp, need, pct]) if level_medal else ("Level %d   ·   %d / %d   (%d%%)" % [hero.level, hero.xp, need, pct])
	if game.xp_bonus_t > 0.0:
		t += "   ·   +50%% XP %d:%02d" % [int(game.xp_bonus_t) / 60, int(game.xp_bonus_t) % 60]
	return t

func refresh() -> void:
	if hero == null:
		return
	_refresh_enchant()
	life_lbl.text = "Life  %d / %d" % [int(hero.life), int(hero.max_life)]
	mana_lbl.text = "Mana  %d / %d" % [int(hero.mana), int(hero.max_mana)]
	var xpf := float(hero.xp) / maxf(Data.xp_for_level(hero.level), 1.0)
	xp_bar.value = xpf
	if level_medal:
		level_medal.level = hero.level
		level_medal.xp = xpf
	xp_bar.detail = _xp_detail()
	for i in 4:
		_set_slot(belt_slots[i], hero.belt[i])
	if inv_panel.visible:
		for i in 40:
			_set_slot(inv_cells[i], hero.inventory[i])
		for k in equip_cells.keys():
			_set_slot(equip_cells[k], hero.equipment.get(k))
		helm_btn.visible = hero.cls == "knight"
		helm_btn.text = "Helm: shown" if hero.show_helm else "Helm: hidden"
		gold_lbl.text = "Gold: %d" % hero.gold
	if stash_panel.visible:
		for i in 60:
			_set_slot(stash_cells[i], hero.stash[i])
	var free: int = hero.free_talent_points()
	talent_badge.visible = free > 0 and not talent_panel.visible
	talent_badge.text = "%d talent point%s to spend  (N)" % [free, "" if free == 1 else "s"]
	if talent_panel.visible and _talent_sig() != _talent_shown:
		_fill_talents()
	if char_panel.visible:
		var cls: Dictionary = Data.CLASSES.get(hero.cls, {})
		var pname: String = game.char_name if game.char_name != "" else str(cls.get("name", "Hero"))
		char_labels["name"].text = pname
		char_labels["level"].text = "%s  ·  Level %d" % [str(cls.get("name", hero.cls.capitalize())), hero.level]
		var need: int = Data.xp_for_level(hero.level)
		(char_labels["xpbar"] as ProgressBar).max_value = maxf(1.0, float(need))
		(char_labels["xpbar"] as ProgressBar).value = float(hero.xp)
		char_labels["xp"].text = "Experience  %d / %d" % [hero.xp, need]
		sheet_points.visible = hero.stat_points > 0
		char_labels["points"].text = "★  %d point%s to spend  ·  click a +  ★" % [hero.stat_points, "" if hero.stat_points == 1 else "s"]
		char_labels["str"].text = "%d" % hero.total_str()
		char_labels["dex"].text = "%d" % hero.total_dex()
		char_labels["vit"].text = "%d" % hero.total_vit()
		char_labels["ene"].text = "%d" % hero.ene
		for b in plus_btns:
			(b as TextureButton).disabled = hero.stat_points <= 0
			(b as TextureButton).modulate = Color(1, 1, 1) if hero.stat_points > 0 else Color(0.35, 0.33, 0.3, 0.6)
		char_labels["damage"].text = "%d - %d%s" % [hero.dmg_min, hero.dmg_max, ("  +%d fire" % hero.fire_dmg) if hero.fire_dmg > 0 else ""]
		char_labels["aspd"].text = "%.2f" % hero.aspd
		char_labels["defense"].text = "%d" % hero.armor
		char_labels["block"].text = ("%d%%" % int(hero.block_chance)) if hero.equipment.get("shield") != null else "no shield"
		char_labels["life"].text = "%d" % int(hero.max_life)
		char_labels["mana"].text = "%d" % int(hero.max_mana)
		char_labels["res"].text = "%d%%" % hero.res
		char_labels["ls"].text = "%d%%" % int(hero.ls)
		char_labels["mf"].text = "%d%%" % hero.mf
		char_labels["gf"].text = "%d%%" % hero.gf

func _process(delta: float) -> void:
	_update_drag(delta)
	if char_panel and char_panel.visible and hero:
		_sheet_camera(delta)
		if sheet_points.visible:
			sheet_points.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(_sheet_t * 4.0))
	if join_panel and join_panel.visible:
		_join_refresh -= delta
		if _join_refresh <= 0.0:
			_join_refresh = 0.5
			_refresh_join()
	if hero:
		if game.xp_bonus_t > 0.0 or _xp_bonus_on:
			xp_bar.detail = _xp_detail()
			_xp_bonus_on = game.xp_bonus_t > 0.0
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
		if _slots_hero != hero:
			_slots_hero = hero          # the bar is built before the hero exists: fill it once he does
			refresh_skill_slots()
		life_globe.set_value(hero.life, hero.max_life)
		mana_globe.set_value(hero.mana, hero.max_mana)
		life_lbl.text = "Life  %d / %d" % [int(hero.life), int(hero.max_life)]
		mana_lbl.text = "Mana  %d / %d" % [int(hero.mana), int(hero.max_mana)]
		for slot in skill_slots.keys():
			var c: Control = skill_slots[slot]
			if not is_instance_valid(c) or not c.has_node("hole"):
				continue
			var sk := Data.skill_def(hero.bound(slot))
			var cdr: ColorRect = c.get_node("hole/cd")
			if sk.is_empty():
				cdr.anchor_top = 1.0
				continue
			var locked: bool = hero.level < int(sk["lvl"]) and not game.test_allskills
			var frac: float = 1.0 if locked else clampf(float(hero.cds.get(sk["id"], 0.0)) / maxf(hero.skill_cd(sk["id"]), 0.01), 0.0, 1.0)
			cdr.anchor_top = 1.0 - frac
			cdr.color = Color(0, 0, 0, 0.82) if locked else Color(0, 0, 0, 0.6)
			(c.get_node("hole/glyph") as SkillGlyph).dim = locked or hero.mana < hero.skill_cost(sk["id"])
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
	var scale_to := 1.0     # unused (kept for callers); the glyph scales to fit its box
	## The talents' own icons ("t_..."), for talents that aren't about one skill.
	func _talent_icon(c: Vector2, gold2: Color, steel: Color) -> void:
		var red := Color(0.85, 0.15, 0.12) if not dim else Color(0.35, 0.25, 0.25)
		var blue := Color(0.35, 0.55, 1.0) if not dim else Color(0.3, 0.32, 0.4)
		var green := Color(0.45, 0.9, 0.4) if not dim else Color(0.3, 0.36, 0.3)
		match id:
			"t_sword":
				draw_line(c + Vector2(0, 16), c + Vector2(0, -15), steel, 4.0, true)
				draw_line(c + Vector2(-8, 7), c + Vector2(8, 7), gold2, 3.0, true)
				draw_line(c + Vector2(0, 16), c + Vector2(0, 11), Color(0.45, 0.28, 0.15), 4.0, true)
			"t_haste":
				for k in 3:
					var o := Vector2(-10 + k * 9, 0)
					draw_polyline(PackedVector2Array([c + o + Vector2(-4, -10), c + o + Vector2(4, 0), c + o + Vector2(-4, 10)]), gold2, 3.0, true)
			"t_star":
				var pts := PackedVector2Array()
				for k in 10:
					var a := -PI / 2.0 + TAU * k / 10.0
					pts.append(c + Vector2(cos(a), sin(a)) * (16.0 if k % 2 == 0 else 7.0))
				draw_colored_polygon(pts, gold2)
			"t_hourglass":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -14), c + Vector2(10, -14), c + Vector2(0, 0)]), gold2)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(10, 14), c + Vector2(-10, 14)]), gold2.darkened(0.3))
				draw_line(c + Vector2(-12, -15), c + Vector2(12, -15), steel, 2.5, true)
				draw_line(c + Vector2(-12, 15), c + Vector2(12, 15), steel, 2.5, true)
			"t_heart":
				draw_circle(c + Vector2(-6, -4), 7.5, red)
				draw_circle(c + Vector2(6, -4), 7.5, red)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -1), c + Vector2(13, -1), c + Vector2(0, 14)]), red)
			"t_armor":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -10), c + Vector2(-6, -14), c + Vector2(0, -10), c + Vector2(6, -14), c + Vector2(14, -10), c + Vector2(11, 14), c + Vector2(-11, 14)]), steel.darkened(0.25))
				draw_line(c + Vector2(0, -9), c + Vector2(0, 13), gold2, 2.0, true)
			"t_ward":
				draw_arc(c, 14, 0, TAU, 28, blue, 3.0, true)
				draw_arc(c, 8, 0, TAU, 20, blue.lightened(0.3), 2.0, true)
				for k in 4:
					var a := TAU * k / 4.0 + PI / 4.0
					draw_line(c + Vector2(cos(a), sin(a)) * 14, c + Vector2(cos(a), sin(a)) * 19, gold2, 2.0, true)
			"t_regen":
				draw_rect(Rect2(c + Vector2(-4, -13), Vector2(8, 26)), red)
				draw_rect(Rect2(c + Vector2(-13, -4), Vector2(26, 8)), red)
				draw_arc(c, 17, -0.4, 1.6, 10, gold2, 2.0, true)
			"t_boot":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -14), c + Vector2(4, -14), c + Vector2(4, 4), c + Vector2(15, 8), c + Vector2(15, 14), c + Vector2(-6, 14)]), Color(0.55, 0.36, 0.2) if not dim else Color(0.32, 0.3, 0.28))
				for k in 3:
					draw_line(c + Vector2(-16, -6 + k * 7), c + Vector2(-10, -6 + k * 7), gold2, 2.0, true)
			"t_fist":
				draw_rect(Rect2(c + Vector2(-11, -8), Vector2(22, 16)), Color(0.8, 0.6, 0.45) if not dim else Color(0.4, 0.37, 0.35))
				for k in 3:
					draw_line(c + Vector2(-11 + (k + 1) * 5.5, -8), c + Vector2(-11 + (k + 1) * 5.5, 0), Color(0.3, 0.2, 0.15), 1.5, true)
				draw_rect(Rect2(c + Vector2(-8, 8), Vector2(16, 8)), steel.darkened(0.2))
			"t_eye":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 0), c + Vector2(0, -9), c + Vector2(16, 0), c + Vector2(0, 9)]), steel.darkened(0.5))
				draw_circle(c, 6, gold2)
				draw_circle(c, 2.5, Color(0.05, 0.05, 0.05))
			"t_skull":
				draw_circle(c + Vector2(0, -3), 11, steel)
				draw_rect(Rect2(c + Vector2(-6, 5), Vector2(12, 8)), steel)
				draw_circle(c + Vector2(-4.5, -3), 3, Color(0.05, 0.05, 0.05))
				draw_circle(c + Vector2(4.5, -3), 3, Color(0.05, 0.05, 0.05))
			"t_drop":
				draw_circle(c + Vector2(0, 5), 9, blue)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 1), c + Vector2(0, -15), c + Vector2(8, 1)]), blue)
			"t_fang":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -12), c + Vector2(-2, -12), c + Vector2(-7, 12)]), steel)
				draw_colored_polygon(PackedVector2Array([c + Vector2(2, -12), c + Vector2(12, -12), c + Vector2(7, 12)]), steel)
				draw_circle(c + Vector2(-7, 14), 2.5, red)
				draw_circle(c + Vector2(7, 14), 2.5, red)
			"t_orb":
				draw_circle(c, 12, green.darkened(0.3))
				draw_circle(c + Vector2(-3, -4), 5, green.lightened(0.3))
				draw_arc(c, 16, 0, TAU, 24, gold2, 1.5, true)
	func _draw() -> void:
		var c := size * 0.5
		# glyphs are drawn for a ~40 px box around the centre; scale them to whatever box this is
		var fit := minf(size.x, size.y) / 40.0
		draw_set_transform(c * (1.0 - fit), 0.0, Vector2(fit, fit))
		var steel := Color(0.85, 0.87, 0.92) if not dim else Color(0.4, 0.4, 0.42)
		var gold2 := Color(1.0, 0.8, 0.4) if not dim else Color(0.4, 0.35, 0.3)
		match id:
			"attack":
				# a sword, point up and to the right
				draw_line(c + Vector2(-11, 11), c + Vector2(12, -12), steel, 4.0, true)
				draw_line(c + Vector2(12, -12), c + Vector2(15, -15), steel, 2.0, true)
				draw_line(c + Vector2(-13, 4), c + Vector2(-4, 13), gold2, 3.0, true)
				draw_line(c + Vector2(-11, 11), c + Vector2(-16, 16), Color(0.45, 0.28, 0.15) if not dim else Color(0.3, 0.27, 0.25), 4.0, true)
				return
			"block":
				# a heater shield with a cross
				var pts := PackedVector2Array([c + Vector2(-13, -14), c + Vector2(13, -14), c + Vector2(13, 0), c + Vector2(0, 16), c + Vector2(-13, 0)])
				draw_colored_polygon(pts, Color(0.35, 0.08, 0.06) if not dim else Color(0.25, 0.2, 0.2))
				pts.append(pts[0])
				draw_polyline(pts, gold2, 2.5, true)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 11), gold2, 3.0, true)
				draw_line(c + Vector2(-9, -4), c + Vector2(9, -4), gold2, 3.0, true)
				return
			"":
				return
		if id.begins_with("t_"):
			_talent_icon(c, gold2, steel)
			return
		var col := Color(1.0, 0.8, 0.4) if not dim else Color(0.4, 0.35, 0.3)
		var wcol := Color(0.45, 0.88, 1.0) if not dim else Color(0.3, 0.35, 0.4)
		var dcol := Color(1.0, 0.45, 0.1) if not dim else Color(0.4, 0.3, 0.28)
		var dhot := Color(1.0, 0.85, 0.4) if not dim else Color(0.45, 0.38, 0.32)
		var lcol := Color(0.45, 1.0, 0.35) if not dim else Color(0.3, 0.36, 0.3)
		var lpale := Color(0.85, 1.0, 0.75) if not dim else Color(0.4, 0.43, 0.4)
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
			"reap":
				# a scythe: long haft and a sweeping crescent blade
				draw_line(c + Vector2(-12, 16), c + Vector2(8, -14), wcol, 3.0, true)
				draw_arc(c + Vector2(-2, -10), 15, PI * 1.05, PI * 1.95, 18, wcol, 4.0, true)
				draw_arc(c + Vector2(-2, -10), 11, PI * 1.15, PI * 1.85, 14, wcol.lightened(0.4), 1.5, true)
			"wail":
				# a screaming hooded face with rings of sound
				draw_arc(c + Vector2(0, -2), 9, PI, TAU, 14, wcol, 3.0, true)
				draw_circle(c + Vector2(-4, -3), 1.8, wcol)
				draw_circle(c + Vector2(4, -3), 1.8, wcol)
				draw_arc(c + Vector2(0, 4), 3.5, 0, TAU, 12, wcol, 2.0, true)
				for r in [14, 19]:
					draw_arc(c, r, -0.6, 0.6, 8, wcol, 1.5, true)
					draw_arc(c, r, PI - 0.6, PI + 0.6, 8, wcol, 1.5, true)
			"shade":
				# a fading silhouette streaking towards a bright one
				for k in 3:
					var o := Vector2(-12 + k * 9, 0)
					var a := 0.25 + k * 0.35
					draw_circle(c + o + Vector2(0, -8), 4.0, Color(wcol.r, wcol.g, wcol.b, a))
					draw_colored_polygon(PackedVector2Array([c + o + Vector2(-5, -3), c + o + Vector2(5, -3), c + o + Vector2(7, 14), c + o + Vector2(-7, 14)]), Color(wcol.r, wcol.g, wcol.b, a))
			"hellclaw":
				# three raking claw marks with burning tips
				for k in 3:
					var o := Vector2((k - 1) * 9, 0)
					draw_arc(c + o + Vector2(14, -2), 18, PI * 0.72, PI * 1.12, 10, dcol, 3.5, true)
					draw_circle(c + o + Vector2(-3, -12), 2.2, dhot)
			"summon":
				# a burning sigil with a horned head rising out of it
				draw_arc(c + Vector2(0, 9), 15, 0, TAU, 28, dcol, 2.0, true)
				for k in 5:
					var a0 := -PI * 0.5 + TAU * k / 5.0
					var a1 := -PI * 0.5 + TAU * (k + 2) / 5.0
					draw_line(c + Vector2(0, 9) + Vector2(cos(a0), sin(a0) * 0.45) * 15, c + Vector2(0, 9) + Vector2(cos(a1), sin(a1) * 0.45) * 15, dcol, 1.3, true)
				draw_circle(c + Vector2(0, -4), 7, Color(0.25, 0.04, 0.03) if not dim else Color(0.2, 0.17, 0.15))
				draw_polyline(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(-11, -18), c + Vector2(-7, -9)]), dhot, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(5, -8), c + Vector2(11, -18), c + Vector2(7, -9)]), dhot, 2.0, true)
				draw_circle(c + Vector2(-3, -5), 1.4, dhot)
				draw_circle(c + Vector2(3, -5), 1.4, dhot)
			"phase":
				# a rift: a violet tear with a figure stepping through
				var vio := Color(0.65, 0.45, 1.0) if not dim else Color(0.32, 0.3, 0.38)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(8, -4), c + Vector2(4, 4), c + Vector2(9, 18), c + Vector2(-2, 6), c + Vector2(-8, 16), c + Vector2(-5, -2), c + Vector2(-9, -10)]), Color(vio.r, vio.g, vio.b, 0.35))
				draw_polyline(PackedVector2Array([c + Vector2(0, -18), c + Vector2(8, -4), c + Vector2(4, 4), c + Vector2(9, 18)]), vio, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(0, -18), c + Vector2(-9, -10), c + Vector2(-5, -2), c + Vector2(-8, 16)]), vio, 2.0, true)
				draw_circle(c + Vector2(0, -6), 3.0, dcol)
				draw_line(c + Vector2(0, -3), c + Vector2(0, 8), dcol, 3.0, true)
			"pact":
				# a dripping blood drop over a burning star
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -17), c + Vector2(9, 0), c + Vector2(7, 8), c + Vector2(0, 12), c + Vector2(-7, 8), c + Vector2(-9, 0)]), Color(0.85, 0.05, 0.08) if not dim else Color(0.35, 0.25, 0.25))
				draw_circle(c + Vector2(-3, 2), 2.5, Color(1, 0.6, 0.6, 0.6))
				draw_arc(c, 18, PI * 0.15, PI * 0.85, 12, dcol, 2.0, true)
			"drain":
				# a beam from an open hand that forks into three victims
				var src := c + Vector2(-15, 12)
				var hit := c + Vector2(6, -4)
				var pts := PackedVector2Array()
				for k in 9:
					var u := k / 8.0
					pts.append(src.lerp(hit, u) + Vector2(0, sin(u * TAU * 1.5) * 3.0 * sin(u * PI)))
				draw_polyline(pts, Color(lcol.r, lcol.g, lcol.b, 0.45), 6.0, true)
				draw_polyline(pts, lpale, 2.0, true)
				for o in [Vector2(12, -16), Vector2(16, 2), Vector2(4, -18)]:
					draw_line(hit, c + o, lcol, 1.5, true)
					draw_circle(c + o, 2.5, lcol)
				draw_circle(hit, 4.0, lpale)
				draw_circle(src, 3.5, lcol)
			"blight":
				# a green skull trailing fire
				draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 14), c + Vector2(-2, -2), c + Vector2(2, 6)]), Color(lcol.r, lcol.g, lcol.b, 0.4))
				draw_circle(c + Vector2(4, -4), 10, lcol)
				draw_rect(Rect2(c + Vector2(-1, 4), Vector2(10, 6)), lcol)
				draw_circle(c + Vector2(0, -5), 2.6, Color(0.02, 0.08, 0.02))
				draw_circle(c + Vector2(8, -5), 2.6, Color(0.02, 0.08, 0.02))
				draw_line(c + Vector2(4, 0), c + Vector2(4, 2), Color(0.02, 0.08, 0.02), 1.5)
			"shackles":
				# chain links radiating out to bound shapes
				for k in 4:
					var a := PI * 0.25 + TAU * k / 4.0
					var dv := Vector2(cos(a), sin(a))
					for j in 3:
						draw_arc(c + dv * (5 + j * 5), 2.6, 0, TAU, 8, lcol, 1.5, true)
					draw_circle(c + dv * 20, 3.0, lpale)
				draw_circle(c, 4.0, lcol)
			"covenant":
				# a green flame inside a pact circle
				draw_arc(c, 17, 0, TAU, 32, lcol, 2.0, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -15), c + Vector2(7, -2), c + Vector2(6, 8), c + Vector2(0, 12), c + Vector2(-6, 8), c + Vector2(-7, -2)]), lcol)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(3, 2), c + Vector2(0, 8), c + Vector2(-3, 2)]), lpale)
			"host":
				# three spirits circling
				draw_arc(c, 13, 0, TAU, 32, Color(wcol.r, wcol.g, wcol.b, 0.4), 1.5, true)
				var t0 := Time.get_ticks_msec() / 900.0
				for k in 3:
					var ang := t0 + TAU * k / 3.0
					var p := c + Vector2(cos(ang), sin(ang)) * 13
					draw_circle(p, 4.5, wcol)
					draw_circle(p, 2.0, Color(1, 1, 1, 0.9))
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
		# the corner map takes clicks (they don't walk the hero); the big map is an overlay you walk through
		mouse_filter = Control.MOUSE_FILTER_IGNORE if big else Control.MOUSE_FILTER_STOP
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
