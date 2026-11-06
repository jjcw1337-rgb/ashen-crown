class_name MpLobbyView
extends Control
## The multiplayer screen (Blaine's overhaul, 2026-11-06: "Valorant's title, lobby and character-selection
## presentation ... translated into our own fantasy identity"), in MpStyle. One screen, two states:
##   browse   the mode's painted art full screen, the mode tabs (Battlegrounds, Arena) along the top, the mode's
##            name and how it plays on the left with Create Lobby, the open lobbies on the right (filters; loading,
##            empty, full and failure states)
##   prepare  inside a lobby: the chosen class (or survivor) large on the left over the title's gate, where the
##            hero stands in the dusk light; on the right the lobby, every member's class and ready state, the
##            class tiles (or the survivors) and Ready / Start / Leave
## LobbyClient keeps the logic (requests, polling, joining matches); this draws it (`render`).

const ART = preload("res://scripts/content_catalog.gd").LOBBY_ART
const MODE_TITLE := {"battlegrounds": "Battlegrounds", "arena": "Arena", "sandbox": "Sandbox"}
const MODE_LINE := {
	"battlegrounds": "Start from nothing in the Verdant Reach. Clear camps, build your hero, and get out alive.",
	"arena": "Your survivors, as they left the Battlegrounds, in team fights of 1v1, 2v2 or 3v3.",
	"sandbox": "Try any class and build. Practice solo with bots or host a free-for-all with friends."}
## How a mode plays, in order (a real sequence, so it's numbered).
const MODE_STEPS := {
	"battlegrounds": ["Pick a class. You start at level 0 with only your basic attack.",
		"Clear a camp to open its chest: gear, potions, and one upgrade of three for you.",
		"Reach an open Extraction Portal alive, then save the character as a survivor."],
	"arena": ["Choose one of your survivors. Its skills, passives and gear come as saved.",
		"Join a team. Best of three rounds; the first team to win two takes the match.",
		"Losing never deletes a survivor."],
	"sandbox": ["Choose a temporary hero. Change class, level and gear during practice.",
		"Play solo with bots and monster packs, or host up to six players with automatic respawns.",
		"No stakes or rewards. Your saved characters stay unchanged."]}
## A class's playstyle in a line (the lobby's class presentation).
const PLAYSTYLE := {
	"knight": ["Frontline", "Sword and shield, holy fire and a rallying cry. Holds the line and hits hard up close."],
	"wraith": ["Assassin", "A floating spirit that rends, drains through a tether and steps through shadow."],
	"demon": ["Bruiser", "A magma brute: heavy slams, a charge that stops on its prey, a counter-stance."],
	"archer": ["Ranged", "Shoots on the move with fire, frost and storm arrows. A dire wolf fights at his side."],
	"plague": ["Control", "Poison vials, a fly swarm, a rooting corpse flower and a fog to vanish in."],
	"warlock": ["Caster", "Drains life down a forking beam, rots foes with blight and chains them in place."],
	"doug": ["Trickster", "Every gag is a weapon: pies that blind, peels that trip, a clown car nobody sees coming."],
	"wyrm": ["Dragon", "A heavy obsidian dragon that rakes, bites and sweeps its tail through crowds."],
	"serpent": ["Dragon", "A long ice dragon: frost breath and a shell of ice to hide in."],
	"wyvern": ["Dragon", "A storm dragon that chains lightning and dodges by taking to the air."]}

var lc
var game
var ui
var art: TextureRect
var shade: ColorRect
var tabs := {}
var left: VBoxContainer
var right: VBoxContainer
var bottom: HBoxContainer
var survivors_btn: Button
## Browse filters (kept while the screen is open).
var joinable_only := false
var _root: Control
## The left column's room (the window less the panel and margins), set by _fit: text there wraps to it.
var col_w := 620.0
## What the screen last showed ("browse:battlegrounds", "prep:arena"...): a change fades the columns in.
var _shown := ""

func setup(client) -> void:
	lc = client
	game = client.game
	ui = game.ui
	name = "multiplayer_lobbies"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	shade = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	# dark where the panels sit (right, top, bottom), clear on the left where the art or the hero shows
	sh.code = """shader_type canvas_item;
uniform float strength = 1.0;
void fragment() {
	float r = smoothstep(0.35, 0.72, UV.x) * 0.82;
	float t = (1.0 - smoothstep(0.0, 0.16, UV.y)) * 0.75;
	float b = smoothstep(0.6, 1.0, UV.y) * 0.7;
	COLOR = vec4(0.04, 0.05, 0.05, clamp(max(max(r, t), b) * strength + 0.12 * strength, 0.0, 0.94));
}"""
	sm.shader = sh
	shade.material = sm
	add_child(shade)
	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		_root.add_theme_constant_override(m, 48)
	_root.add_theme_constant_override("margin_top", 28)
	_root.add_theme_constant_override("margin_bottom", 24)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vb)
	vb.add_child(_topbar())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
	left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var rp := MpStyle.panel(Color(0.067, 0.075, 0.082, 0.9), Color(1, 1, 1, 0.08), 10, 22)
	rp.custom_minimum_size.x = 600
	body.add_child(rp)
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	rp.add_child(right)
	bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	# the client's handles (its logic and the old tests use them)
	lc.status = MpStyle.label("", 14, MpStyle.GOLD, 600)
	lc.status.name = "status"
	lc.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lc.status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.lan_row = HBoxContainer.new()
	lc.lan_row.name = "lan_row"
	lc.lan_row.add_theme_constant_override("separation", 8)
	lc.lan_row.add_child(MpStyle.label("Local network", 13, MpStyle.FAINT, 600))
	var lh := MpStyle.button("Host LAN game")
	lh.name = "lan_host"
	lh.pressed.connect(func(): ui.home.lan_host())
	lc.lan_row.add_child(lh)
	var lj := MpStyle.button("Join LAN / address")
	lj.name = "lan_join"
	lj.pressed.connect(func(): ui.home.lan_join())
	lc.lan_row.add_child(lj)
	bottom.add_child(lc.lan_row)
	bottom.add_child(lc.status)
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_fit)
	_fit()

## Where the hero stands on the title's stage while a lobby is prepared: a little left of the screen's middle, clear
## of the panel (TitleStage._frame reads it; screen pixels from the centre at 1440 wide).
const STAGE_MID := -90.0

func _fit() -> void:
	# the whole window (the menus layer isn't laid out for a late full-rect child); below 1280 wide the panel narrows
	position = Vector2.ZERO
	size = get_viewport_rect().size
	var w := size.x
	var pw := clampf(w * 0.36, 420.0, 640.0)
	var m := int(clampf(w * 0.025, 16.0, 48.0))
	if right != null and right.get_parent() != null:
		(right.get_parent() as Control).custom_minimum_size.x = pw
	if _root != null:
		_root.add_theme_constant_override("margin_left", m)
		_root.add_theme_constant_override("margin_right", m)
	col_w = maxf(260.0, w - pw - m * 2.0 - 40.0 - 36.0)      # (the body's gap, and slack for the panel's own padding)
	if visible and lc != null:
		render()

## A display size that shrinks on narrow windows (the big mode and class names).
func _big(px: int) -> int:
	return int(clampf(px * col_w / 640.0, px * 0.55, px))

func _topbar() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.add_child(MpStyle.eyebrow("Ashen Crown"))
	brand.add_child(MpStyle.label("Multiplayer", 30, MpStyle.IVORY, 700, true))
	hb.add_child(brand)
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	hb.add_child(gap)
	for mode in MpMode.MODES:
		var b := Button.new()
		b.name = "tab_" + mode
		b.text = MODE_TITLE.get(mode, mode).to_upper()
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", MpStyle.font(700, true))
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func():
			if lc.room.is_empty():
				lc.selected_mode = mode
				Sfx.play("click")
				lc.draw())
		hb.add_child(b)
		tabs[mode] = b
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(fill)
	survivors_btn = MpStyle.button("Survivors")
	survivors_btn.name = "survivors_top"
	survivors_btn.pressed.connect(func(): ui.run_ui.open_roster(_survivor_picked if lc.room.is_empty() or str(lc.room.get("mode", "")) == "arena" else Callable(), lc.survivor))
	hb.add_child(survivors_btn)
	var back := MpStyle.button("Back")
	back.name = "back"
	back.pressed.connect(func(): hide())
	hb.add_child(back)
	return hb

func _survivor_picked(id: String) -> void:
	lc.survivor = id
	if not lc.room.is_empty() and str(lc.room.get("mode", "")) == "arena":
		lc.action("pick", {"id": str(lc.room.id)})
	lc.draw()

func _on_visibility() -> void:
	if visible:
		_shown = ""
		_fit()
	if not visible and ui.title_stage != null:
		for k in ["frame_mid", "lobby_cls", "lobby_zoom"]:
			if ui.title_stage.has_meta(k):
				ui.title_stage.remove_meta(k)
		if not game.playing and ui.home != null:
			ui.home.select(ui.home.sel)      # (the title's own character back on the stage)

## Everything from the client's state.
func render() -> void:
	lc.solo_button = null
	var mode: String = str(lc.room.get("mode", lc.selected_mode))
	if not MpMode.mode_on(mode):
		mode = MpMode.MODES[0]
	for m in tabs:
		var on: bool = m == mode
		var b: Button = tabs[m]
		var col: Color = MpStyle.IVORY if on else MpStyle.FAINT
		for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(st, col if st != "font_hover_color" or on else MpStyle.DIM)
		var line := StyleBoxFlat.new()
		line.bg_color = Color(0, 0, 0, 0)
		line.border_color = MpStyle.GOLD if on else Color(0, 0, 0, 0)
		line.border_width_bottom = 3
		line.content_margin_bottom = 6
		line.content_margin_top = 6
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, line)
		b.disabled = not lc.room.is_empty() and not on
	var n := Survivors.list().size()
	survivors_btn.text = "Survivors  ·  %d" % n
	lc.lan_row.visible = not game.playing
	for c in left.get_children():
		left.remove_child(c)
		c.queue_free()
	for c in right.get_children():
		right.remove_child(c)
		c.queue_free()
	var prep: bool = not lc.room.is_empty()
	var stage: bool = prep and not game.playing and ui.title_stage != null and ui.title_stage.root3d != null
	var tex_path: String = ART.get(mode, ART["battlegrounds"])
	art.texture = ResCache.get_res(tex_path) as Texture2D if ResourceLoader.exists(tex_path) else null
	art.visible = not stage
	(shade.material as ShaderMaterial).set_shader_parameter("strength", 0.85 if stage else 1.0)
	if ui.title_stage != null:
		if stage:
			ui.title_stage.set_meta("frame_mid", STAGE_MID)
			ui.title_stage.set_meta("lobby_zoom", 1.0)
		else:
			for k in ["frame_mid", "lobby_zoom"]:
				if ui.title_stage.has_meta(k):
					ui.title_stage.remove_meta(k)
	if prep:
		_left_prep(mode, stage)
		_right_prep(mode)
	else:
		_left_browse(mode)
		_right_browse(mode)
	var key := ("prep:" if prep else "browse:") + mode
	if key != _shown:
		# one restrained move when the screen changes (a lobby entered or left, another mode): never on the poll
		_shown = key
		_fade(left, 14.0)
		_fade(right.get_parent() as Control, 0.0)
		_fade(art, 0.0)

func _fade(c: Control, dy: float) -> void:
	if c == null or not is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.22)
	if dy != 0.0:
		var to := c.position.y
		c.position.y += dy
		tw.parallel().tween_property(c, "position:y", to, 0.26)

# ---------------------------------------------------------------- browse

func _left_browse(mode: String) -> void:
	left.add_child(MpStyle.eyebrow("Mode"))
	var title := MpStyle.label(MODE_TITLE[mode], _big(76), MpStyle.IVORY, 700, true)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	left.add_child(title)
	left.add_child(MpStyle.para(MODE_LINE[mode], 19, MpStyle.IVORY, minf(620.0, col_w)))
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	left.add_child(steps)
	var i := 1
	for s in MODE_STEPS[mode]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var num := MpStyle.label(str(i), 20, MpStyle.GOLD, 700, true)
		num.custom_minimum_size.x = 22
		row.add_child(num)
		var t := MpStyle.para(s, 15, Color(0.88, 0.87, 0.82), minf(560.0, col_w - 40.0))
		row.add_child(t)
		steps.add_child(row)
		i += 1
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	left.add_child(gap)
	var host := HBoxContainer.new()
	host.add_theme_constant_override("separation", 12)
	left.add_child(host)
	if mode == "arena":
		var seg := HBoxContainer.new()
		seg.add_theme_constant_override("separation", 4)
		for n in [1, 2, 3]:
			var b := MpStyle.button("%dv%d" % [n, n], n == lc.team_size)
			b.text = "%dv%d" % [n, n]      # (not upper-cased like a primary action)
			b.name = "size_%d" % n
			b.custom_minimum_size.x = 64
			b.pressed.connect(func():
				lc.team_size = n
				lc.team_pick.select(n - 1)
				lc.draw())
			seg.add_child(b)
		host.add_child(seg)
	var create := MpStyle.button("Create Lobby", true, 18)
	create.name = "create"
	create.custom_minimum_size = Vector2(240, 54)
	create.pressed.connect(func(): lc.action("create", {"mode": mode, "team_size": lc.team_size, "name": lc._lobby_name(), "wager": false}))
	host.add_child(create)
	lc.create_button = create
	if mode in ["battlegrounds", "sandbox"]:
		var who := MpStyle.label("as %s  ·  change in the lobby" % Data.CLASSES[lc.run_class]["name"], 14, MpStyle.DIM)
		who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		host.add_child(who)
	else:
		var s := Survivors.read(lc.survivor)
		var who := MpStyle.label(("with %s" % s.get("name", "")) if not s.is_empty() else "You need a survivor first", 14, MpStyle.DIM if not s.is_empty() else MpStyle.DANGER)
		who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		host.add_child(who)
		create.disabled = s.is_empty()
	var solo_label := MpMode.solo_label(mode)
	if solo_label != "":
		var solo_row := HBoxContainer.new()
		solo_row.add_theme_constant_override("separation", 12)
		left.add_child(solo_row)
		var solo := MpStyle.button(solo_label, false, 18)
		solo.name = "play_solo"
		solo.custom_minimum_size = Vector2(240, 48)
		solo.disabled = lc.busy or game._busy
		solo.pressed.connect(lc.play_solo)
		solo_row.add_child(solo)
		lc.solo_button = solo
		if mode == "sandbox":
			var pick := OptionButton.new()
			pick.name = "solo_class"
			var classes: Array = lc.run_classes()
			for cls in classes: pick.add_item(str(Data.CLASSES[cls]["name"]))
			pick.select(maxi(0, classes.find(lc.run_class)))
			pick.item_selected.connect(func(i):
				lc.run_class = str(classes[i])
				lc.draw())
			solo_row.add_child(pick)
	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size.y = 20
	left.add_child(bottom_gap)

func _right_browse(mode: String) -> void:
	var head := HBoxContainer.new()
	right.add_child(head)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	col.add_child(MpStyle.eyebrow("Open lobbies"))
	var list: Array = lc.rooms.filter(func(r): return str(r.get("mode", "")) == mode)
	var shown: Array = list.filter(func(r): return not joinable_only or _joinable(r))
	col.add_child(MpStyle.label("%d %s lobb%s" % [list.size(), MODE_TITLE[mode], "y" if list.size() == 1 else "ies"], 20, MpStyle.IVORY, 700))
	var refresh := MpStyle.button("Refresh")
	refresh.name = "refresh"
	refresh.pressed.connect(func(): lc.refresh())
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(refresh)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	right.add_child(filters)
	for f in [["All", false], ["Joinable now", true]]:
		var on: bool = joinable_only == f[1]
		var b := MpStyle.button(f[0])
		b.name = "filter_" + ("joinable" if f[1] else "all")
		if on:
			b.add_theme_stylebox_override("normal", MpStyle.box(Color(1, 1, 1, 0.1), MpStyle.GOLD, 4, 10))
		var want: bool = f[1]
		b.pressed.connect(func():
			joinable_only = want
			lc.draw())
		filters.add_child(b)
	right.add_child(MpStyle.rule())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 260
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	lc.rows = rows
	# friends' worlds through Steam (co-op), first
	if game.steam != null and game.steam.ok:
		for f in game.steam.friends_worlds():
			var fl: int = int(f.lobby)
			rows.add_child(_lobby_row(str(f.name) + "'s world", "Co-op  ·  a friend's story game", "", "Open", true, func():
				hide()
				game.steam.join_world(fl)))
	if lc.notice != "":
		var msg: String = lc.notice
		rows.add_child(_state_card("Your last match ended", msg, "Dismiss", func():
			lc.notice = ""
			lc.draw()))
	if lc.last_error != "" and lc.rooms.is_empty():
		rows.add_child(_state_card("Can't reach the lobby service", lc.last_error + " Your selections are kept.", "Retry", func(): lc.refresh()))
	elif not lc.loaded:
		rows.add_child(_state_card("Looking for lobbies…", "This takes a moment.", "", Callable()))
	elif shown.is_empty():
		rows.add_child(_state_card("No %s lobbies %s" % [MODE_TITLE[mode], "you can join right now" if joinable_only and not list.is_empty() else "yet"],
			"Create one on the left: others will see it here.", "", Callable()))
	for r in shown:
		var rid := str(r.id)
		var owner: Dictionary = r.members.get(str(r.get("owner", "")), {})
		var full: bool = int(r.get("joined", r.members.size())) >= int(r.capacity)
		var state := "Full" if full else str(r.state).capitalize()
		var rm := str(r.mode)
		rows.add_child(_lobby_row(str(r.name), "Hosted by %s  ·  %s" % [owner.get("name", "?"), lc._format(r)],
			"%d / %d" % [int(r.get("joined", r.members.size())), int(r.capacity)], state, _joinable(r), func(): lc.join_lobby(rid, rm)))

func _joinable(r: Dictionary) -> bool:
	return bool(r.get("joinable", false)) and int(r.get("joined", r.members.size())) < int(r.capacity)

func _lobby_row(title: String, sub: String, players: String, state: String, joinable: bool, join: Callable) -> Control:
	var p := MpStyle.panel(MpStyle.PANEL, Color(1, 1, 1, 0.07), 6, 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	hb.add_child(col)
	var t := MpStyle.label(title, 16, MpStyle.IVORY, 600)
	t.clip_text = true
	col.add_child(t)
	var s := MpStyle.label(sub, 13, MpStyle.DIM)
	s.clip_text = true
	col.add_child(s)
	if players != "":
		var pl := MpStyle.label(players, 15, MpStyle.IVORY, 600)
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(pl)
	var tag := MpStyle.tag(state, MpStyle.OK if state in ["Waiting", "Open"] else (MpStyle.DANGER if state == "Full" else MpStyle.GOLD))
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tag)
	var j := MpStyle.button("Join")
	j.custom_minimum_size.x = 84
	j.disabled = not joinable
	j.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	j.pressed.connect(join)
	hb.add_child(j)
	return p

func _state_card(title: String, text: String, action: String, cb: Callable) -> Control:
	var p := MpStyle.panel(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 6, 18)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(MpStyle.label(title, 17, MpStyle.IVORY, 600))
	vb.add_child(MpStyle.para(text, 14, MpStyle.DIM, 360.0))
	if action != "":
		var b := MpStyle.button(action)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(cb)
		vb.add_child(b)
	return p

# ---------------------------------------------------------------- prepare

func _left_prep(mode: String, stage: bool) -> void:
	if mode in ["battlegrounds", "sandbox"]:
		var cls: String = lc.run_class
		if stage:
			var w := str(Data.CLASSES[cls].get("weapon", "hand_axe" if cls == "demon" else "short_sword"))
			var gear := {"_cls": cls, "_helm": true}
			if not Dragon.is_dragon(cls) and Data.BASES.has(w):
				gear["weapon"] = Items.make(w)
			if ui.title_stage.get_meta("lobby_cls", "") != cls or ui.title_stage.hero == null:
				ui.title_stage.show_character(gear)
				ui.title_stage.set_meta("lobby_cls", cls)
				if ui.title_stage.hero != null:
					ui.title_stage.hero.light.light_energy = 1.1      # (a key light on the chosen hero)
		var ps: Array = PLAYSTYLE.get(cls, ["", str(Data.CLASSES[cls].get("desc", ""))])
		left.add_child(MpStyle.eyebrow("Your class  ·  temporary practice hero" if mode == "sandbox" else "Your class  ·  a fresh run from level 0"))
		var title := MpStyle.label(Data.CLASSES[cls]["name"], _big(72), MpStyle.IVORY, 700, true)
		title.add_theme_constant_override("outline_size", 10)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		left.add_child(title)
		var tg := MpStyle.tag(ps[0], ClassStage.ACCENTS.get(cls, MpStyle.GOLD))
		left.add_child(tg)
		left.add_child(MpStyle.para(ps[1], 17, MpStyle.IVORY, minf(560.0, col_w)))
		left.add_child(MpStyle.eyebrow("Practice skills" if mode == "sandbox" else "Skills to find in camp chests", MpStyle.FAINT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		left.add_child(row)
		for sk in RunBuild.skill_pool(cls).slice(0, clampi(int(col_w / 56.0), 4, 8)):
			var ic := _skill_icon(str(sk["id"]), 46)
			row.add_child(ic)
	else:
		var d := Survivors.read(lc.survivor)
		left.add_child(MpStyle.eyebrow("Your survivor"))
		if d.is_empty():
			left.add_child(MpStyle.label("No survivor", _big(60), MpStyle.IVORY, 700, true))
			left.add_child(MpStyle.para("Bring a character out of a Battlegrounds run alive and press Save Character to fight here.", 17, MpStyle.IVORY, minf(560.0, col_w)))
			var go := MpStyle.button("Go to Battlegrounds", true)
			go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			go.pressed.connect(func():
				lc.action("leave")
				lc.selected_mode = "battlegrounds")
			left.add_child(go)
			return
		if stage:
			var g: Dictionary = (d["hero"].get("equipment", {}) as Dictionary).duplicate(true)
			g["_cls"] = str(d["cls"])
			g["_helm"] = true
			if ui.title_stage.get_meta("lobby_cls", "") != lc.survivor or ui.title_stage.hero == null:
				ui.title_stage.show_character(g)
				ui.title_stage.set_meta("lobby_cls", lc.survivor)
				if ui.title_stage.hero != null:
					ui.title_stage.hero.light.light_energy = 1.1
		var title := MpStyle.label(str(d.get("name", "Survivor")), _big(66), MpStyle.IVORY, 700, true)
		title.add_theme_constant_override("outline_size", 10)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		left.add_child(title)
		left.add_child(MpStyle.label(Survivors.summary(d), 17, MpStyle.GOLD, 600))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		left.add_child(row)
		var binds: Dictionary = d["hero"].get("binds", {})
		for slot in ["lmb"] + RunBuild.SLOTS:
			row.add_child(_skill_icon(str(binds.get(slot, "")), 46))
		var change := MpStyle.button("Change survivor")
		change.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		change.pressed.connect(func(): ui.run_ui.open_roster(_survivor_picked, lc.survivor))
		left.add_child(change)
	var g2 := Control.new()
	g2.custom_minimum_size.y = 20
	left.add_child(g2)

func _skill_icon(id: String, px: float) -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", MpStyle.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 6, 4))
	holder.custom_minimum_size = Vector2(px, px)
	if id != "":
		var gl := UI.SkillGlyph.new()
		gl.id = id
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(gl)
		var sk := Data.skill_def(id)
		holder.mouse_entered.connect(func(): ui.show_tooltip([[sk.get("name", id), MpStyle.GOLD], [str(sk.get("desc", "")), Color(0.85, 0.83, 0.77)]]))
		holder.mouse_exited.connect(func(): ui.tooltip.visible = false)
	return holder

func _right_prep(mode: String) -> void:
	var room: Dictionary = lc.room
	var head := HBoxContainer.new()
	right.add_child(head)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	col.add_child(MpStyle.eyebrow("%s lobby  ·  %s" % [MODE_TITLE.get(mode, mode), lc._format(room)]))
	var nm := MpStyle.label(str(room.name), 22, MpStyle.IVORY, 700)
	nm.clip_text = true
	col.add_child(nm)
	var joined: int = room.members.values().filter(func(m): return not m.get("departed", false)).size()
	var st := MpStyle.tag("%s  ·  %d / %d" % [str(room.state).capitalize(), joined, int(room.capacity)], MpStyle.OK if str(room.state) == "waiting" else MpStyle.GOLD)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(st)
	# the members: class or survivor, team, ready
	var members := VBoxContainer.new()
	members.name = "members"
	members.add_theme_constant_override("separation", 6)
	right.add_child(members)
	for uid in room.members:
		var m: Dictionary = room.members[uid]
		if m.get("departed", false):
			continue
		members.add_child(_member_row(str(uid), m, mode, room))
	right.add_child(MpStyle.rule())
	if str(room.state) == "waiting":
		if mode in ["battlegrounds", "sandbox"]:
			right.add_child(MpStyle.eyebrow("Choose your class"))
			right.add_child(_class_tiles())
		elif mode == "arena":
			var teams := HBoxContainer.new()
			teams.add_theme_constant_override("separation", 8)
			right.add_child(teams)
			for t in [0, 1]:
				var b := MpStyle.button("Join " + ("Ember" if t == 0 else "Frost"))
				var team: int = t
				b.pressed.connect(func(): lc.action("team", {"team": team}))
				teams.add_child(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	right.add_child(bar)
	var leave := MpStyle.button("Leave lobby" if col_w > 600.0 else "Leave")
	leave.name = "leave"
	leave.pressed.connect(func(): lc.action("leave"))
	bar.add_child(leave)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var me: Dictionary = room.members.get(lc.identity, {})
	var waiting := str(room.state) == "waiting"
	var ready := MpStyle.button("Not ready" if me.get("ready", false) else "Ready", not me.get("ready", false), 17)
	ready.name = "ready"
	ready.custom_minimum_size.x = 160 if col_w > 600.0 else 118
	ready.disabled = not waiting or (mode == "arena" and lc.survivor == "")
	var want: bool = not me.get("ready", false)
	ready.pressed.connect(func(): lc.action("ready", {"ready": want}))
	bar.add_child(ready)
	if str(room.get("owner", "")) == lc.identity:
		var all_ready: bool = room.members.values().filter(func(m): return not m.get("departed", false)).all(func(m): return m.get("ready", false))
		var start := MpStyle.button("Start match", all_ready, 17)
		start.name = "start"
		start.custom_minimum_size.x = 160 if col_w > 600.0 else 118
		start.disabled = not waiting or not all_ready
		start.tooltip_text = "" if all_ready else "Everyone must be ready"
		start.pressed.connect(func(): lc.action("start"))
		bar.add_child(start)

func _member_row(uid: String, m: Dictionary, mode: String, room: Dictionary) -> Control:
	var me: bool = uid == lc.identity
	var p := MpStyle.panel(MpStyle.RAISED if me else MpStyle.PANEL, MpStyle.ARCANE if me else Color(1, 1, 1, 0.06), 6, 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var ch := str(m.get("character", ""))
	var cls := ch.trim_prefix("sandbox_") if ch.begins_with("sandbox_") else ch.trim_prefix("run_") if ch.begins_with("run_") else ""
	var accent: Color = ClassStage.ACCENTS.get(cls, MpStyle.GOLD)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(4, 34)
	hb.add_child(bar)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	hb.add_child(col)
	var crown := "♛ " if str(room.get("owner", "")) == uid else ""
	col.add_child(MpStyle.label(crown + str(m.get("name", "Adventurer")) + ("  (you)" if me else ""), 15, MpStyle.IVORY, 600))
	var what := ""
	if cls != "":
		what = str(Data.CLASSES.get(cls, {}).get("name", cls)) + ("  ·  practice" if mode == "sandbox" else "  ·  level 0")
	elif mode == "arena":
		what = "Survivor  ·  " + ("Ember" if int(m.get("team", 0)) == 0 else "Frost")
	col.add_child(MpStyle.label(what, 13, MpStyle.DIM))
	var rd: bool = m.get("ready", false)
	var tag := MpStyle.tag("Ready" if rd else "Not ready", MpStyle.OK if rd else MpStyle.FAINT)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tag)
	return p

func _class_tiles() -> Control:
	var grid := GridContainer.new()
	grid.name = "class_tiles"
	var pw: float = (right.get_parent() as Control).custom_minimum_size.x - 46.0
	grid.columns = 5 if pw >= 500.0 else 4
	_tile_w = floorf((pw - 6.0 * (grid.columns - 1)) / grid.columns)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for cls in lc.run_classes():
		grid.add_child(_tile(cls))
	return grid

var _tile_w := 98.0

func _tile(cls: String) -> Control:
	var sel: bool = cls == lc.run_class
	var accent: Color = ClassStage.ACCENTS.get(cls, MpStyle.GOLD)
	var b := Button.new()
	b.name = "tile_" + cls
	b.custom_minimum_size = Vector2(_tile_w, 88)
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "%s  ·  %s" % [Data.CLASSES[cls]["name"], PLAYSTYLE.get(cls, [""])[0]]
	var sb := MpStyle.box(Color(accent.r, accent.g, accent.b, 0.16) if sel else MpStyle.PANEL, accent if sel else Color(1, 1, 1, 0.08), 6, 6, 2 if sel else 1)
	sb.border_width_top = 3
	sb.border_color = accent if sel else Color(accent.r, accent.g, accent.b, 0.55)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", MpStyle.box(Color(0, 0, 0, 0), MpStyle.ARCANE, 6, 6, 2))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	b.add_child(vb)
	var own := Data.skills_for(cls)
	var gl := UI.SkillGlyph.new()
	gl.id = str(own[0]["id"]) if not own.is_empty() else "attack"
	gl.custom_minimum_size = Vector2(40, 40)
	gl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(gl)
	var l := MpStyle.label(str(Data.CLASSES[cls]["name"]), 12, MpStyle.IVORY if sel else MpStyle.DIM, 600)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	b.pressed.connect(func():
		if lc.run_class == cls:
			return
		lc.run_class = cls
		game._save_setting("battlegrounds", "class", cls)
		Sfx.play("click")
		lc.action("pick", {"id": str(lc.room.id)}))
	return b
