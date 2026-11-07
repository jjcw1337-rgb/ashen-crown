class_name MpStyle
extends RefCounted
## The multiplayer overhaul's look (Blaine, 2026-11-06): modern fantasy after Valorant's clarity. Clean geometric
## panels on charcoal, deep forest greens, ivory text, gold for the main action and arcane teal for magic; Cinzel
## for titles, Inter for everything read. Every new multiplayer screen (lobby, class choice, rewards, results,
## survivors, the run's build window) builds from these helpers so they stay one system.
## Fonts: assets/fonts (SIL Open Font License, the OFL-*.txt beside them).

const INK := Color(0.067, 0.075, 0.082, 0.96)        # charcoal, the windows
const PANEL := Color(0.094, 0.106, 0.114, 0.97)
const RAISED := Color(0.13, 0.145, 0.15, 1.0)
const FOREST := Color(0.09, 0.17, 0.13, 0.97)
const FOREST_LIT := Color(0.15, 0.28, 0.21, 1.0)
const LINE := Color(1, 1, 1, 0.09)
const IVORY := Color(0.93, 0.9, 0.84)
const DIM := Color(0.62, 0.65, 0.62)
const FAINT := Color(0.42, 0.45, 0.44)
const GOLD := Color(0.86, 0.71, 0.42)
const GOLD_LIT := Color(0.95, 0.8, 0.5)
const ARCANE := Color(0.5, 0.85, 0.79)
const DANGER := Color(0.89, 0.42, 0.36)
const OK := Color(0.47, 0.84, 0.55)

static var _fonts := {}

## Inter at a weight (400 regular .. 800 extra bold), or Cinzel for titles (`display`).
static func font(weight := 400, display := false) -> Font:
	var key := "%s%d" % ["c" if display else "i", weight]
	if _fonts.has(key):
		return _fonts[key]
	var path := "res://assets/fonts/Cinzel.ttf" if display else "res://assets/fonts/Inter.ttf"
	var f := FontVariation.new()
	if ResourceLoader.exists(path):
		f.base_font = load(path)
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	else:
		var sf := SystemFont.new()
		sf.font_weight = weight
		f.base_font = sf
	_fonts[key] = f
	return f

static func box(bg: Color, border := LINE, radius := 6, pad := 14, bw := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

static func panel(bg := INK, border := LINE, radius := 8, pad := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, radius, pad))
	return p

static func label(text: String, size := 15, color := IVORY, weight := 400, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, display))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## A small capital heading over a section ("SPELLBOOK", "PASSIVES").
static func eyebrow(text: String, color := GOLD) -> Label:
	var l := label(text.to_upper(), 12, color, 700)
	l.add_theme_constant_override("outline_size", 0)
	return l

## A paragraph that wraps inside its width.
static func para(text: String, size := 14, color := DIM, width := 0.0) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		l.custom_minimum_size.x = width
	return l

## A button: `primary` is gold with dark text (the screen's one main action), otherwise a quiet outline.
static func button(text: String, primary := false, size := 15) -> Button:
	var b := Button.new()
	b.text = text.to_upper() if primary else text
	b.add_theme_font_override("font", font(700 if primary else 600))
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	var fg := Color(0.08, 0.07, 0.05) if primary else IVORY
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", FAINT)
	var base := GOLD if primary else Color(1, 1, 1, 0.03)
	var edge := GOLD if primary else Color(1, 1, 1, 0.22)
	b.add_theme_stylebox_override("normal", box(base, edge, 4, 10))
	b.add_theme_stylebox_override("hover", box(GOLD_LIT if primary else Color(1, 1, 1, 0.08), GOLD_LIT if primary else GOLD, 4, 10))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.15), edge, 4, 10))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), ARCANE, 4, 10, 2))
	b.add_theme_stylebox_override("disabled", box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.06), 4, 10))
	b.custom_minimum_size.y = 42 if primary else 36
	return b

## A rarity pill ("COMMON", "RARE").
static func tag(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(color.r, color.g, color.b, 0.14), Color(color.r, color.g, color.b, 0.6), 3, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text.to_upper(), 11, color, 700))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p

## A thin rule between sections.
static func rule(color := LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A dimmed full-screen backdrop for a modal window; clicking it calls `on_click` (usually close).
static func scrim(on_click: Callable, alpha := 0.62) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.03, 0.03, alpha)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			c.accept_event()
			on_click.call())
	return c

## Fade a control in, rising a few pixels: the screens' one restrained motion.
static func enter(c: Control, dy := 10.0, t := 0.18) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, t)
	var y0 := c.position.y
	c.position.y = y0 + dy
	tw.tween_property(c, "position:y", y0, t)
