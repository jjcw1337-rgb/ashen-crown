class_name LootList
extends PanelContainer
## The loot list (jj, 2026-11-07: "I can barely see the items"): while Ctrl is held, every item lying on the ground
## within RANGE metres is listed on the left, nearest first, in its rarity's colour with its distance; a click sends
## the hero to pick it up (Hero.cmd_target: he walks there and Game._pickup takes it). Releasing Ctrl hides it.
## Only what this game sees on the ground (GroundItem in World.items_root); the pickup itself is the usual one (the
## server checks it in a match).

const RANGE := 18.0
const MAX_ROWS := 14
const REFRESH := 0.25            # seconds between rebuilds while it's open (items fall, the hero moves)

var game: Node
var rows: VBoxContainer
var _t := 0.0
var _shown: Array = []           # the GroundItems listed, in order
var _going: GroundItem = null     # the item clicked: the hero is on his way to it (see _follow)
const REACH := 1.6                # (Hero takes an item from 1.2 m; a footprint can stop him a little further out)

static func attach(ui: Node) -> LootList:
	var l := LootList.new()
	l.name = "loot_list"
	l.game = ui.game
	ui.hud.add_child(l)
	l._build()
	return l

func _build() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(18, 110)
	custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.035, 0.03, 0.88)
	sb.border_color = Color(0.55, 0.45, 0.3, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var head := Label.new()
	head.text = "ON THE GROUND  ·  click to pick up"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.86, 0.72, 0.44))
	vb.add_child(head)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	vb.add_child(rows)

## The items near the hero, nearest first.
func nearby() -> Array:
	if game == null or game.world == null or game.hero == null:
		return []
	var hp: Vector3 = game.hero.global_position
	var out: Array = game.world.items_root.get_children().filter(func(g) -> bool:
		return g is GroundItem and is_instance_valid(g) and not g.is_queued_for_deletion() and g._toss >= 1.0 \
			and (g.global_position - hp).length() < RANGE)
	out.sort_custom(func(a, b) -> bool: return (a.global_position - hp).length() < (b.global_position - hp).length())
	return out.slice(0, MAX_ROWS)

func _want() -> bool:
	return game != null and game.playing and not game._busy and game.world != null and game.hero != null \
		and not game.hero.dead and Input.is_key_pressed(KEY_CTRL) and not (game.ui.chat != null and game.ui.chat.typing)

func _process(delta: float) -> void:
	_follow()
	var want := _want()
	if want != visible:
		visible = want
		_t = 0.0
	if not visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	_rebuild()

func _rebuild() -> void:
	var items := nearby()
	if items == _shown and rows.get_child_count() > 0:
		_update_distances()
		return
	_shown = items
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	if items.is_empty():
		var none := Label.new()
		none.text = "Nothing on the ground nearby"
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", Color(0.6, 0.57, 0.52))
		rows.add_child(none)
		return
	for g in items:
		rows.add_child(_row(g))
	_update_distances()

func _row(g: GroundItem) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", 15)
	var col: Color = Data.RARITY_COLOR[int(g.item.get("rarity", 0))]
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col.lightened(0.3))
	b.set_meta("item", g)
	b.pressed.connect(func():
		if is_instance_valid(g) and not g.is_queued_for_deletion():
			_going = g
			game.hero.cmd_target(g)
			Sfx.play("inv_click", -10.0))
	b.mouse_entered.connect(func():
		if is_instance_valid(g):
			g.set_hover(true, false))
	b.mouse_exited.connect(func():
		if is_instance_valid(g):
			g.set_hover(false, false))
	return b

func _update_distances() -> void:
	var hp: Vector3 = game.hero.global_position
	for b in rows.get_children():
		if b is Button and b.has_meta("item"):
			var g = b.get_meta("item")
			if is_instance_valid(g):
				b.text = "%s   %d m" % [str(g.item.get("name", "?")), int(round((g.global_position - hp).length()))]


## The clicked item, until it's taken: if the hero's walk ends short of it (a path that stops at a footprint's edge),
## he takes it from REACH, or is sent on again; any other order he's given (keys, a click elsewhere) drops it.
func _follow() -> void:
	if _going == null:
		return
	var h = game.hero if game != null else null
	if not is_instance_valid(_going) or _going.is_queued_for_deletion() or h == null or h.dead or not is_same(h.target, _going):
		_going = null
		return
	if h.moving:
		return
	var d := Vector2(_going.global_position.x - h.global_position.x, _going.global_position.z - h.global_position.z).length()
	if d <= REACH:
		var g := _going
		_going = null
		h.target = null
		game._pickup(g)
	else:
		h.cmd_target(_going)

