class_name BgMatchup
extends Control
## The antechamber's matchup (jj: "when it starts and there's enough players you see the classes that you're going
## against"): during the countdown before the gates rise, a row of cards under the raid's clock, one per other
## raider: their class's emblem (the painted talent-tree crest, assets/textures/talents/<cls>_tree0.png), its name in
## the class's colour and their level, in the inventory's iron and bronze. Never a name. Game.bg_roster (from
## Battlegrounds.roster) is what it shows; Battlegrounds.hud places and updates it.

const CARD := Vector2(132, 168)
const GAP := 12.0
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.92, 0.24, 0.3), "plague": Color(0.6, 0.95, 0.3),
	"doug": Color(1.0, 0.82, 0.2), "wyrm": Color(1.0, 0.3, 0.12), "serpent": Color(0.55, 0.88, 1.0), "wyvern": Color(0.45, 0.95, 0.85)}     # (ClassStage.ACCENTS)

var ui
var shown := ""                 # the roster last drawn (a change rebuilds the cards)
var others: Array = []
var _iron: Texture2D
var _icons := {}

func _init(u) -> void:
	ui = u
	name = "bg_matchup"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_top = 92
	grow_horizontal = Control.GROW_DIRECTION_BOTH

func set_roster(r: Array, me: int) -> void:
	others = r.filter(func(x): return int(x.get("pid", 0)) != me)
	var sig := str(others)
	if sig == shown:
		return
	shown = sig
	var n := others.size()
	var w := maxf(320.0, n * CARD.x + maxf(0, n - 1) * GAP)
	custom_minimum_size = Vector2(w, CARD.y + 40)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_bottom = offset_top + CARD.y + 40
	queue_redraw()

func _icon(cls: String) -> Texture2D:
	if not _icons.has(cls):
		var p := "res://assets/textures/talents/%s_tree0.png" % cls
		_icons[cls] = load(p) if ResourceLoader.exists(p) else null
	return _icons[cls]

func _draw() -> void:
	var f: Font = ui.font_title
	var fb: Font = ui.font_body
	if f == null:
		return
	var n := others.size()
	var head := "YOUR MATCH  ·  %d OTHER RAIDER%s" % [n, "" if n == 1 else "S"] if n > 0 else "NO OTHER RAIDERS YET"
	_text(f, head, Vector2(size.x * 0.5, 14), 15, Color(0.95, 0.82, 0.55))
	if _iron == null:
		_iron = ui._scaled_tex(ui.INV_TEX["iron"], 0.25)
	var x0 := (size.x - (n * CARD.x + maxf(0, n - 1) * GAP)) * 0.5
	for i in n:
		var o: Dictionary = others[i]
		var cls := str(o.get("cls", ""))
		var acc: Color = ACCENTS.get(cls, Color(0.85, 0.75, 0.55))
		var r := Rect2(Vector2(x0 + i * (CARD.x + GAP), 32), CARD)
		# the card: iron, a dark inner shade, a bronze rim with a lighter lip, the class's colour along the top
		draw_rect(r.grow(3), Color(0, 0, 0, 0.6))
		draw_texture_rect(_iron, r, true)
		draw_rect(r, Color(0.02, 0.02, 0.02, 0.35))
		draw_rect(r, Color(0.55, 0.42, 0.22), false, 3.0)
		draw_rect(r.grow(-3), Color(0.85, 0.68, 0.38, 0.6), false, 1.0)
		draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 3)), Color(acc.r, acc.g, acc.b, 0.85))
		# the crest in a round socket, lit in the class's colour
		var c := r.position + Vector2(r.size.x * 0.5, 62)
		for k in 3:
			draw_circle(c, 44.0 + k * 3.0, Color(acc.r, acc.g, acc.b, 0.07 - k * 0.02))
		draw_circle(c, 42, Color(0.05, 0.04, 0.03))
		draw_arc(c, 41, 0, TAU, 48, Color(0.62, 0.48, 0.25), 3.0, true)
		var ic := _icon(cls)
		if ic != null:
			draw_texture_rect(ic, Rect2(c - Vector2(36, 36), Vector2(72, 72)), false)
		else:
			_text(f, str(Data.CLASSES.get(cls, {}).get("name", cls)).left(1).to_upper(), c + Vector2(0, 4), 34, acc)
		var nm := str(Data.CLASSES.get(cls, {}).get("name", cls.capitalize())).to_upper()
		_text(f, nm, r.position + Vector2(r.size.x * 0.5, 124), 15 if nm.length() < 11 else 12, acc.lightened(0.15))
		_text(fb, "Level %d" % int(o.get("lvl", 1)), r.position + Vector2(r.size.x * 0.5, 146), 13, Color(0.86, 0.8, 0.68))

func _text(f: Font, t: String, at: Vector2, px: int, c: Color) -> void:
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := at + Vector2(-w * 0.5, px * 0.35)
	draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 5, Color(0, 0, 0, 0.9))
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)
