class_name GrassField
extends Node
## The grass's sense of touch and the wind that moves it.
##
## Touch: a small GPU simulation that follows the camera (SIZE m square, RES texels: 25 cm each). Every
## texel holds how far the grass there is bent (x, z) and how fast it is moving, and runs as a damped
## spring, so grass that is pushed over overshoots a little on release and settles back instead of
## snapping. Each frame, every character presses a capsule along the path it actually moved (sized by
## its body, harder when sprinting or dashing, a slow flattening while it stands); swings press an arc in
## front of the swinger on its impact frame; slams, novas and spells (Fx.ring and friends, or
## `GrassField.impulse`) shove a ring outward. Two SubViewports take turns: each frame one integrates
## from the other's last result. The grass shader reads the newest finished one through the global
## `grass_field` (RG = bend, BA = velocity, 0.5 = rest), placed by `grass_field_rect`.
## Everything here is local and cosmetic: partners and monsters already arrive at every peer's
## positions and attack timings, so each player's grass reacts to the same things with no new traffic.
##
## Wind: global uniforms shared by every grass material (`wind_dir`, `wind_strength`, `wind_gust`,
## `wind_phase`): gust fronts roll along the wind at a speed that rises with it, and changes of
## strength or direction blend over a few seconds. Zones pick a profile (`WIND`), and the strength
## drifts slowly on its own so the field is never quite the same.

const RES := 256
const SIZE := 64.0
const MAX_STAMPS := 48
## how far ahead of the camera's target the field sits (the top of the screen is further away)
const AHEAD := Vector3(0, 0, -6.0)

## Wind per zone: direction (degrees, 0 = blowing toward +x, 90 = toward +z), strength (0 calm .. 1 gale),
## gustiness (how much gust fronts add on top) and how much it drifts by itself.
const WIND := {
	"default": {"dir": 30.0, "strength": 0.45, "gust": 0.6, "drift": 0.35},
	"moor": {"dir": 25.0, "strength": 0.55, "gust": 0.7, "drift": 0.4},
	"camp": {"dir": 40.0, "strength": 0.28, "gust": 0.4, "drift": 0.25},
	"fort": {"dir": 15.0, "strength": 0.45, "gust": 0.55, "drift": 0.3},
	"calm": {"dir": 0.0, "strength": 0.12, "gust": 0.25, "drift": 0.1},
	"storm": {"dir": 20.0, "strength": 0.95, "gust": 1.0, "drift": 0.2},
}

static var inst: GrassField = null

## Who touches the grass: returns an Array of Node3D (heroes, partners, monsters, pets). Set by the owner.
var movers_fn: Callable
## The point the field follows (usually the camera's target), and the camera itself (for the shader's
## distance fade, which must agree between the camera and the shadow passes).
var center := Vector3.ZERO
var cam_pos := Vector3(0, 20, 20)
var enabled := true
## scales every touch (0 turns interaction off, e.g. on the lowest preset)
var touch := 1.0

var _vp: Array[SubViewport] = []
var _mat: Array[ShaderMaterial] = []
var _cur := 0
var _origin := Vector2.ZERO
var _last := {}           # instance id -> [last position, impact already fired for the current attack]
var _events: Array = []   # live rings/arcs: {"p", "r", "w", "s", "t", "dur", "dir", "cos"}
var _sa := PackedVector4Array()
var _sb := PackedVector4Array()
var _sc := PackedVector4Array()

# wind state
var _wind_now := {"dir": 30.0, "strength": 0.45, "gust": 0.6, "drift": 0.35}
var _wind_from := {}
var _wind_to := {}
var _wind_t := 1.0
var _wind_len := 1.0
var _phase := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()

func _ready() -> void:
	inst = self
	Mats.ensure_globals()
	_noise.seed = 5113
	_noise.frequency = 0.02
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(RES, RES)
		vp.disable_3d = true
		vp.transparent_bg = true   # keep the alpha channel exactly as written (velocity z)
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		var cr := ColorRect.new()
		cr.size = Vector2(RES, RES)
		var m := ShaderMaterial.new()
		m.shader = _sim_shader()
		cr.material = m
		vp.add_child(cr)
		add_child(vp)
		_vp.append(vp)
		_mat.append(m)
	_mat[0].set_shader_parameter("prev", _vp[1].get_texture())
	_mat[1].set_shader_parameter("prev", _vp[0].get_texture())
	# start both at rest
	for m in _mat:
		m.set_shader_parameter("reset", true)
	for vp in _vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wind_from = _wind_now.duplicate()
	_wind_to = _wind_now.duplicate()
	_apply_wind_globals(0.0)

func _exit_tree() -> void:
	if inst == self:
		inst = null
		RenderingServer.global_shader_parameter_set("grass_field_rect", Vector4(0, 0, SIZE, 0.0))

## A shove that spreads out as a ring (slams, novas, landings): strength 0..1 (1 lays the grass flat
## for a moment), radius in metres. Safe to call with no field.
static func impulse(pos: Vector3, radius: float, strength := 0.7, dur := 0.35) -> void:
	if inst == null:
		return
	inst._events.append({"p": Vector2(pos.x, pos.z), "r": maxf(radius, 0.5), "w": clampf(radius * 0.22, 0.35, 1.4),
		"s": strength, "t": 0.0, "dur": dur, "dir": Vector2.ZERO, "cos": -2.0})

## A swing: an arc of grass thrown outward in front of `pos` along `facing` (half-angle in degrees).
static func swing(pos: Vector3, facing: Vector3, reach: float, strength := 0.5, half_deg := 70.0) -> void:
	if inst == null:
		return
	var f := Vector2(facing.x, facing.z)
	if f.length() < 0.01:
		f = Vector2(0, -1)
	inst._events.append({"p": Vector2(pos.x, pos.z), "r": maxf(reach, 0.8), "w": 0.45, "s": strength, "t": 0.0,
		"dur": 0.22, "dir": f.normalized(), "cos": cos(deg_to_rad(half_deg))})

## Change the wind (a WIND key or a profile dictionary), blending over `blend` seconds.
func set_wind(profile, blend := 3.0) -> void:
	var p: Dictionary = WIND.get(profile, WIND["default"]) if profile is String else profile
	_wind_from = _wind_now.duplicate()
	_wind_to = p.duplicate()
	_wind_t = 0.0
	_wind_len = maxf(blend, 0.01)

func wind() -> Dictionary:
	return _wind_now

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 1.0 / 15.0)
	_time += delta
	_update_wind(delta)
	RenderingServer.global_shader_parameter_set("grass_cam", cam_pos)
	if not enabled:
		RenderingServer.global_shader_parameter_set("grass_field_rect", Vector4(_origin.x, _origin.y, SIZE, 0.0))
		return
	# the field moves in whole texels so the grass under it doesn't shimmer
	var texel := SIZE / RES
	var want := Vector2(center.x + AHEAD.x, center.z + AHEAD.z) - Vector2(SIZE, SIZE) * 0.5
	var snapped := Vector2(floor(want.x / texel), floor(want.y / texel)) * texel
	var shift := (snapped - _origin) / SIZE
	if shift.length() > 0.9:
		shift = Vector2(4, 4)   # jumped (travel, teleport): nothing to carry over
	_origin = snapped
	_build_stamps(dt)
	# integrate into the viewport that isn't on show; the grass reads the one finished last frame
	var nxt := 1 - _cur
	var m := _mat[nxt]
	m.set_shader_parameter("reset", false)
	m.set_shader_parameter("shift", shift)
	m.set_shader_parameter("rect", Vector4(_origin.x, _origin.y, SIZE, texel))
	m.set_shader_parameter("dt", dt)
	m.set_shader_parameter("n", _sa.size())
	m.set_shader_parameter("sa", _sa)
	m.set_shader_parameter("sb", _sb)
	m.set_shader_parameter("sc", _sc)
	_vp[nxt].render_target_update_mode = SubViewport.UPDATE_ONCE
	# the one on show was integrated from last frame's origin: hand that origin to the grass with it
	RenderingServer.global_shader_parameter_set("grass_field", _vp[_cur].get_texture())
	shown_rect = Vector4(_shown_origin.x, _shown_origin.y, SIZE, touch)
	RenderingServer.global_shader_parameter_set("grass_field_rect", shown_rect)
	_shown_origin = _origin
	_cur = nxt

var _shown_origin := Vector2.ZERO
## the field on show to the grass right now, and where it lies (origin x, z, size, strength): for tests
var shown_rect := Vector4(0, 0, SIZE, 0)
func shown_image() -> Image:
	return _vp[1 - _cur].get_texture().get_image()

func _build_stamps(dt: float) -> void:
	_sa.clear()
	_sb.clear()
	_sc.clear()
	var lo := _origin - Vector2(2, 2)
	var hi := _origin + Vector2(SIZE + 2, SIZE + 2)
	var seen := {}
	var movers: Array = movers_fn.call() if movers_fn.is_valid() else []
	for n in movers:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var nd := n as Node3D
		var id := nd.get_instance_id()
		seen[id] = true
		var p := nd.global_position
		var rec: Array = _last.get(id, [p, false])
		var p0: Vector3 = rec[0]
		var step := p - p0
		step.y = 0
		if step.length() > 3.0:   # teleported or spawned: no streak across the field
			p0 = p
			step = Vector3.ZERO
		_last[id] = [p, rec[1]]
		if "dead" in nd and bool(nd.get("dead")):
			continue
		if p.x < lo.x or p.z < lo.y or p.x > hi.x or p.z > hi.y:
			continue
		var r := 0.45
		if "radius" in nd:
			r = float(nd.get("radius"))
		var speed := step.length() / maxf(dt, 0.001)
		# reach of the touch: about the stance (legs and feet), a little wider when running; big beasts more
		var reach := r * 1.05 + 0.12 + clampf(speed * 0.012, 0.0, 0.18)
		# standing: a soft, slowly settling press; walking parts the grass; sprinting/dashing throws it
		var s := 0.42 + clampf(speed / 7.5, 0.0, 1.0) * 0.5 + clampf((speed - 8.0) / 8.0, 0.0, 0.25)
		s *= clampf(r / 0.45, 0.8, 1.6)
		var mv := Vector2(step.x, step.z).normalized() * clampf(speed / 6.0, 0.0, 1.0) if speed > 0.2 else Vector2.ZERO
		_push(Vector4(p0.x, p0.z, p.x, p.z), Vector4(reach, s, mv.x, mv.y), Vector4(0, 0, 0, 0))
		_watch_attack(nd, id, r)
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)
	# rings and arcs: a band that sweeps outward over the event's life
	var keep: Array = []
	for e in _events:
		e["t"] = float(e["t"]) + dt
		var k := float(e["t"]) / float(e["dur"])
		if k >= 1.0:
			continue
		keep.append(e)
		var pp: Vector2 = e["p"]
		var rr := lerpf(0.25, float(e["r"]), sqrt(k))
		var fade := 1.0 - smoothstep(0.55, 1.0, k)
		var dir: Vector2 = e["dir"]
		_push(Vector4(pp.x, pp.y, rr, float(e["w"])), Vector4(float(e["s"]) * fade, float(e["cos"]), dir.x, dir.y), Vector4(1, 0, 0, 0))
	_events = keep

func _push(a: Vector4, b: Vector4, c: Vector4) -> void:
	if _sa.size() >= MAX_STAMPS:
		return
	_sa.append(a)
	_sb.append(b)
	_sc.append(c)

## On the frame a mover's attack lands (its timing comes from Anim, the same on every peer), throw the
## grass in front of it; heavy blows (slams, mauls, quakes) also send a ring along the ground.
func _watch_attack(nd: Node3D, id: int, r: float) -> void:
	if not ("atk_t" in nd and "atk_dur" in nd):
		return
	var at := float(nd.get("atk_t"))
	var rec: Array = _last[id]
	if at < 0.0:
		rec[1] = false
		return
	var style := String(nd.get("atk_style")) if "atk_style" in nd else "over"
	var hit := Anim.impact_at(style)
	var prog := at / maxf(float(nd.get("atk_dur")), 0.01)
	if bool(rec[1]) or prog < hit:
		return
	rec[1] = true
	if style == "bow" or style.begins_with("shoot") or style == "cast":
		return
	var fwd := Vector3(0, 0, -1)
	if "rig" in nd and nd.get("rig") is Node3D:
		fwd = -(nd.get("rig") as Node3D).global_transform.basis.z
	var size := clampf(r / 0.45, 0.8, 3.0)
	GrassField.swing(nd.global_position + fwd * 0.3, fwd, 1.5 + r * 1.4, 0.45 + 0.1 * size, 75.0)
	for word in ["slam", "maul", "quake", "smash", "stomp", "cleave"]:
		if word in style:
			GrassField.impulse(nd.global_position + fwd * (0.8 + r), 1.8 + r * 1.6, 0.55 + 0.1 * size, 0.45)
			break

func _update_wind(delta: float) -> void:
	if _wind_t < 1.0:
		_wind_t = minf(1.0, _wind_t + delta / _wind_len)
		var k := smoothstep(0.0, 1.0, _wind_t)
		for key in ["strength", "gust", "drift"]:
			_wind_now[key] = lerpf(float(_wind_from.get(key, 0.4)), float(_wind_to.get(key, 0.4)), k)
		_wind_now["dir"] = rad_to_deg(lerp_angle(deg_to_rad(float(_wind_from.get("dir", 0.0))), deg_to_rad(float(_wind_to.get("dir", 0.0))), k))
	_apply_wind_globals(delta)

func _apply_wind_globals(delta: float) -> void:
	# slow natural drift: a lull, then a stronger spell, and the direction wanders a few degrees
	var drift := float(_wind_now.get("drift", 0.3))
	var s := float(_wind_now["strength"]) * (1.0 + drift * _noise.get_noise_1d(_time * 1.2) * 0.9)
	s = clampf(s, 0.02, 1.2)
	var a := deg_to_rad(float(_wind_now["dir"]) + _noise.get_noise_1d(_time * 0.6 + 400.0) * 18.0 * drift)
	# gust fronts travel faster in a stronger wind (metres per second along the wind)
	_phase += delta * (2.5 + s * 6.0)
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(cos(a), sin(a)))
	RenderingServer.global_shader_parameter_set("wind_strength", s)
	RenderingServer.global_shader_parameter_set("wind_gust", float(_wind_now["gust"]))
	RenderingServer.global_shader_parameter_set("wind_phase", _phase)

static var _shader_cache: Shader = null
static func _sim_shader() -> Shader:
	if _shader_cache == null:
		_shader_cache = Shader.new()
		_shader_cache.code = SIM_SHADER
	return _shader_cache

## The spring step. Bend d and velocity v are stored 0..1 (0.5 = rest): d in -1..1, v in -VR..VR.
## Capsules (kind 0) hold the grass toward their push while they cover it; rings and arcs (kind 1)
## shove it, adding to its velocity. Then the spring pulls everything back.
const SIM_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D prev : filter_nearest, repeat_disable;
uniform bool reset = true;
uniform vec2 shift;
uniform vec4 rect;
uniform float dt = 0.016;
uniform float stiff = 20.0;
uniform float damp = 4.0;
uniform int n = 0;
uniform vec4 sa[48];
uniform vec4 sb[48];
uniform vec4 sc[48];
const float VR = 6.0;
void fragment(){
	vec2 uv = UV;
	vec2 d = vec2(0.0);
	vec2 v = vec2(0.0);
	vec2 puv = uv + shift;
	if (!reset && puv.x >= 0.0 && puv.y >= 0.0 && puv.x <= 1.0 && puv.y <= 1.0) {
		vec4 p = texture(prev, puv);
		d = p.rg * 2.0 - 1.0;
		v = (p.ba * 2.0 - 1.0) * VR;
	}
	vec2 w = rect.xy + uv * rect.z;
	vec2 tgt = vec2(0.0);
	float hold = 0.0;
	vec2 kick = vec2(0.0);
	for (int i = 0; i < n; i++) {
		vec4 a = sa[i];
		vec4 b = sb[i];
		if (sc[i].x < 0.5) {
			// capsule from a.xy to a.zw, reach b.x, strength b.y, motion b.zw
			vec2 ab = a.zw - a.xy;
			float h = clamp(dot(w - a.xy, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
			vec2 off = w - (a.xy + ab * h);
			float dist = length(off);
			if (dist < b.x) {
				float f = 1.0 - smoothstep(b.x * 0.3, b.x, dist);
				vec2 dir = dist > 1e-4 ? off / dist : vec2(0.0);
				vec2 t = (dir + b.zw * 0.45) * f * b.y;
				tgt += t;
				hold = max(hold, f * min(b.y, 1.0));
			}
		} else {
			// ring centre a.xy, radius a.z, band width a.w; strength b.x, arc cos b.y around facing b.zw
			vec2 off = w - a.xy;
			float dist = length(off);
			float band = 1.0 - smoothstep(0.0, a.w, abs(dist - a.z));
			if (band > 0.0 && dist > 1e-3) {
				vec2 dir = off / dist;
				float arc = b.y < -1.5 ? 1.0 : smoothstep(b.y - 0.15, b.y + 0.1, dot(dir, b.zw));
				kick += dir * band * arc * b.x;
			}
		}
	}
	float tl = length(tgt);
	if (tl > 1.0) { tgt /= tl; }
	// rings and arcs: a shove (acceleration) the spring then answers
	v += kick * 40.0 * dt;
	// the spring and its damping (semi-implicit Euler)
	v += (-stiff * d - damp * v) * dt;
	d += v * dt;
	// under a character: driven toward its push, quickly; let go, the spring takes over from rest
	float k = clamp(hold * dt * 12.0, 0.0, 1.0);
	d = mix(d, tgt, k);
	v = mix(v, vec2(0.0), k);
	float dl = length(d);
	if (dl > 1.0) { d /= dl; dl = 1.0; }
	v = clamp(v, vec2(-VR), vec2(VR));
	// 8-bit storage rounds tiny spring steps away, which would leave grass stuck a little bent:
	// once it is nearly still, walk it home by at least one storage step a frame
	if (length(v) < 0.12 && dl > 0.0 && hold < 0.05) {
		float nl = max(0.0, dl - max(dl * dt * 1.5, 0.011));
		d *= nl / dl;
		dl = nl;
	}
	if (dl < 0.012 && length(v) < 0.06) { d = vec2(0.0); v = vec2(0.0); }
	COLOR = vec4(d * 0.5 + 0.5, v / VR * 0.5 + 0.5);
}
"""
