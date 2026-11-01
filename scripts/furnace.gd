class_name Furnace
extends Inter
## Halvar's furnace (the Act I camp, beside his forge): weapons are tempered here with the wood the heroes fell
## (Harvest). Clicking it opens the furnace window (FurnaceUI). The fire is a small heat model, stepped every frame:
##
##   dT/dt = (P - LOSS * (T - AMBIENT)) / MASS        P = the heat of the logs burning (x BELLOWS_HEAT on the bellows)
##
## At most SLOTS logs burn at once (the rest wait in the hopper), each for its "burn" seconds (twice as fast on the
## bellows), and the fire can't get hotter than the best fuel in it allows (Data.BASES "fuel" "max_temp": pine
## 1040 °C, oak 1240 °C, only Ashen Heartwood the full MAX_T). With nothing left to burn it cools. So heat takes
## time, fuel and the right wood, and flooding the firebox does nothing.
##
## Tempering (Items.temper_cost / TEMPER_BANDS, weapons only, at most Items.TEMPER_MAX): pick a weapon, load the
## charge into the hopper (its logs, from +4 its Ashen Heartwood), ignite (the smith's fee is paid then), get the
## fire to the level's band, hold the weapon in it for the soak (the soak only runs while the fire is hot enough),
## then quench. A full soak: the weapon gains a level. Quenched early, or the fire let die: the wood is spent and
## the weapon is as it was. Either way the charge is gone: what's left in the hopper burns on (the "spent" fire)
## and the next temper needs a fresh charge. The furnace is each player's own (nothing of it crosses the network).

const MAX_T := 1400.0
const AMBIENT := 20.0
const MASS := 6.0             # thermal mass: the fire's time constant is MASS / LOSS (about 35 s)
const LOSS := 0.172
const SLOTS := 3
const BELLOWS_HEAT := 1.4
const BELLOWS_BURN := 2.0
const HOPPER_MAX := 60

var temp := AMBIENT
var burning: Array = []       # [[base id, seconds left]]
var hopper: Array = []        # base ids loaded for the next temper (the charge)
var spent: Array = []         # base ids left from a temper that has ended: they burn first, but count for nothing
var lit := false
var bellows := false
var item = null               # the weapon in the heat (a Dictionary on the hero, equipped or in the bag)
var cost := {}
var soak := 0.0
var session := "idle"         # idle | ready (a weapon chosen) | heating (ignited, soaking)
var last_result := ""
# visuals
var _fire_mats: Array = []
var _mouth_light: OmniLight3D
var _flames: GPUParticles3D
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _haze: MeshInstance3D
var _bellows_node: Node3D
var _held: Node3D             # the weapon's model in the mouth of the furnace while it soaks
var _held_mat: ShaderMaterial
var _roar: AudioStreamPlayer
var _bel_t := 0.0
var _vis_t := 0.0

# ---------------------------------------------------------------- the heat
## The hottest the fuel now burning (or waiting, for a planned fire) allows.
func fuel_cap() -> float:
	var c := AMBIENT
	for b in burning:
		c = maxf(c, float(Data.BASES[b[0]]["fuel"]["max_temp"]))
	return c

func power() -> float:
	var p := 0.0
	for b in burning:
		p += float(Data.BASES[b[0]]["fuel"]["heat"])
	return p * (BELLOWS_HEAT if bellows and lit else 1.0)

## Steps the fire by `delta` seconds (every frame; tests call it directly).
func step(delta: float) -> void:
	if lit:
		while burning.size() < SLOTS and (not spent.is_empty() or not hopper.is_empty()):
			var b: String = spent.pop_front() if not spent.is_empty() else hopper.pop_front()
			burning.append([b, float(Data.BASES[b]["fuel"]["burn"])])
	var p := power() if lit else 0.0
	var before := temp
	temp += (p - LOSS * (temp - AMBIENT)) / MASS * delta
	if not burning.is_empty():
		var cap := fuel_cap()
		if temp > cap:
			# more than this wood can give: it can't rise, and falls back to what the fuel sustains
			var t0 := minf(temp, before)
			temp = maxf(cap, t0 - (t0 - cap) * minf(1.0, delta * 0.8) - delta * 6.0)
	temp = clampf(temp, AMBIENT, MAX_T)
	var rate := BELLOWS_BURN if bellows and lit else 1.0
	for i in range(burning.size() - 1, -1, -1):
		burning[i][1] -= delta * rate
		if float(burning[i][1]) <= 0.0:
			burning.remove_at(i)
	if lit and burning.is_empty() and hopper.is_empty() and spent.is_empty():
		lit = false
	if session == "heating" and item != null and temp >= float(cost.get("temp", MAX_T)):
		soak = minf(soak + delta, float(cost.get("soak", 1.0)))

## 0..1 along the furnace's range, for the visuals.
func heat01() -> float:
	return clampf((temp - AMBIENT) / (MAX_T - AMBIENT), 0.0, 1.0)

## The colour of hot metal and flame at a temperature (dull red, cherry, orange, yellow, white).
static func heat_color(t: float) -> Color:
	var keys := [[400.0, Color(0.25, 0.02, 0.0)], [600.0, Color(0.7, 0.06, 0.01)], [850.0, Color(1.0, 0.28, 0.03)],
		[1050.0, Color(1.0, 0.55, 0.12)], [1250.0, Color(1.0, 0.82, 0.48)], [1400.0, Color(1.0, 0.97, 0.9)]]
	if t <= 400.0:
		return Color(0.25, 0.02, 0.0) * clampf(t / 400.0, 0.0, 1.0)
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var u := (t - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0]))
			return (keys[i - 1][1] as Color).lerp(keys[i][1], u)
	return keys[keys.size() - 1][1]

## The band a temperature is in: -1 below Cherry red, else 0..4 (Items.TEMPER_BAND_NAMES).
static func band_of(t: float) -> int:
	var b := -1
	for i in Items.TEMPER_BANDS.size():
		if t >= float(Items.TEMPER_BANDS[i]):
			b = i
	return b

# ---------------------------------------------------------------- tempering
func hopper_count(base := "") -> int:
	if base == "":
		return hopper.size()
	return hopper.count(base)

## Puts a weapon in front of the fire. "" or the reason it can't be.
func choose(it) -> String:
	if session == "heating":
		return "Finish or quench the weapon in the fire first."
	if it == null or Data.BASES[it["base"]]["slot"] != "weapon":
		return "Only weapons can be tempered."
	if int(it.get("temper", 0)) >= Items.TEMPER_MAX:
		return "It's tempered as hard as steel will go (+%d)." % Items.TEMPER_MAX
	item = it
	cost = Items.temper_cost(it)
	soak = 0.0
	session = "ready"
	return ""

## Moves n logs of a base from the hero's bag into the hopper. Returns how many went in.
func load_fuel(hero: Node, base: String, n: int) -> int:
	n = mini(n, HOPPER_MAX - hopper.size() - spent.size())
	n = mini(n, hero.count_of(base))
	if n <= 0 or not hero.take_items(base, n):
		return 0
	for i in n:
		hopper.append(base)
	return n

## Takes back what's in the hopper (only before the fire is lit for this temper).
func unload(hero: Node) -> void:
	if session == "heating":
		return
	for b in hopper:
		hero.add_to_inventory(Items.resource(b, 1))
	hopper.clear()

## What's missing before this temper can be lit: "" when it's ready.
func missing(hero: Node) -> String:
	if item == null:
		return "Choose a weapon to temper."
	var need_l := int(cost["logs"])
	var need_h := int(cost["heart"])
	if hopper.size() < need_l:
		return "Load %d more log%s." % [need_l - hopper.size(), "" if need_l - hopper.size() == 1 else "s"]
	if hopper.count("heartwood") < need_h:
		return "This heat needs %d Ashen Heartwood in the charge." % need_h
	if int(hero.gold) < int(cost["gold"]):
		return "Halvar's fee is %d gold." % int(cost["gold"])
	return ""

## Lights the charged furnace: the fee is paid and the soak can begin.
func ignite(hero: Node) -> String:
	var m := missing(hero)
	if m != "":
		return m
	hero.gold -= int(cost["gold"])
	lit = true
	session = "heating"
	soak = 0.0
	return ""

## Draws the weapon out and plunges it in the trough. True if it took the temper.
func quench(hero: Node) -> bool:
	if session != "heating" or item == null:
		return false
	var ok := soak >= float(cost["soak"]) - 0.001
	if ok:
		item["temper"] = int(item.get("temper", 0)) + 1
		last_result = "ok"
		hero.recalc()
	else:
		last_result = "fail"
	# the charge is spent: what's left of it burns on, but the next temper needs its own
	spent.append_array(hopper)
	hopper.clear()
	item = null
	session = "idle"
	soak = 0.0
	return ok

## Walking away (the window closed) mid-temper is a quench before time: the weapon is safe, the charge spent.
func abandon(hero: Node) -> void:
	if session == "heating":
		quench(hero)
	elif session == "ready":
		item = null
		session = "idle"

# ---------------------------------------------------------------- the furnace in the camp
## Built beside the smith's forge (ForestCamp): a stone furnace with a firebox, a chimney, bellows and a woodpile.
static func place(w: World, at: Vector3, yaw: float) -> Furnace:
	var f := Furnace.new()
	f.kind = "furnace"
	f.label = "Furnace"
	f.radius = 2.4
	w.add_child(f)
	f.position = Vector3(at.x, w.height_at(at.x, at.z), at.z)
	f.rotation.y = yaw
	f._build_model()
	w.interactables.append(f)
	w.add_box(Vector3(at.x, 0, at.z), Vector2(1.6, 1.0), yaw)
	return f

const MOUTH := Vector3(0, 0.95, 0.72)    # the firebox's opening, in the furnace's frame (it faces +z)

func _stone() -> StandardMaterial3D:
	var m := Mats.mat(Color(0.33, 0.31, 0.29), 0.95)
	return m

func _build_model() -> void:
	var stone := _stone()
	var dark := Mats.mat(Color(0.16, 0.15, 0.14), 0.95)
	var soot := Mats.mat(Color(0.07, 0.065, 0.06), 1.0)
	# the plinth and the chamber: rough-laid courses, each stone its own block, a little out of true
	var r := RandomNumberGenerator.new()
	r.seed = 9182
	var base := Models.P(self, Geo.box(2.2, 0.35, 1.9), dark, Vector3(0, 0.17, 0))
	base.name = "plinth"
	for row in 6:
		var y := 0.42 + row * 0.24
		var rad := 0.95 - row * 0.03
		var n := 11
		for k in n:
			var a := TAU * (k + (0.5 if row % 2 == 1 else 0.0)) / n
			var p := Vector3(sin(a) * rad, y, cos(a) * rad * 0.85)
			# leave the mouth open at the front
			if row < 4 and absf(wrapf(a, -PI, PI)) < 0.42:
				continue
			var blk := Models.P(self, Geo.box(0.5 + r.randf_range(-0.04, 0.05), 0.23, 0.32), stone, p, Vector3(r.randf_range(-3, 3), rad2deg_(a) + r.randf_range(-4, 4), r.randf_range(-2, 2)))
			blk.scale = Vector3.ONE * r.randf_range(0.95, 1.05)
	# the dome and the chimney
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.92
	sm.height = 1.1
	sm.is_hemisphere = true
	dome.mesh = sm
	dome.material_override = stone
	dome.position = Vector3(0, 1.82, 0)
	dome.scale = Vector3(1.0, 0.75, 0.85)
	add_child(dome)
	var chim := Models.P(self, Geo.cyl(0.24, 0.3, 1.9, 10), stone, Vector3(0, 2.75, -0.2))
	chim.name = "chimney"
	Models.P(self, Geo.cyl(0.3, 0.3, 0.12, 10), dark, Vector3(0, 3.72, -0.2))
	# the mouth: a soot-black arch with the fire behind it
	Models.P(self, Geo.box(0.62, 0.08, 0.3), dark, Vector3(0, 1.36, 0.78))       # lintel
	for sx in [-0.34, 0.34]:
		Models.P(self, Geo.box(0.08, 0.66, 0.3), dark, Vector3(sx, 1.0, 0.78))
	Models.P(self, Geo.box(0.6, 0.62, 0.05), soot, Vector3(0, 1.0, 0.4))         # the back of the firebox
	# the fire seen through the mouth: two crossed flame cards and a bed of coals, shaded by the heat
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.62, 0.6)
		q.mesh = qm
		var fm := ShaderMaterial.new()
		fm.shader = _shader("flame", FLAME_SHADER)
		fm.set_shader_parameter("seed", float(i) * 3.7)
		q.material_override = fm
		q.position = Vector3((i - 1) * 0.08, 0.98, 0.5 + i * 0.07)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		_fire_mats.append(fm)
	var coals := MeshInstance3D.new()
	var cq := QuadMesh.new()
	cq.size = Vector2(0.58, 0.32)
	coals.mesh = cq
	var cm := ShaderMaterial.new()
	cm.shader = _shader("coals", COALS_SHADER)
	coals.material_override = cm
	coals.rotation_degrees = Vector3(-90, 0, 0)
	coals.position = Vector3(0, 0.71, 0.58)
	add_child(coals)
	_fire_mats.append(cm)
	_mouth_light = OmniLight3D.new()
	_mouth_light.position = MOUTH + Vector3(0, 0.05, 0.35)
	_mouth_light.omni_range = 6.5
	_mouth_light.light_energy = 0.0
	_mouth_light.shadow_enabled = false
	add_child(_mouth_light)
	# flames licking out of the mouth, embers and sparks, smoke out of the chimney
	_flames = _particles(24, 0.45, Color(1.0, 0.5, 0.12, 0.9), 0.14, 0.6, 2.0, true)
	_flames.position = MOUTH + Vector3(0, 0.05, 0.12)
	add_child(_flames)
	_embers = _particles(20, 1.8, Color(1.0, 0.55, 0.15, 1.0), 0.03, 1.6, 0.8, true)
	_embers.position = MOUTH + Vector3(0, 0.2, 0.3)
	add_child(_embers)
	_sparks = _particles(16, 1.1, Color(1.0, 0.85, 0.5, 1.0), 0.02, 0.6, 3.5, true)
	_sparks.position = Vector3(0, 3.8, -0.2)
	add_child(_sparks)
	_smoke = _particles(18, 3.5, Color(0.22, 0.2, 0.19, 0.55), 0.7, 0.45, 0.9, false)
	_smoke.position = Vector3(0, 3.85, -0.2)
	add_child(_smoke)
	# heat haze over the mouth and chimney (screen-space; desktop only)
	if not OS.has_feature("web"):
		_haze = MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(1.2, 1.6)
		_haze.mesh = hq
		var hm := ShaderMaterial.new()
		hm.shader = _shader("haze", HAZE_SHADER)
		_haze.material_override = hm
		_haze.position = Vector3(0, 2.1, 0.9)
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_haze)
	# the bellows on its frame at the side, nozzle into the firebox
	_bellows_node = Node3D.new()
	_bellows_node.position = Vector3(-1.25, 0.75, 0.25)
	_bellows_node.rotation_degrees = Vector3(0, -110, 0)
	add_child(_bellows_node)
	var wood := Props.wood()
	var leather := Mats.mat(Color(0.32, 0.2, 0.12), 0.8)
	Models.P(_bellows_node, Geo.box(0.62, 0.05, 0.4), wood, Vector3(0, -0.12, 0)).name = "board_lo"
	var top := Models.P(_bellows_node, Geo.box(0.62, 0.05, 0.4), wood, Vector3(0, 0.12, 0))
	top.name = "board_hi"
	var bag := Models.P(_bellows_node, Geo.box(0.56, 0.22, 0.36), leather, Vector3(0, 0, 0))
	bag.name = "bag"
	Models.P(_bellows_node, Geo.cyl(0.03, 0.05, 0.42, 8), Mats.mat(Color(0.35, 0.32, 0.3), 0.4, 0.8), Vector3(-0.5, 0, 0), Vector3(0, 0, 90))
	Models.P(_bellows_node, Geo.box(0.4, 0.03, 0.03), wood, Vector3(0.45, 0.14, 0)).name = "handle"
	# a woodpile beside it, split logs in a rack
	var pile := Node3D.new()
	pile.position = Vector3(1.45, 0.0, 0.1)
	pile.rotation_degrees = Vector3(0, 90, 0)
	add_child(pile)
	var kinds := ["oak_log", "oak_log", "pine_log"]
	for row in 3:
		for k in 4 - row:
			var lg := Wood.log_node(kinds[(row + k) % 3], 0.09, 0.85, row * 4 + k)
			lg.rotation_degrees = Vector3(0, 0, 90)
			lg.position = Vector3(-0.42, 0.1 + row * 0.16, (k - (3 - row) * 0.5) * 0.19)
			pile.add_child(lg)
	# a quenching trough of dark water in front
	var trough := Node3D.new()
	trough.position = Vector3(-0.95, 0.0, 1.35)
	add_child(trough)
	Models.P(trough, Geo.box(0.9, 0.36, 0.42), wood, Vector3(0, 0.18, 0))
	var water := Models.P(trough, Geo.box(0.8, 0.02, 0.32), Mats.mat(Color(0.05, 0.07, 0.08), 0.05, 0.0), Vector3(0, 0.33, 0))
	water.name = "water"

static var _shaders := {}
static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

static func rad2deg_(a: float) -> float:
	return rad_to_deg(a)

func _particles(amount: int, speed: float, col: Color, size: float, life: float, up: float, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, up, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	if not additive:
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 1.8))
		var st := CurveTexture.new()
		st.curve = sc
		pm.scale_curve = st
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = Mats.particle_mat(additive, Color(2, 2, 2) if additive else Color.WHITE)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

func _process(delta: float) -> void:
	step(delta)
	_vis_t += delta
	var h := heat01()
	var col := heat_color(temp)
	var glow := clampf((temp - 250.0) / 900.0, 0.0, 1.4)
	for m in _fire_mats:
		(m as ShaderMaterial).set_shader_parameter("heat", h)
		(m as ShaderMaterial).set_shader_parameter("col", col)
		(m as ShaderMaterial).set_shader_parameter("lit", 1.0 if lit else 0.0)
	_mouth_light.light_color = col.lerp(Color(1.0, 0.6, 0.3), 0.3)
	_mouth_light.light_energy = glow * 2.6 + (sin(_vis_t * 9.0) * 0.12 + sin(_vis_t * 23.0) * 0.06) * glow
	_flames.emitting = lit and temp > 300.0
	_flames.amount_ratio = clampf(h * 1.3, 0.2, 1.0)
	_embers.emitting = temp > 450.0
	_embers.amount_ratio = clampf(h * 1.2, 0.15, 1.0)
	_sparks.emitting = lit and temp > 900.0
	_smoke.emitting = lit or temp > 300.0
	_smoke.amount_ratio = clampf(0.3 + (1.0 - h) * 0.5 if lit else 0.25, 0.15, 1.0)
	if _flames.process_material is ParticleProcessMaterial:
		var g := ((_flames.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D).gradient
		g.set_color(0, Color(col.r, col.g, col.b, 0.9))
	if _haze:
		(_haze.material_override as ShaderMaterial).set_shader_parameter("strength", clampf((temp - 500.0) / 900.0, 0.0, 1.0))
	# the bellows: squeezed in a steady rhythm while it's worked
	_bel_t = (_bel_t + delta * 2.6) if bellows and lit else maxf(0.0, _bel_t - delta)
	var sq := (sin(_bel_t * TAU) * 0.5 + 0.5) if bellows and lit else 0.0
	var top := _bellows_node.get_node_or_null("board_hi") as Node3D
	if top:
		top.position.y = 0.12 - sq * 0.09
		top.rotation_degrees.z = -sq * 8.0
		(_bellows_node.get_node("bag") as Node3D).scale = Vector3(1.0, 1.0 - sq * 0.4, 1.0)
	# the weapon in the mouth, glowing as it takes the heat
	_update_held()
	_update_roar()

func _exit_tree() -> void:
	if _roar != null and is_instance_valid(_roar):
		_roar.queue_free()
	_roar = null

func _update_held() -> void:
	var want := session == "heating" and item != null
	if want and _held == null:
		_held = Node3D.new()
		var m := Models.item_model(item)
		_held.add_child(m)
		m.rotation_degrees = Vector3(0, 90, -12)
		_held.position = MOUTH + Vector3(0.1, -0.08, 0.25)
		_held_mat = ShaderMaterial.new()
		_held_mat.shader = _shader("hotmetal", HOT_METAL_SHADER)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = _held_mat
		add_child(_held)
	elif not want and _held != null:
		_held.queue_free()
		_held = null
	if _held != null:
		var k := clampf(soak / maxf(0.1, float(cost.get("soak", 1.0))), 0.0, 1.0)
		var g := clampf((temp - 450.0) / 950.0, 0.0, 1.0) * (0.35 + 0.65 * k)
		_held_mat.set_shader_parameter("glow", g)
		_held_mat.set_shader_parameter("col", heat_color(temp))

## The fire's roar: louder and higher as it heats (the wind stands in until the furnace has its own recording).
func _update_roar() -> void:
	var want := lit or temp > 350.0
	var nm := "furnace_roar" if Harvest.sfx().bank.has("furnace_roar") else "wind"
	if want and _roar == null:
		var near := false
		for hh in get_tree().get_nodes_in_group("hero"):
			if (hh as Node3D).global_position.distance_to(global_position) < 14.0:
				near = true
		if near:
			_roar = Harvest.sfx().start_loop(nm, -30.0, 0.5)
	elif not want and _roar != null:
		_roar.queue_free()
		_roar = null
	if _roar != null:
		var h := heat01()
		_roar.volume_db = lerpf(-26.0, -9.0, h) + (3.0 if bellows and lit else 0.0)
		_roar.pitch_scale = lerpf(0.42, 0.9, h)

# ---------------------------------------------------------------- shaders
## A flame card: tongues of fire rising and flickering, coloured by the heat (dull red to white), dense at the base.
const FLAME_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform float heat = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.4, 0.1);
uniform float lit = 0.0;
uniform float seed = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fbm(vec2 p){ float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += vn(p) * a; p *= 2.03; a *= 0.5; } return s; }
void fragment(){
	vec2 uv = UV;
	float y = 1.0 - uv.y;
	float t = TIME * (1.4 + heat * 1.6);
	float n = fbm(vec2(uv.x * 3.0 + seed, y * 2.5 - t));
	float tall = 0.3 + heat * 0.75;
	float shape = smoothstep(0.5, 0.0, abs(uv.x - 0.5) * (1.0 + y * 1.4)) * smoothstep(tall, tall * 0.25, y + n * 0.35);
	float core = shape * smoothstep(0.35, 0.9, n + (1.0 - y) * 0.4);
	vec3 c = mix(col * vec3(1.0, 0.55, 0.35), col, core) + vec3(1.0, 0.95, 0.85) * core * core * heat;
	float a = shape * (0.25 + lit * 0.75) * clamp(heat * 2.5, 0.0, 1.0);
	ALBEDO = c * a * 1.6;
	ALPHA = a;
}
"""

## The bed of coals: cracked, glowing through, breathing; it still glows a little after the fire dies.
const COALS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float heat = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.4, 0.1);
uniform float lit = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void fragment(){
	vec2 p = UV * vec2(9.0, 5.0);
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float lump = 1.0 - smoothstep(0.25, 0.5, length(f + (vec2(h21(cell), h21(cell + 7.0)) - 0.5) * 0.3));
	float breathe = 0.7 + 0.3 * sin(TIME * (1.0 + h21(cell) * 2.0) + h21(cell) * 6.28);
	float glow = (1.0 - lump * 0.7) * breathe * clamp(heat * 1.8, 0.0, 1.2);
	vec3 c = mix(vec3(0.04, 0.035, 0.03), col * 1.8, glow);
	ALBEDO = c;
}
"""

## Heat haze: the scene behind it ripples upward, more the hotter the fire.
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void fragment(){
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.3, 1.0 - UV.y) * smoothstep(1.0, 0.6, 1.0 - UV.y);
	vec2 w = vec2(vn(UV * vec2(6.0, 4.0) + vec2(0.0, -TIME * 2.2)), vn(UV * vec2(5.0, 3.0) + vec2(3.0, -TIME * 1.7))) - 0.5;
	vec2 suv = SCREEN_UV + w * 0.012 * strength * edge;
	ALBEDO = textureLod(screen_tex, suv, 0.0).rgb;
	ALPHA = edge * strength;
}
"""

## Steel in the fire: the edges and thin parts glow first, in the colour of the heat.
const HOT_METAL_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never;
uniform float glow = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.4, 0.1);
void fragment(){
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float g = glow * (0.55 + rim * 0.8) * (0.85 + 0.15 * sin(TIME * 3.0));
	ALBEDO = col * g * 1.8;
	ALPHA = clamp(g, 0.0, 1.0);
}
"""
