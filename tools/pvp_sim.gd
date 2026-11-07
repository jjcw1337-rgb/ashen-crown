extends SceneTree
## The Battlegrounds' PvP balance (Blaine's progression overhaul): every class at
## levels 1, 5, 10 and 20, fresh (its starting weapon, nothing else) and fully geared (rare gear of its level in every
## slot), under the raid's gear rules (Hero.pvp_scaled). For each it measures, in real play:
##   ehp  life against a player's blows (life x (120 + armor) / 120; elements: life / (1 - res))
##   dps  damage a second into a standing foe with no armour, the bot using its skills as they come off cooldown and
##        its mana allows (dots, minions and all), times Battlegrounds.PVP_MULT
## then duels them on paper (Monte Carlo: each second a player lands what they swing with chance `skill`, +-30%):
##   equal skill (0.75 each): geared vs fresh of the same class must win >= 80%
##   a big skill gap (fresh at 0.9, geared at 0.45): fresh must win >= 35%
##   classes at a checkpoint (equal gear, equal skill): no pairing past 70/30
##   godot --headless --fixed-fps 30 --path . -s tools/pvp_sim.gd -- [classes=knight,doug] [levels=1,20] [out=x.json]
## Lines [PVP] are the measurements, [PVP-DUEL] the duels, [PVP-FLAG] what misses a target.
const CLASSES := ["knight", "wraith", "demon", "warlock", "archer", "plague", "doug"]
const LEVELS := [1, 5, 10, 20]
const FIGHT_S := 20.0
const POINTS := {"knight": {"str": 2, "dex": 1, "vit": 2}, "wraith": {"str": 1, "dex": 2, "vit": 2}, "demon": {"str": 2, "vit": 2, "ene": 1},
	"warlock": {"str": 1, "vit": 2, "ene": 2}, "archer": {"dex": 2, "vit": 2, "str": 1}, "plague": {"dex": 1, "vit": 2, "ene": 2},
	"doug": {"str": 2, "dex": 1, "vit": 2}}
var g
var classes: Array = CLASSES
var levels: Array = LEVELS
var out_path := ""
var skip: Array = []    # skip=id,id: the bot leaves those skills alone (to see what one skill adds)
var moving := false     # "moving": the foe strafes round a 4 m circle at 3.2 m/s like a player, so clouds, traps and
						# ground effects must be aimed and kept up, and melee has to keep up with him
var rows := {}      # "cls:lvl:gear" -> {ehp, dps, life, armor}
var flags := 0

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("classes="):
			classes = Array(a.substr(8).split(","))
		elif a.begins_with("levels="):
			levels = Array(a.substr(7).split(",")).map(func(x): return int(x))
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("skip="):
			skip = Array(a.substr(5).split(","))
		elif a == "moving":
			moving = true
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "knight")
	g.ui.close_all()
	await g.travel(0, "sandbox", "start")
	while g._busy:
		await frames(5)
	g.test_immortal = true
	for cls in classes:
		for lvl in levels:
			for gear in ["fresh", "geared"]:
				await _measure(cls, lvl, gear)
	_duels()
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, " "))
	print("[PVP] done, %d flagged" % flags)
	quit()

func _setup(cls: String, lvl: int, geared: bool) -> void:
	var h = g.hero
	if h.dead:
		h.respawn(h.global_position)
	h.set_class(cls)
	h.new_character()
	h.pvp_force = true
	h.level = lvl
	var pts := (lvl - 1) * 5
	var w: Dictionary = POINTS[cls]
	var wsum := 0
	for k in w:
		wsum += int(w[k])
	for k in w:
		var n := int(pts * int(w[k]) / float(wsum))
		match k:
			"str": h.str_ += n
			"dex": h.dex += n
			"vit": h.vit += n
			"ene": h.ene += n
	if geared:
		var rng := RandomNumberGenerator.new()
		for slot in Items.EQUIP_SLOTS:
			if slot == "shield" and cls != "knight":
				continue
			var base: String = g._boost_base(slot, h, lvl) if slot != "shield" else ("kite_shield" if lvl >= 6 else "buckler")
			if base == "" or not Data.BASES.has(base):
				continue
			rng.seed = hash(slot) + lvl
			seed(hash(slot) + lvl)
			h.equipment[slot] = Items.generate(base, lvl, 2, rng)
	h.talents = Talents.auto_build(cls, lvl - 1)
	h._talents_changed()
	h.recalc()
	h.life = h.max_life
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.refresh_gear()

func _measure(cls: String, lvl: int, gear: String) -> void:
	var h = g.hero
	_setup(cls, lvl, gear == "geared")
	await frames(10)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await frames(2)
	var at: Vector3 = g.world.free_spot_near(h.global_position + Vector3(0, 0, -1.6), 0.5)
	var foe = g.spawn_enemy("zombie", at, lvl)
	foe.max_life = 1.0e7
	foe.life = 1.0e7
	foe.armor = 0
	foe.speed = 0.0
	foe.scripted = 999.0
	await frames(2)
	var t := 0.0
	var centre: Vector3 = foe.global_position + Vector3(0, 0, -3.0)
	while t < FIGHT_S:
		await process_frame
		t += 1.0 / 30.0
		if moving:
			var a := t * 3.2 / 4.0
			var p := centre + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)
			p.y = g.world.height_at(p.x, p.z)
			foe.global_position = p
		_bot(foe)
	var dealt: float = 1.0e7 - foe.life
	var dps: float = dealt / FIGHT_S * Battlegrounds.PVP_MULT
	var ehp: float = h.max_life * (120.0 + float(h.armor)) / 120.0
	var r := {"cls": cls, "lvl": lvl, "gear": gear, "life": int(h.max_life), "armor": h.armor, "res": h.res,
		"dmg": [h.dmg_min, h.dmg_max], "dps": snappedf(dps, 0.1), "ehp": int(ehp), "frw": h.frw,
		"hit": snappedf((h.dmg_min + h.dmg_max) * 0.5 * h.aspd, 0.01)}
	rows["%s:%d:%s" % [cls, lvl, gear]] = r
	print("[PVP] %-8s L%-2d %-6s life %4d armor %4d res %2d dmg %d-%d  dps %6.1f  ehp %5d" % [cls, lvl, gear, r["life"], r["armor"], r["res"], h.dmg_min, h.dmg_max, dps, int(ehp)])
	foe.queue_free()
	h.pvp_force = false

## One frame of play against the one foe: a skill when it's ready and in reach, else the weapon.
func _bot(foe) -> void:
	var h = g.hero
	h.mana = minf(h.max_mana, h.mana)
	if not h.can_act():
		return
	var nd: float = foe.global_position.distance_to(h.global_position)
	var skills: Array = h.skill_list().duplicate()
	skills.reverse()
	for s in skills:
		var id: String = s["id"]
		if id in skip or Data.skill_locked(s, h.level) or h.cds.get(id, 0.0) > 0.0 or h.mana < h.skill_cost(id):
			continue
		h._face(foe.global_position - h.global_position)
		if h.use_skill(id, h.skill_aim(id, foe.global_position)):
			return
	# the weapon: a swing (or a shot) at the foe where he stands; a melee class out of reach walks after him
	h._face(foe.global_position - h.global_position)
	if moving and nd > h.reach() + 0.6:
		if h.target != foe:
			h.cmd_target(foe)
		return
	h.free_attack(foe.global_position)

## Who wins: A deals dps_a x skill_a a second (+-30%), B likewise; first to empty the other's ehp.
func _duel(a: Dictionary, b: Dictionary, skill_a: float, skill_b: float, n := 4000) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var wins := 0
	for i in n:
		var la := float(a["ehp"])
		var lb := float(b["ehp"])
		var t := 0
		while la > 0.0 and lb > 0.0 and t < 600:
			t += 1
			if rng.randf() < skill_a:
				lb -= float(a["dps"]) * rng.randf_range(0.7, 1.3)
			if rng.randf() < skill_b:
				la -= float(b["dps"]) * rng.randf_range(0.7, 1.3)
		if lb <= 0.0 and (la > 0.0 or rng.randf() < 0.5):
			wins += 1
	return float(wins) / n

func _flag(what: String) -> void:
	flags += 1
	print("[PVP-FLAG] " + what)

func _duels() -> void:
	for lvl in levels:
		for cls in classes:
			var fr = rows.get("%s:%d:fresh" % [cls, lvl])
			var ge = rows.get("%s:%d:geared" % [cls, lvl])
			if fr == null or ge == null:
				continue
			# (the same class with the same skills: what gear changes is its damage x attack speed and its ehp, so the
			# duel runs on the fresh one's measured dps scaled by that, keeping the bot's noise out of it)
			var dmg_k: float = float(ge["hit"]) / maxf(0.01, float(fr["hit"]))
			var base_dps: float = maxf(float(fr["dps"]), 1.0)
			var ge2 := {"ehp": ge["ehp"], "dps": base_dps * dmg_k}
			var fr2 := {"ehp": fr["ehp"], "dps": base_dps}
			var even := _duel(ge2, fr2, 0.75, 0.75)
			var gap := 1.0 - _duel(ge2, fr2, 0.45, 0.9)
			var power: float = dmg_k * float(ge["ehp"]) / maxf(1.0, float(fr["ehp"]))
			print("[PVP-DUEL] L%-2d %-8s geared vs fresh: damage x%.2f, ehp x%.2f, power x%.2f, equal skill %d%%, fresh and much better %d%%" % [lvl, cls, dmg_k, float(ge["ehp"]) / maxf(1.0, float(fr["ehp"])), power, int(even * 100), int(gap * 100)])
			if even < 0.8:
				_flag("L%d %s: geared wins only %d%% at equal skill" % [lvl, cls, int(even * 100)])
			if gap < 0.35:
				_flag("L%d %s: a much better fresh player wins only %d%%" % [lvl, cls, int(gap * 100)])
		# the classes against each other, both geared, equal skill
		for i in classes.size():
			for j in range(i + 1, classes.size()):
				var a = rows.get("%s:%d:geared" % [classes[i], lvl])
				var b = rows.get("%s:%d:geared" % [classes[j], lvl])
				if a == null or b == null:
					continue
				var w := _duel(a, b, 0.75, 0.75, 2000)
				if w > 0.7 or w < 0.3:
					_flag("L%d %s vs %s: %d%%" % [lvl, classes[i], classes[j], int(w * 100)])
				print("[PVP-DUEL] L%-2d %s vs %s: %d%%" % [lvl, classes[i], classes[j], int(w * 100)])
