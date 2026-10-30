class_name WaypointPanel
extends PanelContainer
## The waypoint window: a tab per act (Data.WAYPOINT_ACTS), its Meshy banner, and the act's route of
## waypoints. Built in the action bar's iron frame and sockets. An act's tab opens once the act before
## it falls (Game.act_unlocked); a waypoint lights once a player has touched its stone
## (Game.waypoint_known). Click a lit waypoint to go there, in this act or another (Game.waypoint_go).
## Everything it shows comes from Data and Game, so a new act or waypoint needs no change here.

const SIGIL := "res://assets/textures/ui/wp_sigil.png"
const FRAME := "res://assets/textures/ui/bar_frame.png"
const SLOT := "res://assets/textures/ui/slot.png"
const CYAN := Color(0.45, 0.85, 1.0)
const GOLD := Color(0.86, 0.72, 0.44)
const DIM := Color(0.62, 0.58, 0.52)
const INK := Color(0.9, 0.87, 0.8)

var ui: UI
var game: Node
var sel_run := 0
var _t := 0.0
var _spin := 0.0             # extra sigil spin after a click (the jump)
var sigil: TextureRect
var tabs_box: HBoxContainer
var banner_clip: Control
var banner: TextureRect
var banner_title: Label
var banner_sub: Label
var banner_note: Label
var next_box: VBoxContainer
var seal: Label
var route_box: VBoxContainer
var route_line: Control
var here_icons: Array = []   # the "you are here" sigils, pulsed in _process
var stone: Node3D = null     # the waypoint stone it was opened from: walk away and it closes
var cover: Control           # a clear layer behind the window: a click off the window closes it

func setup(u: UI) -> void:
	ui = u
	game = u.game
	name = "Waypoints"
	visible = false
	cover = Control.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.visible = false
	cover.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	get_parent().add_child(cover)
	get_parent().move_child(cover, get_index())
	visibility_changed.connect(func(): cover.visible = visible)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -480
	offset_right = 480
	offset_top = -362
	offset_bottom = 236
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAME)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 62)
	sb.content_margin_left = 74
	sb.content_margin_right = 74
	sb.content_margin_top = 54
	sb.content_margin_bottom = 70
	add_theme_stylebox_override("panel", sb)
	# the frame's middle is open: a dark backing inside it
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", ui._box(Color(0.03, 0.025, 0.02, 0.97), Color(0.2, 0.15, 0.09), 1, 4, 0))
	back.show_behind_parent = true
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.offset_left = 22; back.offset_right = -22; back.offset_top = 22; back.offset_bottom = -22
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	# --- header: the turning sigil, the title, the close button
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(58, 58)
	head.add_child(sw)
	sigil = TextureRect.new()
	sigil.texture = load(SIGIL)
	sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil.size = Vector2(58, 58)
	sigil.pivot_offset = Vector2(29, 29)
	sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(sigil)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(ui._label("WAYPOINTS", 24, GOLD, true))
	tv.add_child(ui._label("Touch a waypoint stone to bind it  ·  slay an act's lord to open the next", 12, DIM))
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(34, 30)
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func():
		close()
		Sfx.play("click"))
	head.add_child(x)
	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.4)
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	# --- the act tabs
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 10)
	vb.add_child(tabs_box)
	# --- body: the act's banner on the left, its route on the right
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var bframe := PanelContainer.new()
	bframe.add_theme_stylebox_override("panel", ui._box(Color(0, 0, 0, 1), Color(0.55, 0.43, 0.24), 2, 6, 0))
	bframe.custom_minimum_size = Vector2(350, 262)
	body.add_child(bframe)
	banner_clip = Control.new()
	banner_clip.clip_contents = true
	banner_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bframe.add_child(banner_clip)
	banner = TextureRect.new()
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_clip.add_child(banner)
	# a dark fade up from the bottom, under the act's name
	var fade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0))
	gr.set_color(1, Color(0, 0, 0, 0.92))
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0.35)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_clip.add_child(fade)
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 1)
	cap.anchor_top = 1.0
	cap.anchor_bottom = 1.0
	cap.anchor_right = 1.0
	cap.offset_left = 16
	cap.offset_right = -16
	cap.offset_top = -96
	cap.offset_bottom = -12
	cap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cap.alignment = BoxContainer.ALIGNMENT_END
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_clip.add_child(cap)
	banner_sub = ui._label("", 12, CYAN, true)
	cap.add_child(banner_sub)
	banner_title = ui._label("", 22, GOLD, true)
	cap.add_child(banner_title)
	banner_note = ui._label("", 12, INK)
	banner_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.add_child(banner_note)
	seal = ui._label("", 30, Color(1.0, 0.5, 0.35), true)
	seal.set_anchors_preset(Control.PRESET_FULL_RECT)
	seal.offset_bottom = -110
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_clip.add_child(seal)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(ui._label("THE ROUTE", 13, DIM, true))
	var rwrap := Control.new()
	rwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(rwrap)
	route_line = Control.new()
	route_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	route_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_line.draw.connect(_draw_route)
	rwrap.add_child(route_line)
	route_box = VBoxContainer.new()
	route_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	route_box.add_theme_constant_override("separation", 14)
	rwrap.add_child(route_box)
	next_box = VBoxContainer.new()
	right.add_child(next_box)

## Show the window on the act you are in.
func open(from: Node3D = null) -> void:
	stone = from
	sel_run = int(game.difficulty)
	_fill()
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.14)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2)
	Sfx.play("portal", -10.0, 1.3)

func close() -> void:
	visible = false
	stone = null
	ui.tooltip.visible = false
	ui.tip_owner = null

func _act_name(run: int) -> String:
	return str(Data.RUNS[clampi(run, 0, Data.RUNS.size() - 1)]["name"])

func _fill() -> void:
	here_icons.clear()
	for c in tabs_box.get_children():
		c.queue_free()
	for a in Data.WAYPOINT_ACTS:
		tabs_box.add_child(_tab(a))
	var act: Dictionary = Data.waypoint_act(sel_run)
	var info: Dictionary = Data.act_info(0, sel_run)
	var open_act: bool = game.act_unlocked(sel_run)
	banner.texture = load(act["art"]) if act.has("art") and ResourceLoader.exists(act["art"]) else null
	banner.modulate = Color(1, 1, 1) if open_act else Color(0.32, 0.3, 0.3)
	banner_sub.text = _act_name(sel_run).to_upper() + ("   ·   YOU ARE HERE" if sel_run == int(game.difficulty) else "")
	banner_title.text = str(info["name"])
	banner_note.text = game.run_note(sel_run)
	seal.visible = not open_act
	seal.text = "SEALED"
	for c in route_box.get_children():
		c.queue_free()
	if not open_act:
		route_box.add_child(_sealed_card(Data.waypoint_act(sel_run - 1)))
	if open_act:
		var pts: Array = act["points"]
		for i in pts.size():
			route_box.add_child(_point_row(act, pts[i], info))
		route_box.add_child(_lair_row(act, info))
	for c in next_box.get_children():
		c.queue_free()
	var nxt: Dictionary = Data.waypoint_act(sel_run + 1)
	if open_act and not nxt.is_empty():
		next_box.add_child(_next_card(act, nxt))
	route_line.queue_redraw()

func _boss_name(act: Dictionary) -> String:
	var b: String = act.get("boss", "")
	return str(Data.ENEMIES[b]["name"]) if Data.ENEMIES.has(b) else "its lord"

## One act's tab: a bar socket with the act's numeral; gold when selected, a cyan glow on the act you
## are in, dark and sealed until it is open.
func _tab(a: Dictionary) -> Control:
	var run: int = a["run"]
	var opened: bool = game.act_unlocked(run)
	var here := run == int(game.difficulty)
	var sel := run == sel_run
	var t := PanelContainer.new()
	var st := ui._box(Color(0.12, 0.09, 0.05, 0.95) if sel else Color(0.05, 0.04, 0.03, 0.9),
		GOLD if sel else (Color(0.42, 0.33, 0.2) if opened else Color(0.22, 0.2, 0.18)), 2 if sel else 1, 6, 6)
	if here:
		st.shadow_color = Color(CYAN, 0.35)
		st.shadow_size = 8
	t.add_theme_stylebox_override("panel", st)
	t.custom_minimum_size = Vector2(150, 0)
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(hb)
	var sock := TextureRect.new()
	sock.texture = load(SLOT)
	sock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sock.stretch_mode = TextureRect.STRETCH_SCALE
	sock.custom_minimum_size = Vector2(42, 44)
	sock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sock)
	var num := ui._label(str(a["tab"]), 17, (Color(1.0, 0.88, 0.55) if sel else GOLD) if opened else Color(0.4, 0.38, 0.35), true)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sock.add_child(num)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	tv.add_child(ui._label(_act_name(run), 15, INK if opened else Color(0.45, 0.42, 0.38), true))
	var sub := "you are here" if here else ("open" if opened else "sealed")
	tv.add_child(ui._label(sub, 11, CYAN if here else (DIM if opened else Color(0.6, 0.35, 0.3))))
	t.mouse_entered.connect(func():
		var lines := [[_act_name(run) + "  ·  " + str(Data.act_info(0, run)["name"]), GOLD]]
		if not opened:
			lines.append(["Slay %s in %s to open it" % [_boss_name(Data.waypoint_act(run - 1)), _act_name(run - 1)], Color(1.0, 0.55, 0.4)])
		else:
			lines.append([game.run_note(run), INK])
		ui.show_tooltip(lines)
		ui.tip_owner = t)
	t.mouse_exited.connect(func():
		ui.tooltip.visible = false
		ui.tip_owner = null)
	t.gui_input.connect(func(ev):
		if ev is InputEvent and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and run != sel_run:
			sel_run = run
			Sfx.play("click")
			_fill())
	return t

## One waypoint on the route: its sigil (lit once bound), its place, and where it takes you.
func _point_row(act: Dictionary, p: Dictionary, info: Dictionary) -> Control:
	var run: int = act["run"]
	var zone: String = p["zone"]
	var known: bool = game.waypoint_known(run, str(p["id"]))
	var here: bool = run == int(game.difficulty) and zone == str(game.cur_zone)
	var pname: String = p.get("name", info.get(zone, zone.capitalize()))
	var row := PanelContainer.new()
	var idle := ui._box(Color(0.06, 0.05, 0.04, 0.85), Color(0.3, 0.24, 0.15), 1, 6, 6)
	var hot := ui._box(Color(0.1, 0.16, 0.2, 0.9), CYAN, 1, 6, 6)
	row.add_theme_stylebox_override("panel", idle)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if known and not here else Control.CURSOR_ARROW
	row.set_meta("node", true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)
	var icon := TextureRect.new()
	icon.texture = load(SIGIL)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	icon.pivot_offset = Vector2(22, 22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1, 1, 1) if known else Color(0.25, 0.25, 0.28)
	hb.add_child(icon)
	if here:
		here_icons.append(icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	tv.add_child(ui._label(pname if known else "Unknown waypoint", 16, INK if known else Color(0.45, 0.42, 0.38), true))
	var kinds := {"camp": "Camp · safe haven", "wild": "Wilderness", "road": "The open road", "city": "City"}
	tv.add_child(ui._label(str(kinds.get(p.get("kind", ""), "")) if known else "Find and touch its stone", 11, DIM))
	var tag := ui._label("HERE" if here else ("TRAVEL ›" if known else ""), 12, CYAN if here else GOLD, true)
	hb.add_child(tag)
	row.mouse_entered.connect(func():
		if known and not here:
			row.add_theme_stylebox_override("panel", hot)
			icon.create_tween().tween_property(icon, "scale", Vector2(1.12, 1.12), 0.1)
		var lines := [[pname if known else "Unknown waypoint", GOLD]]
		if here:
			lines.append(["You are standing at this waypoint", CYAN])
		elif known:
			lines.append(["Click to travel there" + ("" if run == int(game.difficulty) else " (switches to " + _act_name(run) + ")"), INK])
		else:
			lines.append(["You haven't touched this waypoint's stone yet", DIM])
		ui.show_tooltip(lines)
		ui.tip_owner = row)
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", idle)
		icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.12)
		ui.tooltip.visible = false
		ui.tip_owner = null)
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if not known or here:
				Sfx.play("deny")
				return
			_jump(run, zone, icon))
	return row

## The end of the route: the act's lair, reached on foot; shows whether its lord still rules.
func _lair_row(act: Dictionary, info: Dictionary) -> Control:
	var slain: bool = game.act_boss_slain(int(act["run"]))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", ui._box(Color(0.08, 0.03, 0.02, 0.6), Color(0.45, 0.18, 0.12) if not slain else Color(0.3, 0.45, 0.25), 1, 6, 6))
	row.set_meta("node", true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	var mark := ui._label("✝" if slain else "☠", 26, Color(0.55, 0.9, 0.55) if slain else Color(0.95, 0.4, 0.3), true)
	mark.custom_minimum_size = Vector2(44, 44)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(mark)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(tv)
	var lair: String = "Throne of the Ashen King" if int(act["run"]) >= 2 else str(info.get("lair", "The lair"))
	tv.add_child(ui._label(lair, 15, INK, true))
	tv.add_child(ui._label(("Slain: " if slain else "Lord: ") + _boss_name(act) + "  ·  reached on foot", 11, DIM))
	return row

## A sealed act's route: what opens it.
func _sealed_card(prev: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ui._box(Color(0.08, 0.03, 0.02, 0.75), Color(0.5, 0.2, 0.14), 1, 6, 12))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	card.add_child(tv)
	tv.add_child(ui._label("THIS ACT IS SEALED", 14, Color(1.0, 0.5, 0.35), true))
	var l := ui._label("Slay %s in %s to open it. Its waypoints then wait to be found, one stone at a time." % [_boss_name(prev), _act_name(int(prev.get("run", 0)))], 13, INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(l)
	return card

## Where the road leads after this act: the next act's tab, open or sealed by this act's lord.
func _next_card(act: Dictionary, nxt: Dictionary) -> Control:
	var run: int = nxt["run"]
	var opened: bool = game.act_unlocked(run)
	var card := PanelContainer.new()
	var idle := ui._box(Color(0.05, 0.04, 0.03, 0.85), Color(0.42, 0.33, 0.2) if opened else Color(0.3, 0.15, 0.1), 1, 6, 8)
	var hot := ui._box(Color(0.12, 0.09, 0.05, 0.95), GOLD, 1, 6, 8)
	card.add_theme_stylebox_override("panel", idle)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	var thumb := TextureRect.new()
	thumb.texture = load(nxt["art"]) if ResourceLoader.exists(nxt["art"]) else null
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.custom_minimum_size = Vector2(76, 48)
	thumb.modulate = Color(1, 1, 1) if opened else Color(0.3, 0.28, 0.28)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(thumb)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	tv.add_child(ui._label("NEXT  ·  " + _act_name(run).to_upper(), 11, CYAN if opened else Color(0.85, 0.45, 0.35), true))
	tv.add_child(ui._label(str(Data.act_info(0, run)["name"]), 15, INK if opened else DIM, true))
	tv.add_child(ui._label("Open: pick its tab above" if opened else "Sealed until %s falls" % _boss_name(act), 11, DIM))
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hot))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", idle))
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			sel_run = run
			Sfx.play("click")
			_fill())
	return card

## The dotted road joining the route's sigils, top to bottom.
func _draw_route() -> void:
	var pts := []
	for c in route_box.get_children():
		if c is Control and (c as Control).has_meta("node") and not (c as Control).is_queued_for_deletion():
			var r := (c as Control).get_rect()
			pts.append(Vector2(r.position.x + 6 + 22, r.position.y + r.size.y * 0.5))
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 7.0)
		for k in n:
			if k % 2 == 0:
				route_line.draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(GOLD, 0.8), 2.5)

## Take the waypoint: the sigils spin up, a flash, then the journey.
func _jump(run: int, zone: String, icon: Control) -> void:
	_spin = 14.0
	Sfx.play("portal")
	var tw := icon.create_tween()
	tw.tween_property(icon, "modulate", Color(2.2, 2.6, 3.0), 0.12)
	tw.tween_property(icon, "modulate", Color(1, 1, 1), 0.2)
	await get_tree().create_timer(0.28).timeout
	close()
	game.waypoint_go(run, zone)

func _process(delta: float) -> void:
	if not visible:
		return
	# stepped away from the stone (or it is gone, after travel): close, as walking off from a stall would
	if stone != null:
		var h = game.hero
		if not is_instance_valid(stone) or h == null or h.global_position.distance_to(stone.global_position) > 4.5:
			close()
			return
	_t += delta
	_spin = move_toward(_spin, 0.0, delta * 18.0)
	sigil.rotation += delta * (0.35 + _spin)
	sigil.modulate = Color(1, 1, 1).lerp(Color(1.4, 1.6, 1.8), 0.5 + 0.5 * sin(_t * 2.2))
	for ic in here_icons:
		if is_instance_valid(ic):
			(ic as Control).rotation += delta * 0.8
			(ic as Control).modulate = Color(1, 1, 1).lerp(Color(1.6, 1.9, 2.2), 0.5 + 0.5 * sin(_t * 3.0))
	# the banner drifts slowly, a little alive
	if banner_clip.size.x > 0:
		var z := 1.06 + 0.03 * sin(_t * 0.25)
		banner.size = banner_clip.size * z
		banner.position = -(banner.size - banner_clip.size) * 0.5 + Vector2(sin(_t * 0.17) * 6.0, cos(_t * 0.13) * 4.0)
	route_line.queue_redraw()
