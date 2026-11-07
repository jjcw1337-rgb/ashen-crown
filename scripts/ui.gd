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
var _hint_t := 0.0
var dmg_flash: ColorRect
var tooltip: PanelContainer
var tip_box: VBoxContainer
var tip_owner: Control = null
var skill_picker: Control = null
## A multiplayer run character's windows (RunUI: the build, gear swaps, camp upgrades).
var run_ui: RunUI
const BIND_KEYS_UI := ["Q", "E", "R", "F", "G", "V"]

var inv_panel: PanelContainer
var inv_cells: Array = []
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
var vote_panel: Control          # the party's ready check (Net.ask_trip): Join / Not yet
var dialog_panel: PanelContainer
var dialog_name: Label
var dialog_text: Label
var dialog_btns: HBoxContainer
var gfx_info: Label
var pause_panel: PanelContainer
var gfx_btn: Button
var title_panel: Control
var sound_btn: Button
var test_panel: VBoxContainer          # the Escape menu's Admin column (dev tools)
var hud: Control                  # the screen's layers (setup): the in-game HUD
var windows: Control              # inventory, character sheet, skills, rites
var menus: Control                # the title (the multiplayer page's 3D stage)
var modals: Control               # dialogs, the party vote, the pause menu, the F8 panel, death
var top: Control                  # tooltips, drags, messages, sparkles: over everything
var death_panel: Control
var spectate_panel: Control      # Battlegrounds: the fallen hero watching the living (Game.spectate_*)
var _spec_name: Label
var _spec_hint: Label
var _spec_btns: Array = []
var boss_bar_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var boss_ref = null
var minimap: Control
var chat: ChatBox                # in-game chat (game/ui/chat/)
var loot_list: LootList          # Ctrl: the items on the ground nearby (game/ui/loot_list/)
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
	# the screen's layers, bottom to top: each part of the UI lives in one, so what shows where is decided in one place
	# (the title and its menus cover the HUD, a dialog or the pause menu is above every screen, tooltips and messages
	# above everything); `_set_hud` shows or hides the whole in-game HUD at once
	hud = _layer("hud")
	windows = _layer("windows")
	menus = _layer("menus")
	modals = _layer("modals")
	top = _layer("top")
	dmg_flash = ColorRect.new()
	dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = "shader_type canvas_item; void fragment(){ vec2 uv = UV - 0.5; uv.x *= 1.4; float v = smoothstep(0.35, 0.8, length(uv)); COLOR = vec4(0.55, 0.0, 0.0, v * COLOR.a * 1.6); }"
	fm.shader = fsh
	dmg_flash.material = fm
	hud.add_child(dmg_flash)
	_build_hud()
	chat = ChatBox.attach(self)
	loot_list = LootList.attach(self)
	_build_inventory()
	_build_character()
	_build_vote()
	_build_dialog()
	_build_pause()
	_build_skills_panel()
	_build_talent_panel()
	_build_tooltip()
	_build_title()
	_build_death()
	_build_spectate()
	run_ui = RunUI.new()
	modals.add_child(run_ui)      # (over the menus: the survivor roster opens from the multiplayer screen)
	modals.move_child(run_ui, 0)
	run_ui.setup(self)

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
	# every button is the action bar's iron socket by default (Blaine: "no plain boxes"; _iron_button is the same)
	var sock := _scaled_tex(BAR_TEX["slot"], 0.3)
	var iron := func(mod: Color) -> StyleBoxTexture:
		var sb := StyleBoxTexture.new()
		sb.texture = sock
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 9)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.modulate_color = mod
		return sb
	var bn: StyleBoxTexture = iron.call(Color.WHITE)
	var bh: StyleBoxTexture = iron.call(Color(1.25, 1.15, 1.0))
	var bp: StyleBoxTexture = iron.call(Color(0.85, 0.8, 0.75))
	var bd: StyleBoxTexture = iron.call(Color(0.5, 0.48, 0.46, 0.85))
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(0.9, 0.75, 0.45), 1, 2, 8))
	t.set_color("font_color", "Button", Color(0.96, 0.82, 0.5))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.65))
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
static var _socket_tex: Texture2D

## An item socket. iron: the action bar's riveted iron socket (the inventory), else a plain dark box.
func _slot(size: Vector2, on_click: Callable, on_hover: Callable, placeholder := "", iron := false) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.size = size
	if iron:
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		if _socket_tex == null:
			_socket_tex = _scaled_tex(BAR_TEX["slot"], 0.3)
		var fr := NinePatchRect.new()
		fr.name = "socket"
		fr.texture = _socket_tex
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			fr.set_patch_margin(side, 9)
		fr.set_anchors_preset(Control.PRESET_FULL_RECT)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(fr)
		# the rarity: a coloured line just inside the socket's lip
		var rar := Panel.new()
		rar.name = "rar"
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0, 0, 0, 0)
		rsb.set_border_width_all(2)
		rsb.set_corner_radius_all(1)
		rar.add_theme_stylebox_override("panel", rsb)
		rar.set_anchors_preset(Control.PRESET_FULL_RECT)
		rar.offset_left = 5
		rar.offset_top = 5
		rar.offset_right = -5
		rar.offset_bottom = -5
		rar.visible = false
		rar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(rar)
	else:
		var sb := _box(Color(0.03, 0.03, 0.03, 0.85), Color(0.25, 0.2, 0.13), 1, 1, 0)
		sb.shadow_size = 0
		p.add_theme_stylebox_override("panel", sb)
	var tr := TextureRect.new()
	tr.name = "icon"
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ins := 6 if iron else 2
	tr.offset_left = ins
	tr.offset_top = ins
	tr.offset_right = -ins
	tr.offset_bottom = -ins
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
		top.add_child(sp)
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
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	var rar := p.get_node_or_null("rar") as Panel
	if it == null:
		tr.texture = null
		ph.visible = true
		cnt.text = ""
		if sb:
			sb.bg_color = Color(0.03, 0.03, 0.03, 0.85)
			sb.border_color = Color(0.25, 0.2, 0.13)
		if rar:
			rar.visible = false
		p.set_meta("item", null)
		return
	ph.visible = false
	p.set_meta("item", it)
	var c := int(it.get("count", 1))
	cnt.text = str(c) if c > 1 and it["base"] != "gold" else ""
	var r := int(it.get("rarity", 0))
	if sb:
		sb.bg_color = [Color(0.04, 0.04, 0.04, 0.9), Color(0.03, 0.04, 0.1, 0.9), Color(0.09, 0.08, 0.02, 0.9), Color(0.09, 0.06, 0.03, 0.9)][r]
		sb.border_color = Color(0.25, 0.2, 0.13) if r == 0 else (Data.RARITY_COLOR[r] as Color).darkened(0.35)
	if rar:
		rar.visible = r > 0
		(rar.get_theme_stylebox("panel") as StyleBoxFlat).border_color = (Data.RARITY_COLOR[r] as Color).darkened(0.2)
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

const TIP_W := 380.0

func show_tooltip(lines: Array) -> void:
	for c in tip_box.get_children():
		tip_box.remove_child(c)      # out now, so the box sizes to the new lines only
		c.queue_free()
	var first := true
	for ln in lines:
		var l := _label(ln[0], 18 if first else 15, ln[1], first)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# long lines (a skill's description) wrap at TIP_W rather than stretching the box across the screen
		if str(ln[0]).length() > 44:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = TIP_W
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
	top.add_child(tooltip)

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
	hud.add_child(bottom)
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
	hud.add_child(frame)
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
	hud.add_child(talent_badge)
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
	hud.add_child(zone_lbl)
	fps_lbl = _label("", 14, Color(0.7, 0.9, 0.6))
	fps_lbl.anchor_left = 1.0
	fps_lbl.anchor_right = 1.0
	fps_lbl.offset_left = -120
	fps_lbl.offset_top = 14
	top.add_child(fps_lbl)
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
	hud.add_child(target_box)
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
	hud.add_child(boss_bar_box)
	msg_lbl = _label("", 20, Color(1, 1, 1), true)
	msg_lbl.anchor_left = 0.5
	msg_lbl.anchor_right = 0.5
	msg_lbl.offset_left = -400
	msg_lbl.offset_right = 400
	msg_lbl.anchor_top = 0.62
	msg_lbl.anchor_bottom = 0.62
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(msg_lbl)
	big_lbl = _label("", 42, GOLD, true)
	big_lbl.anchor_left = 0.5
	big_lbl.anchor_right = 0.5
	big_lbl.offset_left = -600
	big_lbl.offset_right = 600
	big_lbl.anchor_top = 0.2
	big_lbl.anchor_bottom = 0.2
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_lbl.add_theme_constant_override("outline_size", 8)
	top.add_child(big_lbl)
	hint_lbl = _label("", 14, DIM)
	hint_lbl.anchor_left = 0.0
	hint_lbl.anchor_right = 1.0
	hint_lbl.anchor_top = 1.0
	hint_lbl.anchor_bottom = 1.0
	hint_lbl.offset_left = 24
	hint_lbl.offset_right = -24
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.offset_top = -bh - 52
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_lbl.text = HINT_STORY
	hud.add_child(hint_lbl)
	minimap = Minimap.new()
	minimap.ui = self
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -230
	minimap.offset_right = -18
	minimap.offset_top = 40
	minimap.offset_bottom = 252
	minimap.set_big(false)
	hud.add_child(minimap)

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
		s.visible = not (hero != null and hero.run != null and slot in ["G", "V"])
	tooltip.visible = false
	if hint_lbl != null:
		hint_lbl.text = HINT_RUN if hero != null and hero.run != null else HINT_STORY
	if skills_panel and skills_panel.visible:
		_fill_skills_panel()
	# the standard globes, unless this class is a special character with its own (Data.CLASSES "hud")
	if hero and life_globe and life_globe.mat:
		var hud: Dictionary = Data.CLASSES.get(hero.cls, {}).get("hud", {})
		life_globe.set_style(hud)
		mana_globe.set_style(hud)

const SLOT_NAMES := {"lmb": "Left mouse", "rmb": "Right mouse"}
const HINT_STORY := "WASD: move  ·  Left mouse: attack  ·  Right mouse, Q E R F G V: skills (K to set them)  ·  Space: dodge roll (hold to sprint)  ·  N: rites  ·  1-4: potions  ·  I/C: inventory/stats  ·  Tab: map"
## A multiplayer run character's controls (RunBuild: five slots, the build window, camp chests)
const HINT_RUN := "WASD: move  ·  Left mouse: attack  ·  Right mouse, Q E R F: skills  ·  I or K: your build  ·  Space: dodge roll (hold to sprint)  ·  1-4: consumables  ·  Clear a camp, open its chest: an upgrade  ·  Tab: map"

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
				lines.append(["Mana: %d   Cooldown: %ss" % [int(round(hero.skill_cost(id))), str(snappedf(hero.skill_cd(id), 0.1))] + (("   Not learned" if hero.run != null else "   Unlocks at level %d" % int(sk["lvl"])) if hero.skill_locked(sk) else ""), Color(0.55, 0.65, 1.0)])
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
	if sk.is_empty() or hero == null or (hero.skill_locked(sk) and not game.test_allskills):
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
	if hero != null and hero.run != null:
		run_ui.open_build(slot)     # (a run character's skills live in its build window)
		return
	close_skill_picker()
	tooltip.visible = false
	var where: String = SLOT_NAMES.get(slot, "Key " + slot)
	var cover := Control.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_skill_picker())
	windows.add_child(cover)
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
	var locked: bool = hero.skill_locked(sk) and not game.test_allskills
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
	tb.text = "Rites (N)"
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
		var locked: bool = hero.skill_locked(sk) and not game.test_allskills
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
	if sk.is_empty() or (hero.skill_locked(sk) and not game.test_allskills):
		return true
	hero.bind(key, _hover_skill)
	Sfx.play("click")
	return true

# ---------------------------------------------------------------- talents window (N)
## Three trees side by side, four rows each; left click learns a rank, right click gives it back.
func _build_talent_panel() -> void:
	talent_panel = _panel("Rites", true, 960, 600)
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
	talent_head.text = ("%d rite point%s to spend" % [free, "" if free == 1 else "s"]) if free > 0 else "No points to spend: you get one each level"
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
		if ev is InputEventMouseButton:
			# taken now: learning rebuilds the tree, and a click whose node leaves the tree
			# isn't stopped by it and walks the hero
			p.accept_event()
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
	windows.add_child(p)
	# every window in the game's own frame (Blaine: "no plain boxes"): the inventory's iron and gold
	_ornate(p, 0.2, 6)
	var vb := VBoxContainer.new()
	vb.name = "vb"
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := _label(title, 21, GOLD, true)
	t.name = "title"
	t.uppercase = true
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 3
	t.add_theme_font_override("font", tfv)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	t.add_theme_constant_override("outline_size", 5)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var x := _close_button()
	x.pressed.connect(func():
		p.visible = false
		tooltip.visible = false
		Sfx.play("click"))
	hb.add_child(x)
	vb.add_child(_divider(22))
	return p

var _pie_overlay: ColorRect

## A cream pie in the face (DougSkills; Hero.take_hit "pied"): cream splattered over the screen's edges, fading.
func pie_face(secs: float) -> void:
	if _pie_overlay == null:
		_pie_overlay = ColorRect.new()
		_pie_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pie_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform float amt = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 c = (UV - 0.5) * vec2(1.6, 1.0);
	float edge = smoothstep(0.32, 0.75, length(c) + (noise(UV * 7.0) - 0.5) * 0.35);
	float blob = smoothstep(0.55, 0.7, noise(UV * 4.0 + 3.0)) * smoothstep(0.15, 0.45, length(c));
	float a = clamp(edge + blob * 0.8, 0.0, 1.0) * amt;
	COLOR = vec4(vec3(1.0, 0.97, 0.88) * (0.92 + noise(UV * 30.0) * 0.08), a * 0.95);
}"""
		m.shader = sh
		_pie_overlay.material = m
		top.add_child(_pie_overlay)
	_pie_overlay.visible = true
	var m2 := _pie_overlay.material as ShaderMaterial
	m2.set_shader_parameter("amt", 1.0)
	var tw := _pie_overlay.create_tween()
	tw.tween_interval(secs * 0.6)
	tw.tween_method(func(v: float): m2.set_shader_parameter("amt", v), 1.0, 0.0, secs * 0.4)
	tw.tween_callback(func(): _pie_overlay.visible = false)

## A window's close: a gold ✕ that brightens and grows a touch under the mouse.
func _close_button() -> Button:
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(34, 32)
	x.add_theme_font_size_override("font_size", 20)
	x.add_theme_color_override("font_color", Color(0.8, 0.64, 0.38))
	x.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.55))
	x.add_theme_color_override("font_pressed_color", Color(0.7, 0.5, 0.3))
	x.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	x.add_theme_constant_override("outline_size", 4)
	x.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return x

## The sheet's gold divider, centred, `h` px tall.
func _divider(h := 30) -> TextureRect:
	var rule := TextureRect.new()
	rule.texture = load("res://assets/textures/ui/sheet_divider.png")
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule.custom_minimum_size = Vector2(0, h)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

## The inventory (Meshy art in the action bar's riveted iron and bronze, `assets/textures/ui/inv_*.png`): an
## ornate iron frame, the equipment round a knight's silhouette in a recessed alcove, the bag's 40 sockets
## below and the gold on a bronze plate. Every piece sits inside the frame's trim, clear of the corner pieces'
## spikes (INV_SAFE; tools/inv_geometry_test.gd checks each socket against the frame's ornament).
const INV_TEX := {"frame": "res://assets/textures/ui/inv_frame_full.png", "iron": "res://assets/textures/ui/inv_iron.png",
	"alcove": "res://assets/textures/ui/inv_alcove.png", "plate": "res://assets/textures/ui/inv_plate.png",
	"coinplate": "res://assets/textures/ui/inv_coinplate.png", "coins": "res://assets/textures/ui/inv_coins.png"}
const INV_SIZE := Vector2(650, 641)
## the frame texture's scale on screen; its corner pieces fill INV_PATCH texture pixels of each corner
const INV_SCALE := 0.4
const INV_PATCH := 340
## the alcove, the bag and the gold plate (in the window)
const INV_ALCOVE := Rect2(98, 88, 454, 236)
const INV_GRID := Vector2(96, 334)
const INV_PLATE := Rect2(225, 526, 200, 44)
## the equipment in the alcove: rect, label
const INV_EQUIP := {
	"helm": [Rect2(195, 18, 64, 54), "Helm"], "amulet": [Rect2(275, 28, 40, 40), "Amulet"],
	"weapon": [Rect2(26, 46, 72, 116), "Weapon"], "shield": [Rect2(356, 46, 72, 116), "Shield"],
	"armor": [Rect2(185, 88, 84, 86), "Armour"],
	"gloves": [Rect2(26, 182, 72, 46), "Gloves"], "boots": [Rect2(356, 182, 72, 46), "Boots"],
	"ring1": [Rect2(132, 192, 38, 38), "Ring"], "belt": [Rect2(185, 192, 84, 38), "Belt"], "ring2": [Rect2(284, 192, 38, 38), "Ring"]}
static var _inv_frame_tex: Texture2D
static var _ornate_cache := {}
static var _frame_cache := {}

## The inventory's iron-and-gold frame at scale k (for a NinePatchRect; its patch margin is INV_PATCH * k).
func _ornate_frame(k: float) -> Texture2D:
	if not _frame_cache.has(k):
		_frame_cache[k] = _scaled_tex(INV_TEX["frame"], k)
	return _frame_cache[k]

## Any panel in the game's own frame (Blaine: "no plain boxes"): the inventory's iron inside, its iron-and-gold frame
## round it (the corners at their own size, the edges tiled), at scale k of the painted art; `pad` past the trim.
## Used for the title's sidebar, the dialogs, the Battlegrounds page.
func _ornate(panel: PanelContainer, k := 0.3, pad := 16) -> void:
	if not _ornate_cache.has(k):
		var fr := StyleBoxTexture.new()
		fr.texture = _scaled_tex(INV_TEX["frame"], k)
		var pm := float(INV_PATCH) * k
		fr.texture_margin_left = pm
		fr.texture_margin_right = pm
		fr.texture_margin_top = pm
		fr.texture_margin_bottom = pm
		fr.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		fr.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		fr.draw_center = false
		_ornate_cache[k] = [fr, _scaled_tex(INV_TEX["iron"], k), 178.0 * k]
	var c: Array = _ornate_cache[k]
	var trim: float = c[2]
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = trim + pad
	sb.content_margin_right = trim + pad
	sb.content_margin_top = trim + pad * 0.6
	sb.content_margin_bottom = trim + pad * 0.6
	panel.add_theme_stylebox_override("panel", sb)
	panel.draw.connect(func():
		var r := Rect2(Vector2.ZERO, panel.size)
		panel.draw_texture_rect(c[1], r.grow(-trim * 0.7), true)
		panel.draw_style_box(c[0], r))

## A texture at a fraction of its size (the frame and its pieces are drawn at their pixel size in a NinePatchRect).
static func _scaled_tex(path: String, k: float) -> Texture2D:
	var src := load(path) as Texture2D
	var img: Image = src.get_image() if src != null else null
	if img == null:
		return src     # (a stripped server build: a placeholder with no pixels; nobody sees it)
	img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _build_inventory() -> void:
	inv_panel = PanelContainer.new()
	inv_panel.anchor_left = 1.0
	inv_panel.anchor_right = 1.0
	inv_panel.offset_left = -INV_SIZE.x - 18
	inv_panel.offset_right = -18
	inv_panel.offset_top = 36
	inv_panel.custom_minimum_size = INV_SIZE
	inv_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	inv_panel.visible = false
	windows.add_child(inv_panel)
	var body := Control.new()
	body.name = "body"
	body.custom_minimum_size = INV_SIZE
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	inv_panel.add_child(body)
	# the iron inside, then the frame over it (its corners and trim drawn at their own size, the edges tiled)
	var trim := int(178 * INV_SCALE)
	var iron := TextureRect.new()
	iron.texture = _scaled_tex(INV_TEX["iron"], INV_SCALE)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(trim, trim)
	iron.size = INV_SIZE - Vector2(trim * 2, trim * 2 - 2)
	iron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(iron)
	if _inv_frame_tex == null:
		_inv_frame_tex = _scaled_tex(INV_TEX["frame"], INV_SCALE)
	var frame := NinePatchRect.new()
	frame.name = "frame"
	frame.texture = _inv_frame_tex
	var pm := int(INV_PATCH * INV_SCALE)
	frame.patch_margin_left = pm
	frame.patch_margin_right = pm
	frame.patch_margin_top = pm
	frame.patch_margin_bottom = pm
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.draw_center = false
	frame.size = INV_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(frame)
	# the title plate on the top border, and the close button beside it
	var plate := TextureRect.new()
	plate.texture = load(INV_TEX["plate"])
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(240, 36)
	plate.position = Vector2((INV_SIZE.x - 240) * 0.5, 14)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(plate)
	var title := _label("INVENTORY", 15, GOLD, true)
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 3
	title.add_theme_font_override("font", tfv)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = plate.position
	title.size = plate.size
	body.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_color_override("font_color", Color(0.85, 0.7, 0.42))
	x.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	x.add_theme_font_size_override("font_size", 18)
	x.position = Vector2(INV_SIZE.x - pm - 34, 18)
	x.size = Vector2(30, 30)
	x.pressed.connect(func():
		inv_panel.visible = false
		tooltip.visible = false
		Sfx.play("click"))
	body.add_child(x)
	# the alcove: the knight's silhouette in recessed iron, a bronze line round it
	var al := TextureRect.new()
	al.texture = load(INV_TEX["alcove"])
	al.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	al.position = INV_ALCOVE.position
	al.size = INV_ALCOVE.size
	al.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(al)
	body.add_child(_inset_line(INV_ALCOVE))
	var lfv := FontVariation.new()
	lfv.base_font = font_body
	lfv.spacing_glyph = 2
	for k in INV_EQUIP.keys():
		var slot_name: String = k
		var r: Rect2 = INV_EQUIP[k][0]
		var s := _slot(r.size, func(ev):
			if ev.button_index == MOUSE_BUTTON_LEFT:
				hero.unequip(slot_name)
				tooltip.visible = false, func(p, on): _hover(p, on, "equipped"), "", true)
		s.position = INV_ALCOVE.position + r.position
		body.add_child(s)
		equip_cells[k] = s
		var lb := Caption.new()
		lb.text = str(INV_EQUIP[k][1]).to_upper()
		lb.font = lfv
		lb.position = INV_ALCOVE.position + r.position + Vector2(-8, -12)
		lb.size = Vector2(r.size.x + 16, 11)
		body.add_child(lb)
	# the bag: 10 x 4 sockets
	for i in 40:
		var idx := i
		var c := _slot(Vector2(CELL, CELL), func(ev): _inv_click(idx, ev), func(p, on): _hover(p, on, "inv"), "", true)
		c.gui_input.connect(func(ev: InputEvent): _inv_drag_input(idx, ev))
		c.position = INV_GRID + Vector2((i % 10) * (CELL + 2), (i / 10) * (CELL + 2))
		body.add_child(c)
		inv_cells.append(c)
	# the gold, on its bronze plate
	var cp := TextureRect.new()
	cp.texture = load(INV_TEX["coinplate"])
	cp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cp.position = INV_PLATE.position
	cp.size = INV_PLATE.size
	cp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(cp)
	var coins := TextureRect.new()
	coins.texture = load(INV_TEX["coins"])
	coins.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coins.position = INV_PLATE.position + Vector2(22, 6)
	coins.size = Vector2(32, 32)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(coins)
	gold_lbl = _label("", 17, Color(1.0, 0.85, 0.45), true)
	gold_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gold_lbl.add_theme_constant_override("outline_size", 4)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_lbl.position = INV_PLATE.position + Vector2(58, 0)
	gold_lbl.size = Vector2(INV_PLATE.size.x - 80, INV_PLATE.size.y)
	gold_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gold_lbl)

## A small letter-spaced caption drawn on its bottom edge, exactly inside its rect (a Label's line height
## would run into the socket below it).
class Caption extends Control:
	var text := ""
	var font: Font
	var size_px := 10
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if font == null:
			return
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var at := Vector2((size.x - w) * 0.5, size.y - 1.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color(0, 0, 0, 0.85))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0.72, 0.6, 0.4))

## A recessed line round r: dark outside, bronze, dark inside.
func _inset_line(r: Rect2) -> Control:
	var c := Control.new()
	c.position = r.position - Vector2(3, 3)
	c.size = r.size + Vector2(6, 6)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in [[0, Color(0, 0, 0, 0.75), 1], [1, Color(0.55, 0.43, 0.24), 2], [3, Color(0, 0, 0, 0.6), 1]]:
		var pn := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = k[1]
		sb.set_border_width_all(k[2])
		pn.add_theme_stylebox_override("panel", sb)
		pn.position = Vector2(k[0], k[0])
		pn.size = c.size - Vector2(k[0] * 2, k[0] * 2)
		pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(pn)
	return c

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
		Sfx.play("inv_click", -2.0, randf_range(0.96, 1.04))
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		if not Items.is_equip(it) and not Items.is_material(it):
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
		top.add_child(drag_ghost)
		drag_hint = _label("", 15, Color(1.0, 0.86, 0.5), true)
		drag_hint.z_index = 100
		drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(drag_hint)
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
	for pnl in [inv_panel, char_panel, dialog_panel, action_bar, skills_panel, talent_panel]:
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
	# off until the sheet opens (UI._process); no lantern and fire shadow maps of its own for a 61 px portrait
	sheet_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sheet_view.positional_shadow_atlas_size = 0
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

var _sheet_warm := 0

var _windows_warm := false

## Under the loading screen (Game.load_zone; its overlay is drawn over the UI): the game's windows opened for a frame
## once a session, and the character sheet's portrait drawn for a few frames every zone. The first open of a window
## built its contents, rasterized its fonts' sizes and drew its art for the first time (talents 59 ms, inventory 35,
## the sheet 86 without its portrait); the portrait's view has its own settings (no MSAA, no positional shadows), so
## it compiled pipelines for the hero and everything behind him (with the window, 574 ms on the Mac mini: Blaine's
## app audit, 2026-11-05).
func warm_windows() -> void:
	if hero == null or DisplayServer.get_name() == "headless":
		return
	if sheet_view != null:
		_sheet_camera(0.0)
		_sheet_warm = 3
	if not _windows_warm:
		_windows_warm = true
		var was_muted: bool = Sfx.muted
		Sfx.set_muted(true)
		for p in [inv_panel, char_panel, skills_panel, talent_panel]:
			if p == null or p.visible:
				continue
			toggle(p)
			await RenderingServer.frame_post_draw
			p.visible = false
		tooltip.visible = false
		Sfx.set_muted(was_muted)
	for i in 4:
		await RenderingServer.frame_post_draw

## The portrait's camera: a slow look at the hero's face and shoulders, from the front.
func _sheet_camera(delta: float) -> void:
	if sheet_cam == null or hero == null or not is_instance_valid(hero.rig):
		return
	_sheet_t += delta
	var head: Node3D = hero.J.get("at_head", hero.J.get("head")) if hero.J is Dictionary else null
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

# ---------------------------------------------------------------- the party's ready check
## A small window in the inventory's iron and bronze, top centre: "<name> wants to travel to <place>" with
## Join / Not yet; for the one who asked, "Waiting for <names>" and Cancel.
var vote_title: Label
var vote_dest: Label
var vote_wait: Label
var vote_yes: Button
var vote_no: Button
var vote_cancel: Button
var _vote_mine := false

func _iron_button(text: String, w := 130, h := 38, fs := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_override("font", font_title)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color(0.96, 0.82, 0.5))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.65))
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxTexture.new()
		if _socket_tex == null:
			_socket_tex = _scaled_tex(BAR_TEX["slot"], 0.3)
		sb.texture = _socket_tex
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 9)
		sb.modulate_color = Color(1.25, 1.15, 1.0) if st == "hover" else (Color(0.85, 0.8, 0.75) if st == "pressed" else Color.WHITE)
		b.add_theme_stylebox_override(st, sb)
	return b

func _build_vote() -> void:
	vote_panel = Control.new()
	vote_panel.anchor_left = 0.5
	vote_panel.anchor_right = 0.5
	vote_panel.offset_left = -170
	vote_panel.offset_right = 170
	vote_panel.offset_top = 30
	vote_panel.offset_bottom = 30 + 124
	vote_panel.visible = false
	modals.add_child(vote_panel)
	var iron := TextureRect.new()
	iron.texture = _scaled_tex(INV_TEX["iron"], 0.2)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(20, 20)
	iron.size = Vector2(300, 84)
	vote_panel.add_child(iron)
	var fr := NinePatchRect.new()
	fr.texture = _scaled_tex(INV_TEX["frame"], 0.13)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		fr.set_patch_margin(side, 44)
	fr.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.draw_center = false
	fr.size = Vector2(340, 124)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vote_panel.add_child(fr)
	var vb := VBoxContainer.new()
	vb.position = Vector2(30, 24)
	vb.size = Vector2(280, 80)
	vb.add_theme_constant_override("separation", 1)
	vote_panel.add_child(vb)
	vote_title = _label("", 12, Color(0.8, 0.72, 0.58))
	vote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(vote_title)
	vote_dest = _label("", 17, GOLD, true)
	vote_dest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(vote_dest)
	vote_wait = _label("", 11, Color(0.7, 0.66, 0.58))
	vote_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(vote_wait)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	vote_yes = _iron_button("Join", 92, 28, 13)
	vote_yes.pressed.connect(func():
		Sfx.play("click")
		game.net.answer_vote(true)
		vote_yes.visible = false
		vote_no.visible = false
		vote_wait.text = "Ready. Waiting for the others…")
	hb.add_child(vote_yes)
	vote_no = _iron_button("Not yet", 92, 28, 13)
	vote_no.pressed.connect(func():
		Sfx.play("click")
		game.net.answer_vote(false)
		vote_no.visible = false
		vote_wait.text = "The party waits for you. Join when you're ready.")
	hb.add_child(vote_no)
	vote_cancel = _iron_button("Cancel", 92, 28, 13)
	vote_cancel.pressed.connect(func():
		Sfx.play("click")
		game.net.cancel_vote())
	hb.add_child(vote_cancel)

func party_vote(nm: String, dest: String, mine: bool) -> void:
	_vote_mine = mine
	vote_title.text = "You want to travel to" if mine else "%s wants to travel to" % nm
	vote_dest.text = dest
	vote_wait.text = ""
	vote_yes.visible = not mine
	vote_no.visible = not mine
	vote_cancel.visible = mine
	vote_panel.visible = true
	Sfx.play("portal", -8.0, 1.1)

func party_vote_wait(names: Array) -> void:
	if not vote_panel.visible:
		return
	if _vote_mine:
		vote_wait.text = "Waiting for %s…" % ", ".join(names)
	elif vote_yes.visible == false and vote_no.visible == false:
		vote_wait.text = "Ready. Waiting for %s…" % ", ".join(names)

func party_vote_end() -> void:
	if vote_panel:
		vote_panel.visible = false

## The party leader removing someone: asked first.
func confirm_kick(pid: int, nm: String) -> void:
	if nm == "":
		return
	open_dialog("Party", "Remove %s from the party?" % nm, [
		["Remove", func(): game.net.kick(pid)],
		["Keep", func(): pass]])

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
	# behind it, the world dimmed to a vignette while it asks
	var dim := ColorRect.new()
	dim.name = "dialog_dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var dm := ShaderMaterial.new()
	var dsh := Shader.new()
	dsh.code = "shader_type canvas_item; void fragment(){ float v = smoothstep(0.2, 0.85, length(UV - vec2(0.5))); COLOR = vec4(0.0, 0.0, 0.0, 0.5 + v * 0.35); }"
	dm.shader = dsh
	dim.material = dm
	dim.visible = false
	modals.add_child(dim)
	dialog_panel.visibility_changed.connect(func(): dim.visible = dialog_panel.visible)
	modals.add_child(dialog_panel)
	dialog_panel.offset_left = -360
	dialog_panel.offset_right = 360
	dialog_panel.offset_top = -190
	dialog_panel.offset_bottom = 150
	_ornate(dialog_panel, 0.3, 20)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_panel.add_child(vb)
	dialog_name = _label("", 30, GOLD, true)
	dialog_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_name.add_theme_constant_override("outline_size", 8)
	vb.add_child(dialog_name)
	var rule := TextureRect.new()
	rule.texture = load("res://assets/textures/ui/sheet_divider.png")
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule.custom_minimum_size = Vector2(0, 40)
	vb.add_child(rule)
	dialog_text = _label("", 18, Color(0.88, 0.84, 0.76))
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_text.custom_minimum_size = Vector2(540, 0)
	vb.add_child(dialog_text)
	dialog_btns = HBoxContainer.new()
	dialog_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_btns.add_theme_constant_override("separation", 18)
	vb.add_child(dialog_btns)

func open_dialog(nm: String, text: String, buttons: Array) -> void:
	dialog_name.text = nm
	dialog_text.text = text
	for c in dialog_btns.get_children():
		c.queue_free()
	for b in buttons:
		var btn := _iron_button(str(b[0]), 200, 50, 19)
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
	pause_panel.offset_left = -230
	pause_panel.offset_right = 230
	pause_panel.offset_top = -300
	pause_panel.offset_bottom = 300
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	# the world dimmed to a vignette behind it, like the dialogs
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var dm := ShaderMaterial.new()
	var dsh := Shader.new()
	dsh.code = "shader_type canvas_item; void fragment(){ float v = smoothstep(0.15, 0.85, length(UV - vec2(0.5))); COLOR = vec4(0.0, 0.0, 0.0, 0.45 + v * 0.4); }"
	dm.shader = dsh
	dim.material = dm
	dim.visible = false
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	modals.add_child(dim)
	pause_panel.visibility_changed.connect(func(): dim.visible = pause_panel.visible)
	modals.add_child(pause_panel)
	_ornate(pause_panel, 0.22, 10)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	pause_panel.add_child(cols)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.custom_minimum_size = Vector2(380, 0)
	cols.add_child(vb)
	var t := _label("PAUSED", 34, GOLD, true)
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 6
	t.add_theme_font_override("font", tfv)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_divider(24))
	var resume := _iron_button("Resume", 320, 50, 22)
	resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume.pressed.connect(func(): game.toggle_pause())
	vb.add_child(resume)
	var head := func(txt: String):
		var l := _label(txt, 13, Color(0.62, 0.55, 0.43), true)
		var f := FontVariation.new()
		f.base_font = font_title
		f.spacing_glyph = 3
		l.add_theme_font_override("font", f)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	head.call("SETTINGS")
	gfx_btn = _iron_button("", 320, 38, 16)
	gfx_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	sound_btn = _iron_button("", 320, 38, 16)
	sound_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sound_btn.pressed.connect(func():
		game.set_sound(not game.sound_on)
		update_sound_btn())
	vb.add_child(sound_btn)
	update_sound_btn()
	var ctl := _iron_button("", 320, 38, 16)
	ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ctl_text := func(): ctl.text = "Controls: " + ("click to move (classic)" if game.click_move else "WASD + click to attack")
	ctl_text.call()
	ctl.pressed.connect(func():
		game.set_click_move(not game.click_move)
		ctl_text.call())
	vb.add_child(ctl)
	var fps := _iron_button("FPS counter (F3)", 320, 38, 16)
	fps.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fps.pressed.connect(func(): show_fps = not show_fps)
	vb.add_child(fps)
	vb.add_child(_divider(18))
	var to_title := _iron_button("Save and Exit to Title", 320, 42, 17)
	to_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	to_title.pressed.connect(func(): game.exit_to_title())
	vb.add_child(to_title)
	var save := _iron_button("Save and Quit Game", 320, 42, 17)
	save.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	save.add_theme_color_override("font_color", Color(1.0, 0.62, 0.48))
	save.pressed.connect(func():
		game.save_game()
		get_tree().quit())
	save.visible = not OS.has_feature("web")
	vb.add_child(save)
	# the admins' tools beside it (Game.dev_tools: the editor, a signed admin key or a staging build); the menu
	# widens for them
	test_panel = _build_admin(cols)
	pause_panel.visibility_changed.connect(func():
		if not pause_panel.visible:
			return
		test_panel.visible = game.dev_tools
		var hw := 450 if game.dev_tools else 230
		pause_panel.offset_left = -hw
		pause_panel.offset_right = hw)

## The Escape menu's Admin column (only where Game.dev_tools is on): Go to level 20 with 10,000 gold, Max out, the
## testing switches and the level. Nothing else in the game changes; the switches aren't saved.
func _build_admin(parent: Control) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.custom_minimum_size = Vector2(380, 0)
	vb.visible = false
	parent.add_child(vb)
	var t := _label("ADMIN", 34, Color(0.55, 0.85, 1.0), true)
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 6
	t.add_theme_font_override("font", tfv)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var who := _label("", 13, Color(0.55, 0.85, 1.0))
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(who)
	vb.add_child(_divider(10))
	var l20 := _iron_button("Go to level 20  (+10,000 gold)", 340, 46, 18)
	l20.name = "level20"
	l20.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l20.pressed.connect(func(): game.go_level_20())
	vb.add_child(l20)
	var sbx := _iron_button("Battlegrounds sandbox", 340, 40, 17)
	sbx.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sbx.pressed.connect(func():
		if game.sandbox != null:
			game.toggle_pause()
			game.close_sandbox()
		else:
			game.open_sandbox())
	vb.add_child(sbx)
	# in a raid: the round's controls (the server checks the admin role, Battlegrounds.admin_cmd)
	var raid := VBoxContainer.new()
	raid.add_theme_constant_override("separation", 4)
	var rl := _label("Raid (everyone inside sees it)", 13, Color(0.55, 0.85, 1.0))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raid.add_child(rl)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 4)
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in [["restart", "Restart round"], ["gates", "Start the raid"], ["portals", "Open portals"]]:
		var cmd: String = c[0]
		var rb := _iron_button(c[1], 112, 36, 14)
		rb.pressed.connect(func():
			game.net.send_bg_admin(cmd)
			if cmd == "restart":
				game.toggle_pause())
		rrow.add_child(rb)
	raid.add_child(rrow)
	vb.add_child(raid)
	var mx := _iron_button("Max out (level 99, gold, gear)", 340, 38, 16)
	mx.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mx.pressed.connect(func(): game.max_out())
	vb.add_child(mx)
	# the switches: one iron button each, lit while on
	var syncs: Array[Callable] = []
	for sw in [["test_immortal", "Immortal"], ["test_onehit", "One-hit kill"], ["test_stamina", "Infinite stamina"],
			["test_allskills", "Unlock all skills"], ["test_fast", "Super speed (%dx)" % int(game.TEST_FAST)]]:
		var key: String = sw[0]
		var nm: String = sw[1]
		var b := _iron_button("", 340, 36, 15)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sync := func():
			var on: bool = game.get(key)
			b.text = nm + ":  " + ("ON" if on else "off")
			var col := Color(0.55, 1.0, 0.6) if on else Color(0.96, 0.82, 0.5)
			b.add_theme_color_override("font_color", col)
			b.add_theme_color_override("font_hover_color", col.lightened(0.2))
		b.pressed.connect(func():
			game.set(key, not bool(game.get(key)))
			sync.call()
			message(nm + (" ON" if game.get(key) else " off"), Color(0.6, 1.0, 0.6) if game.get(key) else Color(0.8, 0.8, 0.8)))
		syncs.append(sync)
		vb.add_child(b)
	# the level: pick a number and press Set
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(_label("Level", 16, Color(0.86, 0.83, 0.77)))
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 99
	spin.step = 1
	spin.custom_minimum_size = Vector2(90, 0)
	lv.add_child(spin)
	var setb := _iron_button("Set", 80, 36, 15)
	setb.pressed.connect(func():
		spin.apply()
		hero.set_level(int(spin.value))
		if game.char_id != "":
			game.save_game()
		message("Level set to %d" % hero.level, Color(1.0, 0.85, 0.4)))
	lv.add_child(setb)
	vb.add_child(lv)
	var note := _label("Level and gold are saved; the switches are not.", 13, Color(0.7, 0.66, 0.58))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)
	vb.visibility_changed.connect(func():
		if not vb.visible:
			return
		who.text = game.admin_name if game.admin_name != "" else ("admin account" if game.account_admin else "editor")
		if game.account_id != "":
			who.text += "  ·  account " + game.account_id
		sbx.text = "Leave the sandbox" if game.sandbox != null else "Battlegrounds sandbox (bots, PvP)"
		raid.visible = game.bg_mode and game.net.active
		for f in syncs:
			f.call()
		if hero:
			spin.value = hero.level)
	return vb

func update_sound_btn() -> void:
	if sound_btn:
		sound_btn.text = "Sound: " + ("On" if game.sound_on else "Off") + "  (F2)"

func _update_gfx_btn() -> void:
	gfx_btn.text = "Graphics: " + ["Low", "Medium", "High", "Ultra"][game.quality]
	if gfx_info:
		gfx_info.text = game.renderer_info()

## One of the screen's layers (see `setup`): a full-screen holder that lets the mouse through.
func _layer(nm: String) -> Control:
	var l := Control.new()
	l.name = nm
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _fullscreen_panel(col: Color) -> Control:
	var c := ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.color = col
	c.visible = false
	modals.add_child(c)
	return c

var title_stage: TitleStage

## The title: the 3D stage (TitleStage, its own world) behind the multiplayer page, where the lobby's class preview
## stands, and the build in the corner. Enter World's cards, buttons, character list and class picker are archived
## (archive/camp/).
func _build_title() -> void:
	title_panel = Control.new()
	title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menus.add_child(title_panel)
	title_stage = TitleStage.new()
	title_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_panel.add_child(title_stage)
	title_stage.setup(game)
	if BuildEnv.env() != "local" and BuildEnv.env() != "production":
		# which backend this build uses, so a staging build is never mistaken for the live game
		var envl := _label(BuildEnv.env().to_upper() + " BUILD", 14, Color(1.0, 0.55, 0.3))
		envl.name = "env_badge"
		envl.position = Vector2(14, 10)
		title_panel.add_child(envl)
	# the build, tiny in the corner, so a screenshot shows at once whether a copy is out of date
	var rev := _label("%s · %s" % [BuildEnv.env(), BuildEnv.value("rev")], 11, Color(0.5, 0.47, 0.42, 0.7))
	rev.name = "build_rev"
	rev.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rev.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rev.offset_left = 18
	rev.offset_bottom = -4
	title_panel.add_child(rev)

## The lobby browser's Battlegrounds.
func open_battlegrounds() -> void:
	if game.lobby_client != null:
		game.lobby_client.open("battlegrounds")

## The home screen is the multiplayer page (Blaine, 2026-11-06): the lobby browser over the title's 3D stage (the
## lobby's class preview stands on it). No world is drawn behind it.
func show_title() -> void:
	title_panel.visible = true
	title_stage.show_character({})
	title_stage.reset()
	if game.lobby_client != null:
		game.lobby_client.open("battlegrounds")
	get_viewport().disable_3d = true
	game.zone_music()
	_set_hud(false)

func hide_title() -> void:
	title_panel.visible = false
	get_viewport().disable_3d = false
	_set_hud(true)

func _set_hud(v: bool) -> void:
	hud.visible = v

func _build_death() -> void:
	death_panel = _fullscreen_panel(Color(0.15, 0.0, 0.0, 0.55))
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.3
	vb.offset_left = -420
	vb.offset_right = 420
	vb.add_theme_constant_override("separation", 16)
	death_panel.add_child(vb)
	# a heavy dark-red vignette over the world, the words in the title face, an iron button (Diablo's death screen)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = "shader_type canvas_item; void fragment(){ float v = smoothstep(0.1, 0.8, length((UV - vec2(0.5, 0.42)) * vec2(1.0, 1.25))); COLOR = vec4(0.05, 0.0, 0.0, 0.25 + v * 0.65); }"
	vm.shader = vs
	vig.material = vm
	death_panel.add_child(vig)
	death_panel.move_child(vig, 0)
	var t := _label("YOU HAVE DIED", 76, Color(0.78, 0.07, 0.05), true)
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 8
	t.add_theme_font_override("font", tfv)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_shadow_color", Color(0.3, 0.0, 0.0, 0.8))
	t.add_theme_constant_override("shadow_offset_y", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_divider(34))
	var s := _label("You lose 10% of your gold.", 20, Color(0.86, 0.74, 0.66))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var b := _iron_button("Return to Town", 340, 62, 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		death_panel.visible = false
		game.respawn())
	vb.add_child(b)

## The Battlegrounds' death screen: the world dimmed red, who you're watching with arrows to switch, and the way out.
## In the HUD's layer, so it is only ever seen in play.
func _build_spectate() -> void:
	spectate_panel = Control.new()
	spectate_panel.name = "spectate"
	spectate_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	spectate_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectate_panel.visible = false
	hud.add_child(spectate_panel)
	var tint := ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.14, 0.0, 0.0, 0.25)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectate_panel.add_child(tint)
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.grow_horizontal = Control.GROW_DIRECTION_BOTH
	head.offset_top = 92
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectate_panel.add_child(head)
	var t := _label("YOU HAVE FALLEN", 40, Color(0.85, 0.14, 0.08), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	var s := _label("Everything you carried lies where you fell. Your hero lives on.", 15, Color(0.85, 0.75, 0.68))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(s)
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -225          # (above the action bar, the experience bar and the keys' hint line)
	spectate_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	box.add_child(vb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	_spec_btns = []
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "◀" if d < 0 else "▶"
		b.custom_minimum_size = Vector2(44, 40)
		var dir: int = d
		b.pressed.connect(func(): game.spectate_next(dir))
		_spec_btns.append(b)
	row.add_child(_spec_btns[0])
	_spec_name = _label("", 20, GOLD, true)
	_spec_name.custom_minimum_size = Vector2(300, 0)
	_spec_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_spec_name)
	row.add_child(_spec_btns[1])
	_spec_hint = _label("Tab or ← → to watch someone else", 13, DIM)
	_spec_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_spec_hint)
	var leave := Button.new()
	leave.name = "leave"
	leave.text = "Leave the Crypt"
	leave.custom_minimum_size = Vector2(0, 42)
	leave.pressed.connect(func():
		game.spectate_stop()
		game.respawn())
	vb.add_child(leave)

## The name of the player being watched ("" for no one).
func spectate_name() -> String:
	return str(game.net.players[game.spectating]["name"]) if game.spectate_hero() != null else ""

func update_spectate() -> void:
	var n: int = game.spectate_targets().size()
	var nm := spectate_name()
	_spec_name.text = ("Watching  %s" % nm) if nm != "" else "No one left alive to watch"
	for b in _spec_btns:
		(b as Button).disabled = n < 2
	_spec_hint.visible = n >= 2

func _unhandled_key_input(ev: InputEvent) -> void:
	if game and game.playing and game.lobby_client != null and game.lobby_client.panel.visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		game.lobby_client.panel.hide()
		get_viewport().set_input_as_handled()
		return
	if game and game.paused and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		game.toggle_pause()
		get_viewport().set_input_as_handled()
		return

# ---------------------------------------------------------------- updates
func toggle(panel: Control) -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		tooltip.visible = false
	Sfx.play("click")
	refresh()

func close_all() -> bool:
	var any := close_skill_picker()
	if run_ui != null and run_ui.close():
		any = true
	if game.lobby_client != null and game.lobby_client.panel.visible:
		game.lobby_client.panel.hide()
		any = true
	for p in [inv_panel, char_panel, dialog_panel, skills_panel, talent_panel]:
		if p.visible:
			p.visible = false
			any = true
	tooltip.visible = false
	return any

## The title with nothing open over it (the lobby browser closed).
func title_idle() -> bool:
	return title_panel.visible and not (game.lobby_client != null and game.lobby_client.panel.visible)

func any_panel_open() -> bool:
	return (run_ui != null and run_ui.visible) or (game.lobby_client != null and game.lobby_client.panel.visible) or inv_panel.visible or char_panel.visible or dialog_panel.visible or skills_panel.visible or talent_panel.visible

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
	if e != null and e != boss_ref:
		Telemetry.crumb("boss", {"kind": str(e.kind)})
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
	var need := hero.xp_to_next()
	var pct := int(float(hero.xp) / maxf(need, 1.0) * 100.0)
	var t := ("%d / %d   (%d%%)" % [hero.xp, need, pct]) if level_medal else ("Level %d   ·   %d / %d   (%d%%)" % [hero.level, hero.xp, need, pct])
	if game.xp_bonus_t > 0.0:
		t += "   ·   +50%% XP %d:%02d" % [int(game.xp_bonus_t) / 60, int(game.xp_bonus_t) % 60]
	return t

func refresh() -> void:
	if hero == null:
		return
	life_lbl.text = "Life  %d / %d" % [int(hero.life), int(hero.max_life)]
	mana_lbl.text = "Mana  %d / %d" % [int(hero.mana), int(hero.max_mana)]
	var xpf := float(hero.xp) / maxf(hero.xp_to_next(), 1.0)
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
		gold_lbl.text = "%d" % hero.gold
	var free: int = hero.free_talent_points()
	talent_badge.visible = free > 0 and not talent_panel.visible
	talent_badge.text = "%d rite point%s to spend  (N)" % [free, "" if free == 1 else "s"]
	if talent_panel.visible and _talent_sig() != _talent_shown:
		_fill_talents()
	if char_panel.visible:
		var cls: Dictionary = Data.CLASSES.get(hero.cls, {})
		var pname: String = game.char_name if game.char_name != "" else str(cls.get("name", "Hero"))
		char_labels["name"].text = pname
		char_labels["level"].text = "%s  ·  Level %d" % [str(cls.get("name", hero.cls.capitalize())), hero.level]
		var need: int = hero.xp_to_next()
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
	if sheet_view:
		# the portrait renders the game's own world: only while the sheet is open. UPDATE_WHEN_PARENT_VISIBLE asks the
		# parent *viewport* (the screen, always visible), so with the sheet closed it still drew the whole scene and
		# its shadow passes every frame: 66 M of the camp's 150 M primitives (docs/visual/AUDIT.md)
		var want := SubViewport.UPDATE_ALWAYS if (char_panel and char_panel.is_visible_in_tree() or _sheet_warm > 0) and hero else SubViewport.UPDATE_DISABLED
		_sheet_warm = maxi(0, _sheet_warm - 1)
		if sheet_view.render_target_update_mode != want:
			sheet_view.render_target_update_mode = want
	if char_panel and char_panel.visible and hero:
		_sheet_camera(delta)
		if sheet_points.visible:
			sheet_points.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(_sheet_t * 4.0))
	if hero:
		if game.xp_bonus_t > 0.0 or _xp_bonus_on:
			xp_bar.detail = _xp_detail()
			_xp_bonus_on = game.xp_bonus_t > 0.0
		stamina_bar.value = hero.stamina / maxf(hero.max_stamina, 1.0)
		# the controls line: for a new hero's first minutes, then out of the way (hold F1 to see it again)
		_hint_t += get_process_delta_time()
		var want_hint: bool = (hero.level <= 3 and _hint_t < 180.0) or Input.is_key_pressed(KEY_F1)
		hint_lbl.modulate.a = move_toward(hint_lbl.modulate.a, 1.0 if want_hint else 0.0, get_process_delta_time() * 1.5)
		var rest: float = hero.calm()
		stamina_bar.detail = ("Rested ×%.1f   " % rest if rest > 1.05 else "") + "%d / %d" % [int(hero.stamina), int(hero.max_stamina)]
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
			var locked: bool = hero.skill_locked(sk) and not game.test_allskills
			var frac: float = 1.0 if locked else clampf(float(hero.cds.get(sk["id"], 0.0)) / maxf(hero.skill_cd(sk["id"]), 0.01), 0.0, 1.0)
			cdr.anchor_top = 1.0 - frac
			cdr.color = Color(0, 0, 0, 0.82) if locked else Color(0, 0, 0, 0.6)
			(c.get_node("hole/glyph") as SkillGlyph).dim = locked or hero.mana < hero.skill_cost(sk["id"])
			# a locked skill waits on the bar with the level it opens at
			var ll: Label = c.get_node_or_null("hole/lock")
			if locked and ll == null:
				ll = Label.new()
				ll.name = "lock"
				ll.set_anchors_preset(Control.PRESET_FULL_RECT)
				ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ll.add_theme_font_size_override("font_size", 13)
				ll.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
				ll.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				ll.add_theme_constant_override("outline_size", 4)
				c.get_node("hole").add_child(ll)
			if ll != null:
				ll.visible = locked
				ll.text = "Lv %d" % int(sk.get("lvl", 1))
	if msg_t > 0.0:
		msg_t -= delta
		msg_lbl.modulate.a = clampf(msg_t, 0.0, 1.0)
	# Transient world announcements and the controls hint must not cover menu actions.
	var clear_hud_text := not any_panel_open() and not pause_panel.visible
	msg_lbl.visible = not (run_ui != null and run_ui.visible)
	big_lbl.visible = clear_hud_text
	hint_lbl.visible = clear_hud_text
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
			pos.y = mp.y - sz.y - 12          # above the pointer (the skill bar sits at the bottom)
		# whatever happens, inside the screen on every side
		pos.x = clampf(pos.x, 8.0, maxf(8.0, vs.x - sz.x - 8.0))
		pos.y = clampf(pos.y, 8.0, maxf(8.0, vs.y - sz.y - 8.0))
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
	## The attack is a bow shot for a hero holding a bow (the archer), so its slot shows a bow instead of a sword.
	func _bow_hand() -> bool:
		if not is_inside_tree():
			return false
		var h := get_tree().get_first_node_in_group("hero") as Hero
		return h != null and h.has_bow()

	## A skill's painted icon (tools/skill_icons.py: Meshy, assets/textures/skills/<id>.png), when it has one; the
	## Plague Doctor's cane has its own for "attack".
	static var _painted := {}
	static func painted(sid: String) -> Texture2D:
		if not _painted.has(sid):
			var path := "res://assets/textures/skills/%s.png" % sid
			_painted[sid] = load(path) if sid != "" and ResourceLoader.exists(path) else null
		return _painted[sid]

	func _icon_id() -> String:
		if id == "attack" and is_inside_tree():
			var h := get_tree().get_first_node_in_group("hero") as Hero
			if h != null and h.is_plague():
				return "plague_attack"
		return id

	func _draw() -> void:
		var tex := SkillGlyph.painted(_icon_id())
		if tex != null:
			# the painted icon fills the socket's hole, greyed while the skill is out of reach
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(0.42, 0.42, 0.45) if dim else Color(1, 1, 1))
			return
		var c := size * 0.5
		# glyphs are drawn for a ~40 px box around the centre; scale them to whatever box this is
		var fit := minf(size.x, size.y) / 40.0
		draw_set_transform(c * (1.0 - fit), 0.0, Vector2(fit, fit))
		var steel := Color(0.85, 0.87, 0.92) if not dim else Color(0.4, 0.4, 0.42)
		var gold2 := Color(1.0, 0.8, 0.4) if not dim else Color(0.4, 0.35, 0.3)
		match id:
			"attack":
				if _bow_hand():
					# a drawn bow with a nocked arrow, pointing up and to the right
					var wood := Color(0.62, 0.42, 0.24) if not dim else Color(0.35, 0.3, 0.27)
					var ax := Vector2(1, -1).normalized()
					var bc := c + ax * 4.0
					draw_arc(bc, 15.0, ax.angle() - 1.25, ax.angle() + 1.25, 18, wood, 3.5, true)
					var t1 := bc + ax.rotated(-1.25) * 15.0
					var t2 := bc + ax.rotated(1.25) * 15.0
					var nock := c - ax * 9.0
					draw_polyline(PackedVector2Array([t1, nock, t2]), Color(0.9, 0.86, 0.75) if not dim else steel, 1.2, true)
					draw_line(nock, c + ax * 16.0, steel, 2.0, true)
					draw_colored_polygon(PackedVector2Array([c + ax * 21.0, c + ax * 15.0 + ax.orthogonal() * 3.5, c + ax * 15.0 - ax.orthogonal() * 3.5]), steel)
					draw_line(nock, nock - ax * 4.0 + ax.orthogonal() * 3.5, gold2, 2.0, true)
					draw_line(nock, nock - ax * 4.0 - ax.orthogonal() * 3.5, gold2, 2.0, true)
					return
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
			# the shared skills (SharedSkills)
			"earthshatter":
				var ec := Color(0.85, 0.6, 0.32) if not dim else Color(0.4, 0.37, 0.35)
				draw_rect(Rect2(c + Vector2(-16, 6), Vector2(32, 5)), ec.darkened(0.4))
				draw_polyline(PackedVector2Array([c + Vector2(0, 6), c + Vector2(-4, -2), c + Vector2(2, -7), c + Vector2(-2, -14)]), ec, 2.5, true)
				draw_polyline(PackedVector2Array([c + Vector2(0, 6), c + Vector2(7, 0), c + Vector2(12, -6)]), ec, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(0, 6), c + Vector2(-9, 1), c + Vector2(-14, -4)]), ec, 2.0, true)
			"frost_nova":
				var ic := Color(0.6, 0.85, 1.0) if not dim else Color(0.4, 0.42, 0.45)
				draw_arc(c, 15, 0, TAU, 32, ic, 2.5, true)
				for k in 6:
					var a := TAU * k / 6.0
					draw_line(c, c + Vector2(cos(a), sin(a)) * 11, ic.lightened(0.3), 2.0, true)
			"frost_breath":
				# a serpent's breath: a cone of frost fanning out from a point
				var fc := Color(0.7, 0.9, 1.0) if not dim else Color(0.4, 0.42, 0.45)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 0), c + Vector2(14, -12), c + Vector2(16, 0), c + Vector2(14, 12)]), Color(fc.r, fc.g, fc.b, 0.35))
				for k in 3:
					draw_line(c + Vector2(-12, 0), c + Vector2(14, (k - 1) * 9.0), fc, 1.6, true)
				draw_circle(c + Vector2(-13, 0), 3.0, fc.lightened(0.3))
			"arc", "storm_arc":
				var lc := (Color(0.75, 0.7, 1.0) if id == "arc" else Color(0.45, 0.95, 0.95)) if not dim else Color(0.4, 0.4, 0.45)
				draw_polyline(PackedVector2Array([c + Vector2(-15, -12), c + Vector2(-4, -3), c + Vector2(-8, 2), c + Vector2(4, 9), c + Vector2(0, 12), c + Vector2(15, 15)]), lc, 3.0, true)
				draw_circle(c + Vector2(15, 15), 2.5, lc.lightened(0.4))
			"war_cry":
				var rc := Color(1.0, 0.3, 0.2) if not dim else Color(0.45, 0.35, 0.33)
				draw_circle(c + Vector2(-4, 0), 8, rc.darkened(0.3))
				draw_colored_polygon(PackedVector2Array([c + Vector2(-2, -3), c + Vector2(6, -7), c + Vector2(6, 7), c + Vector2(-2, 3)]), Color(0.1, 0.05, 0.05))
				for k in 3:
					draw_arc(c + Vector2(4, 0), 7 + k * 5, -0.6, 0.6, 8, rc, 2.0, true)
			"cry":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -6), c + Vector2(-4, -6), c + Vector2(8, -14), c + Vector2(8, 14), c + Vector2(-4, 6), c + Vector2(-14, 6)]), col)
				draw_arc(c + Vector2(8, 0), 10, -0.8, 0.8, 8, col, 2.0, true)
			"rend":
				# three spectral claw rakes, curving, with a soul flying off the top
				for k in 3:
					var o := Vector2((k - 1) * 8, 0)
					draw_arc(c + o + Vector2(-10, 4), 17, -PI * 0.42, PI * 0.08, 10, wcol, 3.0, true)
				draw_circle(c + Vector2(11, -12), 3.0, Color(0.9, 0.97, 1.0))
			"siphon":
				# a tether: a twisted cord from a hand (left) to a torn soul (right)
				var pts := PackedVector2Array()
				for i in 13:
					var u := i / 12.0
					pts.append(c + Vector2(-16 + 32 * u, sin(u * PI * 3.0) * 4.0))
				draw_polyline(pts, wcol, 2.5, true)
				var pts2 := PackedVector2Array()
				for i in 13:
					var u := i / 12.0
					pts2.append(c + Vector2(-16 + 32 * u, -sin(u * PI * 3.0) * 4.0))
				draw_polyline(pts2, Color(0.62, 0.38, 1.0) if not dim else wcol, 2.0, true)
				draw_circle(c + Vector2(15, 0), 5.5, wcol)
				draw_circle(c + Vector2(15, 0), 2.5, Color(1, 1, 1, 0.9))
				draw_circle(c + Vector2(-16, 0), 3.0, wcol.lightened(0.3))
			"step":
				# a fading silhouette streaking into a sharp one, mist between
				for k in 3:
					var o := Vector2(-12 + k * 9, 0)
					var al := 0.25 + k * 0.35
					draw_circle(c + o + Vector2(0, -8), 4.0, Color(wcol.r, wcol.g, wcol.b, al))
					draw_colored_polygon(PackedVector2Array([c + o + Vector2(-5, -3), c + o + Vector2(5, -3), c + o + Vector2(7, 14), c + o + Vector2(-7, 14)]), Color(wcol.r, wcol.g, wcol.b, al))
			"grasp":
				# a clawed hand reaching up out of a dark ring
				draw_arc(c + Vector2(0, 12), 15, 0, TAU, 28, Color(0.62, 0.38, 1.0) if not dim else wcol, 2.5, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 12), c + Vector2(5, 12), c + Vector2(4, -2), c + Vector2(-4, -2)]), wcol)
				for k in 4:
					var x := -7.5 + k * 5.0
					draw_line(c + Vector2(x, -1), c + Vector2(x * 1.5, -14 + absf(k - 1.5) * 2.0), wcol, 2.5, true)
				draw_line(c + Vector2(-6, 2), c + Vector2(-13, -6), wcol, 2.5, true)
			"phantom":
				# three hooded shapes fanning forward from one
				for k in 3:
					var ang := (k - 1) * 0.55
					var d := Vector2(sin(ang), -cos(ang))
					var p := c + Vector2(0, 10) + d * 16
					var al := 0.5 + 0.5 * float(k == 1)
					draw_circle(p + Vector2(0, -4), 3.2, Color(wcol.r, wcol.g, wcol.b, al))
					draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -1), p + Vector2(4, -1), p + Vector2(5, 8), p + Vector2(-5, 8)]), Color(wcol.r, wcol.g, wcol.b, al * 0.8))
				draw_circle(c + Vector2(0, 12), 2.5, Color(0.62, 0.38, 1.0) if not dim else wcol)
			"night":
				# a crescent of night over a screaming hood, with rings of sound
				var ncol := Color(0.62, 0.38, 1.0) if not dim else wcol
				draw_circle(c + Vector2(0, -4), 13.0, Color(ncol.r, ncol.g, ncol.b, 0.45))
				draw_circle(c + Vector2(5, -8), 10.0, Color(0.05, 0.03, 0.09) if not dim else Color(0.22, 0.2, 0.24))
				draw_arc(c + Vector2(0, 6), 7, PI, TAU, 14, wcol, 3.0, true)
				draw_circle(c + Vector2(-3, 5), 1.6, wcol)
				draw_circle(c + Vector2(3, 5), 1.6, wcol)
				draw_arc(c + Vector2(0, 11), 3.0, 0, TAU, 12, wcol, 2.0, true)
				for r in [14, 19]:
					draw_arc(c + Vector2(0, 8), r, -0.5, 0.5, 8, wcol, 1.5, true)
					draw_arc(c + Vector2(0, 8), r, PI - 0.5, PI + 0.5, 8, wcol, 1.5, true)
			"fists":
				# two fists coming down on cracking ground
				for sx in [-1, 1]:
					draw_circle(c + Vector2(sx * 8, -8), 6.5, dcol)
					draw_arc(c + Vector2(sx * 8, -8), 6.5, 0, TAU, 16, dhot, 1.5, true)
				for k in 5:
					var a0 := PI * 0.15 + k * PI * 0.175
					draw_line(c + Vector2(0, 4), c + Vector2(cos(a0), sin(a0) * 0.6) * 19 + Vector2(0, 4), dhot, 2.0, true)
			"icharge":
				# a horned head lowered into a charge, lava streaking behind
				draw_colored_polygon(PackedVector2Array([c + Vector2(14, -2), c + Vector2(4, -10), c + Vector2(-6, -6), c + Vector2(-4, 6), c + Vector2(6, 8)]), dcol)
				draw_polyline(PackedVector2Array([c + Vector2(2, -10), c + Vector2(6, -19), c + Vector2(10, -12)]), dhot, 2.2, true)
				draw_polyline(PackedVector2Array([c + Vector2(-5, -6), c + Vector2(-11, -15), c + Vector2(-3, -11)]), dhot, 2.2, true)
				for k in 3:
					draw_line(c + Vector2(-6, 2 + k * 4), c + Vector2(-19, 6 + k * 4), dhot, 2.5 - k * 0.5, true)
			"cslam":
				# a fault split across the ground, plates heaved up along it, fire between
				draw_line(c + Vector2(-19, 6), c + Vector2(19, 2), dhot, 3.0, true)
				for k in 5:
					var x0 := -16.0 + k * 8.0
					var tip := c + Vector2(x0 + 2.0, -10.0 - (k % 2) * 6.0)
					draw_colored_polygon(PackedVector2Array([c + Vector2(x0 - 3.0, 5.0 - k * 0.8), tip, c + Vector2(x0 + 5.0, 4.0 - k * 0.8)]), dcol)
					draw_line(c + Vector2(x0 - 1.0, 4.0 - k * 0.8), tip, dhot, 1.2, true)
			"hurl":
				# a molten boulder in flight with an ember trail
				draw_circle(c + Vector2(6, -6), 9, dcol)
				draw_arc(c + Vector2(6, -6), 9, 0, TAU, 20, dhot, 1.5, true)
				draw_line(c + Vector2(2, -9), c + Vector2(9, -2), dhot, 2.0, true)
				draw_line(c + Vector2(4, -2), c + Vector2(10, -8), dhot, 1.5, true)
				for k in 3:
					draw_circle(c + Vector2(-6 - k * 5, 2 + k * 5), 3.0 - k * 0.7, Color(dhot.r, dhot.g, dhot.b, 0.8 - k * 0.2))
			"grip":
				# a chain thrown out, a hooked claw at its head
				for k in 6:
					var pk := c + Vector2(-16 + k * 5.0, 10 - k * 3.6)
					draw_arc(pk, 2.6, 0, TAU, 10, dhot if k < 2 else dcol.lightened(0.35), 1.6, true)
				var hc := c + Vector2(13, -12)
				draw_circle(hc, 4.0, dcol)
				for k in 3:
					var a0 := -PI * 0.6 + k * 0.6
					draw_polyline(PackedVector2Array([hc, hc + Vector2(cos(a0), sin(a0)) * 8.0, hc + Vector2(cos(a0 + 1.2), sin(a0 + 1.2)) * 9.0]), dhot, 2.0, true)
			"wrath":
				# a horned head roaring under a rain of meteors
				var pit := Color(1.0, 0.92, 0.6) if not dim else Color(0.45, 0.42, 0.35)
				draw_circle(c + Vector2(0, 8), 7, dcol)
				draw_polyline(PackedVector2Array([c + Vector2(-5, 4), c + Vector2(-11, -5), c + Vector2(-6, 2)]), dhot, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(5, 4), c + Vector2(11, -5), c + Vector2(6, 2)]), dhot, 2.0, true)
				draw_circle(c + Vector2(-2, 8), 1.4, pit)
				draw_circle(c + Vector2(2, 8), 1.4, pit)
				for k in 3:
					var o := Vector2(-12 + k * 12, -18 + (k % 2) * 4)
					draw_circle(c + o, 3.2, pit)
					draw_line(c + o + Vector2(2, -2), c + o + Vector2(7, -9), Color(dhot.r, dhot.g, dhot.b, 0.7), 2.0, true)
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
			"pie":
				# a cream pie in its tin, a cherry on the swirl
				var cream := Color(1.0, 0.96, 0.86) if not dim else Color(0.5, 0.48, 0.44)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-15, 4), c + Vector2(15, 4), c + Vector2(11, 12), c + Vector2(-11, 12)]), steel)
				draw_circle(c + Vector2(0, 2), 12.0, cream)
				draw_circle(c + Vector2(-4, -4), 6.0, cream.lightened(0.1))
				draw_circle(c + Vector2(4, -6), 5.0, cream)
				draw_circle(c + Vector2(1, -12), 3.2, Color(0.85, 0.1, 0.12) if not dim else steel)
			"peels":
				# a banana peel lying open, its four flaps out
				var ban := Color(1.0, 0.86, 0.2) if not dim else Color(0.5, 0.46, 0.3)
				for k in 4:
					var a2 := -PI * 0.5 + (k - 1.5) * 0.9
					draw_line(c + Vector2(0, 4), c + Vector2(cos(a2), sin(a2) + 0.6) * 15.0 + Vector2(0, 4), ban, 5.0, true)
				draw_circle(c + Vector2(0, 5), 4.5, ban.darkened(0.15))
				draw_line(c + Vector2(0, 5), c + Vector2(0, 13), Color(0.35, 0.25, 0.1), 3.0, true)
			"slide":
				# a belly-slide: a round body low over speed lines
				var yel := Doug.ACCENT if not dim else Color(0.5, 0.46, 0.3)
				for k in 3:
					draw_line(c + Vector2(-16, -4 + k * 6), c + Vector2(-4, -4 + k * 6), Color(0.8, 0.75, 0.6, 0.8), 2.0, true)
				draw_circle(c + Vector2(6, 4), 9.0, yel)
				draw_circle(c + Vector2(14, -2), 4.5, Color(0.95, 0.85, 0.8) if not dim else steel)
				draw_circle(c + Vector2(17, -2), 1.8, Color(0.9, 0.1, 0.1) if not dim else steel)
			"doppel":
				# two of him: one solid, one a shiny balloon outline
				var yel2 := Doug.ACCENT if not dim else Color(0.5, 0.46, 0.3)
				draw_circle(c + Vector2(-7, 4), 8.0, yel2)
				draw_circle(c + Vector2(-7, -8), 5.0, Color(0.95, 0.85, 0.8) if not dim else steel)
				draw_arc(c + Vector2(8, 4), 8.0, 0, TAU, 20, yel2.lightened(0.4), 2.0, true)
				draw_arc(c + Vector2(8, -8), 5.0, 0, TAU, 16, yel2.lightened(0.4), 2.0, true)
				draw_line(c + Vector2(8, 12), c + Vector2(10, 17), yel2.lightened(0.4), 1.5, true)
			"juggle":
				# three pins in the air, one of them alight
				for k in 3:
					var pc := c + Vector2(-11 + k * 11, -6 + absf(k - 1) * 8)
					draw_line(pc + Vector2(0, -7), pc + Vector2(0, 7), Color(0.95, 0.95, 0.95) if not dim else steel, 4.0, true)
					draw_circle(pc + Vector2(0, -6), 3.0, Color(0.9, 0.15, 0.15) if not dim else steel)
				draw_circle(c + Vector2(0, -14), 3.0, Color(1.0, 0.6, 0.15) if not dim else steel)
			"bounce":
				# a trampoline and a curve up off it
				draw_arc(c + Vector2(0, 13), 12.0, PI, TAU, 16, Color(0.85, 0.2, 0.2) if not dim else steel, 3.0, true)
				draw_line(c + Vector2(-12, 13), c + Vector2(12, 13), Color(1.0, 0.85, 0.2) if not dim else steel, 3.0, true)
				draw_arc(c + Vector2(4, 4), 13.0, PI * 1.1, PI * 1.9, 14, Color(1.0, 1.0, 1.0, 0.8), 2.0, true)
				draw_circle(c + Vector2(13, -5), 4.0, Doug.ACCENT if not dim else steel)
			"car":
				# the tiny clown car: a bubble body on big wheels, a horn
				var red := Color(0.85, 0.15, 0.15) if not dim else Color(0.45, 0.32, 0.3)
				draw_circle(c + Vector2(0, 0), 12.0, red)
				draw_rect(Rect2(c + Vector2(-15, 0), Vector2(30, 8)), red.darkened(0.1))
				draw_circle(c + Vector2(-9, 10), 5.0, Color(0.1, 0.1, 0.1))
				draw_circle(c + Vector2(9, 10), 5.0, Color(0.1, 0.1, 0.1))
				draw_circle(c + Vector2(-3, -4), 4.0, Color(0.6, 0.8, 1.0) if not dim else steel)
				draw_circle(c + Vector2(13, -8), 2.5, Color(1.0, 0.85, 0.2) if not dim else steel)
			"toxic":
				# a round flask of green poison, a wisp rising from it
				var gtox := Plague.TOXIC if not dim else Color(0.32, 0.38, 0.3)
				draw_circle(c + Vector2(0, 5), 11.0, gtox.darkened(0.25))
				draw_circle(c + Vector2(-3, 2), 4.0, gtox.lightened(0.3))
				draw_rect(Rect2(c + Vector2(-3.5, -12), Vector2(7, 8)), steel)
				draw_rect(Rect2(c + Vector2(-4.5, -15), Vector2(9, 3.5)), Color(0.55, 0.35, 0.2))
				draw_arc(c + Vector2(6, -14), 5.0, PI * 0.5, PI * 1.5, 8, Color(gtox.r, gtox.g, gtox.b, 0.6), 2.0, true)
			"swarm":
				# a cloud of flies boiling out of a little brass reliquary
				var gsw := Plague.TOXIC if not dim else Color(0.32, 0.38, 0.3)
				var gbx := Plague.BRASS if not dim else Color(0.38, 0.35, 0.3)
				draw_rect(Rect2(c + Vector2(-9, 6), Vector2(14, 10)), gbx.darkened(0.25))
				draw_rect(Rect2(c + Vector2(-10, 4), Vector2(16, 3)), gbx)
				for k in 11:
					var fa := float(k) * 2.39
					var fr := 4.0 + float(k) * 1.15
					var fp := c + Vector2(3, -4) + Vector2(cos(fa), sin(fa) * 0.75) * fr
					draw_circle(fp, 1.6, Color(0.08, 0.08, 0.06))
					draw_line(fp + Vector2(-2.2, -1.2), fp + Vector2(2.2, -1.2), Color(gsw.r, gsw.g, gsw.b, 0.55), 1.0, true)
			"bloom":
				# a swollen corpse flower over spreading roots
				var gbl := Color(0.62, 0.25, 0.32) if not dim else Color(0.36, 0.32, 0.32)
				var gsac := Plague.TOXIC if not dim else Color(0.32, 0.38, 0.3)
				for k in 5:
					var ra := PI * (0.15 + 0.175 * k)
					draw_line(c + Vector2(0, 10), c + Vector2(cos(ra) * 15.0, 10.0 + sin(ra) * 6.0), Color(0.12, 0.1, 0.1), 2.0, true)
				for k in 5:
					var pa := -PI * 0.5 + (k - 2) * 0.55
					draw_colored_polygon(PackedVector2Array([c + Vector2(0, 6), c + Vector2(cos(pa - 0.25), sin(pa - 0.25)) * 15.0 + Vector2(0, 2), c + Vector2(cos(pa + 0.25), sin(pa + 0.25)) * 15.0 + Vector2(0, 2)]), gbl.darkened(0.15 * (k % 2)))
				draw_circle(c + Vector2(-4, -2), 4.5, gsac)
				draw_circle(c + Vector2(4, -3), 4.0, gsac.lightened(0.15))
				draw_circle(c + Vector2(0, -8), 3.5, gsac.darkened(0.1))
			"fog":
				# a censer swinging in pale curls of fog
				var gfg := Color(0.82, 0.82, 0.9) if not dim else Color(0.42, 0.42, 0.45)
				for k in 4:
					draw_arc(c + Vector2(-10 + k * 7, 8 - (k % 2) * 5), 7.0, PI, TAU, 10, Color(gfg.r, gfg.g, gfg.b, 0.7), 2.5, true)
				draw_line(c + Vector2(0, -16), c + Vector2(0, -6), steel, 1.5, true)
				draw_circle(c + Vector2(0, -2), 5.0, Plague.BRASS if not dim else steel)
				draw_circle(c + Vector2(0, -2), 2.0, Color(0.15, 0.12, 0.1))
			"transfusion":
				# two glass tanks with serum and the needle
				var gtr := Color(0.85, 0.2, 0.18) if not dim else Color(0.4, 0.3, 0.3)
				var gbr2 := Plague.BRASS if not dim else Color(0.38, 0.35, 0.3)
				for k in 2:
					var x0 := -11.0 + k * 10.0
					draw_rect(Rect2(c + Vector2(x0, -12), Vector2(7, 20)), Color(0.75, 0.85, 0.85, 0.35))
					draw_rect(Rect2(c + Vector2(x0, -4), Vector2(7, 12)), gtr)
					draw_rect(Rect2(c + Vector2(x0 - 1, -14), Vector2(9, 3)), gbr2)
					draw_rect(Rect2(c + Vector2(x0 - 1, 8), Vector2(9, 3)), gbr2)
				draw_line(c + Vector2(6, 2), c + Vector2(15, 14), steel, 2.0, true)
				draw_line(c + Vector2(15, 14), c + Vector2(19, 18), Color(0.9, 0.9, 0.95), 1.0, true)
			"experiment":
				# the vat, a curled shape inside
				var gvt := Plague.BRASS if not dim else Color(0.38, 0.35, 0.3)
				var gfl := Plague.MIASMA if not dim else Color(0.3, 0.34, 0.3)
				draw_rect(Rect2(c + Vector2(-11, -12), Vector2(22, 24)), gfl.darkened(0.2))
				draw_circle(c + Vector2(0, 1), 5.5, Color(0.8, 0.82, 0.7) if not dim else steel)
				draw_circle(c + Vector2(2, -1), 1.3, Color(0.1, 0.1, 0.1))
				for y in [-13, -2, 9]:
					draw_rect(Rect2(c + Vector2(-13, y), Vector2(26, 3)), gvt)
				draw_rect(Rect2(c + Vector2(-14, 12), Vector2(28, 4)), gvt.darkened(0.3))
				draw_arc(c + Vector2(14, 0), 4.0, 0, TAU, 10, gvt, 2.0, true)
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
				"shrine":
					var sc := Color(0.5, 0.5, 0.5) if it.used else Color(1.0, 0.55, 0.3)
					ci.draw_circle(sp2, 4.5, Color(0.05, 0.05, 0.05))
					ci.draw_circle(sp2, 3.0, sc)
				"chest":
					if not it.used:
						ci.draw_rect(Rect2(sp2 - Vector2(3.5, 2.5), Vector2(7, 5)), Color(0.85, 0.65, 0.3))
		# a Hollow Sloth close by: a red mark, so you can steer clear
		for sl in g.get_tree().get_nodes_in_group("sloth"):
			if is_instance_valid(sl) and not sl.dead and sl.global_position.distance_to(hp) < 40.0:
				var ssp := _to_screen(sl.global_position, hp)
				if _inside(ssp):
					var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
					ci.draw_circle(ssp, 7.5, Color(0, 0, 0, 0.75))
					ci.draw_circle(ssp, 5.5 * pulse, Color(0.95, 0.15, 0.1))
		# co-op partners (in the Battlegrounds only a duo's teammate: the other raiders are hidden)
		if g.net and g.net.active:
			for a in g.net.puppets():
				if not a.visible or (g.bg_mode and not Battlegrounds.is_teammate(g, int(a.peer_id))):
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
