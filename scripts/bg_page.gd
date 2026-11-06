class_name BgPage
extends Control
## The Battlegrounds' own page (Blaine, 2026-11-01: "the battlegrounds button should go to its own pvp page"): over the
## whole title, the Hollow Crypt's key art (Meshy, assets/textures/ui/bg_crypt.jpg) drifting slowly behind a dark
## gradient, the mode's name, what a raid is in three steps (Fight, Loot, Extract), the one rule that matters (death
## costs what you carry, levels are kept), your champion (the characters, cycled with the arrows; what they'd risk),
## the raid server's state (counting down when a raid turned us away) and one big Enter the Crypt, asked once in the
## ornate dialog. Back (or Esc) returns to the home screen. UI.open_battlegrounds opens it; Game.start_battlegrounds
## is the way in. Panels are UI._ornate (the inventory's iron and gold), buttons UI._iron_button.

const ART := "res://assets/textures/ui/bg_crypt.jpg"
const RED := Color(1.0, 0.42, 0.3)
const STEPS := [["I", "FIGHT", "Other players hunt the crypt as you do. Its dead are few, and deadly."],
	["II", "LOOT", "Chests, graves and the fallen: whatever you find is yours while you live."],
	["III", "EXTRACT", "The Extraction Portals open %d minutes in. Reach one, and keep it all."]]

var ui
var game
var sel := ""
var _chars: Array = []
var _art: TextureRect
var _t := 0.0
var _name: Label
var _cls: Label
var _risk: Label
var _status: Label
var _enter: Button
var _addr: LineEdit
var _glow: ColorRect
var _board: VBoxContainer
var _rows := []                  # one Label per live raid
var _board_t := 0.0

func setup(u) -> void:
	ui = u
	game = u.game
	name = "bg_page"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# the art, a touch larger than the screen so it can drift
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	_art = TextureRect.new()
	_art.texture = load(ART)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_art)
	# dark from the left (where the words are) and the bottom, and a vignette
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float left = 1.0 - smoothstep(0.0, 0.62, UV.x);
	float bottom = smoothstep(0.55, 1.0, UV.y);
	float vig = smoothstep(0.35, 0.95, length((UV - vec2(0.55, 0.45)) * vec2(1.0, 1.3)));
	COLOR = vec4(0.01, 0.008, 0.012, clamp(left * 0.88 + bottom * 0.7 + vig * 0.55, 0.0, 0.96));
}"""
	sm.shader = sh
	shade.material = sm
	add_child(shade)
	# the portal's breath: a cold glow far down the hall
	_glow = ColorRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = """shader_type canvas_item;
uniform float pulse = 0.5;
uniform vec2 at = vec2(0.655, 0.38);
void fragment() {
	vec2 d = (UV - at) * vec2(1.0, 0.75);
	float g = exp(-dot(d, d) * 60.0) * (0.25 + pulse * 0.3);
	COLOR = vec4(0.35, 0.6, 1.0, g);
}"""
	gm.shader = gs
	_glow.material = gm
	add_child(_glow)
	var dust := CPUParticles2D.new()
	dust.amount = 70
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(1100, 600)
	dust.position = Vector2(960, 540)
	dust.direction = Vector2(0.3, -1)
	dust.spread = 40.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 6.0
	dust.initial_velocity_max = 18.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.6
	dust.color = Color(0.85, 0.8, 0.7, 0.35)
	add_child(dust)
	resized.connect(func(): dust.position = size * 0.5; dust.emission_rect_extents = size * 0.55)
	_build_words()
	_build_champion()
	var back: Button = ui._iron_button("Back", 170, 50, 19)
	back.name = "back"
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40
	back.offset_right = 210
	back.offset_top = -82
	back.offset_bottom = -32
	back.pressed.connect(close)
	add_child(back)
	get_viewport().size_changed.connect(_layout)
	get_node("words").minimum_size_changed.connect(_layout.call_deferred)
	_layout()

func _layout() -> void:
	var available := get_viewport_rect().size
	var factor := minf(1.0, minf(available.x / 1440.0, available.y / 900.0))
	scale = Vector2.ONE * factor
	size = available / factor
	position = Vector2.ZERO
	var words: VBoxContainer = get_node("words")
	var heading: Label = words.get_node("heading")
	var width := maxf(720.0, size.x - 728.0)
	var font: Font = heading.get_theme_font("font")
	var font_size := 84
	while font_size > 40 and font.get_string_size(heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width - 20:
		font_size -= 1
	heading.add_theme_font_size_override("font_size", font_size)
	words.size = Vector2(width, 0)

func _title_font(sz: int, spacing := 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ui.font_title
	fv.spacing_glyph = spacing
	return fv

func _build_words() -> void:
	var vb := VBoxContainer.new()
	vb.name = "words"
	vb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vb.offset_left = 72
	vb.offset_top = 70
	vb.offset_right = 72 + 720
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var eyebrow: Label = ui._label("BATTLEGROUNDS  ·  PVP EXTRACTION", 17, Color(0.62, 0.78, 1.0), true)
	eyebrow.add_theme_font_override("font", _title_font(17, 4))
	vb.add_child(eyebrow)
	var title: Label = ui._label(Battlegrounds.map_title().to_upper(), 84, ui.GOLD, true)
	title.name = "heading"
	title.add_theme_font_override("font", _title_font(84, 2))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 6)
	vb.add_child(title)
	var rule := TextureRect.new()
	rule.texture = load("res://assets/textures/ui/sheet_divider.png")
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rule.custom_minimum_size = Vector2(300, 64)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(rule)
	var pitch: Label = ui._label("Descend with one of your heroes. Find what the dead left behind, and get out before someone takes it from you.", 21, Color(0.9, 0.86, 0.78))
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size = Vector2(640, 0)
	vb.add_child(pitch)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	vb.add_child(gap)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 16)
	vb.add_child(steps)
	for st in STEPS:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(222, 196)
		ui._ornate(pc, 0.17, 10)
		steps.add_child(pc)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 4)
		pc.add_child(sv)
		var num: Label = ui._label(str(st[0]), 30, Color(0.62, 0.78, 1.0), true)
		num.add_theme_font_override("font", _title_font(30))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(num)
		var hd: Label = ui._label(str(st[1]), 21, ui.GOLD, true)
		hd.add_theme_font_override("font", _title_font(21, 3))
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(hd)
		var tx := str(st[2])
		if tx.contains("%d"):
			tx = tx % int(Battlegrounds.PORTALS_AT / 60.0)
		var body: Label = ui._label(tx, 15, Color(0.84, 0.8, 0.72))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(body)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	vb.add_child(gap2)
	# the rule, on a blood-dark plate
	var warn := PanelContainer.new()
	warn.add_theme_stylebox_override("panel", ui._box(Color(0.16, 0.03, 0.02, 0.82), Color(0.62, 0.16, 0.1, 0.95), 2, 3, 14))
	warn.custom_minimum_size = Vector2(698, 0)
	warn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(warn)
	var wv := VBoxContainer.new()
	warn.add_child(wv)
	var w1: Label = ui._label("DEATH COSTS EVERYTHING YOU CARRY", 22, RED, true)
	w1.add_theme_font_override("font", _title_font(22, 2))
	wv.add_child(w1)
	var w2: Label = ui._label("Fall, and what you wear and carry and your gold stay where you fell. Your levels, rites and camp stash are kept.", 15, Color(0.92, 0.78, 0.72))
	w2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wv.add_child(w2)

func _build_champion() -> void:
	var pc := PanelContainer.new()
	pc.name = "champion"
	pc.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pc.offset_left = -608
	pc.offset_right = -48
	pc.offset_top = -430 - 24 * Battlegrounds.LIVE_RAIDS
	pc.offset_bottom = -40
	ui._ornate(pc, 0.26, 18)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var hd: Label = ui._label("YOUR CHAMPION", 17, Color(0.7, 0.62, 0.48), true)
	hd.add_theme_font_override("font", _title_font(17, 4))
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hd)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var prev: Button = ui._iron_button("◀", 44, 44, 18)
	prev.name = "prev"
	prev.pressed.connect(func(): _cycle(-1))
	row.add_child(prev)
	var nv := VBoxContainer.new()
	nv.custom_minimum_size = Vector2(300, 0)
	nv.add_theme_constant_override("separation", 0)
	row.add_child(nv)
	_name = ui._label("", 32, Color(0.98, 0.92, 0.8), true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	nv.add_child(_name)
	_cls = ui._label("", 17, ui.GOLD)
	_cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nv.add_child(_cls)
	var nxt: Button = ui._iron_button("▶", 44, 44, 18)
	nxt.name = "next"
	nxt.pressed.connect(func(): _cycle(1))
	row.add_child(nxt)
	_risk = ui._label("", 15, Color(0.9, 0.7, 0.6))
	_risk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_risk)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	# the raids running now (Battlegrounds.schedule, from the clock): time left, open or not
	_board = VBoxContainer.new()
	_board.name = "raids"
	_board.add_theme_constant_override("separation", 2)
	vb.add_child(_board)
	for i in Battlegrounds.LIVE_RAIDS:
		var r: Label = ui._label("", 16, Color(0.86, 0.82, 0.74))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_board.add_child(r)
		_rows.append(r)
	_status = ui._label("", 16, Color(0.62, 0.85, 1.0), true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)
	_enter = ui._iron_button("Enter the Crypt", 420, 74, 32)
	_enter.name = "enter"
	_enter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_enter.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	_enter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_enter.add_theme_constant_override("outline_size", 6)
	_enter.pressed.connect(enter)
	vb.add_child(_enter)
	# the raid server (its own build's by default; a field for a test server, folded away)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 8)
	vb.add_child(srow)
	_addr = LineEdit.new()
	_addr.name = "addr"
	_addr.placeholder_text = "server (host:port)"
	_addr.custom_minimum_size = Vector2(260, 32)
	_addr.add_theme_font_size_override("font_size", 14)
	_addr.add_theme_stylebox_override("normal", ui._box(Color(0.04, 0.035, 0.03, 0.9), Color(0.35, 0.28, 0.18), 1, 3, 8))
	_addr.visible = false
	_addr.text_submitted.connect(func(_t): enter())
	var srv := Button.new()
	srv.name = "server"
	srv.flat = true
	srv.focus_mode = Control.FOCUS_NONE
	srv.add_theme_font_size_override("font_size", 13)
	srv.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
	srv.add_theme_color_override("font_hover_color", Color(0.85, 0.75, 0.55))
	srv.text = "Server: %s  ·  change" % ("this PC" if BuildEnv.env() == "local" else BuildEnv.env())
	srv.pressed.connect(func(): _addr.visible = not _addr.visible)
	srow.add_child(srv)
	srow.add_child(_addr)

func open() -> void:
	Sfx.play("click")
	_chars = game.list_characters()
	var last := str(game._load_setting("battlegrounds", "character", ""))
	if sel == "" or _chars.filter(func(c): return str(c["id"]) == sel).is_empty():
		sel = last if not _chars.filter(func(c): return str(c["id"]) == last).is_empty() else (str(_chars[0]["id"]) if not _chars.is_empty() else "")
	_addr.text = str(game._load_setting("battlegrounds", "address", ""))
	_t = 0.0
	visible = true
	_show()

func close() -> void:
	if not visible:
		return
	Sfx.play("click")
	visible = false
	game.bg_retry = []          # (no longer waiting for the next raid)
	if ui.home != null and sel != "":
		ui.home.select(sel)     # (the one you were looking at stands on the dais)

func _cycle(d: int) -> void:
	if _chars.is_empty():
		return
	var i := 0
	for k in _chars.size():
		if str(_chars[k]["id"]) == sel:
			i = k
	sel = str(_chars[posmod(i + d, _chars.size())]["id"])
	Sfx.play("click")
	_show()

func _show() -> void:
	for key in ["prev", "next"]:
		(get_node("champion").find_child(key, true, false) as Button).disabled = _chars.size() < 2
	var c: Dictionary = {}
	for x in _chars:
		if str(x["id"]) == sel:
			c = x
	if c.is_empty():
		_name.text = "No champion"
		_cls.text = "Create a character on the home screen first."
		_risk.text = ""
		_enter.disabled = true
		return
	_enter.disabled = false
	_name.text = str(c["name"]) if str(c["name"]) != "" else "Unnamed"
	var cls := str(c["cls"])
	_cls.text = "Level %d %s" % [int(c["level"]), Data.CLASSES.get(cls, {"name": "Knight"})["name"]]
	_cls.add_theme_color_override("font_color", ClassStage.ACCENTS.get(cls, ui.GOLD))
	var n := int(c.get("carried", 0))
	var g := int(c.get("gold", 0))
	_risk.text = "At stake: %d item%s and %s gold" % [n, "" if n == 1 else "s", BoatShop.gold_str(g)] if n + g > 0 else "Nothing at stake yet: go in light, come out rich."
	(get_node("champion").find_child("prev", true, false) as Button).disabled = _chars.size() < 2
	(get_node("champion").find_child("next", true, false) as Button).disabled = _chars.size() < 2

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# the art drifts and breathes; the portal pulses
	var k := 1.06 + sin(_t * 0.05) * 0.02
	_art.pivot_offset = _art.size * Vector2(0.62, 0.4)
	_art.scale = Vector2(k, k)
	_art.position = Vector2(sin(_t * 0.07) * 14.0, cos(_t * 0.05) * 8.0)
	(_glow.material as ShaderMaterial).set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 1.6) * (0.7 + 0.3 * sin(_t * 0.37)))
	_enter.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.15, 1.05, 0.95), 0.5 + 0.5 * sin(_t * 2.2)) if not _enter.disabled else Color(0.6, 0.6, 0.6)
	var waiting: bool = game.bg_wait_until > Time.get_ticks_msec() and not game.bg_retry.is_empty()
	_board_t -= delta
	if _board_t <= 0.0:
		_board_t = 0.25
		_fill_board()
	if waiting:
		_status.text = "The raid you chose is closing. The next opens in %s, and you'll be let in then." % game.bg_wait_text()
	elif _addr.text.strip_edges() != "":
		_status.text = "Up to %d heroes in each raid." % Battlegrounds.MAX_PLAYERS
	else:
		var b: Dictionary = Battlegrounds.best_raid(Time.get_unix_time_from_system())
		_status.text = ("You'll join Raid %s, %s left." % [b["name"], _clock(float(b["left"]))]) if b.get("open", false) \
			else ("Every raid is in its last minutes. Raid %s opens in %s." % [b["name"], _clock(float(b["opens_in"]))])

static func _clock(t: float) -> String:
	var s := int(ceilf(t))
	return "%d:%02d" % [s / 60, s % 60]

## The raids now: name, time left, whether it takes joiners.
func _fill_board() -> void:
	var sch: Array = Battlegrounds.schedule(Time.get_unix_time_from_system())
	for k in mini(sch.size(), _rows.size()):
		var r: Dictionary = sch[k]
		var l: Label = _rows[k]
		if r["open"] and float(r["left"]) > Battlegrounds.RAID_SECS - Battlegrounds.LOBBY_MAX:
			l.text = "Raid %s  ·  gathering in the antechamber  ·  join now" % r["name"]
			l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		elif r["open"]:
			l.text = "Raid %s  ·  %s left  ·  open" % [r["name"], _clock(float(r["left"]))]
			l.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
		elif r["state"] == "raid":
			l.text = "Raid %s  ·  %s left  ·  closed, next in %s" % [r["name"], _clock(float(r["left"])), _clock(float(r["opens_in"]))]
			l.add_theme_color_override("font_color", Color(0.85, 0.6, 0.45))
		else:
			l.text = "Raid %s  ·  resetting, opens in %s" % [r["name"], _clock(float(r["opens_in"]))]
			l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))

func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev.is_pressed() and (ev as InputEventKey).keycode == KEY_ESCAPE and not ui.dialog_panel.visible:
		close()
		get_viewport().set_input_as_handled()

## One last word, then in.
func enter() -> void:
	if sel == "" or _enter.disabled or ui._title_busy:
		return
	var nm := _name.text
	var addr := _addr.text.strip_edges()
	if addr == "":
		# this build's raid server, at the port of the best raid now (Battlegrounds.best_raid)
		var host: String = (BuildEnv.value("bg_server") if BuildEnv.env() != "local" else "127.0.0.1").split(":")[0]
		addr = "%s:%d" % [host, int(Battlegrounds.best_raid(Time.get_unix_time_from_system()).get("port", Net.PORT))]
	var id := sel
	Sfx.play("click")
	ui.open_dialog("Enter the Crypt?", "%s goes in with everything they wear and carry. Fall, and it stays on the crypt floor." % nm,
		[["Enter", func():
			visible = false
			game.start_battlegrounds(addr, id)], ["Not yet", func(): pass]])
