class_name DayClock
extends Control
## The camp's hour on the HUD (jj): a small dial hung on the corner map's ring, the sky in the hour's colours over a
## dark treeline, the sun arcing over it by day and the moon among stars by night, and the time beside it. Shown
## while DayNight runs (Act I's camp); `UI.day_clock`.

const R := 23.0                       # the dial's radius
const GOLD := Color(0.78, 0.62, 0.34)
const GOLD_HI := Color(1.0, 0.86, 0.55)

var game: Node
var font: Font
var _t := 0.0
var _hour := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(R * 2.0 + 6.0, R * 2.0 + 6.0)

func _process(delta: float) -> void:
	var dn: DayNight = game.day_night if game != null else null
	var show: bool = dn != null and dn.on and not bool(game.get("bg_mode"))
	visible = show
	_t -= delta
	if show and _t <= 0.0:
		_t = 0.25
		_hour = dn.clock()
		queue_redraw()

## The sky's colours at an hour (top, horizon): night navy, dawn rose, day blue, dusk ember.
static func sky(h: float) -> Array:
	var keys := [[0.0, Color(0.03, 0.04, 0.1), Color(0.07, 0.09, 0.18)], [5.0, Color(0.04, 0.05, 0.12), Color(0.1, 0.11, 0.2)],
		[6.3, Color(0.25, 0.3, 0.5), Color(0.95, 0.55, 0.4)], [8.0, Color(0.3, 0.5, 0.8), Color(0.7, 0.78, 0.85)],
		[17.5, Color(0.28, 0.46, 0.76), Color(0.72, 0.76, 0.8)], [19.3, Color(0.25, 0.22, 0.42), Color(1.0, 0.48, 0.22)],
		[20.6, Color(0.05, 0.06, 0.14), Color(0.16, 0.12, 0.22)], [24.0, Color(0.03, 0.04, 0.1), Color(0.07, 0.09, 0.18)]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var f := smoothstep(float(a[0]), float(b[0]), h)
			return [(a[1] as Color).lerp(b[1], f), (a[2] as Color).lerp(b[2], f)]
	return [keys[0][1], keys[0][2]]

func _draw() -> void:
	if _hour < 0.0:
		return
	var c := size * 0.5
	var h := _hour
	var cols := sky(h)
	# the sky: a disc shaded from the top colour to the horizon's
	var pts := PackedVector2Array()
	var vc := PackedColorArray()
	for i in 40:
		var a := TAU * i / 40.0
		var p := c + Vector2(cos(a), sin(a)) * R
		pts.append(p)
		vc.append((cols[0] as Color).lerp(cols[1], clampf((p.y - (c.y - R)) / (R * 1.4), 0.0, 1.0)))
	draw_polygon(pts, vc)
	var horizon := c.y + R * 0.38
	# stars at night
	var dn: DayNight = game.day_night
	var night: float = dn.night if dn != null else 0.0
	if night > 0.05:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 14:
			var sp := c + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.85, 0.3)) * R
			if sp.distance_to(c) < R - 3.0 and sp.y < horizon - 2.0:
				var tw := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.002 + i * 1.7)
				draw_circle(sp, 0.5 + rng.randf() * 0.7, Color(0.9, 0.92, 1.0, night * tw))
	# the sun or the moon on its arc, rising at the left, setting at the right
	var day_f := (h - DayNight.SUNRISE) / (DayNight.SUNSET - DayNight.SUNRISE)
	var moon_len := 24.0 - (DayNight.SUNSET - DayNight.SUNRISE)
	var night_f := fposmod(h - DayNight.SUNSET, 24.0) / moon_len
	var is_day := day_f >= 0.0 and day_f <= 1.0
	var f := day_f if is_day else night_f
	var arc := Vector2(-cos(f * PI) * R * 0.62, -6.0 - sin(f * PI) * R * 0.62)     # always just over the trees
	var body := Vector2(c.x, horizon) + arc
	if is_day:
		var sun := Color(1.0, 0.86, 0.45).lerp(Color(1.0, 0.55, 0.25), 1.0 - sin(f * PI))
		draw_circle(body, 8.5, Color(sun.r, sun.g, sun.b, 0.18))
		draw_circle(body, 6.0, Color(sun.r, sun.g, sun.b, 0.35))
		for i in 8:
			var a := TAU * i / 8.0 + h * 0.4
			draw_line(body + Vector2(cos(a), sin(a)) * 5.5, body + Vector2(cos(a), sin(a)) * 7.5, sun, 1.2, true)
		draw_circle(body, 4.2, sun)
	else:
		draw_circle(body, 7.5, Color(0.75, 0.82, 1.0, 0.15))
		draw_circle(body, 4.6, Color(0.93, 0.94, 0.86))
		draw_circle(body + Vector2(2.2, -1.4), 3.9, (cols[0] as Color).lerp(cols[1], 0.3))   # the crescent's shadow
	# the treeline: a dark ridge of firs across the bottom, cut to the disc
	var ridge := PackedVector2Array()
	var xs := 18
	for i in xs + 1:
		var x := c.x - R + 2.0 * R * i / float(xs)
		var tip := 5.0 if i % 2 == 0 else 1.5
		tip += 2.5 * sin(i * 2.3)
		ridge.append(Vector2(x, horizon - maxf(0.0, tip)))
	var under := PackedVector2Array()
	for p in ridge:
		var dy := sqrt(maxf(0.0, R * R - (p.x - c.x) * (p.x - c.x)))
		under.append(Vector2(p.x, minf(p.y, c.y + dy)))
	for i in range(xs, -1, -1):
		var x := c.x - R + 2.0 * R * i / float(xs)
		var dy := sqrt(maxf(0.0, R * R - (x - c.x) * (x - c.x)))
		under.append(Vector2(x, c.y + dy))
	var ground := Color(0.03, 0.035, 0.03).lerp(Color(0.08, 0.1, 0.07), 1.0 - night)
	draw_colored_polygon(under, ground)
	# the gold ring, like the corner map's
	draw_arc(c, R + 1.5, 0.0, TAU, 48, Color(0.08, 0.06, 0.03), 4.0, true)
	draw_arc(c, R + 1.0, 0.0, TAU, 48, GOLD, 2.0, true)
	draw_arc(c, R - 0.6, PI * 1.1, PI * 1.6, 12, Color(GOLD_HI.r, GOLD_HI.g, GOLD_HI.b, 0.5), 1.0, true)
	# the time, to the left of the dial
	if font != null:
		var txt := "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
		var fs := 16
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2(c.x - R - 8.0 - w, c.y + fs * 0.35)
		draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD_HI)
