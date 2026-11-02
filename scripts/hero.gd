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
## Boats this character owns (Data.BOATS ids; bought from the shipwright on the Mournwater Coast, saved).
var boats: Array = []
## Aboard a boat (BoatRide): he stands at the tiller; the boat moves him, so his own moving stops.
var aboard := false
## He has sailed before (the controls guide shows the first time only; saved).
var sailed := false
var dwarves := ""              # the Verdant Isle's drunken dwarves (DwarfGame): "" not met, "won", "lost", "fought"

func owns_boat(id: String) -> bool:
	return boats.has(id)

## The boat he sails: the dearest one he owns (Data.BOATS), or the Gull (moored at the pier before he buys her).
func best_boat() -> String:
	var best := "gull"
	var price := -1
	for b in boats:
		if Data.BOATS.has(str(b)) and int(Data.BOATS[str(b)]["price"]) > price:
			best = str(b)
			price = int(Data.BOATS[str(b)]["price"])
	return best
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
var knock_v := Vector3.ZERO    # being thrown back (a bear's maul)
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
## Where the current (or last) attack or skill was aimed. Setting it also fixes atk_dir, the flat
## direction from the hero to that point at the moment of aiming, so the blow, the projectile or the
## lunge keep going the way the pointer was even if he walks on (WASD) or the body turns meanwhile.
var atk_aim := Vector3.ZERO:
	set(v):
		atk_aim = v
		if is_inside_tree():
			var d := (v - global_position) * Vector3(1, 0, 1)
			if d.length() > 0.05:
				atk_dir = d.normalized()
var atk_dir := Vector3.FORWARD
## The mouse pointer's point on the ground (or the enemy under it), refreshed by Game every frame.
var cursor := Vector3.ZERO
var impact_done := false
var blocking := false
var block_amt := 0.0
var block_flash := 0.0
## the Hollow Sloth's blows (sloth.gd): its sweep throws you back, its slam stuns
var shove := Vector3.ZERO
var daze_t := 0.0
var chill_t := 0.0          # Rimeclaw's cold: slowed while it lasts
var hit_t := 0.0
var cls := "knight"          # "knight", "wraith", "demon" or "warlock" (Data.CLASSES)
var cds := {}
var wr := {}                 # Wraith: the skills' state (WraithSkills: the tether, phantoms, the night, the claws)
var veil_t := 0.0            # Wraith: seconds he is mist, and blows pass through him (Shadowstep, Eternal Night)
var roll_t := -1.0          # the dodge roll on Space (Dodge): seconds into it, -1 when not rolling
var roll_dir := Vector3.FORWARD
var roll_cd := 0.0
var dm := {}                 # Demon: the skills' state (DemonSkills: the charge, lava on the ground, fissures, boulders, the grip, the wrath)
var phased := false          # (the Underworld's grade in game.gd reads it; no skill sets it now)
var drain_t := -1.0          # Warlock: Drain Life channel time (-1 = not channelling)
var drain_tick := 0.0
var drain_main = null        # the enemy the beam is latched onto (the beams themselves are fxs["drain"], WarlockFx)
var drain_heal := 0.0        # healing gathered since the last "+N" number
var drain_heal_t := 0.0
var drain_victims: Array = []  # Drain Life's victims this frame: the main one, then its forks (WarlockSkills)
var covenant_t := 0.0        # Warlock: Fel Covenant (Drain Life forks further and heals double)
var bolts: Array = []        # Warlock's Blight Bolts in flight: [{node, dir, left}] (flown by WarlockFx.update, burst here)
## The archer (archer.gd): arrows in flight, volleys raining down, snares lying in wait, the spirit beasts
var arrows: Array = []
var volleys: Array = []
var snares: Array = []
var pd: Plague = null           # the plague doctor's flasks, clouds, traps, poison and infection (plague.gd)
var beasts: Array = []
var beast_down_t := 0.0     # after the Spirit Beast falls, seconds until it rises again beside him
var mark = null             # the enemy the archer is shooting at: his beast goes for it first
var mark_t := 0.0
var blights: Array = []      # plague pools on the ground, their ticks: [{pos, t, tick, r}] (the pool itself is a WarlockFx effect)
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
var hidden_t := 0.0            # Doug's Doppel-Doug: monsters can't see him while it runs (Enemy's hero_dead)
var pied_t := 0.0              # a cream pie in the face (DougSkills, PvP): aim assist off, the screen creamed
## seconds since this hero last fought (struck, was struck, attacked or cast; jj, 2026-11-02): out of combat
## stamina lasts and refills better and better, up to CALM_MAX times after CALM_RAMP more seconds (calm())
var combat_t := 999.0
const COMBAT_SECS := 5.0
const CALM_RAMP := 10.0
const CALM_MAX := 5.0
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
var net_boat_st: Variant = null      # a partner sailing: Vector4(x, z, yaw, speed) of his boat (Net._boat_packet)
var net_boat_id := "gull"            # and which boat she is (Data.BOATS)
var net_boat: BoatRide               # the boat drawn under his puppet (BoatRide.puppet_update)
var _net_last_t := 0.0
## Skill effects that linger (SkillFx: the Siphon tether, Drain Life's beams, Eternal Night, phantoms, arrows
## in flight), on the local hero and on a puppet alike; started and ended by fx events, moved by SkillFx.update.
var fxs := {}

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

func is_doug() -> bool:
	return cls == "doug"

func is_plague() -> bool:
	return cls == "plague"

## The dragon classes (Obsidian Wyrm, Frost Serpent, Storm Wyvern; scripts/dragon.gd).
func is_dragon() -> bool:
	return Dragon.is_dragon(cls)

## The archer with a bow in his hands: his attack shoots instead of swinging.
func has_bow() -> bool:
	var w = equipment.get("weapon") if equipment is Dictionary else null
	return is_archer() and w != null and Data.BASES[w["base"]]["kind"] in ["bow", "longbow"]

func skill_list() -> Array:
	return Data.skills_for(cls)

# ---------------------------------------------------------------- skill effects (SkillFx, every class)
## A skill wants something seen: play the event here now and, in co-op, on this hero's puppet on every
## partner's game. `data` carries what the effect needs (points, a direction, enemies in "t"); the gameplay
## (damage, healing, stuns) never goes through here. See SkillFx.
func fx(skill: String, ev: String, data := {}) -> void:
	var d: Dictionary = data.duplicate()
	d["s"] = skill
	d["e"] = ev
	SkillFx.play(self, d)
	if not puppet and game != null and game.net != null:
		game.net.skill_fx(d)

## The attack in progress (0..1, -1 when none) and its style: the local hero's own, a puppet's from the net.
func attack_progress() -> float:
	return SkillFx.atk(self)

func attack_style() -> String:
	return SkillFx.style(self)

# ---------------------------------------------------------------- skill bindings
## The bar holds a skill on each mouse button; any skill can also go on a hotkey. Saved per character.
const BIND_KEYS := ["Q", "E", "R", "F", "G", "V"]
const BIND_SLOTS := ["lmb", "rmb", "Q", "E", "R", "F", "G", "V"]
var binds := {}

## Path of Exile style: left mouse attacks, right mouse is the class's first skill (also on Q); Block is in the
## skills window (K) for anyone who wants it on a slot.
func default_binds() -> Dictionary:
	var own := skill_list()
	var b := {"lmb": "attack", "rmb": own[0]["id"] if not own.is_empty() else "block"}
	# (a class with fewer than six of its own fills the rest from the shared ones; one with seven, Doug, has its first
	# on the right mouse button and the other six on the hotkeys)
	var bar := (own.slice(1) if own.size() > BIND_KEYS.size() else own) + Data.shared_skills()
	for i in BIND_KEYS.size():
		b[BIND_KEYS[i]] = bar[i]["id"] if i < bar.size() else ""
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
	# every hotkey holds a skill: an empty one takes the next of the class's skills not on the bar yet
	var on_bar := {}
	for k in BIND_KEYS:
		on_bar[str(binds.get(k, ""))] = true
	var spare := (skill_list() + Data.shared_skills()).map(func(s): return str(s["id"])).filter(func(id): return not on_bar.has(id))
	for k in BIND_KEYS:
		if str(binds.get(k, "")) == "" and not spare.is_empty():
			binds[k] = spare.pop_front()

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
	elif is_doug():
		rig = Doug.build_body()
	elif is_plague():
		rig = Plague.build_body()
		if pd == null:
			pd = Plague.new(self)
	elif is_dragon():
		rig = Dragon.build(cls)     # posed in code every frame (Anim.pose hands it to Dragon.pose)
	else:
		var body := _knight_body()
		if body == "mocap":
			rig = Knight.build_mocap()
		else:
			rig = Knight.build(Knight.default_gear()) if body == "" else Knight.build_meshy(body == "armored")
		rig.set_meta("gait", "knight")    # Anim: heavy armoured run, elbows out
	rig.set_meta("pers", "hero")
	radius = float(Dragon.spec(cls)["radius"]) if is_dragon() else 0.45
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
	ClassSkills.clear(self)
	pd = null                 # the plague doctor's Plague object goes with his body (a new one comes with the rig)
	SkillFx.clear(self)
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
	var tm := ShaderMaterial.new()
	tm.shader = _trail_shader()
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
	stash = []           # (a new character starts with an empty stash, not the last one's)
	stash.resize(60)
	for k in cds.keys():
		cds[k] = 0.0
	buff_t = 0.0
	ClassSkills.clear(self)
	SkillFx.clear(self)
	equipment = {}
	for s in Items.EQUIP_SLOTS:
		equipment[s] = null
	# a dragon starts with its own claws and teeth (Data.unarmed); everyone else with their weapon
	equipment["weapon"] = null if is_dragon() else Items.make(str(Data.CLASSES[cls].get("weapon", "hand_axe" if is_demon() else "short_sword")))
	if cls == "knight":
		equipment["shield"] = Items.make("buckler")
	equipment["armor"] = Items.make("quilted")
	belt = [Items.potion("hp_potion"), Items.potion("hp_potion"), Items.potion("mp_potion"), null]
	belt[0]["count"] = 4
	belt[1]["count"] = 4
	belt[2]["count"] = 3
	inventory[39] = Items.make("woodsman_axe")     # every hero in the Wilds carries a felling axe (Harvest)
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
	var wd: Array = Items.damage_of(w) if w != null else Data.unarmed(cls)    # a dragon's claws and teeth
	var k := 1.0 + st_total / 100.0
	dmg_min = maxi(1, int(wd[0] * k))
	dmg_max = maxi(dmg_min, int(wd[1] * k))
	fire_dmg = stats.get("fire", 0)
	var wspeed: float = Data.BASES[w["base"]].get("speed", 1.0) if w != null else Data.unarmed_speed(cls)
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
	if game != null and game.net.server and game.hero == self:
		return      # (a dedicated server's parked hero isn't anyone's)
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
		if has_bow() and J.has("grip_l") and not J.has("grip_bow"):
			# the placeholder body holds a bow in its left hand; Anim keeps the grip lined up with the arm (bow_l)
			(J["grip_l"] as Node3D).add_child(weapon_node)
			J["bow_l"] = weapon_node
		else:
			J.erase("bow_l")
			_weapon_hand(J).add_child(weapon_node)
		# the new model starts in the hand: force _carry_weapon to place it (and the body's hilt) next frame
		carry.configure(cls)
		_carry_in_hand = not (carry.t >= float(carry.p["grab"]))
		gear_nodes.append(weapon_node)
		if w.get("rarity", 0) == 3 and Models.palette(w)["glow"] != null:
			var fl := Props.fire(weapon_node, Vector3(0, 0, -0.5), 0.35, Models.palette(w)["glow"], false, false, false, "weapon")
			gear_nodes.append(fl)
	var s = equipment.get("shield")
	if s != null:
		shield_node = Models.item_model(s)
		(J["mount_l"] as Node3D).add_child(shield_node)
		shield_node.rotation_degrees = Vector3(0, 0, 0)
		shield_node.position = Vector3(-0.03, 0, 0)
		shield_rest = shield_node.transform
		gear_nodes.append(shield_node)
	rig.set_meta("shield", shield_node != null)
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
	elif is_dragon():
		pass                               # a dragon's body has no armour to show (its gear hangs off a hidden joint)
	elif is_archer():
		if not rig.has_meta("meshy"):      # the ranger's own body has nothing to rebuild
			Knight.rebuild_body(rig, Archer.body_gear(knight_gear()))
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
	if weapon_node == null or not is_instance_valid(weapon_node) or rig == null or has_bow():  # a bow stays in the left hand
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
	weapon_node.visible = (in_hand or store != "hilt") and not (pd != null and pd.hands_busy) and _chop_axe == null   # the plague doctor puts his cane away to throw; the felling axe replaces it
	# ease into the hold (identity in the hand; the back mount's own rest)
	var k := 1.0 - exp(-delta * 16.0)
	weapon_node.transform = weapon_node.transform.interpolate_with(Transform3D.IDENTITY, k)

## The hand that holds the weapon: the right, except a bow on a body that holds it in the left (the ranger),
## turned for the bow's kind (Archer.BOW_HOLD).
func _weapon_hand(J: Dictionary) -> Node3D:
	var w = equipment.get("weapon")
	if J.has("grip_bow") and w != null and has_bow():
		var g: Node3D = J["grip_bow"]
		var hold: Array = Archer.BOW_HOLD.get(Archer.bow_key(Data.BASES[w["base"]]["kind"]), Archer.BOW_HOLD["bow"])
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
	stop_chop()
	end_drain()
	target = null
	_set_goal(p, direct)

# ---------------------------------------------------------------- aiming
## The mouse pointer is the source of truth for aim, Path of Exile style: WASD moves, the pointer
## aims, and the two are independent, so he can run one way and cast another. Facing never decides
## where anything goes; the body only turns to show it (see _process). Each skill says in
## Data.SKILLS how it uses the pointer:
##   "point"  lands on the pointer (each skill still clamps to its own range: Volley, Grasp, Hurl...)
##   "facing" directional: goes from the hero toward the pointer, out to the skill's "range" (projectiles,
##            beams, charges, lunges, frontal arcs). The name is kept for old data; it means "toward
##            the pointer" now. Short melee skills (range < MELEE_RANGE) bend onto a foe within AIM_CONE_MELEE
##            of the pointer's line; ranged ones go exactly where the pointer says.
##   "self"   centred on the hero; he doesn't turn.
const AIM_CONE_MELEE := 0.35  # radians either side of the pointer's line, for melee reach only
const MELEE_RANGE := 5.0

## The way the body faces (visual; used for blocking's "from the front" and a few effects).
func facing() -> Vector3:
	var f := -rig.global_transform.basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

## The way the current attack or skill was aimed (from the pointer when it started).
func aim_dir() -> Vector3:
	return atk_dir

## The flat unit direction from the hero to point p (the hero's facing if p is on top of him).
func dir_to(p: Vector3) -> Vector3:
	var d := (p - global_position) * Vector3(1, 0, 1)
	return d.normalized() if d.length() > 0.05 else facing()

## The best enemy within dist inside a cone of `cone` radians round `axis` (null if none).
func _assist_pick(axis: Vector3, dist: float, cone: float):
	var best = null
	var bs := INF
	for e in game.enemies_near(global_position, dist):
		var d: Vector3 = e.global_position - global_position
		d.y = 0
		var dl := d.length()
		var ang := axis.angle_to(d / dl) if dl > 0.05 else 0.0
		if ang > cone:
			continue
		var score := dl * (1.0 + 2.5 * ang)
		if score < bs:
			bs = score
			best = e
	return best

## Where an action aimed along the current aim direction lands: for melee reach a foe close to that
## line, else straight along it. Used when a skill needs to find its foe again mid-cast.
func aim_ahead(dist: float) -> Vector3:
	var axis := aim_dir()
	if dist < MELEE_RANGE and pied_t <= 0.0:          # (a pie in the face: no help aiming)
		var best = _assist_pick(axis, dist, AIM_CONE_MELEE)
		if best != null:
			return best.global_position
	return global_position + axis * dist

## The aim point for skill `id`, given the pointer's point `at` (the enemy under it if there is one).
func skill_aim(id: String, at: Vector3) -> Vector3:
	var s := Data.skill_def(id)
	if s.is_empty():
		return at
	match String(s.get("aim", "facing")):
		"point":
			return at
		"self":
			return global_position + facing()
	# directional: toward the pointer, out to the skill's range
	var rng := float(s.get("range", 3.5))
	var to := (at - global_position) * Vector3(1, 0, 1)
	var dir := to.normalized() if to.length() > 0.05 else facing()
	if rng < MELEE_RANGE:
		var best = _assist_pick(dir, rng + 0.5, AIM_CONE_MELEE)
		if best != null:
			return best.global_position
	# the pointer itself when it's in range (so a beam or a tether latches on what's under it), else
	# the point on its line at full range; either way the direction is the pointer's
	var p := global_position + dir * minf(maxf(to.length(), 0.5), rng)
	p.y = game.world.height_at(p.x, p.z) if game != null and game.world != null else at.y
	return p

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
# ---------------------------------------------------------------- woodcutting (Harvest)
var chop_tree = null              # the Harvest.HTree he's felling
var chop_power := 0.0
var _chop_axe: Node3D = null      # the felling axe in his hand while he chops (none when his weapon is the axe)
var _chop_axe_base := ""

## Starts felling a tree he has walked up to (Game._interact "tree"). False, with a word why, when he can't.
func start_chop(t) -> bool:
	if dead or not is_instance_valid(t) or str(t.state) != "stand":
		return false
	if game.bg_mode:
		return false
	var ax := chop_axe()
	if str(ax[0]) == "":
		game.ui.message("You need an axe to fell trees. Halvar the smith sells them.", Color(1, 0.6, 0.35))
		Sfx.play("deny")
		return false
	chop_tree = t
	chop_power = float(ax[1])
	target = null
	moving = false
	path = PackedVector3Array()
	var w = equipment.get("weapon")
	_show_chop_axe(not (w != null and str(w["base"]) == str(ax[0])), str(ax[0]))
	if atk_t < 0.0:
		_chop_swing()
	return true

## One swing of the axe at the trunk: turned square to it, the class's own swing time (Data.CHOP_PROFILES).
func _chop_swing() -> void:
	var d: Vector3 = (chop_tree as Node3D).global_position - global_position
	d.y = 0.0
	if d.length() > 0.05:
		_face(d.normalized())
	var prof := Data.chop_profile(cls)
	_start_attack("chop", "chop")
	atk_dur = float(prof["swing"])
	Sfx.play_synced("swing_heavy", Anim.impact_at("chop") * atk_dur - 0.05, -7.0, 0.82)

func _chop_ok() -> bool:
	if dead or not is_instance_valid(chop_tree) or str(chop_tree.state) != "stand":
		return false
	var tp: Vector3 = (chop_tree as Node3D).global_position
	return Vector2(tp.x - global_position.x, tp.z - global_position.z).length() <= float(chop_tree.radius) + 0.8

func _chop_impact() -> void:
	if _chop_ok():
		Harvest.strike_from(self, int(chop_tree.id), chop_power)

func _chop_next() -> void:
	if _chop_ok():
		_chop_swing()
	else:
		stop_chop()

## Puts the axe away (moving, a skill, a blow taken, the tree down).
func stop_chop() -> void:
	if chop_tree == null and _chop_axe == null:
		return
	if atk_skill == "chop":
		atk_t = -1.0
		atk_skill = ""
	chop_tree = null
	_show_chop_axe(false, "")

## The felling axe in his weapon hand (sized for his body; the Wraith's is a spectral one), his own weapon away.
func _show_chop_axe(on: bool, base: String) -> void:
	if rig == null:
		return
	if on and _chop_axe != null and _chop_axe_base == base:
		return
	if _chop_axe != null:
		if is_instance_valid(_chop_axe):
			_chop_axe.queue_free()
		_chop_axe = null
		_chop_axe_base = ""
	if on and base != "":
		var J: Dictionary = rig.get_meta("j")
		var hand: Node3D = J.get("grip_r", null)
		if hand == null:
			return
		var prof := Data.chop_profile(cls)
		_chop_axe = Models.item_model(Items.make(base))
		_chop_axe.scale = Vector3.ONE * float(prof["axe_scale"])
		if prof.get("spectral", false):
			for mi in _chop_axe.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = Mats.glow(Color(0.45, 0.9, 1.0), 1.1, 0.0, 0.8)
		hand.add_child(_chop_axe)
		_chop_axe_base = base
	if weapon_node != null and is_instance_valid(weapon_node) and puppet:
		weapon_node.visible = _chop_axe == null

func swipe_attack(aim: Vector3, keep_target := false) -> void:
	if dead or charge_t >= 0.0 or drain_t >= 0.0 or daze_t > 0.0:
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
	# along the aim taken when the swing started, not the body's facing
	var fwd := aim_dir()
	if slam:
		# Holy Slam leaps to the spot aimed at, sliding round anything solid on the way
		global_position = game.world.move(global_position, fwd * d)
		return
	# don't step through a foe that's already in reach
	for e in game.enemies_near(global_position, 2.0):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() - e.radius < 0.75 and fwd.dot(to.normalized()) > 0.5:
			return
	global_position = game.world.move(global_position, fwd.normalized() * d)

func _swipe_impact() -> void:
	var fwd := aim_dir()
	var fin := atk_style == "swipe3"
	var rng := reach() + (1.0 if fin else 0.55)
	var arc := 181.0 if fin else 70.0
	var mult := 1.0 if atk_style == "swipe1" else (1.15 if atk_style == "swipe2" else 1.7)
	var any := false
	var struck := []
	for e in game.enemies_near(global_position, rng + 1.5):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() - e.radius > rng:
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(arc)):
			_hit_enemy(e, mult, 0.9 if fin else 0.2)
			fx("attack", "hit", {"p": e.global_position + Vector3(0, 1.1 * e.height, 0), "c": trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5)})
			any = true
			struck.append(e)
	if pd != null:
		pd.cane_blow(atk_style, struck)      # the plague doctor's blows each leave something of his own
	if fin:
		fx("attack", "finisher", {"r": rng, "x": any})
		if any:
			game.hitstop(0.06)

func _face_smooth(d: Vector3, delta: float) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), clampf(delta * 14.0, 0.0, 1.0))

func cmd_target(t) -> void:
	if dead or charge_t >= 0.0:
		return
	if t != chop_tree:
		stop_chop()
	end_drain()
	target = t
	if is_instance_valid(t):
		_set_goal(t.global_position, false)

## WASD steering: the hero runs where the keys point. The heading eases toward the keys at TURN_RATE
## (fast: a full reversal takes about a tenth of a second) only to smooth the change of direction; it
## starts from the keys themselves, not from the way the body faces, and it has nothing to do with
## aiming (the pointer aims). A sharp turn slows him a little; letting go of the keys forgets the heading.
const TURN_RATE := 28.0     # radians per second
var wasd_heading := Vector3.ZERO
## Where the head looks ahead of the body while turning (radians, + = left), for Anim.pose's "look".
var look := 0.0
var _look_want := 0.0
var _last_yaw := 0.0

func _steer(want: Vector3, delta: float) -> Vector3:
	if wasd_heading.length() < 0.1:
		# starting off: straight the way the keys say (he may be facing his last shot)
		wasd_heading = want
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
		stop_chop()
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
	return (not Data.skill_locked(sk, level) or game.test_allskills) and cds.get(id, 0.0) <= 0.0 and mana >= skill_cost(id)

func can_act() -> bool:
	return not dead and atk_t < 0.0 and charge_t < 0.0 and drain_t < 0.0

func use_skill(id: String, aim: Vector3) -> bool:
	stop_chop()
	if dead or charge_t >= 0.0 or daze_t > 0.0:
		return false
	if atk_t >= 0.0 and atk_skill != "":
		return false
	var sk: Dictionary = {}
	for s in skill_list() + Data.shared_skills():
		if s["id"] == id:
			sk = s
	if sk.is_empty() or (Data.skill_locked(sk, level) and not game.test_allskills):
		game.ui.message("Requires level %d" % sk.get("lvl", 1), Color(1, 0.4, 0.3))
		return false
	if cds[id] > 0.0:
		game.ui.message("%s is recharging" % sk["name"], Color(0.8, 0.8, 0.8))
		return false
	if mana < skill_cost(id):
		game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
		Sfx.play("deny")
		return false
	# the class's own checks (a foe to latch onto or seize, ...) before anything is spent
	if not ClassSkills.can_cast(self, id, aim):
		return false
	# cancel a basic swing (or a Drain Life channel) so the skill fires right away
	end_drain()
	atk_t = -1.0
	impact_done = true
	mana -= skill_cost(id)
	cds[id] = skill_cd(id)
	atk_aim = aim
	_face(aim - global_position)
	# the class's skills script starts it (ClassSkills.of: KnightSkills, WraithSkills, DemonSkills, ...)
	ClassSkills.cast(self, id, aim)
	SkillSpec.apply_timing(self, id)      # (a "use" in the skill's data sets its length)
	# the cast itself, seen by everyone (SkillFx: the class draws it, or the default puff shows it)
	fx(id, "cast", {"p": atk_aim})
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

## Starts an attack or a skill's motion. `secs` (optional) is the attack's length in seconds before attack speed
## and the class's pace (else 0.62, or the swipe's own length for a weapon swing).
func _start_attack(style: String, skill := "", secs := 0.0) -> void:
	atk_style = style
	atk_skill = skill
	atk_t = 0.0
	atk_dur = 0.62 / aspd
	if SWIPE_DUR.has(style) and skill == "":
		atk_dur = SWIPE_DUR[style] / aspd
	if secs > 0.0:
		atk_dur = secs / aspd
	atk_dur *= Data.attack_pace(cls)     # every class's pace (Data.ATTACK_PACE)
	impact_done = false
	trail_pts.clear()
	trail_col = ClassSkills.trail_color(cls, skill)
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
	# a skill's (or the bow's) own sound: the class's skills script
	if ClassSkills.sound(self, skill, at):
		return
	match skill:
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
	return what + "_" + str(Data.CLASSES.get(cls, {}).get("voice", "knight"))

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = atan2(-d.x, -d.z)

func reach() -> float:
	if is_dragon():
		return Dragon.reach(cls)
	return Archer.RANGE if has_bow() else 1.7

# ---------------------------------------------------------------- damage
func roll_damage(mult: float = 1.0) -> Dictionary:
	var d := randf_range(dmg_min, dmg_max + 1) * mult * buff_mult()
	var crit := randf() < 0.05 + total_dex() * 0.0015 + talent("crit") / 100.0
	if crit:
		d *= 2.0 + talent("crit_dmg") / 100.0
	return {"phys": d, "fire": fire_dmg * mult, "crit": crit}

## The battle buffs (Battle Cry, Eternal Night, Blood Pact, Fel Covenant): +40% damage, more with talents.
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
	# "power" in the skill's data scales all it deals (its weapon part, its own part, its burns): tuning a skill the
	# Path of Exile way (its use time sets its rate) without touching its code
	return (1.0 + (talent("dmg") + talent("dmg:" + id)) / 100.0) * pace_mult(id) * float(Data.skill_def(id).get("power", 1.0))

## Attacks are slower by the class's pace (Data.ATTACK_PACE); the ones whose rate the swing itself sets
## (the basic attack, skills with no cooldown) hit that much harder, so their damage per second stays put.
## Skills on a cooldown fire just as often, and channels ("channel" in Data.SKILLS) tick on their own clock, so they keep their damage.
func pace_mult(id: String) -> float:
	if id == "attack" or (skill_cd(id) <= 0.0 and not Data.skill_def(id).get("channel", false)):
		return Data.attack_pace(cls)
	return 1.0

## src: the skill doing the hitting (talent bonuses); by default the attack in progress.
## flat: damage on top of the weapon roll (a spell's part by level, e.g. the Wraith's spirit-light), scaled by the
## buffs and the skill's talents like the rest, in the same number.
var _engaged_t := 0.0

## A monster awake and after this hero close by (its fight is on even before a blow lands).
func _engaged() -> bool:
	if game == null or game.world == null:
		return false
	for e in game.world.enemies_root.get_children():
		if e is Enemy and not e.dead and e.aggro and (e.global_position - global_position).length_squared() < 196.0:
			return true
	return false

## How rested the hero is: 1 in combat (and for COMBAT_SECS after), rising to CALM_MAX over CALM_RAMP s out of it.
## Sprinting drains stamina that many times slower and it refills that many times faster.
func calm() -> float:
	return lerpf(1.0, CALM_MAX, clampf((combat_t - COMBAT_SECS) / CALM_RAMP, 0.0, 1.0))

func _hit_enemy(e, mult: float, knock: float = 0.0, src := "", flat := 0.0) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	combat_t = 0.0
	if src == "":
		src = atk_skill if atk_skill != "" else "attack"
	var r := roll_damage(mult * dmg_mult(src))
	if flat > 0.0:
		r["phys"] += flat * buff_mult() * dmg_mult(src) * (2.0 if r["crit"] else 1.0)
	var dealt: float = e.take_damage(r["phys"], r["fire"], global_position, knock, r["crit"])
	if ls > 0.0:
		life = minf(max_life, life + dealt * ls / 100.0)
	if r["crit"]:
		game.hitstop(0.05)
	game.add_shake(0.15 if not r["crit"] else 0.3)

func take_hit(dmg: float, from: Vector3, kind: String = "melee", element: String = "phys") -> void:
	stop_chop()
	if dead:
		return
	combat_t = 0.0
	if puppet:
		if game.net.is_host:
			game.net.hit_player(peer_id, dmg, from, kind, element)
		return
	if game.test_immortal or phased:
		return
	if Dodge.dodging(self):
		Dodge.dodged(self)
		return
	if veil_t > 0.0:
		# the Wraith as mist: the blow goes through him
		Fx.number(game.world.fx_root, global_position + Vector3(0, 2.2, 0), "Mist", WraithFx.SPIRIT)
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 1.0, 0), Color(0.06, 0.03, 0.1, 0.7), 8, 1.5, 0.3, 0.5, false, 0.8)
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
	if kind == "maul":
		# thrown back from the blow
		var away := global_position - from
		away.y = 0
		knock_v = (away.normalized() if away.length() > 0.05 else -rig.global_transform.basis.z) * 7.5
	# a plain thud, no voice: an "oof" on every hit was too much
	var burn := kind == "burn"
	if not burn:
		Sfx.play("hero_hit", -3.0, randf_range(0.9, 1.1))
		Fx.blood(game.world.fx_root, global_position + Vector3(0, 1.2, 0), Color(0.6, 0.02, 0.02))
		game.add_shake(0.2)
	show_damage(dmg)
	game.ui.flash_damage()
	# Doug in his clown car is unstoppable: blows land, their stuns and slows don't
	if DougSkills.driving(self) and kind in ["sweep", "quake", "chill", "freeze", "shock", "root", "slip"]:
		kind = "melee"
	# the Hollow Sloths' blows: thrown back, stunned, chilled, frozen solid, shocked
	match kind:
		"sweep":
			var away := global_position - from
			away.y = 0
			if away.length() > 0.01:
				shove = away.normalized() * 11.0
		"quake":
			daze_t = maxf(daze_t, 1.1)
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Stunned", Color(0.95, 0.8, 0.5))
		"chill":
			chill_t = maxf(chill_t, 2.5)
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Chilled", Color(0.55, 0.85, 1.0))
		"freeze":
			daze_t = maxf(daze_t, 1.8)
			chill_t = maxf(chill_t, 4.0)
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Frozen", Color(0.6, 0.9, 1.0))
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 1.0, 0), Color(0.8, 0.95, 1.0), 30, 1.5, 0.15, 1.0, true, -1.0)
		"slip":
			# a banana peel (DougSkills): down for a moment, sliding on the way he was going
			if not DougSkills.driving(self):
				daze_t = maxf(daze_t, 0.7)
				var dir := facing()
				shove = dir * 6.0
				Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Slipped!", Color(1.0, 0.9, 0.3))
		"pied":
			pied_t = 1.5
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Pied!", Color(1.0, 0.97, 0.88))
			if not puppet and game.ui.has_method("pie_face"):
				game.ui.pie_face(1.5)
		"root":
			daze_t = maxf(daze_t, 1.2)
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Rooted", Color(0.55, 1.0, 0.4))
		"shock":
			daze_t = maxf(daze_t, 0.45)
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Shocked", Color(0.8, 0.6, 1.0))
	if life <= 0.0:
		life = 0.0
		dead = true
		Dodge.cancel(self)
		ClassSkills.died(self)
		SkillFx.clear(self)
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
		if pd != null:
			pd.update(delta)       # a partner plague doctor's flasks and clouds (shown only)
		return
	for k in cds.keys():
		cds[k] = maxf(0.0, cds[k] - delta)
	buff_t = maxf(0.0, buff_t - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	ClassSkills.update(self, delta)     # every class's lingering skills (pools, the tether, lava, arrows, clouds...)
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
	if knock_v.length() > 0.05:
		global_position = game.world.move(global_position, knock_v * delta)
		knock_v = knock_v.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	if dead:
		dead_t += delta
		var f := clampf(dead_t / 0.7, 0.0, 1.0)
		var fall := clampf((dead_t - 0.35) / 0.6, 0.0, 1.0)
		if not _floats() and not _own_death():
			rig.rotation.x = fall * fall * 1.42
			rig.position.y = -fall * 0.12
		Anim.pose(rig, {"time": anim_time, "dead": f, "hit": (1.0 - f) * 0.5})
		if is_demon():
			_hover()      # the lava keeps cooling, the Underworld's shadow lifts
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
	if not game.bg_mode:            # (no life regeneration in the crypt: potions and care)
		life = minf(max_life, life + regen * delta)
	mana = minf(max_mana, mana + (1.0 + ene * 0.06) * delta)

	if aboard:
		# at the tiller: standing, swaying a little with the boat; BoatRide places him
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
		block_amt = 0.0
		var stand := {"time": anim_time, "phase": phase, "move": move_amt, "atk": -1.0, "style": atk_style, "block": 0.0, "hit": 0.0, "look": 0.0}
		if not puppet:
			carry.update(self, delta)
			stand.merge(carry.anim_state(), true)
		Anim.pose(rig, stand)
		last_pose = stand
		return
	var want_block := blocking and atk_t < 0.0 and charge_t < 0.0
	block_amt = move_toward(block_amt, 1.0 if (want_block or block_flash > 0.0) else 0.0, delta * 9.0)
	var vel := Vector3.ZERO
	var wants_move := direct_dir.length() > 0.1 or (moving and not path.is_empty())
	# stamina: sprint drains it, resting refills it; running dry leaves you winded
	running = sprint and wants_move and not exhausted and block_amt < 0.5 and charge_t < 0.0
	combat_t += delta
	hidden_t = maxf(0.0, hidden_t - delta)
	pied_t = maxf(0.0, pied_t - delta)
	_engaged_t -= delta
	if _engaged_t <= 0.0:
		_engaged_t = 0.5
		if _engaged():
			combat_t = 0.0
	var rested := calm()
	if running:
		stamina = maxf(0.0, stamina - delta * 14.0 / rested)
		stamina_rest = 0.0
		if stamina <= 0.0:
			exhausted = true
			game.ui.message("Out of stamina", Color(1.0, 0.8, 0.3))
	else:
		stamina_rest += delta
		if stamina_rest > 0.6:
			stamina = minf(max_stamina, stamina + delta * (16.0 if not wants_move else 9.0) * rested)
	if game.test_stamina:
		stamina = max_stamina
		exhausted = false
	if exhausted and stamina >= max_stamina * 0.3:
		exhausted = false
	var speed := 4.8 * (1.0 + frw / 100.0) * (Battlegrounds.MOVE_MULT if game.bg_mode else 1.0) * DougSkills.car_mult(self)
	# the archer runs 10% faster while his Spirit Beast is at his side
	if is_archer() and beasts.any(func(b) -> bool: return is_instance_valid(b) and not b.dead):
		speed *= 1.1
	if running:
		speed *= 1.6
	if phased:
		speed *= 1.4
	if block_amt > 0.5:
		speed *= 0.42
	if atk_t >= 0.0:
		# an archer loosing arrows steps slowly with the bow drawn; everyone else slows a little mid-swing
		speed *= Archer.SHOOT_MOVE if (has_bow() and atk_style == "bow") else 0.72
	if game.test_fast:
		speed *= game.TEST_FAST
	if shove.length() > 0.05:
		global_position = game.world.move(global_position, shove * delta)
		shove = shove.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	if daze_t > 0.0:
		daze_t -= delta
		hit_t = maxf(hit_t, 0.6)
		speed = 0.0
	if chill_t > 0.0:
		chill_t -= delta
		speed *= 0.55

	if roll_t >= 0.0:
		vel = Dodge.step(self, delta)
	elif charge_t >= 0.0:
		KnightSkills.update_charge(self, delta)
	else:
		if atk_t >= 0.0:
			_update_attack(delta)
		if drain_t >= 0.0:
			WarlockSkills.update_drain(self, delta)
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
	if ClassSkills.rooted(self):
		vel = Vector3.ZERO
	if vel.length() > 0.01:
		var np: Vector3 = game.world.move(global_position, vel * delta)
		var moved := (np - global_position)
		moved.y = 0
		global_position = np
		if moved.length() < vel.length() * delta * 0.2 and moving:
			moving = false
			path = PackedVector3Array()
		if atk_t >= 0.0:
			# moving while he attacks or casts: the body keeps to the aim taken at the start, whichever
			# way the legs carry him (visual; the blow goes along atk_dir regardless)
			_face_smooth(atk_dir, delta)
		elif block_amt > 0.5 and charge_t < 0.0:
			_face_smooth(cursor - global_position, delta)
		elif charge_t < 0.0 and drain_t < 0.0:
			_face(vel)
		move_amt = move_toward(move_amt, stride, delta * 6.0)
		# super speed glides: the legs only go a little faster
		var anim_v: float = vel.length() * (1.6 / game.TEST_FAST if game.test_fast else 1.0)
		phase += delta * anim_v * 2.9 / maxf(move_amt, 0.6) * (float(rig.get_meta("stride")) if rig.has_meta("stride") else 1.0)
		_snow_step()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
		if atk_t < 0.0 and charge_t < 0.0 and drain_t < 0.0 and block_amt > 0.5:
			# standing with the guard up: the shield turns to the pointer
			_face_smooth(cursor - global_position, delta)
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
		if _chop_axe != null and not is_instance_valid(chop_tree):
			stop_chop()
		carry.update(self, delta)
		st.merge(carry.anim_state(), true)
		_carry_weapon(delta)
		if pd != null:
			pd.idle_fidget(st, delta)   # now and then, standing about, he peers at a vial
	Anim.pose(rig, st)
	if is_archer():
		Archer.pose_bow(self, st)
	last_pose = st
	_hover()
	Dodge.pose(self, delta)
	WarlockSkills.drain_victims_changed(self)
	SkillFx.update(self, delta)
	_breathe(delta)
	_apply_shield_pose()
	# no sword-swing streak off a bow, nor off the Wraith's and the Demon's skills (their clips, not weapon swings)
	_update_trail(((atk_t >= 0.0 and not ((is_wraith() or is_demon() or is_doug()) and atk_skill != "")) or charge_t >= 0.0) and not has_bow() and not is_dragon())

## The Wraith floats a hand's breadth off the ground, bobbing slowly and leaning into motion.
func _hover() -> void:
	if is_demon():
		Demon.animate(rig, anim_time, move_amt, self)
		return
	if is_warlock():
		Warlock.animate(rig, anim_time, move_amt, 1.0 if covenant_t > 0.0 or (puppet and net_buff) else 0.0,
			phase, float(last_pose.get("atk", -1.0)) < 0.0 and drain_t < 0.0)
		return
	if not is_wraith() or dead or _floats():
		return
	rig.position.y = 0.2 + sin(anim_time * 2.1) * 0.05
	rig.rotation.x = -move_amt * 0.12

## The Wraith's mocap body floats by itself (KnightMocapRig's float mode: hover, lean, the sinking death).
func _floats() -> bool:
	return is_wraith() and rig != null and rig.has_method("sync_pose")

## A body whose death clip lays it down itself (the Demon's mocap body): the hero's death tilt stays off it.
func _own_death() -> bool:
	return rig != null and rig.has_meta("own_death")

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
	net_boat_st = Vector4(p[16], p[17], p[18], p[19]) if p.size() >= 20 and p[15] > 0.5 else null
	var bi := int(p[20]) if p.size() >= 21 else 0
	var bk: Array = Data.BOATS.keys()
	net_boat_id = str(bk[bi]) if bi >= 0 and bi < bk.size() else "gull"
	if was_dead and not dead:
		rig.rotation.x = 0.0
		rig.position.y = 0.0
	elif dead and not was_dead:
		# the partner fell: whatever his skills left behind goes with him, as on his own screen
		SkillFx.clear(self)
	net_has = true

## The zone changed under a puppet: its lingering effects belonged to the old one.
func net_zone_reset() -> void:
	Dodge.cancel(self)
	net_boat_st = null
	if net_boat and is_instance_valid(net_boat):
		net_boat.queue_free()
	net_boat = null
	visible = false
	net_has = false
	SkillFx.clear(self)
	for b in beasts:
		if is_instance_valid(b):
			b.queue_free()
	beasts.clear()

func _puppet_process(delta: float) -> void:
	visible = net_has
	if not net_has:
		return
	var k := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(net_pos, k)
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	BoatRide.puppet_update(self, delta)      # a partner at sea: his boat, and him at its tiller
	aura.emitting = net_buff
	if dead:
		var f := clampf(dead_t / 0.7, 0.0, 1.0)
		var fall := clampf((dead_t - 0.35) / 0.6, 0.0, 1.0)
		if not _floats() and not _own_death():
			rig.rotation.x = fall * fall * 1.42
			rig.position.y = -fall * 0.12
		Anim.pose(rig, {"time": anim_time, "dead": f, "hit": (1.0 - f) * 0.5})
		if is_demon():
			_hover()      # the lava keeps cooling, the Underworld's shadow lifts
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
	_show_chop_axe(atk_t >= 0.0 and str(st.get("style", "")) == "chop", "woodsman_axe")
	Anim.pose(rig, st)
	if is_archer():
		Archer.pose_bow(self, st)
	_hover()
	Dodge.pose(self, delta)
	Archer.update(self, delta)
	SkillFx.update(self, delta)
	_apply_shield_pose()
	# a partner's swing in his class's colour (white before), and none on Doug's throws and tricks
	if trail_pts.is_empty():
		trail_col = ClassSkills.trail_color(cls, "")
	_update_trail(atk_t >= 0.0 and not has_bow() and not is_dragon() and not (is_doug() and str(st.get("style", "")) in Doug.SKILL_STYLES))

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
		var was_chop := atk_skill == "chop"
		atk_t = -1.0
		atk_skill = ""
		if swipe and atk_style == "swipe3":
			swipe_n = 0
		if was_chop:
			_chop_next()

func _impact() -> void:
	if atk_skill == "chop":
		_chop_impact()
		return
	var fwd := aim_dir()
	# a skill (or the archer's shot): its class's script deals it
	if ClassSkills.impact(self):
		stats_changed.emit()
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
					fx("attack", "hit", {"p": tg.global_position + Vector3(0, 1.1 * tg.height, 0)})
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
					fx("attack", "hit", {"p": best.global_position + Vector3(0, 1.1 * best.height, 0)})
					hit_any = true
	stats_changed.emit()

# ---------------------------------------------------------------- class skills kept on the hero
## Called from other scripts and tests; the skills themselves live in WarlockSkills.
func end_drain() -> void:
	WarlockSkills.end_drain(self)

func _drain_victims() -> Array:
	return WarlockSkills.drain_victims(self)

func _blight_burst(p: Vector3) -> void:
	WarlockSkills.blight_burst(self, p)

func _clear_warlock() -> void:
	WarlockSkills.clear(self)

static var _trail_sh: Shader

## The swing's trail (was a flat additive ribbon that read as a white paper blade): UV.x = age along the swing
## (0 = the blade now), UV.y = from the hilt (0) to the tip (1); a hot thin edge at the tip, a soft body fading toward
## the hilt and with age, faint streaks running back along it, in the class's colour (vertex colour; alpha = strength).
static func _trail_shader() -> Shader:
	if _trail_sh == null:
		_trail_sh = Shader.new()
		_trail_sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float age = UV.x;
	float edge = UV.y;
	float body = pow(edge, 1.3) * 0.5;
	float rim = smoothstep(0.78, 1.0, edge) * 1.25;
	float fade = pow(clamp(1.0 - age, 0.0, 1.0), 1.7);
	float streak = 0.72 + 0.28 * sin(edge * 34.0 + age * 9.0);
	float a = (body + rim) * fade * streak * COLOR.a;
	vec3 c = mix(COLOR.rgb, vec3(1.0, 0.97, 0.9), smoothstep(0.88, 1.0, edge) * 0.55);
	ALBEDO = c * a;
	ALPHA = clamp(a, 0.0, 1.0);
}"""
	return _trail_sh

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
	# smoothed through the samples (Catmull-Rom, SUB steps between each pair), so a fast swing is an arc, not facets
	const SUB := 3
	var n: int = trail_pts.size()
	var total := float((n - 1) * SUB)
	var c := Color(trail_col.r, trail_col.g, trail_col.b, 0.85)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		for k in SUB + (1 if i == n - 2 else 0):
			var t := float(k) / SUB
			var a0: Array = trail_pts[maxi(i - 1, 0)]
			var a1: Array = trail_pts[i]
			var a2: Array = trail_pts[i + 1]
			var a3: Array = trail_pts[mini(i + 2, n - 1)]
			var base: Vector3 = (a1[0] as Vector3).cubic_interpolate(a2[0], a0[0], a3[0], t)
			var tip: Vector3 = (a1[1] as Vector3).cubic_interpolate(a2[1], a0[1], a3[1], t)
			var age := float(i * SUB + k) / total
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(age, 0.0))
			im.surface_add_vertex(base)
			im.surface_set_color(c)
			im.surface_set_uv(Vector2(age, 1.0))
			im.surface_add_vertex(tip)
	im.surface_end()

func respawn(p: Vector3) -> void:
	if not puppet and game != null and game.hero == self:
		game.on_local_respawn()
	Dodge.cancel(self)
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
	if Items.stack_cap(it["base"]) > 1:
		# resources (wood): onto matching stacks first, then empty cells, each up to the base's "stack"
		var left := _stack_into(inventory, it, Items.stack_cap(it["base"]), int(it.get("count", 1)), false)
		stats_changed.emit()
		it["count"] = left
		return left <= 0
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

## How many of a base the inventory holds, across all its stacks.
func count_of(base_id: String) -> int:
	var n := 0
	for s in inventory:
		if s != null and s["base"] == base_id:
			n += int(s.get("count", 1))
	return n

## Takes n of a base out of the inventory (smallest stacks first). False, and nothing taken, if there aren't enough.
func take_items(base_id: String, n: int) -> bool:
	if n <= 0:
		return true
	if count_of(base_id) < n:
		return false
	var cells := []
	for i in inventory.size():
		if inventory[i] != null and inventory[i]["base"] == base_id:
			cells.append(i)
	cells.sort_custom(func(x, y): return int(inventory[x].get("count", 1)) < int(inventory[y].get("count", 1)))
	for i in cells:
		var c := int(inventory[i].get("count", 1))
		var k := mini(c, n)
		n -= k
		if k >= c:
			inventory[i] = null
		else:
			inventory[i]["count"] = c - k
		if n <= 0:
			break
	stats_changed.emit()
	return true

## The best thing he carries to chop with: [base id, power] (an equipped or carried combat axe, or the
## woodsman's axe), or ["", 0.0] with none (Data.CHOP_POWER).
func chop_axe() -> Array:
	var best := ["", 0.0]
	var cands := [equipment.get("weapon")] + inventory
	for it in cands:
		if it == null:
			continue
		var bid: String = it["base"]
		var pw := 0.0
		if bid == "woodsman_axe":
			pw = float(Data.BASES[bid].get("chop", 1.0))
		elif Data.CHOP_POWER.has(bid):
			pw = float(Data.CHOP_POWER[bid])
		if pw > float(best[1]):
			best = [bid, pw]
	return best

## Drops inventory cell `from` onto cell `to`: potions of the same kind merge (up to a full
## stack), anything else swaps.
func move_in_inventory(from: int, to: int) -> void:
	var a = inventory[from]
	var b = inventory[to]
	if a != null and b != null and a["base"] == b["base"] and Items.stack_cap(a["base"]) > 1:
		var add := mini(int(a.get("count", 1)), Items.stack_cap(a["base"]) - int(b.get("count", 1)))
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
	if Items.is_material(it) or Items.is_resource(it) or Items.is_tool_item(it):
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
		"equipment": equipment, "inventory": inventory, "belt": belt, "stash": stash, "show_helm": show_helm, "binds": binds, "binds_v": 2, "talents": talents, "axe_given": true, "boats": boats, "sailed": sailed, "dwarves": dwarves}

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
	boats = (d.get("boats", []) as Array).filter(func(b): return Data.BOATS.has(str(b))) if d.get("boats") is Array else []
	sailed = bool(d.get("sailed", false))
	dwarves = str(d.get("dwarves", ""))
	show_helm = bool(d.get("show_helm", true))
	equipment = d.get("equipment", {})
	for s in Items.EQUIP_SLOTS:
		if not equipment.has(s):
			equipment[s] = null
	inventory = d.get("inventory", [])
	inventory.resize(40)
	# characters from before woodcutting get their felling axe once (in the last free cell)
	if not d.get("axe_given", false) and count_of("woodsman_axe") == 0:
		for i in range(inventory.size() - 1, -1, -1):
			if inventory[i] == null:
				inventory[i] = Items.make("woodsman_axe")
				break
	stack_potions()
	belt = d.get("belt", [null, null, null, null])
	belt.resize(4)
	stash = d.get("stash", [])
	stash.resize(60)
	binds = (d.get("binds", {}) as Dictionary).duplicate() if d.get("binds") is Dictionary else {}
	WraithSkills.migrate_binds(binds)
	DemonSkills.migrate_binds(binds)
	# saves from before the Path of Exile controls had Block on right mouse by default: it becomes the first skill
	if int(d.get("binds_v", 1)) < 2 and str(binds.get("rmb", "")) == "block":
		binds.erase("rmb")
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
