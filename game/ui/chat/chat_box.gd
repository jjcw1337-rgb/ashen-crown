class_name ChatBox
extends Control
## In-game chat (jj, 2026-11-07): in a match (Battlegrounds, Arena, Sandbox) Enter opens a line at the bottom left,
## Enter sends it and Escape closes it. Everyone in the match reads it; a line starting with "/t" goes to your team
## only (a duo's pair, an Arena team). The server checks and relays every line (Net.sv_chat: a length cap and a rate
## limit, the sender's name its own, never the client's), so this only shows what arrives (Net.cl_chat -> add).
## While the line is open the hero doesn't walk (Game.wasd_dir) and keys type, not cast.

const MAX_LINES := 8
const SHOW_SECS := 12.0          # a line fades this long after it arrived (the whole log shows while typing)
const MAX_LEN := 160              # (Net.CHAT_MAX: the server cuts longer lines)
const TEAM_COL := Color(0.55, 0.95, 0.6)
const ALL_COL := Color(0.95, 0.92, 0.85)
const NAME_COL := Color(1.0, 0.8, 0.45)
## While you type, the line glows neon (jj, 2026-11-07: "neon green and blue to type"): its border and glow drift
## between these two, and a TYPING tag sits at its right end, so it's plain your keys are typing, not casting.
const NEON_GREEN := Color(0.25, 1.0, 0.45)
const NEON_BLUE := Color(0.2, 0.7, 1.0)
const NEON_PULSE := 2.6           # radians a second: one green -> blue -> green sweep every ~2.4 s
const FADE := 0.12                # seconds the line takes to light up or fade out

var game: Node
var log_box: VBoxContainer
var input: LineEdit
var typing := false
var neon: StyleBoxFlat           # the line's lit style (its border and glow pulse while typing)
var tag: Label                   # "TYPING", over the line
var _neon_t := 0.0
var _fade: Tween
var _lines: Array = []           # [RichTextLabel, arrived (msec)]

static func attach(ui: Node) -> ChatBox:
	var c := ChatBox.new()
	c.name = "chat"
	c.game = ui.game
	ui.hud.add_child(c)
	c._build()
	return c

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 18
	offset_right = 18 + 460
	offset_top = -462
	offset_bottom = -262      # (above the controls hint and the action bar)
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_box.offset_bottom = -34
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.add_theme_constant_override("separation", 2)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_box)
	input = LineEdit.new()
	input.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	input.offset_top = -30
	input.max_length = MAX_LEN
	input.placeholder_text = "Say something  (/t: your team)  ·  Enter sends, Esc closes"
	input.visible = false
	input.add_theme_font_size_override("font_size", 15)
	neon = StyleBoxFlat.new()
	neon.bg_color = Color(0.02, 0.05, 0.06, 0.88)
	neon.border_color = NEON_GREEN
	neon.set_border_width_all(2)
	neon.set_corner_radius_all(5)
	neon.content_margin_left = 10
	neon.content_margin_right = 88       # (room for the TYPING tag)
	neon.shadow_color = Color(NEON_GREEN.r, NEON_GREEN.g, NEON_GREEN.b, 0.55)
	neon.shadow_size = 10
	input.add_theme_stylebox_override("normal", neon)
	input.add_theme_stylebox_override("focus", neon)
	input.add_theme_color_override("font_color", Color(0.9, 1.0, 0.95))
	input.add_theme_color_override("caret_color", NEON_GREEN)
	input.add_theme_color_override("font_placeholder_color", Color(0.45, 0.85, 0.75, 0.75))
	input.add_theme_color_override("selection_color", Color(NEON_BLUE.r, NEON_BLUE.g, NEON_BLUE.b, 0.45))
	input.add_theme_constant_override("caret_width", 2)
	tag = Label.new()
	tag.text = "TYPING"
	tag.visible = false
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)      # (inside the line's right end, clear of the log)
	tag.offset_left = -84
	tag.offset_right = -10
	tag.offset_top = -28
	tag.offset_bottom = -2
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", NEON_GREEN)
	tag.add_theme_color_override("font_outline_color", Color(NEON_BLUE.r, NEON_BLUE.g, NEON_BLUE.b, 0.8))
	tag.add_theme_constant_override("outline_size", 4)
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_input_key)
	add_child(input)
	add_child(tag)

## Tools and tests can open it outside a match (nothing is sent: there's no server to send to).
var allow_offline := false

## Whether chat can open here: in a match with other players (a server's world), not on a menu or the title.
func can_chat() -> bool:
	return game != null and game.playing and (allow_offline or (game.net.active and not game.net.server)) and not game._busy

func _unhandled_key_input(ev: InputEvent) -> void:
	if typing or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER) and can_chat():
		open()
		get_viewport().set_input_as_handled()

func open() -> void:
	typing = true
	input.visible = true
	tag.visible = true
	input.text = ""
	input.grab_focus()
	_neon_t = 0.0
	_glow(1.0)
	for l in _lines:
		(l[0] as CanvasItem).modulate.a = 1.0

func close() -> void:
	typing = false
	input.release_focus()
	_glow(0.0)

## Lights the line up (1) or fades it out and hides it (0).
func _glow(to: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not is_inside_tree():
		input.modulate.a = to
		tag.modulate.a = to
		input.visible = to > 0.0
		tag.visible = to > 0.0
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(input, "modulate:a", to, FADE)
	_fade.tween_property(tag, "modulate:a", to, FADE)
	if to <= 0.0:
		_fade.chain().tween_callback(func():
			if not typing:
				input.visible = false
				tag.visible = false)

func _input_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		close()
		input.accept_event()

func _submit(text: String) -> void:
	var t := text.strip_edges()
	close()
	if t == "":
		return
	var team := t.begins_with("/t ") or t == "/t"
	if team:
		t = t.substr(2).strip_edges()
	if t != "":
		game.net.send_chat(t, team)

## A line from the server: who said it, what, and whether it was for the team only.
func add(who: String, text: String, team: bool) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 15)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	# (escape the player's text: [ and ] would be markup)
	var safe := text.replace("[", "[lb]")
	var nm := who.replace("[", "[lb]")
	var col: Color = TEAM_COL if team else ALL_COL
	l.text = "[color=#%s]%s%s:[/color] [color=#%s]%s[/color]" % [NAME_COL.to_html(false), "(team) " if team else "", nm, col.to_html(false), safe]
	log_box.add_child(l)
	_lines.append([l, Time.get_ticks_msec()])
	while _lines.size() > MAX_LINES:
		(_lines[0][0] as Node).queue_free()
		_lines.pop_front()

func clear() -> void:
	for l in _lines:
		(l[0] as Node).queue_free()
	_lines.clear()
	close()

func _process(delta: float) -> void:
	visible = game != null and game.playing
	if typing and not can_chat():
		close()
	if typing:
		_neon_t += delta
		_pulse()
	var now := Time.get_ticks_msec()
	for l in _lines:
		var age := (now - int(l[1])) / 1000.0
		(l[0] as CanvasItem).modulate.a = 1.0 if typing else clampf((SHOW_SECS - age) / 1.5, 0.0, 1.0)

## The neon's drift: the border and glow sweep green -> blue -> green, the glow breathing a little with it.
func _pulse() -> void:
	var k := 0.5 - 0.5 * cos(_neon_t * NEON_PULSE)      # (0 at the open: it lights up green)
	var c := NEON_GREEN.lerp(NEON_BLUE, k)
	neon.border_color = c
	neon.shadow_color = Color(c.r, c.g, c.b, 0.4 + 0.25 * (1.0 - absf(k - 0.5) * 2.0))
	tag.add_theme_color_override("font_color", NEON_GREEN.lerp(NEON_BLUE, 1.0 - k))
	input.add_theme_color_override("caret_color", c)
