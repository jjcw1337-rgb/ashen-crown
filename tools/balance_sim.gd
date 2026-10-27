extends SceneTree
## Balance protocol: an autopilot plays every class through the run checkpoints (Act I, A2
## arriving in Act I gear, A2 in A2 gear, A3) in real fights against real packs and bosses,
## and reports how long kills take, how much life they cost and whether it died. Each number
## is checked against the target bands in BANDS below. See BALANCE.md for the protocol.
##
##   godot --headless --fixed-fps 30 --path . -s tools/balance_sim.gd -- [out=report.json] [classes=knight,warlock] [quick]
##
## --fixed-fps makes the sim run as fast as the CPU allows (each frame is 1/30 s of game time).
## Lines starting [BAL] are the table; [BAL-FLAG] lines are numbers outside their band.

const CLASSES := ["knight", "wraith", "demon", "warlock"]
## Share of each zone's monsters a player kills on the way through.
const CLEAR := 1.0
## Where we measure: run (0 Act I, 1 A2, 2 A3), zone, the gear the player has by then
## (item level, and the run whose loot multiplier it carries) and how far through the run's
## experience the player is (0 = arriving, 1 = everything cleared but the boss).
const CHECKPOINTS := [
	{"id": "A1 moor", "run": 0, "zone": "wild", "ilvl": 3, "gear_run": 0, "xp_at": 0.4},
	{"id": "A1 boss", "run": 0, "zone": "lair", "ilvl": 6, "gear_run": 0, "xp_at": 1.0},
	{"id": "A2 arrive", "run": 1, "zone": "wild", "ilvl": 6, "gear_run": 0, "xp_at": 0.0},
	{"id": "A2 moor", "run": 1, "zone": "wild", "ilvl": 6, "gear_run": 1, "xp_at": 0.4},
	{"id": "A2 boss", "run": 1, "zone": "lair", "ilvl": 6, "gear_run": 1, "xp_at": 1.0},
	{"id": "A3 moor", "run": 2, "zone": "wild", "ilvl": 6, "gear_run": 2, "xp_at": 0.4},
	{"id": "A3 boss", "run": 2, "zone": "lair", "ilvl": 6, "gear_run": 2, "xp_at": 1.0},
]
## Target bands. Seconds are checked against the same class's Act I numbers ("vs"), so the
## bot's skill cancels out; life lost is a plain share of max life (potions put some back, so
## it can pass 1). pack_s: seconds to wipe a pack; pack_hurt: life lost per pack; boss_s and
## boss_hurt likewise for the boss. A death always flags.
const BANDS := {
	"A1 moor": {"pack_s": [3.0, 15.0], "pack_hurt": [0.0, 0.8]},
	"A1 boss": {"boss_s": [15.0, 90.0], "boss_hurt": [0.0, 2.5]},
	"A2 arrive": {"vs": "A1 moor", "pack_s": [1.2, 3.0], "pack_hurt": [0.0, 1.6]},
	"A2 moor": {"vs": "A1 moor", "pack_s": [0.9, 1.6], "pack_hurt": [0.0, 1.0]},
	"A2 boss": {"vs": "A1 boss", "boss_s": [0.9, 1.6], "boss_hurt": [0.0, 3.0]},
	"A3 moor": {"vs": "A1 moor", "pack_s": [1.1, 2.0], "pack_hurt": [0.0, 1.2]},
	"A3 boss": {"vs": "A1 boss", "boss_s": [1.1, 2.0], "boss_hurt": [0.0, 3.5]},
}
const PACK_LIMIT := 60.0
const BOSS_LIMIT := 150.0

var g
var out_path := ""
var only: Array = []
var quick := false
var results: Array = []

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("classes="):
			only = a.substr(8).split(",")
		elif a == "quick":
			quick = true
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	seed(1234)
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.playing = false
	var levels := await _expected_levels()
	print("[BAL] expected level per checkpoint: ", levels)
	for cls in CLASSES:
		if not only.is_empty() and not cls in only:
			continue
		for cp in CHECKPOINTS:
			if quick and not cp["id"] in ["A1 moor", "A2 arrive", "A2 moor"]:
				continue
			var r: Dictionary = await _checkpoint(cls, cp, int(levels[cp["id"]]))
			results.append(r)
			_report(r)
	_summary()
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"date": Time.get_datetime_string_from_system(), "results": results, "levels": levels}, "  "))
		print("[BAL] wrote ", out_path)
	quit()

# ---------------------------------------------------------------- expected progression
## Level at each checkpoint if the player kills CLEAR of every zone on the way, from level 1,
## with the game's own falloff for monsters below the player's level (Game.gain_kill_xp).
func _expected_levels() -> Dictionary:
	var zone_foes := {}   # "0wild" -> [[xp, level], ...]; "0boss" -> [[xp, level]]
	for run in 3:
		for zone in ["wild", "lair"]:
			g.difficulty = run
			await g.load_zone(0, zone, "start")
			var foes := []
			for e in g.world.enemies_root.get_children():
				if e is Enemy:
					if e.boss:
						zone_foes["%dboss" % run] = [[e.xp, e.level]]
					else:
						foes.append([e.xp, e.level])
			zone_foes["%d%s" % [run, zone]] = foes
	var out := {}
	var p := {"lvl": 1, "xp": 0.0}
	for run in 3:
		var walk: Array = zone_foes["%dwild" % run] + zone_foes["%dlair" % run]
		var done := 0
		for cp in CHECKPOINTS:
			if cp["run"] != run:
				continue
			var upto := int(walk.size() * float(cp["xp_at"]))
			for i in range(done, upto):
				_award(p, float(walk[i][0]) * CLEAR, int(walk[i][1]))
			done = upto
			out[cp["id"]] = p["lvl"]
		for i in range(done, walk.size()):
			_award(p, float(walk[i][0]) * CLEAR, int(walk[i][1]))
		var b: Array = zone_foes["%dboss" % run][0]
		_award(p, float(b[0]), int(b[1]))
	g.difficulty = 0
	return out

func _award(p: Dictionary, xp: float, foe_lvl: int) -> void:
	var ratio := clampf(1.0 - (int(p["lvl"]) - foe_lvl) * 0.08, 0.2, 1.3)
	p["xp"] = float(p["xp"]) + xp * ratio
	while float(p["xp"]) >= Data.xp_for_level(int(p["lvl"])):
		p["xp"] = float(p["xp"]) - Data.xp_for_level(int(p["lvl"]))
		p["lvl"] = int(p["lvl"]) + 1

# ---------------------------------------------------------------- the character
## A plausible build: class stats plus 5 points a level spent the way that class wants them,
## and the best base the player could be wearing in each slot, magic, rolled at ilvl and
## carrying the loot multiplier of the run it dropped in.
func _equip(cls: String, lvl: int, ilvl: int, gear_run: int) -> void:
	var h = g.hero
	if h.dead:
		h.respawn(h.global_position)
	g.death_t = 0.0
	g.ui.death_panel.visible = false
	h.set_class(cls)
	h.new_character()
	h.level = lvl
	var pts := (lvl - 1) * 5
	var w: Dictionary = {"knight": {"str": 2, "dex": 1, "vit": 2}, "wraith": {"str": 1, "dex": 2, "vit": 2}, "demon": {"str": 2, "vit": 2, "ene": 1}, "warlock": {"str": 1, "vit": 2, "ene": 2}}[cls]
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
	# the same rolls at every checkpoint with the same item level, so A2 gear is exactly the
	# Act I gear times the loot multiplier
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + ilvl
	var mult: float = g.run_mult("loot", gear_run)
	for slot in Items.EQUIP_SLOTS:
		if slot == "shield" and cls != "knight":
			continue
		var base := _best_base(slot, mini(ilvl + 2, lvl), cls)
		if base == "":
			continue
		rng.seed = hash(slot) + ilvl
		seed(hash(slot) + ilvl)   # affix picks shuffle with the global generator
		var it := Items.generate(base, ilvl, 1, rng)
		h.equipment[slot] = Items.empower(it, mult) if gear_run > 0 else it
	h.recalc()
	h.life = h.max_life
	h.mana = h.max_mana
	h.refresh_gear()

func _best_base(slot: String, max_lvl: int, cls: String) -> String:
	var best := ""
	var bl := -1
	for id in Data.BASES:
		var b: Dictionary = Data.BASES[id]
		var bslot: String = b["slot"]
		if bslot != slot and not (slot.begins_with("ring") and bslot == "ring"):
			continue
		var l: int = b.get("lvl", 1)
		if l <= max_lvl and l > bl:
			bl = l
			best = id
	return best

# ---------------------------------------------------------------- fights
func _checkpoint(cls: String, cp: Dictionary, lvl: int) -> Dictionary:
	g.difficulty = int(cp["run"])
	await g.load_zone(0, cp["zone"], "start")
	g.ui.close_all()
	_equip(cls, lvl, int(cp["ilvl"]), int(cp["gear_run"]))
	var h = g.hero
	var r := {"class": cls, "checkpoint": cp["id"], "level": lvl, "life": int(h.max_life), "dmg": [h.dmg_min, h.dmg_max], "armor": h.armor}
	if cp["zone"] == "lair":
		var boss = null
		for e in g.world.enemies_root.get_children():
			if e is Enemy and e.boss:
				boss = e
		# clear the throne room's guards out of the way so this measures the boss
		for e in g.enemies_near(boss.global_position, 16.0):
			if not e.boss:
				e.queue_free()
		await process_frame
		h.global_position = g.world.free_spot_near(boss.global_position + Vector3(0, 0, 7.0), 1.0)
		# a player who kept track of the Hollow Matron's heart goes for its Mourner
		var f: Dictionary = await _fight(func(): return ([boss.heart.priority_target()] if boss.heart != null else [boss]) if is_instance_valid(boss) and not boss.dead else [], BOSS_LIMIT)
		r["boss_s"] = f["t"]
		r["boss_hurt"] = f["hurt"]
		r["potions"] = f["potions"]
		r["died"] = f["died"]
		r["boss_left"] = snappedf(boss.life / boss.max_life, 0.01) if is_instance_valid(boss) and not boss.dead else 0.0
	else:
		var packs := _packs(3 if not quick else 2)
		var ts := []
		var hurts := []
		var pots := 0
		var died := false
		for p in packs:
			_reset_hero()
			var c: Vector3 = p
			h.global_position = g.world.free_spot_near(c + Vector3(7.0, 0, 0), 1.0)
			var f: Dictionary = await _fight(func(): return g.enemies_near(c, 13.0), PACK_LIMIT)
			ts.append(f["t"])
			hurts.append(f["hurt"])
			pots += int(f["potions"])
			if f["died"]:
				died = true
				break
		r["pack_s"] = _avg(ts)
		r["pack_hurt"] = _avg(hurts)
		r["potions"] = pots
		r["died"] = died
	return r

## Centres of the packs nearest the zone start (the first fights a player meets).
func _packs(n: int) -> Array:
	var sp: Vector3 = g.world.spawns["start"]
	var groups := {}
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.boss:
			var k: int = e.pack_id
			if not groups.has(k):
				groups[k] = []
			groups[k].append(e.global_position)
	var cs := []
	for k in groups:
		var c := Vector3.ZERO
		for p in groups[k]:
			c += p
		cs.append(c / float((groups[k] as Array).size()))
	cs.sort_custom(func(a, b): return a.distance_to(sp) < b.distance_to(sp))
	return cs.slice(0, n)

func _reset_hero() -> void:
	var h = g.hero
	h.life = h.max_life
	h.mana = h.max_mana
	for k in h.cds.keys():
		h.cds[k] = 0.0
	h.belt = [Items.potion("hp_potion"), Items.potion("hp_potion"), Items.potion("mp_potion"), null]
	h.belt[0]["count"] = 4
	h.belt[1]["count"] = 4
	h.belt[2]["count"] = 3

## Fights until foes() is empty, the hero dies or the time runs out. Returns seconds taken,
## life lost as a share of max life (counting what potions put back), potions drunk.
func _fight(foes: Callable, limit: float) -> Dictionary:
	var h = g.hero
	_reset_hero()
	var t := 0.0
	var hurt := 0.0
	var pots := 0
	var last_life: float = h.life
	var pot_cd := 0.0
	while t < limit:
		await process_frame
		var dt: float = 1.0 / 30.0
		t += dt
		pot_cd -= dt
		if h.life < last_life:
			hurt += last_life - h.life
		last_life = h.life
		if h.dead:
			return {"t": snappedf(t, 0.1), "hurt": snappedf(hurt / h.max_life, 0.01), "potions": pots, "died": true}
		var fs: Array = foes.call()
		if fs.is_empty():
			return {"t": snappedf(t, 0.1), "hurt": snappedf(hurt / h.max_life, 0.01), "potions": pots, "died": false}
		if h.life < h.max_life * 0.45 and pot_cd <= 0.0 and _drink(["hp_potion", "rejuv"]):
			pots += 1
			pot_cd = 1.0
		if h.mana < 8.0 and pot_cd <= 0.0 and _drink(["mp_potion"]):
			pots += 1
			pot_cd = 1.0
		_bot(fs)
	return {"t": limit, "hurt": snappedf(hurt / h.max_life, 0.01), "potions": pots, "died": false, "timeout": true}

func _drink(bases: Array) -> bool:
	var h = g.hero
	for i in 4:
		if h.belt[i] != null and h.belt[i]["base"] in bases:
			h.drink(i)
			return true
	return false

## One frame of play: skills off cooldown when they'd do something, otherwise attack the
## nearest foe. Uses the same aiming as the keyboard (face the foe, then skill_aim).
func _bot(fs: Array) -> void:
	var h = g.hero
	if not h.can_act():
		return
	var near = null
	var nd := INF
	for e in fs:
		var d: float = e.global_position.distance_to(h.global_position)
		if d < nd:
			nd = d
			near = e
	var crowd: int = g.enemies_near(h.global_position, 7.0).size()
	var skills: Array = h.skill_list().duplicate()
	skills.reverse()   # F, R, E, Q: buffs and big spells first
	for s in skills:
		var id: String = s["id"]
		if h.level < int(s["lvl"]) or h.cds[id] > 0.0 or h.mana < float(s["mana"]):
			continue
		var want := false
		match String(s.get("aim", "facing")):
			"self":
				match id:
					"cry", "host", "covenant", "pact":
						want = nd < 8.0 and (id != "pact" or h.life > h.max_life * 0.6)
					"phase":
						want = h.life < h.max_life * 0.5
					"summon":
						want = nd < 12.0 and h.minions.size() < 3
					_:
						want = crowd >= 2 or (near.boss and nd < 6.0)
			"point":
				want = nd > 3.0 and nd < 12.0
			_:
				want = nd <= float(s.get("range", 3.5))
		if not want:
			continue
		h._face(near.global_position - h.global_position)
		if h.use_skill(id, h.skill_aim(id, near.global_position)):
			return
	if h.target != near:
		h.cmd_target(near)

# ---------------------------------------------------------------- report
func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return snappedf(s / a.size(), 0.1)

func _report(r: Dictionary) -> void:
	var line := "[BAL] %-8s %-10s lvl %2d life %4d dmg %s armor %4d" % [r["class"], r["checkpoint"], r["level"], r["life"], str(r["dmg"]), r["armor"]]
	if r.has("boss_s"):
		line += "  boss %5.1fs hurt %4.2f pots %d%s" % [r["boss_s"], r["boss_hurt"], r["potions"], ("  DIED (boss at %d%%)" % int(r["boss_left"] * 100)) if r["died"] else ""]
	else:
		line += "  pack %5.1fs hurt %4.2f pots %d%s" % [r["pack_s"], r["pack_hurt"], r["potions"], "  DIED" if r["died"] else ""]
	var band: Dictionary = BANDS[r["checkpoint"]]
	var base := {}
	if band.has("vs"):
		for o in results:
			if o["class"] == r["class"] and o["checkpoint"] == band["vs"]:
				base = o
	var flags := []
	for k in band:
		if k == "vs" or not r.has(k):
			continue
		var v: float = r[k]
		var what := "%s %.2f" % [k, v]
		if band.has("vs") and k.ends_with("_s"):
			if base.is_empty() or float(base[k]) <= 0.0:
				continue
			v /= float(base[k])
			what = "%s %.2fx %s" % [k, v, band["vs"]]
			r[k + "_x"] = snappedf(v, 0.01)
		var lo: float = band[k][0]
		var hi: float = band[k][1]
		if v < lo:
			flags.append("%s below %.2f" % [what, lo])
		elif v > hi:
			flags.append("%s above %.2f" % [what, hi])
	if r["died"]:
		flags.append("died")
	r["flags"] = flags
	var rel := ""
	for k in ["pack_s_x", "pack_hurt_x", "boss_s_x", "boss_hurt_x"]:
		if r.has(k):
			rel += "  %s %.2f" % [k.trim_suffix("_x"), r[k]]
	print(line + ("   vs Act I:" + rel if rel != "" else ""))
	if not flags.is_empty():
		print("[BAL-FLAG] %s %s: %s" % [r["class"], r["checkpoint"], ", ".join(flags)])

func _summary() -> void:
	var n := 0
	for r in results:
		n += (r["flags"] as Array).size()
	print("[BAL] %d results, %d flags" % [results.size(), n])
