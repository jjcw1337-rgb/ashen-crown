class_name ClassStage
extends SubViewportContainer
## The New Character screen's heroes (UI._build_class_picker): a focused carousel in a ruined cathedral
## (ClassCathedral). The chosen hero stands large in the middle, front and close, on the biggest plinth with
## its shaft blazing; the ones either side stand back, smaller and dimmer; the outer ones further back again,
## fading into the gloom, and beyond them the rest wait unseen. Every class in CLASSES gets its own stand
## (plinth, shaft of light, banner, candles, lights: ClassCathedral.build_stand under one Node3D), and the
## carousel moves the stand with its hero, so any number of classes works and the ring wraps round.
## The arrows (ui.gd's `Arrow`s), the mouse wheel, Left/Right (A/D) and a click on a side hero turn it one
## slot (`turn`, `go_to`): the ring slides with an eased glide (`TURN_T`), and the hero that arrives in the
## middle is the chosen one (`picked`, its PICK_SOUND, its signature move once it has arrived).
## The heroes are co-op puppets (Hero with `puppet`, driven by `net_st`) in their starting gear. Idle they
## breathe, shift their weight and look about; under the mouse each fidgets in its own annoying way
## (`_fidget`); the chosen one does its signature move every few seconds (`_signature`, with its effects).
## `hovered` / `chosen` are class ids ("" for none).

signal picked(cls: String)
signal hovering(cls: String)

## the ring, in order; the knight, the first choice, starts in the middle. The three dragons are spread round it
## (never two side by side, the wrap from the last to the first included).
const CLASSES := ["archer", "wyrm", "wraith", "knight", "doug", "serpent", "plague", "demon", "wyvern", "warlock"]
const ACCENTS := {"knight": Color(0.95, 0.72, 0.35), "wraith": Color(0.4, 0.85, 1.0), "demon": Color(1.0, 0.38, 0.1), "warlock": Color(0.45, 1.0, 0.35), "archer": Color(0.92, 0.24, 0.3), "plague": Color(0.6, 0.95, 0.3),
	"doug": Color(1.0, 0.82, 0.2), "wyrm": Color(1.0, 0.3, 0.12), "serpent": Color(0.55, 0.88, 1.0), "wyvern": Color(0.45, 0.95, 0.85)}
## the banner's emblem (ClassCathedral.BANNER_SHADER): cross, hood, horns, hat, arrow, beak, claw marks (the dragons)
const EMBLEMS := {"knight": 1, "wraith": 2, "demon": 3, "warlock": 4, "archer": 5, "plague": 6, "doug": 1, "wyrm": 7, "serpent": 7, "wyvern": 7}
const PLINTH_TOP := 0.78            # feet height on a plinth (the stand is scaled with its slot)
const PLINTH_R := 0.56
const STEP := 0.1
const FOV := 31.0                   # the stage band's vertical field of view (see `_frame`)                   # how far the chosen one steps forward on its plinth
const FACE := PI                     # bodies face -z; the camera is on +z
## The carousel's slots, by distance from the middle (0 = chosen, 1 = beside it, 2 = outer; further is unseen):
## x spacing, z (toward the camera), the stand's scale, and its light (1 = the chosen one's blaze).
const SLOT_X := [0.0, 2.7, 4.9, 6.6]
const SLOT_Z := [1.9, -0.3, -1.9, -3.2]
const SLOT_SCALE := [1.25, 0.86, 0.7, 0.58]
const SLOT_LIGHT := [1.0, 0.42, 0.16, 0.0]
const VISIBLE := 2.95               # slots further than this from the middle are hidden (fewer classes: nearer)
const TURN_T := 0.52                # seconds of a glide by one slot
const WHEEL_GAP := 0.08             # seconds between wheel notches that count
## signature moves: [pose style, seconds, impact fraction, skill name]
const SIGNATURE := {"knight": ["cleave", 1.1, 0.5, "Holy Slam"], "wraith": ["rend", 0.95, 0.42, "Spectral Rend"],
	"demon": ["fists", 0.9, 0.48, "Molten Fists"], "warlock": ["cast", 1.8, 0.2, "Drain Life"], "archer": ["bow", 1.0, 0.55, "Volley"],
	"plague": ["pd_flask", 1.3, 0.55, "Pestilence Vial"], "doug": ["pie", 0.9, 0.5, "Cream Pie"],
	"wyrm": ["swipe3", 1.2, 0.47, "Tail Spin"], "serpent": ["swipe3", 1.1, 0.47, "Tail Spin"], "wyvern": ["swipe3", 1.1, 0.47, "Tail Spin"]}
const SIG_EVERY := 4.5
## Skill previews (hover a skill in the panel, `show_skill`): each skill's pose style and seconds (before the
## class's attack pace), as Hero.use_skill plays them; the effects are the game's own, scaled to the stage.
const SKILL_SHOW := {"cleave": ["cleave", 0.95], "nova": ["cast", 0.55], "charge": ["swipe3", 0.7], "cry": ["cast", 0.6],
	"rend": ["rend", 0.8], "siphon": ["siphon", 0.7], "step": ["wstep", 0.75], "grasp": ["grasp", 0.95],
	"phantom": ["phantom", 1.0], "night": ["night_scream", 0.9],
	"fists": ["fists", 0.8], "icharge": ["icharge", 0.75], "cslam": ["cslam", 1.2], "hurl": ["hurl", 1.1], "grip": ["grip_throw", 0.9],
	"wrath": ["wrath_roar", 1.3],
	"drain": ["cast", 1.6], "blight": ["cast", 0.45], "shackles": ["cast", 0.5], "covenant": ["cast", 0.6],
	"pierce": ["bow", 0.9], "volley": ["bow", 0.9], "snare": ["cast", 0.6], "beast": ["cast", 0.6],
	"toxic": ["pd_flask", 0.85], "swarm": ["pd_swarm", 0.8], "bloom": ["pd_bloom", 0.95], "fog": ["pd_fog", 0.6],
	"transfusion": ["pd_transfuse", 0.8], "experiment": ["pd_slam", 1.2],
	"pie": ["pie", 0.9], "peels": ["peels", 0.8], "slide": ["slide", 0.7], "doppel": ["doppel", 0.6], "juggle": ["juggle", 1.4],
	"bounce": ["bounce", 1.3], "car": ["car", 1.0]}
const SKILL_GAP := 1.1              # rest between repeats of a previewed skill
## The sound of choosing each hero: layers of the game's own recordings, [sound, delay s, dB, pitch]
const PICK_SOUND := {
	"knight": [["swing_heavy", 0.0, -2.0, 0.9], ["block", 0.16, 0.0, 0.85], ["battle_cry", 0.3, -3.0, 1.0]],
	"wraith": [["phase_in", 0.0, -2.0, 1.0], ["wail", 0.12, -4.0, 1.1], ["shade_implode", 0.75, -3.0, 0.9]],
	"demon": [["fire_erupt", 0.0, 0.0, 0.85], ["summon_demon", 0.2, -3.0, 0.9]],
	"warlock": [["blight_cast", 0.0, -2.0, 1.0], ["relic_ting", 0.08, -6.0, 1.3], ["cackle", 0.3, -4.0, 1.55]],
	"archer": [["bow", 0.0, 0.0, 0.85], ["bow", 0.14, -3.0, 1.05], ["lion_roar", 0.32, -8.0, 1.45]],
	"plague": [["ice_shatter", 0.0, -4.0, 1.4], ["blight_burst", 0.1, -5.0, 1.15], ["fuse", 0.35, -9.0, 1.0]],
	"doug": [["arena_horn", 0.0, -6.0, 2.4], ["inv_click", 0.25, -2.0, 0.5], ["arena_horn", 0.4, -8.0, 2.8]],
	"wyrm": [["wyrm_step", 0.0, -2.0, 0.9], ["wyrm_roar", 0.12, -3.0, 1.0]],
	"serpent": [["serpent_tail", 0.0, -6.0, 1.1], ["serpent_roar", 0.15, -3.0, 1.0]],
	"wyvern": [["wyvern_flap", 0.0, -3.0, 1.0], ["wyvern_roar", 0.2, -3.0, 1.0]]}

var game: Node
var band := Vector2(96.0, 262.0)    # screen pixels above (title) and below (info panel) the heroes' band
var vp: SubViewport
var cam: Camera3D
var root3d: Node3D
var heroes := {}                    # cls -> Hero
var stands := {}                    # cls -> the Node3D its plinth, shaft, banner, candles and lights hang from
var spots := {}                     # cls -> SpotLight3D over them
var rims := {}                      # cls -> the rim light behind them
var ups := {}                       # cls -> the runes' light rising onto him (chosen and hovered only)
var homes := {}                     # cls -> feet position on its plinth now (world; moves with the carousel)
var shafts := {}                    # cls -> the light shaft's material (power)
var glows := {}                     # cls -> the plinth runes' material (power)
var scales := {}                    # cls -> the stand's scale now
var alphas := {}                    # cls -> how visible its slot is (1 in the light .. 0 gone)
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
# the carousel: `center` is where the ring stands now (a float index into CLASSES, wrapping), gliding
# toward `target` (an int index, unwrapped, so several turns queue into one longer glide)
var center := 0.0
var target := 0
var _glide_from := 0.0
var _glide_t := 1.0                 # 0..1 along the glide (1 = arrived)
var _glide_len := 1.0
var _wheel_t := 0.0
var turning := false

func setup(g: Node) -> void:
	game = g
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
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
	e.fog_light_color = Color(0.06, 0.065, 0.08)
	e.fog_density = 0.06
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 24, 0)
	key.light_energy = 0.45
	key.light_color = Color(0.75, 0.8, 1.0)
	key.shadow_enabled = true
	root3d.add_child(key)
	cam = Camera3D.new()
	cam.fov = FOV
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.35, 10.6), Vector3(0, 1.6, 0.4))
	_frame()
	ClassCathedral.build_hall(root3d)
	for n in root3d.get_children():
		if n is OmniLight3D and n.has_meta("flicker"):
			_flicker.append(n as OmniLight3D)
	var mid := CLASSES.find("knight")
	center = float(maxi(mid, 0))
	target = int(center)
	for i in CLASSES.size():
		var c: String = CLASSES[i]
		var col: Color = ACCENTS[c]
		# the stand: everything of its own that moves with it round the carousel
		var stand := Node3D.new()
		stand.name = "Stand_" + c
		root3d.add_child(stand)
		var built := ClassCathedral.build_stand(stand, PLINTH_R, PLINTH_TOP, col, int(EMBLEMS.get(c, 0)), i * 1.7)
		shafts[c] = built["shaft"]
		glows[c] = built["glow"]
		stands[c] = stand
		# light on the body itself: the shaft's light falling on him from in front and above (his colour warmed toward
		# white so faces and steel read), a rim light high behind him in his colour that outlines him, and for the
		# chosen and hovered one the runes' glow rising onto him from the plinth
		var sp := SpotLight3D.new()
		sp.light_color = col.lerp(Color(1.0, 0.94, 0.84), 0.55)
		sp.spot_angle = 24.0
		sp.spot_angle_attenuation = 0.6
		sp.spot_range = 11.0
		sp.light_energy = 1.0
		sp.light_specular = 0.8
		sp.shadow_enabled = false
		stand.add_child(sp)
		sp.look_at_from_position(Vector3(0, 6.2, 3.4), Vector3(0, PLINTH_TOP + 1.05, 0))
		spots[c] = sp
		var rim := OmniLight3D.new()
		rim.light_color = col
		rim.light_energy = 1.3
		rim.omni_range = 3.2
		rim.omni_attenuation = 1.4
		rim.position = Vector3(0, PLINTH_TOP + 2.3, -1.05)
		stand.add_child(rim)
		rims[c] = rim
		var up := OmniLight3D.new()
		up.light_color = col
		up.light_energy = 0.0
		up.omni_range = 1.9
		up.omni_attenuation = 1.6
		up.light_specular = 0.2
		up.position = Vector3(0, PLINTH_TOP + 0.12, 0.5)
		up.visible = false
		stand.add_child(up)
		ups[c] = up
		var h := Hero.new()
		h.puppet = true
		h.name = "Stage_" + c
		root3d.add_child(h)
		h.setup(game)
		var gear := {"_cls": c, "_helm": true}
		if not Dragon.is_dragon(c):
			gear["weapon"] = Items.make(str(Data.CLASSES[c].get("weapon", "hand_axe" if c == "demon" else "short_sword")))
		if c == "knight":
			gear["shield"] = Items.make("buckler")
		gear["armor"] = Items.make("quilted")
		h.apply_net_gear(gear)
		if Dragon.is_dragon(c):
			# a dragon is several metres long: shrunk onto its plinth and turned three-quarters so its length shows
			h.rig.scale = Vector3.ONE * Dragon.stage_scale(c)
		h.net_yaw = _face(c)
		h.rig.rotation.y = _face(c)
		h.net_has = true
		h.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		h.light.light_energy = 0.35
		h.anim_time = i * 1.7
		heroes[c] = h
		_sig_t[c] = -1.0
		_fid_t[c] = 0.0
		scales[c] = 1.0
		alphas[c] = 1.0
		homes[c] = Vector3(0, PLINTH_TOP, 0)
	_place(true)

# --- the carousel ------------------------------------------------------------------------------------------

## How far round the ring a class stands from the middle now: 0 in the middle, negative to the left.
func offset_of(c: String) -> float:
	var n := CLASSES.size()
	var i := CLASSES.find(c)
	if i < 0 or n == 0:
		return 99.0
	return wrapf(float(i) - center, -n * 0.5, n * 0.5)

## The class in the middle of the ring (the nearest, while it turns).
func centre_class() -> String:
	if CLASSES.is_empty():
		return ""
	return CLASSES[wrapi(int(roundf(center)), 0, CLASSES.size())]

## Turn the ring: +1 brings the hero on the right to the middle, -1 the one on the left. Turns while one is
## under way queue into one longer glide that eases from where the ring is now.
func turn(dir: int) -> void:
	if dir == 0 or CLASSES.size() < 2:
		return
	_set_target(target + dir)

## Bring a class to the middle the shortest way round.
func go_to(c: String) -> void:
	var i := CLASSES.find(c)
	if i < 0:
		return
	var n := CLASSES.size()
	var d := wrapf(float(i) - center, -n * 0.5, n * 0.5)
	var tg := int(roundf(center + d))
	if tg == target:
		return
	_set_target(tg)

## Snap the ring so a class stands in the middle, chosen, with no glide (opening the screen).
func snap_to(c: String) -> void:
	var i := CLASSES.find(c)
	if i < 0:
		return
	center = float(i)
	target = i
	_glide_t = 1.0
	turning = false
	_place(true)
	if chosen != c:
		chosen = c
		_sig_wait = 0.25
		for k in _sig_t:
			_sig_t[k] = -1.0
		picked.emit(c)

func _set_target(tg: int) -> void:
	# retarget smoothly: a new glide from where the ring is now, as long as the way left; rapid clicks
	# queue up, but never further than half the ring ahead (the rest are ignored, not spun through)
	var n := CLASSES.size()
	if absf(float(tg) - center) > n * 0.5 + 0.5:
		return
	target = tg
	_glide_from = center
	_glide_len = maxf(absf(float(target) - center), 0.001)
	_glide_t = 0.0
	turning = true
	Sfx.play("click", -6.0, 0.9)
	var arriving: String = CLASSES[wrapi(target, 0, n)]
	if arriving != chosen:
		# the hero that will arrive is the choice from now (the panel updates at once); its signature waits
		# until it stands in the light
		stop_skill()
		chosen = arriving
		_sig_wait = _glide_len * TURN_T * 0.55 + 0.3
		for k in _sig_t:
			_sig_t[k] = -1.0
		pick_sound(arriving)
		picked.emit(arriving)

func _glide(delta: float) -> void:
	if _glide_t >= 1.0:
		turning = false
		return
	# one slot takes TURN_T; a longer queued glide takes a little longer, not proportionally
	var secs := TURN_T * (0.6 + 0.4 * _glide_len)
	_glide_t = minf(_glide_t + delta / secs, 1.0)
	var a := _ease(_glide_t)
	center = lerpf(_glide_from, float(target), a)
	if _glide_t >= 1.0:
		center = float(target)
		turning = false
		# keep the numbers small
		var n := CLASSES.size()
		var w := wrapi(target, 0, n)
		center = float(w)
		target = w

static func _ease(x: float) -> float:
	# ease in-out: a gentle start, a soft landing (cubic)
	return x * x * (3.0 - 2.0 * x) if x < 1.0 else 1.0

## Interpolates a slot value across the fractional offset.
static func _slot(tab: Array, d: float) -> float:
	var a := absf(d)
	var i := int(floorf(a))
	if i >= tab.size() - 1:
		return float(tab[tab.size() - 1])
	return lerpf(float(tab[i]), float(tab[i + 1]), a - i)

## Puts every stand and hero where the ring says now. The stand at the back of the ring (half a ring from
## the middle) crosses from one side to the other unseen: the fade ends short of it, whatever the count.
func _place(snap: bool) -> void:
	var n := CLASSES.size()
	var vis_end := minf(VISIBLE, n * 0.5 - 0.02)
	var band := clampf(vis_end - 2.0, 0.3, 0.9)
	for c: String in CLASSES:
		var d := offset_of(c)
		var stand: Node3D = stands[c]
		var h: Hero = heroes[c]
		var x := signf(d) * _slot(SLOT_X, d)
		var z := _slot(SLOT_Z, d)
		var sc := _slot(SLOT_SCALE, d)
		var vis := clampf((vis_end - absf(d)) / band, 0.0, 1.0)
		vis = vis * vis * (3.0 - 2.0 * vis)
		if n <= 2:
			vis = 1.0
		# beyond the outer slots the stand walks further into the dark and sinks out of sight
		var far := maxf(absf(d) - 2.0, 0.0)
		stand.position = Vector3(x, -far * 0.25, z - far * 0.6)
		stand.scale = Vector3.ONE * sc
		stand.visible = vis > 0.001
		scales[c] = sc
		alphas[c] = vis
		homes[c] = stand.position + Vector3(0, PLINTH_TOP * sc, 0)
		h.scale = Vector3.ONE * sc
		# a puppet shows itself while `net_has` (Hero._puppet_process): the hidden slots' heroes are dropped
		h.net_has = vis > 0.001
		h.visible = h.net_has
		if snap:
			h.net_pos = homes[c]
			h.global_position = homes[c]

## Choose a class: the ring glides until it stands in the middle (`go_to`; `picked` is emitted as the glide
## sets off), or, already there, it is simply the chosen one.
func choose(c: String) -> void:
	if not heroes.has(c):
		return
	var i := CLASSES.find(c)
	if wrapi(target, 0, CLASSES.size()) != i:
		go_to(c)
		return
	if chosen != c:
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

## The class whose body is under this point of the stage (screen space of this control), or "". Only the
## heroes in the light count, the nearer first.
func class_at(p: Vector2) -> String:
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	var best := ""
	var bd := 1e9
	for c in heroes:
		if float(alphas.get(c, 0.0)) < 0.35:
			continue
		var h: Hero = heroes[c]
		var k: float = scales[c]
		var feet := cam.unproject_position(h.global_position) * sc
		var head := cam.unproject_position(h.global_position + Vector3(0, 1.9 * k, 0)) * sc
		var half := absf(feet.y - head.y) * 0.32
		if p.y < head.y - 10.0 or p.y > feet.y + 14.0:
			continue
		var d := absf(p.x - feet.x)
		# the nearer slot wins where they overlap
		var score := d + absf(offset_of(c)) * 40.0
		if d < half and score < bd:
			bd = score
			best = c
	return best

## Where a class's feet are on screen (this control's space): for its nameplate.
func feet_at(c: String) -> Vector2:
	var sc := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	return cam.unproject_position((heroes[c] as Hero).global_position) * sc

## How much of a class's nameplate shows: 1 in the middle, less to the sides, 0 when its slot is hidden.
func plate_alpha(c: String) -> float:
	var a: float = alphas.get(c, 0.0)
	return a * lerpf(1.0, 0.55, clampf(absf(offset_of(c)) / 2.0, 0.0, 1.0))

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := class_at((ev as InputEventMouseMotion).position)
		if c != hovered:
			hovered = c
			_fid_t[c] = 0.0 if c != "" else 0.0
			hovering.emit(c)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if c != "" else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		accept_event()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var c2 := class_at(mb.position)
			if c2 != "":
				if c2 == centre_class() and not turning:
					pick_sound(c2)
				choose(c2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_wheel(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_wheel(-1)

func _wheel(dir: int) -> void:
	# a wheel notch turns one slot; a fast spin doesn't fling the ring round
	if t - _wheel_t < WHEEL_GAP:
		return
	_wheel_t = t
	turn(dir)

## The stage fills the whole screen behind the title and the info panel, so the hall carries on round them (no
## black bands); the camera's frustum is shifted and widened so the heroes sit in the band between them (`band`:
## pixels kept for the title above and the panel below) framed exactly as a stage of just that band would be.
func _frame() -> void:
	if cam == null or size.y < 2.0:
		return
	var h := size.y
	var hs := maxf(h - band.x - band.y, 1.0)
	var near := 0.05
	cam.near = near
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.size = 2.0 * near * tan(deg_to_rad(FOV) * 0.5) * h / hs
	cam.frustum_offset = Vector2(0.0, -(band.y - band.x) * 0.5 / h * cam.size)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_frame()
	if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
		hovered = ""
		hovering.emit("")

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	_glide(delta)
	_place(false)
	if chosen != "" and _sig_t.get(chosen, -1.0) < 0.0 and _skill_c != chosen and not turning:
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
		var d := absf(offset_of(c))
		var vis: float = alphas[c]
		var lit := _slot(SLOT_LIGHT, d)
		var sp: SpotLight3D = spots[c]
		var rim: OmniLight3D = rims[c]
		var hov := c == hovered and c != chosen
		sp.light_energy = move_toward(sp.light_energy, (4.6 * lit + 0.7 + (1.8 if hov else 0.0)) * vis, delta * 12.0)
		rim.light_energy = (0.8 + 2.0 * lit + (0.6 if hov else 0.0)) * vis
		var up: OmniLight3D = ups[c]
		var upk := maxf(lit * lit, 0.55 if hov else 0.0) * vis
		up.light_energy = 1.5 * upk
		up.visible = upk > 0.05
		# the lights of the hidden slots are off (WebGL's light budget)
		sp.visible = vis > 0.05
		rim.visible = vis > 0.05
		h.light.visible = vis > 0.05
		h.light.light_energy = 0.35 * vis
		var pw := 0.18 + 0.82 * lit + (0.25 if hov else 0.0)
		if c == _skill_c:
			pw = 1.0
		pw *= vis
		var sm: ShaderMaterial = shafts[c]
		var nxt := move_toward(float(_pow.get(c, 0.2)), pw, delta * 3.0)
		_pow[c] = nxt
		sm.set_shader_parameter("power", nxt)
		var gm: ShaderMaterial = glows[c]
		gm.set_shader_parameter("power", nxt)
		(gm.get_meta("cap") as ShaderMaterial).set_shader_parameter("power", nxt)
		h.net_buff = false      # no buff aura on the stage: its motes floated in front of the chosen one; his light marks him
		if not h.visible:
			continue
		if c == _skill_c:
			_skill_show(c, h, home, delta)
		elif float(_sig_t[c]) >= 0.0:
			_signature(c, h, home, delta)
		elif c == hovered and d < 2.5:
			_fid_t[c] = float(_fid_t[c]) + delta
			_fidget(c, h, home, float(_fid_t[c]))
		else:
			_idle(c, h, home, i)
		if turning:
			# while the ring turns the puppet's lerp would lag behind its plinth: ride it exactly
			h.global_position = h.net_pos

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

## Which way a class faces on its plinth: toward the camera, the dragons turned three-quarters.
func _face(c: String) -> float:
	return FACE + (Dragon.stage_yaw(c) if Dragon.is_dragon(c) else 0.0)

## The stand's scale: lifts and reaches in a move are in the hero's own metres, scaled with it.
func _k(c: String) -> float:
	return float(scales.get(c, 1.0))

func _skill_show(c: String, h: Hero, home: Vector3, delta: float) -> void:
	var spec: Array = SKILL_SHOW[_skill_id]
	var style: String = spec[0]
	var dur: float = float(spec[1]) * Data.attack_pace(c)
	var k := _k(c)
	_skill_t += delta
	if _skill_t >= dur + SKILL_GAP:
		_skill_t -= dur + SKILL_GAP
		_skill_hit = false
	var resting := _skill_t > dur
	var a := clampf(_skill_t / dur, 0.0, 1.0)
	var st := {"move": 0.0, "atk": -1.0 if resting else a, "style": style, "block": 0.0, "hit": 0.0}
	var pos := home + Vector3(0, 0, STEP * k)
	var impact := Anim.impact_at(style)
	match _skill_id:
		"cleave":
			if not resting:
				pos.y += sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6 * k
				pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.2 * k
		"charge":
			# a short rush to the plinth's edge and back
			if not resting:
				pos.z += sin(a * PI) * 0.32 * k
				st["move"] = 1.0 - a
			impact = 0.5
		"drain":
			st["atk"] = -1.0 if resting else minf(a / 0.15, 1.0) * 0.6
			impact = 0.15
			if not resting and a > 0.15 and a < 0.95:
				_beam_t -= delta
				if _beam_t <= 0.0:
					_beam_t = 0.05
					var from := h.global_position + Vector3(0, 0.75, 0.35) * k
					Fx.burst(root3d, from + Vector3(randf_range(-0.05, 0.05), 0, 0), ACCENTS[c], 4, 3.5 * k, 0.07 * k, 0.5, true, 0.0, 6.0, Vector3(0, 0.08, 1))
		"rend", "phantom":
			# the wraith's lunge, kept on his plinth
			if not resting:
				pos.z += smoothstep(0.05, 0.4, a) * 0.25 * k
	h.net_pos = pos
	h.net_yaw = _face(c)
	h.net_st = st
	if not _skill_hit and not resting and a >= impact:
		_skill_hit = true
		_skill_fx(c, h, home)

## The skill's effects at its impact frame: the game's own, at stage scale.
func _skill_fx(c: String, h: Hero, home: Vector3) -> void:
	var col: Color = ACCENTS[c]
	var k := _k(c)
	var p := Vector3(home.x, home.y + 0.02, home.z + STEP * k)
	var yaw := h.rig.global_rotation.y
	var floor_front := Vector3(home.x, 0.03, home.z + 1.5 * k)
	var chest := h.global_position + Vector3(0, 1.1, 0.2) * k
	match _skill_id:
		"cleave":
			Fx.holy_slam(root3d, p + Vector3(0, 0, 0.25 * k), 1.3 * k)
			Sfx.play("cleave_hit", -10.0)
		"nova":
			Fx.ring(root3d, p, 2.4 * k, Color(1.0, 0.75, 0.3), 0.5)
			Fx.burst(root3d, p + Vector3(0, 0.9 * k, 0), Color(1.0, 0.8, 0.4), 40, 5.0 * k, 0.12 * k, 0.6, true, 0.0, 180.0)
			Sfx.play("holy_nova", -10.0)
		"charge":
			Fx.burst(root3d, p + Vector3(0, 0.6, 0.6) * k, Color(1.0, 0.9, 0.7), 24, 3.0 * k, 0.08 * k, 0.4, true, -2.0, 50.0, Vector3(0, 0.3, 1))
			Fx.flash(root3d, p + Vector3(0, 1.0, 0.6) * k, col, 2.0, 0.25, 3.0 * k)
			Sfx.play("charge_impact", -10.0)
		"cry":
			Fx.ring(root3d, p, 2.0 * k, Color(1.0, 0.85, 0.4), 0.6)
			Fx.pillar(root3d, p, Color(1.0, 0.8, 0.35), 0.8)
			Sfx.play("battle_cry", -10.0)
		"rend":
			WraithFx.rake(root3d, h.global_position, yaw, 1.6 * k, false)
			Sfx.play("reap_swing", -10.0)
		"siphon":
			WraithFx.latch(root3d, floor_front + Vector3(0, 0.9 * k, 0))
			WraithFx.pulse(root3d, chest, col, 0.6, 0.6 * k)
			Fx.burst(root3d, floor_front + Vector3(0, 0.9 * k, 0), col, 24, 4.0 * k, 0.07 * k, 0.5, true, 0.0, 10.0, Vector3(0, 0.1, -1))
			Sfx.play("shade_in", -10.0)
		"step":
			WraithFx.mist_out(root3d, p)
			WraithFx.mist_in(root3d, p + Vector3(0, 0, 0.1))
			Sfx.play("shade_out", -10.0)
		"grasp":
			WraithFx.grasp(root3d, floor_front, 1.0, 1.6 * k)
			Sfx.play("slam", -10.0, 0.9)
		"phantom":
			WraithFx.split(root3d, p)
			WraithFx.phantom_hit(root3d, floor_front + Vector3(0, 0.9 * k, 0), Vector3(0, 0, 1))
			Sfx.play("reap_swing", -10.0, 0.9)
		"night":
			WraithFx.scream(root3d, p, 2.2 * k)
			WraithFx.collapse(root3d, p, 1.4 * k)
			Sfx.play("host_summon", -10.0, 0.8)
		"fists":
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var d := DemonFx.lava_decal(root3d, h.global_position + fwd * 1.8 * k, 1.6 * k, 1.6, 0.25, yaw, deg_to_rad(50.0))
			d.position.y = home.y + 0.04
			Fx.burst(root3d, floor_front + Vector3(0, 0.3 * k, 0), col, 24, 4.5 * k, 0.08 * k, 0.5, true, -4.0, 50.0, fwd + Vector3(0, 0.5, 0))
			Sfx.play("hellclaw", -10.0)
		"icharge":
			DemonKitFx.smoke(root3d, p, "ash", 1.6 * k, 1.0)
			DemonKitFx.sparks(root3d, p + Vector3(0, 0.3 * k, 0), Vector3(0, 0.6, -1), 14, 40.0)
			Sfx.play("charge_dash", -10.0)
		"cslam":
			DemonKitFx.smoke(root3d, floor_front, "steam", 2.0 * k, 1.6)
			DemonKitFx.smoke(root3d, floor_front, "ash", 1.6 * k, 1.0)
			DemonKitFx.clods(root3d, floor_front + Vector3(0, 0.2 * k, 0), 14, 3.0 * k)
			Sfx.play("slam", -10.0)
		"hurl":
			DemonKitFx.smoke(root3d, floor_front, "impact", 2.6 * k, 1.5)
			DemonKitFx.clods(root3d, floor_front + Vector3(0, 0.2 * k, 0), 16, 3.5 * k)
			Sfx.play("boom", -12.0)
		"grip":
			DemonKitFx.sparks(root3d, floor_front + Vector3(0, 0.5 * k, 0), Vector3.UP, 18, 70.0)
			DemonKitFx.smoke(root3d, floor_front, "ash", 1.6 * k, 1.0)
			Sfx.play("impact_metal", -10.0, 0.8)
		"wrath":
			DemonKitFx.smoke(root3d, p, "blast", 3.0 * k, 1.4)
			DemonKitFx.sparks(root3d, chest, Vector3.UP, 30, 180.0)
			Sfx.play("roar", -10.0)
		"drain":
			Fx.flash(root3d, chest + Vector3(0, -0.3, 0.4) * k, col, 2.5, 1.2, 3.5 * k)
			Sfx.play("drain_start", -12.0)
		"blight":
			Fx.burst(root3d, chest, col, 26, 6.0 * k, 0.1 * k, 0.35, true, -2.0, 10.0, Vector3(0, 0.15, 1))
			WarlockFx.blight_burst(root3d, floor_front, 0.9 * k)
			Sfx.play("blight_cast", -10.0)
		"shackles":
			WarlockFx.shackle_cast(root3d, p, 1.7 * k)
			for j in 3:
				var to := Vector3(home.x + (j - 1) * 1.1 * k, 0.4 * k, home.z + 1.6 * k)
				WarlockFx.chain(root3d, chest, to, 0.8)
			Sfx.play("shackles", -10.0)
		"covenant":
			WarlockFx.covenant(root3d, p)
			Sfx.play("covenant", -10.0)
		"pierce":
			# a burning arrow streaking out of the bow
			Fx.burst(root3d, chest + Vector3(0, 0.2, 0.2) * k, Color(1.0, 0.5, 0.15), 30, 9.0 * k, 0.08 * k, 0.4, true, 0.0, 3.0, Vector3(0, 0, 1))
			Fx.flash(root3d, chest + Vector3(0, 0.2, 0.4) * k, Color(1.0, 0.5, 0.15), 2.0, 0.3, 3.0 * k)
			Sfx.play("bow", -10.0)
		"volley":
			for j in 5:
				Fx.burst(root3d, chest + Vector3(0, 0.2, 0.2) * k, Color(0.7, 0.9, 1.0), 6, 9.0 * k, 0.06 * k, 0.45, true, -2.0, 4.0, Vector3((j - 2) * 0.15, 1.0, 0.4))
			Fx.ring(root3d, floor_front, 1.2 * k, Color(0.7, 0.9, 1.0), 0.8)
			Fx.burst(root3d, floor_front + Vector3(0, 2.5 * k, 0), Color(0.75, 0.92, 1.0), 40, 4.0 * k, 0.06 * k, 0.6, true, -12.0, 15.0, Vector3.DOWN)
			Sfx.play("bow", -10.0)
		"snare":
			# Thunderstep: a gold sigil flares on the floor before him and lightning bursts out of it
			Fx.ring(root3d, floor_front, 0.8 * k, Color(1.0, 0.72, 0.22), 0.7)
			for j in 3:
				var to := floor_front + Vector3((j - 1) * 0.9 * k, 0.0, 0.3 * k)
				Fx.bolt(root3d, floor_front + Vector3(0, 0.1, 0), to + Vector3(0, 0.1, 0), Color(1.0, 0.8, 0.35), 0.3)
			Sfx.play("thunder_blast", -14.0)
		"beast":
			# the spirit beast answers: a grey spirit burst where it would pounce
			Fx.burst(root3d, floor_front + Vector3(0, 0.5 * k, 0), Color(0.75, 0.8, 0.85), 30, 3.0 * k, 0.1 * k, 0.7, true, 0.0)
			Fx.ring(root3d, floor_front, 1.0 * k, Color(0.75, 0.8, 0.85), 0.6)
			Sfx.play("growl", -8.0)
		"toxic":
			# the flask shatters on the floor in front: glass and a green cloud
			Fx.burst(root3d, floor_front, Color(0.8, 1.0, 0.85), 14, 3.0 * k, 0.05 * k, 0.4, true, -9.0)
			Fx.burst(root3d, floor_front + Vector3(0, 0.3 * k, 0), col, 34, 1.8 * k, 0.16 * k, 1.2, true, 0.4)
			Fx.flash(root3d, floor_front + Vector3(0, 0.6 * k, 0), col, 2.5, 0.6, 3.0 * k)
			Sfx.play("ice_shatter", -10.0, 1.35)
		"swarm":
			# a dark boil of flies out of his hand, wheeling over the floor in front
			Fx.burst(root3d, p + Vector3(0, 1.3 * k, 0), Color(0.08, 0.09, 0.06), 60, 2.4 * k, 0.03 * k, 1.4, false, 0.2, 60.0, Vector3(0, 0.3, -1))
			Fx.burst(root3d, floor_front + Vector3(0, 0.6 * k, 0), Color(0.5, 0.75, 0.3, 0.4), 18, 1.0 * k, 0.12 * k, 1.2, true, 0.0)
			Sfx.play("drip", -10.0, 0.6)
		"bloom":
			# something fleshy splits the floor and breathes out spores
			Fx.ring(root3d, floor_front, 1.1 * k, Color(0.62, 0.25, 0.32), 0.9)
			Fx.burst(root3d, floor_front + Vector3(0, 0.3 * k, 0), Color(0.8, 0.95, 0.4), 30, 1.6 * k, 0.05 * k, 1.1, true, 0.6, 30.0)
			Sfx.play("blight_burst", -10.0, 0.8)
		"fog":
			# the censer dashed down: pale fog rolls out over the plinth
			Fx.burst(root3d, p + Vector3(0, 0.3 * k, 0), Color(0.85, 0.85, 0.92, 0.5), 50, 2.2 * k, 0.4 * k, 1.8, false, 0.15, 85.0)
			Sfx.play("phase_erupt", -12.0, 1.3)
		"transfusion":
			# red serum rises through the tanks on his back
			Fx.burst(root3d, p + Vector3(0, 1.5 * k, 0.2 * k), Color(0.9, 0.2, 0.15), 20, 0.8 * k, 0.04 * k, 0.9, true, 1.5)
			Fx.flash(root3d, p + Vector3(0, 1.5 * k, 0), Color(0.9, 0.3, 0.2), 2.0, 0.5, 2.0 * k)
			Sfx.play("drip", -8.0, 0.5)
		"experiment":
			# the vat slammed down: glass and fluid burst, a quarantine ring
			Fx.ring(root3d, p, 2.4 * k, Plague.MIASMA, 0.8)
			Fx.burst(root3d, floor_front + Vector3(0, 0.5 * k, 0), Color(0.85, 1.0, 0.9), 20, 3.0 * k, 0.05 * k, 0.5, true, -9.0)
			Fx.burst(root3d, floor_front + Vector3(0, 0.4 * k, 0), col, 46, 4.0 * k, 0.14 * k, 0.9, true, 0.3)
			Sfx.play("ice_shatter", -9.0, 0.7)

## Alive: breathing (Anim's idle), the weight shifting, the head turning to look about, now and then a
## glance at you; the chosen one stands a step forward in the light.
func _idle(c: String, h: Hero, home: Vector3, i: int) -> void:
	var ph := t * 0.45 + i * 1.9
	var look := sin(ph) * 0.22 + sin(ph * 2.3 + 1.0) * 0.08
	if fmod(t + i * 2.3, 9.0) < 1.6:
		look = 0.0       # a look straight at you
	var k := _k(c)
	h.net_yaw = _face(c) + look
	h.net_pos = home + Vector3(sin(ph * 0.7) * 0.04, 0, STEP if c == chosen else 0.0) * k
	h.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}

## Hovered: each class fidgets in its own (annoying) way.
func _fidget(c: String, h: Hero, home: Vector3, f: float) -> void:
	var st := {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
	var k := _k(c)
	var pos := home + Vector3(0, 0, STEP if c == chosen else 0.05) * k
	var yaw := _face(c)
	match c:
		"knight":
			# show-off sword combo, over and over, stamping between swings
			var cyc := fmod(f, 1.5)
			var j := int(cyc / 0.5)
			st["style"] = ["swipe1", "swipe2", "swipe3"][j]
			st["atk"] = fmod(cyc, 0.5) / 0.5
			pos.y += absf(sin(f * 6.3)) * 0.05 * k
			yaw = FACE + sin(f * 3.0) * 0.25
		"wraith":
			# rakes the air with his claws over and over, drifting side to side
			var cyc := fmod(f, 1.1)
			st["style"] = "rend"
			st["atk"] = cyc / 1.1
			pos.x += sin(f * 2.4) * 0.25 * k
			yaw = FACE + sin(f * 2.4) * 0.3
		"demon":
			# pounds the air with both fists, stamping
			pos.y += absf(sin(f * 7.0)) * 0.12 * k
			st["style"] = "fists"
			st["atk"] = fmod(f, 0.9) / 0.9
		"warlock":
			# cackling, tiny frantic hops
			st["style"] = "cackle"
			st["atk"] = fmod(f, 1.2) / 1.2
			pos.y += absf(sin(f * 11.0)) * 0.14 * k
			yaw = FACE + sin(f * 9.0) * 0.35
		"archer":
			# sways side to side drawing the bow at everything
			pos.x += sin(f * 4.0) * 0.22 * k
			yaw = FACE + sin(f * 2.0) * 0.9
			st["style"] = "bow"
			st["atk"] = fmod(f, 0.8) / 0.8
		"doug":
			# a bow to the crowd, a chest-pound, a grin: the old act
			st["style"] = "car" if fmod(f, 6.0) < 3.0 else "juggle"
			st["atk"] = fmod(f, 3.0) / 3.0
			yaw = FACE + sin(f * 1.7) * 0.4
		"plague":
			# holds a vial up to the light and peers at it, tilting his head, again and again
			st["style"] = "pd_inspect"
			st["atk"] = fmod(f, 3.2) / 3.2
			yaw = FACE + sin(f * 1.3) * 0.2
		"wyrm", "serpent", "wyvern":
			# snaps and rakes at the hand over it, claw then bite, swinging its head after it
			var cyc := fmod(f, 1.4)
			st["style"] = "swipe1" if cyc < 0.7 else "swipe2"
			st["atk"] = fmod(cyc, 0.7) / 0.7
			yaw = _face(c) + sin(f * 1.6) * 0.3
	h.net_pos = pos
	h.net_yaw = yaw
	h.net_st = st

## The chosen class's signature move, with its effects at the impact.
func _signature(c: String, h: Hero, home: Vector3, delta: float) -> void:
	var sig: Array = SIGNATURE[c]
	var dur: float = sig[1]
	var s: float = float(_sig_t[c]) + delta
	_sig_t[c] = s
	var k := _k(c)
	var a := clampf(s / dur, 0.0, 1.0)
	var pos := home + Vector3(0, 0, STEP * k)
	var front := h.global_position + Vector3(0, 0, 1.0 * k)
	var col: Color = ACCENTS[c]
	var st := {"move": 0.0, "atk": a, "style": str(sig[0]), "block": 0.0, "hit": 0.0}
	match c:
		"knight":
			# leaps and brings the sword down
			pos.y += sin(clampf(a / 0.5, 0.0, 1.0) * PI) * 0.6 * k
			pos.z += clampf(a / 0.5, 0.0, 1.0) * 0.2 * k
		"wraith":
			# the lunge of Spectral Rend, kept on the plinth
			pos.z += smoothstep(0.05, 0.4, a) * 0.3 * k
		"warlock":
			# Drain Life: both hands out, holding the beam
			st["atk"] = minf(a / 0.2, 1.0) * 0.6
			if a > 0.2 and a < 0.95:
				_beam_t -= delta
				if _beam_t <= 0.0:
					_beam_t = 0.05
					var from := h.global_position + Vector3(0, 0.75, 0.35) * k
					Fx.burst(root3d, from + Vector3(randf_range(-0.05, 0.05), 0, 0), col, 4, 3.5 * k, 0.07 * k, 0.5, true, 0.0, 6.0, Vector3(0, 0.08, 1))
	h.net_pos = pos
	h.net_yaw = _face(c)
	h.net_st = st
	if not bool(_hit_done.get(c, false)) and a >= float(sig[2]):
		_hit_done[c] = true
		match c:
			"knight":
				var at := home + Vector3(0, 0.02, 0.2 * k)
				Fx.ring(root3d, at, 1.6 * k, Color(1.0, 0.92, 0.6), 0.55)
				Fx.burst(root3d, at + Vector3(0, 0.3 * k, 0), Color(1.0, 0.85, 0.45), 40, 5.0 * k, 0.1 * k, 0.6, true, -5.0)
				Sfx.play("cleave_hit", -10.0)
			"wraith":
				WraithFx.rake(root3d, h.global_position, h.net_yaw, 2.4 * k, false)
				Sfx.play("reap_swing", -12.0)
			"demon":
				# the fists crack the stage open ahead of him
				var fwd2 := Vector3(-sin(h.net_yaw), 0, -cos(h.net_yaw))
				var d := DemonFx.lava_decal(root3d, h.global_position + fwd2 * 1.8 * k, 1.6 * k, 1.6, 0.25, h.net_yaw, deg_to_rad(50.0))
				d.position.y = h.global_position.y + 0.04
				Fx.burst(root3d, front + Vector3(0, 0.3 * k, 0), col, 24, 4.5 * k, 0.08 * k, 0.5, true, -4.0, 50.0, fwd2 + Vector3(0, 0.5, 0))
				Fx.flash(root3d, front + Vector3(0, 0.7 * k, 0), col, 3.0, 0.3, 4.0 * k)
				Sfx.play("hellclaw", -10.0)
				Sfx.play("slam", -16.0, 1.2)
			"warlock":
				Fx.flash(root3d, h.global_position + Vector3(0, 0.8, 0.6) * k, col, 2.5, 1.4, 3.5 * k)
				Sfx.play("drain", -14.0)
			"archer":
				# the volley: a fan of arrows streaking up out of the bow
				for j in 5:
					Fx.burst(root3d, h.global_position + Vector3(0, 1.3, 0.3) * k, col, 6, 9.0 * k, 0.06 * k, 0.45, true, -2.0, 4.0, Vector3((j - 2) * 0.15, 1.0, 0.4))
				Fx.flash(root3d, h.global_position + Vector3(0, 1.4, 0.4) * k, col, 2.0, 0.3, 3.0 * k)
				Sfx.play("bow", -10.0)
			"doug":
				# the pie lands at the edge of the light: a cream splat and confetti
				var at4 := Vector3(h.global_position.x, 0.05, h.global_position.z + 1.6 * k)
				Fx.burst(root3d, at4 + Vector3(0, 0.4 * k, 0), DougFx.CREAM, 30, 3.0 * k, 0.1 * k, 0.6, false, -9.0)
				for cc in DougFx.CONFETTI:
					Fx.burst(root3d, at4 + Vector3(0, 0.8 * k, 0), cc, 10, 3.5 * k, 0.05 * k, 1.0, false, -3.0, 180.0)
				Sfx.play("arena_horn", -10.0, 2.4)
			"plague":
				# the flask shatters at the edge of the light: glass and a green cloud
				var at2 := Vector3(h.global_position.x, 0.05, h.global_position.z + 1.6 * k)   # on the floor in front of the plinth
				Fx.burst(root3d, at2, Color(0.8, 1.0, 0.85), 14, 3.0 * k, 0.05 * k, 0.4, true, -9.0)
				Fx.burst(root3d, at2 + Vector3(0, 0.3 * k, 0), col, 34, 1.8 * k, 0.16 * k, 1.2, true, 0.4)
				Fx.flash(root3d, at2 + Vector3(0, 0.6 * k, 0), col, 2.5, 0.6, 3.0 * k)
				Sfx.play("ice_shatter", -10.0, 1.35)
			"wyrm", "serpent", "wyvern":
				# the tail spin: a ring of dust in the dragon's colour swept round the plinth
				var at3 := home + Vector3(0, 0.03, 0)
				Fx.ring(root3d, at3, 1.5 * k, col, 0.5)
				Fx.burst(root3d, at3 + Vector3(0, 0.2 * k, 0), col.lerp(Color(0.7, 0.65, 0.6), 0.5), 30, 4.0 * k, 0.08 * k, 0.5, true, -4.0, 180.0)
				Sfx.play(c + "_tail", -8.0)
	if s >= dur:
		_sig_t[c] = -1.0
		_sig_wait = SIG_EVERY
