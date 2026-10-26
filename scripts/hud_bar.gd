class_name HudBar
extends Control
## A labelled, animated resource bar for the action bar: gradient fill with a moving sheen,
## a glowing leading edge, tick marks, a "ghost" that trails behind when the value drops,
## and an optional round icon badge at the left.

var value := 0.0
var shown := 0.0
var trail := 0.0
var col_lo := Color(0.3, 0.1, 0.6)
var col_hi := Color(0.7, 0.45, 1.0)
var glow := Color(0.85, 0.6, 1.0)
var title := ""
var detail := ""
var icon := ""            # "star", "bolt" or ""
var ticks := 10
var pulse := 0.0          # 0..1 extra glow (sprinting, level-up)
var font_size := 13
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _process(delta: float) -> void:
	_t += delta
	shown = lerpf(shown, value, clampf(delta * 9.0, 0.0, 1.0))
	if trail > shown:
		trail = move_toward(trail, shown, delta * 0.35)
	else:
		trail = shown
	queue_redraw()

func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

func _draw() -> void:
	var h := size.y
	var ox := h * 1.15 if icon != "" else 0.0
	var r := Rect2(ox, 0, size.x - ox, h)
	# frame and recessed track
	draw_rect(r.grow(3), Color(0.02, 0.015, 0.01, 0.95))
	draw_rect(r.grow(3), Color(0.62, 0.48, 0.26), false, 1.5)
	draw_rect(r.grow(1), Color(0.2, 0.15, 0.08), false, 1.0)
	_vgrad(r, Color(0.02, 0.02, 0.025), Color(0.1, 0.09, 0.09))
	var fw := r.size.x * clampf(shown, 0.0, 1.0)
	# the bit just lost, fading behind the fill
	if trail > shown + 0.002:
		draw_rect(Rect2(r.position.x + fw, 0, r.size.x * (trail - shown), h), Color(1.0, 0.95, 0.85, 0.35))
	if fw > 0.5:
		var fr := Rect2(r.position, Vector2(fw, h))
		var hi := col_hi.lerp(Color.WHITE, pulse * 0.25)
		_vgrad(Rect2(fr.position, Vector2(fw, h * 0.5)), hi, col_hi.lerp(col_lo, 0.45))
		_vgrad(Rect2(fr.position + Vector2(0, h * 0.5), Vector2(fw, h * 0.5)), col_hi.lerp(col_lo, 0.45), col_lo)
		draw_rect(Rect2(fr.position + Vector2(0, 1), Vector2(fw, maxf(1.0, h * 0.16))), Color(1, 1, 1, 0.3))
		# a sheen sweeping along the fill
		var sx := fmod(_t * 140.0, fw + 220.0) - 80.0 + r.position.x
		var x0 := clampf(sx, r.position.x, r.position.x + fw)
		var x1 := clampf(sx + 34.0, r.position.x, r.position.x + fw)
		var x2 := clampf(sx + 14.0, r.position.x, r.position.x + fw)
		var x3 := clampf(sx - 20.0, r.position.x, r.position.x + fw)
		if x1 - x0 > 1.0 or x2 - x3 > 1.0:
			draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x2, h), Vector2(x3, h)]), Color(1, 1, 1, 0.16))
		# glowing leading edge
		var ex := r.position.x + fw
		var gl := Color(glow.r, glow.g, glow.b, 0.22 + pulse * 0.3 + sin(_t * 4.0) * 0.05)
		draw_circle(Vector2(ex, h * 0.5), h * 0.95, gl)
		draw_rect(Rect2(ex - 2.0, 0, 2.0, h), glow.lerp(Color.WHITE, 0.5))
	for i in range(1, ticks):
		var tx := r.position.x + r.size.x * i / ticks
		draw_line(Vector2(tx, 2), Vector2(tx, h - 2), Color(0, 0, 0, 0.4), 1.0)
	# labels
	var font := get_theme_font("font", "Label")
	var fs := font_size
	var base_y := h * 0.5 + fs * 0.36
	if title != "":
		draw_string_outline(font, Vector2(r.position.x + 8, base_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(r.position.x + 8, base_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.97, 0.9))
	if detail != "":
		var dw := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var dp := Vector2(r.end.x - 8 - dw, base_y)
		draw_string_outline(font, dp, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, dp, detail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.97, 0.9))
	if icon != "":
		_badge(Vector2(ox * 0.42, h * 0.5), h * 0.78)

func _badge(c: Vector2, rad: float) -> void:
	draw_circle(c, rad + 3.0, Color(0.02, 0.015, 0.01))
	draw_circle(c, rad + 1.5, Color(0.7, 0.55, 0.3))
	draw_circle(c, rad, col_lo.darkened(0.55))
	draw_circle(c, rad * 0.82, Color(glow.r, glow.g, glow.b, 0.18 + pulse * 0.25))
	var pts := PackedVector2Array()
	match icon:
		"star":
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				var rr := rad * (0.72 if i % 2 == 0 else 0.32)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
		"bolt":
			var s := rad * 0.8
			for p in [Vector2(0.15, -1.0), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12), Vector2(-0.2, 1.0), Vector2(0.6, -0.2), Vector2(0.1, -0.2)]:
				pts.append(c + p * s)
	if pts.size() > 2:
		draw_colored_polygon(pts, glow.lerp(Color.WHITE, 0.35))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.6), 1.0, true)


## The action bar's frame: a dark bevelled plate with a doubled gold trim, corner studs and
## an optional crest notch at the top centre (where the level medallion sits).
class Frame extends Control:
	var crest := false
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(4), Color(0, 0, 0, 0.45))
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
			PackedColorArray([Color(0.11, 0.09, 0.07, 0.96), Color(0.11, 0.09, 0.07, 0.96), Color(0.04, 0.035, 0.03, 0.96), Color(0.04, 0.035, 0.03, 0.96)]))
		draw_rect(r, Color(0.66, 0.5, 0.27), false, 2.0)
		draw_rect(r.grow(-5), Color(0.36, 0.27, 0.14), false, 1.0)
		for c in [Vector2(0, 0), Vector2(r.end.x, 0), Vector2(0, r.end.y), r.end]:
			var d := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
			draw_colored_polygon(d, Color(0.72, 0.56, 0.3))
			draw_circle(c, 3.0, Color(0.95, 0.8, 0.45))
		if crest:
			var cx := r.size.x * 0.5
			var arc := PackedVector2Array()
			for i in 17:
				var a := PI + PI * i / 16.0
				arc.append(Vector2(cx, 6) + Vector2(cos(a), sin(a)) * 52.0)
			draw_colored_polygon(arc, Color(0.11, 0.09, 0.07, 0.96))
			draw_polyline(arc, Color(0.66, 0.5, 0.27), 2.0, true)


## Big round medallion showing the hero's level, with an experience ring around it.
class Medallion extends Control:
	var level := 1
	var xp := 0.0
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, rad + 4.0, Color(0.02, 0.015, 0.01))
		draw_circle(c, rad + 2.0, Color(0.72, 0.56, 0.3))
		draw_circle(c, rad, Color(0.12, 0.08, 0.03))
		draw_arc(c, rad - 4.0, -PI * 0.5, -PI * 0.5 + TAU * xp, 48, Color(1.0, 0.78, 0.3), 5.0, true)
		draw_arc(c, rad - 4.0, -PI * 0.5 + TAU * xp, -PI * 0.5 + TAU, 48, Color(0.25, 0.18, 0.08), 5.0, true)
		draw_circle(c, rad - 9.0, Color(0.2, 0.13, 0.05))
		draw_circle(c + Vector2(-rad * 0.25, -rad * 0.3), rad * 0.35, Color(1, 0.9, 0.6, 0.06 + sin(_t * 2.0) * 0.02))
		var font := get_theme_font("font", "Label")
		var s := str(level)
		var fs := int(rad * 0.82)
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(c.x - w * 0.5, c.y + rad * 0.5)
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.5))
		var lv := "LEVEL"
		var lfs := int(rad * 0.24)
		var lw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(font, Vector2(c.x - lw * 0.5, c.y - rad * 0.36), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(0.85, 0.7, 0.42))
