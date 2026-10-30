class_name Hero
extends Node3D
## The player character: stats, equipment visuals, movement, combat, skills.

signal died
signal leveled(lvl: int)
signal stats_changed

var game: Node
var rig: Node3D
var J: Dictionary
var hlook := {"skin": Color(0.8, 0.62, 0.5), "cloth": Color(0.36, 0.07, 0.05), "cloth2": Color(0.2, 0.14, 0.1),
	"head": "human", "hair": Color(0.25, 0.15, 0.08), "beard": Color(0.25, 0.15, 0.08), "cape": Color(0.32, 0.05, 0.04)}

# --- persistent state
var level := 1
var xp := 0
var str_ := 20
var dex := 15
var vit := 25
var ene := 10
var stat_points := 0
var talents := {}            # talent id -> ranks taken (Talents); a point per level from level 2
var gold := 120
var equipment := {}
var inventory: Array = []
var belt: Array = [null, null, null, null]
var stash: Array = []

# --- derived
var tfx := {}                # what the talents taken add up to (Talents.sum); read with talent()
var max_life := 100.0
var max_mana := 30.0
var life := 100.0
var mana := 30.0
var dmg_min := 1
var dmg_max := 3
var fire_dmg := 0
var armor := 0
var block_chance := 0.0
var aspd := 1.0
var dmg_stack: DamageStack     # the stacking red damage number over the head
var ls := 0.0
var res := 0
var frw := 0
var regen := 0.0
var mf := 0
var gf := 0
var stats := {}

# --- runtime
var radius := 0.45
var target = null            # Enemy, Inter, GroundItem or null
var move_goal := Vector3.ZERO
var path := PackedVector3Array()
var moving := false
var direct_dir := Vector3.ZERO
var phase := 0.0
var move_amt := 0.0
var atk_t := -1.0
var atk_dur := 0.6
var atk_style := "over"
var atk_skill := ""
var atk_aim := Vector3.ZERO
var impact_done := false
var blocking := false
var block_amt := 0.0
var block_flash := 0.0
var hit_t := 0.0
var cls := "knight"          # "knight", "wraith", "demon" or "warlock" (Data.CLASSES)
var cds := {}
var spirits: Array = []      # Wraith's Spectral Host: [{node, phase, state, t, target, from}]
var spirit_t := 0.0
var minions: Array = []      # Demon's summoned demons (DemonMinion), oldest first
var phased := false          # Demon: walking in the Underworld, unseen and untouchable
var phase_t := 0.0
var drain_t := -1.0          # Warlock: Drain Life channel time (-1 = not channelling)
var drain_tick := 0.0
var drain_main = null        # the enemy the beam is latched onto
var drain_beams := {}        # enemy instance id -> WarlockFx.Beam
var drain_light: OmniLight3D = null
var drain_sigil: Node3D = null    # the fel sigil turning under the Warlock while channelling
var drain_hum: AudioStreamPlayer = null
var drain_lit := {}          # enemy instance id -> enemy shown with the green drain rim
var drain_heal := 0.0        # healing gathered since the last "+N" number
var drain_heal_t := 0.0
var covenant_t := 0.0        # Warlock: Fel Covenant (Drain Life forks further and heals double)
var bolts: Array = []        # Warlock's Blight Bolts in flight: [{node, dir, left}]
## The archer (archer.gd): arrows in flight, volleys raining down, snares lying in wait, the spirit beasts
var arrows: Array = []
var volleys: Array = []
var snares: Array = []
var beasts: Array = []
var blights: Array = []      # plague pools on the ground: [{node, pos, t, tick}]
var buff_t := 0.0
var heal_pool := 0.0
var mana_pool := 0.0
var dead := false
var dead_t := 0.0
var charge_t := -1.0
var charge_dir := Vector3.ZERO
var charge_hit := {}
var anim_time := 0.0
var shield_rest := Transform3D()
var trail: MeshInstance3D
var trail_pts: Array = []
var trail_col := Color(1, 1, 1)
var aura: GPUParticles3D
var light: OmniLight3D
var breath: GPUParticles3D
var _breath_t := 1.0
var _last_step := 0
var weapon_node: Node3D = null
## Drawing / holstering (WeaponCarry, profile Data.WEAPON_PROFILES[cls]); the weapon rides in the hand
## or in storage, moving between them at the motion's grab point without popping.
var carry := WeaponCarry.new()
var _carry_in_hand := true
var shield_node: Node3D = null
var gear_nodes: Array = []
var combo := 0
var combo_t := 0.0
# right-click combo: three swipes (forehand, rising backhand, spinning finisher)
const SWIPES := ["swipe1", "swipe2", "swipe3"]
const SWIPE_DUR := {"swipe1": 0.56, "swipe2": 0.58, "swipe3": 0.9}
const SWIPE_LUNGE := {"swipe1": [0.22, 0.44, 0.5], "swipe2": [0.2, 0.46, 0.55], "swipe3": [0.18, 0.64, 0.5], "cleave": [0.2, 0.5, 1.9]}  # from, to, metres
var swipe_n := 0
var swipe_idle := 0.0
var swipe_q := false
var swipe_aim := Vector3.ZERO
var swipe_keep := false
const SLAM_RANGE := 6.0
const SLAM_REACH := 1.25
var slam_leap := 0.0       # Holy Slam: how far this leap carries him, and how far ahead the blade lands
var slam_reach := SLAM_REACH
var atk_target = null
var stamina := 100.0
var max_stamina := 100.0
var stamina_rest := 0.0
var sprint := false
## The knight can keep a helm equipped (its stats) but not draw it (inventory toggle).
var show_helm := true
var running := false
var exhausted := false
# co-op: a puppet is a partner's knight, driven by the poses their game sends
var puppet := false
var peer_id := 0
var ally_color := Color.WHITE
var last_pose := {}
var net_has := false
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_phase_rate := 0.0
var net_st := {}
var net_buff := false
var _net_last_t := 0.0

func _init() -> void:
	inventory.resize(40)
	stash.resize(60)
	for s in Data.SKILLS:
		cds[s["id"]] = 0.0
	binds = default_binds()

func is_wraith() -> bool:
	return cls == "wraith"

func is_demon() -> bool:
	return cls == "demon"

func is_warlock() -> bool:
	return cls == "warlock"

func is_archer() -> bool:
	return cls == "archer"

## The archer with a bow in his hands: his attack shoots instead of swinging.
func has_bow() -> bool:
	var w = equipment.get("weapon") if equipment is Dictionary else null
	return is_archer() and w != null and Data.BASES[w["base"]]["kind"] in ["bow", "longbow"]

func skill_list() -> Array:
	return Data.skills_for(cls)

# ---------------------------------------------------------------- skill bindings
## The bar holds a skill on each mouse button; any skill can also go on a hotkey. Saved per character.
const BIND_KEYS := ["Q", "E", "R", "F", "G", "V"]
const BIND_SLOTS := ["lmb", "rmb", "Q", "E", "R", "F", "G", "V"]
var binds := {}

func default_binds() -> Dictionary:
	var b := {"lmb": "attack", "rmb": "block"}
	var own := skill_list()
	for i in BIND_KEYS.size():
		b[BIND_KEYS[i]] = own[i]["id"] if i < own.size() else ""
	return b

## Put a skill on a slot. A skill sits on one hotkey at most, so binding it again moves it.
func bind(slot: String, id: String) -> void:
	if not BIND_SLOTS.has(slot):
		return
	if id != "" and BIND_KEYS.has(slot):
		for k in BIND_KEYS:
			if binds.get(k, "") == id:
				binds[k] = ""
	binds[slot] = id
	if game and game.ui and not puppet:
		game.ui.refresh_skill_slots()

## Keep only skills this class knows; fill anything missing from the defaults.
func _check_binds() -> void:
	var known := {}
	for s in Data.skills_known(cls):
		known[s["id"]] = true
	var d := default_binds()
	for slot in BIND_SLOTS:
		var id: String = str(binds.get(slot, d[slot]))
		binds[slot] = id if (id == "" or known.has(id)) else d[slot]

func bound(slot: String) -> String:
	return str(binds.get(slot, ""))

# ---------------------------------------------------------------- talents (Talents, the window is N)
func talent(key: String) -> float:
	return float(tfx.get(key, 0.0))

## A point per level from level 2, less what is spent.
func free_talent_points() -> int:
	return maxi(0, level - 1 - Talents.spent(talents))

func learn_talent(id: String) -> bool:
	if not Talents.can_learn(cls, id, talents, free_talent_points()):
		return false
	talents[id] = int(talents.get(id, 0)) + 1
	_talents_changed()
	return true

func unlearn_talent(id: String) -> bool:
	if not Talents.can_unlearn(cls, id, talents):
		return false
	talents[id] = int(talents[id]) - 1
	if talents[id] <= 0:
		talents.erase(id)
	_talents_changed()
	return true

func reset_talents() -> void:
	talents = {}
	_talents_changed()

## Spend the free points along the class's suggested build.
func auto_talents() -> void:
	talents = Talents.auto_build(cls, free_talent_points(), talents)
	_talents_changed()

func _talents_changed() -> void:
	tfx = Talents.sum(cls, talents)
	recalc()
	if game and game.ui and not puppet:
		game.ui.refresh_skill_slots()     # mana costs on the bar

## Mana and cooldown after talents.
func skill_cost(id: String) -> float:
	return float(Data.skill_def(id).get("mana", 0)) * (1.0 - talent("cost:" + id) / 100.0)

func skill_cd(id: String) -> float:
	return float(Data.skill_def(id).get("cd", 0.0)) * (1.0 - talent("cd:" + id) / 100.0)

func _build_rig() -> void:
	if is_wraith():
		rig = Wraith.build(wraith_gear())
	elif is_demon():
		rig = Demon.build(demon_gear())
	elif is_warlock():
		rig = Warlock.build(warlock_gear())
	elif is_archer():
		rig = Archer.build_body()
	else:
		var body := _knight_body()
		if body == "mocap":
			rig = Knight.build_mocap()
		else:
			rig = Knight.build(Knight.default_gear()) if body == "" else Knight.build_meshy(body == "armored")
		rig.set_meta("gait", "knight")    # Anim: heavy armoured run, elbows out
	rig.set_meta("pers", "hero")
	add_child(rig)
	J = rig.get_meta("j")
	if breath != null and is_instance_valid(breath):
		breath.queue_free()
	breath = game.weather.make_breath()
	(J.get("at_head", J["head"]) as Node3D).add_child(breath)
	breath.position = Vector3(0, 0.02, -0.16)

## Which body the knight wears: the Meshy one in shirt and shorts while no armour is equipped
## ("plain"), the Meshy plate once it is ("armored"), or "" for the procedural armoured body
## (without the glb files).
func _knight_body() -> String:
	if cls != "knight":
		return ""
	if equipment.get("armor") == null:
		return "plain" if Knight.meshy_ok() else ""
	if Knight.mocap_ok():
		return "mocap"
	return "armored" if Knight.armored_ok() else ""

## Switch the character's class: new body, skills and spirit colours.
func set_class(c: String) -> void:
	if not Data.CLASSES.has(c):
		c = "knight"
	if c == cls and rig != null:
		return
	var changed := c != cls
	cls = c
	if changed or binds.is_empty():
		binds = default_binds()
	if changed:
		talents = {}
		tfx = {}
	_clear_spirits()
	dismiss_minions()
	end_phase(false)
	_clear_warlock()
	Archer.clear(self)
	if rig != null:
		rig.queue_free()
		rig = null
	weapon_node = null
	shield_node = null
	gear_nodes.clear()
	_build_rig()
	_tint_aura()
	refresh_gear()
	if not puppet and game and game.ui:
		game.ui.refresh_skill_slots()

func _tint_aura() -> void:
	if aura == null:
		return
	var g2 := Gradient.new()
	if is_wraith():
		g2.set_color(0, Color(0.45, 0.9, 1.0, 0.9))
		g2.set_color(1, Color(0.55, 0.35, 1.0, 0.0))
	elif is_demon():
		g2.set_color(0, Color(1.0, 0.3, 0.1, 0.9))
		g2.set_color(1, Color(0.7, 0.02, 0.05, 0.0))
	elif is_warlock():
		g2.set_color(0, Color(0.5, 1.0, 0.35, 0.9))
		g2.set_color(1, Color(0.05, 0.4, 0.05, 0.0))
	else:
		g2.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
		g2.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g2
	(aura.process_material as ParticleProcessMaterial).color_ramp = gt

func demon_gear() -> Dictionary:
	var g := Demon.default_gear()
	var a = equipment.get("armor")
	if a != null:
		var p := Models.palette(a)
		if int(a.get("rarity", 0)) == 3 and p["glow"] != null:
			g["edge"] = p["glow"]
		elif int(a.get("ench", 0)) >= 5:
			g["edge"] = Color(1.0, 0.62, 0.15)
	return g

func warlock_gear() -> Dictionary:
	var g := Warlock.default_gear()
	var a = equipment.get("armor") if equipment is Dictionary else null
	if a != null:
		var p := Models.palette(a)
		if int(a.get("rarity", 0)) == 3 and p["glow"] != null:
			g["fel"] = p["glow"]
		elif int(a.get("ench", 0)) >= 5:
			g["fel"] = Color(0.7, 1.0, 0.2)
	return g

func wraith_gear() -> Dictionary:
	var g := Wraith.default_gear()
	var a = equipment.get("armor") if equipment is Dictionary else null
	if a != null:
		var p := Models.palette(a)
		if int(a.get("rarity", 0)) == 3 and p["glow"] != null:
			g["spirit"] = p["glow"]
			g["trim"] = (p["glow"] as Color).lightened(0.2)
		elif int(a.get("ench", 0)) >= 5:
			g["spirit"] = Color(0.55, 0.45, 1.0)
	return g

func setup(g: Node) -> void:
	game = g
	if not puppet:
		add_to_group("hero")
	_build_rig()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 0.9
	light.omni_range = 10.0
	light.omni_attenuation = 1.6
	light.position = Vector3(0, 3.2, 0.5)
	light.shadow_enabled = false
	add_child(light)
	trail = MeshInstance3D.new()
	trail.mesh = ImmediateMesh.new()
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = tm
	trail.top_level = true
	add_child(trail)
	aura = GPUParticles3D.new()
	aura.amount = 30
	aura.lifetime = 1.2
	aura.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.7
	pm.emission_ring_inner_radius = 0.5
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 10
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	var g2 := Gradient.new()
	g2.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	g2.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g2
	pm.color_ramp = gt
	aura.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	aura.draw_pass_1 = q
	add_child(aura)
	_tint_aura()

func new_character() -> void:
	var c: Dictionary = Data.CLASSES[cls]
	binds = default_binds()
	talents = {}
	tfx = {}
	level = 1
	xp = 0
	str_ = c["str"]
	dex = c["dex"]
	vit = c["vit"]
	ene = c["ene"]
	stat_points = 0
	gold = 120
	inventory = []
	inventory.resize(40)
	for k in cds.keys():
		cds[k] = 0.0
	buff_t = 0.0
	_clear_spirits()
	dismiss_minions()
	end_phase(false)
	_clear_warlock()
	equipment = {}
	for s in Items.EQUIP_SLOTS:
		equipment[s] = null
	equipment["weapon"] = Items.make(str(Data.CLASSES[cls].get("weapon", "hand_axe" if is_demon() else "short_sword")))
	if cls == "knight":
		equipment["shield"] = Items.make("buckler")
	equipment["armor"] = Items.make("quilted")
	belt = [Items.potion("hp_potion"), Items.potion("hp_potion"), Items.potion("mp_potion"), null]
	belt[0]["count"] = 4
	belt[1]["count"] = 4
	belt[2]["count"] = 3
	recalc()
	life = max_life
	mana = max_mana
	refresh_gear()

# ---------------------------------------------------------------- stats
func recalc() -> void:
	stats = {}
	var def_sum := 0
	var shield_block := 0
	for s in Items.EQUIP_SLOTS:
		var it = equipment.get(s)
		if it == null:
			continue
		var ss := Items.stat_sum(it)
		for k in ss.keys():
			stats[k] = stats.get(k, 0) + ss[k]
		def_sum += Items.defense_of(it)
		if s == "shield":
			shield_block = it.get("block", 0)
	for k in ["str", "dex", "vit", "res", "ls", "regen", "ias", "frw", "block", "mf"]:
		if tfx.has(k):
			stats[k] = stats.get(k, 0) + (tfx[k] if k == "regen" else int(tfx[k]))
	var st_total: int = str_ + stats.get("str", 0)
	var dx_total: int = dex + stats.get("dex", 0)
	var vt_total: int = vit + stats.get("vit", 0)
	max_life = (45.0 + vt_total * 3.0 + level * 4.0 + stats.get("life", 0)) * (1.0 + talent("life_pct") / 100.0)
	max_mana = (15.0 + (ene + talent("ene")) * 2.0 + level * 1.5 + stats.get("mana", 0)) * (1.0 + talent("mana_pct") / 100.0)
	max_stamina = 70.0 + vt_total * 0.6 + level * 2.0
	stamina = minf(stamina, max_stamina)
	var w = equipment.get("weapon")
	var wd: Array = Items.damage_of(w) if w != null else [1, 3]
	var k := 1.0 + st_total / 100.0
	dmg_min = maxi(1, int(wd[0] * k))
	dmg_max = maxi(dmg_min, int(wd[1] * k))
	fire_dmg = stats.get("fire", 0)
	var wspeed: float = Data.BASES[w["base"]].get("speed", 1.0) if w != null else 1.2
	aspd = wspeed * (1.0 + mini(stats.get("ias", 0), 120) / 100.0 + dx_total * 0.002)  # A2/A3 gear: speed capped
	armor = int((def_sum + dx_total / 4) * (1.0 + talent("armor_pct") / 100.0))
	block_chance = 0.0
	if equipment.get("shield") != null:
		block_chance = minf(60.0, shield_block + stats.get("block", 0) + dx_total * 0.1)
	ls = mini(stats.get("ls", 0), 25)  # life steal capped at 25%
	res = mini(75, stats.get("res", 0))
	frw = mini(stats.get("frw", 0), 100)  # run speed capped at double
	regen = 0.4 + stats.get("regen", 0)
	mf = stats.get("mf", 0)
	gf = stats.get("gf", 0)
	life = minf(life, max_life)
	mana = minf(mana, max_mana)
	stats_changed.emit()

func total_str() -> int: return str_ + stats.get("str", 0)
func total_dex() -> int: return dex + stats.get("dex", 0)
func total_vit() -> int: return vit + stats.get("vit", 0)

func add_xp(v: int) -> void:
	xp += v
	while xp >= Data.xp_for_level(level):
		xp -= Data.xp_for_level(level)
		level += 1
		stat_points += 5
		recalc()
		life = max_life
		mana = max_mana
		Fx.pillar(game.world.fx_root, global_position, Color(1.0, 0.85, 0.4))
		Sfx.play("levelup")
		leveled.emit(level)
	stats_changed.emit()

## Testing panel: jump straight to a level. Going up grants the usual 5 stat points per level.
func set_level(n: int) -> void:
	n = clampi(n, 1, 99)
	if n == level:
		return
	var up := n > level
	if up:
		stat_points += (n - level) * 5
	level = n
	xp = 0
	if Talents.spent(talents) > level - 1:
		talents = {}
	_talents_changed()
	life = max_life
	mana = max_mana
	if up and game.world:
		Fx.pillar(game.world.fx_root, global_position, Color(1.0, 0.85, 0.4))
		Sfx.play("levelup")
	leveled.emit(level)
	stats_changed.emit()

# ---------------------------------------------------------------- gear visuals
func refresh_gear() -> void:
	for n in gear_nodes:
		if is_instance_valid(n):
			n.queue_free()
	gear_nodes.clear()
	if cls == "knight" and rig != null and _knight_body() != (str(rig.get_meta("meshy")) if rig.has_meta("meshy") else ""):
		var yaw := rig.rotation.y
		rig.queue_free()
		rig = null
		_build_rig()
		rig.rotation.y = yaw
	weapon_node = null
	shield_node = null
	var w = equipment.get("weapon")
	if w != null:
		weapon_node = Models.item_model(w)
		_weapon_hand(J).add_child(weapon_node)
		# the new model starts in the hand: force _carry_weapon to place it (and the body's hilt) next frame
		carry.configure(cls)
		_carry_in_hand = not (carry.t >= float(carry.p["grab"]))
		gear_nodes.append(weapon_node)
		if w.get("rarity", 0) == 3 and Models.palette(w)["glow"] != null:
			var fl := Props.fire(weapon_node, Vector3(0, 0, -0.5), 0.35, Models.palette(w)["glow"], false, false, false)
			gear_nodes.append(fl)
	var s = equipment.get("shield")
	if s != null:
		shield_node = Models.item_model(s)
		(J["mount_l"] as Node3D).add_child(shield_node)
		shield_node.rotation_degrees = Vector3(0, 0, 0)
		shield_node.position = Vector3(-0.03, 0, 0)
		shield_rest = shield_node.transform
		gear_nodes.append(shield_node)
	var h = equipment.get("helm")
	# the crusader (the armoured body) always wears his own great helm: a helm item's stats count, its model isn't drawn
	if h != null and cls == "knight" and not ["armored", "mocap"].has(str(rig.get_meta("meshy", ""))):
		var hm := Models.item_model(h)
		(J.get("at_head", J["head"]) as Node3D).add_child(hm)
		Knight.fit_helm(hm, rig)
		gear_nodes.append(hm)
	if is_wraith():
		Wraith.rebuild_body(rig, wraith_gear())
	elif is_demon():
		Demon.rebuild_body(rig, demon_gear())
	elif is_warlock():
		Warlock.rebuild_body(rig, warlock_gear())
	elif not rig.has_meta("meshy"):
		Knight.rebuild_body(rig, knight_gear())
	var am = equipment.get("amulet")
	if am != null:
		var an := Models.amulet(Models.palette(am))
		if J.has("chest"):
			(J["chest"] as Node3D).add_child(an)
		else:
			(J["torso"] as Node3D).add_child(an)
			an.position = Vector3(0, 0.47, -0.15)
			an.rotation_degrees = Vector3(-75, 0, 0)
			an.scale = Vector3(1.2, 1.2, 1.2)
		gear_nodes.append(an)
	if not puppet and game and game.net and game.net.active:
		game.net.send_gear()

## Equipment plus the class, for co-op partners.
func net_gear() -> Dictionary:
	var g: Dictionary = equipment.duplicate()
	g["_cls"] = cls
	g["_helm"] = show_helm
	return g

## Describes the equipped armour so the skinned body can be rebuilt to match.
func knight_gear() -> Dictionary:
	var g := Knight.default_gear()
	var a = equipment.get("armor")
	if a != null:
		var p := Models.palette(a)
		g["armor"] = Data.BASES[a["base"]]["kind"]
		g["steel"] = p["metal"]
		g["trim"] = p["trim"] if int(a.get("rarity", 0)) > 0 else Color(0.78, 0.62, 0.32)
		g["glow"] = p["glow"]
		if int(a.get("ench", 0)) >= 5 and p["glow"] == null:
			g["glow"] = Color(0.4, 0.58, 1.0)
		if int(a.get("rarity", 0)) == 3:
			g["cloth"] = (p["metal"] as Color).darkened(0.2)
			g["cape"] = (p["metal"] as Color).darkened(0.45)
			g["emblem"] = p["trim"]
	var gl = equipment.get("gloves")
	if gl != null:
		g["gloves"] = Data.BASES[gl["base"]]["kind"]
	var bo = equipment.get("boots")
	if bo != null:
		g["boots"] = Data.BASES[bo["base"]]["kind"]
		if int(bo.get("rarity", 0)) == 3 and a == null:
			g["steel"] = Models.palette(bo)["metal"]
	g["belt"] = true
	g["coif"] = g["armor"] in ["chain", "plate", "ornate"]
	return g

## Where the weapon is this frame: in the hand once the draw passes its grab point, else in storage
## ("hilt": the body's own sheathed hilt shows and the weapon model hides; "back": on the back). When it
## changes hands it keeps its place in the world and eases into the new hold, so it never jumps.
func _carry_weapon(delta: float) -> void:
	if weapon_node == null or not is_instance_valid(weapon_node) or rig == null:
		return
	var in_hand := carry.t >= float(carry.p["grab"])
	var store: String = carry.p["store"]
	var J: Dictionary = rig.get_meta("j")
	if in_hand != _carry_in_hand:
		_carry_in_hand = in_hand
		var dest: Node3D = _weapon_hand(J) if in_hand else _weapon_store(J, store)
		if dest != null and weapon_node.get_parent() != dest:
			weapon_node.reparent(dest, true)
		_set_hilt(not in_hand and store == "hilt")
	# hidden in the scabbard; on the back it stays in view
	weapon_node.visible = in_hand or store != "hilt"
	# ease into the hold (identity in the hand; the back mount's own rest)
	var k := 1.0 - exp(-delta * 16.0)
	weapon_node.transform = weapon_node.transform.interpolate_with(Transform3D.IDENTITY, k)

## The hand that holds the weapon: the right, except a bow on a body that holds it in the left (the ranger),
## turned for the bow's kind (Archer.BOW_HOLD).
func _weapon_hand(J: Dictionary) -> Node3D:
	var w = equipment.get("weapon")
	if J.has("grip_bow") and w != null and has_bow():
		var g: Node3D = J["grip_bow"]
		var hold: Array = Archer.BOW_HOLD.get(Data.BASES[w["base"]]["kind"], Archer.BOW_HOLD["bow"])
		g.position = hold[0]
		g.rotation_degrees = hold[1]
		var at: Node3D = J["grip_bow_at"]
		at.position = hold[2]
		return at
	return J["grip_r"]

## The storage node on the rig for "back" (made on first use: across the back, hilt over the right
## shoulder); "hilt" has none (the weapon model just hides).
func _weapon_store(J: Dictionary, store: String) -> Node3D:
	if store != "back":
		return J["grip_r"]
	var torso: Node3D = J.get("at_torso", J["torso"])    # the mocap knight's real chest bone when it has one
	var m := torso.get_node_or_null("back_mount") as Node3D
	if m == null:
		m = Node3D.new()
		m.name = "back_mount"
		torso.add_child(m)
		m.position = Vector3(0.0, 0.32, 0.2)
		m.rotation = Vector3(deg_to_rad(-80.0), deg_to_rad(10.0), deg_to_rad(35.0))
	return m

## The crusader body's own sword hilt (its "Hilt" surface, see rig_crusader_knight.py) shows only while
## the sword is sheathed. Bodies without one are left alone.
func _set_hilt(show: bool) -> void:
	if rig == null:
		return
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat != null and mat.resource_name == "Hilt":
				(mi as MeshInstance3D).set_surface_override_material(si, null if show else _hidden_mat())

static var _hide_mat: StandardMaterial3D
static func _hidden_mat() -> StandardMaterial3D:
	if _hide_mat == null:
		_hide_mat = StandardMaterial3D.new()
		_hide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hide_mat.albedo_color = Color(0, 0, 0, 0)
		_hide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _hide_mat

# ---------------------------------------------------------------- commands
func cmd_move(p: Vector3, direct := false) -> void:
	if dead or charge_t >= 0.0:
		return
	end_drain()
	target = null
	_set_goal(p, direct)

# ---------------------------------------------------------------- aiming
## Keyboard actions (Space and the QERF skills) go where the hero is facing, for every class:
## run with WASD, press a key, and it fires ahead. A light assist bends the shot onto the enemy
## nearest that line, inside a cone that is wider up close. Mouse clicks still go where you
## click. Each skill says how it aims in Data.SKILLS: "facing" (with a "range"), "point" (the
## cursor; Shadow Step's destination) or "self" (centred on the hero, no turn).
const AIM_CONE_NEAR := 0.8    # radians either side of facing, for melee reach
const AIM_CONE_FAR := 0.42    # for ranged skills

func facing() -> Vector3:
	var f := -rig.global_transform.basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

## Where a facing-aimed action lands: the best enemy in the cone ahead, else straight ahead.
func aim_ahead(dist: float) -> Vector3:
	var f := facing()
	var cone := AIM_CONE_NEAR if dist < 4.0 else AIM_CONE_FAR
	var best = null
	var bs := INF
	for e in game.enemies_near(global_position, dist):
		var d: Vector3 = e.global_position - global_position
		d.y = 0
		var dl := d.length()
		var ang := f.angle_to(d / dl) if dl > 0.05 else 0.0
		if ang > cone:
			continue
		var score := dl * (1.0 + 2.5 * ang)
		if score < bs:
			bs = score
			best = e
	return best.global_position if best != null else global_position + f * dist

## The aim point for skill `id` given the cursor point (used only by "point" skills).
func skill_aim(id: String, cursor: Vector3) -> Vector3:
	for s in skill_list():
		if s["id"] == id:
			match String(s.get("aim", "facing")):
				"point": return cursor
				"self": return global_position + facing()
				_: return aim_ahead(float(s.get("range", 3.5)))
	return cursor

## Swing toward a point without needing a target (Space). Works while moving.
func free_attack(aim: Vector3) -> void:
	if not can_act():
		return
	if has_bow():
		Archer.shoot(self, aim, false)
		return
	atk_aim = aim
	atk_target = null
	_face(aim - global_position)
	_start_attack(["over", "back", "thrust"][combo % 3])
	combo += 1
	combo_t = 0.0

## Right-click: the next swipe of the combo toward the cursor. Pressing again late in a swipe queues
## the next one, which cuts off that swipe's recovery so the three flow together; the finisher
## (a full spin that hits all round) always plays out, and the chain starts over after a pause.
func swipe_attack(aim: Vector3, keep_target := false) -> void:
	if dead or charge_t >= 0.0 or drain_t >= 0.0:
		return
	if has_bow():
		Archer.shoot(self, aim, keep_target)
		return
	if atk_t >= 0.0:
		if atk_skill == "" and atk_style.begins_with("swipe") and atk_t / atk_dur > 0.3 and atk_style != "swipe3":
			swipe_q = true
			swipe_aim = aim
			swipe_keep = keep_target
		return
	_swipe(aim, keep_target)

## keep_target: a held left-click on a foe keeps him targeted (the hero follows him between swipes)
func _swipe(aim: Vector3, keep_target := false) -> void:
	swipe_q = false
	if not keep_target:
		target = null
	moving = false
	path = PackedVector3Array()
	atk_aim = aim
	atk_target = null
	_face(aim - global_position)
	var st: String = SWIPES[swipe_n % 3]
	swipe_n = (swipe_n + 1) % 3
	swipe_idle = 0.0
	_start_attack(st)

func _swipe_lunge(a0: float, a1: float) -> void:
	var L: Array = SWIPE_LUNGE[atk_style]
	var f0 := clampf((a0 - L[0]) / (L[1] - L[0]), 0.0, 1.0)
	var f1 := clampf((a1 - L[0]) / (L[1] - L[0]), 0.0, 1.0)
	var slam := atk_style == "cleave" and atk_skill == "cleave"
	var d: float = (smoothstep(0.0, 1.0, f1) - smoothstep(0.0, 1.0, f0)) * (slam_leap if slam else float(L[2]))
	if d <= 0.0:
		return
	var fwd := -rig.global_transform.basis.z
	if slam:
		# Holy Slam leaps to the spot aimed at, sliding round anything solid on the way
		fwd.y = 0
		global_position = game.world.move(global_position, fwd.normalized() * d)
		return
	if atk_style == "swipe3":
		fwd = (atk_aim - global_position) * Vector3(1, 0, 1)
		fwd = fwd.normalized() if fwd.length() > 0.01 else -rig.global_transform.basis.z
	fwd.y = 0
	# don't step through a foe that's already in reach
	for e in game.enemies_near(global_position, 2.0):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() - e.radius < 0.75 and fwd.dot(to.normalized()) > 0.5:
			return
	global_position = game.world.move(global_position, fwd.normalized() * d)

func _swipe_impact() -> void:
	var fwd := -rig.global_transform.basis.z
	var fin := atk_style == "swipe3"
	var rng := reach() + (1.0 if fin else 0.55)
	var arc := 181.0 if fin else 70.0
	var mult := 1.0 if atk_style == "swipe1" else (1.15 if atk_style == "swipe2" else 1.7)
	var any := false
	for e in game.enemies_near(global_position, rng + 1.5):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() - e.radius > rng:
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(arc)):
			_hit_enemy(e, mult, 0.9 if fin else 0.2)
			Fx.sparks(game.world.fx_root, e.global_position + Vector3(0, 1.1 * e.height, 0), trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5))
			any = true
	if fin:
		Fx.ring(game.world.fx_root, global_position + Vector3(0, 0.05, 0), rng, trail_col, 0.35)
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.2, 0), Color(0.7, 0.62, 0.5, 0.5), 22, 3.5, 0.2, 0.5, false, -2.0, 180.0, Vector3.UP)
		game.add_shake(0.28 if any else 0.1)
		if any:
			game.hitstop(0.06)

func _face_smooth(d: Vector3, delta: float) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), clampf(delta * 14.0, 0.0, 1.0))

func cmd_target(t) -> void:
	if dead or charge_t >= 0.0:
		return
	end_drain()
	target = t
	if is_instance_valid(t):
		_set_goal(t.global_position, false)

## WASD steering: the hero runs where it is heading and the heading swings round toward the keys at
## TURN_RATE, so W then W+A carves a curve instead of snapping to the diagonal. A sharp turn slows him a
## little; letting go of the keys forgets the heading.
const TURN_RATE := 9.0      # radians per second
var wasd_heading := Vector3.ZERO
## Where the head looks ahead of the body while turning (radians, + = left), for Anim.pose's "look".
var look := 0.0
var _look_want := 0.0
var _last_yaw := 0.0

func _steer(want: Vector3, delta: float) -> Vector3:
	if wasd_heading.length() < 0.1:
		# starting off: from the way he faces
		wasd_heading = -rig.global_transform.basis.z
		wasd_heading.y = 0
		wasd_heading = wasd_heading.normalized() if wasd_heading.length() > 0.1 else want
	var ang := wasd_heading.signed_angle_to(want, Vector3.UP)
	_look_want = clampf(ang * 0.8, -0.75, 0.75)
	wasd_heading = wasd_heading.rotated(Vector3.UP, clampf(ang, -TURN_RATE * delta, TURN_RATE * delta)).normalized()
	return wasd_heading * (0.7 + 0.3 * maxf(0.0, wasd_heading.dot(want)))

func cmd_wasd(dir: Vector3) -> void:
	if dead or charge_t >= 0.0:
		return
	direct_dir = dir
	if dir.length() < 0.1:
		wasd_heading = Vector3.ZERO
	if dir.length() > 0.1:
		end_drain()
		if not (is_instance_valid(target) and target is Enemy):
			target = null
		path = PackedVector3Array()
		moving = false

func _set_goal(p: Vector3, direct: bool) -> void:
	move_goal = p
	if direct:
		path = PackedVector3Array([p])
	else:
		path = game.world.find_path(global_position, p)
		if path.is_empty():
			path = PackedVector3Array([p])
	moving = true

## Could this skill be cast right now (level, cooldown, mana, not mid-skill)? Used for held buttons.
func skill_ready(id: String) -> bool:
	var sk := Data.skill_def(id)
	if sk.is_empty() or dead or charge_t >= 0.0 or drain_t >= 0.0:
		return false
	if atk_t >= 0.0 and atk_skill != "":
		return false
	return (level >= sk["lvl"] or game.test_allskills) and cds.get(id, 0.0) <= 0.0 and mana >= skill_cost(id)

func can_act() -> bool:
	return not dead and atk_t < 0.0 and charge_t < 0.0 and drain_t < 0.0

func use_skill(id: String, aim: Vector3) -> bool:
	if dead or charge_t >= 0.0:
		return false
	if atk_t >= 0.0 and atk_skill != "":
		return false
	var sk: Dictionary = {}
	for s in skill_list():
		if s["id"] == id:
			sk = s
	if sk.is_empty() or (level < sk["lvl"] and not game.test_allskills):
		game.ui.message("Requires level %d" % sk.get("lvl", 1), Color(1, 0.4, 0.3))
		return false
	if cds[id] > 0.0:
		game.ui.message("%s is recharging" % sk["name"], Color(0.8, 0.8, 0.8))
		return false
	if mana < skill_cost(id):
		game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
		Sfx.play("deny")
		return false
	var foe = null
	if id == "drain":
		foe = _drain_pick(aim)
		if foe == null:
			game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
			return false
	# cancel a basic swing (or a Drain Life channel) so the skill fires right away
	end_drain()
	atk_t = -1.0
	impact_done = true
	mana -= skill_cost(id)
	cds[id] = skill_cd(id)
	atk_aim = aim
	_face(aim - global_position)
	match id:
		"cleave":
			# Holy Slam lands on the cursor (up to SLAM_RANGE away): he leaps far enough that the
			# blade, which strikes about SLAM_REACH in front of him, comes down right there
			var to := (aim - global_position) * Vector3(1, 0, 1)
			var dist := minf(to.length(), SLAM_RANGE)
			slam_reach = minf(dist, SLAM_REACH)
			slam_leap = dist - slam_reach
			_start_attack("cleave", "cleave")
		"nova":
			_start_attack("cast", "nova")
			atk_dur = 0.55 * Data.attack_pace(cls)
		"charge":
			var d := aim - global_position
			d.y = 0
			charge_dir = d.normalized() if d.length() > 0.1 else -rig.global_transform.basis.z
			charge_t = 0.0
			charge_hit = {}
			Sfx.play("charge_dash", -2.0)
			path = PackedVector3Array()
			moving = false
		"cry":
			_start_attack("cast", "cry")
			atk_dur = 0.6 * Data.attack_pace(cls)
		"reap":
			_start_attack("side", "reap")
		"wail":
			_start_attack("cast", "wail")
			atk_dur = 0.5 * Data.attack_pace(cls)
		"shade":
			_shadow_step(aim)
		"host":
			_start_attack("cast", "host")
			atk_dur = 0.65 * Data.attack_pace(cls)
		"hellclaw":
			_start_attack("side", "hellclaw")
		"summon":
			_start_attack("cast", "summon")
			atk_dur = 0.55 * Data.attack_pace(cls)
		"phase":
			_phase_start()
		"pact":
			life = maxf(1.0, life - max_life * maxf(0.05, 0.2 - talent("pact_cost") / 100.0))
			_start_attack("cast", "pact")
			atk_dur = 0.6 * Data.attack_pace(cls)
		"drain":
			_drain_start(foe)
		"blight":
			_start_attack("cast", "blight")
			atk_dur = 0.45 * Data.attack_pace(cls)
		"shackles":
			_start_attack("cast", "shackles")
			atk_dur = 0.5 * Data.attack_pace(cls)
		"covenant":
			_start_attack("cast", "covenant")
			atk_dur = 0.6 * Data.attack_pace(cls)
		"pierce", "volley", "snare", "beast":
			Archer.cast(self, id, aim)
	return true

func drink(slot: int) -> void:
	if dead or slot < 0 or slot > 3 or belt[slot] == null:
		return
	var it: Dictionary = belt[slot]
	var b: Dictionary = Data.BASES[it["base"]]
	if b.has("heal"):
		heal_pool += b["heal"] * (1.0 + level * 0.06)
	if b.has("mana"):
		mana_pool += b["mana"] * (1.0 + level * 0.05)
	if b.has("rejuv"):
		life = minf(max_life, life + max_life * b["rejuv"])
		mana = minf(max_mana, mana + max_mana * b["rejuv"])
	it["count"] = int(it.get("count", 1)) - 1
	if it["count"] <= 0:
		belt[slot] = null
	Sfx.play("potion")
	Fx.burst(game.world.fx_root, global_position + Vector3(0, 1.2, 0), b["color"], 14, 1.5, 0.12, 0.8, true, 1.0)
	stats_changed.emit()

func _start_attack(style: String, skill := "") -> void:
	atk_style = style
	atk_skill = skill
	atk_t = 0.0
	atk_dur = 0.62 / aspd
	if SWIPE_DUR.has(style) and skill == "":
		atk_dur = SWIPE_DUR[style] / aspd
	if skill == "reap" or skill == "hellclaw":
		atk_dur = 0.7 / aspd
	elif skill == "cleave":
		atk_dur = 0.95 / aspd      # Holy Slam: crouch, leap, slam, hold the blow, rise
	atk_dur *= Data.attack_pace(cls)     # every class's pace (Data.ATTACK_PACE)
	impact_done = false
	trail_pts.clear()
	trail_col = Color(1.0, 0.85, 0.5) if skill == "cleave" else Color(0.85, 0.9, 1.0)
	if is_archer():
		trail_col = Archer.HUNTER
	if is_wraith():
		trail_col = WraithFx.SPIRIT if skill != "reap" else WraithFx.PALE
	elif is_demon():
		trail_col = DemonFx.EMBER
	elif is_warlock():
		trail_col = Warlock.FEL
	var w = equipment.get("weapon")
	if w != null and w.get("rarity", 0) == 3 and Models.palette(w)["glow"] != null:
		trail_col = Models.palette(w)["glow"]
	_attack_sound(skill)

## The swing or wind-up as an attack starts. A cast spell's sound starts here so that its payoff
## (the crack of Holy Nova, the scream of the Wail) lands on the animation's impact frame (Sfx.play_synced);
## spells with no wind-up play their sound at the impact instead (_impact).
func _attack_sound(skill: String) -> void:
	# when this attack's impact frame comes (it scales with attack speed)
	var at := Anim.impact_at(atk_style) * atk_dur
	if atk_style == "bow":
		# the archer: the string's twang on the release (Volley's flight a little lower)
		Sfx.play_synced("bow", at, -3.0, 0.85 if skill == "volley" else (0.92 if skill == "pierce" else 1.0))
		return
	match skill:
		"cleave": Sfx.play_synced("cleave_swing", at, -2.0)
		"reap": Sfx.play_synced("reap_swing", at, -2.0)
		"hellclaw": Sfx.play_synced("hellclaw", at, -1.0)
		"nova":
			Sfx.play_synced("holy_nova", at, 0.0)
			Sfx.duck(-8.0, 1.0)
		"wail":
			Sfx.play_synced("wail", at, 0.0)
			Sfx.duck(-8.0, 1.0)
		"blight": Sfx.play_synced("blight_cast", at, -2.0)
		"":
			# the whoosh peaks just before the blade lands
			if atk_style == "swipe3":
				Sfx.play_synced(_swing_sound(), at - 0.04, -2.0, 0.72)    # the finisher's spin: a long low whoosh
			elif atk_style != "cast":
				Sfx.play_synced(_swing_sound(), at - 0.04, -3.0, 1.12 if atk_style == "swipe2" else 1.0)
		_:
			pass

## A light whoosh for blades and fists, a heavier one for axes, maces, hammers and the like.
func _swing_sound() -> String:
	var w = equipment.get("weapon")
	if w == null:
		return "swing_light"
	var kind: String = Data.BASES[w["base"]].get("kind", "sword")
	return "swing_heavy" if kind in ["axe", "mace", "hammer", "club", "star"] else "swing_light"

## Hurt and death voices per body: the knight, the gnome (higher), the wraith (a hiss), the demon (a growl).
func _voice(what: String) -> String:
	if is_warlock():
		return what + "_gnome"
	if is_wraith():
		return what + "_wraith"
	if is_demon():
		return what + "_demon"
	return what + "_knight"

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = atan2(-d.x, -d.z)

func reach() -> float:
	return Archer.RANGE if has_bow() else 1.7

# ---------------------------------------------------------------- damage
func roll_damage(mult: float = 1.0) -> Dictionary:
	var d := randf_range(dmg_min, dmg_max + 1) * mult * buff_mult()
	var crit := randf() < 0.05 + total_dex() * 0.0015 + talent("crit") / 100.0
	if crit:
		d *= 2.0 + talent("crit_dmg") / 100.0
	return {"phys": d, "fire": fire_dmg * mult, "crit": crit}

## The battle buffs (Battle Cry, Spectral Host, Blood Pact, Fel Covenant): +40% damage, more with talents.
func buff_mult() -> float:
	return 1.4 + talent("buff_pow") / 100.0 if buff_t > 0.0 else 1.0

## Talent damage for a skill ("attack" is the weapon attack): all-damage plus that skill's own.
## The red number over the head: hits close together stack into one running total (DamageStack).
func show_damage(dmg: float) -> void:
	if dmg_stack == null or not is_instance_valid(dmg_stack):
		dmg_stack = DamageStack.new()
		add_child(dmg_stack)
	dmg_stack.add(dmg)

func dmg_mult(id: String) -> float:
	return (1.0 + (talent("dmg") + talent("dmg:" + id)) / 100.0) * pace_mult(id)

## Attacks are slower by the class's pace (Data.ATTACK_PACE); the ones whose rate the swing itself sets
## (the basic attack, skills with no cooldown) hit that much harder, so their damage per second stays put.
## Skills on a cooldown fire just as often, and channels ("channel" in Data.SKILLS) tick on their own clock, so they keep their damage.
func pace_mult(id: String) -> float:
	if id == "attack" or (skill_cd(id) <= 0.0 and not Data.skill_def(id).get("channel", false)):
		return Data.attack_pace(cls)
	return 1.0

## src: the skill doing the hitting (talent bonuses); by default the attack in progress.
func _hit_enemy(e, mult: float, knock: float = 0.0, src := "") -> void:
	if not is_instance_valid(e) or e.dead:
		return
	if src == "":
		src = atk_skill if atk_skill != "" else "attack"
	var r := roll_damage(mult * dmg_mult(src))
	var dealt: float = e.take_damage(r["phys"], r["fire"], global_position, knock, r["crit"])
	if ls > 0.0:
		life = minf(max_life, life + dealt * ls / 100.0)
	if r["crit"]:
		game.hitstop(0.05)
	game.add_shake(0.15 if not r["crit"] else 0.3)

func take_hit(dmg: float, from: Vector3, kind: String = "melee", element: String = "phys") -> void:
	if dead:
		return
	if puppet:
		if game.net.is_host:
			game.net.hit_player(peer_id, dmg, from, kind, element)
		return
	if game.test_immortal or phased:
		return
	var to_src := from - global_position
	to_src.y = 0
	var fwd := -rig.global_transform.basis.z
	var facing := fwd.dot(to_src.normalized()) > cos(deg_to_rad(80.0))
	var has_shield: bool = equipment.get("shield") != null
	var shield_pos := global_position + Vector3(0, 1.2, 0) + fwd * 0.5
	if block_amt > 0.5 and facing:
		var reduce := maxf(0.05, 0.2 - talent("block_dr") / 100.0)     # Block: 80% less damage from the front
		if kind == "proj" and has_shield:
			reduce = 0.0
		dmg *= reduce
		block_flash = 0.25
		hit_t = 0.35
		Sfx.play("block", 0.0, randf_range(0.9, 1.1))
		Fx.sparks(game.world.fx_root, shield_pos, Color(1.0, 0.85, 0.5))
		game.add_shake(0.12)
		if dmg <= 0.5:
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.2, 0), "Blocked", Color(0.8, 0.85, 1.0))
			return
	elif has_shield and facing and randf() * 100.0 < block_chance:
		block_flash = 0.35
		Sfx.play("block", 0.0, randf_range(0.95, 1.15))
		Fx.sparks(game.world.fx_root, shield_pos, Color(1.0, 0.85, 0.5))
		Fx.number(game.world.fx_root, global_position + Vector3(0, 2.2, 0), "Block", Color(0.8, 0.85, 1.0))
		return
	if element == "phys":
		var a := float(armor) * (1.4 if buff_t > 0.0 else 1.0)
		dmg *= 120.0 / (120.0 + a)
	else:
		dmg *= 1.0 - res / 100.0
	dmg = maxf(1.0, dmg)
	life -= dmg
	hit_t = 1.0
	# a plain thud, no voice: an "oof" on every hit was too much
	Sfx.play("hero_hit", -3.0, randf_range(0.9, 1.1))
	Fx.blood(game.world.fx_root, global_position + Vector3(0, 1.2, 0), Color(0.6, 0.02, 0.02))
	show_damage(dmg)
	game.add_shake(0.2)
	game.ui.flash_damage()
	if life <= 0.0:
		life = 0.0
		dead = true
		end_phase(false)
		dismiss_minions()
		end_drain()
		dead_t = 0.0
		atk_t = -1.0
		Sfx.play(_voice("death"), -2.0)
		died.emit()
	stats_changed.emit()

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	if game == null or game.world == null or game._busy:
		return
	anim_time += delta
	if puppet:
		_puppet_process(delta)
		return
	for k in cds.keys():
		cds[k] = maxf(0.0, cds[k] - delta)
	buff_t = maxf(0.0, buff_t - delta)
	covenant_t = maxf(0.0, covenant_t - delta)
	_update_spirits(delta)
	_update_bolts(delta)
	Archer.update(self, delta)
	_update_blights(delta)
	if phased:
		phase_t -= delta
		if phase_t <= 0.0:
			end_phase(true)
	aura.emitting = buff_t > 0.0
	hit_t = maxf(0.0, hit_t - delta * 4.0)
	block_flash = maxf(0.0, block_flash - delta)
	if atk_t < 0.0:
		combo_t += delta
		if combo_t > 0.9:
			combo = 0
		swipe_idle += delta
		if swipe_idle > 0.75:
			swipe_n = 0
			swipe_q = false
	if dead:
		dead_t += delta
		var f := clampf(dead_t / 0.7, 0.0, 1.0)
		var fall := clampf((dead_t - 0.35) / 0.6, 0.0, 1.0)
		rig.rotation.x = fall * fall * 1.42
		rig.position.y = -fall * 0.12
		Anim.pose(rig, {"time": anim_time, "dead": f, "hit": (1.0 - f) * 0.5})
		_update_trail(false)
		return
	# regen & potions
	if heal_pool > 0.0:
		var h := minf(heal_pool, delta * 30.0 * (1.0 + level * 0.05))
		heal_pool -= h
		life = minf(max_life, life + h)
	if mana_pool > 0.0:
		var m := minf(mana_pool, delta * 20.0)
		mana_pool -= m
		mana = minf(max_mana, mana + m)
	life = minf(max_life, life + regen * delta)
	mana = minf(max_mana, mana + (1.0 + ene * 0.06) * delta)

	var want_block := blocking and atk_t < 0.0 and charge_t < 0.0
	block_amt = move_toward(block_amt, 1.0 if (want_block or block_flash > 0.0) else 0.0, delta * 9.0)
	var vel := Vector3.ZERO
	var wants_move := direct_dir.length() > 0.1 or (moving and not path.is_empty())
	# stamina: sprint drains it, resting refills it; running dry leaves you winded
	running = sprint and wants_move and not exhausted and block_amt < 0.5 and charge_t < 0.0
	if running:
		stamina = maxf(0.0, stamina - delta * 14.0)
		stamina_rest = 0.0
		if stamina <= 0.0:
			exhausted = true
			game.ui.message("Out of stamina", Color(1.0, 0.8, 0.3))
	else:
		stamina_rest += delta
		if stamina_rest > 0.6:
			stamina = minf(max_stamina, stamina + delta * (16.0 if not wants_move else 9.0))
	if game.test_stamina:
		stamina = max_stamina
		exhausted = false
	if exhausted and stamina >= max_stamina * 0.3:
		exhausted = false
	var speed := 4.8 * (1.0 + frw / 100.0)
	if running:
		speed *= 1.6
	if phased:
		speed *= 1.4
	if block_amt > 0.5:
		speed *= 0.42
	if atk_t >= 0.0:
		speed *= 0.72
	if game.test_fast:
		speed *= game.TEST_FAST

	if charge_t >= 0.0:
		_update_charge(delta)
	else:
		if atk_t >= 0.0:
			_update_attack(delta)
		if drain_t >= 0.0:
			_update_drain(delta)
		# pursue target (an attack already in progress keeps its rhythm)
		if target != null and (not is_instance_valid(target) or target.is_queued_for_deletion()):
			target = null
			moving = false
		if target != null:
			if not is_instance_valid(target) or (target is Enemy and target.dead):
				target = null
				moving = false
			else:
				var tp: Vector3 = target.global_position
				var d := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
				var need := 1.0
				if target is Enemy:
					need = reach() + target.radius
				elif target is Inter:
					need = target.radius
				elif target is GroundItem:
					need = 1.2
				if d <= need:
					if direct_dir.length() < 0.1:
						moving = false
						path = PackedVector3Array()
					if target is Enemy:
						# left-click on a foe: the sword combo; held, it keeps chaining at him
						if atk_t < 0.0 or game.lmb_held:
							swipe_attack(tp, game.lmb_held)
							if atk_t >= 0.0 and not game.lmb_held:
								target = null
					elif atk_t < 0.0:
						var t = target
						target = null
						game.on_reach_target(t)
				elif direct_dir.length() < 0.1 and (path.is_empty() or move_goal.distance_to(tp) > 1.5):
					_set_goal(tp, false)
		if direct_dir.length() > 0.1:
			vel = _steer(direct_dir.normalized(), delta) * speed
		elif moving and not path.is_empty():
			var nxt := path[0]
			var dv := Vector3(nxt.x - global_position.x, 0, nxt.z - global_position.z)
			# a waypoint within this frame's step is reached (at super speed he'd overshoot and dither)
			if dv.length() < maxf(0.25, speed * delta):
				path.remove_at(0)
				if path.is_empty():
					moving = false
			else:
				vel = dv.normalized() * speed
	var stride := 1.3 if running else 1.0
	if vel.length() > 0.01:
		var np: Vector3 = game.world.move(global_position, vel * delta)
		var moved := (np - global_position)
		moved.y = 0
		global_position = np
		if moved.length() < vel.length() * delta * 0.2 and moving:
			moving = false
			path = PackedVector3Array()
		if atk_t < 0.0 and charge_t < 0.0:
			_face(vel)
		elif atk_t >= 0.0:
			# keep facing the foe while stepping
			if is_instance_valid(target) and target is Enemy:
				_face_smooth(target.global_position - global_position, delta)
			else:
				_face_smooth(atk_aim - global_position, delta)
		move_amt = move_toward(move_amt, stride, delta * 6.0)
		# super speed glides: the legs only go a little faster
		var anim_v: float = vel.length() * (1.6 / game.TEST_FAST if game.test_fast else 1.0)
		phase += delta * anim_v * 2.9 / maxf(move_amt, 0.6) * (float(rig.get_meta("stride")) if rig.has_meta("stride") else 1.0)
		_snow_step()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
	if charge_t < 0.0:
		global_position.y = game.world.height_at(global_position.x, global_position.z)

	# the head turns into a turn: toward the keys while steering, or with how fast he is swinging round
	var yaw_rate := wrapf(rig.rotation.y - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = rig.rotation.y
	if direct_dir.length() < 0.1:
		_look_want = 0.0
	var lw := clampf(_look_want + yaw_rate * 0.1, -0.75, 0.75) if move_amt > 0.2 and atk_t < 0.0 else 0.0
	# quick to look into a turn, slow to come back to straight ahead
	look = lerpf(look, lw, clampf(delta * (16.0 if absf(lw) > absf(look) else 3.5), 0.0, 1.0))
	var st := {"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": atk_style, "block": block_amt if charge_t < 0.0 else 1.0, "hit": hit_t * (0.3 if block_flash > 0.0 else 1.0), "look": look}
	if charge_t >= 0.0:
		st["atk"] = 0.45
		st["style"] = "thrust"
		st["move"] = 1.0
	elif drain_t >= 0.0:
		# both hands thrust out, holding the beam
		st["atk"] = 0.6
		st["style"] = "cast"
	if not puppet:
		carry.update(self, delta)
		st.merge(carry.anim_state(), true)
		_carry_weapon(delta)
	Anim.pose(rig, st)
	if is_archer():
		Archer.pose_bow(self, st)
	last_pose = st
	_hover()
	_draw_drain()
	_breathe(delta)
	_apply_shield_pose()
	_update_trail(atk_t >= 0.0 or charge_t >= 0.0)

## The Wraith floats a hand's breadth off the ground, bobbing slowly and leaning into motion.
func _hover() -> void:
	if is_demon():
		Demon.animate(rig, anim_time, move_amt)
		return
	if is_warlock():
		Warlock.animate(rig, anim_time, move_amt, 1.0 if covenant_t > 0.0 or (puppet and net_buff) else 0.0,
			phase, float(last_pose.get("atk", -1.0)) < 0.0 and drain_t < 0.0)
		return
	if not is_wraith() or dead:
		return
	rig.position.y = 0.2 + sin(anim_time * 2.1) * 0.05
	rig.rotation.x = -move_amt * 0.12

# ---------------------------------------------------------------- winter
## A footprint each time a foot comes down in the snow.
func _snow_step() -> void:
	if not game.weather.snowing or is_wraith():
		return
	var st := int(floor(phase / PI))
	if st != _last_step:
		_last_step = st
		game.weather.footstep(game.world.fx_root, global_position, rig.rotation.y, 1.0 if st % 2 == 0 else -1.0)

## Frosty breath every couple of seconds (faster while sprinting).
func _breathe(delta: float) -> void:
	if not game.weather.snowing or dead or is_wraith():
		return
	_breath_t -= delta
	if _breath_t <= 0.0:
		_breath_t = randf_range(2.2, 3.0) * (0.55 if running or move_amt > 1.1 else 1.0)
		breath.restart()

# ---------------------------------------------------------------- co-op puppet
func apply_net_gear(gear: Dictionary) -> void:
	equipment = gear.duplicate(true)
	var c: String = str(equipment.get("_cls", "knight"))
	equipment.erase("_cls")
	show_helm = bool(equipment.get("_helm", true))
	equipment.erase("_helm")
	if c != cls:
		set_class(c)
	for s in Items.EQUIP_SLOTS:
		if not equipment.has(s):
			equipment[s] = null
	refresh_gear()

func apply_net_state(p: PackedFloat32Array) -> void:
	if p.size() < 15:
		return
	var np := Vector3(p[0], p[1], p[2])
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _net_last_t, 0.02, 0.3)
	if net_has and absf(p[4] - phase) < 6.0:
		net_phase_rate = (p[4] - phase) / dt
	else:
		phase = p[4]
	_net_last_t = now
	if not net_has or np.distance_to(global_position) > 6.0:
		global_position = np
	net_pos = np
	net_yaw = p[3]
	net_st = {"move": p[5], "atk": p[6], "style": Net.STYLES[clampi(int(p[7]), 0, Net.STYLES.size() - 1)], "block": p[8], "hit": p[9]}
	var was_dead := dead
	dead = p[10] > 0.5
	dead_t = p[11]
	life = p[12]
	max_life = maxf(p[13], 1.0)
	net_buff = p[14] > 0.5
	if was_dead and not dead:
		rig.rotation.x = 0.0
		rig.position.y = 0.0
	net_has = true

func _puppet_process(delta: float) -> void:
	visible = net_has
	if not net_has:
		return
	var k := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(net_pos, k)
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	aura.emitting = net_buff
	if dead:
		var f := clampf(dead_t / 0.7, 0.0, 1.0)
		var fall := clampf((dead_t - 0.35) / 0.6, 0.0, 1.0)
		rig.rotation.x = fall * fall * 1.42
		rig.position.y = -fall * 0.12
		Anim.pose(rig, {"time": anim_time, "dead": f, "hit": (1.0 - f) * 0.5})
		_update_trail(false)
		return
	phase += net_phase_rate * delta
	if move_amt > 0.15:
		_snow_step()
	_breathe(delta)
	var st := net_st.duplicate()
	st["time"] = anim_time
	st["phase"] = phase
	move_amt = st.get("move", 0.0)
	block_amt = st.get("block", 0.0)
	atk_t = 0.0 if st.get("atk", -1.0) >= 0.0 else -1.0
	Anim.pose(rig, st)
	if is_archer():
		Archer.pose_bow(self, st)
	_hover()
	_apply_shield_pose()
	_update_trail(atk_t >= 0.0)

func _apply_shield_pose() -> void:
	if shield_node == null or not is_instance_valid(shield_node):
		return
	shield_node.transform = shield_rest
	var b := clampf(block_amt, 0.0, 1.0)
	var run := Anim.run_factor(move_amt) * (0.0 if atk_t >= 0.0 else 1.0) * (1.0 - b)
	if b <= 0.001 and run <= 0.001:
		return
	if b > 0.001:
		var tgt := rig.global_transform * Transform3D(Basis(Vector3.UP, 0.25), Vector3(-0.12, 1.22, -0.48))
		shield_node.global_transform = shield_node.global_transform.interpolate_with(tgt, b)
	else:
		# carried forward and angled out while sprinting
		var bob := sin(phase * 2.0) * 0.025
		var tgt2 := rig.global_transform * Transform3D(Basis(Vector3.UP, 0.55) * Basis(Vector3.RIGHT, -0.15), Vector3(-0.2, 1.2 + bob, -0.36))
		shield_node.global_transform = shield_node.global_transform.interpolate_with(tgt2, run * 0.8)

func _update_attack(delta: float) -> void:
	var a0 := atk_t / atk_dur
	atk_t += delta
	var a := atk_t / atk_dur
	var swipe := atk_skill == "" and SWIPE_LUNGE.has(atk_style)
	if swipe or (atk_skill == "cleave" and atk_style == "cleave"):
		_swipe_lunge(a0, a)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact()
	if swipe and swipe_q and a >= 0.68:
		atk_t = -1.0
		_swipe(swipe_aim, swipe_keep)
		return
	if atk_t >= atk_dur:
		atk_t = -1.0
		atk_skill = ""
		if swipe and atk_style == "swipe3":
			swipe_n = 0

func _impact() -> void:
	var fwd := -rig.global_transform.basis.z
	if Archer.impact(self):
		return
	match atk_skill:
		"":
			if atk_style.begins_with("swipe"):
				_swipe_impact()
				return
			var hit_any := false
			var tg = atk_target
			if is_instance_valid(tg) and tg is Enemy and not tg.dead:
				var d := Vector2(tg.global_position.x - global_position.x, tg.global_position.z - global_position.z).length()
				if d <= reach() + tg.radius + 0.7:
					_hit_enemy(tg, 1.0, 0.15)
					Fx.sparks(game.world.fx_root, tg.global_position + Vector3(0, 1.1 * tg.height, 0), Color(1.0, 0.75, 0.4))
					hit_any = true
			if not hit_any:
				# free swing: strike the nearest foe in a frontal arc
				var best = null
				var bd := 99.0
				for e in game.enemies_near(global_position, reach() + 1.6):
					var to: Vector3 = e.global_position - global_position
					to.y = 0
					var dd: float = to.length() - e.radius
					if dd <= reach() + 0.4 and (to.length() < 0.4 or fwd.dot(to.normalized()) > cos(deg_to_rad(60.0))) and dd < bd:
						bd = dd
						best = e
				if best != null:
					_hit_enemy(best, 1.0, 0.15)
					Fx.sparks(game.world.fx_root, best.global_position + Vector3(0, 1.1 * best.height, 0), Color(1.0, 0.75, 0.4))
					hit_any = true
		"cleave":
			# Holy Slam: the slam lands just ahead; everything around the blow is hit and thrown back
			var at := global_position + fwd * slam_reach
			at.y = game.world.height_at(at.x, at.z)
			var any := false
			for e in game.enemies_near(at, 3.6):
				var to: Vector3 = e.global_position - at
				to.y = 0
				if to.length() - e.radius <= 2.6:
					_hit_enemy(e, 1.6, 0.6)     # knocked back a little
					if is_instance_valid(e) and not e.dead:
						e.stun(1.0)
					Fx.sparks(game.world.fx_root, e.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.97, 0.9))
					any = true
			Fx.holy_slam(game.world.fx_root, at, 2.6)
			game.add_shake(0.5 if any else 0.32)
			game.hitstop(0.09 if any else 0.04)
		"nova":
			var nd := 18.0 + level * 5.0 + (dmg_min + dmg_max) * 0.4
			Fx.ring(game.world.fx_root, global_position, 7.0, Color(1.0, 0.75, 0.3), 0.5)
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 1, 0), Color(1.0, 0.8, 0.4), 50, 9.0, 0.15, 0.6, true, 0.0, 180.0)
			game.add_shake(0.35)
			nd *= buff_mult() * dmg_mult("nova")
			var burned := 0
			for e in game.enemies_near(global_position, 7.0):
				e.take_damage(0.0, nd, global_position, 1.2, false)
				burned += 1
			if talent("nova_heal") > 0.0 and burned > 0:
				life = minf(max_life, life + max_life * talent("nova_heal") / 100.0 * mini(burned, 5))
		"cry":
			buff_t = 12.0 + talent("buff_dur")
			if talent("cry_heal") > 0.0:
				life = minf(max_life, life + max_life * talent("cry_heal") / 100.0)
			Fx.ring(game.world.fx_root, global_position, 6.0, Color(1.0, 0.85, 0.4), 0.6)
			Fx.pillar(game.world.fx_root, global_position, Color(1.0, 0.8, 0.35), 0.8)
			Sfx.play("battle_cry")
			Sfx.duck(-8.0, 1.2)
			game.add_shake(0.3)
			for e in game.enemies_near(global_position, 6.0):
				e.stun(2.0)
		"reap":
			var yaw := rig.global_rotation.y
			WraithFx.reap(game.world.fx_root, global_position, yaw, 3.3)
			var any := false
			var full := talent("reap_full") > 0.0
			if full:
				WraithFx.reap(game.world.fx_root, global_position, yaw + PI, 3.3)
			for e in game.enemies_near(global_position, 3.6):
				var to: Vector3 = e.global_position - global_position
				to.y = 0
				if full or to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(80.0)):
					_hit_enemy(e, 1.5, 0.6)
					any = true
					WraithFx.soul_wisp(game.world.fx_root, e.global_position + Vector3(0, 1.0 * e.height, 0), self, func():
						if not dead:
							Sfx.play("soul_return", -8.0)
							life = minf(max_life, life + max_life * (0.025 + talent("reap_heal") / 100.0))
							stats_changed.emit())
			game.add_shake(0.12)
		"wail":
			var nd := (16.0 + level * 4.5 + (dmg_min + dmg_max) * 0.35) * buff_mult() * dmg_mult("wail")
			_wail(nd, 2.2)
			if talent("wail_echo") > 0.0:
				# Echo: the scream comes back a moment later
				get_tree().create_timer(0.6, false).timeout.connect(func():
					if is_instance_valid(self) and not dead and game.world:
						Sfx.play("wail", -6.0)
						_wail(nd * talent("wail_echo") / 100.0, 1.0))
		"host":
			buff_t = 12.0 + talent("buff_dur")
			WraithFx.summon(game.world.fx_root, global_position)
			Sfx.play("host_summon")
			Sfx.duck(-6.0, 1.0)
			game.add_shake(0.25)
			_clear_spirits()
			var count := 3 + int(talent("spirits"))
			for i in count:
				var n := WraithFx.spirit_node(game.world.fx_root)
				n.global_position = global_position + Vector3(0, 1.4, 0)
				spirits.append({"node": n, "phase": TAU * i / float(count), "state": "orbit", "t": 0.3 * i, "target": null, "from": Vector3.ZERO})
			spirit_t = buff_t
		"hellclaw":
			var yaw2 := rig.global_rotation.y
			var wide := talent("claw_wide") > 0.0     # Inferno: a metre further, much wider
			DemonFx.claw(game.world.fx_root, global_position, yaw2, 4.0 if wide else 3.0)
			var hit := false
			for e in game.enemies_near(global_position, 4.3 if wide else 3.3):
				var to2: Vector3 = e.global_position - global_position
				to2.y = 0
				if to2.length() < 0.5 or fwd.dot(to2.normalized()) > cos(deg_to_rad(115.0 if wide else 75.0)):
					var r := roll_damage(1.4 * dmg_mult("hellclaw"))
					var dealt: float = e.take_damage(r["phys"], r["fire"] + r["phys"] * 0.35, global_position, 0.5, r["crit"])
					if ls > 0.0:
						life = minf(max_life, life + dealt * ls / 100.0)
					DemonFx.ignite(game.world.fx_root, e)
					hit = true
			game.add_shake(0.15 if hit else 0.05)
		"summon":
			_summon_minion()
		"pact":
			buff_t = 12.0 + talent("buff_dur")
			DemonFx.pact(game.world.fx_root, global_position)
			Sfx.play("blood_pact")
			Sfx.duck(-6.0, 1.2)
			game.add_shake(0.3)
			for m in minions:
				if is_instance_valid(m):
					m.empowered = buff_t
					DemonFx.pact(game.world.fx_root, m.global_position)
		"blight":
			var dir := atk_aim - global_position
			dir.y = 0
			dir = dir.normalized() if dir.length() > 0.3 else fwd
			# Twin Skulls: two, a little apart
			var dirs := [dir] if talent("blight_twin") <= 0.0 else [dir.rotated(Vector3.UP, 0.14), dir.rotated(Vector3.UP, -0.14)]
			for dv in dirs:
				var n := WarlockFx.bolt_node(game.world.fx_root)
				n.global_position = global_position + Vector3(0, 1.3, 0) + dv * 0.6
				n.look_at(n.global_position + dv, Vector3.UP)
				bolts.append({"node": n, "dir": dv, "left": 15.0})
		"shackles":
			var root: Node3D = game.world.fx_root
			var reach_s := 7.0 + talent("shackle_range")
			var bind_t := 2.5 + talent("shackle_dur")
			WarlockFx.shackle_cast(root, global_position, reach_s)
			Sfx.play("shackles")
			game.add_shake(0.25)
			for e in game.enemies_near(global_position, reach_s):
				WarlockFx.chain(root, global_position + Vector3(0, 1.1, 0), e.global_position + Vector3(0, 0.8 * e.height, 0), 0.8)
				_hit_enemy(e, 0.8, 0.0)
				if not e.dead:
					e.stun(bind_t)
					WarlockFx.shackle(e, bind_t * (0.3 if e.boss else 1.0))
		"covenant":
			buff_t = 12.0 + talent("buff_dur")
			covenant_t = buff_t
			WarlockFx.covenant(game.world.fx_root, global_position)
			Sfx.play("covenant")
			Sfx.duck(-9.0, 1.6)
			game.add_shake(0.3)
	stats_changed.emit()

## Banshee Wail's scream: damage, hurls back and terrifies everything within 7 m.
func _wail(nd: float, knock: float) -> void:
	WraithFx.wail(game.world.fx_root, global_position, 7.0)
	game.add_shake(0.4 if knock > 1.5 else 0.25)
	for e in game.enemies_near(global_position, 7.0):
		e.take_damage(nd, 0.0, global_position, knock, false)
		if not e.dead:
			e.stun(1.6 + talent("wail_stun"))

# ---------------------------------------------------------------- warlock skills
const DRAIN_RANGE := 11.0     # how far away a beam can latch on
const DRAIN_LEASH := 13.0     # a latched victim that gets further away than this breaks free
const DRAIN_FORK := 5.5       # forks reach enemies this close to the main victim
const DRAIN_MIN := 1.0        # a tap of Q still channels this long

## The enemy Drain Life latches onto: the one nearest the aim point, else the nearest in reach.
func _drain_pick(aim: Vector3):
	var best = null
	var bd := 3.0
	for e in game.enemies_near(aim, 3.0):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(global_position) <= DRAIN_RANGE:
			bd = d
			best = e
	if best == null:
		best = _drain_nearest(global_position, DRAIN_RANGE, null)
	return best

func _drain_nearest(p: Vector3, r: float, skip):
	var best = null
	var bd := r
	for e in game.enemies_near(p, r):
		if e == skip:
			continue
		var d: float = e.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best

func _drain_valid(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.global_position.distance_to(global_position) <= DRAIN_LEASH

## The main victim first, then the enemies the beam forks to (nearest the main victim).
func _drain_victims() -> Array:
	if not _drain_valid(drain_main):
		return []
	var mp: Vector3 = drain_main.global_position
	var near: Array = game.enemies_near(mp, DRAIN_FORK).filter(func(e): return e != drain_main)
	near.sort_custom(func(a, b): return a.global_position.distance_to(mp) < b.global_position.distance_to(mp))
	var forks := (5 if covenant_t > 0.0 else 3) + int(talent("drain_fork"))
	return [drain_main] + near.slice(0, forks)

func _drain_start(foe) -> void:
	drain_t = 0.0
	drain_tick = 0.1
	drain_main = foe
	target = null
	path = PackedVector3Array()
	moving = false
	drain_heal = 0.0
	drain_heal_t = 0.0
	_face(foe.global_position - global_position)
	var root: Node3D = game.world.fx_root
	WarlockFx.latch(root, foe.global_position + Vector3(0, 1.0 * foe.height, 0))
	drain_sigil = WarlockFx.sigil(root, 1.25)
	drain_sigil.global_position = global_position + Vector3(0, 0.06, 0)
	drain_hum = Sfx.start_loop("drain_loop", -9.0)
	Sfx.play("drain_start", -3.0)
	game.add_shake(0.08)

func end_drain() -> void:
	var was := drain_t >= 0.0
	drain_t = -1.0
	drain_main = null
	for b in drain_beams.values():
		if is_instance_valid(b):
			b.queue_free()
	drain_beams.clear()
	for e in drain_lit.values():
		if is_instance_valid(e):
			e.set_drained(false)
	drain_lit.clear()
	if was and game and game.world and drain_light != null and is_instance_valid(drain_light):
		WarlockFx.release(game.world.fx_root, drain_light.global_position)
	if drain_light != null and is_instance_valid(drain_light):
		drain_light.queue_free()
	drain_light = null
	if drain_sigil != null:
		WarlockFx.sigil_fade(drain_sigil)
	drain_sigil = null
	if drain_hum != null and is_instance_valid(drain_hum):
		drain_hum.stop()
		drain_hum.queue_free()
	drain_hum = null
	_show_drain_heal()

## Healing from the beam shows as one green "+N" about once a second rather than every tick.
func _show_drain_heal() -> void:
	if drain_heal >= 1.0 and game and game.world:
		Fx.number(game.world.fx_root, global_position + Vector3(0, 2.3, 0), "+%d" % int(drain_heal), Color(0.45, 1.0, 0.4))
	drain_heal = 0.0
	drain_heal_t = 0.0

## Drain Life: every 0.3 s each victim loses life and the Warlock gains some of it back.
## If the main victim dies the beam jumps to the nearest enemy still in reach.
func _update_drain(delta: float) -> void:
	drain_t += delta
	if not _drain_valid(drain_main):
		var from: Vector3 = drain_main.global_position if drain_main != null and is_instance_valid(drain_main) else global_position
		drain_main = _drain_nearest(from, DRAIN_FORK, null)
		if not _drain_valid(drain_main):
			drain_main = _drain_nearest(global_position, DRAIN_RANGE, null)
		if drain_main == null:
			end_drain()
			return
		WarlockFx.latch(game.world.fx_root, drain_main.global_position + Vector3(0, 1.0 * drain_main.height, 0))
	if drain_t >= DRAIN_MIN and not game.skill_held("drain"):
		end_drain()
		return
	_face_smooth(drain_main.global_position - global_position, delta)
	drain_tick -= delta
	if drain_tick > 0.0:
		return
	drain_tick = 0.3
	if drain_t >= DRAIN_MIN:
		# past the first second the channel costs mana (about 6.5 a second)
		if mana < 2.0:
			game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
			end_drain()
			return
		mana -= 2.0 * (1.0 - talent("cost:drain") / 100.0)
	var root: Node3D = game.world.fx_root
	var hand: Vector3 = (J.get("at_hand_l", J["hand_l"]) as Node3D).global_position
	var dmg := (6.0 + level * 2.4 + (dmg_min + dmg_max) * 0.6) * 0.3 * buff_mult() * dmg_mult("drain")
	var heal := 0.0
	var victims := _drain_victims()
	for i in victims.size():
		var e = victims[i]
		e.dmg_tint = Color(0.55, 1.0, 0.45)
		# the main victim is dragged a little toward the Warlock
		var dealt: float = e.take_damage(dmg * (1.0 if i == 0 else 0.6), 0.0, global_position, -0.25 if i == 0 else 0.0, false)
		e.dmg_tint = Color(0, 0, 0, 0)
		heal += dealt * (0.3 if i == 0 else 0.15)
		if not e.dead:
			e.drain_flash(Warlock.FEL)
		WarlockFx.siphon(root, e.global_position + Vector3(0, 1.0 * e.height, 0), hand if i == 0 else drain_main.global_position + Vector3(0, 1.0 * drain_main.height, 0))
	if covenant_t > 0.0:
		heal *= 2.0
	heal *= 1.0 + talent("drain_heal") / 100.0
	# Soul Glut: what would heal past full life fills mana instead
	if talent("drain_glut") > 0.0 and life + heal > max_life:
		mana = minf(max_mana, mana + (life + heal - max_life) * talent("drain_glut") / 100.0)
	life = minf(max_life, life + heal)
	drain_heal += heal
	drain_heal_t += 0.3
	if drain_heal_t >= 0.9:
		_show_drain_heal()
	Sfx.play("drain_tick", -7.0)
	stats_changed.emit()

## Redraws the beams each frame after the pose, so they leave the hand where it is now.
func _draw_drain() -> void:
	if drain_t < 0.0:
		return
	var victims := _drain_victims()
	if victims.is_empty():
		return
	var root: Node3D = game.world.fx_root
	var hand: Vector3 = (J.get("at_hand_l", J["hand_l"]) as Node3D).global_position + (-rig.global_transform.basis.z) * 0.08
	var mc: Vector3 = drain_main.global_position + Vector3(0, 1.0 * drain_main.height, 0)
	var keep := {}
	for i in victims.size():
		var e = victims[i]
		var id: int = e.get_instance_id()
		keep[id] = true
		var b = drain_beams.get(id)
		if b == null or not is_instance_valid(b):
			b = WarlockFx.beam(root, 0.26 if i == 0 else 0.15)
			drain_beams[id] = b
			if i > 0:
				WarlockFx.latch(root, e.global_position + Vector3(0, 1.0 * e.height, 0))
		b.width = 0.26 if i == 0 else 0.15
		b.caps = i == 0
		if not drain_lit.has(id):
			drain_lit[id] = e
			e.set_drained(true)
		if i == 0:
			b.draw(hand, mc, anim_time)
		else:
			var ec: Vector3 = e.global_position + Vector3(0, 1.0 * e.height, 0)
			b.arc = 0.45 + mc.distance_to(ec) * 0.12
			b.draw(mc, ec, anim_time)
	for id in drain_beams.keys():
		if not keep.has(id):
			var b = drain_beams[id]
			if is_instance_valid(b):
				b.queue_free()
			drain_beams.erase(id)
	for id in drain_lit.keys():
		if not keep.has(id):
			var e = drain_lit[id]
			if is_instance_valid(e):
				e.set_drained(false)
			drain_lit.erase(id)
	if drain_light == null or not is_instance_valid(drain_light):
		drain_light = WarlockFx.hand_light(root)
	drain_light.global_position = hand
	drain_light.light_energy = 1.5 + 0.4 * sin(anim_time * 23.0) + 0.3 * sin(anim_time * 7.0)
	if drain_sigil != null and is_instance_valid(drain_sigil):
		drain_sigil.global_position = global_position + Vector3(0, 0.06, 0)
		drain_sigil.rotation.y = anim_time * 0.9

## Blight Bolt: flies straight until it hits an enemy, a wall or runs out of range.
func _update_bolts(delta: float) -> void:
	for b in bolts.duplicate():
		var n = b["node"]
		if not is_instance_valid(n):
			bolts.erase(b)
			continue
		var step := 16.0 * delta
		var p: Vector3 = n.global_position
		var np: Vector3 = game.world.move(p, (b["dir"] as Vector3) * step, 0.15)
		var moved := np - p
		moved.y = 0
		np.y = lerpf(p.y, game.world.height_at(np.x, np.z) + 1.2, clampf(delta * 6.0, 0.0, 1.0))
		n.global_position = np
		b["left"] -= step
		if not game.enemies_near(np, 1.0).is_empty() or b["left"] <= 0.0 or moved.length() < step * 0.4:
			_blight_burst(np)
			n.queue_free()
			bolts.erase(b)

func _blight_burst(p: Vector3) -> void:
	var g := Vector3(p.x, game.world.height_at(p.x, p.z), p.z)
	var root: Node3D = game.world.fx_root
	var rad := 3.0 * (1.0 + talent("blight_size") / 100.0)
	var dur := 4.0 + talent("blight_dur")
	WarlockFx.blight_burst(root, g, rad)
	var pool := WarlockFx.blight_pool(root, g, rad, dur)
	blights.append({"node": pool, "pos": g, "t": dur, "tick": 0.5, "r": rad})
	Sfx.play_at("blight_burst", g, -1.0)
	game.add_shake(0.18)
	var nd := (14.0 + level * 4.0 + (dmg_min + dmg_max) * 0.35) * buff_mult() * dmg_mult("blight")
	for e in game.enemies_near(g, rad):
		e.take_damage(nd, 0.0, g, 0.8, false)

## Plague pools rot whatever stands in them every half second.
func _update_blights(delta: float) -> void:
	for bl in blights.duplicate():
		bl["t"] -= delta
		bl["tick"] -= delta
		if bl["t"] <= 0.0 or not is_instance_valid(bl["node"]):
			blights.erase(bl)
			continue
		if bl["tick"] <= 0.0:
			bl["tick"] = 0.5
			var nd := (4.0 + level * 1.3 + (dmg_min + dmg_max) * 0.12) * buff_mult() * dmg_mult("blight")
			for e in game.enemies_near(bl["pos"], float(bl.get("r", 3.0))):
				e.take_damage(nd, 0.0, bl["pos"], 0.0, false)

func _clear_warlock() -> void:
	end_drain()
	for b in bolts:
		if is_instance_valid(b["node"]):
			b["node"].queue_free()
	bolts.clear()
	blights.clear()
	covenant_t = 0.0

# ---------------------------------------------------------------- demon skills
## Summon Demon: a demon climbs out of a sigil in front of you. Up to three; a fourth
## replaces the oldest.
func _summon_minion() -> void:
	minions = minions.filter(func(m): return is_instance_valid(m))
	var slot := 0
	if minions.size() >= max_minions():
		var old = minions.pop_front()
		slot = old.slot
		old.dismiss()
	else:
		var used := minions.map(func(m): return m.slot)
		while slot in used:
			slot += 1
	var fwd := -rig.global_transform.basis.z
	var pos: Vector3 = game.world.move(global_position, fwd * 1.8)
	pos.y = game.world.height_at(pos.x, pos.z)
	DemonFx.summon_circle(game.world.fx_root, pos)
	Sfx.play("summon_demon")
	game.add_shake(0.2)
	var m := DemonMinion.new()
	m.name = "Minion%d" % slot
	game.add_child(m)
	m.setup(self, game, slot)
	m.global_position = pos
	m.rig.rotation.y = rig.rotation.y
	minions.append(m)

## Three demons at once, four with Legion of Hell.
func max_minions() -> int:
	return 3 + int(talent("minion_max"))

func dismiss_minions() -> void:
	for b in beasts:
		if is_instance_valid(b):
			b.dismiss()
	beasts.clear()
	for m in minions:
		if is_instance_valid(m):
			m.dismiss()
	minions.clear()

## Underworld Phase: six seconds unseen and untouchable, moving faster; the rift erupts on return.
func _phase_start() -> void:
	phased = true
	phase_t = 6.0 + talent("phase_dur")
	game.set_underworld(true)
	DemonFx.phase_tear(game.world.fx_root, global_position)
	Sfx.play("phase_in")
	game.add_shake(0.2)

func end_phase(erupt := true) -> void:
	if not phased:
		return
	phased = false
	phase_t = 0.0
	if game and game.world:
		game.set_underworld(false)
		if erupt and not dead:
			DemonFx.eruption(game.world.fx_root, global_position, 4.0)
			Sfx.play("phase_erupt")
			Sfx.duck(-8.0, 1.0)
			game.add_shake(0.4)
			for e in game.enemies_near(global_position, 4.0):
				_hit_enemy(e, 2.0, 2.0, "phase")
				if not e.dead:
					e.stun(0.8)
			if talent("phase_heal") > 0.0:
				life = minf(max_life, life + max_life * talent("phase_heal") / 100.0)
				stats_changed.emit()

# ---------------------------------------------------------------- wraith skills
## Shadow Step: dissolve, slide through the shadows to the aim point (stopping at walls), re-form.
func _shadow_step(aim: Vector3) -> void:
	var start := global_position
	var d := aim - start
	d.y = 0
	var dist := minf(d.length(), 9.0)
	if dist < 0.5:
		dist = 4.0
		d = -rig.global_transform.basis.z
	var dir := d.normalized()
	var p := start
	var step := 0.4
	var travelled := 0.0
	while travelled < dist:
		var np: Vector3 = game.world.move(p, dir * minf(step, dist - travelled))
		var moved := np - p
		moved.y = 0
		if moved.length() < step * 0.3:
			break
		p = np
		travelled += moved.length()
	p.y = game.world.height_at(p.x, p.z)
	var root: Node3D = game.world.fx_root
	WraithFx.shade_depart(root, start)
	Sfx.play_at("shade_out", start, -2.0)
	Sfx.play("shade_in", -2.0)
	global_position = p
	path = PackedVector3Array()
	moving = false
	target = null
	_face(dir)
	WraithFx.shade_arrive(root, p)
	game.add_shake(0.2)
	for e in game.enemies_near(p, 2.4):
		_hit_enemy(e, 1.2, 1.0, "shade")
		if not e.dead:
			e.stun(0.7)
	# the shade left behind collapses a moment later
	get_tree().create_timer(0.45, false).timeout.connect(func():
		if not is_instance_valid(self) or game.world == null:
			return
		WraithFx.shade_implode(game.world.fx_root, start)
		Sfx.play_at("shade_implode", start, -1.0)
		for e in game.enemies_near(start, 2.6):
			_hit_enemy(e, 0.9, 0.8, "shade"))
	# a quick cast pose so the re-forming reads on screen
	_start_attack("cast", "")
	atk_dur = 0.35
	impact_done = true

func _clear_spirits() -> void:
	for s in spirits:
		if is_instance_valid(s["node"]):
			var n: Node3D = s["node"]
			if game and game.world:
				WraithFx.spirit_hit(game.world.fx_root, n.global_position)
			n.queue_free()
	spirits.clear()
	spirit_t = 0.0

## Spectral Host: the spirits orbit, then dart at the nearest foe and fly back.
func _update_spirits(delta: float) -> void:
	if spirits.is_empty():
		return
	spirit_t -= delta
	if spirit_t <= 0.0 or dead:
		_clear_spirits()
		return
	var centre := global_position + Vector3(0, 1.35, 0)
	for s in spirits:
		var n: Node3D = s["node"]
		if not is_instance_valid(n):
			continue
		s["phase"] += delta * 2.6
		var orbit: Vector3 = centre + Vector3(cos(s["phase"]) * 1.15, sin(s["phase"] * 2.0) * 0.18, sin(s["phase"]) * 1.15)
		match s["state"]:
			"orbit":
				n.global_position = n.global_position.lerp(orbit, clampf(delta * 10.0, 0.0, 1.0))
				s["t"] -= delta
				if s["t"] <= 0.0:
					var best = null
					var bd := 7.5
					for e in game.enemies_near(global_position, 7.5):
						var dd: float = e.global_position.distance_to(global_position)
						if dd < bd:
							bd = dd
							best = e
					if best != null:
						s["state"] = "dart"
						s["target"] = best
						s["from"] = n.global_position
						s["t"] = 0.0
					else:
						s["t"] = 0.3
			"dart":
				var tg = s["target"]
				if not is_instance_valid(tg) or tg.dead:
					s["state"] = "back"
					s["t"] = 0.0
					continue
				s["t"] += delta / 0.28
				var to: Vector3 = tg.global_position + Vector3(0, 1.0 * tg.height, 0)
				var mid: Vector3 = (s["from"] as Vector3).lerp(to, 0.5) + Vector3(0, 1.2, 0)
				var k: float = clampf(s["t"], 0.0, 1.0)
				n.global_position = (s["from"] as Vector3).lerp(mid, k).lerp(mid.lerp(to, k), k)
				if k >= 1.0:
					_hit_enemy(tg, 0.55, 0.3, "host")
					WraithFx.spirit_hit(game.world.fx_root, to)
					Sfx.play_at("spirit_dart", to, -4.0)
					s["state"] = "back"
					s["t"] = 0.0
			"back":
				n.global_position = n.global_position.lerp(orbit, clampf(delta * 7.0, 0.0, 1.0))
				if n.global_position.distance_to(orbit) < 0.25:
					s["state"] = "orbit"
					s["t"] = randf_range(0.7, 1.1)

func _update_charge(delta: float) -> void:
	charge_t += delta
	var dist := 18.0 * delta
	var np: Vector3 = game.world.move(global_position, charge_dir * dist)
	var moved := np - global_position
	moved.y = 0
	global_position = np
	_face(charge_dir)
	phase += delta * 20.0
	Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.2, 0), Color(0.6, 0.55, 0.45, 0.5), 2, 0.8, 0.3, 0.6, false, 0.5)
	for e in game.enemies_near(global_position, 1.6):
		if not charge_hit.has(e.get_instance_id()):
			charge_hit[e.get_instance_id()] = true
			_hit_enemy(e, 1.3, 2.5, "charge")
			e.stun(0.8)
			# Relentless: each enemy smashed takes time off the other cooldowns
			if talent("charge_cdr") > 0.0:
				for k in cds:
					if k != "charge":
						cds[k] = maxf(0.0, cds[k] - talent("charge_cdr"))
			if charge_hit.size() == 1:
				Sfx.play_at("charge_impact", e.global_position, 0.0)
			Fx.sparks(game.world.fx_root, e.global_position + Vector3(0, 1.0, 0))
	if charge_t > 0.5 or moved.length() < dist * 0.3:
		charge_t = -1.0
		Fx.ring(game.world.fx_root, global_position, 2.5, Color(0.9, 0.8, 0.6), 0.35)
		game.add_shake(0.25)

func _update_trail(active: bool) -> void:
	var im: ImmediateMesh = trail.mesh
	im.clear_surfaces()
	if active and weapon_node != null and is_instance_valid(weapon_node):
		var wl := 0.9
		var w = equipment.get("weapon")
		if w != null:
			var sh: Dictionary = Data.BASES[w["base"]].get("shape", {})
			wl = sh.get("len", sh.get("haft", 0.7)) + 0.05
		var base := weapon_node.global_transform * Vector3(0, 0, -0.25)
		var tip := weapon_node.global_transform * Vector3(0, 0, -wl)
		trail_pts.push_front([base, tip])
		if trail_pts.size() > 12:
			trail_pts.pop_back()
	elif trail_pts.size() > 0:
		trail_pts.pop_back()
		if trail_pts.size() > 0:
			trail_pts.pop_back()
	if trail_pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in trail_pts.size():
		var f := 1.0 - float(i) / trail_pts.size()
		var c := Color(trail_col.r, trail_col.g, trail_col.b, f * 0.55)
		im.surface_set_color(c)
		im.surface_add_vertex(trail_pts[i][0])
		im.surface_set_color(Color(c.r, c.g, c.b, f * 0.9))
		im.surface_add_vertex(trail_pts[i][1])
	im.surface_end()

func respawn(p: Vector3) -> void:
	dead = false
	dead_t = 0.0
	rig.rotation.x = 0.0
	rig.position.y = 0.0
	life = max_life
	mana = max_mana
	heal_pool = 0.0
	target = null
	path = PackedVector3Array()
	moving = false
	global_position = p
	stats_changed.emit()

# ---------------------------------------------------------------- inventory
const BELT_STACK := 5
const INV_STACK := 20

## Picks up, buys or moves an item. Potions (any count) top up matching belt stacks, then
## empty belt slots, then matching inventory stacks, then empty cells. Returns false if not
## everything fit; a potion stack is then left holding what didn't.
func add_to_inventory(it: Dictionary) -> bool:
	if it["base"] == "gold":
		gold += int(it["count"])
		stats_changed.emit()
		return true
	if Data.BASES[it["base"]]["slot"] == "potion":
		var n := _stack_into(belt, it, BELT_STACK, int(it.get("count", 1)), true)
		n = _stack_into(inventory, it, INV_STACK, n, false)
		stats_changed.emit()
		it["count"] = n
		return n <= 0
	for i in inventory.size():
		if inventory[i] == null:
			inventory[i] = it
			stats_changed.emit()
			return true
	return false

## Puts up to n potions like `it` into `slots`: matching stacks first, then empty slots
## (belt slots only fill when `fill_empty_belt`). Returns how many are left over.
func _stack_into(slots: Array, it: Dictionary, cap: int, n: int, fill_empty_belt: bool) -> int:
	for i in slots.size():
		if n <= 0:
			return 0
		var s = slots[i]
		if s != null and s["base"] == it["base"] and int(s.get("count", 1)) < cap:
			var add := mini(n, cap - int(s.get("count", 1)))
			s["count"] = int(s.get("count", 1)) + add
			n -= add
	for i in slots.size():
		if n <= 0:
			return 0
		if slots[i] == null and (fill_empty_belt or slots != belt):
			var s := it.duplicate(true)
			s["count"] = mini(n, cap)
			slots[i] = s
			n -= int(s["count"])
	return n

## Merges loose potions in the inventory into stacks (older saves kept one per cell).
func stack_potions() -> void:
	for i in inventory.size():
		var it = inventory[i]
		if it != null and Data.BASES[it["base"]]["slot"] == "potion":
			inventory[i] = null
			var n := _stack_into(inventory, it, INV_STACK, int(it.get("count", 1)), false)
			if n > 0:
				it["count"] = n
				inventory[i] = it

## Drops inventory cell `from` onto cell `to`: potions of the same kind merge (up to a full
## stack), anything else swaps.
func move_in_inventory(from: int, to: int) -> void:
	var a = inventory[from]
	var b = inventory[to]
	if a != null and b != null and a["base"] == b["base"] and Data.BASES[a["base"]]["slot"] == "potion":
		var add := mini(int(a.get("count", 1)), INV_STACK - int(b.get("count", 1)))
		b["count"] = int(b.get("count", 1)) + add
		a["count"] = int(a.get("count", 1)) - add
		if a["count"] <= 0:
			inventory[from] = null
	else:
		inventory[from] = b
		inventory[to] = a
	stats_changed.emit()

func equip_from_inventory(idx: int) -> void:
	var it = inventory[idx]
	if it == null:
		return
	if not Items.is_equip(it):
		# potions: as many as fit go to the belt, the rest stay here
		inventory[idx] = null
		var n := _stack_into(belt, it, BELT_STACK, int(it.get("count", 1)), true)
		if n > 0:
			it["count"] = n
			inventory[idx] = it
		stats_changed.emit()
		return
	var only: String = str(Data.BASES[it["base"]].get("cls", ""))
	if only != "" and only != cls:
		game.ui.message("Only the %s can use that" % Data.CLASSES[only]["name"], Color(1, 0.4, 0.3))
		Sfx.play("deny")
		return
	if int(it.get("req", 1)) > level:
		game.ui.message("You need to be level %d" % it["req"], Color(1, 0.4, 0.3))
		Sfx.play("deny")
		return
	var slot := Items.equip_slot(it, equipment)
	var old = equipment.get(slot)
	equipment[slot] = it
	inventory[idx] = old
	Sfx.play("equip")
	recalc()
	refresh_gear()

func unequip(slot: String) -> void:
	var it = equipment.get(slot)
	if it == null:
		return
	for i in inventory.size():
		if inventory[i] == null:
			inventory[i] = it
			equipment[slot] = null
			Sfx.play("equip")
			recalc()
			refresh_gear()
			return
	game.ui.message("Inventory is full", Color(1, 0.4, 0.3))

func to_save() -> Dictionary:
	return {"cls": cls, "level": level, "xp": xp, "str": str_, "dex": dex, "vit": vit, "ene": ene, "points": stat_points, "gold": gold,
		"equipment": equipment, "inventory": inventory, "belt": belt, "stash": stash, "show_helm": show_helm, "binds": binds, "talents": talents}

func from_save(d: Dictionary) -> void:
	set_class(str(d.get("cls", "knight")))
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	str_ = int(d.get("str", 20))
	dex = int(d.get("dex", 15))
	vit = int(d.get("vit", 25))
	ene = int(d.get("ene", 10))
	stat_points = int(d.get("points", 0))
	gold = int(d.get("gold", 0))
	show_helm = bool(d.get("show_helm", true))
	equipment = d.get("equipment", {})
	for s in Items.EQUIP_SLOTS:
		if not equipment.has(s):
			equipment[s] = null
	inventory = d.get("inventory", [])
	inventory.resize(40)
	stack_potions()
	belt = d.get("belt", [null, null, null, null])
	belt.resize(4)
	stash = d.get("stash", [])
	stash.resize(60)
	binds = (d.get("binds", {}) as Dictionary).duplicate() if d.get("binds") is Dictionary else {}
	_check_binds()
	# a save from before talents gets a build picked for its class and level
	if d.get("talents") is Dictionary:
		talents = Talents.clean(cls, d["talents"])
		if Talents.spent(talents) > level - 1:
			talents = {}
	else:
		talents = Talents.auto_build(cls, level - 1)
	tfx = Talents.sum(cls, talents)
	if game and game.ui and not puppet:
		game.ui.refresh_skill_slots()
	recalc()
	life = max_life
	mana = max_mana
	refresh_gear()
