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

## left to right on the stage; the knight, the first choice, stands in the middle on the biggest plinth
const CLASSES := ["archer", "wraith", "knight", "plague", "demon", "warlock"]
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.92, 0.24, 0.3), "plague": Color(0.6, 0.95, 0.3)}
## the banner's emblem (ClassCathedral.BANNER_SHADER): cross, hood, horns, hat, arrow, beak
const EMBLEMS := {"knight": 1, "wraith": 2, "demon": 3, "warlock": 4, "archer": 5, "plague": 6}
const SPACING := 1.95
const PLINTH_TOP := 0.78            # feet height on a plinth (the knight's is taller, nearer and wider)
const PLINTH_R := 0.56
const STEP := 0.1                   # how far the chosen one steps forward on its plinth
const FACE := PI                     # bodies face -z; the camera is on +z
## signature moves: [pose style, seconds, impact fraction, skill name]
const SIGNATURE := {"knight": ["cleave", 1.1, 0.5, "Holy Slam"], "wraith": ["rend", 0.95, 0.42, "Spectral Rend"],
	"demon": ["side", 0.9, 0.45, "Hellfire Claw"], "warlock": ["cast", 1.8, 0.2, "Drain Life"], "archer": ["bow", 1.0, 0.55, "Volley"],
	"plague": ["pd_flask", 1.3, 0.55, "Toxic Flask"]}
const SIG_EVERY := 4.5
## Skill previews (hover a skill in the panel, `show_skill`): each skill's pose style and seconds (before the
## class's attack pace), as Hero.use_skill plays them; the effects are the game's own, scaled to the stage.
const SKILL_SHOW := {"cleave": ["cleave", 0.95], "nova": ["cast", 0.55], "charge": ["swipe3", 0.7], "cry": ["cast", 0.6],
	"rend": ["rend", 0.8], "siphon": ["siphon", 0.7], "step": ["wstep", 0.75], "grasp": ["grasp", 0.95],
	"phantom": ["phantom", 1.0], "night": ["night_scream", 0.9],
	"hellclaw": ["side", 0.7], "summon": ["cast", 0.55], "phase": ["cast", 0.6], "pact": ["cast", 0.6],
	"drain": ["cast", 1.6], "blight": ["cast", 0.45], "shackles": ["cast", 0.5], "covenant": ["cast", 0.6],
	"pierce": ["bow", 0.9], "volley": ["bow", 0.9], "snare": ["cast", 0.6], "beast": ["cast", 0.6],
	"toxic": ["pd_flask", 0.85], "volatile": ["pd_volatile", 1.25], "trap": ["pd_trap", 1.0], "epidemic": ["pd_slam", 1.2]}
const SKILL_GAP := 1.1              # rest between repeats of a previewed skill
## The sound of choosing each hero: layers of the game's own recordings, [sound, delay s, dB, pitch]
const PICK_SOUND := {
	"knight": [["swing_heavy", 0.0, -2.0, 0.9], ["block", 0.16, 0.0, 0.85], ["battle_cry", 0.3, -3.0, 1.0]],
	"wraith": [["phase_in", 0.0, -2.0, 1.0], ["wail", 0.12, -4.0, 1.1], ["shade_implode", 0.75, -3.0, 0.9]],
	"demon": [["fire_erupt", 0.0, 0.0, 0.85], ["summon_demon", 0.2, -3.0, 0.9]],
	"warlock": [["blight_cast", 0.0, -2.0, 1.0], ["relic_ting", 0.08, -6.0, 1.3], ["cackle", 0.3, -4.0, 1.55]],
	"archer": [["bow", 0.0, 0.0, 0.85], ["bow", 0.14, -3.0, 1.05], ["lion_roar", 0.32, -8.0, 1.45]],
	"plague": [["ice_shatter", 0.0, -4.0, 1.4], ["blight_burst", 0.1, -5.0, 1.15], ["fuse", 0.35, -9.0, 1.0]]}

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
var _skill_c := ""                 # the class showing a skill (its panel's skill is hovered), or ""
var _skill_id := ""
var _skill_t := 0.0
var _skill_hit := false
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

## Each hero's own sound when chosen (PICK_SOUND), heard flat like the UI.
func pick_sound(c: String) -> void:
	for layer in PICK_SOUND.get(c, [["click", 0.0, 0.0, 1.0]]):
		var nm: String = layer[0]
		var vol: float = layer[2]
		var pitch: float = layer[3]
		if float(layer[1]) <= 0.0:
			Sfx.play(nm, vol, pitch)
		else:
			get_tree().create_timer(float(layer[1])).timeout.connect(func(): Sfx.play(nm, vol, pitch))

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
			pick_sound(c2)
			choose(c2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
		hovered = ""
		hovering.emit("")

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	if chosen != "" and _sig_t.get(chosen, -1.0) < 0.0 and _skill_c != chosen:
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
		var pw := 1.0 if c == chosen or c == _skill_c else (0.6 if c == hovered else 0.32)
		var sm: ShaderMaterial = shafts[c]
		var nxt := move_toward(float(_pow.get(c, 0.2)), pw, delta * 3.0)
		_pow[c] = nxt
		sm.set_shader_parameter("power", nxt)
		var gm: ShaderMaterial = glows[c]
		gm.set_shader_parameter("power", nxt)
		(gm.get_meta("cap") as ShaderMaterial).set_shader_parameter("power", nxt)
		h.net_buff = c == chosen
		if c == _skill_c:
			_skill_show(c, h, home, delta)
		elif float(_sig_t[c]) >= 0.0:
			_signature(c, h, home, delta)
		elif c == hovered:
			_fid_t[c] = float(_fid_t[c]) + delta
			_fidget(c, h, home, float(_fid_t[c]))
		else:
			_idle(c, h, home, i)

## Hovering a skill in the panel: that class performs it on its plinth, over and over ("" stops).
func show_skill(c: String, id: String) -> void:
	if id == "" and c != _skill_c:
		return
	if id == "" or not heroes.has(c) or not SKILL_SHOW.has(id):
		_skill_c = ""
		_skill_id = ""
		return
	if _skill_c != "" and _skill_c != c:
		_sig_t[_skill_c] = -1.0
	_skill_c = c
	_skill_id = id
	_skill_t = 0.0
	_skill_hit = false
	_sig_t[c] = -1.0

func stop_skill() -> void:
	if _skill_c != "":
		show_skill(_skill_c, "")

func _skill_show(c: String, h: Hero, home: Vector3, delta: float) -> void:
	var spec: Array = SKILL_SHOW[_skill_id]
	var style: String = spec[0]
	var dur: float = float(spec[1]) * Data.attack_pace(c)
	_skill_t += delta
	if _skill_t >= dur + SKILL_GAP:
		_skill_t -= dur + SKILL_GAP
		_skill_hit = false
	var resting := _skill_t > dur
	var a := clampf(_skill_t / dur, 0.0, 1.0)
	var st := {"move": 0.0, "atk": -1.0 if resting else a, "style": style, "block": 0.0, "hit": 0.0}
	var pos := home + Vector3(0, 0, STEP)
	var impact := Anim.impact_at(style)
	match _skill_id:
		"cleave":
			if not resting:
				pos.y += sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6
				pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.2
		"charge":
			# a short rush to the plinth's edge and back
			if not resting:
				pos.z += sin(a * PI) * 0.32
				st["move"] = 1.0 - a
			impact = 0.5
		"drain":
			st["atk"] = -1.0 if resting else minf(a / 0.15, 1.0) * 0.6
			impact = 0.15
			if not resting and a > 0.15 and a < 0.95:
				_beam_t -= delta
				if _beam_t <= 0.0:
					_beam_t = 0.05
					var from := h.global_position + Vector3(0, 0.75, 0.35)
					Fx.burst(root3d, from + Vector3(randf_range(-0.05, 0.05), 0, 0), ACCENTS[c], 4, 3.5, 0.07, 0.5, true, 0.0, 6.0, Vector3(0, 0.08, 1))
		"rend", "phantom":
			# the wraith's lunge, kept on his plinth
			if not resting:
				pos.z += smoothstep(0.05, 0.4, a) * 0.25
	h.net_pos = pos
	h.net_yaw = FACE
	h.net_st = st
	if not _skill_hit and not resting and a >= impact:
		_skill_hit = true
		_skill_fx(c, h, home)

## The skill's effects at its impact frame: the game's own, at stage scale.
func _skill_fx(c: String, h: Hero, home: Vector3) -> void:
	var col: Color = ACCENTS[c]
	var p := Vector3(home.x, home.y + 0.02, home.z + STEP)
	var yaw := h.rig.global_rotation.y
	var floor_front := Vector3(home.x, 0.03, home.z + 1.5)
	var chest := h.global_position + Vector3(0, 1.1, 0.2)
	match _skill_id:
		"cleave":
			Fx.holy_slam(root3d, p + Vector3(0, 0, 0.25), 1.3)
			Sfx.play("cleave_hit", -10.0)
		"nova":
			Fx.ring(root3d, p, 2.4, Color(1.0, 0.75, 0.3), 0.5)
			Fx.burst(root3d, p + Vector3(0, 0.9, 0), Color(1.0, 0.8, 0.4), 40, 5.0, 0.12, 0.6, true, 0.0, 180.0)
			Sfx.play("holy_nova", -10.0)
		"charge":
			Fx.burst(root3d, p + Vector3(0, 0.6, 0.6), Color(1.0, 0.9, 0.7), 24, 3.0, 0.08, 0.4, true, -2.0, 50.0, Vector3(0, 0.3, 1))
			Fx.flash(root3d, p + Vector3(0, 1.0, 0.6), col, 2.0, 0.25, 3.0)
			Sfx.play("charge_impact", -10.0)
		"cry":
			Fx.ring(root3d, p, 2.0, Color(1.0, 0.85, 0.4), 0.6)
			Fx.pillar(root3d, p, Color(1.0, 0.8, 0.35), 0.8)
			Sfx.play("battle_cry", -10.0)
		"rend":
			WraithFx.rake(root3d, h.global_position, yaw, 1.6, false)
			Sfx.play("reap_swing", -10.0)
		"siphon":
			WraithFx.latch(root3d, floor_front + Vector3(0, 0.9, 0))
			WraithFx.pulse(root3d, chest, col, 0.6, 0.6)
			Fx.burst(root3d, floor_front + Vector3(0, 0.9, 0), col, 24, 4.0, 0.07, 0.5, true, 0.0, 10.0, Vector3(0, 0.1, -1))
			Sfx.play("shade_in", -10.0)
		"step":
			WraithFx.mist_out(root3d, p)
			WraithFx.mist_in(root3d, p + Vector3(0, 0, 0.1))
			Sfx.play("shade_out", -10.0)
		"grasp":
			WraithFx.grasp(root3d, floor_front, 1.0, 1.6)
			Sfx.play("slam", -10.0, 0.9)
		"phantom":
			WraithFx.split(root3d, p)
			WraithFx.phantom_hit(root3d, floor_front + Vector3(0, 0.9, 0), Vector3(0, 0, 1))
			Sfx.play("reap_swing", -10.0, 0.9)
		"night":
			WraithFx.scream(root3d, p, 2.2)
			WraithFx.collapse(root3d, p, 1.4)
			Sfx.play("host_summon", -10.0, 0.8)
		"hellclaw":
			DemonFx.claw(root3d, p, yaw, 1.5)
			Sfx.play("hellclaw", -10.0)
		"summon":
			DemonFx.summon_circle(root3d, floor_front)
			Sfx.play("summon_demon", -10.0)
		"phase":
			DemonFx.phase_tear(root3d, p)
			DemonFx.eruption(root3d, p, 1.6)
			Sfx.play("phase_in", -10.0)
		"pact":
			DemonFx.pact(root3d, p)
			Sfx.play("blood_pact", -10.0)
		"drain":
			Fx.flash(root3d, chest + Vector3(0, -0.3, 0.4), col, 2.5, 1.2, 3.5)
			Sfx.play("drain_start", -12.0)
		"blight":
			Fx.burst(root3d, chest, col, 26, 6.0, 0.1, 0.35, true, -2.0, 10.0, Vector3(0, 0.15, 1))
			WarlockFx.blight_burst(root3d, floor_front, 0.9)
			Sfx.play("blight_cast", -10.0)
		"shackles":
			WarlockFx.shackle_cast(root3d, p, 1.7)
			for k in 3:
				var to := Vector3(home.x + (k - 1) * 1.1, 0.4, home.z + 1.6)
				WarlockFx.chain(root3d, chest, to, 0.8)
			Sfx.play("shackles", -10.0)
		"covenant":
			WarlockFx.covenant(root3d, p)
			Sfx.play("covenant", -10.0)
		"pierce":
			# a burning arrow streaking out of the bow
			Fx.burst(root3d, chest + Vector3(0, 0.2, 0.2), Color(1.0, 0.5, 0.15), 30, 9.0, 0.08, 0.4, true, 0.0, 3.0, Vector3(0, 0, 1))
			Fx.flash(root3d, chest + Vector3(0, 0.2, 0.4), Color(1.0, 0.5, 0.15), 2.0, 0.3, 3.0)
			Sfx.play("bow", -10.0)
		"volley":
			for k in 5:
				Fx.burst(root3d, chest + Vector3(0, 0.2, 0.2), Color(0.7, 0.9, 1.0), 6, 9.0, 0.06, 0.45, true, -2.0, 4.0, Vector3((k - 2) * 0.15, 1.0, 0.4))
			Fx.ring(root3d, floor_front, 1.2, Color(0.7, 0.9, 1.0), 0.8)
			Fx.burst(root3d, floor_front + Vector3(0, 2.5, 0), Color(0.75, 0.92, 1.0), 40, 4.0, 0.06, 0.6, true, -12.0, 15.0, Vector3.DOWN)
			Sfx.play("bow", -10.0)
		"snare":
			Fx.ring(root3d, floor_front, 0.8, Color(0.75, 0.6, 1.0), 0.7)
			for k in 3:
				var to := floor_front + Vector3((k - 1) * 0.9, 0.0, 0.3)
				Fx.bolt(root3d, floor_front + Vector3(0, 0.1, 0), to + Vector3(0, 0.1, 0), Color(0.8, 0.7, 1.0), 0.3)
			Sfx.play("thunder_strike", -14.0)
		"beast":
			# the spirit beast answers: a grey spirit burst where it would pounce
			Fx.burst(root3d, floor_front + Vector3(0, 0.5, 0), Color(0.75, 0.8, 0.85), 30, 3.0, 0.1, 0.7, true, 0.0)
			Fx.ring(root3d, floor_front, 1.0, Color(0.75, 0.8, 0.85), 0.6)
			Sfx.play("growl", -8.0)
		"toxic":
			# the flask shatters on the floor in front: glass and a green cloud
			Fx.burst(root3d, floor_front, Color(0.8, 1.0, 0.85), 14, 3.0, 0.05, 0.4, true, -9.0)
			Fx.burst(root3d, floor_front + Vector3(0, 0.3, 0), col, 34, 1.8, 0.16, 1.2, true, 0.4)
			Fx.flash(root3d, floor_front + Vector3(0, 0.6, 0), col, 2.5, 0.6, 3.0)
			Sfx.play("ice_shatter", -10.0, 1.35)
		"volatile":
			# it lands, fizzes and blows: fire and poison
			Fx.flash(root3d, floor_front + Vector3(0, 0.7, 0), Color(1.0, 0.6, 0.2), 4.0, 0.4, 4.0)
			Fx.burst(root3d, floor_front + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.15), 40, 5.0, 0.1, 0.5, true, -4.0)
			Fx.burst(root3d, floor_front + Vector3(0, 0.4, 0), col, 30, 2.0, 0.18, 1.0, true, 0.5)
			Fx.ring(root3d, floor_front, 1.3, Color(1.0, 0.6, 0.25), 0.4)
			Sfx.play("boom", -12.0)
		"trap":
			Fx.ring(root3d, floor_front, 0.6, col, 0.8)
			Fx.burst(root3d, floor_front + Vector3(0, 0.1, 0), col, 20, 2.0, 0.07, 0.6, true, -3.0, 25.0)
			Sfx.play("equip", -10.0, 0.8)
		"epidemic":
			# the cane slams down: a plague wave rolls out and a sickly pillar rises
			Fx.ring(root3d, p, 2.4, col, 0.7)
			Fx.pillar(root3d, p, col, 0.9)
			Fx.burst(root3d, p + Vector3(0, 0.4, 0), col, 46, 4.0, 0.14, 0.9, true, 0.3)
			Sfx.play("blight_burst", -10.0)

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
			pos.y += absf(sin(f * 6.3)) * 0.05
			yaw = FACE + sin(f * 3.0) * 0.25
		"wraith":
			# rakes the air with his claws over and over, drifting side to side
			var cyc := fmod(f, 1.1)
			st["style"] = "rend"
			st["atk"] = cyc / 1.1
			pos.x += sin(f * 2.4) * 0.25
			yaw = FACE + sin(f * 2.4) * 0.3
		"demon":
			# hops up and down raking the air
			pos.y += absf(sin(f * 7.0)) * 0.35
			st["style"] = "claw"
			st["atk"] = fmod(f, 0.6) / 0.6
		"warlock":
			# cackling, tiny frantic hops
			st["style"] = "cackle"
			st["atk"] = fmod(f, 1.2) / 1.2
			pos.y += absf(sin(f * 11.0)) * 0.14
			yaw = FACE + sin(f * 9.0) * 0.35
		"archer":
			# sways side to side drawing the bow at everything
			pos.x += sin(f * 4.0) * 0.22
			yaw = FACE + sin(f * 2.0) * 0.9
			st["style"] = "bow"
			st["atk"] = fmod(f, 0.8) / 0.8
		"plague":
			# holds a vial up to the light and peers at it, tilting his head, again and again
			st["style"] = "pd_inspect"
			st["atk"] = fmod(f, 3.2) / 3.2
			yaw = FACE + sin(f * 1.3) * 0.2
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
			pos.y += sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6
			pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.2
		"wraith":
			# the lunge of Spectral Rend, kept on the plinth
			pos.z += smoothstep(0.05, 0.4, a) * 0.3
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
				var at := home + Vector3(0, 0.02, 0.2)
				Fx.ring(root3d, at, 1.6, Color(1.0, 0.92, 0.6), 0.55)
				Fx.burst(root3d, at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), 40, 5.0, 0.1, 0.6, true, -5.0)
				Sfx.play("cleave_hit", -10.0)
			"wraith":
				WraithFx.rake(root3d, h.global_position, h.net_yaw, 2.4, false)
				Sfx.play("reap_swing", -12.0)
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
			"plague":
				# the flask shatters at the edge of the light: glass and a green cloud
				var at2 := Vector3(h.global_position.x, 0.05, h.global_position.z + 1.6)   # on the floor in front of the plinth
				Fx.burst(root3d, at2, Color(0.8, 1.0, 0.85), 14, 3.0, 0.05, 0.4, true, -9.0)
				Fx.burst(root3d, at2 + Vector3(0, 0.3, 0), col, 34, 1.8, 0.16, 1.2, true, 0.4)
				Fx.flash(root3d, at2 + Vector3(0, 0.6, 0), col, 2.5, 0.6, 3.0)
				Sfx.play("ice_shatter", -10.0, 1.35)
	if s >= dur:
		_sig_t[c] = -1.0
		_sig_wait = SIG_EVERY
