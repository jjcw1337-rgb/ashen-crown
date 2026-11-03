class_name BossCard
extends Control
## A boss's introduction, Borderlands-style (Blaine, 2026-11-01): the first time a boss with an "intro" in its
## Data.ENEMIES entry roars at you, the camera swings in on it (Game.focus_on), the screen goes to comic ink for a
## moment (INK_SHADER: posterized colours, thick black outlines, halftone shading) and a slanted card slams in with its
## name, its title and one line about it, under a stinger ("boss_sting"); then it all slides away and the fight is on.
## Local to each game: every player near it sees their own, when its roar reaches them (Enemy's "bear_roar" fx), and
## nothing is slowed or paused for anyone. Once per boss per zone visit (Game meta "boss_cards").
##   BossCard.play(game, enemy)

const LEN := 3.6                 # seconds on screen
const IN := 0.28
const OUT := 0.45

const INK_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amt = 0.0;
uniform vec3 accent = vec3(1.0, 0.75, 0.2);
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 1.6;
	vec3 c = texture(screen, SCREEN_UV).rgb;
	// outlines: where the brightness steps (a Sobel on the screen)
	float tl = lum(texture(screen, SCREEN_UV + vec2(-px.x, -px.y)).rgb), t = lum(texture(screen, SCREEN_UV + vec2(0.0, -px.y)).rgb);
	float tr = lum(texture(screen, SCREEN_UV + vec2(px.x, -px.y)).rgb), l = lum(texture(screen, SCREEN_UV + vec2(-px.x, 0.0)).rgb);
	float r = lum(texture(screen, SCREEN_UV + vec2(px.x, 0.0)).rgb), bl = lum(texture(screen, SCREEN_UV + vec2(-px.x, px.y)).rgb);
	float b = lum(texture(screen, SCREEN_UV + vec2(0.0, px.y)).rgb), br = lum(texture(screen, SCREEN_UV + vec2(px.x, px.y)).rgb);
	float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
	float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
	float edge = smoothstep(0.08, 0.2, sqrt(gx * gx + gy * gy));
	// posterized colour, pushed toward the boss's accent in the lights
	vec3 p = floor(c * 5.0 + 0.5) / 5.0;
	p = mix(p, p * accent * 1.4, 0.25 * smoothstep(0.4, 0.9, lum(c)));
	// halftone dots in the shadows
	vec2 cell = fract(FRAGCOORD.xy / 6.0) - 0.5;
	float dot_r = (1.0 - lum(c)) * 0.55;
	float tone = step(length(cell), dot_r) * smoothstep(0.55, 0.15, lum(c));
	vec3 ink = mix(p, p * 0.35, tone * 0.6);
	ink = mix(ink, vec3(0.02), edge);
	COLOR = vec4(mix(c, ink, amt), 1.0);
}
"""

var _t := 0.0
var _ink: ColorRect
var _band: Control
var _name: Label
var _sub: Label
var _line: Label
var _accent := Color(1.0, 0.75, 0.2)

static func play(game: Node, e) -> void:
	if game == null or e == null or not is_instance_valid(e) or game.ui == null:
		return
	var intro: Dictionary = Data.ENEMIES.get(e.kind, {}).get("intro", {})
	if intro.is_empty():
		return
	var shown: Dictionary = game.get_meta("boss_cards", {})
	var key := "%s:%s" % [game.cur_zone, e.kind]
	if shown.has(key):
		return
	shown[key] = true
	game.set_meta("boss_cards", shown)
	var c := BossCard.new()
	c._accent = intro.get("color", Color(1.0, 0.75, 0.2))
	game.ui.top.add_child(c)
	c._build(intro)
	game.focus_on(e, LEN, 0.42)
	if Sfx.bank.has("boss_sting"):
		Sfx.play("boss_sting", -2.0)
	else:
		Sfx.play("boom", -4.0, 0.7)

func _build(intro: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink = ColorRect.new()
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = INK_SHADER
	m.shader = sh
	m.set_shader_parameter("accent", Vector3(_accent.r, _accent.g, _accent.b))
	_ink.material = m
	add_child(_ink)
	# the card: a slanted band across the lower left, the name over it
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.position = Vector2(-900, 0)
	add_child(_band)
	var vp := get_viewport_rect().size
	var slab := Polygon2D.new()
	var y0 := vp.y * 0.56
	slab.polygon = PackedVector2Array([Vector2(0, y0 + 40), Vector2(vp.x * 0.62, y0 - 30), Vector2(vp.x * 0.66, y0 + 150), Vector2(0, y0 + 210)])
	slab.color = Color(0.04, 0.03, 0.03, 0.92)
	_band.add_child(slab)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([Vector2(0, y0 + 26), Vector2(vp.x * 0.62, y0 - 44), Vector2(vp.x * 0.625, y0 - 30), Vector2(0, y0 + 40)])
	stripe.color = _accent
	_band.add_child(stripe)
	_name = _lab(str(intro.get("title", "")), 104, _accent, 16)
	_name.position = Vector2(vp.x * 0.05, y0 - 40)
	_name.rotation = -0.11
	_band.add_child(_name)
	_sub = _lab(str(intro.get("sub", "")), 38, Color(0.95, 0.92, 0.85), 10)
	_sub.position = Vector2(vp.x * 0.08, y0 + 66)
	_sub.rotation = -0.11
	_band.add_child(_sub)
	_line = _lab(str(intro.get("line", "")), 22, Color(0.85, 0.82, 0.75), 6)
	_line.position = Vector2(vp.x * 0.09, y0 + 122)
	_line.rotation = -0.11
	_band.add_child(_line)

func _lab(txt: String, sz: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _process(delta: float) -> void:
	_t += delta
	var k_in := smoothstep(0.0, IN, _t)
	var k_out := smoothstep(LEN - OUT, LEN, _t)
	var amt := k_in * (1.0 - k_out)
	(_ink.material as ShaderMaterial).set_shader_parameter("amt", amt * 0.85)
	# the band slams in (overshoots a touch), holds, then slides off the other way
	var slam := 1.0 - pow(1.0 - k_in, 3.0)
	_band.position.x = lerpf(-900.0, 0.0, slam) + sin(clampf(_t / IN, 0.0, 1.0) * PI) * 18.0 + k_out * 1400.0
	_line.modulate.a = smoothstep(IN, IN + 0.35, _t)
	if _t >= LEN:
		queue_free()
