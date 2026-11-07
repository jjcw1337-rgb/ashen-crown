class_name RunBuild
extends RefCounted
## A multiplayer run character's build (Blaine's overhaul, 2026-11-06): what a Battlegrounds
## character earns in one run and what a survivor keeps. It sits on the hero as `Hero.run` only in multiplayer; in
## single player it is null and the talents, level unlocks and backpack work as before.
##   skills    the acquired active skills in the order earned (the spellbook); up to five sit on SLOTS
##   passives  {id: stacks}: power-ups from camp chests, summed into Hero.tfx in place of talents
##   offers    {camp id: {"tier", "choices", "claimed"}}: each camp's upgrade offer, rolled once and claimed once
## The primary attack (left mouse) is outside the five slots and always there.

## The five assignable skill slots: right mouse and four keys.
const SLOTS := ["rmb", "Q", "E", "R", "F"]
## The gear a run character wears (no belt, amulet or rings) and its consumables: the belt's four slots.
const GEAR := ["weapon", "shield", "helm", "armor", "gloves", "boots"]
const BELT := 4
const STACK := 5
const RARITY := RunTalents.RARITY_NAMES
const RARITY_COLORS := RunTalents.RARITY_COLORS
## A camp's tier (1-3, 4 = a boss) -> the odds of each upgrade rarity [common, uncommon, rare], the experience
## for clearing it, and the item level of its loot.
const ODDS := {1: [66, 28, 6], 2: [46, 40, 14], 3: [26, 46, 28], 4: [6, 40, 54]}
## How many choices a chest offers (a boss one more; the Seer's Eye gem one more again), and how much a theme the
## build already has pulls the draw toward its talents and skills (weight 1 + THEME_PULL x what it has of it).
const CHOICES := 3
const THEME_PULL := 1.0
const CAMP_XP := {1: 60, 2: 140, 3: 260, 4: 600}
const TIER_ILVL := {1: 2, 2: 7, 3: 13, 4: 18}
## Gear rarity odds by tier [common, uncommon, rare].
const GEAR_ODDS := {1: [70, 26, 4], 2: [50, 40, 10], 3: [30, 48, 22], 4: [10, 50, 40]}
## A class talent becomes a passive at this many times its rank (a run has far fewer picks than a talent tree has
## points); only the keys `_scales` accepts, never a class special like arc_count or arrow_split.
const TALENT_SCALE := 2.0
## A class's damage in a run, where its kit plays differently from the story game (measured with
## tools/run_playthrough.gd: the knight and Doug flattened at ~30 damage a second against the bosses while every
## other class reached 60-250). Runs only; single player and the Battlegrounds' PvP scale stay as they are.
const CLASS_POWER := {"knight": 1.6, "doug": 1.8, "demon": 0.9}
## Cooldown and mana reductions stop here however many stack.
const REDUCTION_CAP := 60.0

## Passives every class can take.
## Laid over by the Hero Codex (data/codex/shared.json "rites") when this script loads.
static var GENERIC: Array = [
	{"id": "g_edge", "name": "Honed Edge", "rarity": 0, "max": 5, "icon": "t_sword", "fx": {"dmg": 6}, "text": "+{dmg}% damage."},
	{"id": "g_hide", "name": "Thick Hide", "rarity": 0, "max": 5, "icon": "t_heart", "fx": {"life_pct": 8}, "text": "+{life_pct}% maximum life."},
	{"id": "g_hands", "name": "Quick Hands", "rarity": 0, "max": 4, "icon": "t_haste", "fx": {"ias": 6}, "text": "+{ias}% attack speed."},
	{"id": "g_stride", "name": "Fleet Foot", "rarity": 0, "max": 3, "icon": "t_boot", "fx": {"frw": 6}, "text": "+{frw}% run speed."},
	{"id": "g_plate", "name": "Hardened", "rarity": 0, "max": 4, "icon": "t_armor", "fx": {"armor_pct": 12}, "text": "+{armor_pct}% defense."},
	{"id": "g_well", "name": "Deep Well", "rarity": 0, "max": 4, "icon": "t_eye", "fx": {"mana_pct": 12}, "text": "+{mana_pct}% maximum mana."},
	{"id": "g_mend", "name": "Mending", "rarity": 0, "max": 4, "icon": "t_regen", "fx": {"regen": 1.0}, "text": "+{regen} life regenerated per second."},
	{"id": "g_instinct", "name": "Killer Instinct", "rarity": 1, "max": 4, "icon": "t_star", "fx": {"crit": 4}, "text": "+{crit}% chance to land a critical hit."},
	{"id": "g_vicious", "name": "Vicious", "rarity": 1, "max": 3, "icon": "t_skull", "fx": {"crit_dmg": 20}, "text": "Critical hits deal +{crit_dmg}% damage."},
	{"id": "g_thirst", "name": "Bloodthirst", "rarity": 1, "max": 3, "icon": "t_heart", "fx": {"ls": 3}, "text": "{ls}% of the damage you deal heals you."},
	{"id": "g_ward", "name": "Warded", "rarity": 1, "max": 3, "icon": "t_ward", "fx": {"res": 8}, "text": "+{res}% to all resistances."},
	{"id": "g_flow", "name": "Arcane Flow", "rarity": 2, "max": 2, "icon": "t_hourglass", "fx": {"cdr": 12}, "text": "Skills recharge {cdr}% faster."},
	{"id": "g_trance", "name": "Battle Trance", "rarity": 2, "max": 2, "icon": "t_fist", "fx": {"dmg": 15, "ias": 8}, "text": "+{dmg}% damage and +{ias}% attack speed."},
	{"id": "g_colossus", "name": "Colossus", "rarity": 2, "max": 2, "icon": "t_heart", "fx": {"life_pct": 20, "vit": 5}, "text": "+{life_pct}% maximum life and +{vit} vitality."},
]

static func _static_init() -> void:
	Codex.apply_rites(GENERIC, Codex.shared().get("rites", []))

var skills: Array = []
var passives := {}
var offers := {}
## The gems found (RunTalents.GEMS ids, in the order found; duplicates stack their stats).
var gems: Array = []
## The Hunger Stone's damage so far (+% for the rest of the run).
var hunger := 0.0
## Not saved: timed buffs ({key: {"t", "fx"}}: momentum, frenzy, a consumable's), proc counters, the procs cache.
var buffs := {}
var counters := {}
var proc_cache = null
var cls_hint := ""       # (the class the offers are rolled for: roll_gem reads its luck)
## A run's own seed: offers roll from it and the camp, so a reopened chest shows the same three.
var seed := 0
## The run's own id: its survivor's file name (Survivors), so one run is saved once however often it's asked.
var uid := ""
## Camps cleared and levels reached, for the results and the survivor card.
var camps := 0
var bosses := 0

func _init() -> void:
	seed = randi()
	uid = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xffffffff]

# ---------------------------------------------------------------- experience

## Experience to finish `level` (0 -> 1 is one fight; level 20 is a full run of camps).
static func xp_for(level: int) -> int:
	return 30 + 14 * level + level * level

# ---------------------------------------------------------------- passives

static var _class_cache := {}

## Every passive this class can be offered: the generic ones and its talents (rows 0-1 common, 2 uncommon, the
## capstone rare), each with "needs" = the skill it improves when its icon names one (offered only once that
## skill is acquired). The talents' code already reads these keys (Hero.talent), so each one works as described.
static func passive_pool(cls: String) -> Array:
	if _class_cache.has(cls):
		return _class_cache[cls]
	var out: Array = GENERIC.duplicate(true)
	for p in out:
		p["theme"] = ""
	for t in RunTalents.talents_for(cls):
		out.append(t.duplicate(true))
	var own := {}
	for s in Data.skills_for(cls) + Data.shared_skills():
		own[str(s["id"])] = true
	var themes: Array = RunTalents.TREE_THEME.get(cls, [])
	var trees: Array = Talents.TREES.get(cls, [])
	for ti in trees.size():
		var tree: Dictionary = trees[ti]
		for t in tree["talents"]:
			var p: Dictionary = t.duplicate(true)
			p["rarity"] = clampi(int(t["rarity"]), 0, 2) if t.has("rarity") else [0, 0, 1, 2][clampi(int(t["row"]), 0, 3)]
			p["tree"] = tree["name"]
			p["theme"] = str(themes[ti]) if ti < themes.size() else ""
			var fx := {}
			for k in t["fx"]:
				fx[k] = float(t["fx"][k]) * (TALENT_SCALE if _scales(k) else 1.0)
			p["fx"] = fx
			var icon := str(t.get("icon", ""))
			if icon == "block" or (icon != "attack" and Data.skill_def(icon).size() > 0):
				p["needs"] = icon      # (block: the Block skill isn't a run skill, so those never come up)
			out.append(p)
	var known := {}
	for p in out:
		known[str(p["id"])] = true
	out.append_array(Codex.extra_rites(cls, known))      # (live rites made of data alone, data/codex)
	_class_cache[cls] = out
	return out

## The keys a talent's value is multiplied for: plain stats and percentages, never a class special.
static func _scales(k: String) -> bool:
	return k in ["dmg", "life_pct", "mana_pct", "armor_pct", "crit", "crit_dmg", "ias", "frw", "regen", "res", "ls",
		"str", "dex", "vit", "ene", "buff_pow", "block_dr"] or k.begins_with("dmg:") or k.begins_with("cd:") or k.begins_with("cost:")

static func passive_def(cls: String, id: String) -> Dictionary:
	for p in passive_pool(cls):
		if p["id"] == id:
			return p
	return {}

## The passives' effects added up, the way Talents.sum adds ranks: Hero.tfx in a run.
func fx(cls: String) -> Dictionary:
	var out := {}
	for id in passives:
		var p := passive_def(cls, id)
		if p.is_empty():
			continue
		for k in p.get("fx", {}):
			out[k] = float(out.get(k, 0.0)) + float(p["fx"][k]) * int(passives[id])
	for g in gems:
		var gd := RunTalents.gem_def(str(g))
		for k in gd.get("fx", {}):
			out[k] = float(out.get(k, 0.0)) + float(gd["fx"][k])
	for b in buffs.values():
		for k in b["fx"]:
			out[k] = float(out.get(k, 0.0)) + float(b["fx"][k])
	for k in out:
		if str(k).begins_with("cd:") or str(k).begins_with("cost:"):
			out[k] = minf(out[k], REDUCTION_CAP)
	return out

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.1))

## A passive's text at `stacks`; with `from` > 0 it shows the change: "Fire Arrow deals 24% -> 48% more damage."
static func passive_text(p: Dictionary, stacks: int, from := 0) -> String:
	return RunTalents.text_of(p, stacks, from)

## Something about the build changed (a passive, a gem, a buff): the procs are looked up again.
func changed() -> void:
	proc_cache = null

## How much of each theme the build has: its skills and passives (stacks), for the offers' pull and the build window.
func theme_counts(cls: String) -> Dictionary:
	var out := {}
	var mine := {}
	for t in RunTalents.THEMES.get(cls, []):
		mine[t["id"]] = true
	for id in skills:
		var th := str(RunTalents.SKILL_THEMES.get(id, ""))
		if mine.has(th):
			out[th] = int(out.get(th, 0)) + 2
	for id in passives:
		var th := str(passive_def(cls, id).get("theme", ""))
		if mine.has(th):
			out[th] = int(out.get(th, 0)) + int(passives[id])
	return out

# ---------------------------------------------------------------- skills

## The active skills this class can earn: its own and the shared ones (never the primary attack or Block).
static func skill_pool(cls: String) -> Array:
	var out := []
	for s in Data.skills_for(cls) + Data.run_skills_for(cls) + Data.shared_skills():
		if not (str(s["id"]) in ["attack", "block"]):
			out.append(s)
	return out

## A skill's rarity as a reward: the first ones common, the middle ones uncommon, the ultimates rare; the shared
## skills uncommon.
static func skill_rarity(sk: Dictionary) -> int:
	if sk.has("rarity"):      # (set by the Hero Codex)
		return clampi(int(sk["rarity"]), 0, 2)
	if str(sk.get("cls", "")) == "any":
		return 1
	var lvl := int(sk.get("lvl", 1))
	return 0 if lvl <= 5 else (1 if lvl <= 14 else 2)

## Acquire a skill: into the first empty slot (true), or the spellbook only when all five are full.
func add_skill(id: String, binds: Dictionary) -> bool:
	if skills.has(id):
		return false
	skills.append(id)
	for slot in SLOTS:
		if str(binds.get(slot, "")) == "":
			binds[slot] = id
			return true
	return false

## The run's binds: the attack on the left mouse, its skills on SLOTS (kept where they are), nothing on G and V.
func check_binds(binds: Dictionary) -> void:
	binds["lmb"] = "attack"
	var seen := {}
	for slot in SLOTS:
		var id := str(binds.get(slot, ""))
		if id != "" and (not skills.has(id) or seen.has(id)):
			id = ""
		binds[slot] = id
		seen[id] = true
	for slot in ["G", "V"]:
		binds[slot] = ""

# ---------------------------------------------------------------- upgrade offers

## Roll a camp's offer: CHOICES (+1 at a boss, +1 with the Seer's Eye) choices, each a rarity drawn by the tier's
## odds (one step rarer with the Shard of the Crown), then an eligible skill or passive of that rarity (the nearest
## rarity when that one has nothing left), weighted toward the themes the build already has; no repeats. One to
## three are skills while skills are left to learn (at least one while a slot is empty), like Slay the Spire's
## reward screen leaning on the deck's archetype.
func roll_offer(cls: String, tier: int, key: String, binds: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [seed, key])
	var have := theme_counts(cls)
	var tfx := fx(cls)
	var up := int(tfx.get("rarity_up", 0.0))
	var n := CHOICES + (1 if tier >= 4 else 0) + int(tfx.get("offer_plus", 0.0))
	var skill_pool_ := {0: [], 1: [], 2: []}
	var pass_pool := {0: [], 1: [], 2: []}
	for sk in skill_pool(cls):
		if not skills.has(sk["id"]):
			var c := {"kind": "skill", "id": str(sk["id"]), "rarity": skill_rarity(sk), "theme": str(RunTalents.SKILL_THEMES.get(str(sk["id"]), str(sk.get("direction", "")).to_lower()))}
			skill_pool_[c["rarity"]].append(c)
	for p in passive_pool(cls):
		var stacks := int(passives.get(p["id"], 0))
		if stacks >= int(p["max"]):
			continue
		if p.has("needs") and not skills.has(p["needs"]):
			continue
		if p.has("needs_any") and not (p["needs_any"] as Array).any(func(x): return skills.has(x)):
			continue
		var pr := mini(2, int(p["rarity"]))
		pass_pool[pr].append({"kind": "passive", "id": str(p["id"]), "rarity": pr, "theme": str(p.get("theme", ""))})
	var skills_left := 0
	for r in skill_pool_:
		skills_left += skill_pool_[r].size()
	var empty := SLOTS.any(func(s): return str(binds.get(s, "")) == "")
	# how many of the choices are skills: 1-3 while there are skills to learn (more while the slots are empty)
	var want_skills := 0
	if skills_left > 0:
		var x := rng.randf()
		want_skills = 1 if x < 0.55 else (2 if x < 0.9 else 3)
		if empty:
			want_skills = maxi(want_skills, 2 if skills.size() < 2 else 1)
		want_skills = mini(want_skills, mini(skills_left, n))
	var odds: Array = ODDS.get(clampi(tier, 1, 4), ODDS[1])
	var out := []
	for i in n:
		var pools: Dictionary = skill_pool_ if i < want_skills else pass_pool
		var r := mini(2, _draw(odds, rng) + up)
		var pick = null
		for d in [0, -1, 1, -2, 2]:
			var rr: int = r + d
			if rr < 0 or rr > 2:
				continue
			var left: Array = pools[rr].filter(func(c): return not _has(out, c))
			if not left.is_empty():
				pick = _weighted(left, have, rng)
				break
		if pick == null and pools == skill_pool_:
			for rr in [0, 1, 2]:
				var left2: Array = pass_pool[rr].filter(func(c): return not _has(out, c))
				if not left2.is_empty():
					pick = _weighted(left2, have, rng)
					break
		if pick != null:
			out.append(pick)
	return out

## One of `list`, each weighted 1 + THEME_PULL x how much of its theme the build has (generic ones weigh 1).
static func _weighted(list: Array, have: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	var ws := []
	for c in list:
		var w := 1.0 + THEME_PULL * float(have.get(str(c.get("theme", "")), 0)) if str(c.get("theme", "")) != "" else 1.0
		ws.append(w)
		total += w
	var x := rng.randf() * total
	for i in list.size():
		x -= float(ws[i])
		if x <= 0.0:
			return list[i]
	return list[list.size() - 1]

## The gem a camp's chest holds for this player, or "" (rolled with the offer, once).
func roll_gem(tier: int, key: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:gem" % [seed, key])
	tier = clampi(tier, 1, 4)
	var luck := 1.0 + float(fx(cls_hint).get("gem_luck", 0.0))
	if rng.randf() >= float(RunTalents.GEM_CHANCE[tier]) * luck:
		return ""
	var want := 0
	if tier >= 4 and rng.randf() < RunTalents.LEGEND_ODDS:
		want = 3
	elif rng.randf() < float(RunTalents.RARE_GEM_CHANCE[tier]) * luck or tier >= 4:
		want = 2
	var pool := RunTalents.GEMS.filter(func(g): return int(g["rarity"]) == want and (want < 3 or not gems.has(g["id"])))
	if pool.is_empty():
		pool = RunTalents.GEMS.filter(func(g): return int(g["rarity"]) == 0)
	return str(pool[rng.randi() % pool.size()]["id"])

static func _has(list: Array, c: Dictionary) -> bool:
	return list.any(func(o): return o["kind"] == c["kind"] and o["id"] == c["id"])

static func _draw(odds: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in odds:
		total += float(w)
	var x := rng.randf() * total
	for i in odds.size():
		x -= float(odds[i])
		if x <= 0.0:
			return i
	return 0

## The camp's offer, rolled the first time it is asked for and the same ever after (closing and reopening the chest
## doesn't reroll it).
func offer_for(cls: String, key: String, tier: int, binds: Dictionary) -> Dictionary:
	if not offers.has(key):
		cls_hint = cls
		var gem := roll_gem(tier, key)
		var lrng := RandomNumberGenerator.new()
		lrng.seed = hash("%d:%s:loot" % [seed, key])
		var loot := RunTalents.roll_consumables(tier, lrng)
		for i in int(fx(cls).get("loot_plus", 0.0)):
			loot.append_array(RunTalents.roll_consumables(1, lrng).slice(0, 1))
		offers[key] = {"tier": tier, "choices": roll_offer(cls, tier, key, binds), "claimed": "", "gem": gem, "loot": loot}
		if gem != "":
			gems.append(gem)       # (found when the chest is opened, whatever is chosen)
			changed()
	return offers[key]

func offer_open(key: String) -> bool:
	return offers.has(key) and str(offers[key]["claimed"]) == ""

## Take choice `i` of a camp's offer, once: the skill is acquired (and slotted if a slot is free) or the passive
## gains a stack. Returns the choice taken, or {} when the offer is gone or already claimed.
func claim(key: String, i: int, binds: Dictionary) -> Dictionary:
	if not offer_open(key):
		return {}
	var o: Dictionary = offers[key]
	if i < 0 or i >= o["choices"].size():
		return {}
	var c: Dictionary = o["choices"][i]
	o["claimed"] = c["id"]
	if c["kind"] == "skill":
		add_skill(c["id"], binds)
	else:
		passives[c["id"]] = int(passives.get(c["id"], 0)) + 1
	changed()
	return c

# ---------------------------------------------------------------- gear

## Is this item something a run character can wear (one of GEAR's slots, and its class)?
static func wearable(it: Dictionary, cls: String) -> bool:
	if not Data.BASES.has(str(it.get("base", ""))):
		return false
	var b: Dictionary = Data.BASES[it["base"]]
	var slot := str(b["slot"])
	if not (slot in GEAR):
		return false
	if slot == "shield" and cls != "knight":
		return false
	var only := str(b.get("cls", ""))
	if slot == "weapon" and has_own_weapons(cls):
		return only == cls      # (the archer keeps a bow, the plague doctor a cane: their kits are built on them)
	return only == "" or only == cls

static var _own_weapons := {}
## Does this class have weapons of its own to grow through (two or more Data.BASES with its "cls")? Doug has one
## drumstick, at level 1: he takes general weapons too, or he'd never find a better one.
static func has_own_weapons(cls: String) -> bool:
	if not _own_weapons.has(cls):
		_own_weapons[cls] = Data.BASES.values().filter(func(b): return str(b["slot"]) == "weapon" and str(b.get("cls", "")) == cls).size() >= 2
	return _own_weapons[cls]

## Where a found item would go on this hero.
static func gear_slot(it: Dictionary) -> String:
	return str(Data.BASES[it["base"]]["slot"])

## A run's loot (the camp chests and the monsters): gear for one of `classes` (the heroes in the raid) at the tier's
## item level and rarity odds, never a ring, amulet or belt.
static func random_gear(tier: int, rng: RandomNumberGenerator, classes: Array) -> Dictionary:
	tier = clampi(tier, 1, 4)
	var ilvl: int = TIER_ILVL[tier]
	var cls: String = str(classes[rng.randi() % classes.size()]) if not classes.is_empty() else "knight"
	var slots := GEAR.filter(func(s): return s != "shield" or cls == "knight")
	var slot: String = slots[rng.randi() % slots.size()]
	var base := ""
	if slot == "weapon":
		base = weapon_base(cls, ilvl, rng)
	else:
		base = Items.pick_base(ilvl, rng, slot)
	var rarity := _draw(GEAR_ODDS[tier], rng)
	var it := Items.generate(base, ilvl, rarity, rng)
	it["req"] = 0      # (a run's gear has no level requirement: what drops in a camp is for that camp)
	return it

## A weapon this class fights with: its own kind when it has one (the archer's bows, the plague doctor's canes),
## else any general weapon, at about this item level.
static func weapon_base(cls: String, ilvl: int, rng: RandomNumberGenerator) -> String:
	var own := []
	var general := []
	for k in Data.BASES:
		var b: Dictionary = Data.BASES[k]
		if str(b["slot"]) != "weapon" or int(b.get("lvl", 1)) > ilvl + 1:
			continue
		if str(b.get("cls", "")) == cls:
			own.append(k)
		elif str(b.get("cls", "")) == "":
			general.append(k)
	var pool := own if has_own_weapons(cls) else general + own
	if pool.is_empty():
		return str(Data.CLASSES.get(cls, {}).get("weapon", "short_sword"))
	pool.sort_custom(func(a, b): return int(Data.BASES[a].get("lvl", 1)) > int(Data.BASES[b].get("lvl", 1)))
	return pool[mini(rng.randi() % 2, pool.size() - 1)]      # (the best one or two for the level)

# ---------------------------------------------------------------- level-ups

## A run's level-up raises the class's attributes by itself (no points to spend): five a level, split by the
## class's starting attributes.
static func grow(hero) -> void:
	var c: Dictionary = Data.CLASSES[hero.cls]
	var w := [float(c["str"]), float(c["dex"]), float(c["vit"]), float(c["ene"])]
	var total: float = w[0] + w[1] + w[2] + w[3]
	var add := [0, 0, 0, 0]
	var left := 5
	for i in 4:
		add[i] = int(floor(5.0 * w[i] / total))
		left -= add[i]
	var best := w.find(w.max())
	add[best] += left
	hero.str_ += add[0]
	hero.dex += add[1]
	hero.vit += add[2]
	hero.ene += add[3]

# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"skills": skills.duplicate(), "passives": passives.duplicate(), "offers": offers.duplicate(true),
		"seed": seed, "camps": camps, "bosses": bosses, "uid": uid, "gems": gems.duplicate(), "hunger": hunger}

static func from_dict(d: Dictionary) -> RunBuild:
	var r := RunBuild.new()
	r.skills = Array(d.get("skills", [])).map(func(x): return str(x))
	for k in d.get("passives", {}):
		r.passives[str(k)] = int(d["passives"][k])
	r.offers = d.get("offers", {}).duplicate(true)
	r.seed = int(d.get("seed", r.seed))
	r.camps = int(d.get("camps", 0))
	r.bosses = int(d.get("bosses", 0))
	r.uid = str(d.get("uid", r.uid))
	r.gems = Array(d.get("gems", [])).map(func(x): return str(x))
	r.hunger = float(d.get("hunger", 0.0))
	return r
