class_name ClassStage
extends SubViewportContainer
## The New Character screen's heroes (UI._build_class_picker): every class stands on its own carved plinth in a
## ruined cathedral (ClassCathedral: a shaft of light in its colour, its banner above, candles, drifting ash),
## in its own little world, as the co-op puppets are (Hero with `puppet`, driven by `net_st`), in
## its starting gear. The chosen one's shaft and runes blaze; the one under the mouse brightens. Idle they breathe, shift their weight and look about; under the mouse each fidgets in its
## own annoying way (`_fidget`); the chosen one steps into the light and does its signature move every few
## seconds (`_signature`, with its effects). `hovered` / `chosen` are class ids ("" for none).

signal picked(cls: String)
signal hovering(cls: String)

## left to right on the stage; the knight, the first choice, stands in the middle
const CLASSES := ["wraith", "demon", "knight", "warlock", "archer"]
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.92, 0.24, 0.3)}
## the banner's emblem (ClassCathedral.BANNER_SHADER): cross, hood, horns, hat, arrow
const EMBLEMS := {"knight": 1, "wraith": 2, "demon": 3, "warlock": 4, "archer": 5}
const SPACING := 2.05
const PLINTH_TOP := 0.78            # feet height on a plinth (the middle one is taller, nearer and wider)
const PLINTH_R := 0.6
const STEP := 0.1                   # how far the chosen one steps forward on its plinth
const FACE := PI                     # bodies face -z; the camera is on +z
## signature moves: [pose style, seconds, impact fraction, skill name]
const SIGNATURE := {"knight": ["cleave", 1.1, 0.5, "Holy Slam"], "wraith": ["cast", 1.2, 0.45, "Banshee Wail"],
	"demon": ["side", 0.9, 0.45, "Hellfire Claw"], "warlock": ["cast", 1.8, 0.2, "Drain Life"], "archer": ["bow", 1.0, 0.55, "Volley"]}
const SIG_EVERY := 4.5

var game: Node
var vp: SubViewport
var cam: Camera3D
var root3d: Node3D
var heroes := {}                    # cls -> Hero
var spots := {}                     # cls -> SpotLight3D over them
var homes := {}                     # cls -> feet position on its plinth
var shafts := {}                    # cls -> the light shaft's material (power)
var glows := {}                     # cls -> the plinth runes' material (power)
var _flicker: Array[OmniLight3D] = []
var _pow := {}                      # cls -> the shaft/rune power now (eases toward its target)
var hovered := ""
var chosen := ""
var t := 0.0
var _sig_t := {}                    # cls -> seconds into the signature (-1 when not doing it)
var _sig_wait := 0.0
var _fid_t := {}                    # cls -> seconds of fidgeting
var _hit_done := {}
var _beam_t := 0.0

func setup(g: Node) -> void:
	game = g
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	add_child(vp)
	root3d = Node3D.new()
	vp.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.36, 0.38, 0.46)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.75
	e.glow_bloom = 0.08
	e.fog_enabled = true
	e.fog_light_color = Color(0.07, 0.075, 0.09)
	e.fog_density = 0.045
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 24, 0)
	key.light_energy = 0.45
	key.light_color = Color(0.75, 0.8, 1.0)
	key.shadow_enabled = true
	root3d.add_child(key)
	cam = Camera3D.new()
	cam.fov = 30.0
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.4, 11.4), Vector3(0, 1.85, 0))
	var radii := {}
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var x := (float(i) - (CLASSES.size() - 1) * 0.5) * SPACING
		var mid := c == "knight"
		homes[c] = Vector3(x, PLINTH_TOP + (0.14 if mid else 0.0), 0.4 if mid else 0.0)
		radii[c] = PLINTH_R * (1.2 if mid else 1.0)
	var built := ClassCathedral.build(root3d, homes, radii, ACCENTS, EMBLEMS)
	shafts = built["shafts"]
	glows = built["glows"]
	for n in root3d.get_children():
		if n is OmniLight3D and n.has_meta("flicker"):
			_flicker.append(n as OmniLight3D)
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var home: Vector3 = homes[c]
		var x := home.x
		var h := Hero.new()
		h.puppet = true
		h.name = "Stage_" + c
		root3d.add_child(h)
		h.setup(game)
		var gear := {"_cls": c, "_helm": true}
		gear["weapon"] = Items.make(str(Data.CLASSES[c].get("weapon", "hand_axe" if c == "demon" else "short_sword")))
		if c == "knight":
			gear["shield"] = Items.make("buckler")
		gear["armor"] = Items.make("quilted")
		h.apply_net_gear(gear)
		h.global_position = home
		h.net_pos = h.global_position
		h.net_yaw = FACE
		h.rig.rotation.y = FACE
		h.net_has = true
		h.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		h.light.light_energy = 0.35
		h.anim_time = i * 1.7
		heroes[c] = h
		_sig_t[c] = -1.0
		_fid_t[c] = 0.0
		# the shaft's light falling on each, in its colour, blazing for the chosen one; a rim light behind
		var sp := SpotLight3D.new()
		sp.light_color = (ACCENTS[c] as Color).lerp(Color(1.0, 0.95, 0.85), 0.35)
		sp.spot_angle = 20.0
		sp.spot_range = 10.0
		sp.light_energy = 1.0
		sp.shadow_enabled = false
		root3d.add_child(sp)
		sp.look_at_from_position(Vector3(x, 7.5, home.z + 1.6), home)
		spots[c] = sp
		var rim := OmniLight3D.new()
		rim.light_color = ACCENTS[c]
		rim.light_energy = 1.3
		rim.omni_range = 3.4
		rim.position = Vector3(x, home.y + 1.7, home.z - 1.3)
		root3d.add_child(rim)

func choose(c: String) -> void:
	if not heroes.has(c):
		return
	chosen = c
	_sig_wait = 0.25
	for k in _sig_t:
		_sig_t[k] = -1.0
	picked.emit(c)

## The class whose body is under this point of the stage (screen space of this control), or "".
func class_at(p: Vector2) -> String:
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	var best := ""
	var bd := 1e9
	for c in heroes:
		var h: Hero = heroes[c]
		var feet := cam.unproject_position(h.global_position) * sc
		var head := cam.unproject_position(h.global_position + Vector3(0, 1.9, 0)) * sc
		var half := absf(feet.y - head.y) * 0.32
		if p.y < head.y - 10.0 or p.y > feet.y + 14.0:
			continue
		var d := absf(p.x - feet.x)
		if d < half and d < bd:
			bd = d
			best = c
	return best

## Where a class's feet are on screen (this control's space): for its nameplate.
func feet_at(c: String) -> Vector2:
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	return cam.unproject_position((heroes[c] as Hero).global_position) * sc

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := class_at((ev as InputEventMouseMotion).position)
		if c != hovered:
			hovered = c
			_fid_t[c] = 0.0 if c != "" else 0.0
			hovering.emit(c)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if c != "" else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var c2 := class_at((ev as InputEventMouseButton).position)
		accept_event()
		if c2 != "":
			Sfx.play("click")
			choose(c2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
		hovered = ""
		hovering.emit("")

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	if chosen != "" and _sig_t.get(chosen, -1.0) < 0.0:
		_sig_wait -= delta
		if _sig_wait <= 0.0:
			_sig_t[chosen] = 0.0
			_hit_done[chosen] = false
			_sig_wait = SIG_EVERY
	for l in _flicker:
		l.light_energy = 1.2 + 0.18 * sin(t * 11.0 + l.position.x) * sin(t * 6.7)
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var h: Hero = heroes[c]
		var home: Vector3 = homes[c]
		var sp: SpotLight3D = spots[c]
		sp.light_energy = move_toward(sp.light_energy, 6.0 if c == chosen else (3.0 if c == hovered else 1.2), delta * 12.0)
		var pw := 1.0 if c == chosen else (0.55 if c == hovered else 0.18)
		var sm: ShaderMaterial = shafts[c]
		var nxt := move_toward(float(_pow.get(c, 0.2)), pw, delta * 3.0)
		_pow[c] = nxt
		sm.set_shader_parameter("power", nxt)
		var gm: ShaderMaterial = glows[c]
		gm.set_shader_parameter("power", nxt)
		(gm.get_meta("cap") as ShaderMaterial).set_shader_parameter("power", nxt)
		h.net_buff = c == chosen
		if float(_sig_t[c]) >= 0.0:
			_signature(c, h, home, delta)
		elif c == hovered:
			_fid_t[c] = float(_fid_t[c]) + delta
			_fidget(c, h, home, float(_fid_t[c]))
		else:
			_idle(c, h, home, i)

## Alive: breathing (Anim's idle), the weight shifting, the head turning to look about, now and then a
## glance at you; the chosen one stands a step forward in the light.
func _idle(c: String, h: Hero, home: Vector3, i: int) -> void:
	var ph := t * 0.45 + i * 1.9
	var look := sin(ph) * 0.22 + sin(ph * 2.3 + 1.0) * 0.08
	if fmod(t + i * 2.3, 9.0) < 1.6:
		look = 0.0       # a look straight at you
	h.net_yaw = FACE + look
	h.net_pos = home + Vector3(sin(ph * 0.7) * 0.04, 0, STEP if c == chosen else 0.0)
	h.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}

## Hovered: each class fidgets in its own (annoying) way.
func _fidget(c: String, h: Hero, home: Vector3, f: float) -> void:
	var st := {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
	var pos := home + Vector3(0, 0, STEP if c == chosen else 0.05)
	var yaw := FACE
	match c:
		"knight":
			# show-off sword combo, over and over, stamping between swings
			var cyc := fmod(f, 1.5)
			var k := int(cyc / 0.5)
			st["style"] = ["swipe1", "swipe2", "swipe3"][k]
			st["atk"] = fmod(cyc, 0.5) / 0.5
			pos.y = absf(sin(f * 6.3)) * 0.05
			yaw = FACE + sin(f * 3.0) * 0.25
		"wraith":
			# spins on the spot, rising and sinking
			yaw = FACE + f * 7.0
			pos.y = 0.25 + sin(f * 5.0) * 0.2
			st["move"] = 0.3
		"demon":
			# hops up and down raking the air
			pos.y = absf(sin(f * 7.0)) * 0.35
			st["style"] = "claw"
			st["atk"] = fmod(f, 0.6) / 0.6
		"warlock":
			# cackling, tiny frantic hops
			st["style"] = "cackle"
			st["atk"] = fmod(f, 1.2) / 1.2
			pos.y = absf(sin(f * 11.0)) * 0.14
			yaw = FACE + sin(f * 9.0) * 0.35
		"archer":
			# sways side to side drawing the bow at everything
			pos.x += sin(f * 4.0) * 0.22
			yaw = FACE + sin(f * 2.0) * 0.9
			st["style"] = "bow"
			st["atk"] = fmod(f, 0.8) / 0.8
	h.net_pos = pos
	h.net_yaw = yaw
	h.net_st = st

## The chosen class's signature move, with its effects at the impact.
func _signature(c: String, h: Hero, home: Vector3, delta: float) -> void:
	var sig: Array = SIGNATURE[c]
	var dur: float = sig[1]
	var s: float = float(_sig_t[c]) + delta
	_sig_t[c] = s
	var a := clampf(s / dur, 0.0, 1.0)
	var pos := home + Vector3(0, 0, STEP)
	var front := h.global_position + Vector3(0, 0, 1.0)
	var col: Color = ACCENTS[c]
	var st := {"move": 0.0, "atk": a, "style": str(sig[0]), "block": 0.0, "hit": 0.0}
	match c:
		"knight":
			# leaps and brings the sword down
			pos.y = sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6
			pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.2
		"wraith":
			pos.y = 0.2 + sin(a * PI) * 0.35
		"warlock":
			# Drain Life: both hands out, holding the beam
			st["atk"] = minf(a / 0.2, 1.0) * 0.6
			if a > 0.2 and a < 0.95:
				_beam_t -= delta
				if _beam_t <= 0.0:
					_beam_t = 0.05
					var from := h.global_position + Vector3(0, 0.75, 0.35)
					Fx.burst(root3d, from + Vector3(randf_range(-0.05, 0.05), 0, 0), col, 4, 3.5, 0.07, 0.5, true, 0.0, 6.0, Vector3(0, 0.08, 1))
	h.net_pos = pos
	h.net_yaw = FACE
	h.net_st = st
	if not bool(_hit_done.get(c, false)) and a >= float(sig[2]):
		_hit_done[c] = true
		match c:
			"knight":
				var at := h.global_position + Vector3(0, 0, 0.9)
				at.y = 0.02
				Fx.ring(root3d, at, 2.6, Color(1.0, 0.92, 0.6), 0.55)
				Fx.burst(root3d, at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), 40, 5.0, 0.1, 0.6, true, -5.0)
				Sfx.play("cleave_hit", -10.0)
			"wraith":
				Fx.ring(root3d, Vector3(home.x, home.y + 0.02, home.z), 3.4, col, 0.7, 1.0)
				Fx.burst(root3d, h.global_position + Vector3(0, 1.4, 0), col, 46, 5.5, 0.09, 0.7, true, 0.0)
				Sfx.play("wail", -12.0)
			"demon":
				for k in 3:
					Fx.burst(root3d, front + Vector3((k - 1) * 0.35, 0.9 - k * 0.15, 0), col, 18, 3.5, 0.09, 0.45, true, 2.0, 30.0, Vector3(1.0 - k, 0.2, 0.5))
				Fx.flash(root3d, front + Vector3(0, 1, 0), col, 3.0, 0.4, 4.0)
				Sfx.play("hellclaw", -10.0)
			"warlock":
				Fx.flash(root3d, h.global_position + Vector3(0, 0.8, 0.6), col, 2.5, 1.4, 3.5)
				Sfx.play("drain", -14.0)
			"archer":
				# the volley: a fan of arrows streaking up out of the bow
				for k in 5:
					Fx.burst(root3d, h.global_position + Vector3(0, 1.3, 0.3), col, 6, 9.0, 0.06, 0.45, true, -2.0, 4.0, Vector3((k - 2) * 0.15, 1.0, 0.4))
				Fx.flash(root3d, h.global_position + Vector3(0, 1.4, 0.4), col, 2.0, 0.3, 3.0)
				Sfx.play("bow", -10.0)
	if s >= dur:
		_sig_t[c] = -1.0
		_sig_wait = SIG_EVERY
