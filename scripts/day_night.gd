class_name DayNight
extends Node
## Day and night (jj, 2026-11-04): Act I's camp runs through a whole day. The sun rises in the east, arcs across the
## south and sets in the west, and the moon follows it through the night; the one shadowed DirectionalLight (Game.sun)
## is whichever of them is up, so every shadow in the camp swings round and stretches through the day. The sky, the
## ambient light, the mist (morning mist low and thick, thin at noon), the exposure, the bloom and the hero's light
## and rim follow KEYS, the camp's look at each hour (night is the dusk-under-the-canopy look the camp was tuned to);
## the lanterns go out by day and are lit at dusk, the fires burn lower in daylight (Game.lamp_mul / fire_mul in the
## flicker loop), fireflies come out at night, and the guards go on their night rounds (CampGuard reads `night`).
##
## The clock is the wall clock (one day every DAY_LEN seconds), so every game in a co-op party sees the same hour
## without a word on the network. `-- --time 13.5` holds it at an hour, `--day-len 120` runs a day in two minutes.
## Game owns one (Game.day_night); `enable(true)` in the camp (Game._zone_env), off elsewhere (the zone's own look).

const DAY_LEN := 1800.0          # real seconds per day: half an hour
const SUNRISE := 6.0
const SUNSET := 19.5
const SUN_ELEV := 62.0           # degrees at noon (never overhead: the shadows keep a direction)
const MOON_ELEV := 46.0
const MIN_ELEV := 11.0           # the light's direction never drops below this (grazing shadows smear), its strength does

## The camp's look by the hour (the night is Game._zone_env's tuned forest-camp dusk). Each key: hour, then values;
## between keys everything is blended. sun_e is the light's strength at full height; it fades as the sun (or the
## moon) sinks to the horizon.
const KEYS := [
	{"h": 0.0, "sun_c": Color(0.58, 0.7, 0.92), "sun_e": 0.62, "amb": 0.62, "exp": 1.5, "fog_c": Color(0.2, 0.26, 0.29), "fog": 0.009, "fog_h": 0.1,
		"vol": 0.014, "vol_a": Color(0.62, 0.7, 0.72), "vol_e": Color(0.016, 0.022, 0.028), "top": Color(0.1, 0.13, 0.17), "hor": Color(0.24, 0.29, 0.31),
		"gnd": Color(0.2, 0.24, 0.25), "sat": 0.97, "glow": 0.95, "bloom": 0.1, "lamps": 1.0, "fires": 1.0, "hero": 1.7, "flies": 1.0},
	{"h": 4.5, "sun_c": Color(0.58, 0.7, 0.92), "sun_e": 0.55, "amb": 0.6, "exp": 1.5, "fog_c": Color(0.2, 0.26, 0.3), "fog": 0.01, "fog_h": 0.12,
		"vol": 0.016, "vol_a": Color(0.62, 0.7, 0.74), "vol_e": Color(0.016, 0.022, 0.03), "top": Color(0.09, 0.12, 0.17), "hor": Color(0.22, 0.27, 0.31),
		"gnd": Color(0.19, 0.23, 0.25), "sat": 0.96, "glow": 0.95, "bloom": 0.1, "lamps": 1.0, "fires": 1.0, "hero": 1.7, "flies": 0.7},
	# dawn: a pink-gold sun low in the east, the morning mist lying thick between the tents
	{"h": 6.2, "sun_c": Color(1.0, 0.6, 0.45), "sun_e": 0.9, "amb": 0.56, "exp": 1.38, "fog_c": Color(0.34, 0.33, 0.36), "fog": 0.011, "fog_h": 0.16,
		"vol": 0.019, "vol_a": Color(0.82, 0.78, 0.78), "vol_e": Color(0.022, 0.018, 0.02), "top": Color(0.24, 0.26, 0.36), "hor": Color(0.78, 0.52, 0.42),
		"gnd": Color(0.4, 0.32, 0.3), "sat": 0.94, "glow": 0.9, "bloom": 0.1, "lamps": 0.75, "fires": 0.9, "hero": 1.3, "flies": 0.0},
	{"h": 8.0, "sun_c": Color(1.0, 0.86, 0.7), "sun_e": 1.3, "amb": 0.6, "exp": 1.16, "fog_c": Color(0.42, 0.48, 0.46), "fog": 0.006, "fog_h": 0.07,
		"vol": 0.011, "vol_a": Color(0.84, 0.88, 0.85), "vol_e": Color(0.014, 0.017, 0.015), "top": Color(0.34, 0.47, 0.62), "hor": Color(0.64, 0.68, 0.66),
		"gnd": Color(0.34, 0.37, 0.31), "sat": 0.95, "glow": 0.8, "bloom": 0.08, "lamps": 0.12, "fires": 0.55, "hero": 0.8, "flies": 0.0},
	# noon: the brightest the old forest gets, green light through the canopy, the mist burnt off
	{"h": 13.0, "sun_c": Color(1.0, 0.95, 0.86), "sun_e": 1.5, "amb": 0.62, "exp": 1.05, "fog_c": Color(0.44, 0.52, 0.48), "fog": 0.004, "fog_h": 0.035,
		"vol": 0.007, "vol_a": Color(0.84, 0.88, 0.85), "vol_e": Color(0.012, 0.015, 0.012), "top": Color(0.38, 0.52, 0.68), "hor": Color(0.66, 0.72, 0.7),
		"gnd": Color(0.36, 0.4, 0.33), "sat": 0.98, "glow": 0.75, "bloom": 0.07, "lamps": 0.05, "fires": 0.45, "hero": 0.6, "flies": 0.0},
	{"h": 17.0, "sun_c": Color(1.0, 0.84, 0.62), "sun_e": 1.32, "amb": 0.6, "exp": 1.12, "fog_c": Color(0.46, 0.45, 0.4), "fog": 0.005, "fog_h": 0.05,
		"vol": 0.009, "vol_a": Color(0.88, 0.85, 0.78), "vol_e": Color(0.016, 0.014, 0.011), "top": Color(0.34, 0.44, 0.58), "hor": Color(0.74, 0.66, 0.56),
		"gnd": Color(0.38, 0.36, 0.3), "sat": 0.98, "glow": 0.8, "bloom": 0.08, "lamps": 0.1, "fires": 0.55, "hero": 0.7, "flies": 0.0},
	# sunset: a low red-gold sun in the west, long shadows across the camp, the lanterns being lit
	{"h": 19.0, "sun_c": Color(1.0, 0.5, 0.3), "sun_e": 1.0, "amb": 0.55, "exp": 1.3, "fog_c": Color(0.38, 0.3, 0.27), "fog": 0.008, "fog_h": 0.09,
		"vol": 0.014, "vol_a": Color(0.84, 0.72, 0.66), "vol_e": Color(0.022, 0.015, 0.012), "top": Color(0.2, 0.2, 0.32), "hor": Color(0.84, 0.45, 0.3),
		"gnd": Color(0.4, 0.27, 0.22), "sat": 0.98, "glow": 0.9, "bloom": 0.1, "lamps": 0.7, "fires": 0.85, "hero": 1.1, "flies": 0.2},
	# dusk: the moon rising, the camp's own blue hour
	{"h": 20.6, "sun_c": Color(0.6, 0.7, 0.92), "sun_e": 0.6, "amb": 0.6, "exp": 1.48, "fog_c": Color(0.21, 0.25, 0.3), "fog": 0.009, "fog_h": 0.1,
		"vol": 0.015, "vol_a": Color(0.64, 0.7, 0.74), "vol_e": Color(0.018, 0.022, 0.03), "top": Color(0.11, 0.13, 0.19), "hor": Color(0.27, 0.29, 0.34),
		"gnd": Color(0.21, 0.24, 0.26), "sat": 0.97, "glow": 0.95, "bloom": 0.1, "lamps": 1.0, "fires": 1.0, "hero": 1.6, "flies": 0.9},
	{"h": 24.0, "sun_c": Color(0.58, 0.7, 0.92), "sun_e": 0.62, "amb": 0.62, "exp": 1.5, "fog_c": Color(0.2, 0.26, 0.29), "fog": 0.009, "fog_h": 0.1,
		"vol": 0.014, "vol_a": Color(0.62, 0.7, 0.72), "vol_e": Color(0.016, 0.022, 0.028), "top": Color(0.1, 0.13, 0.17), "hor": Color(0.24, 0.29, 0.31),
		"gnd": Color(0.2, 0.24, 0.25), "sat": 0.97, "glow": 0.95, "bloom": 0.1, "lamps": 1.0, "fires": 1.0, "hero": 1.7, "flies": 1.0},
]
const DEFAULT_SUN := Vector3(-52, -38, 0)    # Game._setup_env's sun, put back when the cycle is off
const LAMP_GROUP := "day_night_lamp"         # a candle's glowing core (ForestCamp._candle): hidden by day

var game: Node
var on := false
var hour := 20.6                 # 0..24
var night := 1.0                 # 0 by day .. 1 at night (lanterns, fireflies, the guards' night rounds)
var moon_up := false             # the light is the moon
var fixed := -1.0                # --time, or the admin panel's hour (-1 = the wall clock)
var pace := 0.0                  # the hand-set hour runs on at this many times the day's pace (0 = held)
var night_shift := 0             # the admin panel's step through the night beds (this game only)
var day_len := DAY_LEN
var _was_night := -1
var _flies: GPUParticles3D = null
var _lit := true
var _lamps_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # the admin panel sets the hour from the pause menu: show it behind
	var a := OS.get_cmdline_user_args()
	var i := a.find("--time")
	if i >= 0 and i + 1 < a.size():
		fixed = fposmod(float(a[i + 1]), 24.0)
	i = a.find("--day-len")
	if i >= 0 and i + 1 < a.size():
		day_len = maxf(10.0, float(a[i + 1]))

## The hour now: the wall clock's, the same on every game.
func clock() -> float:
	if fixed >= 0.0:
		return fixed
	return fposmod(Time.get_unix_time_from_system() / day_len * 24.0, 24.0)

func enable(yes: bool) -> void:
	on = yes
	_was_night = -1
	if not yes:
		night = 0.0
		_lit = true
		game.lamp_mul = 1.0
		game.fire_mul = 1.0
		game.sun.rotation_degrees = DEFAULT_SUN
		if _flies != null and is_instance_valid(_flies):
			_flies.queue_free()
		_flies = null
		return
	_make_flies()
	update(0.0)

func _process(delta: float) -> void:
	if fixed >= 0.0 and pace > 0.0:
		fixed = fposmod(fixed + delta * 24.0 / day_len * pace, 24.0)
	if on:
		update(delta)

## The admin panel's clock (this game only; partners keep the wall clock): hold the camp at an hour, or let it run
## on from there at `p` times the day's pace. A pace below 0 keeps the one it has.
func set_hour(h: float, p := -1.0) -> void:
	fixed = fposmod(h, 24.0)
	if p >= 0.0:
		pace = p
	if on:
		update(0.0)

## Which night this is, counted on the wall clock from one sunset to the next, so every game in a party hears the
## same night's bed (jj: five unique nights, one each night in turn; `night_forest` takes 0..4).
func night_number() -> int:
	return int(floor((Time.get_unix_time_from_system() / day_len * 24.0 - SUNSET) / 24.0))

func night_take() -> int:
	return posmod(night_number() + night_shift, maxi(1, (Sfx.bank.get("night_forest", [null]) as Array).size()))

## The admin panel's "Next night's sounds": step this game on to the next bed (and play it, if it's dark).
func next_night_bed() -> void:
	night_shift += 1
	if on and night > 0.5:
		Sfx.play_music("town", "night_forest", night_take())

## Back to the wall clock, the hour every game shares.
func live() -> void:
	fixed = -1.0
	pace = 0.0
	if on:
		update(0.0)

## Everything at the hour now: the sky, the light and its direction, the mist and the lamps.
func update(delta: float) -> void:
	if game == null or game.env == null or game.sun == null:
		return
	hour = clock()
	var k := sample(hour)
	var env: Environment = game.env
	# the sun or the moon, whichever is up, as the one shadowed light
	var sun_el := _elev(hour, SUNRISE, SUNSET, SUN_ELEV)
	var moon_h := fposmod(hour - (SUNSET + 0.6), 24.0)
	var moon_el := _elev(moon_h, 0.0, 24.0 - (SUNSET + 0.6) + SUNRISE - 0.3, MOON_ELEV)
	var sun_f := smoothstep(-2.0, 8.0, sun_el)
	var moon_f := smoothstep(-2.0, 8.0, moon_el)
	moon_up = moon_f > sun_f
	var el: float
	var az: float
	if moon_up:
		el = moon_el
		az = _azimuth(moon_h, 0.0, 24.0 - (SUNSET + 0.6) + SUNRISE - 0.3)
	else:
		el = sun_el
		az = _azimuth(hour, SUNRISE, SUNSET)
	var strength := maxf(sun_f, moon_f)
	var dir := _dir(maxf(el, MIN_ELEV), az)
	game.sun.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD), Vector3.ZERO)
	game.sun.light_color = k["sun_c"]
	game.sun.light_energy = float(k["sun_e"]) * lerpf(0.18, 1.0, strength)
	# low light makes long, soft shadows
	game.sun.shadow_blur = lerpf(2.6, 1.4, smoothstep(10.0, 45.0, el))
	game.sky_mat.sky_top_color = k["top"]
	game.sky_mat.sky_horizon_color = k["hor"]
	game.sky_mat.ground_horizon_color = k["gnd"]
	env.ambient_light_energy = k["amb"]
	env.tonemap_exposure = k["exp"]
	env.fog_light_color = k["fog_c"]
	env.fog_density = k["fog"]
	env.fog_height_density = k["fog_h"]
	env.volumetric_fog_density = k["vol"]
	env.volumetric_fog_albedo = k["vol_a"]
	env.volumetric_fog_emission = k["vol_e"]
	env.adjustment_saturation = k["sat"]
	env.glow_intensity = k["glow"]
	env.glow_bloom = k["bloom"]
	game.lamp_mul = k["lamps"]
	game.fire_mul = k["fires"]
	if game.hero != null and game.hero.light != null:
		game.hero.light.light_energy = k["hero"]
	night = clampf(float(k["lamps"]), 0.0, 1.0)
	# the candles in the lanterns: put out in daylight, lit again at dusk
	var lit := night > (0.25 if _lit else 0.35)
	if lit != _lit or _lamps_t <= 0.0:
		_lit = lit
		_lamps_t = 1.0
		for n in game.get_tree().get_nodes_in_group(LAMP_GROUP):
			(n as Node3D).visible = lit
	_lamps_t -= delta
	if _flies != null and is_instance_valid(_flies):
		_flies.amount_ratio = clampf(float(k["flies"]), 0.0, 1.0)
		_flies.emitting = float(k["flies"]) > 0.02
		var c: Vector3 = game.cam_target
		_flies.global_position = Vector3(c.x, 0.0, c.z)
	_announce()

## The camp hears the turn of the day.
func _announce() -> void:
	var n := 1 if night > 0.5 else 0
	if n != _was_night and Sfx.bank.has("night_forest"):
		# the bed under the camp: tonight's night sounds after dark (a different one each night), the wind by day
		Sfx.play_music("town", "night_forest" if n == 1 else "", night_take())
	if _was_night >= 0 and n != _was_night and game.ui != null:
		game.ui.message("Night falls over the camp." if n == 1 else "Dawn breaks over the old forest.", Color(0.75, 0.82, 1.0) if n == 1 else Color(1.0, 0.85, 0.6))
	_was_night = n

## The look at an hour, blended between KEYS.
static func sample(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	for i in KEYS.size() - 1:
		var a: Dictionary = KEYS[i]
		var b: Dictionary = KEYS[i + 1]
		if h >= float(a["h"]) and h <= float(b["h"]):
			var f := (h - float(a["h"])) / maxf(0.001, float(b["h"]) - float(a["h"]))
			f = f * f * (3.0 - 2.0 * f)
			var out := {}
			for key in a:
				var va: Variant = a[key]
				var vb: Variant = b[key]
				if va is Color:
					out[key] = (va as Color).lerp(vb as Color, f)
				else:
					out[key] = lerpf(float(va), float(vb), f)
			return out
	return KEYS[0]

## Height of a body above the horizon (degrees) through its arc from rise to set (hours), below it otherwise.
static func _elev(h: float, rise: float, set_h: float, top: float) -> float:
	if h < rise or h > set_h:
		var off := minf(absf(h - rise), absf(h - set_h))
		return -off * 12.0
	return top * sin(PI * (h - rise) / (set_h - rise))

## Compass bearing (degrees, north 0, east 90): east at rising, south at the top, west at setting.
static func _azimuth(h: float, rise: float, set_h: float) -> float:
	var f := clampf((h - rise) / (set_h - rise), 0.0, 1.0)
	return 90.0 + 180.0 * f

## The direction toward a body (Godot: north is -z, east +x).
static func _dir(el_deg: float, az_deg: float) -> Vector3:
	var el := deg_to_rad(el_deg)
	var az := deg_to_rad(az_deg)
	var d := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
	return d.normalized()

## Fireflies drifting over the camp after dark (round the camera; their amount follows the hour).
func _make_flies() -> void:
	if _flies != null and is_instance_valid(_flies) and _flies.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = 90
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.visibility_aabb = AABB(Vector3(-24, -1, -24), Vector3(48, 6, 48))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 1.0, 20)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	var fade := Gradient.new()
	fade.set_offset(0, 0.0)
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_offset(1, 1.0)
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.45, Color(1, 1, 1, 0.25))
	fade.add_point(0.65, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 0.4))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 1.0, 0.45)
	m.emission_enabled = true
	m.emission = Color(0.7, 1.0, 0.4)
	m.emission_energy_multiplier = 4.0
	m.albedo_texture = _dot()
	q.material = m
	p.draw_pass_1 = q
	p.position.y = 1.2
	game.world.fx_root.add_child(p)
	_flies = p

static func _dot() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
