class_name WaypointPanel
extends PanelContainer
## The waypoint window: a tab per act (Data.WAYPOINT_ACTS), its Meshy banner, and the act's route of
## waypoints. Built in the action bar's iron frame and sockets. An act's tab opens once the act before
## it falls (Game.act_unlocked); a waypoint lights once a player has touched its stone
## (Game.waypoint_known). Click a lit waypoint to go there, in this act or another (Game.waypoint_go).
## Everything it shows comes from Data and Game, so a new act or waypoint needs no change here.

const SIGIL := "res://assets/textures/ui/wp_sigil.png"
const TOWN_PLAQUE := "res://assets/textures/ui/wp_town.png"
const FRAME := "res://assets/textures/ui/bar_frame.png"
const SLOT := "res://assets/textures/ui/slot.png"
const CYAN := Color(0.45, 0.85, 1.0)
const GOLD := Color(0.86, 0.72, 0.44)
const DIM := Color(0.62, 0.58, 0.52)
const INK := Color(0.9, 0.87, 0.8)
const CRYPT := Color(0.42, 0.62, 1.0)     # the Hollow Crypt's cold rune light (the Battlegrounds card's accent)
const RISK := Color(1.0, 0.5, 0.35)       # the stakes, the seal's red

var ui: UI
var game: Node
var sel_run := 0
var _t := 0.0
var _spin := 0.0             # extra sigil spin after a click (the jump)
var sigil: TextureRect
var tabs_box: HBoxContainer
var groups_box: HBoxContainer
var sel_group := "acts"
var acts_override: Array = []   # screenshots only: sample future acts in place of Data.WAYPOINT_ACTS
var banner_clip: Control
var banner: TextureRect
var banner_title: Label
var banner_sub: Label
var banner_note: Label
var next_box: VBoxContainer
var seal: Label
var route_box: VBoxContainer
var route_head: Label         # "THE ROUTE" over an act's stops, "THE DESCENT" over the raids
var route_line: Control
var route_stack: Control      # holds the road and the stops; sized to the stops so the route scrolls
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
	# --- the tab groups (Acts, Ancient Levels, ...: shown once there is more than one) and the act tabs,
	# in a row that scrolls sideways when more acts are added than fit
	groups_box = HBoxContainer.new()
	groups_box.add_theme_constant_override("separation", 18)
	vb.add_child(groups_box)
	var tscroll := ScrollContainer.new()
	tscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tscroll.custom_minimum_size = Vector2(0, 58)
	vb.add_child(tscroll)
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 10)
	tscroll.add_child(tabs_box)
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
	route_head = ui._label("THE ROUTE", 13, DIM, true)
	right.add_child(route_head)
	# the route scrolls when an act has more waypoints than fit; the road is drawn behind the stops
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	route_stack = Control.new()
	route_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	rscroll.add_child(route_stack)
	var rwrap := route_stack
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
	sel_group = str(_act(sel_run).get("group", "acts"))
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
	_probe_stop()
	ui.tooltip.visible = false
	ui.tip_owner = null

## The act whose lord opens act `run`: its "requires", else the act before it.
func _opener(run: int) -> int:
	return int(_act(run).get("requires", run - 1))

func _acts() -> Array:
	return acts_override if not acts_override.is_empty() else Data.WAYPOINT_ACTS

func _act(run: int) -> Dictionary:
	for a in _acts():
		if int(a["run"]) == run:
			return a
	return {}

## An act's name: its entry's "name", else its run's (Data.RUNS).
func _act_name(run: int) -> String:
	var a := _act(run)
	if a.has("name"):
		return str(a["name"])
	return str(Data.RUNS[clampi(run, 0, Data.RUNS.size() - 1)]["name"])

func _fill() -> void:
	here_icons.clear()
	bg_icons.clear()
	probe_lbl = null
	_probe_stop()
	route_head.text = "THE ROUTE"
	for c in tabs_box.get_children():
		c.queue_free()
	for c in groups_box.get_children():
		c.queue_free()
	var used := []
	for a in _acts():
		if not used.has(a.get("group", "acts")):
			used.append(a.get("group", "acts"))
	if acts_override.is_empty() and not Data.WAYPOINT_BATTLEGROUNDS.is_empty():
		used.append("battlegrounds")
	groups_box.visible = used.size() > 1
	for gdef in Data.WAYPOINT_GROUPS:
		if used.has(gdef["id"]):
			groups_box.add_child(_group_tab(gdef))
	if sel_group == "battlegrounds":
		_fill_battlegrounds()
		return
	for a in _acts():
		if str(a.get("group", "acts")) == sel_group:
			tabs_box.add_child(_tab(a))
	var act: Dictionary = _act(sel_run)
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
		route_box.remove_child(c)
		c.queue_free()
	if not open_act:
		route_box.add_child(_sealed_card(_act(_opener(sel_run))))
	if open_act:
		var pts: Array = act["points"]
		for i in pts.size():
			route_box.add_child(_point_row(act, pts[i], info))
		route_box.add_child(_lair_row(act, info))
	for c in next_box.get_children():
		c.queue_free()
	var nxt: Dictionary = _act(sel_run + 1)
	if open_act and not nxt.is_empty():
		next_box.add_child(_next_card(act, nxt))
	_size_route.call_deferred()
	route_line.queue_redraw()

## The Battlegrounds group: no act tabs or route. The banner shows the raid's painting (the first entry's art) and
## the right column holds a card per battleground (Data.WAYPOINT_BATTLEGROUNDS), each a way down from this dais.
func _fill_battlegrounds() -> void:
	var first: Dictionary = Data.WAYPOINT_BATTLEGROUNDS[0] if not Data.WAYPOINT_BATTLEGROUNDS.is_empty() else {}
	banner.texture = load(first["art"]) if first.has("art") and ResourceLoader.exists(first["art"]) else null
	banner.modulate = Color(1, 1, 1)
	banner_sub.text = "BATTLEGROUNDS   ·   A SHARED SERVER"
	banner_title.text = str(first.get("name", "Battlegrounds"))
	banner_note.text = "Raids where other heroes hunt too. What you carry down is at stake; your levels, talents and the camp's stash never are."
	seal.visible = false
	route_head.text = "THE DESCENT"
	for c in route_box.get_children():
		route_box.remove_child(c)
		c.queue_free()
	for c in next_box.get_children():
		c.queue_free()
	for b in Data.WAYPOINT_BATTLEGROUNDS:
		route_box.add_child(_bg_card(b))
	# a word on where it ends: the way back is the same dais
	var back := PanelContainer.new()
	back.add_theme_stylebox_override("panel", ui._box(Color(0.05, 0.04, 0.03, 0.7), Color(0.3, 0.24, 0.15), 1, 6, 8))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	back.add_child(bh)
	var bi := TextureRect.new()
	bi.texture = load(SIGIL)
	bi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bi.custom_minimum_size = Vector2(32, 32)
	bi.modulate = Color(0.6, 0.6, 0.65)
	bh.add_child(bi)
	var bt := VBoxContainer.new()
	bt.add_theme_constant_override("separation", 0)
	bt.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_child(bt)
	bt.add_child(ui._label("The way back is this waypoint", 13, INK, true))
	bt.add_child(ui._label("Extracted or fallen, %s returns to this dais" % game.char_name, 11, DIM))
	route_box.add_child(back)
	_probe_start(game.bg_server_address())
	_size_route.call_deferred()
	route_line.queue_redraw()

## One battleground, laid out like a route stop: its sigil and name with a RAID plaque, the mode and the round's
## numbers (Battlegrounds' constants), what the place is, the stakes in plain words, the character going down and
## what they carry, the server and whether it answers (the probe), and Descend. Hover lights it like a stop; the
## button or a click on the card asks Game.waypoint_battleground (a last word on the stakes, then the way down).
func _bg_card(b: Dictionary) -> Control:
	var h = game.hero
	var in_coop: bool = game.net.active
	var card := PanelContainer.new()
	var idle := ui._box(Color(0.06, 0.05, 0.04, 0.9), Color(0.3, 0.24, 0.15), 1, 6, 10)
	var hot := ui._box(Color(0.08, 0.1, 0.16, 0.94), CRYPT, 1, 6, 10)
	card.add_theme_stylebox_override("panel", idle)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if in_coop else Control.CURSOR_POINTING_HAND
	card.set_meta("node", true)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	# the head: the sigil (slowly turning, in the crypt's cold light), the name, the plaque, and the tag
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	var icon := TextureRect.new()
	icon.texture = load(SIGIL)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	icon.pivot_offset = Vector2(22, 22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(0.75, 0.85, 1.0)
	head.add_child(icon)
	bg_icons.append(icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tv)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(nrow)
	nrow.add_child(ui._label(str(b["name"]), 16, INK, true))
	nrow.add_child(_plaque("RAID", Color(0.95, 0.5, 0.4)))
	var mins := int(Battlegrounds.RAID_SECS / 60.0)
	var pmins := int(Battlegrounds.PORTALS_AT / 60.0)
	tv.add_child(ui._label("%s  ·  up to %d raiders  ·  rounds of %d min, the portals open after %d" % [str(b.get("kind", "Raid")), Battlegrounds.MAX_PLAYERS, mins, pmins], 11, DIM))
	var tag := ui._label("IN CO-OP" if in_coop else "DESCEND ›", 12, DIM if in_coop else CRYPT, true)
	head.add_child(tag)
	# the place
	for line in b.get("lines", []):
		var l := ui._label(str(line), 12, INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
	# the stakes, in plain words
	var risk := ui._label("☠  Fall down there and every item you wear and carry, your belt and your gold stay on the crypt floor. Your levels, stats, talents and the camp's stash are safe.", 12, RISK, true)
	risk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	risk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(risk)
	# who goes down, and with what
	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(rule)
	var worn := 0
	for slot in h.equipment:
		if h.equipment[slot] != null:
			worn += 1
	var carried := 0
	for it in h.inventory + h.belt:
		if it != null:
			carried += 1
	var stashed: int = game.stash.count() if game.stash != null else 0      # (the shared stash, SharedStash)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(who)
	var cls_name := str(Data.CLASSES.get(h.cls, {}).get("name", h.cls))
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(wv)
	wv.add_child(ui._label("%s  ·  level %d %s" % [game.char_name, h.level, cls_name], 13, GOLD, true))
	wv.add_child(ui._label("At stake: %d worn, %d in the bag and belt, %d gold" % [worn, carried, h.gold], 11, INK))
	wv.add_child(ui._label("Safe in the stash (all your characters'): %d item%s" % [stashed, "" if stashed == 1 else "s"], 11, DIM))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	sv.alignment = BoxContainer.ALIGNMENT_END
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(sv)
	var addr: String = game.bg_server_address()
	var server_name := "the %s server" % BuildEnv.env() if BuildEnv.env() != "local" else addr
	sv.add_child(ui._label("Server  ·  " + server_name, 11, DIM))
	probe_lbl = ui._label("checking...", 11, DIM)
	probe_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sv.add_child(probe_lbl)
	# the way down
	if in_coop:
		var why := ui._label("Leave co-op to go down: the party's host would lose you mid-act.", 12, RISK)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(why)
	else:
		var go := Button.new()
		go.text = "Descend into %s" % str(b["name"])
		go.custom_minimum_size = Vector2(0, 38)
		go.focus_mode = Control.FOCUS_NONE
		go.pressed.connect(func(): _descend(str(b["id"]), icon))
		vb.add_child(go)
	card.mouse_entered.connect(func():
		if not in_coop:
			card.add_theme_stylebox_override("panel", hot)
			icon.create_tween().tween_property(icon, "scale", Vector2(1.12, 1.12), 0.1)
		var lines := [[str(b["name"]), GOLD], ["A shared server: other raiders are down there with you", INK]]
		if in_coop:
			lines.append(["Leave co-op to go down", RISK])
		else:
			lines.append(["Click to descend with %s (you will be asked first)" % game.char_name, INK])
			lines.append(["Death costs everything worn and carried", RISK])
		ui.show_tooltip(lines)
		ui.tip_owner = card)
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", idle)
		icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.12)
		ui.tooltip.visible = false
		ui.tip_owner = null)
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if in_coop:
				Sfx.play("deny")
				return
			_descend(str(b["id"]), icon))
	# every line of text wraps (the name, its plaque and the tag excepted): an unwrapped line sets the card's
	# minimum width, and wider than its column the card was clipped, text and button cut off at the right
	for n in card.find_children("*", "Label", true, false):
		var lb: Label = n
		if lb.get_parent() == nrow or lb == tag or lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
			continue
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = 60.0
	return card

## Down we go: the sigil flashes, the window closes and Game asks its last word (then the dais flares).
func _descend(id: String, icon: Control) -> void:
	_spin = 10.0
	Sfx.play("click")
	var tw := icon.create_tween()
	tw.tween_property(icon, "modulate", Color(2.0, 2.4, 3.0), 0.1)
	tw.tween_property(icon, "modulate", Color(0.75, 0.85, 1.0), 0.2)
	await get_tree().create_timer(0.2).timeout
	close()
	game.waypoint_battleground(id)

## A small plaque like the town's, with its own word and colour (the Meshy gold nameplate behind).
func _plaque(word: String, col: Color) -> Control:
	var plq := _town_plaque()
	var t: Label = plq.get_child(0)
	t.text = word
	t.add_theme_color_override("font_color", col)
	return plq

# ---------------------------------------------------------------- is the raid server there?
## A cheap look at the server before anyone goes down: an ENet connection attempt (the raid's own protocol) that is
## dropped the moment the handshake answers. The game server rejects a peer with no player id before any player
## hears of it, so nobody in the raid sees a thing. Three seconds without an answer is "no answer". Not from a
## browser (no UDP there).
const PROBE_SECS := 3.0
var probe: ENetConnection = null
var probe_t := 0.0
var probe_state := ""          # "" | "checking" | "ok" | "fail" | "web"
var probe_lbl: Label = null
var bg_icons: Array = []       # the raid cards' sigils, turning slowly

func _probe_start(addr: String) -> void:
	_probe_stop()
	probe_t = 0.0
	if OS.has_feature("web"):
		probe_state = "web"
		_probe_show()
		return
	var a: Array = Battlegrounds.parse_address(addr)
	var c := ENetConnection.new()
	if c.create_host(1) != OK:
		probe_state = "fail"
		_probe_show()
		return
	var peer: ENetPacketPeer = c.connect_to_host(str(a[0]), int(a[1]), 1, 0)
	if peer == null:
		c.destroy()
		probe_state = "fail"
		_probe_show()
		return
	probe = c
	probe_state = "checking"
	_probe_show()

func _probe_stop() -> void:
	if probe != null:
		for p in probe.get_peers():
			(p as ENetPacketPeer).peer_disconnect_now(0)
		probe.destroy()
		probe = null

func _probe_poll(delta: float) -> void:
	if probe == null:
		return
	probe_t += delta
	var ev: Array = probe.service(0)
	var kind: int = int(ev[0])
	if kind == ENetConnection.EVENT_CONNECT:
		probe_state = "ok"
		_probe_stop()
	elif kind == ENetConnection.EVENT_DISCONNECT or kind == ENetConnection.EVENT_ERROR or probe_t > PROBE_SECS:
		probe_state = "fail"
		_probe_stop()
	_probe_show()

func _probe_show() -> void:
	if probe_lbl == null or not is_instance_valid(probe_lbl):
		return
	match probe_state:
		"ok":
			probe_lbl.text = "answering  ●"
			probe_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		"fail":
			probe_lbl.text = "no answer  ●"
			probe_lbl.add_theme_color_override("font_color", RISK)
		"web":
			probe_lbl.text = "not from a browser"
			probe_lbl.add_theme_color_override("font_color", RISK)
		_:
			probe_lbl.text = "checking..."
			probe_lbl.add_theme_color_override("font_color", DIM)

func _boss_name(act: Dictionary) -> String:
	var b: String = act.get("boss", "")
	return str(Data.ENEMIES[b]["name"]) if Data.ENEMIES.has(b) else "its lord"

## A tab group's heading (ACTS | ANCIENT LEVELS): picks which acts' tabs show; gold underline when chosen.
func _group_tab(gdef: Dictionary) -> Control:
	var gid: String = gdef["id"]
	var on := gid == sel_group
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_STOP
	vb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var l := ui._label(str(gdef["name"]).to_upper(), 13, GOLD if on else DIM, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	var bar := ColorRect.new()
	bar.color = GOLD if on else Color(0, 0, 0, 0)
	bar.custom_minimum_size = Vector2(0, 2)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bar)
	vb.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and gid != sel_group:
			sel_group = gid
			for a in _acts():
				if str(a.get("group", "acts")) == gid:
					sel_run = int(a["run"])
					break
			Sfx.play("click")
			_fill())
	return vb

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
	t.custom_minimum_size = Vector2(140, 0)
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
			lines.append(["Slay %s in %s to open it" % [_boss_name(_act(_opener(run))), _act_name(_opener(run))], Color(1.0, 0.55, 0.4)])
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
	var at: String = game._at_waypoint()
	var here: bool = run == int(game.difficulty) and (str(p["id"]) == at if at != "" else zone == str(game.cur_zone))
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
	# the name, with the act's town marked in small print beside it
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(nrow)
	nrow.add_child(ui._label(pname if known else "Unknown waypoint", 16, INK if known else Color(0.45, 0.42, 0.38), true))
	if p.get("kind", "") == "camp":
		nrow.add_child(_town_plaque())
	var kinds := {"camp": "Safe haven · traders and stash", "wild": "Wilderness", "road": "The open road", "city": "City"}
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
			_jump(run, str(p["id"]), icon))
	return row

## The town badge: the Meshy gold nameplate (castle gate on the left) with TOWN set on its plate.
func _town_plaque() -> Control:
	var plq := TextureRect.new()
	plq.texture = load(TOWN_PLAQUE)
	plq.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plq.stretch_mode = TextureRect.STRETCH_SCALE
	plq.custom_minimum_size = Vector2(112, 32)
	plq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := ui._label("TOWN", 13, Color(1.0, 0.86, 0.5), true)
	t.add_theme_constant_override("outline_size", 4)
	t.add_theme_color_override("font_outline_color", Color(0.12, 0.02, 0.02))
	t.anchor_left = 0.3
	t.anchor_right = 0.9
	t.anchor_bottom = 1.0
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plq.add_child(t)
	return plq

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

func _size_route() -> void:
	route_stack.custom_minimum_size = Vector2(0, route_box.get_combined_minimum_size().y + 4)

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
func _jump(run: int, id: String, icon: Control) -> void:
	_spin = 14.0
	Sfx.play("portal")
	var tw := icon.create_tween()
	tw.tween_property(icon, "modulate", Color(2.2, 2.6, 3.0), 0.12)
	tw.tween_property(icon, "modulate", Color(1, 1, 1), 0.2)
	await get_tree().create_timer(0.28).timeout
	close()
	game.waypoint_go(run, id)

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
	for ic in bg_icons:
		if is_instance_valid(ic):
			(ic as Control).rotation -= delta * 0.45      # the crypt's sigil turns the other way, slowly, in a cold light
	_probe_poll(delta)
	# the banner drifts slowly, a little alive
	if banner_clip.size.x > 0:
		var z := 1.06 + 0.03 * sin(_t * 0.25)
		banner.size = banner_clip.size * z
		banner.position = -(banner.size - banner_clip.size) * 0.5 + Vector2(sin(_t * 0.17) * 6.0, cos(_t * 0.13) * 4.0)
	route_line.queue_redraw()
