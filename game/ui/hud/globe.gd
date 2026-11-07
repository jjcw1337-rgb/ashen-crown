class_name Globe
extends Control
## A life or mana globe: liquid that moves like liquid. Fed the current and maximum value each frame
## (set_value); everything else happens here and in GLOBE_SHADER.
##   Life: damage surges the level down after a short delay (with a pale band showing what was lost
##   draining after it); healing rises it with a bright ripple spreading through the liquid; low life
##   pulses and shakes, critical life pulses harder and darkens. More maximum life = a bigger globe.
##   Mana: casting drops it fast and sets the liquid swirling; regeneration rises it slowly; a big
##   restore sends a wave up through it; low mana pulses a faint blue.
## Layers: the liquid (shader), the glass reflections (rendered in Blender, added on top), the frame.

const GLASS_TEX := "res://assets/textures/ui/globe_glass.png"
const FRAME_TEX := "res://assets/textures/ui/globe_frame.png"

var kind := "life"           # "life" or "mana"
var value := 1.0
var max_value := 1.0
var base_size := 170.0       # globe diameter at the starting maximum
var ref_max := 100.0         # the maximum the globe is drawn at base size for (set from the hero at start)

var liquid: ColorRect
var glass: TextureRect
var frame: TextureRect
var mat: ShaderMaterial

var _shown := 1.0            # the level drawn
var _vel := 0.0              # its speed (the surge and slosh come from this spring)
var _trail := 1.0            # the pale "lost" band above a fresh wound
var _trail_wait := 0.0
var _delay := 0.0            # damage waits this long before the liquid falls
var _target := 1.0
var _last := -1.0
var _ripple := -1.0          # 0..1 while a heal ripple / mana wave runs
var _swirl := 0.0
var _swirl_v := 0.0
var _slosh := 0.0
var _t := 0.0
var _scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP    # a click on the globe (see _has_point) doesn't walk the hero
	liquid = ColorRect.new()
	liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GLOBE_SHADER
	mat.shader = sh
	if kind == "life":
		mat.set_shader_parameter("liquid", Color(0.85, 0.06, 0.05))
		mat.set_shader_parameter("liquid2", Color(0.28, 0.0, 0.01))
		mat.set_shader_parameter("glow", Color(1.0, 0.55, 0.4))
	else:
		mat.set_shader_parameter("liquid", Color(0.16, 0.36, 1.0))
		mat.set_shader_parameter("liquid2", Color(0.01, 0.03, 0.25))
		mat.set_shader_parameter("glow", Color(0.55, 0.8, 1.0))
	liquid.material = mat
	add_child(liquid)
	if ResourceLoader.exists(GLASS_TEX):
		glass = TextureRect.new()
		glass.texture = load(GLASS_TEX)
		glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glass.material = cm
		glass.modulate = Color(0.55, 0.55, 0.55, 1.0)
		add_child(glass)
	if ResourceLoader.exists(FRAME_TEX):
		frame = TextureRect.new()
		frame.texture = load(FRAME_TEX)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
	_layout()

## The globe grows with maximum life/mana: up to a quarter bigger at ten times the starting maximum.
func _layout() -> void:
	var d := base_size * _scale
	var c := size * 0.5
	liquid.size = Vector2(d, d)
	liquid.position = c - Vector2(d, d) * 0.5
	if glass:
		glass.size = Vector2(d, d)
		glass.position = liquid.position
	if frame:
		# the frame's hole is FRAME_HOLE of its width, centred FRAME_HOLE_Y down from the top
		var fw := d / FRAME_HOLE
		frame.size = Vector2(fw, fw * frame.texture.get_height() / frame.texture.get_width())
		frame.position = Vector2(c.x - fw * 0.5, c.y - frame.size.y * FRAME_HOLE_Y)

## Only the round globe and its rim take the mouse, not the clear corners of the square.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= base_size * _scale * 0.62

const FRAME_HOLE := 0.5       # liquid diameter / frame width: the hole (0.484) plus a little under the rim (globe_frame.png)
const FRAME_HOLE_Y := 0.5     # hole centre / frame height

## The standard globes are every character's, including classes added later. A special character can
## override them: give its Data.CLASSES entry a "hud" dictionary, e.g.
##   "hud": {"life_frame": "res://...png", "life": Color(..), "life2": Color(..), "life_glow": Color(..),
##           "mana_frame": "res://...png", "mana": Color(..), "mana2": Color(..), "mana_glow": Color(..)}
## Anything left out keeps the standard look.
func set_style(hud: Dictionary) -> void:
	var defaults := {"life": [Color(0.85, 0.06, 0.05), Color(0.28, 0.0, 0.01), Color(1.0, 0.55, 0.4)],
		"mana": [Color(0.16, 0.36, 1.0), Color(0.01, 0.03, 0.25), Color(0.55, 0.8, 1.0)]}
	var d: Array = defaults[kind]
	mat.set_shader_parameter("liquid", hud.get(kind, d[0]))
	mat.set_shader_parameter("liquid2", hud.get(kind + "2", d[1]))
	mat.set_shader_parameter("glow", hud.get(kind + "_glow", d[2]))
	var ft: String = hud.get(kind + "_frame", FRAME_TEX)
	if frame and ResourceLoader.exists(ft):
		frame.texture = load(ft)
		_layout()

func set_value(v: float, mx: float) -> void:
	value = v
	max_value = maxf(mx, 1.0)

func _process(delta: float) -> void:
	_t += delta
	var f := clampf(value / max_value, 0.0, 1.0)
	if _last < 0.0:
		_last = f
		_shown = f
		_trail = f
		_target = f
	var change := f - _last
	_last = f
	if change < -0.002:
		# a wound (life) or a cast (mana)
		if kind == "life":
			if _target - f > 0.002 and _delay <= 0.0 and _shown >= _target - 0.001:
				_delay = 0.12
			_trail = maxf(_trail, _shown)
			_trail_wait = 0.45
		else:
			_swirl_v += clampf(-change * 14.0, 0.4, 3.0)
			_vel -= 0.6
	elif change > 0.002:
		var big := change > (0.03 if kind == "life" else 0.1)
		if big:
			_ripple = 0.0
	_target = f
	# the level: a spring toward the target (damage waits out its delay, then surges)
	if _delay > 0.0:
		_delay -= delta
	else:
		var stiff := 60.0 if (_target < _shown) else (22.0 if kind == "life" else 9.0)
		var damp := 9.0 if (_target < _shown) else 8.0
		_vel += ((_target - _shown) * stiff - _vel * damp) * delta
		_shown += _vel * delta
	_shown = clampf(_shown, 0.0, 1.0)
	_slosh = lerpf(_slosh, clampf(absf(_vel) * 1.5, 0.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	if _trail_wait > 0.0:
		_trail_wait -= delta
	else:
		_trail = move_toward(_trail, _shown, delta * 0.5)
	_trail = maxf(_trail, _shown)
	_swirl_v *= exp(-delta * 1.6)
	_swirl += _swirl_v * delta
	if _ripple >= 0.0:
		_ripple += delta / (0.75 if kind == "life" else 0.9)
		if _ripple > 1.0:
			_ripple = -1.0
	# low / critical: pulse (and for life, darken and shake)
	var low := 0.0
	var crit := 0.0
	if kind == "life":
		low = clampf((0.35 - f) / 0.2, 0.0, 1.0)
		crit = clampf((0.15 - f) / 0.1, 0.0, 1.0)
	else:
		low = clampf((0.2 - f) / 0.15, 0.0, 1.0) * 0.5
	var beat := 0.5 + 0.5 * sin(_t * (5.5 + crit * 4.0))
	mat.set_shader_parameter("fill", _shown)
	mat.set_shader_parameter("trail", _trail if kind == "life" else _shown)
	mat.set_shader_parameter("slosh", _slosh)
	mat.set_shader_parameter("swirl", _swirl)
	mat.set_shader_parameter("swirl_amt", clampf(absf(_swirl_v), 0.0, 1.0))
	mat.set_shader_parameter("ripple", _ripple)
	mat.set_shader_parameter("ripple_up", kind == "mana")
	mat.set_shader_parameter("pulse", (low * 0.5 + crit * 0.5) * beat)
	mat.set_shader_parameter("dark", crit * 0.35)
	# a bigger maximum makes a bigger globe (smoothly)
	var want := clampf(1.0 + log(max_value / maxf(ref_max, 1.0)) / log(10.0) * 0.25, 1.0, 1.25)
	if absf(want - _scale) > 0.001:
		_scale = move_toward(_scale, want, delta * 0.3)
	_layout()
	if kind == "life" and low > 0.0:
		var amp := low * 0.8 + crit * 2.2
		liquid.position += Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * (0.4 + beat * 0.6)

const GLOBE_SHADER := """
shader_type canvas_item;
uniform vec4 liquid : source_color = vec4(0.85, 0.06, 0.05, 1.0);
uniform vec4 liquid2 : source_color = vec4(0.28, 0.0, 0.01, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.55, 0.4, 1.0);
uniform float fill = 1.0;
uniform float trail = 1.0;
uniform float slosh = 0.0;
uniform float swirl = 0.0;
uniform float swirl_amt = 0.0;
uniform float ripple = -1.0;
uniform bool ripple_up = false;
uniform float pulse = 0.0;
uniform float dark = 0.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n2(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(h(i),h(i+vec2(1,0)),u.x), mix(h(i+vec2(0,1)),h(i+vec2(1,1)),u.x), u.y); }
float fbm(vec2 p){ return n2(p) * 0.55 + n2(p * 2.1 + 3.7) * 0.3 + n2(p * 4.3 - 1.3) * 0.15; }
vec2 rot(vec2 p, float a){ float c = cos(a); float s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }
void fragment(){
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) { discard; }
	float z = sqrt(max(1.0 - r * r, 0.0));
	// the surface: gentle waves, bigger and faster while it's sloshing
	float level = 1.0 - fill * 2.0;
	float amp = 0.018 + slosh * 0.07;
	float wave = sin(uv.x * 5.0 + TIME * (2.2 + slosh * 4.0)) * amp + sin(uv.x * 11.0 - TIME * 3.3) * amp * 0.45;
	float surf_y = level + wave;
	float inside = smoothstep(surf_y - 0.012, surf_y + 0.012, uv.y);
	// the body of the liquid: slow churning, swirled round the middle after a cast
	vec2 q = rot(uv, swirl * (1.2 - r) * swirl_amt * 2.0 + swirl * 0.15);
	float churn = fbm(q * 2.6 + vec2(TIME * 0.18, -TIME * 0.32));
	float vein = fbm(q * 6.0 - vec2(TIME * 0.25, TIME * 0.1));
	float depth = clamp((uv.y - surf_y) * 0.6, 0.0, 1.0);
	vec3 lc = mix(liquid.rgb, liquid2.rgb, depth * 0.7 + (1.0 - churn) * 0.35);
	lc += glow.rgb * pow(vein, 4.0) * 0.5;
	lc *= 0.55 + z * 0.6;
	// bubbles drifting up
	vec2 bp = vec2(uv.x * 9.0, uv.y * 9.0 + TIME * 1.6);
	float b = step(0.93, h(floor(bp))) * (1.0 - smoothstep(0.1, 0.32, length(fract(bp) - 0.5)));
	lc += glow.rgb * b * 0.35 * inside;
	// a bright meniscus line where the surface meets the glass
	float men = (1.0 - smoothstep(0.0, 0.035, abs(uv.y - surf_y))) * step(level - 0.2, uv.y);
	// the pale band of what was just lost (life), draining after the wound
	float tl = 1.0 - trail * 2.0;
	float lost = step(tl, uv.y) * (1.0 - inside);
	// empty glass: dark, smoky
	vec3 empty = vec3(0.025, 0.022, 0.025) + liquid2.rgb * 0.15 * fbm(uv * 3.0 + TIME * 0.05);
	vec3 col = mix(empty, lc, inside);
	col = mix(col, mix(liquid.rgb, vec3(1.0, 0.9, 0.8), 0.35) * 0.55, lost * 0.75);
	col += glow.rgb * men * 0.9;
	// heal ripple: a bright ring spreading from the middle of the liquid; mana restore: a wave rising
	if (ripple >= 0.0) {
		float band;
		if (ripple_up) {
			float y0 = 1.0 - ripple * 2.3;
			band = exp(-pow((uv.y - y0) / 0.09, 2.0));
		} else {
			float d = length(uv - vec2(0.0, max(level, -0.2) * 0.5 + 0.5));
			band = exp(-pow((d - ripple * 1.6) / 0.1, 2.0));
		}
		col += glow.rgb * band * (1.0 - ripple) * 1.4 * inside;
	}
	// low: a pulse of glow; critical: darker, with a red heartbeat from the edge
	col += liquid.rgb * pulse * 0.6 * inside;
	col *= 1.0 - dark * (0.5 + 0.5 * r);
	// the curve of the glass: darker toward the rim
	col *= mix(0.45, 1.0, z);
	float rim = smoothstep(0.94, 1.0, r);
	COLOR = vec4(mix(col, vec3(0.0), rim), 1.0);
}
"""
