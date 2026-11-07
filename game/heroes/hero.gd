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

# --- derived
var tfx := {}                # what the talents taken add up to (Talents.sum); read with talent()
## A multiplayer run character's build (RunBuild: skills, passives, camp offers); null in single player.
var run: RunBuild = null
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
var boosted := false        # "Go to level 20" was used on this character (saved; the raid server lets only admins in with it)
var boss_luck := {}         # boss kind -> its kills since its last unique (-1/absent: never killed; Game._boss_loot)
var invis_t := 0.0          # a Shadow Phial: unseen (monsters lose him, other players see a faint shimmer up close); any blow ends it
var net_invis := false      # a partner's, from his state (Net._hero_packet)
var burn_t := 0.0           # set burning by another player (PvP: a Fire Arrow, magma, a unique's burn): take_hit "burn"
var burn_dps := 0.0
var burn_by: Hero = null     # who set him burning (the Proving Crypt's meter counts the ticks as theirs)
var _burn_tick := 0.0
var dash_t := 0.0           # a unique's "dash": faster for a moment after a dodge roll (Dodge.start)
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
var fog_hidden := false     # a puppet hidden from this game by the Plague Doctor's Fog (PlagueFogFx.update)
var pvs := {}               # statuses another player put on him in PvP (PvpStatus: slow, snare, harried, reveal, blight)
var pvs_shown := -1         # what PvpStatusFx shows of them on him (bits | blight << 4)
var net_pvs_bits := 0       # a puppet: the statuses his game says he has (PvpStatusFx bits, in his state packet)
var net_pvs_blight := 0     # and his Blight stacks
var chill_t := 0.0          # Rimeclaw's cold: slowed while it lasts
var cc := {}                # crowd control from other players in the Battlegrounds (PvpStatus)
var hit_t := 0.0
var cls := "knight"          # "knight", "wraith", "demon" or "warlock" (Data.CLASSES)
var cds := {}
var veil_t := 0.0            # Wraith: seconds he is mist, and blows pass through him (Shadowstep, Eternal Night)
var roll_t := -1.0          # the dodge roll on Space (Dodge): seconds into it, -1 when not rolling
var roll_dir := Vector3.FORWARD
var roll_cd := 0.0
var phased := false          # (the Underworld's grade in game.gd reads it; no skill sets it now)
var channel_t := -1.0        # a held channel (the Warlock's Drain Life): seconds held, -1 when none (ClassSkills.channel)
## A hero's skills that are objects (Skill, docs/content/skills.md), by skill id: made by his class's script
var kit: Dictionary = {}
## The archer (archer.gd): arrows in flight (drawn: ArcherArrowFx), the spirit beasts
var arrows: Array = []
var beasts: Array = []
var beast_down_t := 0.0     # after the Spirit Beast falls, seconds until it rises again beside him
var mark = null             # the enemy the archer is shooting at: his beast goes for it first
var mark_t := 0.0
var buff_t := 0.0
var heal_pool := 0.0
var mana_pool := 0.0
var dead := false
var dead_t := 0.0
var charge_t := -1.0         # a dash in progress (the Knight's Charge): seconds into it, -1 when none (ClassSkills.dash)
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
var atk_leap := -1.0        # how far this attack's lunge carries him when a skill sets it (Holy Slam's leap): -1 for none
var atk_target = null
var stamina := 100.0
var max_stamina := 100.0
var stamina_rest := 0.0
var hidden_t := 0.0            # Doug's Doppel-Doug: monsters can't see him while it runs (Enemy's hero_dead)
var pied_t := 0.0              # a cream pie in the face (Doug's Cream Pie, PvP): aim assist off, the screen creamed
## seconds since this hero last fought (struck, was struck, attacked or cast; jj, 2026-11-02): out of combat
## stamina lasts and refills better and better, up to CALM_MAX times after CALM_RAMP more seconds (calm())
var combat_t := 999.0
# the uniques' roll and ward effects (Data.ITEM_EFFECTS; everywhere since the items rework): a free dodge roll every pvp_roll_s seconds,
# and a ward (absorbs blows before life; refills out of combat)
var pvp_roll_s := 0
var free_roll_t := 0.0
var ward := 0.0
var ward_max := 0.0
func free_roll() -> bool:
	return pvp_roll_s > 0 and free_roll_t <= 0.0
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
var _net_last_t := 0.0
## Skill effects that linger (SkillFx: the Siphon tether, Drain Life's beams, Eternal Night, phantoms, arrows
## in flight), on the local hero and on a puppet alike; started and ended by fx events, moved by SkillFx.update.
var fxs := {}

func _init() -> void:
	inventory.resize(40)
	for s in Data.SKILLS + Data.RUN_SKILLS:
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

## The dragon classes (Obsidian Wyrm, Frost Serpent, Storm Wyvern; their shared body game/systems/dragons/dragon.gd).
func is_dragon() -> bool:
	return Dragon.is_dragon(cls)

## The archer with a bow in his hands: his attack shoots instead of swinging.
func has_bow() -> bool:
	var w = equipment.get("weapon") if equipment is Dictionary else null
	return is_archer() and w != null and Data.BASES[w["base"]]["kind"] in ["bow", "longbow"]

func skill_list() -> Array:
	# (a run character also has the run-only skills of its class: Data.RUN_SKILLS)
	return Data.skills_for(cls) + (Data.run_skills_for(cls) if run != null else [])

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
	elif puppet and game != null and game.net != null and game.net.server and ServerRules.on(self):
		game.net.server_fx(self, d)      # (what a player's skills did on the server: every game shows it)

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
	if run != null:
		_run_bind(slot, id)
		return
	# a locked skill can't go on the bar (one already there may move between slots: it waits there greyed)
	var sk := Data.skill_def(id) if id != "" else {}
	if not sk.is_empty() and skill_locked(sk) and not (game != null and game.test_allskills) and not binds.values().has(id):
		if game and game.ui and _mine():
			game.ui.message("%s unlocks at level %d" % [sk["name"], int(sk["lvl"])], Color(1, 0.55, 0.4))
		return
	if id != "" and BIND_KEYS.has(slot):
		for k in BIND_KEYS:
			if binds.get(k, "") == id:
				binds[k] = ""
	binds[slot] = id
	if game and game.ui and _mine():
		game.ui.refresh_skill_slots()

## A run character's binds: only its acquired skills, only on the five RunBuild.SLOTS; a skill moved onto a slot
## leaves the one it was on (its cooldown goes with it: Hero.cds is by skill).
func _run_bind(slot: String, id: String) -> void:
	if not (slot in RunBuild.SLOTS) or (id != "" and not run.skills.has(id)):
		return
	if id != "":
		for k in RunBuild.SLOTS:
			if binds.get(k, "") == id:
				binds[k] = ""
	binds[slot] = id
	if game and game.ui and _mine():
		game.ui.refresh_skill_slots()

## Locked: in a run, not acquired yet; otherwise below the skill's level.
func skill_locked(sk: Dictionary) -> bool:
	if run != null:
		return not (str(sk.get("id", "")) == "attack" or run.skills.has(str(sk.get("id", ""))))
	return Data.skill_locked(sk, level)

## Keep only skills this class knows; fill anything missing from the defaults.
func _check_binds() -> void:
	if run != null:
		run.check_binds(binds)
		return
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
	if run != null:
		return 0      # (a run character grows through camp chests, never talents)
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
	if run != null:
		return
	talents = {}
	_talents_changed()

## Spend the free points along the class's suggested build.
func auto_talents() -> void:
	if run != null:
		return
	talents = Talents.auto_build(cls, free_talent_points(), talents)
	_talents_changed()

## The run's build changed (a passive, a gem, a buff came or went): its stats again.
func refresh_run() -> void:
	if run == null:
		return
	run.changed()
	tfx = run.fx(cls)
	recalc()

func _talents_changed() -> void:
	if run != null:
		run.changed()
	tfx = run.fx(cls) if run != null else Talents.sum(cls, talents)
	recalc()
	if game and game.ui and _mine():
		game.ui.refresh_skill_slots()     # mana costs on the bar

## Mana and cooldown after talents.
func skill_cost(id: String) -> float:
	return float(Data.skill_def(id).get("mana", 0)) * (1.0 - talent("cost:" + id) / 100.0)

func skill_cd(id: String) -> float:
	return float(Data.skill_def(id).get("cd", 0.0)) * (1.0 - talent("cd:" + id) / 100.0) * (1.0 - float(stats.get("cdr", 0)) / 100.0)

## A dodge roll's stamina (Dodge.STAMINA, less an item's "stam").
func roll_cost() -> float:
	return Dodge.STAMINA * (1.0 - float(stats.get("stam", 0)) / 100.0)

## How long a stun, slow or root lasts on this hero (1 = in full; items' "ten" shorten it).
func cc_k() -> float:
	return 1.0 - float(stats.get("ten", 0)) / 100.0

func _build_rig() -> void:
	if is_wraith():
		rig = WraithBody.build(wraith_gear())
	elif is_demon():
		rig = DemonBody.build(demon_gear())
	elif is_warlock():
		rig = Warlock.build(warlock_gear())
	elif is_archer():
		rig = ArcherBody.build()
	elif is_doug():
		rig = DougBody.build()
	elif is_plague():
		rig = Plague.build_body()
	elif is_dragon():
		rig = Dragon.build(cls)     # posed in code every frame (Anim.pose hands it to Dragon.pose)
	else:
		var body := _knight_body()
		if body == "mocap":
			rig = KnightBody.build_mocap()
		else:
			rig = Knight.build(Knight.default_gear()) if body == "" else KnightBody.build_meshy(body == "armored")
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
	if DisplayServer.get_name() == "headless": return ""
	if cls != "knight":
		return ""
	if equipment.get("armor") == null:
		return "plain" if KnightBody.meshy_ok() else ""
	if KnightBody.mocap_ok():
		return "mocap"
	return "armored" if KnightBody.armored_ok() else ""

## Switch the character's class: new body, skills and spirit colours.
func set_class(c: String) -> void:
	if not Data.CLASSES.has(c):
		c = "knight"
	if c == cls and rig != null:
		return
	var changed := c != cls
	cls = c
	# whatever the last one was doing is over (a cast left running carried over to the new body)
	atk_t = -1.0
	atk_skill = ""
	impact_done = true
	if changed or binds.is_empty():
		binds = default_binds()
	if changed:
		talents = {}
		tfx = {}
	ClassSkills.clear(self)
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
	if _mine() and game and game.ui:
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
	var g := DemonBody.default_gear()
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
	var g := WraithBody.default_gear()
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
	if not puppet and not bot:
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
	if DisplayServer.get_name() != "headless":
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
	run = null
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
	recalc()
	life = max_life
	mana = max_mana
	refresh_gear()

# ---------------------------------------------------------------- stats
func recalc() -> void:
	stats = {}
	var def_sum := 0
	var shield_block := 0
	for s in (RunBuild.GEAR if run != null else Items.EQUIP_SLOTS):
		var it = equipment.get(s)
		if it == null:
			continue
		var ss := Items.stat_sum(it)
		for k in ss.keys():
			# a unique's effect counts once, the strongest (Data.ITEM_EFFECTS; a free roll's is the quickest recharge);
			# stats add up
			if k == "roll":
				stats[k] = int(ss[k]) if int(stats.get(k, 0)) <= 0 else mini(int(stats[k]), int(ss[k]))
			elif k in Data.ITEM_EFFECTS:
				stats[k] = maxi(int(stats.get(k, 0)), int(ss[k]))
			else:
				stats[k] = stats.get(k, 0) + ss[k]
		def_sum += Items.defense_of(it)
		if s == "shield":
			shield_block = it.get("block", 0)
	# the item rules (Data: level and skills carry a character, gear helps): percentages capped across all gear
	for k in Data.GEAR_CAP:
		if stats.has(k):
			stats[k] = mini(int(stats[k]), int(Data.GEAR_CAP[k]))
	# the Battlegrounds on top: gear's flat stats and defence count for less, its percentages are capped lower, and
	# the weapon is at its Act I strength
	var pvp := pvp_scaled()
	if pvp:
		for k in stats.keys():
			if k in Data.PVP_GEAR_FLAT:
				stats[k] = int(round(float(stats[k]) * Data.PVP_GEAR_SHARE))
		for k in Data.PVP_GEAR_CAP:
			if stats.has(k):
				stats[k] = mini(int(stats[k]), int(Data.PVP_GEAR_CAP[k]))
		def_sum = int(round(def_sum * Data.PVP_ARMOR_SHARE))
	for k in ["str", "dex", "vit", "res", "ls", "regen", "ias", "frw", "block", "mf", "cdr", "pot"]:
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
	# the weapon hits for the level's damage times its quality, then its Enhanced Damage, +Damage and act strength
	# (Data.weapon_damage); bare hands are a dragon's claws and teeth
	var wbase: Array = w["dmg"] if w != null and w.has("dmg") else Data.unarmed(cls)
	var wss: Dictionary = Items.stat_sum(w) if w != null else {}
	var wed := int(wss.get("ed", 0))
	var wpow := float(w.get("power", 1.0)) if w != null else 1.0
	if pvp:
		wed = mini(wed, int(Data.PVP_GEAR_CAP.get("ed", 999)))
	var wd: Array = Data.weapon_damage(level, wbase, wpow, wed, int(wss.get("dmg", 0)), 1.0 if pvp else wpow)
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
	pvp_roll_s = int(stats.get("roll", 0))
	ward_max = max_life * (float(stats.get("ward", 0)) + talent("ward_bonus")) / 100.0
	ward = minf(ward, ward_max)
	life = minf(life, max_life)
	mana = minf(mana, max_mana)
	stats_changed.emit()

## A sandbox bot (Sandbox, the admins' Battlegrounds sandbox): a full hero of its own class, level and gear, played
## by a BotBrain instead of the mouse. Its screen effects, messages and the testing switches are the player's only
## (_mine); `bot_hold` stands in for a held left mouse button.
var bot := false
var bot_hold := false
## The hero whose turn it is (set at the top of each hero's _process; a summon sets its master before it strikes):
## a sandbox stand-in never takes its own hero's blows.
static var striker: Hero = null

## The local player's hero (not a partner's puppet, not a sandbox bot): screen shake, hitstop, messages, the UI.
func _mine() -> bool:
	return not puppet and not bot

## This hero's hits are decided on this game: its own game, or the match server's copy of it when its skills run
## there (ServerRules). Its rites' procs (RunTalents.on_hit, on_death) fire only here.
func decides() -> bool:
	return game.net.server if ServerRules.on(self) else not puppet

## Life back from its own blows (leech, a rite): on the match server's copy of a player it goes to their game, which
## keeps their life.
func gain_life(amount: float) -> void:
	if amount <= 0.0:
		return
	if puppet and game.net.server:
		game.net.tell_self(self, {"life": amount})
		return
	life = minf(max_life, life + amount)

## The Battlegrounds' rules for gear (recalc): on while this game is in a raid (Game.bg_mode); `pvp_force` for tools.
var pvp_force := false
func pvp_scaled() -> bool:
	return pvp_force or (game != null and (game.bg_mode or game.arena_mode or game.sandbox != null) and not puppet)

## The raid's rules for movement and regeneration: in a raid, and in the admins' sandbox (which plays like one).
func raid_rules() -> bool:
	return game != null and (game.bg_mode or game.arena_mode or game.sandbox != null)

func total_str() -> int: return str_ + stats.get("str", 0)
func total_dex() -> int: return dex + stats.get("dex", 0)
func total_vit() -> int: return vit + stats.get("vit", 0)

func add_xp(v: int) -> void:
	if game != null and game.net.server and game.hero == self:
		return      # (a dedicated server's parked hero isn't anyone's)
	xp += v
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		if run != null:
			RunBuild.grow(self)     # (a run's attributes grow by themselves; its skills come from camp chests)
		else:
			stat_points += 5
		recalc()
		life = max_life
		mana = max_mana
		HolyFx.level_up(self, game.world.fx_root, global_position)
		Sfx.play("levelup")
		leveled.emit(level)
		_announce_unlocks()
	stats_changed.emit()

## Experience to finish this level: a run's own fast curve, or the game's.
func xp_to_next() -> int:
	return RunBuild.xp_for(level) if run != null else Data.xp_for_level(level)

## The skills that open at this level light up on the bar (they wait there greyed till then): say which.
func _announce_unlocks() -> void:
	if game == null or game.ui == null or not _mine():
		return
	if run != null:
		return      # (Game._on_level announces it)
	if Data.SKILLS_UNLOCKED:
		return
	var names := []
	for s in Data.skills_known(cls):
		if int(s.get("lvl", 1)) == level:
			names.append(s["name"])
	if names.is_empty():
		return
	game.ui.big_message("New skill: " + ", ".join(names))
	game.ui.refresh_skill_slots()

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
		HolyFx.level_up(self, game.world.fx_root, global_position)
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
		if rig.has_meta("bare_hands"):
			weapon_node.visible = false      # a body that fights with its hands (the Warlock's void spirit): the weapon's stats still count
		if w.get("rarity", 0) == 3 and Models.palette(w)["glow"] != null and weapon_node.visible:
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
		KnightBody.fit_helm(hm, rig)
		gear_nodes.append(hm)
	if is_wraith():
		WraithBody.rebuild_body(rig, wraith_gear())
	elif is_demon():
		DemonBody.rebuild_body(rig, demon_gear())
	elif is_warlock():
		Warlock.rebuild_body(rig, warlock_gear())
	elif is_dragon():
		pass                               # a dragon's body has no armour to show (its gear hangs off a hidden joint)
	elif is_archer():
		if not rig.has_meta("meshy"):      # the ranger's own body has nothing to rebuild
			Knight.rebuild_body(rig, ArcherBody.body_gear(knight_gear()))
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
	g["_boosted"] = boosted
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
	weapon_node.visible = (in_hand or store != "hilt") and not ClassSkills.hands_busy(self) and not rig.has_meta("bare_hands")   # the plague doctor puts his cane away to throw
	# ease into the hold (identity in the hand; the back mount's own rest)
	var k := 1.0 - exp(-delta * 16.0)
	weapon_node.transform = weapon_node.transform.interpolate_with(Transform3D.IDENTITY, k)

## The hand that holds the weapon: the right, unless the class holds it its own way (the ranger's bow, in his left).
func _weapon_hand(J: Dictionary) -> Node3D:
	var own := ClassSkills.weapon_hand(self, J)
	return own if own != null else J["grip_r"]

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
	end_channel()
	target = null
	_set_goal(p, direct)

# ---------------------------------------------------------------- aiming
## The mouse pointer is the source of truth for aim, Path of Exile style: WASD moves, the pointer
## aims, and the two are independent, so he can run one way and cast another. Facing never decides
## where anything goes; the body only turns to show it (see _process). Each skill says in
## Data.SKILLS how it uses the pointer:
##   "point"  lands on the pointer (each skill still clamps to its own range: Volley, Grasp, Hurl...; an area
##            skill, "aoe" in its data, is clamped here to its "range" too, so Aiming shows the spot it lands on)
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
		if e.pvp_hidden:
			continue     # a player hidden in the Plague Doctor's fog: no aim help onto him
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
			if s.has("aoe"):
				return _in_range(at, float(s.get("range", 0.0)))
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

## An area skill's spot ("aoe" in its data): the pointer, or the point on its line at the skill's range when it is
## further (where its rules put it; Aiming shows the same spot before the click).
func _in_range(at: Vector3, rng: float) -> Vector3:
	var to := (at - global_position) * Vector3(1, 0, 1)
	if rng <= 0.0 or to.length() <= rng:
		return at
	var p := global_position + to.limit_length(rng)
	p.y = game.world.height_at(p.x, p.z) if game != null and game.world != null else at.y
	return p

## Swing toward a point without needing a target (Space). Works while moving.
func free_attack(aim: Vector3) -> void:
	Hero.striker = self          # (whoever acts now strikes: a sandbox stand-in never takes its own hero's blows)
	break_invis()
	if not can_act():
		return
	if ClassSkills.attack(self, aim, false):
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
	Hero.striker = self          # (whoever acts now strikes: a sandbox stand-in never takes its own hero's blows)
	break_invis()
	if dead or charge_t >= 0.0 or channel_t >= 0.0 or daze_t > 0.0:
		return
	if ClassSkills.attack(self, aim, keep_target):
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
	var slam := atk_leap >= 0.0
	var d: float = (smoothstep(0.0, 1.0, f1) - smoothstep(0.0, 1.0, f0)) * (atk_leap if slam else float(L[2]))
	if d <= 0.0:
		return
	# along the aim taken when the swing started, not the body's facing
	var fwd := aim_dir()
	if slam:
		# a skill's leap (Holy Slam's) to the spot aimed at, sliding round anything solid on the way
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
	# a class may deal its swing its own way (the plague doctor's cane: each blow leaves its mark, decided where his
	# rules run)
	if ClassSkills.swing(self, atk_style):
		return
	if not decides():
		_send_swing(null)
		return
	_swipe_blows(atk_style, aim_dir())

## A weapon swing whose blows the match server decides (this hero's skills run there: ServerRules): its game sends
## the swing, and the server's copy of it strikes with its own positions (server_swing).
func _send_swing(tg) -> void:
	var ids: PackedInt64Array = SkillFx.encode(game.net, {"t": [tg] if is_instance_valid(tg) else []})["t"]
	game.net.send_skill_make("attack", "swing", {"style": atk_style, "fwd": aim_dir(), "t": ids, "at": global_position})

## Match server: a player's swing, struck by its copy here (ServerRules.received "attack" "swing"), from where their
## game swung it (`at`) when that's near where the server has them (the copy lags a step behind them). False when it
## doesn't add up (a style it can't swing, faster than it swings, too far from where the server has them).
func server_swing(style: String, fwd: Vector3, tg, at = null) -> bool:
	var now := Time.get_ticks_msec()
	if style.length() > 16 or now - _last_swing_ms < 150:
		return false
	if at is Vector3:
		if (at as Vector3).distance_to(global_position) > SWING_SLACK:
			return false
		global_position = at
	_last_swing_ms = now
	fwd = (fwd * Vector3(1, 0, 1)).normalized() if fwd.length() > 0.01 else facing()
	if style.begins_with("swipe"):
		_swipe_blows(style, fwd)
	else:
		_plain_blow(tg, fwd)
	return true

var _last_swing_ms := 0
## How far a swing's spot may be from where the match server has the player (its copy is a few frames behind them).
const SWING_SLACK := 4.0

func _swipe_blows(style: String, fwd: Vector3) -> void:
	var fin := style == "swipe3"
	var rng := reach() + (1.0 if fin else 0.55)
	var arc := 181.0 if fin else 70.0
	var mult := 1.0 if style == "swipe1" else (1.15 if style == "swipe2" else 1.7)
	var any := false
	var struck := []
	for e in game.enemies_near(global_position, rng + 1.5):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		if to.length() - e.radius > rng or ServerRules.friend(self, e):
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(arc)):
			_hit_enemy(e, mult, 0.9 if fin else 0.2)
			fx("attack", "hit", {"p": e.global_position + Vector3(0, 1.1 * e.height, 0), "c": trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5)})
			any = true
			struck.append(e)
	if fin:
		fx("attack", "finisher", {"r": rng, "x": any})
		if any and _mine():
			game.hitstop(0.06)

func _face_smooth(d: Vector3, delta: float) -> void:
	d.y = 0
	if d.length() > 0.01:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-d.x, -d.z), clampf(delta * 14.0, 0.0, 1.0))

func cmd_target(t) -> void:
	if dead or charge_t >= 0.0:
		return
	end_channel()
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
		end_channel()
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
	if sk.is_empty() or dead or charge_t >= 0.0 or channel_t >= 0.0:
		return false
	if atk_t >= 0.0 and atk_skill != "":
		return false
	return (not skill_locked(sk) or game.test_allskills) and cds.get(id, 0.0) <= 0.0 and mana >= skill_cost(id)

func arena_waiting() -> bool:
	return not puppet and game != null and game.arena_mode and game.arena_state.get("phase", "waiting") != "fight"

func can_act() -> bool:
	return not arena_waiting() and not dead and atk_t < 0.0 and charge_t < 0.0 and channel_t < 0.0

func use_skill(id: String, aim: Vector3) -> bool:
	if arena_waiting(): return false
	var t0 := FxTiming.t()
	var r := _use_skill(id, aim)
	FxTiming.done(t0, "use_skill " + id)
	return r

func _use_skill(id: String, aim: Vector3) -> bool:
	Hero.striker = self          # (whoever acts now strikes: a sandbox stand-in never takes its own hero's blows)
	break_invis()
	if dead or charge_t >= 0.0 or daze_t > 0.0:
		return false
	if atk_t >= 0.0 and atk_skill != "" and ClassSkills.recast(self, id):
		return true
	if atk_t >= 0.0 and atk_skill != "":
		return false
	if skill_denied(id):
		return false
	# the class's own checks (a foe to latch onto or seize, ...) before anything is spent
	if not ClassSkills.can_cast(self, id, aim):
		return false
	# cancel a basic swing (or a Drain Life channel) so the skill fires right away
	end_channel()
	atk_t = -1.0
	impact_done = true
	mana -= skill_cost(id)
	cds[id] = skill_cd(id)
	if run != null:
		RunTalents.on_cooldown(self, id)
	atk_aim = aim
	_face(aim - global_position)
	# the class's skills script starts it (ClassSkills.of: KnightSkills, Wraith, Demon, ...)
	ClassSkills.cast(self, id, aim)
	SkillSpec.apply_timing(self, id)      # (a "use" in the skill's data sets its length)
	# the cast itself, seen by everyone (SkillFx: the class draws it, or the default puff shows it)
	fx(id, "cast", {"p": atk_aim})
	return true

## Is the skill kept from casting by its lock, its cooldown or its mana? Tells his player why. A cast checks this, and
## so does arming an area skill for click to cast (Aiming).
func skill_denied(id: String) -> bool:
	var sk: Dictionary = {}
	for s in skill_list() + Data.shared_skills():
		if s["id"] == id:
			sk = s
	if sk.is_empty() or (skill_locked(sk) and not game.test_allskills):
		if _mine():
			game.ui.message(("%s isn't learned yet" % sk.get("name", id)) if run != null else ("Requires level %d" % sk.get("lvl", 1)), Color(1, 0.4, 0.3))
		return true
	if cds.get(id, 0.0) > 0.0:
		if _mine():
			game.ui.message("%s is recharging" % sk["name"], Color(0.8, 0.8, 0.8))
		return true
	if mana < skill_cost(id):
		if _mine():
			game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
		Sfx.play("deny")
		return true
	return false

func drink(slot: int) -> void:
	if dead or slot < 0 or slot > 3 or belt[slot] == null:
		return
	var it: Dictionary = belt[slot]
	var b: Dictionary = Data.BASES[it["base"]]
	if b.has("heal"):
		heal_pool += b["heal"] * (1.0 + level * 0.06) * (1.0 + float(stats.get("pot", 0)) / 100.0)
	if b.has("mana"):
		mana_pool += b["mana"] * (1.0 + level * 0.05)
	if b.has("invis"):
		invis_t = float(b["invis"])
		hidden_t = maxf(hidden_t, invis_t)
		Sfx.play("ice_shatter", -10.0, 0.6)
		if _mine():
			game.ui.message("Unseen for %d seconds" % int(invis_t), Color(0.7, 0.6, 1.0))
	if b.has("rejuv"):
		life = minf(max_life, life + max_life * b["rejuv"])
		mana = minf(max_mana, mana + max_mana * b["rejuv"])
	# a run's consumables (Data.BASES): elixirs (timed buffs), salves, flasks thrown at the pointer, wards, tomes
	if b.has("buff") and run != null:
		var bfx: Dictionary = b["buff"].duplicate()
		if b.has("regen_pct"):
			bfx["regen"] = max_life * float(b["regen_pct"]) / 100.0
		RunTalents.buff(self, "item_" + str(it["base"]), bfx, float(b["secs"]))
		if _mine():
			game.ui.message("%s: %s" % [b["name"], b.get("desc", "")], b["color"])
	if b.has("bomb"):
		RunTalents.throw_flask(self, str(it["base"]), cursor)
	if b.has("ward_pct") and run != null:
		RunTalents.buff(self, "item_ward", {"ward_bonus": float(b["ward_pct"])}, 20.0)
		ward = ward_max
		Fx.ring(game.world.fx_root, global_position, 1.6, b["color"], 0.6)
	if b.has("xp_level") and run != null:
		add_xp(int(RunBuild.xp_for(level) * float(b["xp_level"])))
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
	if not pvs.is_empty():
		atk_dur *= PvpStatus.act_mult(self)       # harried (PvP)
	impact_done = false
	atk_leap = -1.0
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
	var r := ClassSkills.reach(self)
	return r if r > 0.0 else 1.7

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
	var run_k: float = float(RunBuild.CLASS_POWER.get(cls, 1.0)) if run != null else 1.0
	return (1.0 + (talent("dmg") + talent("dmg:" + id)) / 100.0) * pace_mult(id) * float(Data.skill_def(id).get("power", 1.0)) * run_k

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
	Hero.striker = self          # (whoever acts now strikes: a sandbox stand-in never takes its own hero's blows)
	if not is_instance_valid(e) or e.dead:
		return
	combat_t = 0.0
	if src == "":
		src = atk_skill if atk_skill != "" else "attack"
	if run != null:
		mult *= RunTalents.hit_mult(self, e, src)
	var r := roll_damage(mult * dmg_mult(src))
	if flat > 0.0:
		r["phys"] += flat * buff_mult() * dmg_mult(src) * (2.0 if r["crit"] else 1.0)
	var dealt: float = e.take_damage(r["phys"], r["fire"], global_position, knock, r["crit"])
	if puppet and game.net.server:
		game.net.tell_dealt(self, e.global_position, dealt, r["crit"])      # (the number on the player's screen)
	if run != null:
		RunTalents.on_hit(self, e, dealt, r["crit"], src)
		ClassSkills.struck(self, e, src)      # a class's own mark on what its blows strike (the Knight's Holy Brands)
		if is_instance_valid(e) and e.has_meta("deathmark") and e.get_meta("deathmark").get("h") == self:
			e.get_meta("deathmark")["stored"] = float(e.get_meta("deathmark")["stored"]) + dealt      # (Death Mark's store)
	if ls > 0.0:
		gain_life(dealt * ls / 100.0)
	_item_effects(e, dealt, src)
	if _mine():
		if r["crit"]:
			game.hitstop(0.05)
		game.add_shake(0.15 if not r["crit"] else 0.3)

const BURN_SECS := 3.0

func break_invis() -> void:
	if invis_t > 0.0:
		invis_t = 0.0
		hidden_t = 0.0

## The uniques' effects on a blow (Data.ITEM_EFFECTS): burning and chilling on weapon blows, life on a kill.
func _item_effects(e, dealt: float, src: String) -> void:
	if not is_instance_valid(e) or dealt <= 0.0:
		return
	if src == "attack":
		var burn := float(stats.get("burn", 0))
		if burn > 0.0 and not e.dead:
			e.ignite(dealt * burn / 100.0, 3.0)
		var chill := float(stats.get("chill", 0))
		if chill > 0.0 and not e.dead:
			e.chill(chill / 100.0, 2.0)
	var kh := float(stats.get("kill_heal", 0))
	if kh > 0.0 and e.dead:
		gain_life(max_life * kh / 100.0)

func take_hit(dmg: float, from: Vector3, kind: String = "melee", element: String = "phys") -> void:
	if dead:
		return
	combat_t = 0.0
	if puppet:
		if game.net.is_host:
			game.net.hit_player(peer_id, dmg, from, kind, element)
		return
	if dmg > 0.0:
		break_invis()
	if kind == "burn":
		# set alight by another player: `dmg` is the burn a second, for BURN_SECS (ticks as fire, resist counts)
		burn_dps = maxf(burn_dps if burn_t > 0.0 else 0.0, minf(dmg, 80.0))
		burn_t = BURN_SECS
		if Hero.striker != null and Hero.striker != self:
			burn_by = Hero.striker
		return
	if (game.test_immortal and _mine()) or phased:
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
	dmg = ClassSkills.taken(self, dmg)     # (the Plague Doctor's Transfusion soaks part of it into his tanks)
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
		if _mine():
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
	dmg = ClassSkills.absorb(self, dmg)      # a class's own ward (the Warlock's shield; the Demon's Crucible)
	if ward > 0.0:
		var soak := minf(ward, dmg)
		ward -= soak
		dmg = maxf(0.0, dmg - soak)
		if ward <= 0.0:
			Sfx.play("ice_shatter", -8.0, 1.4)
	life -= dmg
	hit_t = 1.0
	if run != null:
		RunTalents.struck(self, dmg, from)
		if life <= 0.0 and RunTalents.save_from_death(self):
			life = maxf(life, 1.0)
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
		if _mine():
			game.add_shake(0.2)
	show_damage(dmg)
	if _mine():
		game.ui.flash_damage()
	# Doug in his clown car is unstoppable: blows land, their stuns and slows don't
	if ClassSkills.unstoppable(self) and kind in ["sweep", "quake", "chill", "freeze", "shock", "root", "slip"]:
		kind = "melee"
	# the Hollow Sloths' blows: thrown back, stunned, chilled, frozen solid, shocked
	match kind:
		"sweep":
			var away := global_position - from
			away.y = 0
			if away.length() > 0.01:
				shove = away.normalized() * 11.0
		"quake":
			daze_t = maxf(daze_t, 1.1 * cc_k())
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Stunned", Color(0.95, 0.8, 0.5))
		"chill":
			chill_t = maxf(chill_t, 2.5 * cc_k())
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Chilled", Color(0.55, 0.85, 1.0))
		"freeze":
			daze_t = maxf(daze_t, 1.8 * cc_k())
			chill_t = maxf(chill_t, 4.0 * cc_k())
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Frozen", Color(0.6, 0.9, 1.0))
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 1.0, 0), Color(0.8, 0.95, 1.0), 30, 1.5, 0.15, 1.0, true, -1.0)
		"slip":
			# a banana peel (Doug's): down for a moment, sliding on the way he was going
			if not ClassSkills.unstoppable(self):
				daze_t = maxf(daze_t, 0.7 * cc_k())
				var dir := facing()
				shove = dir * 6.0
				Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Slipped!", Color(1.0, 0.9, 0.3))
		"pied":
			pied_t = 1.5 * cc_k()
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Pied!", Color(1.0, 0.97, 0.88))
			if _mine() and game.ui.has_method("pie_face"):
				game.ui.pie_face(1.5)
		"root":
			daze_t = maxf(daze_t, 1.2 * cc_k())
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Rooted", Color(0.55, 1.0, 0.4))
		"shock":
			daze_t = maxf(daze_t, 0.45 * cc_k())
			Fx.number(game.world.fx_root, global_position + Vector3(0, 2.6, 0), "Shocked", Color(0.8, 0.6, 1.0))
	if life <= 0.0:
		life = 0.0
		dead = true
		Dodge.cancel(self)
		PvpStatus.clear(self)
		ClassSkills.died(self)
		SkillFx.clear(self)
		dead_t = 0.0
		atk_t = -1.0
		Sfx.play(_voice("death"), -2.0)
		died.emit()
	stats_changed.emit()

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	var t0 := FxTiming.t()
	_process_body(delta)
	FxTiming.done(t0, "hero process%s" % (" (puppet)" if puppet else ""))

func _process_body(delta: float) -> void:
	if game == null or game.world == null or game._busy:
		return
	anim_time += delta
	if puppet:
		_puppet_process(delta)
		return
	Hero.striker = self
	if run != null:
		RunTalents.tick(self, delta)
	for k in cds.keys():
		cds[k] = maxf(0.0, cds[k] - delta)
	buff_t = maxf(0.0, buff_t - delta)
	dash_t = maxf(0.0, dash_t - delta)
	invis_t = maxf(0.0, invis_t - delta)
	_show_invis(invis_t > 0.0, _mine())
	if burn_t > 0.0 and not dead:
		burn_t -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			var l0 := life
			take_hit(burn_dps * 0.5, global_position, "burnt", "fire")
			if game.sandbox != null and life < l0:
				game.sandbox.note_hit(burn_by, self, l0 - life)     # (the burn's ticks were done but never counted)
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
		if not pvs.is_empty() and PvpStatus.strength(self, "blight") >= 3.0:
			h *= 0.6     # Feverish (the Plague Doctor's Fever, PvP): healing -40%
		life = minf(max_life, life + h)
	if mana_pool > 0.0:
		var m := minf(mana_pool, delta * 20.0)
		mana_pool -= m
		mana = minf(max_mana, mana + m)
	if not raid_rules():            # (no life regeneration in the crypt, nor in the sandbox: potions and care)
		life = minf(max_life, life + regen * delta)
	mana = minf(max_mana, mana + (1.0 + ene * 0.06) * delta)

	var want_block := blocking and atk_t < 0.0 and charge_t < 0.0
	block_amt = move_toward(block_amt, 1.0 if (want_block or block_flash > 0.0) else 0.0, delta * 9.0)
	var vel := Vector3.ZERO
	if arena_waiting():
		direct_dir = Vector3.ZERO
		moving = false
		path = PackedVector3Array()
	var wants_move := direct_dir.length() > 0.1 or (moving and not path.is_empty())
	# stamina: sprint drains it, resting refills it; running dry leaves you winded
	running = sprint and wants_move and not exhausted and block_amt < 0.5 and charge_t < 0.0
	combat_t += delta
	free_roll_t = maxf(0.0, free_roll_t - delta)
	if ward_max > 0.0 and combat_t > COMBAT_SECS:
		ward = minf(ward_max, ward + ward_max * 0.25 * delta)     # the ward back over 4 s out of combat
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
			if _mine():
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
	var speed := 4.8 * (1.0 + frw / 100.0 + (float(stats.get("dash", 0)) / 100.0 if dash_t > 0.0 else 0.0)) * (Battlegrounds.MOVE_MULT if raid_rules() else 1.0)
	speed *= ClassSkills.pace(self)      # (a class's own pace: the archer beside his wolf, Doug in his clown car)
	if running:
		speed *= 1.6
	if phased:
		speed *= 1.4
	if block_amt > 0.5:
		speed *= 0.42
	if atk_t >= 0.0:
		# everyone slows a little mid-swing; a class may step its own way (the archer, slowly with the bow drawn)
		var ap := ClassSkills.attack_pace(self)
		speed *= ap if ap > 0.0 else 0.72
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
	if not cc.is_empty() or not pvs.is_empty():
		speed *= PvpStatus.update(self, delta)     # the Demon's and the Plague Doctor's statuses (snare = 0)
		if PvpStatus.held(self):
			speed = 0.0
	if not pvs.is_empty() or pvs_shown > 0 or cc.has("slow"):
		PvpStatusFx.sync(self, PvpStatusFx.bits_of(self), PvpStatusFx.blight_of(self))

	if roll_t >= 0.0:
		vel = Dodge.step(self, delta)
	elif charge_t >= 0.0:
		ClassSkills.dash(self, delta)      # a dash (the Knight's Charge) moves him in place of his walking
	else:
		if atk_t >= 0.0:
			_update_attack(delta)
		if channel_t >= 0.0:
			ClassSkills.channel(self, delta)       # a held channel (Drain Life)
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
					# measured from his body's edge, with a little slack: a stall or the keeper's own footprint stops a
					# big hero (or one coming from the side) 1.6-1.8 m out of a 1.5 m reach (tools/npc_reach_test.gd)
					need = target.radius + radius + 0.35
				elif target is GroundItem:
					need = 1.2
				if d <= need:
					if direct_dir.length() < 0.1:
						moving = false
						path = PackedVector3Array()
					if target is Enemy:
						# left-click on a foe: the sword combo; held, it keeps chaining at him
						var held: bool = bot_hold if bot else game.lmb_held
						if atk_t < 0.0 or held:
							swipe_attack(tp, held)
							if atk_t >= 0.0 and not held:
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
		elif charge_t < 0.0 and channel_t < 0.0:
			_face(vel)
		move_amt = move_toward(move_amt, stride, delta * 6.0)
		# super speed glides: the legs only go a little faster
		var anim_v: float = vel.length() * (1.6 / game.TEST_FAST if game.test_fast else 1.0)
		phase += delta * anim_v * 2.9 / maxf(move_amt, 0.6) * (float(rig.get_meta("stride")) if rig.has_meta("stride") else 1.0)
		_snow_step()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 6.0)
		if atk_t < 0.0 and charge_t < 0.0 and channel_t < 0.0 and block_amt > 0.5:
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
	elif channel_t >= 0.0:
		# both hands thrust out, holding the beam
		st["atk"] = 0.6
		st["style"] = "cast"
	if not puppet:
		carry.update(self, delta)
		st.merge(carry.anim_state(), true)
		_carry_weapon(delta)
		ClassSkills.pose(self, st, delta)   # (a class's own idle: now and then the plague doctor peers at a vial)
	if Enemy.server_nopose:
		return
	Anim.pose(rig, st)
	ClassSkills.posed(self, st)
	last_pose = st
	_hover()
	Dodge.pose(self, delta)
	SkillFx.update(self, delta)
	_breathe(delta)
	_apply_shield_pose()
	# no sword-swing streak off a bow, nor off the Wraith's and the Demon's skills (their clips, not weapon swings)
	# (the Plague Doctor's skills put the cane away too: thrown vials, the censer, the reliquary)
	_update_trail(((atk_t >= 0.0 and not ((is_wraith() or is_demon() or is_doug() or cls == "plague") and atk_skill != "")) or charge_t >= 0.0) and not has_bow() and not is_dragon())

## The Wraith floats a hand's breadth off the ground, bobbing slowly and leaning into motion.
func _hover() -> void:
	if is_demon():
		DemonBody.animate(rig, anim_time, move_amt, self)
		return
	if not is_wraith() or dead or _floats():
		return
	rig.position.y = 0.2 + sin(anim_time * 2.1) * 0.05
	rig.rotation.x = -move_amt * 0.12

## The Wraith's mocap body floats by itself (KnightMocapRig's float mode: hover, lean, the sinking death).
func _floats() -> bool:
	return (is_wraith() or (is_warlock() and rig != null and rig.has_meta("spirit"))) and rig != null and rig.has_method("sync_pose")

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
	boosted = bool(equipment.get("_boosted", false))
	equipment.erase("_boosted")
	if c != cls:
		set_class(c)
	for s in Items.EQUIP_SLOTS:
		if not equipment.has(s):
			equipment[s] = null
	refresh_gear()

## Invisibility drawn: on his own screen he's a ghost of himself; on a partner's he's gone, but for a faint shimmer
## within 4 m. (The bodies' materials vary by class, so it's done with each mesh's transparency.)
var _invis_shown := -1.0
func _show_invis(on: bool, own: bool) -> void:
	var want := 0.0
	if on:
		want = 0.65
		if not own and game != null and game.hero != null:
			want = 0.9 if game.hero.global_position.distance_to(global_position) < 4.0 else 1.0
	if is_equal_approx(want, _invis_shown) or rig == null:
		return
	_invis_shown = want
	for m in rig.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).transparency = want
	# the Compatibility renderer (the browser, Safe Mode) ignores transparency: there someone else's unseen hero is hidden
	var compat: bool = game != null and not game.is_forward()
	rig.visible = not (on and not own and (want >= 1.0 or compat))
	if light:
		light.visible = want < 1.0
	for c in get_children():
		if c is Label3D:
			(c as Label3D).visible = want < 0.95

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
	net_buff = int(p[14]) & 1 != 0
	net_invis = int(p[14]) & 2 != 0
	net_pvs_bits = (int(p[14]) >> 2) & 15      # the PvP statuses on him (Net._flags), shown by PvpStatusFx
	net_pvs_blight = (int(p[14]) >> 6) & 3
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
	visible = false
	net_has = false
	SkillFx.clear(self)
	for b in beasts:
		if is_instance_valid(b):
			b.queue_free()
	beasts.clear()

func _puppet_process(delta: float) -> void:
	visible = net_has and not fog_hidden
	if not net_has:
		return
	var k := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(net_pos, k)
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	aura.emitting = net_buff and not net_invis
	_show_invis(net_invis, false)
	if net_pvs_bits != 0 or net_pvs_blight != 0 or pvs_shown > 0:
		PvpStatusFx.sync(self, 0 if dead else net_pvs_bits, 0 if dead else net_pvs_blight)    # PvP statuses on him
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
	if game.net.server:
		ServerRules.update(self, delta)      # (a player's skills that run on the server: its arrows, rains, sigils)
	if Enemy.server_nopose:
		return
	Anim.pose(rig, st)
	ClassSkills.posed(self, st)
	_hover()
	Dodge.pose(self, delta)
	ClassSkills.puppet_update(self, delta)
	SkillFx.update(self, delta)
	_apply_shield_pose()
	# a partner's swing in his class's colour (white before), and none on Doug's throws and tricks nor while the
	# Plague Doctor's hands are on a skill
	if trail_pts.is_empty():
		trail_col = ClassSkills.trail_color(cls, "")
	_update_trail(atk_t >= 0.0 and not has_bow() and not is_dragon() and not (is_doug() and str(st.get("style", "")) in Doug.SKILL_STYLES) and not ClassSkills.hands_busy(self))

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
	if swipe or (atk_leap >= 0.0 and SWIPE_LUNGE.has(atk_style)):
		_swipe_lunge(a0, a)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact()
	if swipe and swipe_q and a >= 0.68:
		atk_t = -1.0
		_swipe(swipe_aim, swipe_keep)
		return
	if atk_t >= atk_dur:
		var done_style := atk_style
		var done_skill := atk_skill
		atk_t = -1.0
		atk_skill = ""
		if done_skill != "":
			ClassSkills.stage_done(self, done_style, done_skill)     # (a skill of several clips: the Demon's)
		if swipe and atk_style == "swipe3":
			swipe_n = 0

func _impact() -> void:
	var t0 := FxTiming.t()
	_impact_body()
	FxTiming.done(t0, "impact " + atk_style)

func _impact_body() -> void:
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
			if not decides():
				_send_swing(atk_target)
			else:
				_plain_blow(atk_target, fwd)
	stats_changed.emit()

## A plain weapon blow: on the foe it was swung at if it's still in reach, else the nearest foe in a frontal arc.
func _plain_blow(tg, fwd: Vector3) -> void:
	if is_instance_valid(tg) and tg is Enemy and not tg.dead and not ServerRules.friend(self, tg):
		var d := Vector2(tg.global_position.x - global_position.x, tg.global_position.z - global_position.z).length()
		if d <= reach() + tg.radius + 0.7:
			_hit_enemy(tg, 1.0, 0.15)
			fx("attack", "hit", {"p": tg.global_position + Vector3(0, 1.1 * tg.height, 0)})
			return
	# free swing: strike the nearest foe in a frontal arc
	var best = null
	var bd := 99.0
	for e in game.enemies_near(global_position, reach() + 1.6):
		if ServerRules.friend(self, e):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var dd: float = to.length() - e.radius
		if dd <= reach() + 0.4 and (to.length() < 0.4 or fwd.dot(to.normalized()) > cos(deg_to_rad(60.0))) and dd < bd:
			bd = dd
			best = e
	if best != null:
		_hit_enemy(best, 1.0, 0.15)
		fx("attack", "hit", {"p": best.global_position + Vector3(0, 1.1 * best.height, 0)})

# ---------------------------------------------------------------- a held channel
## The channel lets go (a move, a click, another skill, a dodge): its class's script ends it (ClassSkills.end_channel).
func end_channel() -> void:
	ClassSkills.end_channel(self)

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
	// clamped: the strip's interpolation can dip a hair below 0 at the hilt edge, and pow() of a negative is NaN,
	// which the framebuffer shows as black specks along the trail
	float age = clamp(UV.x, 0.0, 1.0);
	float edge = clamp(UV.y, 0.0, 1.0);
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
	if trail.mesh == null: return # No sword-trail draw mesh in a headless world.
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
	PvpStatus.clear(self)
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
	if run != null:
		return _run_take(it)
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

## A run character has no backpack: consumables go into the belt's four slots (stacks of RunBuild.STACK), gear is
## worn when its slot is empty (a better piece found later is swapped through Game.run_swap, which leaves the old one
## on the ground), and gold, rings, amulets and materials aren't taken at all.
func _run_take(it: Dictionary) -> bool:
	var b: Dictionary = Data.BASES.get(str(it.get("base", "")), {})
	if b.is_empty() or str(b["slot"]) in ["gold", "ring", "amulet", "belt", "material", "resource", "tool"]:
		return false
	if str(b["slot"]) == "potion":
		var n := _stack_into(belt, it, RunBuild.STACK, int(it.get("count", 1)), true)
		it["count"] = n
		stats_changed.emit()
		return n <= 0
	if not RunBuild.wearable(it, cls) or equipment.get(RunBuild.gear_slot(it)) != null:
		return false
	equipment[RunBuild.gear_slot(it)] = it
	Sfx.play("equip")
	recalc()
	refresh_gear()
	stats_changed.emit()
	return true

## Wear a found piece in a run, handing back what it replaces (null for an empty slot) for the ground.
func run_wear(it: Dictionary):
	var slot := RunBuild.gear_slot(it)
	var old = equipment.get(slot)
	equipment[slot] = it
	Sfx.play("equip")
	recalc()
	refresh_gear()
	stats_changed.emit()
	return old

## A fresh run character (a Battlegrounds lobby's class choice): level 0, the class's weapon and plain armour, the
## primary attack and no skills, passives, gold or backpack, two health potions and a mana potion.
func start_run() -> void:
	new_character()
	run = RunBuild.new()
	level = 0
	gold = 0
	talents = {}
	tfx = {}
	inventory = []
	inventory.resize(40)
	for s in equipment.keys():
		if not (s in RunBuild.GEAR):
			equipment[s] = null
	for s in RunBuild.GEAR:
		var it = equipment.get(s)
		if it != null:
			it["req"] = 0
	belt = [Items.potion("hp_potion"), Items.potion("mp_potion"), null, null]
	belt[0]["count"] = 2
	binds = {}
	_check_binds()
	recalc()
	life = max_life
	mana = max_mana
	refresh_gear()
	if game and game.ui and _mine():
		game.ui.refresh_skill_slots()

## A run's skill or passive changed (a camp chest's choice): the effects and the bar follow.
func run_changed() -> void:
	_check_binds()
	_talents_changed()

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
	if it.has("unique") and Data.UNIQUES.has(it["unique"]):
		only = str(Data.UNIQUES[it["unique"]].get("cls", only))     # a class unique (Blaine's overhaul)
	if only != "" and only != cls:
		game.ui.message("Only the %s can use that" % Data.CLASSES[only]["name"], Color(1, 0.4, 0.3))
		Sfx.play("deny")
		return
	if int(it.get("req", 1)) > level and run == null:
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
		"equipment": equipment, "inventory": inventory, "belt": belt, "show_helm": show_helm, "binds": binds, "binds_v": 2, "talents": talents, "boss_luck": boss_luck, "boosted": boosted}.merged({"run": run.to_dict()} if run != null else {})

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
	boss_luck = (d.get("boss_luck", {}) as Dictionary).duplicate() if d.get("boss_luck") is Dictionary else {}
	boosted = bool(d.get("boosted", false))
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
	# items from before the items rework are rebuilt once under the new rules (Items.upgrade; nothing is deleted)
	Items.upgrade_all([equipment, inventory, belt])
	run = RunBuild.from_dict(d["run"]) if d.get("run") is Dictionary else null
	binds = (d.get("binds", {}) as Dictionary).duplicate() if d.get("binds") is Dictionary else {}
	Wraith.migrate_binds(binds)
	Demon.migrate_binds(binds)
	Plague.migrate_binds(binds)
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
	if run != null:
		talents = {}
	tfx = run.fx(cls) if run != null else Talents.sum(cls, talents)
	if game and game.ui and _mine():
		game.ui.refresh_skill_slots()
	recalc()
	life = max_life
	mana = max_mana
	refresh_gear()
