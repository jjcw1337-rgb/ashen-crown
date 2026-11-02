class_name TitleHome
extends Control
## The title's controls, WoW-style (Blaine, 2026-11-01): the gate scene (TitleStage) stays the picture; over it
##  - a right sidebar of your characters (name, level and class, act, last played): click one to stand it on the dais;
##    delete on its card (asks first); "Create New Character" at the bottom of the list
##  - bottom centre, how to play it: Story · Battlegrounds · Online Co-op · LAN, and one big Play (LAN: Host / Join);
##    Battlegrounds says in one line what death costs there, and counts down when a raid turned us away
##  - bottom left: the Battlegrounds' card (its key art; opens its own page, BgPage), and Quit
## Panels are UI._ornate (the inventory's iron and gold frame), buttons UI._iron_button: no plain boxes (Blaine).
## Play hands the chosen character to the game: Story = UI._title_choose("continue") on it, Battlegrounds =
## Game.start_battlegrounds (after one confirm), Online Co-op = Game.start_join on the co-op server, LAN = host or
## the join screen. UI keeps the old cards (hidden) so its title API and tests stay as they were.

const W := 420.0                 # the sidebar's width
const MODES := [["story", "Story"], ["online", "Online Co-op"], ["lan", "LAN"]]
const NOTE := {"story": "Your journey through the acts, alone.",
	"online": "Play the story together, on the co-op server.", "lan": "Host a game, or join one on your network."}

var ui
var game
var sel := ""                    # the chosen character's id
var mode := "story"
var _list: VBoxContainer
var _count: Label
var _modes := {}
var _play: Button
var _join: Button
var _note: Label
var _status: Label
var _bg_card: Button
var _bg_art: TextureRect
var _bg_t := 0.0
var _bg_hot := 0.0

func setup(u) -> void:
	ui = u
	game = u.game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_sidebar()
	_build_play()
	_build_bg_card()
	var quit: Button = ui._iron_button("Quit Game", 200, 52, 19)
	quit.name = "quit"
	quit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	quit.offset_top = -80
	quit.offset_bottom = -28
	quit.offset_left = 40
	quit.offset_right = 240
	quit.pressed.connect(func(): get_tree().quit())
	quit.visible = not OS.has_feature("web")
	add_child(quit)

func _build_sidebar() -> void:
	var side := PanelContainer.new()
	side.name = "sidebar"
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -W - 18
	side.offset_right = -18
	side.offset_top = 18
	side.offset_bottom = -18
	ui._ornate(side, 0.2, 8)
	add_child(side)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	side.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t: Label = ui._label("CHARACTERS", 22, ui.GOLD, true)
	var tf := FontVariation.new()
	tf.base_font = ui.font_title
	tf.spacing_glyph = 3
	t.add_theme_font_override("font", tf)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count = ui._label("", 14, ui.DIM)
	head.add_child(_count)
	var rule := TextureRect.new()
	rule.texture = load("res://assets/textures/ui/sheet_divider.png")
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule.custom_minimum_size = Vector2(0, 30)
	vb.add_child(rule)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	var make: Button = ui._iron_button("Create New Character", int(W - 96), 54, 19)
	make.name = "create"
	make.pressed.connect(func(): ui._title_choose("new"))
	vb.add_child(make)

func _build_play() -> void:
	var box := VBoxContainer.new()
	box.name = "play_box"
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -26
	# centred in the room the sidebar leaves
	box.offset_left = -W * 0.5 - 270
	box.offset_right = -W * 0.5 + 270
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_status = ui._label("", 15, Color(0.6, 0.85, 1.0), true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for m in MODES:
		if m[0] == "online" and BuildEnv.env() == "local":
			continue           # (the co-op server is the staging/production builds')
		if m[0] in ["bg", "lan"] and OS.has_feature("web"):
			continue           # (no raw UDP in a browser)
		var b: Button = ui._iron_button(m[1], 160, 42, 17)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color(0.72, 0.64, 0.5))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.55))
		b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.92, 0.65))
		# the chosen one lit gold (the socket brightened), the others dim iron
		var on := (b.get_theme_stylebox("pressed") as StyleBoxTexture).duplicate() as StyleBoxTexture
		on.modulate_color = Color(1.45, 1.22, 0.82)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		var id: String = m[0]
		b.pressed.connect(func(): set_mode(id))
		row.add_child(b)
		_modes[id] = b
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", 10)
	box.add_child(prow)
	_play = ui._iron_button("Play", 360, 68, 30)
	_play.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_play.add_theme_constant_override("outline_size", 6)
	_play.name = "play"
	_play.pressed.connect(play)
	prow.add_child(_play)
	_join = ui._iron_button("Join", 160, 68, 24)
	_join.pressed.connect(func(): ui.open_join())
	_join.visible = false
	prow.add_child(_join)
	_note = ui._label("", 16, Color(0.78, 0.72, 0.64))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	set_mode("story")

## The characters into the sidebar (newest first, as Game.list_characters gives them), keeping the choice.
func refresh(chars: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_count.text = str(chars.size()) if not chars.is_empty() else ""
	if chars.filter(func(c): return str(c["id"]) == sel).is_empty():
		sel = str(chars[0]["id"]) if not chars.is_empty() else ""
	for c in chars:
		_list.add_child(_card(c))
	if chars.is_empty():
		var e: Label = ui._label("No characters yet.\nCreate one to begin.", 15, ui.DIM)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(e)
	select(sel)

func _card(c: Dictionary) -> Control:
	var id := str(c["id"])
	var b := Button.new()
	b.name = "char_" + id
	b.custom_minimum_size = Vector2(W - 96, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("id", id)
	var mine := id == sel
	b.add_theme_stylebox_override("normal", _card_box(false))
	b.add_theme_stylebox_override("hover", _card_box(true))
	b.add_theme_stylebox_override("pressed", _card_box(true))
	b.pressed.connect(func(): select(id))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 20
	vb.offset_top = 9
	vb.offset_right = -40
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var nm: Label = ui._label(str(c["name"]) if str(c["name"]) != "" else "Unnamed", 20, Color(0.97, 0.9, 0.78), true)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var cls: String = Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]
	var acc: Color = ClassStage.ACCENTS.get(str(c["cls"]), ui.GOLD)
	var strip := ColorRect.new()
	strip.color = acc
	strip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	strip.offset_left = 4
	strip.offset_right = 8
	strip.offset_top = 6
	strip.offset_bottom = -6
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(strip)
	var l1: Label = ui._label("Level %d %s" % [int(c["level"]), cls], 15, acc.lerp(Color(0.9, 0.85, 0.75), 0.35))
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l1)
	var ago: String = ui._ago(int(c["played"]))
	var l2: Label = ui._label(["Act I", "Act II", "Act III"][clampi(int(c["difficulty"]), 0, 2)] + ("  ·  " + ago if ago != "" else ""), 12, ui.DIM)
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l2)
	var del := Button.new()
	del.text = "✕"
	del.flat = true
	del.tooltip_text = "Delete this character"
	del.add_theme_font_size_override("font_size", 15)
	del.add_theme_color_override("font_color", Color(0.6, 0.45, 0.4))
	del.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	del.offset_left = -34
	del.offset_top = 6
	del.offset_right = -8
	del.offset_bottom = 32
	del.pressed.connect(func():
		var who := nm.text
		ui.open_dialog("Delete %s?" % who, "%s and everything they carry will be gone for good." % who,
			[["Delete", func():
				game.delete_character(id)
				Sfx.play("deny")
				refresh(game.list_characters())], ["Keep", func(): pass]]))
	b.add_child(del)
	if mine:
		b.add_theme_stylebox_override("normal", _card_box(true, true))
	return b

func _card_box(hot: bool, chosen := false) -> StyleBoxFlat:
	var bg: Color = Color(0.16, 0.115, 0.06, 0.96) if chosen else (Color(0.1, 0.08, 0.055, 0.94) if hot else Color(0.05, 0.042, 0.032, 0.9))
	var edge: Color = ui.GOLD if chosen else (Color(0.55, 0.43, 0.26) if hot else Color(0.24, 0.19, 0.12))
	var sb: StyleBoxFlat = ui._box(bg, edge, 2 if chosen else 1, 3, 0)
	if chosen:
		sb.shadow_color = Color(1.0, 0.7, 0.3, 0.25)
		sb.shadow_size = 8
	return sb

## Stand this character on the dais (the figure Play takes in).
func select(id: String) -> void:
	sel = id
	for b in _list.get_children():
		if b is Button and b.has_meta("id"):
			(b as Button).add_theme_stylebox_override("normal", _card_box(false, str(b.get_meta("id")) == id))
	if id == "":
		ui.title_stage.show_character({})
		ui.title_stage.remove_meta("char_id")
	else:
		ui.title_stage.set_meta("char_id", id)
		ui.title_stage.show_character(game.character_gear(id))
	_update()

func set_mode(m: String) -> void:
	if not _modes.has(m):
		m = "story"
	mode = m
	for k in _modes:
		(_modes[k] as Button).set_pressed_no_signal(k == m)
	_update()

func _update() -> void:
	var none := sel == ""
	_play.disabled = none
	_play.text = {"story": "Play", "online": "Join Co-op", "lan": "Host"}.get(mode, "Play")
	_join.visible = mode == "lan"
	_note.text = "Create a character to begin." if none else NOTE.get(mode, "")

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_status.visible = false
	# the Battlegrounds card breathes, brighter under the mouse
	if _bg_card != null and _bg_art != null:
		_bg_t += delta
		var hot := _bg_card.is_hovered()
		_bg_hot = move_toward(_bg_hot, 1.0 if hot else 0.0, delta * 5.0)
		var k := 1.04 + 0.03 * _bg_hot + sin(_bg_t * 0.3) * 0.01
		_bg_art.pivot_offset = _bg_art.size * Vector2(0.62, 0.4)
		_bg_art.scale = Vector2(k, k)
		_bg_art.modulate = Color(0.78, 0.78, 0.8).lerp(Color(1.08, 1.06, 1.1), _bg_hot)

## Play the chosen character the chosen way.
func play() -> void:
	if sel == "" or ui._title_busy:
		return
	match mode:
		"story":
			ui._title_choose("continue")
		"online":
			game.start_join(BuildEnv.value("coop_server"), sel)
		"lan":
			game.start_host(sel)

## Bottom left: the Battlegrounds, its own way in (a card of its key art in the iron and gold frame; BgPage).
func _build_bg_card() -> void:
	if OS.has_feature("web"):
		return                       # (no raw UDP in a browser)
	_bg_card = Button.new()
	_bg_card.name = "bg_card"
	_bg_card.focus_mode = Control.FOCUS_NONE
	_bg_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		_bg_card.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_bg_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bg_card.offset_left = 34
	_bg_card.offset_right = 34 + 400
	_bg_card.offset_top = -100 - 240
	_bg_card.offset_bottom = -100
	_bg_card.pressed.connect(func(): ui.open_battlegrounds())
	add_child(_bg_card)
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.offset_left = 16
	clip.offset_top = 16
	clip.offset_right = -16
	clip.offset_bottom = -16
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_card.add_child(clip)
	_bg_art = TextureRect.new()
	_bg_art.texture = load(BgPage.ART)
	_bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_bg_art)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float a = (1.0 - smoothstep(0.0, 0.75, UV.x)) * 0.8 + smoothstep(0.45, 1.0, UV.y) * 0.65; COLOR = vec4(0.01, 0.008, 0.012, clamp(a, 0.0, 0.92)); }"
	sm.shader = sh
	shade.material = sm
	clip.add_child(shade)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 34
	vb.offset_top = 24
	vb.offset_right = -30
	vb.offset_bottom = -30
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(vb)
	var eb: Label = ui._label("BATTLEGROUNDS", 14, Color(0.62, 0.78, 1.0), true)
	var ef := FontVariation.new()
	ef.base_font = ui.font_title
	ef.spacing_glyph = 3
	eb.add_theme_font_override("font", ef)
	eb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(eb)
	var t: Label = ui._label(Battlegrounds.TITLE, 30, ui.GOLD, true)
	t.add_theme_constant_override("outline_size", 8)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var l: Label = ui._label("PvP extraction raids  ·  Enter  ▸", 15, Color(0.88, 0.82, 0.72))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	# the frame over it all
	var fr := NinePatchRect.new()
	fr.texture = ui._ornate_frame(0.13)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		fr.set_patch_margin(side, int(ui.INV_PATCH * 0.13))
	fr.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	fr.draw_center = false
	fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_card.add_child(fr)

