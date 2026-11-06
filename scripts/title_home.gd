class_name TitleHome
extends Control
## The title's controls (Blaine, 2026-11-05: "Simplify the bottom controls to Enter World, Multiplayer, and a smaller
## Quit"): the gate scene (TitleStage) stays the picture, the chosen character standing alone in the arch; over it
##  - a right sidebar of your characters (name, level and class, act, last played): click one to stand it in the arch;
##    delete on its card (asks first); "Create New Character" at the bottom of the list
##  - bottom centre: Enter World (the chosen character's game: alone, or with friends who join you), Multiplayer (the
##    lobby browser: Battlegrounds, Arena, Endless Waves; LobbyClient) and a small Quit
##  - the title and the buttons are centred in the room left of the sidebar (`mid`)
## LAN is no menu of its own any more: the lobby browser's "Local network" row hosts or joins one (lan_host,
## lan_join). Panels are UI._ornate (the inventory's iron and gold frame), buttons UI._iron_button (Blaine).
## UI keeps the old cards (hidden) so its title API and tests stay as they were.

const W := 420.0                 # the sidebar's width
const EDGE := 18.0               # the screen edge to the sidebar and the column
const BOARD_TOP := 168.0         # (the Last Flame board's top, for when it has a home again)
const LEFT_W := 360.0            # (the board's width)

var ui
var game
var sel := ""                    # the chosen character's id
var _list: VBoxContainer
var _count: Label
var _play: Button                # Enter World
var _mp: Button                  # Multiplayer
var _quit: Button
var _note: Label
var _status: Label
var _board: VBoxContainer
var _board_rows: VBoxContainer
var _board_best: Label
var _board_busy := false

## The middle of the free room left of the sidebar, from the screen's centre (the title, the buttons and the
## stage's framing use it).
static func mid() -> float:
	return -(W + EDGE) * 0.5

func setup(u) -> void:
	ui = u
	game = u.game
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_sidebar()
	_build_play()
	# Scale the layout as one on small screens; the buttons must never cross into the character sidebar.
	var head: Control = ui.title_panel.get_node("title_head")
	head.reparent(self, false)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 34
	head.offset_left = EDGE
	head.offset_right = -W - EDGE
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var available := get_viewport_rect().size
	var factor := minf(1.0, minf(available.x / 1440.0, available.y / 800.0))
	scale = Vector2.ONE * factor
	size = available / factor
	position = Vector2.ZERO
	var title: Label = get_node("title_head").get_child(0)
	title.add_theme_font_size_override("font_size", mini(84, int((size.x - W - EDGE * 2) / 9.0)))

func _build_sidebar() -> void:
	var side := PanelContainer.new()
	side.name = "sidebar"
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -W - EDGE
	side.offset_right = -EDGE
	side.offset_top = EDGE
	side.offset_bottom = -EDGE
	ui._ornate(side, 0.2, 8)
	add_child(side)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	side.add_child(vb)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 6)
	hm.add_theme_constant_override("margin_right", 30)     # (the count clear of the frame's corner spike)
	hm.add_theme_constant_override("margin_top", 4)
	vb.add_child(hm)
	var head := HBoxContainer.new()
	hm.add_child(head)
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
	make.visible = MpMode.CREATE_CHARACTER
	vb.add_child(make)

func _build_play() -> void:
	var box := VBoxContainer.new()
	box.name = "play_box"
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -30
	# centred in the room left of the sidebar
	box.offset_left = mid() - 380
	box.offset_right = mid() + 380
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_status = ui._label("", 15, Color(0.6, 0.85, 1.0), true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.name = "buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_play = ui._iron_button("Enter World", 340, 68, 30)
	_play.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_play.add_theme_constant_override("outline_size", 6)
	_play.name = "play"
	_play.pressed.connect(play)
	row.add_child(_play)
	_mp = ui._iron_button("Multiplayer", 240, 68, 24)
	_mp.name = "multiplayer"
	_mp.pressed.connect(open_multiplayer)
	_mp.visible = not OS.has_feature("web")        # (no raw UDP in a browser)
	row.add_child(_mp)
	_quit = ui._iron_button("Quit", 110, 44, 16)
	_quit.name = "quit"
	_quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quit.add_theme_color_override("font_color", Color(0.7, 0.62, 0.5))
	_quit.pressed.connect(func(): get_tree().quit())
	_quit.visible = not OS.has_feature("web")
	row.add_child(_quit)
	_note = ui._label("", 16, Color(0.78, 0.72, 0.64))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	_update()

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

func _update() -> void:
	var none := sel == ""
	_play.disabled = none
	_note.text = "Create a character to begin." if none else ""
	_note.visible = none

func _process(_delta: float) -> void:
	# Subpages own the screen and input
	visible = not ((ui.class_panel != null and ui.class_panel.visible)
		or (ui.chars_panel != null and ui.chars_panel.visible)
		or (ui.bg_page != null and ui.bg_page.visible)
		or (ui.join_panel != null and ui.join_panel.visible)
		or (game.lobby_client != null and game.lobby_client.panel.visible))
	if is_visible_in_tree():
		_status.visible = false

## Enter World: the chosen character's own game (friends join it from there).
func play() -> void:
	if sel == "" or ui._title_busy:
		return
	ui._title_choose("continue")

## Multiplayer: straight to the lobby browser.
func open_multiplayer() -> void:
	game.lobby_client.open()

## LAN, from the lobby browser's "Local network" row: host the chosen character's game on this network, or find one.
func lan_host() -> void:
	if sel != "":
		game.lobby_client.panel.hide()
		game.start_host(sel)

func lan_join() -> void:
	game.lobby_client.panel.hide()
	ui.open_join()

## (Not on the home screen since 2026-11-05: for the Endless Waves lobby to show.) The Hall of the Last Flame, the endless vigil's best ten (FlameBoard; Blaine: "a
## leaderboard added to the main title page"), with this game's own best under it. It fills from the server when the
## title shows (refresh_board); offline it says so and keeps the local best. It shrinks to the room left above the
## Battlegrounds card (its rows are cut, never drawn over the card).
func _build_board() -> void:
	var panel := PanelContainer.new()
	panel.name = "flame_board"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = EDGE
	panel.offset_right = EDGE + LEFT_W
	panel.offset_top = BOARD_TOP
	panel.clip_contents = true
	ui._ornate(panel, 0.16, 6)
	add_child(panel)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 4)
	panel.add_child(_board)
	var k: Label = ui._label("THE LAST FLAME", 13, Color(1.0, 0.62, 0.3), true)
	var kf := FontVariation.new()
	kf.base_font = ui.font_title
	kf.spacing_glyph = 3
	k.add_theme_font_override("font", kf)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(k)
	var t: Label = ui._label("Hall of the Last Flame", 21, ui.GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(t)
	var rule := TextureRect.new()
	rule.texture = load("res://assets/textures/ui/sheet_divider.png")
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rule.custom_minimum_size = Vector2(0, 18)
	_board.add_child(rule)
	_board_rows = VBoxContainer.new()
	_board_rows.add_theme_constant_override("separation", 1)
	_board.add_child(_board_rows)
	_board_best = ui._label("", 13, ui.DIM)
	_board_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board.add_child(_board_best)
	var enter: Button = ui._iron_button("Play Endless Waves", 0, 42, 17)
	enter.pressed.connect(func(): game.lobby_client.open("waves"))
	_board.add_child(enter)
	_board_note("Reaching the hall...")

func _board_note(txt: String) -> void:
	for c in _board_rows.get_children():
		_board_rows.remove_child(c)
		c.queue_free()
	var l: Label = ui._label(txt, 14, ui.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board_rows.add_child(l)

## Fills the hall from the server (when the title shows). Rows that wouldn't fit above the Battlegrounds card are left
## out.
func refresh_board() -> void:
	if _board == null or _board_busy:
		return
	var b := FlameBoard.best(game)
	_board_best.text = "Your best: %d wave%s" % [b, "" if b == 1 else "s"] if b > 0 else "Play Endless Waves from Multiplayer"
	_board_busy = true
	var rows = await FlameBoard.top(game)
	_board_busy = false
	if not is_instance_valid(_board_rows):
		return
	if rows == null:
		_board_note("Leaderboard offline. Play is available.")
		return
	if (rows as Array).is_empty():
		_board_note("No waves recorded yet. Be the first.")
		return
	for c in _board_rows.get_children():
		_board_rows.remove_child(c)
		c.queue_free()
	# room for rows: from the hall's top down to the Battlegrounds card, less the hall's own heading and footer
	var room := (size.y - EDGE - 8 - 64.0 - 14 - 196.0 - 12) - BOARD_TOP - 164.0
	var fit := clampi(int(room / 23.0), 3, FlameBoard.TOP)
	for r in (rows as Array).slice(0, fit):
		_board_rows.add_child(_board_row(r))

func _board_row(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var mine: bool = r["mine"]
	var top3: bool = int(r["rank"]) <= 3
	var col: Color = Color(1.0, 0.86, 0.5) if mine else (Color(0.95, 0.88, 0.74) if top3 else Color(0.82, 0.77, 0.68))
	var rk: Label = ui._label("%d" % int(r["rank"]), 15, Color(1.0, 0.62, 0.3) if top3 else ui.DIM, true)
	rk.custom_minimum_size = Vector2(26, 0)
	rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(rk)
	var cls: String = Data.CLASSES.get(str(r["cls"]), {}).get("name", "")
	var nm: Label = ui._label(str(r["name"]) + ("  ·  " + cls if cls != "" else ""), 15, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(nm)
	var p := int(r["party"])
	var w: Label = ui._label("%d%s" % [int(r["waves"]), "" if p <= 1 else "  (%dp)" % p], 15, col, true)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(w)
	return h
