class_name TitleHome
extends Control
## The title's controls, WoW-style (Blaine, 2026-11-01): the gate scene (TitleStage) stays the picture; over it
##  - a right sidebar of your characters (name, level and class, act, last played): click one to stand it on the dais;
##    delete on its card (asks first); "Create New Character" at the bottom of the list
##  - bottom centre, how to play it: Story · Battlegrounds · Online Co-op · LAN, and one big Play (LAN: Host / Join);
##    Battlegrounds says in one line what death costs there, and counts down when a raid turned us away
##  - bottom left: Quit
## Play hands the chosen character to the game: Story = UI._title_choose("continue") on it, Battlegrounds =
## Game.start_battlegrounds (after one confirm), Online Co-op = Game.start_join on the co-op server, LAN = host or
## the join screen. UI keeps the old cards (hidden) so its title API and tests stay as they were.

const W := 360.0                 # the sidebar's width
const MODES := [["story", "Story"], ["bg", "Battlegrounds"], ["online", "Online Co-op"], ["lan", "LAN"]]
const NOTE := {"story": "Your journey through the acts, alone.", "bg": "Death in the crypt costs everything you carry. Levels are kept.",
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

func setup(u) -> void:
	ui = u
	game = u.game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_sidebar()
	_build_play()
	var quit: Button = ui._iron_button("Quit", 110, 38, 15)
	quit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	quit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	quit.position = Vector2(24, -62)
	quit.offset_top = -62
	quit.offset_bottom = -24
	quit.offset_left = 24
	quit.offset_right = 134
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
	side.offset_left = -W - 22
	side.offset_right = -22
	side.offset_top = 28
	side.offset_bottom = -28
	side.add_theme_stylebox_override("panel", ui._box(Color(0.03, 0.025, 0.02, 0.86), Color(0.45, 0.35, 0.2, 0.9), 1, 4, 14))
	add_child(side)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	side.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t: Label = ui._label("CHARACTERS", 20, ui.GOLD, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count = ui._label("", 14, ui.DIM)
	head.add_child(_count)
	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.35, 0.2, 0.6)
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	var make: Button = ui._iron_button("Create New Character", int(W - 28), 46, 17)
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
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(128, 34)
		b.add_theme_font_size_override("font_size", 15)
		var id: String = m[0]
		b.pressed.connect(func(): set_mode(id))
		row.add_child(b)
		_modes[id] = b
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", 10)
	box.add_child(prow)
	_play = ui._iron_button("Play", 300, 58, 26)
	_play.name = "play"
	_play.pressed.connect(play)
	prow.add_child(_play)
	_join = ui._iron_button("Join", 150, 58, 22)
	_join.pressed.connect(func(): ui.open_join())
	_join.visible = false
	prow.add_child(_join)
	_note = ui._label("", 14, Color(0.78, 0.72, 0.64))
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
	b.custom_minimum_size = Vector2(W - 34, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("id", id)
	var mine := id == sel
	b.add_theme_stylebox_override("normal", _card_box(false))
	b.add_theme_stylebox_override("hover", _card_box(true))
	b.add_theme_stylebox_override("pressed", _card_box(true))
	b.pressed.connect(func(): select(id))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14
	vb.offset_top = 8
	vb.offset_right = -40
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var nm: Label = ui._label(str(c["name"]) if str(c["name"]) != "" else "Unnamed", 20, Color(0.97, 0.9, 0.78), true)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var cls: String = Data.CLASSES.get(c["cls"], {"name": "Knight"})["name"]
	var l1: Label = ui._label("Level %d %s" % [int(c["level"]), cls], 14, Color(0.86, 0.8, 0.7))
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
	var bg: Color = Color(0.13, 0.1, 0.06, 0.95) if chosen else (Color(0.08, 0.065, 0.045, 0.92) if hot else Color(0.05, 0.04, 0.03, 0.85))
	var edge: Color = ui.GOLD if chosen else (Color(0.5, 0.4, 0.25) if hot else Color(0.25, 0.2, 0.13))
	return ui._box(bg, edge, 2 if chosen else 1, 4, 0)

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
	if m != "bg":
		game.bg_retry = []          # (no longer waiting for the next raid)
	for k in _modes:
		(_modes[k] as Button).set_pressed_no_signal(k == m)
	_update()

func _update() -> void:
	var none := sel == ""
	_play.disabled = none
	_play.text = {"story": "Play", "bg": "Enter the Crypt", "online": "Join Co-op", "lan": "Host"}.get(mode, "Play")
	_join.visible = mode == "lan"
	_note.text = "Create a character to begin." if none else NOTE.get(mode, "")
	_note.add_theme_color_override("font_color", Color(1.0, 0.5, 0.38) if mode == "bg" and not none else Color(0.78, 0.72, 0.64))

func _process(_d: float) -> void:
	if not is_visible_in_tree():
		return
	var waiting: bool = game.bg_wait_until > Time.get_ticks_msec() and not game.bg_retry.is_empty()
	_status.visible = waiting
	if waiting:
		_status.text = "The next raid opens in %s. You'll be let in then." % game.bg_wait_text()

## Play the chosen character the chosen way.
func play() -> void:
	if sel == "" or ui._title_busy:
		return
	match mode:
		"story":
			ui._title_choose("continue")
		"bg":
			var nm := ""
			for c in game.list_characters():
				if str(c["id"]) == sel:
					nm = str(c["name"])
			var addr := str(game._load_setting("battlegrounds", "address", ""))
			if addr == "":
				addr = BuildEnv.value("bg_server") if BuildEnv.env() != "local" else "127.0.0.1"
			var id := sel
			ui.open_dialog("Enter the Crypt?", "%s goes in with everything they wear and carry. Fall, and it stays on the crypt floor." % nm,
				[["Enter", func(): game.start_battlegrounds(addr, id)], ["Not yet", func(): pass]])
		"online":
			game.start_join(BuildEnv.value("coop_server"), sel)
		"lan":
			game.start_host(sel)
