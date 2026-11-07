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
var quest_panel: PanelContainer       # the quest log (J, Quests)
var quest_list: VBoxContainer
var quest_tracker: VBoxContainer     # the current objectives under the corner map
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
var chars_sub: Label
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
var auction_panel: PanelContainer
var shop_title: Label
var shop_grid: GridContainer
var shop_items: Array = []
var shop_mode := ""
var shop_view: Array = []      # the shop_items indices shown, in cell order (the open tab's)
var shop_tab := "All"
var shop_tabs: HBoxContainer
var shop_gold: Label
var shop_who: Label
var shop_role: Label
var shop_greet: Label
var shop_face: PanelContainer  # holds the trader's live portrait
var furnace_ui: FurnaceUI      # the furnace window (furnace_ui.gd), opened at Halvar's furnace
var trade_with: Inter = null   # the NPC whose window (dialog, trade, stash) is open: walking off closes it
var plates: Control            # VendorUI.Plates: nameplates over the town's people
var stash_panel: PanelContainer
var burn_panel: PanelContainer   # the camp's bonfire: drag or right-click an item to burn it for good
var vote_panel: Control          # the party's ready check (Net.ask_trip): Join / Not yet
var burn_fire: Control
var stash_cells: Array = []
var wp_panel: PanelContainer
var dialog_panel: PanelContainer
var dialog_name: Label
var dialog_text: Label
var dialog_btns: HBoxContainer
var gfx_info: Label
var pause_panel: PanelContainer
var invite_btn: Button
var gfx_btn: Button
var title_panel: Control
var sound_btn: Button
var test_panel: VBoxContainer          # the Escape menu's Admin column (dev tools)
var join_panel: PanelContainer
var join_list: VBoxContainer
var join_ip: LineEdit
var join_hint: Label
var join_character_id := ""
var hud: Control                  # the screen's layers (setup): the in-game HUD
var windows: Control              # inventory, character sheet, shops, the stash, the fire, waypoints
var menus: Control                # the title and its screens (characters, class picker, co-op, Battlegrounds)
var modals: Control               # dialogs, the party vote, the pause menu, the F8 panel, death
var top: Control                  # tooltips, drags, messages, sparkles: over everything
var menu_shade: ColorRect         # under a menu screen opened over the title: dims it and keeps its clicks off it
var home: TitleHome               # the title's controls (title_home.gd): the character sidebar, the modes and Play
var _join_refresh := 0.0
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
var day_clock: DayClock              # the camp's hour on the corner map's ring
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
	plates = VendorUI.Plates.new()
	plates.ui = self
	hud.add_child(plates)
	_build_hud()
	chat = ChatBox.attach(self)
	_build_inventory()
	_build_character()
	_build_shop()
	auction_panel = AuctionUI.build(self)    # the Gilded Hall's window (auction_ui.gd)
	_build_stash()
	_build_burn()
	furnace_ui = FurnaceUI.new()
	windows.add_child(furnace_ui)
	furnace_ui.build(self)
	_build_vote()
	_build_waypoints()
	_build_dialog()
	_build_pause()
	_build_skills_panel()
	_build_talent_panel()
	_build_quests()
	_build_tooltip()
	_build_title()
	_build_join()
	_build_enchant()
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
	# the camp's hour (DayNight), a small dial on the corner map's ring at its lower left
	day_clock = DayClock.new()
	day_clock.game = game
	day_clock.font = font_title
	day_clock.anchor_left = 1.0
	day_clock.anchor_right = 1.0
	day_clock.offset_left = -225
	day_clock.offset_right = -173
	day_clock.offset_top = 195
	day_clock.offset_bottom = 247
	hud.add_child(day_clock)
	quest_tracker = VBoxContainer.new()
	quest_tracker.anchor_left = 1.0
	quest_tracker.anchor_right = 1.0
	quest_tracker.offset_left = -250
	quest_tracker.offset_right = -18
	quest_tracker.offset_top = 262
	quest_tracker.add_theme_constant_override("separation", 1)
	quest_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(quest_tracker)

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
const HINT_STORY := "WASD: move  ·  Left mouse: attack  ·  Right mouse, Q E R F G V: skills (K to set them)  ·  Space: dodge roll (hold to sprint)  ·  N: rites  ·  J: quests  ·  1-4: potions  ·  I/C: inventory/stats  ·  T: portal  ·  Tab: map"
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
## The quest log (J): every quest taken, the main quest first, with its story, objectives and reward. The tracker
## under the corner map lists the current objectives. Both redraw when a quest moves (Quests.changed).
func _build_quests() -> void:
	quest_panel = _panel("Quests", true, 540, 470)
	var vb: VBoxContainer = quest_panel.get_node("vb")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	quest_list = VBoxContainer.new()
	quest_list.add_theme_constant_override("separation", 14)
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(quest_list)
	quest_panel.visibility_changed.connect(func():
		if quest_panel.visible:
			_fill_quests())
	game.quests.changed.connect(func():
		_fill_tracker()
		if quest_panel.visible:
			_fill_quests())

func _fill_quests() -> void:
	for c in quest_list.get_children():
		c.queue_free()
	var qs = game.quests
	var shown := 0
	for pass_done in [false, true]:
		for q in qs.current() if not pass_done else qs.line().filter(func(x): return qs.status(x["id"]) == "done"):
			var id: String = q["id"]
			var s: String = qs.status(id)
			# each quest on its own inset card: a gold edge for the act's main quest, dimmer when done
			var card := PanelContainer.new()
			var csb := StyleBoxFlat.new()
			csb.bg_color = Color(0.035, 0.03, 0.03, 0.85)
			csb.border_color = (GOLD if q.get("main", false) else Color(0.55, 0.45, 0.3)).darkened(0.45 if s == "done" else 0.0)
			csb.border_width_left = 4
			csb.border_width_top = 1
			csb.border_width_right = 1
			csb.border_width_bottom = 1
			csb.content_margin_left = 14
			csb.content_margin_right = 10
			csb.content_margin_top = 8
			csb.content_margin_bottom = 10
			card.add_theme_stylebox_override("panel", csb)
			quest_list.add_child(card)
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 3)
			card.add_child(box)
			var tl := _label(("◆  " if q.get("main", false) else "") + str(q["name"]) + ("   (done)" if s == "done" else ""), 19, GOLD if s != "done" else DIM, true)
			box.add_child(tl)
			var who: String = Data.VENDORS.get(q["giver"], "")
			box.add_child(_label(("Main quest  ·  " if q.get("main", false) else "") + "From " + who, 12, DIM))
			var story := _label(str(q["done"] if s != "active" else q["busy"]), 14)
			story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			story.custom_minimum_size = Vector2(470, 0)
			box.add_child(story)
			if s != "done":
				var c: Array = qs.counts(id)
				var goals: Array = q["goals"]
				for i in goals.size():
					var g: Dictionary = goals[i]
					var got: bool = int(c[i]) >= int(g["n"])
					var gl := _label(("☑  " if got else "☐  ") + str(g["text"]) + ("   %d / %d" % [c[i], g["n"]] if int(g["n"]) > 1 else ""), 14, Color(0.6, 0.85, 0.5) if got else Color(0.9, 0.86, 0.78))
					box.add_child(gl)
				if s == "ready":
					box.add_child(_label("✔  Return to " + who, 14, Color(1.0, 0.82, 0.45)))
				var rw := _label("Reward: " + qs.reward_text(q), 13, DIM)
				rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				rw.custom_minimum_size = Vector2(470, 0)
				box.add_child(rw)
			shown += 1
	if shown == 0:
		var none := _label("No quests yet. Talk to the people of the camp: a gold ! over someone means they have work for you.", 14, DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(500, 0)
		quest_list.add_child(none)
	# what's ahead, under the list (the log is never a bare frame)
	var dv := _divider(24)
	dv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quest_list.add_child(dv)
	var hint := _label("More work turns up as you go: a gold ! over someone in the camp has a job for you, a ? is ready to hand in. The tracker under the map keeps the current ones in sight.", 13, Color(0.6, 0.56, 0.48))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(470, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quest_list.add_child(hint)

func _fill_tracker() -> void:
	if quest_tracker == null:
		return
	for c in quest_tracker.get_children():
		c.queue_free()
	var qs = game.quests
	for q in (qs.current() as Array).slice(0, 4):
		var id: String = q["id"]
		var t := _label(str(q["name"]), 15, GOLD, true)
		t.add_theme_constant_override("outline_size", 4)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quest_tracker.add_child(t)
		var lines: Array = []
		if qs.status(id) == "ready":
			lines.append(["✔ Return to " + str(Data.VENDORS.get(q["giver"], "")), Color(1.0, 0.82, 0.45)])
		else:
			var c: Array = qs.counts(id)
			var goals: Array = q["goals"]
			for i in goals.size():
				if int(c[i]) < int(goals[i]["n"]):
					lines.append(["· %s%s" % [goals[i]["text"], (" %d/%d" % [c[i], goals[i]["n"]]) if int(goals[i]["n"]) > 1 else ""], Color(0.88, 0.85, 0.78)])
		for ln in lines:
			var l := _label(str(ln[0]), 13, ln[1])
			l.add_theme_constant_override("outline_size", 4)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			quest_tracker.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quest_tracker.add_child(gap)

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
		if p == shop_panel or p == stash_panel or p == burn_panel:
			shop_mode = ""
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
		shop_panel.visible = false
		stash_panel.visible = false
		burn_panel.visible = false
		shop_mode = ""
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
		var c := _slot(Vector2(CELL, CELL), func(ev): _inv_click(idx, ev), func(p, on): _hover(p, on, "sell" if shop_mode in ["smith", "armor", "alch", "gamble"] else ("stash" if shop_mode == "stash" else "inv")), "", true)
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
		if shop_mode in ["smith", "armor", "alch", "gamble"]:
			hero.inventory[idx] = null
			hero.gold += Items.sell_price(it)
			Sfx.play("gold")
			refresh()
		elif shop_mode == "burn":
			burn_request(idx)
		elif shop_mode == "reforge":
			reforge_request(idx)
		elif shop_mode == "furnace":
			furnace_ui.bag_click(idx, ev.shift_pressed)
		elif shop_mode == "stash":
			if game.stash_deposit(idx, stash_tab):
				Sfx.play("pickup")
			tooltip.visible = false
			refresh()
		elif not Items.is_equip(it) and not Items.is_material(it):
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
	if burn_panel.visible and burn_fire.get_global_rect().has_point(mp):
		return ["fire", null]
	for pnl in [inv_panel, char_panel, stash_panel, burn_panel, shop_panel, wp_panel, dialog_panel, action_bar, skills_panel, talent_panel]:
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
		"fire":
			if shop_mode == "reforge":
				reforge_request(idx)
			else:
				burn_request(idx)
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
		for p in [inv_panel, char_panel, skills_panel, talent_panel, quest_panel]:
			if p == null or p.visible:
				continue
			toggle(p)
			await RenderingServer.frame_post_draw
			p.visible = false
		if wp_panel != null and not wp_panel.visible:
			open_waypoints()
			await RenderingServer.frame_post_draw
			wp_panel.visible = false
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

# ---------------------------------------------------------------- shops & stash
func _build_shop() -> void:
	shop_panel = _panel("Merchant", true, 500, 600)
	var vb: VBoxContainer = shop_panel.get_node("vb")
	shop_title = shop_panel.get_node("vb").get_child(0).get_node("title")
	shop_title.add_theme_font_size_override("font_size", 15)
	shop_title.add_theme_color_override("font_color", DIM)
	# the trader: their live portrait beside their name, trade and greeting, and your purse
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	shop_face = PanelContainer.new()
	shop_face.add_theme_stylebox_override("panel", _box(Color(0.07, 0.05, 0.035), Color(0.62, 0.48, 0.26), 2, 4, 2))
	shop_face.custom_minimum_size = Vector2(136, 160)
	head.add_child(shop_face)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	head.add_child(info)
	shop_who = _label("", 26, GOLD, true)
	info.add_child(shop_who)
	shop_role = _label("", 13, Color(0.74, 0.66, 0.52))
	var fv := FontVariation.new()
	fv.base_font = font_body
	fv.spacing_glyph = 2
	shop_role.add_theme_font_override("font", fv)
	info.add_child(shop_role)
	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.43, 0.24, 0.5)
	rule.custom_minimum_size = Vector2(0, 1)
	info.add_child(rule)
	shop_greet = _label("", 15, Color(0.86, 0.82, 0.74))
	shop_greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_greet.custom_minimum_size = Vector2(280, 0)
	shop_greet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(shop_greet)
	var purse := PanelContainer.new()
	purse.add_theme_stylebox_override("panel", _box(Color(0.03, 0.025, 0.02, 0.9), Color(0.4, 0.31, 0.17), 1, 3, 6))
	info.add_child(purse)
	shop_gold = _label("", 17, Color(1.0, 0.85, 0.4), true)
	purse.add_child(shop_gold)
	# what they sell, by kind
	shop_tabs = HBoxContainer.new()
	shop_tabs.add_theme_constant_override("separation", 4)
	vb.add_child(shop_tabs)
	shop_grid = GridContainer.new()
	shop_grid.columns = 10
	shop_grid.add_theme_constant_override("h_separation", 3)
	shop_grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(shop_grid)
	for i in 50:
		var idx := i
		var c := _slot(Vector2(CELL, CELL + 14), func(ev): if ev.button_index == MOUSE_BUTTON_LEFT: _buy(idx), func(p, on): _hover(p, on, "gamble" if shop_mode == "gamble" else "buy"))
		var ic: Control = c.get_node("icon")
		ic.offset_bottom = -16
		var pr := _label("", 11, Color(1.0, 0.85, 0.4))
		pr.name = "price"
		pr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		pr.offset_top = -15
		pr.offset_bottom = -1
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(pr)
		shop_grid.add_child(c)
	vb.add_child(_label("Left-click to buy  ·  Right-click your own items to sell  ·  Walk away to close", 13, DIM))

const SHOP_KINDS := {"weapon": "Weapons", "shield": "Shields", "armor": "Armour", "helm": "Armour", "gloves": "Armour",
	"boots": "Armour", "belt": "Armour", "ring": "Jewellery", "amulet": "Jewellery", "potion": "Potions", "tool": "Tools", "resource": "Goods"}

static func shop_kind(it: Dictionary) -> String:
	return str(SHOP_KINDS.get(str(Data.BASES[it["base"]]["slot"]), "Goods"))

func shop_cost(it: Dictionary) -> int:
	return Items.price(it) * (2 if shop_mode == "gamble" else 1)

## The trade window, headed by the trader (who, when there is one: their portrait, name and trade).
func open_shop(mode: String, title: String, items: Array, who: Inter = null, greet := "") -> void:
	if furnace_ui != null:
		furnace_ui.visible = false
	shop_mode = mode
	shop_items = items
	shop_title.text = title
	shop_tab = "All"
	for c in shop_face.get_children():
		c.queue_free()
	shop_face.visible = who != null
	if who:
		trade_with = who
		var pt := VendorUI.Portrait.new()
		shop_face.add_child(pt)
		pt.setup(who)
	shop_who.text = who.label if who else title
	shop_role.text = VendorUI.title_for(who).to_upper() if who else ""
	shop_greet.text = ("“%s”" % greet) if greet != "" else ""
	shop_panel.visible = true
	stash_panel.visible = false
	burn_panel.visible = false
	inv_panel.visible = true
	char_panel.visible = false
	_refresh_shop()

func _refresh_shop() -> void:
	# the tabs: All, then each kind on sale (only when there's more than one); rebuilt only on a change
	var kinds := []
	for it in shop_items:
		var k := shop_kind(it)
		if k not in kinds:
			kinds.append(k)
	if shop_tab not in kinds:
		shop_tab = "All"
	var sig := "%s %s" % [shop_tab, kinds]
	var shown: String = str(shop_tabs.get_meta("sig")) if shop_tabs.has_meta("sig") else ""
	if shown != sig:
		shop_tabs.set_meta("sig", sig)
		for c in shop_tabs.get_children():
			shop_tabs.remove_child(c)
			c.queue_free()
		if kinds.size() > 1:
			for k in ["All"] + kinds:
				var b := Button.new()
				b.text = k
				b.toggle_mode = true
				b.button_pressed = k == shop_tab
				b.add_theme_font_size_override("font_size", 14)
				b.custom_minimum_size = Vector2(0, 28)
				var kk: String = k
				b.pressed.connect(func():
					shop_tab = kk
					Sfx.play("click")
					_refresh_shop())
				shop_tabs.add_child(b)
	shop_view = []
	for i in shop_items.size():
		if shop_tab == "All" or shop_kind(shop_items[i]) == shop_tab:
			shop_view.append(i)
	# the goods, each priced (red and dimmed when you can't afford it)
	for i in shop_grid.get_child_count():
		var cell: Panel = shop_grid.get_child(i)
		var it = shop_items[shop_view[i]] if i < shop_view.size() else null
		_set_slot(cell, it)
		var pr: Label = cell.get_node("price")
		var ic: Control = cell.get_node("icon")
		if it == null:
			pr.text = ""
			ic.modulate = Color.WHITE
			continue
		var cost := shop_cost(it)
		var ok: bool = hero == null or hero.gold >= cost
		pr.text = "%d g" % cost
		pr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if ok else Color(0.9, 0.35, 0.28))
		ic.modulate = Color.WHITE if ok else Color(0.55, 0.5, 0.5)
	if hero:
		shop_gold.text = "◉  Your gold: %d" % hero.gold

## Buys what's in cell idx of the open tab.
func _buy(cell: int) -> void:
	if cell >= shop_view.size():
		return
	var idx: int = shop_view[cell]
	var it: Dictionary = shop_items[idx]
	var cost := shop_cost(it)
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

## The shared stash (SharedStash, Game.stash: one for every character, never at stake): the inventory's iron and gold
## frame, a title plate, SharedStash.TABS tabs over a 10 x 6 grid of the bag's sockets, and a count. Three looks for
## the tabs while jj picks (STASH_STYLES; `stash_style`): bronze plaques, hanging cloth ribbons, rune-gem sockets.
## A click on a stash item takes it to the bag; a click on a bag item (with the stash open) puts it in this tab.
const STASH_SIZE := Vector2(600, 548)
const STASH_K := 0.3                  # the frame at 0.3 of the painted art (the inventory's is INV_SCALE)
const STASH_GRID := Vector2(70, 140)
const STASH_STYLES := ["plaques", "ribbons", "gems"]
const STASH_NUMERALS := ["I", "II", "III", "IV", "V"]
const STASH_COLORS := [Color(0.62, 0.12, 0.1), Color(0.16, 0.3, 0.62), Color(0.18, 0.46, 0.22), Color(0.42, 0.2, 0.55), Color(0.78, 0.55, 0.16)]
var stash_style := "plaques"
var stash_tab := 0
var stash_tab_row: Control
var stash_count_lbl: Label

## One tab of the stash, drawn in the chosen style.
class StashTab extends Control:
	var ui
	var idx := 0
	var hover := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			hover = true
			queue_redraw())
		mouse_exited.connect(func():
			hover = false
			queue_redraw())
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			ui.select_stash_tab(idx)
	func _draw() -> void:
		var on: bool = ui.stash_tab == idx
		var st: String = ui.stash_style
		var f: Font = ui.font_title
		var num: String = STASH_NUMERALS[idx]
		var col: Color = STASH_COLORS[idx]
		var n: int = ui.game.stash.tab_count(idx) if ui.game.stash != null else 0
		var lit := 1.0 if on else (0.8 if hover else 0.55)
		match st:
			"plaques":
				var r := Rect2(Vector2(2, 4 if on else 8), size - Vector2(4, 8 if on else 12))
				if on:
					draw_rect(r.grow(5), Color(1.0, 0.7, 0.3, 0.12))
					draw_rect(r.grow(2), Color(1.0, 0.75, 0.35, 0.25))
				draw_texture_rect(ui.stash_plate_tex(), r, false, Color(lit, lit, lit))
				_text(f, num, r.get_center() + Vector2(0, -3 if n > 0 else 1), 18, Color(1.0, 0.86, 0.55) * Color(lit, lit, lit, 1.0) if on else Color(0.82, 0.68, 0.45, 0.85))
				if n > 0:
					_text(ui.font_body, str(n), r.get_center() + Vector2(0, 12), 11, Color(0.95, 0.85, 0.65, 0.75 if on else 0.5))
				if on:
					draw_line(Vector2(r.position.x + 14, size.y - 1), Vector2(r.end.x - 14, size.y - 1), Color(1.0, 0.75, 0.35), 2.0)
			"ribbons":
				var h := size.y if on else size.y - 10
				var w := size.x - 10
				var x0 := 5.0
				var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0), Vector2(x0 + w, h), Vector2(x0 + w * 0.5, h - 10), Vector2(x0, h)])
				var cloth := col.darkened(0.15 if on else 0.45)
				if hover and not on:
					cloth = col.darkened(0.3)
				draw_colored_polygon(pts, cloth)
				# the weave's shading and the gold stitching down both edges
				draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w * 0.35, 0), Vector2(x0 + w * 0.35, h - 6), Vector2(x0, h)]), Color(1, 1, 1, 0.06))
				var stitch := Color(0.85, 0.66, 0.32, 0.9 if on else 0.5)
				draw_line(Vector2(x0 + 4, 2), Vector2(x0 + 4, h - 4), stitch, 1.0)
				draw_line(Vector2(x0 + w - 4, 2), Vector2(x0 + w - 4, h - 4), stitch, 1.0)
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), Color(0, 0, 0, 0.7), 1.5)
				# the bronze rod it hangs from
				draw_rect(Rect2(0, -3, size.x, 5), Color(0.55, 0.42, 0.22))
				draw_rect(Rect2(0, -3, size.x, 2), Color(0.85, 0.68, 0.38))
				_text(f, num, Vector2(size.x * 0.5, h * 0.42), 17, Color(1.0, 0.9, 0.7) if on else Color(0.9, 0.82, 0.66, 0.75))
				if n > 0:
					_text(ui.font_body, str(n), Vector2(size.x * 0.5, h * 0.42 + 15), 11, Color(1, 0.92, 0.75, 0.7))
			"gems":
				var c := Vector2(size.x * 0.5, 22)
				if on:
					for i in 4:
						draw_circle(c, 24.0 + i * 3.0, Color(col.r, col.g, col.b, 0.1 - i * 0.02))
				draw_circle(c, 19, Color(0.05, 0.04, 0.03))
				draw_arc(c, 18, 0, TAU, 40, Color(0.62, 0.48, 0.25), 3.0, true)
				draw_arc(c, 15.5, 0, TAU, 40, Color(0.25, 0.18, 0.1), 1.5, true)
				var g := col.lightened(0.25) if on else col.darkened(0.35 if not hover else 0.1)
				draw_circle(c, 12.5, g.darkened(0.35))
				draw_circle(c + Vector2(-1, -1), 10, g)
				draw_circle(c + Vector2(-4, -4.5), 3.2, Color(1, 1, 1, 0.55 if on else 0.25))
				# four little prongs holding the stone
				for k in 4:
					var a := PI * 0.25 + k * PI * 0.5
					draw_circle(c + Vector2(cos(a), sin(a)) * 13.0, 2.0, Color(0.78, 0.62, 0.34))
				_text(f, num, Vector2(size.x * 0.5, 54), 14, Color(1.0, 0.86, 0.55) if on else Color(0.72, 0.62, 0.45, 0.8))
	func _text(f: Font, t: String, at: Vector2, px: int, c: Color) -> void:
		if f == null:
			return
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var p := at + Vector2(-w * 0.5, px * 0.35)
		draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0, 0, 0, 0.85))
		draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)

var _stash_plate: Texture2D
func stash_plate_tex() -> Texture2D:
	if _stash_plate == null:
		_stash_plate = load(INV_TEX["plate"])
	return _stash_plate

func _build_stash() -> void:
	stash_panel = PanelContainer.new()
	stash_panel.position = Vector2(24, 36)
	stash_panel.custom_minimum_size = STASH_SIZE
	stash_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	stash_panel.visible = false
	windows.add_child(stash_panel)
	stash_panel.visibility_changed.connect(func():
		if not stash_panel.visible and is_instance_valid(trade_with) and trade_with.kind == "stash":
			game.chest_lid(trade_with, false))
	var body := Control.new()
	body.name = "body"
	body.custom_minimum_size = STASH_SIZE
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	stash_panel.add_child(body)
	var trim := int(178 * STASH_K)
	var iron := TextureRect.new()
	iron.texture = _scaled_tex(INV_TEX["iron"], STASH_K)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(trim, trim)
	iron.size = STASH_SIZE - Vector2(trim * 2, trim * 2 - 2)
	iron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(iron)
	var frame := NinePatchRect.new()
	frame.texture = _ornate_frame(STASH_K)
	var pm := int(INV_PATCH * STASH_K)
	frame.patch_margin_left = pm
	frame.patch_margin_right = pm
	frame.patch_margin_top = pm
	frame.patch_margin_bottom = pm
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.draw_center = false
	frame.size = STASH_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(frame)
	var plate := TextureRect.new()
	plate.texture = stash_plate_tex()
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(220, 34)
	plate.position = Vector2((STASH_SIZE.x - 220) * 0.5, 10)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(plate)
	var title := _label("STASH", 15, GOLD, true)
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
	var lfv := FontVariation.new()
	lfv.base_font = font_body
	lfv.spacing_glyph = 2
	var sub := Caption.new()
	sub.text = "SHARED BY ALL YOUR CHARACTERS  ·  NEVER AT STAKE"
	sub.font = lfv
	sub.size_px = 11
	sub.position = Vector2(0, 50)
	sub.size = Vector2(STASH_SIZE.x, 14)
	body.add_child(sub)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_color_override("font_color", Color(0.85, 0.7, 0.42))
	x.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.5))
	x.add_theme_font_size_override("font_size", 18)
	x.position = Vector2(STASH_SIZE.x - pm - 30, 13)
	x.size = Vector2(30, 30)
	x.pressed.connect(func():
		stash_panel.visible = false
		tooltip.visible = false
		shop_mode = ""
		Sfx.play("click"))
	body.add_child(x)
	stash_tab_row = Control.new()
	stash_tab_row.position = Vector2(STASH_GRID.x, 70)
	stash_tab_row.size = Vector2(460, 66)
	stash_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stash_tab_row)
	_layout_stash_tabs()
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	grid.position = STASH_GRID
	body.add_child(grid)
	body.add_child(_inset_line(Rect2(STASH_GRID, Vector2(10 * (CELL + 2) - 2, 6 * (CELL + 2) - 2))))
	for i in SharedStash.SLOTS:
		var idx := i
		var c := _slot(Vector2(CELL, CELL), func(ev):
			if ev.button_index == MOUSE_BUTTON_RIGHT or ev.button_index == MOUSE_BUTTON_LEFT:
				if game.stash_withdraw(stash_tab, idx):
					Sfx.play("pickup")
				tooltip.visible = false
				refresh(), func(p, on): _hover(p, on, "stash"), "", true)     # the bag's iron sockets
		grid.add_child(c)
		stash_cells.append(c)
	stash_count_lbl = _label("", 14, Color(0.86, 0.78, 0.6))
	stash_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stash_count_lbl.position = Vector2(0, STASH_GRID.y + 6 * (CELL + 2) + 12)
	stash_count_lbl.size = Vector2(STASH_SIZE.x, 20)
	body.add_child(stash_count_lbl)
	var hint := _label("Click an item to move it between the stash and your bag", 12, DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, STASH_GRID.y + 6 * (CELL + 2) + 34)
	hint.size = Vector2(STASH_SIZE.x, 18)
	body.add_child(hint)

## The tab row for `stash_style`: plaques side by side, ribbons hanging from a rod, gems in a row.
func _layout_stash_tabs() -> void:
	for c in stash_tab_row.get_children():
		stash_tab_row.remove_child(c)
		c.queue_free()
	var n := SharedStash.TABS
	var w := 460.0
	for i in n:
		var t := StashTab.new()
		t.ui = self
		t.idx = i
		match stash_style:
			"plaques":
				var tw := (w - 6.0 * (n - 1)) / n
				t.position = Vector2(i * (tw + 6.0), 14)
				t.size = Vector2(tw, 50)
			"ribbons":
				var tw2 := 64.0
				var gap := (w - tw2 * n) / (n - 1)
				t.position = Vector2(i * (tw2 + gap), 6)
				t.size = Vector2(tw2, 60)
			_:
				var tw3 := 64.0
				var gap3 := (w - tw3 * n) / (n - 1)
				t.position = Vector2(i * (tw3 + gap3), 0)
				t.size = Vector2(tw3, 66)
		stash_tab_row.add_child(t)

func select_stash_tab(i: int) -> void:
	if i == stash_tab:
		return
	stash_tab = i
	Sfx.play("click")
	refresh()

func set_stash_style(st: String) -> void:
	stash_style = st
	_layout_stash_tabs()
	refresh()

func open_stash() -> void:
	if not game.stash_allowed():
		message("The stash can't be opened here", Color(1, 0.6, 0.4))
		return
	game.stash.fresh()
	if furnace_ui != null:
		furnace_ui.visible = false
	shop_mode = "stash"
	burn_panel.visible = false
	stash_panel.visible = true
	shop_panel.visible = false
	char_panel.visible = false
	inv_panel.visible = true
	refresh()

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

## The camp's bonfire: a window with the fire in it beside your inventory. Drag an item onto the flames, or
## right-click it, and it burns, gone for good (rare, unique and the sloths' materials ask first).
## The bonfire window in the inventory's iron and bronze (the same frame, plate and trim): the fire burns in
## a recessed stone hearth on an iron grate; drop an item on it (or right-click it in the bag) to burn it.
## Below the hearth, what the fire can do (`BONFIRE_OPTIONS`, in the action bar's sockets): Burn and Enchant
## now, with empty sockets left for what comes later (a new entry here fills the next one).
const BURN_SIZE := Vector2(360, 590)
const BURN_SCALE := 0.26
const BURN_HEARTH := Rect2(52, 112, 256, 260)
const BONFIRE_OPTIONS := [
	["burn", "Burn", "Throw unwanted gear on the fire. Drag it onto the flames or right-click it in your bag."],
	["enchant", "Enchant", "Bind runes into your worn armour over the flames: more defense and life, up to +10."],
	["reforge", "Reforge", "Spend a Cinderheart, Everfrost or Stormglass: the weakest affix of a magic or rare item is rerolled. Right-click it in your bag or drag it onto the flames."],
]
const BONFIRE_SOCKETS := 6
var burn_hint: Label
var burn_opts := {}

func _build_burn() -> void:
	burn_panel = PanelContainer.new()
	burn_panel.position = Vector2(24, 64)
	burn_panel.custom_minimum_size = BURN_SIZE
	burn_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	burn_panel.visible = false
	windows.add_child(burn_panel)
	var body := Control.new()
	body.custom_minimum_size = BURN_SIZE
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	burn_panel.add_child(body)
	var trim := int(178 * BURN_SCALE)
	var iron := TextureRect.new()
	iron.texture = _scaled_tex(INV_TEX["iron"], BURN_SCALE)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(trim, trim)
	iron.size = BURN_SIZE - Vector2(trim * 2, trim * 2 - 2)
	iron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(iron)
	var frame := NinePatchRect.new()
	frame.texture = _scaled_tex(INV_TEX["frame"], BURN_SCALE)
	var pm := int(INV_PATCH * BURN_SCALE)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		frame.set_patch_margin(side, pm)
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	frame.draw_center = false
	frame.size = BURN_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(frame)
	var plate := TextureRect.new()
	plate.texture = load(INV_TEX["plate"])
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(150, 30)
	plate.position = Vector2((BURN_SIZE.x - 150) * 0.5, 11)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(plate)
	var title := _label("BONFIRE", 14, GOLD, true)
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
	x.add_theme_font_size_override("font_size", 16)
	x.position = Vector2(BURN_SIZE.x * 0.5 + 80, 12)
	x.size = Vector2(28, 28)
	x.pressed.connect(func():
		burn_panel.visible = false
		tooltip.visible = false
		shop_mode = ""
		Sfx.play("click"))
	body.add_child(x)
	var t := _label("Drag an item onto the fire, or right-click it in your bag. It burns for good.", 13, Color(0.8, 0.74, 0.62))
	burn_hint = t
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(66, 58)
	t.size = Vector2(BURN_SIZE.x - 132, 48)
	body.add_child(t)
	# the hearth: a recess in the iron, a bronze line round it, the fire inside
	var well := Panel.new()
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.03, 0.025, 0.022)
	wsb.shadow_color = Color(0, 0, 0, 0.6)
	wsb.shadow_size = 6
	well.add_theme_stylebox_override("panel", wsb)
	well.position = BURN_HEARTH.position
	well.size = BURN_HEARTH.size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(well)
	burn_fire = Flames.new()
	burn_fire.position = BURN_HEARTH.position
	burn_fire.size = BURN_HEARTH.size
	burn_fire.clip_contents = true
	burn_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(burn_fire)
	body.add_child(_inset_line(BURN_HEARTH))
	# what the fire can do: a socket each, three to a row; the empty ones wait for upgrades
	var grid_at := Vector2(BURN_HEARTH.position.x + 6, BURN_HEARTH.end.y + 18)
	if _socket_tex == null:
		_socket_tex = _scaled_tex(BAR_TEX["slot"], 0.3)
	for i in BONFIRE_SOCKETS:
		var cell := Control.new()
		cell.position = grid_at + Vector2((i % 3) * 84, (i / 3) * 86)
		cell.size = Vector2(76, 80)
		body.add_child(cell)
		var sock := Panel.new()
		var sb := StyleBoxTexture.new()
		sb.texture = _socket_tex
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 9)
		sock.add_theme_stylebox_override("panel", sb)
		sock.position = Vector2(12, 0)
		sock.size = Vector2(52, 52)
		cell.add_child(sock)
		if i >= BONFIRE_OPTIONS.size():
			sock.modulate = Color(0.55, 0.52, 0.5)
			sock.tooltip_text = "More to come"
			continue
		var opt: Array = BONFIRE_OPTIONS[i]
		var id: String = opt[0]
		var ic := FireIcon.new()
		ic.kind = id
		ic.position = Vector2(6, 6)
		ic.size = Vector2(40, 40)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sock.add_child(ic)
		var lb := _label(str(opt[1]), 13, Color(0.86, 0.8, 0.7))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.position = Vector2(0, 54)
		lb.size = Vector2(76, 20)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lb)
		var b := Button.new()
		b.flat = true
		b.position = Vector2.ZERO
		b.size = cell.size
		b.tooltip_text = str(opt[2])
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func(): _bonfire_option(id))
		cell.add_child(b)
		burn_opts[id] = [sock, lb]
	_bonfire_select("burn")

func _bonfire_select(id: String) -> void:
	for k in burn_opts:
		var on: bool = k == id
		(burn_opts[k][0] as Panel).modulate = Color(1.35, 1.15, 0.85) if on else Color.WHITE
		(burn_opts[k][1] as Label).add_theme_color_override("font_color", GOLD if on else Color(0.86, 0.8, 0.7))

func _bonfire_option(id: String) -> void:
	Sfx.play("click")
	match id:
		"burn":
			_bonfire_select("burn")
			shop_mode = "burn"
			burn_hint.text = "Drag an item onto the fire, or right-click it in your bag. It burns for good."
		"reforge":
			_bonfire_select("reforge")
			shop_mode = "reforge"
			burn_hint.text = "Drag a magic or rare item onto the fire, or right-click it: one Sloth material rerolls its weakest affix."
		"enchant":
			var fire = trade_with
			open_enchant("Bonfire")
			trade_with = fire

## The bonfire's option icons, drawn: a flame (Burn), a rune-lit breastplate (Enchant).
class FireIcon extends Control:
	var kind := ""
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var s := size.x
		match kind:
			"burn":
				var cols := [Color(0.8, 0.15, 0.04), Color(1.0, 0.5, 0.1), Color(1.0, 0.85, 0.45)]
				for k in 3:
					var h := s * (0.42 - k * 0.1)
					var w := s * (0.22 - k * 0.05)
					var sw := sin(_t * 4.0 + k) * 2.0
					var b := c + Vector2(0, s * 0.3)
					draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.9 + sw * 0.3, -h * 0.55),
						b + Vector2(sw, -h * 1.6), b + Vector2(w * 0.9 + sw * 0.3, -h * 0.55), b + Vector2(w, 0)]), cols[k])
			"reforge":
				# an anvil with a hammer over it, sparks off the blow
				draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.02), Vector2(s * 0.6, s * 0.12)), Color(0.42, 0.4, 0.38))
				draw_rect(Rect2(c + Vector2(-s * 0.12, s * 0.14), Vector2(s * 0.24, s * 0.16)), Color(0.36, 0.34, 0.32))
				var sw := sin(_t * 4.0) * 0.25
				var hp := c + Vector2(s * 0.08, -s * 0.18)
				draw_line(hp, hp + Vector2(cos(-0.9 + sw), sin(-0.9 + sw)) * s * 0.3, Color(0.55, 0.38, 0.2), 3.0)
				draw_rect(Rect2(hp + Vector2(-s * 0.09, -s * 0.06), Vector2(s * 0.18, s * 0.12)), Color(0.75, 0.6, 0.35))
				var glow2 := 0.5 + 0.5 * sin(_t * 8.0)
				for k in 3:
					draw_circle(c + Vector2(-s * 0.1 + k * s * 0.1, -s * 0.02 - glow2 * s * 0.08), s * 0.025, Color(1.0, 0.7, 0.3, glow2))
			"enchant":
				var pts := PackedVector2Array([c + Vector2(-s * 0.32, -s * 0.3), c + Vector2(s * 0.32, -s * 0.3), c + Vector2(s * 0.26, s * 0.12),
					c + Vector2(0, s * 0.36), c + Vector2(-s * 0.26, s * 0.12)])
				draw_colored_polygon(pts, Color(0.42, 0.4, 0.38))
				draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.75, 0.6, 0.35), 1.5)
				var glow := 0.6 + 0.4 * sin(_t * 3.0)
				var r := c + Vector2(0, -s * 0.02)
				for a in 4:
					var ang := a * PI * 0.5 + _t * 0.6
					draw_line(r, r + Vector2(cos(ang), sin(ang)) * s * 0.16, Color(0.55, 0.9, 1.0, glow), 2.0)
				draw_circle(r, s * 0.05, Color(0.8, 0.95, 1.0, glow))

## Halvar's furnace: the furnace window beside the bag (FurnaceUI); right-clicks in the bag feed it.
func open_furnace(f: Furnace) -> void:
	ench_panel.visible = false
	burn_panel.visible = false
	stash_panel.visible = false
	shop_panel.visible = false
	char_panel.visible = false
	shop_mode = "furnace"
	trade_with = f
	furnace_ui.open(f)
	inv_panel.visible = true
	refresh()

func open_burn() -> void:
	if furnace_ui != null:
		furnace_ui.visible = false
	shop_mode = "burn"
	ench_panel.visible = false
	_bonfire_select("burn")
	stash_panel.visible = false
	shop_panel.visible = false
	char_panel.visible = false
	burn_panel.visible = true
	inv_panel.visible = true
	refresh()

## Burns inventory slot idx, asking first for anything rare, unique or a material.
func burn_request(idx: int) -> void:
	var it = hero.inventory[idx]
	if it == null:
		return
	tooltip.visible = false
	if int(it.get("rarity", 0)) >= 2 or Data.BASES[it["base"]].get("slot", "") == "material":
		open_dialog("Bonfire", "Burn the %s? It will be gone forever." % it["name"], [
			["Burn it", func(): _burn(idx, it)],
			["Keep it", func(): pass]])
		return
	_burn(idx, it)

## The bonfire's Reforge (the items rework: rewards from effort): a magic or rare item's weakest affix rerolled for
## one Sloth material from the bag (Items.reforge).
func reforge_request(idx: int) -> void:
	var it = hero.inventory[idx]
	if it == null:
		return
	tooltip.visible = false
	if not Items.can_reforge(it):
		message("Only magic and rare items can be reforged", Color(1, 0.5, 0.35))
		Sfx.play("deny")
		return
	var mat := -1
	for i in hero.inventory.size():
		if Items.is_material(hero.inventory[i]):
			mat = i
			break
	if mat < 0:
		message("You need a Cinderheart, Everfrost or Stormglass (the Hollow Sloths carry them)", Color(1, 0.5, 0.35))
		Sfx.play("deny")
		return
	var spent: String = hero.inventory[mat]["name"]
	hero.inventory[mat] = null
	var got := Items.reforge(it, game.rng)
	hero.recalc()
	game.burned(it)
	(burn_fire as Flames).flare = 1.0
	message("%s reforged with the %s: %s" % [it["name"], spent, got], Color(1.0, 0.8, 0.45))
	refresh()

func _burn(idx: int, it: Dictionary) -> void:
	if hero.inventory[idx] != it:
		return
	hero.inventory[idx] = null
	game.burned(it)
	(burn_fire as Flames).flare = 1.0
	message("%s burns" % it["name"], Color(1.0, 0.6, 0.3))
	refresh()

## The fire in the bonfire's hearth: the firelight on the recess, a shader fire (noise-driven tongues, dark red
## at the roots to white-gold at the heart), then in front the iron grate, the ring of hearth stones and embers
## drifting up. `flare` (set when something burns) makes it leap and brighten, then dies down.
class Flames extends Control:
	var flare := 0.0
	var _t := 0.0
	var _fire: ColorRect
	var _front: Control
	func _ready() -> void:
		_fire = ColorRect.new()
		_fire.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		# the simulated fire's flipbook (FireFx) when it is there: three flames played out of step, side by side
		var book := FireFx.book("body")
		sh.code = FIRE_FLIP_SHADER if book != null else FIRE_SHADER
		m.shader = sh
		if book != null:
			m.set_shader_parameter("flip_tex", book)
			m.set_shader_parameter("grid", FireFx.grid_of("body"))
		_fire.material = m
		add_child(_fire)
		_front = Control.new()
		_front.set_anchors_preset(Control.PRESET_FULL_RECT)
		_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_front.draw.connect(_draw_front)
		add_child(_front)
	func _process(delta: float) -> void:
		_t += delta
		flare = maxf(0.0, flare - delta * 1.2)
		if _fire:
			(_fire.material as ShaderMaterial).set_shader_parameter("flare", flare)
			_front.queue_redraw()
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Vector2(w * 0.5, h * 0.62)
		var flick := sin(_t * 7.0) * 0.004 + sin(_t * 11.3) * 0.003
		for k in 18:
			var r := w * (1.05 - k * 0.05) * (1.0 + flare * 0.2)
			draw_circle(c, r, Color(1.0, 0.36, 0.08, 0.012 + flare * 0.012 + flick))
	func _draw_front() -> void:
		var w := size.x
		var h := size.y
		var gy := h - 52.0
		# embers drifting up out of the fire
		for e in 26:
			var life := fmod(_t * (0.3 + fmod(e * 0.37, 0.3)) + e * 0.137, 1.0)
			var ex := w * 0.5 + sin(e * 12.9898) * w * 0.2 + sin(_t * 2.0 + e) * 10.0 * life
			var ey := gy - 10.0 - life * h * (0.7 + flare * 0.2)
			_front.draw_circle(Vector2(ex, ey), 1.7 * (1.0 - life) + 0.5, Color(1.0, 0.6 + 0.35 * (1.0 - life), 0.25, (1.0 - life) * 0.9))
		# the iron grate
		_front.draw_line(Vector2(w * 0.14, gy), Vector2(w * 0.86, gy), Color(0.09, 0.08, 0.075), 6.0)
		for b in 8:
			var bx := w * (0.18 + b * 0.094)
			_front.draw_line(Vector2(bx, gy - 2.0), Vector2(bx, gy + 16.0), Color(0.11, 0.1, 0.09), 3.0)
		_front.draw_line(Vector2(w * 0.14, gy - 3.0), Vector2(w * 0.86, gy - 3.0), Color(1.0, 0.5, 0.18, 0.55 + flare * 0.4), 1.0)
		# the ring of hearth stones, lit from the fire above
		var stones := 9
		for k in stones:
			var f := (float(k) + 0.5) / stones
			var cx := w * (0.05 + f * 0.9)
			var cy := h - 22.0 - absf(f - 0.5) * 12.0
			var rw := w * 0.058 + sin(k * 7.1) * 3.0
			var rh := 15.0 + cos(k * 3.3) * 3.0
			var pts := PackedVector2Array()
			for q in 12:
				var aq := TAU * q / 12.0
				pts.append(Vector2(cx + cos(aq) * rw * (1.0 + sin(aq * 3.0 + k) * 0.08), cy + sin(aq) * rh))
			var lit := 0.55 + 0.45 * (1.0 - absf(f - 0.5) * 2.0)
			_front.draw_colored_polygon(pts, Color(0.19, 0.17, 0.155) * lit)
			_front.draw_arc(Vector2(cx, cy + 2.0), rw * 0.9, PI * 1.15, PI * 1.85, 8, Color(1.0, 0.5, 0.2, 0.35 * lit + flare * 0.3), 2.0)

## The bonfire window's fire from the simulated flipbook: a tall flame in the middle and two smaller ones either
## side, each at its own speed and frame, the side ones mirrored; all light (added), brighter on a flare.
const FIRE_FLIP_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform sampler2D flip_tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(6.0, 6.0);
uniform float flare = 0.0;
vec3 frame_at(float f, vec2 uv) {
	float n = grid.x * grid.y;
	f = mod(f, n);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	return texture(flip_tex, (cell + clamp(uv, vec2(0.002), vec2(0.998))) / grid).rgb;
}
vec3 flame(vec2 uv, vec2 at, vec2 sz, float speed, float off, bool flip) {
	vec2 u = (uv - at) / sz + vec2(0.5, 1.0);
	if (u.x < 0.0 || u.x > 1.0 || u.y < 0.0 || u.y > 1.0) { return vec3(0.0); }
	if (flip) { u.x = 1.0 - u.x; }
	float f = TIME * 30.0 * speed + off;
	float f0 = floor(f);
	return mix(frame_at(f0, u), frame_at(f0 + 1.0, u), f - f0);
}
void fragment() {
	vec2 uv = UV;
	float grow = 1.0 + flare * 0.3;
	vec3 c = flame(uv, vec2(0.5, 0.86), vec2(0.62, 1.05) * grow, 1.0, 0.0, false);
	c += flame(uv, vec2(0.33, 0.87), vec2(0.42, 0.72) * grow, 0.86, 11.0, true) * 0.75;
	c += flame(uv, vec2(0.67, 0.87), vec2(0.4, 0.68) * grow, 1.12, 23.0, false) * 0.7;
	c *= 1.05 + flare * 0.5;
	COLOR = vec4(c, 1.0);
}
"""

const FIRE_SHADER := """
shader_type canvas_item;
uniform float flare = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float y = (uv.y - 0.2) / (0.66 + flare * 0.3);
	float n = fbm(vec2(uv.x * 4.0, uv.y * 3.2 - TIME * 2.1));
	float n2 = fbm(vec2(uv.x * 9.0 + 3.0, uv.y * 6.0 - TIME * 3.4));
	// the flames lick sideways more the higher they reach, and split into tongues
	float x = (uv.x - 0.5) * 2.0 + (n - 0.5) * 0.7 * max(y, 0.0);
	float tongues = 0.25 * sin(x * 9.0 + n2 * 4.0 - TIME * 1.5) * max(y, 0.0);
	float shape = 1.0 - abs(x) * (1.5 + max(y, 0.0) * 1.1) - y * 0.95 + tongues;
	float f = clamp((shape + n * 1.1 + n2 * 0.6 - 0.8) * 2.0, 0.0, 1.0);
	f *= smoothstep(-0.08, 0.04, y);
	vec3 c = mix(vec3(0.45, 0.04, 0.0), vec3(1.0, 0.42, 0.05), smoothstep(0.0, 0.45, f));
	c = mix(c, vec3(1.0, 0.86, 0.5), smoothstep(0.62, 1.0, f));
	COLOR = vec4(c * (1.15 + flare * 0.4), smoothstep(0.03, 0.3, f));
}
"""

## The waypoint window lives in WaypointPanel (scripts/waypoint_panel.gd); its acts and waypoints in
## Data.WAYPOINT_ACTS.
func _build_waypoints() -> void:
	var wp := WaypointPanel.new()
	windows.add_child(wp)
	wp.setup(self)
	wp_panel = wp

## Opened from a waypoint stone (`stone`): walking away from it, or clicking outside the window, closes it.
func open_waypoints(stone: Node3D = null) -> void:
	(wp_panel as WaypointPanel).open(stone)
	if stone:
		for g in stone.get_children():
			if g is WaypointGrand:
				(g as WaypointGrand).pulse()   # the grand waypoint flares as it wakes

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
	# co-op through Steam: open this world to Steam friends and invite them (SteamLink; only with Steam running, in
	# your own game, not in a raid or a match)
	invite_btn = _iron_button("Invite Friends", 320, 44, 19)
	invite_btn.name = "invite_friends"
	invite_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	invite_btn.pressed.connect(func():
		game.toggle_pause()
		game.steam.invite())
	vb.add_child(invite_btn)
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
	# the camp's hour (DayNight): jump to a time, drag to any hour, hold it or run it fast, or back to the shared clock
	var tod := VBoxContainer.new()
	tod.add_theme_constant_override("separation", 4)
	var tl := _label("", 14, Color(0.75, 0.82, 1.0))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tod.add_child(tl)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	for at in [[6.3, "Dawn"], [13.0, "Noon"], [19.3, "Dusk"], [0.0, "Midnight"]]:
		var h: float = at[0]
		var tb := _iron_button(at[1], 83, 34, 14)
		tb.pressed.connect(func(): game.day_night.set_hour(h, 0.0 if game.day_night.fixed < 0.0 else -1.0))
		trow.add_child(tb)
	tod.add_child(trow)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 24.0
	slider.step = 0.25
	slider.custom_minimum_size = Vector2(340, 22)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float): game.day_night.set_hour(v, 0.0 if game.day_night.fixed < 0.0 else -1.0))
	tod.add_child(slider)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 4)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	for pc in [[0.0, "Hold"], [1.0, "Run"], [30.0, "Fast 30x"], [-1.0, "Live clock"]]:
		var p: float = pc[0]
		var pb := _iron_button(pc[1], 83, 34, 14)
		pb.pressed.connect(func():
			var dn: DayNight = game.day_night
			if p < 0.0:
				dn.live()
			else:
				dn.set_hour(dn.hour, p))
		prow.add_child(pb)
	tod.add_child(prow)
	var nb := _iron_button("Next night's sounds", 340, 32, 14)
	nb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	nb.pressed.connect(func(): game.day_night.next_night_bed())
	tod.add_child(nb)
	vb.add_child(tod)
	var tick := Timer.new()             # the hour runs on under the pause menu: keep the label and slider with it
	tick.wait_time = 0.2
	tick.process_mode = Node.PROCESS_MODE_ALWAYS
	tick.timeout.connect(func():
		var dn: DayNight = game.day_night
		if not vb.visible or dn == null:
			return
		var h := dn.clock()
		var mode := "live clock (everyone's)" if dn.fixed < 0.0 else ("held, your screen only" if dn.pace <= 0.0 else "running %sx, your screen only" % str(snappedf(dn.pace, 0.1)))
		var beds: int = (Sfx.bank.get("night_forest", []) as Array).size()
		tl.text = "Time of day  %02d:%02d  ·  %s\nnight sounds %d of %d%s" % [int(h), int(fmod(h, 1.0) * 60.0), mode, dn.night_take() + 1, beds, "" if dn.on else "  (the Act I camp only)"]
		if not slider.has_focus() or dn.pace > 0.0 or dn.fixed < 0.0:
			slider.set_value_no_signal(h))
	tick.autostart = true
	vb.add_child(tick)
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

## The shade under the co-op and Battlegrounds screens (the title shows dimmed behind them, and can't be clicked).
func _sync_menu_shade() -> void:
	if menu_shade == null:
		menu_shade = ColorRect.new()
		menu_shade.name = "menu_shade"
		menu_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_shade.color = Color(0.0, 0.0, 0.0, 0.55)
		menu_shade.mouse_filter = Control.MOUSE_FILTER_STOP
		menus.add_child(menu_shade)
		menus.move_child(menu_shade, title_panel.get_index() + 1)
	menu_shade.visible = join_panel != null and join_panel.visible

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
var _title_cards := {}          # "continue"/"new" -> Button (the choice cards)
var _title_fade: ColorRect
var _title_busy := false        # a choice is under way: ignore more clicks

## The title screen: the Gate of the Ashen Crown (TitleStage, its own 3D world) with the two choices as cards
## under their daises: Continue (the last character played, shown on the left dais in their gear) and Create
## New Character (the empty dais, into the class picker). Characters, co-op, settings and Quit sit in a row below.
func _build_title() -> void:
	title_panel = Control.new()
	title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menus.add_child(title_panel)
	title_stage = TitleStage.new()
	title_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_panel.add_child(title_stage)
	title_stage.setup(game)
	title_stage.hovering.connect(_title_hover)
	title_stage.clicked.connect(_title_choose)
	# while the class picker or the character list covers it, the stage stops drawing
	title_stage.covered = func() -> bool: return (class_panel != null and class_panel.visible) or (chars_panel != null and chars_panel.visible)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ vec2 d = (UV - vec2(0.5, 0.48)) * vec2(1.1, 1.0); float v = smoothstep(0.35, 0.95, length(d) * 1.25); float top = smoothstep(0.32, 0.0, UV.y) * 0.45; float bot = smoothstep(0.7, 1.0, UV.y) * 0.55; COLOR = vec4(0.0, 0.0, 0.0, clamp(v * 0.75 + top + bot, 0.0, 0.9)); }"
	sm.shader = sh
	shade.material = sm
	title_panel.add_child(shade)
	# the name, high over the gate
	var head := VBoxContainer.new()
	head.name = "title_head"
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 34
	head.offset_left = TitleHome.EDGE                        # (centred in the room left of the character
	head.offset_right = -TitleHome.W - TitleHome.EDGE        # sidebar, like the buttons)
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(head)
	var t := _label("ASHEN CROWN", 84, Color(0.92, 0.74, 0.44), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01, 0.95))
	t.add_theme_color_override("font_shadow_color", Color(1.0, 0.45, 0.15, 0.35))
	t.add_theme_constant_override("shadow_outline_size", 22)
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	head.add_child(t)
	var orn := _label("—  ✦  —", 18, Color(0.7, 0.55, 0.32), true)
	orn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(orn)
	var st := _label("ACT I  ·  THE ASHEN MOORS", 18, Color(0.78, 0.72, 0.62), true)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(st)
	# the two choices
	var cont := _title_card("continue", WARM_CARD)
	cont.pressed.connect(func(): _title_choose("continue"))
	var ng := _title_card("newchar", COLD_CARD)
	ng.pressed.connect(func(): _title_choose("new"))
	_title_cards = {"continue": cont, "new": ng}
	title_stage.cards = _title_cards
	(ng.find_child("kicker", true, false) as Label).text = "A NEW LEGEND"
	(ng.find_child("big", true, false) as Label).text = "Create New Character"
	(ng.find_child("line", true, false) as Label).text = "Choose a class and forge your hero"
	(ng.find_child("ago", true, false) as Label).text = ""
	# the rest, in a row along the bottom
	var row := HBoxContainer.new()
	row.name = "title_row"
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -18
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	title_panel.add_child(row)
	var chb := _iron_button("Characters", 170, 38, 15)
	chb.name = "characters"
	chb.pressed.connect(func(): open_characters())
	row.add_child(chb)
	var hb := _iron_button("Host Co-op", 150, 38, 15)
	hb.name = "host"
	hb.pressed.connect(func(): game.start_host())
	row.add_child(hb)
	var jb := _iron_button("Join Co-op", 150, 38, 15)
	jb.name = "join"
	jb.pressed.connect(func(): open_join())
	row.add_child(jb)
	var bgb := _iron_button("Battlegrounds", 170, 38, 15)
	bgb.name = "battlegrounds"
	bgb.pressed.connect(func(): open_battlegrounds())
	row.add_child(bgb)
	var q := _iron_button("Quit", 110, 38, 15)
	q.pressed.connect(func(): get_tree().quit())
	row.add_child(q)
	if BuildEnv.env() != "local" and BuildEnv.env() != "production":
		# which backend this build uses, so a staging build is never mistaken for the live game
		var envl := _label(BuildEnv.env().to_upper() + " BUILD", 14, Color(1.0, 0.55, 0.3))
		envl.name = "env_badge"
		envl.position = Vector2(14, 10)
		title_panel.add_child(envl)
	# the build, tiny in the corner, so a screenshot shows at once whether a copy is out of date
	var rev := _label("%s · %s" % [BuildEnv.env(), BuildEnv.value("rev")], 11, Color(0.5, 0.47, 0.42, 0.7))
	rev.name = "build_rev"
	# (bottom left: the bottom right is the character sidebar's frame)
	rev.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rev.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rev.offset_left = TitleHome.EDGE + 4
	rev.offset_bottom = -4
	title_panel.add_child(rev)
	var slots := _label("", 13, Color(0.62, 0.58, 0.5))
	slots.name = "slots"
	slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slots.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	slots.offset_top = -86
	slots.offset_bottom = -66
	title_panel.add_child(slots)
	if OS.has_feature("web"):
		# browsers can't use the LAN co-op networking, and there's nothing to quit to
		hb.visible = false
		jb.visible = false
		bgb.visible = false
		q.visible = false
	# the controls, WoW-style (title_home.gd): they replace the two cards and the row of buttons, kept hidden for the
	# title's own API (_title_choose, the cards' state)
	cont.visible = false
	ng.visible = false
	row.visible = false
	slots.visible = false
	home = TitleHome.new()
	title_panel.add_child(home)
	home.setup(self)
	# a fade for the move into a choice (under the picker and the list, which are built on top)
	_title_fade = ColorRect.new()
	_title_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_fade.color = Color(0, 0, 0, 0)
	_title_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(_title_fade)
	_build_class_picker()
	_build_characters()

const WARM_CARD := Color(0.95, 0.68, 0.36)
const COLD_CARD := Color(0.58, 0.8, 1.0)

## A choice card: a dark glass plate edged in its colour, with a kicker, a big line, a detail line and a
## last-played line (filled by show_title). The whole card is the button.
func _title_card(nm: String, col: Color) -> Button:
	var b := Button.new()
	b.name = nm
	b.custom_minimum_size = Vector2(420, 116)
	b.size = Vector2(420, 116)
	b.focus_mode = Control.FOCUS_ALL
	b.pivot_offset = Vector2(210, 58)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var lit: bool = s == "hover" or s == "focus" or s == "pressed"
		sb.bg_color = Color(0.03, 0.025, 0.025, 0.78 if not lit else 0.86)
		sb.border_color = Color(col.r, col.g, col.b, 0.95 if lit else (0.25 if s == "disabled" else 0.55))
		sb.set_border_width_all(2 if lit else 1)
		sb.border_width_top = 3 if lit else 2
		sb.set_corner_radius_all(3)
		sb.shadow_color = Color(col.r, col.g, col.b, 0.35 if lit else 0.0)
		sb.shadow_size = 18 if lit else 0
		sb.set_content_margin_all(14)
		b.add_theme_stylebox_override(s, sb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 18
	vb.offset_right = -18
	vb.offset_top = 12
	vb.offset_bottom = -10
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var k := _label("", 13, col, true)
	k.name = "kicker"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(k)
	var big := _label("", 28, Color(0.97, 0.9, 0.78), true)
	big.name = "big"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	big.add_theme_constant_override("outline_size", 6)
	vb.add_child(big)
	var line := _label("", 16, Color(0.82, 0.77, 0.68))
	line.name = "line"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(line)
	var ago := _label("", 13, Color(0.6, 0.56, 0.5))
	ago.name = "ago"
	ago.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ago)
	b.mouse_entered.connect(func(): if not b.disabled: title_stage.set_focus("continue" if nm == "continue" else "new"))
	b.mouse_exited.connect(func(): title_stage.set_focus(""))
	b.focus_entered.connect(func(): if not b.disabled: title_stage.set_focus("continue" if nm == "continue" else "new"))
	title_panel.add_child(b)
	return b

## The stage's hover (a dais or a card): the matching card lifts and the other settles.
func _title_hover(which: String) -> void:
	for side in _title_cards:
		var c: Button = _title_cards[side]
		var on: bool = side == which and not c.disabled
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2.ONE * (1.04 if on else 1.0), 0.18).set_trans(Tween.TRANS_SINE)
		# hovering the dais lights the card as if the mouse were on it
		if not c.has_meta("plain"):
			c.set_meta("plain", c.get_theme_stylebox("normal"))
		c.add_theme_stylebox_override("normal", c.get_theme_stylebox("hover") if on else c.get_meta("plain"))
	if which != "":
		Sfx.play("inv_click", -14.0, 0.8 if which == "continue" else 1.15)

## A choice made (card or dais): the camera moves into it, then Continue loads the character shown and
## New Character opens the class picker.
func _title_choose(which: String) -> void:
	if _title_busy or game._intro_playing or (game.lobby_client != null and game.lobby_client.panel.visible):
		return
	if which == "continue" and (_title_cards["continue"] as Button).disabled:
		return
	_title_busy = true
	Sfx.play("click")
	if which == "continue":
		Sfx.play("swing_heavy", -10.0, 0.8)
	else:
		Sfx.play("phase_in", -8.0, 1.0)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_title_fade, "color", Color(0, 0, 0, 1) if which == "continue" else Color(0.02, 0.03, 0.05, 1), 0.3)
	await title_stage.enter(which)
	if which == "continue":
		var id: String = str(title_stage.get_meta("char_id")) if title_stage.has_meta("char_id") else ""
		await game.start_game(true, "knight", id)
	else:
		open_class_picker()
	_title_fade.color = Color(0, 0, 0, 0)
	title_stage.reset()
	_title_busy = false

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
	join_panel.visibility_changed.connect(_sync_menu_shade)
	join_panel.visible = false
	menus.add_child(join_panel)
	join_panel.offset_left = -360
	join_panel.offset_right = 360
	join_panel.offset_top = -290
	join_panel.offset_bottom = 290
	_ornate(join_panel, 0.26, 18)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	join_panel.add_child(vb)
	var t := _label("JOIN A GAME", 32, GOLD, true)
	var tfv := FontVariation.new()
	tfv.base_font = font_title
	tfv.spacing_glyph = 5
	t.add_theme_font_override("font", tfv)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(_divider(30))
	vb.add_child(_label("Games on your network:", 16))
	var games_scroll := ScrollContainer.new()
	games_scroll.custom_minimum_size.y = 150
	games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(games_scroll)
	join_list = VBoxContainer.new()
	join_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_list.custom_minimum_size = Vector2(0, 150)
	join_list.add_theme_constant_override("separation", 6)
	games_scroll.add_child(join_list)
	join_hint = _label("Searching… ask the other player to choose LAN → Host LAN.", 14, Color(0.7, 0.66, 0.58))
	join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(join_hint)
	vb.add_child(_label("Or type the host's address (shown at the top left of their screen):", 14, Color(0.7, 0.66, 0.58)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	join_ip = LineEdit.new()
	join_ip.placeholder_text = "e.g. 192.168.1.23"
	join_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_ip.custom_minimum_size = Vector2(0, 46)
	join_ip.add_theme_font_size_override("font_size", 17)
	join_ip.add_theme_stylebox_override("normal", _box(Color(0.03, 0.028, 0.025, 0.95), Color(0.42, 0.33, 0.2), 1, 3, 10))
	join_ip.add_theme_stylebox_override("focus", _box(Color(0.04, 0.035, 0.03, 0.95), GOLD, 1, 3, 10))
	join_ip.text_submitted.connect(func(txt): _join_ip(txt))
	row.add_child(join_ip)
	var go := _iron_button("Join", 140, 46, 19)
	go.pressed.connect(func(): _join_ip(join_ip.text))
	row.add_child(go)
	var note := _label("Your selected character comes with you.", 13, Color(0.6, 0.57, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	var back := _iron_button("Back", 220, 46, 18)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.name = "join_back"
	back.pressed.connect(func():
		join_panel.visible = false
		game.net.stop_listening())
	vb.add_child(back)

	join_panel.minimum_size_changed.connect(_fit_join_panel.call_deferred)
	get_viewport().size_changed.connect(_fit_join_panel)
	_fit_join_panel.call_deferred()

func _fit_join_panel() -> void:
	# Wrapped labels can report a tall minimum before their first layout pass.
	# Refit the preferred frame when that minimum settles; do not retain the old height.
	join_panel.size = Vector2(760, 600)
	var available := get_viewport().get_visible_rect().size - Vector2(40, 40)
	var factor := minf(1.0, minf(available.x / join_panel.size.x, available.y / join_panel.size.y))
	join_panel.pivot_offset = join_panel.size * 0.5
	join_panel.scale = Vector2.ONE * factor
	join_panel.position = (get_viewport().get_visible_rect().size - join_panel.size) * 0.5

## The lobby browser's Battlegrounds.
func open_battlegrounds() -> void:
	if game.lobby_client != null:
		game.lobby_client.open("battlegrounds")

func open_join() -> void:
	Sfx.play("click")
	join_character_id = game.char_id if game.playing else (home.sel if home != null else "")
	join_panel.visible = true
	game.net.start_listening()
	_refresh_join()

func _join_ip(txt: String) -> void:
	txt = txt.strip_edges()
	if txt == "":
		return
	join_panel.visible = false
	game.start_join(txt, join_character_id)

func _refresh_join() -> void:
	for c in join_list.get_children():
		c.queue_free()
	var found: Dictionary = game.net.found
	for ip in found.keys():
		var b := _iron_button("%s's game  ·  %s  ·  %s" % [found[ip]["name"], found[ip]["zone"], ip], 600, 50, 17)
		var addr: String = ip
		b.pressed.connect(func(): _join_ip(addr))
		join_list.add_child(b)
	join_hint.visible = found.is_empty()

# ---------------------------------------------------------------- armor enchanting
func _build_enchant() -> void:
	ench_panel = _panel("Enchant Armor", true, 560, 600)
	var vb: VBoxContainer = ench_panel.get_node("vb")
	var intro := _label("Pay to bind runes into your worn armor. Each level adds %d%% defense and extra life. Up to +10." % int(round(Items.ENCHANT_DEF * 100)), 14, DIM)
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
	if furnace_ui != null:
		furnace_ui.visible = false
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
		top.add_child(sp)
		var a := TAU * i / 16.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sp, "position", sp.position + Vector2(cos(a), sin(a)) * 60.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "modulate:a", 0.0, 0.5).set_delay(0.15)
		tw.chain().tween_callback(sp.queue_free)

## New Game: choose a class. The heroes stand live on a torch-lit stage (ClassStage): idle they breathe and
## look about, under the mouse each fidgets, and the chosen one does its signature move. Below them, in the
## inventory's iron and bronze: the chosen class's name, story, skills and stats, the name field and Play.
var class_stage: ClassStage
var class_info: Control
var class_plates := {}
var class_arrows := {}              # -1 / 1 -> ClassArrow
## Over the New Character stage: darkens the hall softly behind the title at the top and behind the info panel at
## the bottom, and into the corners, so the cathedral runs to the screen's edges without fighting the text.
const STAGE_FADE_SHADER := """
shader_type canvas_item;
void fragment() {
	float top = 1.0 - smoothstep(0.02, 0.17, UV.y);
	float bottom = smoothstep(0.62, 0.86, UV.y);
	vec2 c = (UV - vec2(0.5, 0.42)) * vec2(1.25, 1.0);
	float edge = smoothstep(0.45, 0.85, length(c));
	float a = clamp(max(max(top * 0.82, bottom * 0.9), edge * 0.7), 0.0, 1.0);
	COLOR = vec4(0.03, 0.026, 0.024, a);
}
"""
var _class_sel := "knight"

func _build_class_picker() -> void:
	class_panel = Control.new()
	class_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	class_panel.visible = false
	title_panel.add_child(class_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dm := ShaderMaterial.new()
	var dsh := Shader.new()
	dsh.code = "shader_type canvas_item; void fragment(){ float v = length((UV - vec2(0.5, 0.38)) * vec2(1.3, 1.0)); COLOR = vec4(vec3(0.035, 0.03, 0.028) * (1.0 - v * 0.9), 1.0); }"
	dm.shader = dsh
	dim.material = dm
	class_panel.add_child(dim)
	var t := _label("Choose your path", 40, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 8)
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.offset_top = 26
	class_panel.add_child(t)
	var hint := _label("Turn with the arrows or the keys, click a hero to choose", 14, Color(0.62, 0.58, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 80
	class_panel.add_child(hint)
	# the stage: built when the picker opens, freed when it closes. It fills the screen behind the title and the
	# panel (ClassStage.band keeps the heroes between them), with soft dark fades so the text stays readable
	var holder := Control.new()
	holder.name = "stage_holder"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_panel.add_child(holder)
	class_panel.move_child(holder, dim.get_index() + 1)
	var fade := ColorRect.new()
	fade.name = "stage_fade"
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = STAGE_FADE_SHADER
	fm.shader = fsh
	fade.material = fm
	class_panel.add_child(fade)
	class_panel.move_child(fade, holder.get_index() + 1)
	# the chosen class, in the inventory's frame
	class_info = Control.new()
	class_info.anchor_left = 0.5
	class_info.anchor_right = 0.5
	class_info.anchor_top = 1.0
	class_info.anchor_bottom = 1.0
	class_info.offset_left = -560
	class_info.offset_right = 560
	class_info.offset_top = -270
	class_info.offset_bottom = -22
	class_panel.add_child(class_info)
	var iron := TextureRect.new()
	iron.texture = _scaled_tex(INV_TEX["iron"], 0.25)
	iron.stretch_mode = TextureRect.STRETCH_TILE
	iron.position = Vector2(28, 28)
	iron.size = Vector2(1064, 192)
	class_info.add_child(iron)
	var fr := NinePatchRect.new()
	fr.texture = _scaled_tex(INV_TEX["frame"], 0.18)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		fr.set_patch_margin(side, 61)
	fr.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.draw_center = false
	fr.size = Vector2(1120, 248)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_info.add_child(fr)
	var hb := HBoxContainer.new()
	hb.position = Vector2(66, 42)
	hb.size = Vector2(988, 168)
	hb.add_theme_constant_override("separation", 28)
	class_info.add_child(hb)
	# left: name, story, stats
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(380, 0)
	lv.add_theme_constant_override("separation", 6)
	hb.add_child(lv)
	var nm := _label("", 32, GOLD, true)
	nm.name = "cname"
	lv.add_child(nm)
	var ds := _label("", 14, Color(0.84, 0.8, 0.74))
	ds.name = "cdesc"
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(380, 0)
	lv.add_child(ds)
	var stl := _label("", 13, Color(0.78, 0.7, 0.55))
	stl.name = "cstats"
	lv.add_child(stl)
	# middle: the four skills in the action bar's sockets
	var mv := VBoxContainer.new()
	mv.custom_minimum_size = Vector2(300, 0)
	mv.add_theme_constant_override("separation", 6)
	hb.add_child(mv)
	mv.add_child(_label("Skills", 15, Color(0.8, 0.72, 0.58), true))
	var grid := GridContainer.new()
	grid.name = "cskills"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(grid)
	# right: the name and Play
	var rv := VBoxContainer.new()
	rv.custom_minimum_size = Vector2(250, 0)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 5)
	hb.add_child(rv)
	rv.add_child(_label("Name", 14, Color(0.8, 0.72, 0.58)))
	name_edit = LineEdit.new()
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(250, 36)
	name_edit.placeholder_text = "a name for your hero"
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.05, 0.045, 0.04, 0.95)
	le.border_color = Color(0.55, 0.43, 0.24)
	le.set_border_width_all(1)
	le.set_corner_radius_all(3)
	le.content_margin_left = 10
	name_edit.add_theme_stylebox_override("normal", le)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = GOLD
	name_edit.add_theme_stylebox_override("focus", lef)
	rv.add_child(name_edit)
	var note := _label("", 12, Color(0.7, 0.66, 0.58))
	note.name = "slotnote"
	note.custom_minimum_size = Vector2(250, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(note)
	var go := _iron_button("Play", 250, 46, 18)
	go.name = "cplay"
	go.pressed.connect(func():
		class_panel.visible = false
		_close_class_stage()
		game.start_game(false, _class_sel, "", name_edit.text))
	rv.add_child(go)
	var back := _iron_button("Back", 250, 34, 14)
	back.pressed.connect(func():
		Sfx.play("click")
		class_panel.visible = false
		_close_class_stage()
		# the whole title as it should be (its fade, camera, stage, music, the 3D switch), never half of it
		show_title())
	rv.add_child(back)
	_show_class("knight")
	get_viewport().size_changed.connect(_layout_class_info)
	_layout_class_info()

func _layout_class_info() -> void:
	var available := get_viewport().get_visible_rect().size
	var factor := minf(1.0, minf((available.x - 32.0) / 1120.0, available.y * 0.38 / 248.0))
	class_info.scale = Vector2.ONE * factor
	class_info.offset_left = -560.0 * factor
	class_info.offset_right = class_info.offset_left + 1120.0
	class_info.offset_top = -22.0 - 248.0 * factor
	class_info.offset_bottom = class_info.offset_top + 248.0

## Fills the info panel for a class (the chosen one, or the one under the mouse while it's there).
func _show_class(c: String) -> void:
	if class_stage != null:
		class_stage.stop_skill()      # the skill rows are rebuilt; a hovered one is gone
	var d: Dictionary = Data.CLASSES[c]
	var acc: Color = ClassStage.ACCENTS[c]
	var nm := class_info.find_child("cname", true, false) as Label
	nm.text = str(d["name"])
	nm.add_theme_color_override("font_color", acc)
	(class_info.find_child("cdesc", true, false) as Label).text = str(d["desc"])
	(class_info.find_child("cstats", true, false) as Label).text = "Strength %d   Dexterity %d   Vitality %d   Energy %d" % [d["str"], d["dex"], d["vit"], d["ene"]]
	var grid := class_info.find_child("cskills", true, false) as GridContainer
	for ch in grid.get_children():
		ch.queue_free()
	for sk in Data.skills_for(c):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sock := Panel.new()
		sock.custom_minimum_size = Vector2(46, 46)
		var sb := StyleBoxTexture.new()
		if _socket_tex == null:
			_socket_tex = _scaled_tex(BAR_TEX["slot"], 0.3)
		sb.texture = _socket_tex
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 9)
		sock.add_theme_stylebox_override("panel", sb)
		var g := SkillGlyph.new()
		g.id = sk["id"]
		g.position = Vector2(5, 5)
		g.size = Vector2(36, 36)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sock.add_child(g)
		sock.tooltip_text = str(sk["desc"])
		row.add_child(sock)
		var l := _label(str(sk["name"]), 13, Color(0.86, 0.82, 0.74))
		l.custom_minimum_size = Vector2(96, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		grid.add_child(row)
		# hover a skill and the hero shows it on the stage
		var sid: String = sk["id"]
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_entered.connect(func():
			if class_stage != null:
				class_stage.show_skill(c, sid))
		row.mouse_exited.connect(func():
			if class_stage != null:
				class_stage.show_skill(c, ""))
	(class_info.find_child("cplay", true, false) as Button).text = "Play as " + str(d["name"])
	for k in class_plates:
		var p: Label = class_plates[k]
		p.add_theme_color_override("font_color", ClassStage.ACCENTS[k] if k == c else Color(0.75, 0.7, 0.62))

func _open_class_stage() -> void:
	if class_stage != null:
		return
	var holder := class_panel.find_child("stage_holder", true, false) as Control
	class_stage = ClassStage.new()
	class_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(class_stage)
	class_stage.setup(game)
	class_stage.picked.connect(func(c: String):
		_class_sel = c
		_show_class(c))
	class_stage.hovering.connect(func(c: String): _show_class(c if c != "" else _class_sel))
	class_plates.clear()
	for c in ClassStage.CLASSES:
		var p := _label(str(Data.CLASSES[c]["name"]), 17, Color(0.75, 0.7, 0.62), true)
		p.add_theme_constant_override("outline_size", 6)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.size = Vector2(160, 26)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(p)
		class_plates[c] = p
	# the carousel's arrows at the stage's edges, level with the heroes
	for dir: int in [-1, 1]:
		var ar := ClassArrow.new()
		ar.setup(dir)
		ar.anchor_left = 0.0 if dir < 0 else 1.0
		ar.anchor_right = ar.anchor_left
		ar.anchor_top = 0.5
		ar.anchor_bottom = 0.5
		var w := ClassArrow.SIZE.x
		ar.offset_left = 48.0 if dir < 0 else -48.0 - w
		ar.offset_right = ar.offset_left + w
		ar.offset_top = -ClassArrow.SIZE.y * 0.5 - 36.0 - 83.0     # level with the heroes' band (ClassStage.band)
		ar.offset_bottom = ar.offset_top + ClassArrow.SIZE.y
		ar.turned.connect(func(d: int):
			if class_stage != null:
				class_stage.turn(d))
		holder.add_child(ar)
		class_arrows[dir] = ar
	class_stage.snap_to(_class_sel)
	_show_class(_class_sel)
	# the hero select has its own theme (back to the zone's when it closes)
	Sfx.play_music("select")

func _close_class_stage() -> void:
	if class_stage != null:
		class_stage.queue_free()
		class_stage = null
		game.zone_music()
	for c in class_plates:
		(class_plates[c] as Label).queue_free()
	class_plates.clear()
	for d in class_arrows:
		(class_arrows[d] as Control).queue_free()
	class_arrows.clear()

## Left/Right (or A/D) turn the carousel while the picker is open and nothing is being typed.
func _class_key(ev: InputEvent) -> bool:
	if class_stage == null or not class_panel.visible or not (ev is InputEventKey):
		return false
	var k := ev as InputEventKey
	if not k.pressed:
		return false
	if name_edit != null and name_edit.has_focus():
		return false
	var dir := 0
	if k.keycode == KEY_LEFT or k.keycode == KEY_A:
		dir = -1
	elif k.keycode == KEY_RIGHT or k.keycode == KEY_D:
		dir = 1
	if dir == 0:
		return false
	if not k.echo:
		var ar := class_arrows.get(dir) as ClassArrow
		if ar != null:
			ar.flash()
		class_stage.turn(dir)
	return true

## One of the carousel's two arrows (a Meshy-painted iron chevron with a gold gem): brightens, grows a
## little and its gem glows under the mouse; pressed it dips; a click turns the ring one way.
class ClassArrow extends Control:
	signal turned(dir: int)
	const SIZE := Vector2(150, 158)
	static var _tex: Texture2D
	static var _gem: Texture2D
	var dir := 1
	var art: TextureRect
	var gem: TextureRect
	var _hot := 0.0
	var _over := false
	var _down := false
	var _flash := 0.0

	func setup(d: int) -> void:
		dir = d
		if _tex == null:
			_tex = load("res://assets/textures/ui/arrow_left.png")
			_gem = load("res://assets/textures/ui/arrow_gem.png")
		custom_minimum_size = SIZE
		size = SIZE
		pivot_offset = SIZE * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Previous hero  (Left, A)" if d < 0 else "Next hero  (Right, D)"
		art = TextureRect.new()
		art.texture = _tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.flip_h = d > 0
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		gem = TextureRect.new()
		gem.texture = _gem
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.set_anchors_preset(Control.PRESET_FULL_RECT)
		gem.flip_h = d > 0
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gm := CanvasItemMaterial.new()
		gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gem.material = gm
		gem.modulate = Color(1, 1, 1, 0.0)
		add_child(gem)
		mouse_entered.connect(func(): _over = true)
		mouse_exited.connect(func():
			_over = false
			_down = false)
		_apply(0.0)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			accept_event()
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_down = true
					_flash = 1.0
					turned.emit(dir)
				else:
					_down = false
			elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT):
				turned.emit(-1)
			elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT):
				turned.emit(1)
		elif ev is InputEventMouseMotion:
			accept_event()

	## A key press lights the arrow for a moment as a click would.
	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		_hot = move_toward(_hot, 1.0 if _over else 0.0, delta * 7.0)
		_flash = maxf(_flash - delta * 3.0, 0.0)
		_apply(delta)

	func _apply(_delta: float) -> void:
		var glow := maxf(_hot, _flash)
		var k := 1.0 + 0.06 * _hot - (0.05 if _down else 0.0) + 0.03 * _flash
		scale = Vector2(k, k)
		art.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.18, 1.05), glow) * (0.9 if _down else 1.0)
		# the gem's light: a slow pulse at rest, blazing under the mouse
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 2.2 + dir)
		gem.modulate = Color(1, 1, 1, 0.1 + 0.12 * pulse + 0.75 * glow)

func open_class_picker() -> void:
	Sfx.play("click")
	chars_panel.visible = false
	name_edit.text = ""
	var n: int = game.list_characters().size()
	(class_panel.find_child("slotnote", true, false) as Label).text = "" if n == 0 \
		else "A new save. Your other %s kept." % ("character is" if n == 1 else "%d are" % n)
	class_panel.visible = true
	_open_class_stage()

func show_title() -> void:
	title_panel.visible = true
	if class_panel:
		class_panel.visible = false
		_close_class_stage()
	if chars_panel:
		chars_panel.visible = false
	var chars: Array = game.list_characters()
	var cont := _title_cards["continue"] as Button
	cont.disabled = chars.is_empty()
	cont.mouse_default_cursor_shape = Control.CURSOR_ARROW if chars.is_empty() else Control.CURSOR_POINTING_HAND
	var kick := cont.find_child("kicker", true, false) as Label
	var big := cont.find_child("big", true, false) as Label
	var line := cont.find_child("line", true, false) as Label
	var ago := cont.find_child("ago", true, false) as Label
	if chars.is_empty():
		kick.text = "CONTINUE"
		big.text = "No hero yet"
		line.text = "Your first character will wait for you here"
		ago.text = ""
		big.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
		title_stage.show_character({})
		title_stage.remove_meta("char_id")
	else:
		var c: Dictionary = chars[0]
		kick.text = "CONTINUE YOUR LEGEND"
		big.text = str(c["name"]) if str(c["name"]) != "" else "Unnamed"
		big.add_theme_color_override("font_color", Color(0.97, 0.9, 0.78))
		line.text = "Level %d %s" % [int(c["level"]), Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]]
		var a := _ago(int(c["played"]))
		ago.text = "Last played " + a if a != "" else ""
		# the figure on the dais and the save Continue loads are the same one
		title_stage.set_meta("char_id", str(c["id"]))
		title_stage.show_character(game.character_gear(str(c["id"])))
	var chb := title_panel.find_child("characters", true, false) as Button
	chb.visible = not chars.is_empty()
	chb.text = "Characters  ·  %d" % chars.size()
	var ng := _title_cards["new"] as Button
	(ng.find_child("kicker", true, false) as Label).text = "BEGIN YOUR LEGEND" if chars.is_empty() else "A NEW LEGEND"
	(title_panel.find_child("slots", true, false) as Label).text = "" if chars.is_empty() \
		else "Every character has its own save. Making a new one never overwrites the others."
	title_stage.reset()
	home.refresh(chars)
	_title_hover("")
	_title_fade.color = Color(0, 0, 0, 0)
	_title_busy = false
	# the home screen is the multiplayer page (Blaine, 2026-11-06): no title, Enter World or characters; the 3D stage
	# stays as its backdrop (the lobby's class preview stands on it)
	for c in title_panel.get_children():
		if c != title_stage and not str(c.name) in ["build_rev", "env_badge"]:
			(c as CanvasItem).visible = false
	if game.lobby_client != null:
		game.lobby_client.open("battlegrounds")
	# the camp keeps building behind; it isn't drawn while the title's own world is up
	get_viewport().disable_3d = true
	game.zone_music()
	_set_hud(false)

## "2 hours ago" from a save's `played` (unix ms); "" when unknown.
func _ago(ms: int) -> String:
	if ms <= 0:
		return ""
	var s := int(Time.get_unix_time_from_system()) - ms / 1000
	if s < 60:
		return "just now"
	for u in [[86400, "day"], [3600, "hour"], [60, "minute"]]:
		if s >= int(u[0]):
			var k := s / int(u[0])
			return "%d %s%s ago" % [k, u[1], "" if k == 1 else "s"]
	return ""

func _char_line(c: Dictionary) -> String:
	var nm: String = c["name"] if str(c["name"]) != "" else "Unnamed"
	return "%s, level %d %s" % [nm, int(c["level"]), Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]]

## The saved characters: play one, delete one (asks twice), or make a new one.
## The Characters screen (the title's list of saves): the game's own frame (Blaine: "no plain boxes"), a card per
## character in its class's colour (ClassStage.ACCENTS: a lit edge, the name, level, class and act, when last played)
## with iron Play / Delete (Delete asks once), and New Character / Back below.
func _build_characters() -> void:
	chars_panel = Control.new()
	chars_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	chars_panel.visible = false
	title_panel.add_child(chars_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.015, 0.82)
	chars_panel.add_child(dim)
	var frame := PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -430
	frame.offset_right = 430
	frame.offset_top = -330
	frame.offset_bottom = 330
	_ornate(frame, 0.3, 26)
	chars_panel.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	frame.add_child(vb)
	var t := _label("CHARACTERS", 34, GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var dv := _divider(26)
	dv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(dv)
	chars_sub = _label("", 15, Color(0.75, 0.7, 0.62))
	chars_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(chars_sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	chars_list = VBoxContainer.new()
	chars_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chars_list.add_theme_constant_override("separation", 10)
	sc.add_child(chars_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	var nb := _iron_button("New Character", 220, 46, 17)
	nb.pressed.connect(func(): open_class_picker())
	row.add_child(nb)
	var back := _iron_button("Back", 160, 46, 17)
	back.pressed.connect(func(): chars_panel.visible = false)
	row.add_child(back)

func open_characters() -> void:
	Sfx.play("click")
	for c in chars_list.get_children():
		c.queue_free()
	var all: Array = game.list_characters()
	chars_sub.text = "%d saved, each with its own save. Play any of them, or make a new one." % all.size()
	var first := true
	for c in all:
		var acc: Color = ClassStage.ACCENTS.get(c["cls"], GOLD)
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.045, 0.04, 0.04, 0.92)
		sb.border_color = acc.darkened(0.35) if not first else acc
		sb.border_width_left = 5
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_width_right = 1
		sb.corner_radius_top_left = 3
		sb.corner_radius_bottom_left = 3
		sb.content_margin_left = 18
		sb.content_margin_right = 12
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.shadow_color = Color(acc.r, acc.g, acc.b, 0.22 if first else 0.0)
		sb.shadow_size = 8
		card.add_theme_stylebox_override("panel", sb)
		chars_list.add_child(card)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		card.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		hb.add_child(info)
		info.add_child(_label(str(c["name"]) if str(c["name"]) != "" else "Unnamed", 24, acc, true))
		info.add_child(_label("Level %d %s" % [int(c["level"]), Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]], 15, Color(0.82, 0.76, 0.66)))
		var when := _ago(int(c["played"]))
		info.add_child(_label(("Last played  ·  " if first else "Played ") + when if when != "" else "", 12, GOLD if first else Color(0.6, 0.57, 0.5)))
		first = false
		var id: String = c["id"]
		var play := _iron_button("Play", 120, 44, 17)
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(func():
			chars_panel.visible = false
			game.start_game(true, "knight", id))
		hb.add_child(play)
		var del := _iron_button("Delete", 110, 44, 15)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del.add_theme_color_override("font_color", Color(0.85, 0.5, 0.42))
		del.pressed.connect(func():
			if del.text == "Delete":
				del.text = "Sure?"
				del.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
				return
			game.delete_character(id)
			open_characters()
			show_title()
			chars_panel.visible = not game.list_characters().is_empty())
		hb.add_child(del)
	chars_panel.visible = true

func hide_title() -> void:
	title_panel.visible = false
	join_panel.visible = false
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
	if _class_key(ev):
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- updates
func toggle(panel: Control) -> void:
	panel.visible = not panel.visible
	if not panel.visible:
		tooltip.visible = false
	if panel == inv_panel and not panel.visible:
		shop_panel.visible = false
		stash_panel.visible = false
		burn_panel.visible = false
		shop_mode = ""
	Sfx.play("click")
	refresh()

## Walking away from the trader (or the stash) closes their windows, as stepping off from a stall would.
func _walked_off() -> void:
	if trade_with == null:
		return
	var open := shop_panel.visible or stash_panel.visible or burn_panel.visible or furnace_ui.visible or dialog_panel.visible or ench_panel.visible
	if not open or not is_instance_valid(trade_with) or hero == null:
		trade_with = null
		return
	var d: Vector3 = hero.global_position - trade_with.global_position
	if Vector2(d.x, d.z).length() > trade_with.radius + 3.0:
		trade_with = null
		for p in [shop_panel, stash_panel, burn_panel, furnace_ui, dialog_panel, ench_panel, inv_panel]:
			p.visible = false
		shop_mode = ""
		tooltip.visible = false

func close_all() -> bool:
	var any := close_skill_picker()
	if run_ui != null and run_ui.close():
		any = true
	if game.lobby_client != null and game.lobby_client.panel.visible:
		game.lobby_client.panel.hide()
		any = true
	for p in [inv_panel, char_panel, shop_panel, stash_panel, burn_panel, furnace_ui, wp_panel, dialog_panel, ench_panel, skills_panel, talent_panel, quest_panel, auction_panel]:
		if p.visible:
			p.visible = false
			any = true
	shop_mode = ""
	tooltip.visible = false
	return any

## The title with nothing open over it (no class picker, character list, co-op or Battlegrounds screen).
func title_idle() -> bool:
	return title_panel.visible and not (class_panel != null and class_panel.visible) and not (chars_panel != null and chars_panel.visible) \
		and not join_panel.visible and not (game.lobby_client != null and game.lobby_client.panel.visible)

func any_panel_open() -> bool:
	return (run_ui != null and run_ui.visible) or (game.lobby_client != null and game.lobby_client.panel.visible) or inv_panel.visible or char_panel.visible or shop_panel.visible or stash_panel.visible or burn_panel.visible or furnace_ui.visible or wp_panel.visible or dialog_panel.visible or ench_panel.visible or skills_panel.visible or talent_panel.visible or quest_panel.visible or auction_panel.visible

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
	_fill_tracker()

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
	_refresh_enchant()
	if shop_panel.visible:
		_refresh_shop()
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
	if stash_panel.visible and game.stash != null:
		var tab: Array = game.stash.tabs[stash_tab]
		for i in SharedStash.SLOTS:
			_set_slot(stash_cells[i], tab[i])
		for t in stash_tab_row.get_children():
			t.queue_redraw()
		stash_count_lbl.text = "Tab %s: %d / %d    ·    All tabs: %d / %d" % [STASH_NUMERALS[stash_tab], game.stash.tab_count(stash_tab), SharedStash.SLOTS, game.stash.count(), SharedStash.SLOTS * SharedStash.TABS]
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
	_walked_off()
	if class_stage != null and class_stage.is_visible_in_tree():
		# the nameplates sit just under each hero's feet, fading with the hero into the gloom
		for c in class_plates:
			var p: Label = class_plates[c]
			var a: float = class_stage.plate_alpha(c)
			p.visible = a > 0.02
			p.modulate = Color(1, 1, 1, a)
			p.position = class_stage.feet_at(c) + Vector2(-80, 8 + 10 * float(class_stage.scales[c]))
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
	quest_tracker.visible = game.hero.run == null and not game.bg_mode and not game.arena_mode and game.sandbox == null
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
