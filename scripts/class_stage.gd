class_name ClassStage
extends SubViewportContainer
## The New Character screen's heroes (UI._build_class_picker): every class stands in a row on a torch-lit
## stone floor in its own little world, as the co-op puppets are (Hero with `puppet`, driven by `net_st`), in
## its starting gear. Idle they breathe, shift their weight and look about; under the mouse each fidgets in its
## own annoying way (`_fidget`); the chosen one steps into the light and does its signature move every few
## seconds (`_signature`, with its effects). `hovered` / `chosen` are class ids ("" for none).

signal picked(cls: String)
signal hovering(cls: String)

const CLASSES := ["knight", "wraith", "demon", "warlock", "archer"]
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.55, 0.85, 0.45)}
const SPACING := 1.75
const FACE := PI                     # bodies face -z; the camera is on +z
## signature moves: [pose style, seconds, impact fraction, skill name]
const SIGNATURE := {"knight": ["cleave", 1.1, 0.5, "Holy Slam"], "wraith": ["cast", 1.2, 0.45, "Banshee Wail"],
	"demon": ["side", 0.9, 0.45, "Hellfire Claw"], "warlock": ["cast", 1.8, 0.2, "Drain Life"], "archer": ["bow", 1.0, 0.55, "Volley"]}
const SIG_EVERY := 4.5
## The sound of choosing each hero: layers of the game's own recordings, [sound, delay s, dB, pitch]
const PICK_SOUND := {
	"knight": [["swing_heavy", 0.0, -2.0, 0.9], ["block", 0.16, 0.0, 0.85], ["battle_cry", 0.3, -3.0, 1.0]],
	"wraith": [["phase_in", 0.0, -2.0, 1.0], ["wail", 0.12, -4.0, 1.1], ["shade_implode", 0.75, -3.0, 0.9]],
	"demon": [["fire_erupt", 0.0, 0.0, 0.85], ["summon_demon", 0.2, -3.0, 0.9]],
	"warlock": [["blight_cast", 0.0, -2.0, 1.0], ["relic_ting", 0.08, -6.0, 1.3], ["cackle", 0.3, -4.0, 1.55]],
	"archer": [["bow", 0.0, 0.0, 0.85], ["bow", 0.14, -3.0, 1.05], ["lion_roar", 0.32, -8.0, 1.45]]}

var game: Node
var vp: SubViewport
var cam: Camera3D
var root3d: Node3D
var heroes := {}                    # cls -> Hero
var spots := {}                     # cls -> SpotLight3D over them
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
	e.ambient_light_color = Color(0.42, 0.4, 0.46)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 18, 0)
	key.light_energy = 0.9
	key.light_color = Color(1.0, 0.86, 0.68)
	key.shadow_enabled = true
	root3d.add_child(key)
	cam = Camera3D.new()
	cam.fov = 30.0
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.0, 9.6), Vector3(0, 0.95, 0))
	_floor()
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var x := (float(i) - (CLASSES.size() - 1) * 0.5) * SPACING
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
		h.global_position = Vector3(x, 0, 0)
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
		# a pool of light over each, brighter for the chosen one; a rim light in the class's colour behind
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.9, 0.75)
		sp.spot_angle = 22.0
		sp.spot_range = 9.0
		sp.light_energy = 0.0
		sp.shadow_enabled = false
		root3d.add_child(sp)
		sp.look_at_from_position(Vector3(x, 6.5, 2.2), Vector3(x, 0, 0))
		spots[c] = sp
		var rim := OmniLight3D.new()
		rim.light_color = ACCENTS[c]
		rim.light_energy = 1.1
		rim.omni_range = 3.2
		rim.position = Vector3(x, 1.6, -1.4)
		root3d.add_child(rim)

## A round stone floor fading into the dark, and two braziers.
func _floor() -> void:
	var fl := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.5
	cyl.bottom_radius = 7.5
	cyl.height = 0.2
	cyl.radial_segments = 64
	fl.mesh = cyl
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	sm.shader = sh
	fl.material_override = sm
	fl.position = Vector3(0, -0.1, 0)
	root3d.add_child(fl)
	for sx: int in [-1, 1]:
		var p := Vector3(sx * 5.6, 0, -1.2)
		var bowl := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.38
		bc.bottom_radius = 0.16
		bc.height = 1.1
		bowl.mesh = bc
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.13, 0.11, 0.1)
		bm.metallic = 0.6
		bm.roughness = 0.5
		bowl.material_override = bm
		bowl.position = p + Vector3(0, 0.55, 0)
		root3d.add_child(bowl)
		Props.fire(root3d, p + Vector3(0, 1.1, 0), 0.8, Color(1.0, 0.55, 0.2), false, false, true)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 1.6
		l.omni_range = 6.5
		l.position = p + Vector3(0, 1.6, 0.3)
		l.name = "brazier_light"
		root3d.add_child(l)

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
	if chosen != "" and _sig_t.get(chosen, -1.0) < 0.0:
		_sig_wait -= delta
		if _sig_wait <= 0.0:
			_sig_t[chosen] = 0.0
			_hit_done[chosen] = false
			_sig_wait = SIG_EVERY
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var h: Hero = heroes[c]
		var home := Vector3((float(i) - (CLASSES.size() - 1) * 0.5) * SPACING, 0, 0)
		var sp: SpotLight3D = spots[c]
		sp.light_energy = move_toward(sp.light_energy, 5.0 if c == chosen else (2.0 if c == hovered else 0.0), delta * 12.0)
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
	h.net_pos = home + Vector3(sin(ph * 0.7) * 0.04, 0, 0.45 if c == chosen else 0.0)
	h.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}

## Hovered: each class fidgets in its own (annoying) way.
func _fidget(c: String, h: Hero, home: Vector3, f: float) -> void:
	var st := {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
	var pos := home + Vector3(0, 0, 0.45 if c == chosen else 0.15)
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
			pos.x += sin(f * 4.0) * 0.3
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
	var pos := home + Vector3(0, 0, 0.45)
	var front := h.global_position + Vector3(0, 0, 1.0)
	var col: Color = ACCENTS[c]
	var st := {"move": 0.0, "atk": a, "style": str(sig[0]), "block": 0.0, "hit": 0.0}
	match c:
		"knight":
			# leaps and brings the sword down
			pos.y = sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6
			pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.35
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
				at.y = 0.0
				Fx.ring(root3d, at, 2.6, Color(1.0, 0.92, 0.6), 0.55)
				Fx.burst(root3d, at + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), 40, 5.0, 0.1, 0.6, true, -5.0)
				Sfx.play("cleave_hit", -10.0)
			"wraith":
				Fx.ring(root3d, Vector3(h.global_position.x, 0.0, h.global_position.z), 3.4, col, 0.7, 1.0)
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

const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = wp.xz * 1.6;
	vec2 c = floor(p);
	vec2 f = fract(p);
	// flagstones: a dark seam round each slab, each slab its own shade
	float seam = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.05, f.y) * smoothstep(1.0, 0.95, f.x) * smoothstep(1.0, 0.95, f.y);
	float shade = 0.75 + h(c) * 0.35;
	float r = length(wp.xz);
	float fade = 1.0 - smoothstep(3.0, 7.2, r);
	ALBEDO = vec3(0.11, 0.1, 0.09) * shade * mix(0.3, 1.0, seam) * fade;
	ROUGHNESS = 0.85;
}
"""
