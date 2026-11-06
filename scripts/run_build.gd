class_name RunBuild
extends RefCounted
## A multiplayer run character's build (Blaine's overhaul, 2026-11-06; docs/overhaul_plan.md): what a Battlegrounds
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
const RARITY := ["Common", "Uncommon", "Rare"]
const RARITY_COLORS := [Color(0.86, 0.84, 0.78), Color(0.42, 0.86, 0.52), Color(0.48, 0.68, 1.0)]
## A camp's tier (1-3, 4 = a boss) -> the odds of each upgrade rarity [common, uncommon, rare], the experience for
## clearing it, and the item level of its loot.
const ODDS := {1: [70, 25, 5], 2: [50, 38, 12], 3: [32, 43, 25], 4: [12, 45, 43]}
const CAMP_XP := {1: 60, 2: 140, 3: 260, 4: 600}
const TIER_ILVL := {1: 2, 2: 7, 3: 13, 4: 18}
## Gear rarity odds by tier [common, uncommon, rare].
const GEAR_ODDS := {1: [70, 26, 4], 2: [50, 40, 10], 3: [30, 48, 22], 4: [10, 50, 40]}
## A class talent becomes a passive at this many times its rank (a run has far fewer picks than a talent tree has
## points); only the keys `_scales` accepts, never a class special like arc_count or arrow_split.
const TALENT_SCALE := 2.0
## Cooldown and mana reductions stop here however many stack.
const REDUCTION_CAP := 60.0

## Passives every class can take.
const GENERIC := [
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

var skills: Array = []
var passives := {}
var offers := {}
## A run's own seed: offers roll from it and the camp, so a reopened chest shows the same three.
var seed := 0
## Camps cleared and levels reached, for the results and the survivor card.
var camps := 0
var bosses := 0

func _init() -> void:
	seed = randi()

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
	var own := {}
	for s in Data.skills_for(cls) + Data.shared_skills():
		own[str(s["id"])] = true
	for tree in Talents.TREES.get(cls, []):
		for t in tree["talents"]:
			var p: Dictionary = t.duplicate(true)
			p["rarity"] = [0, 0, 1, 2][clampi(int(t["row"]), 0, 3)]
			p["tree"] = tree["name"]
			var fx := {}
			for k in t["fx"]:
				fx[k] = float(t["fx"][k]) * (TALENT_SCALE if _scales(k) else 1.0)
			p["fx"] = fx
			var icon := str(t.get("icon", ""))
			if icon == "block" or (icon != "attack" and Data.skill_def(icon).size() > 0):
				p["needs"] = icon      # (block: the Block skill isn't a run skill, so those never come up)
			out.append(p)
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
		for k in p["fx"]:
			out[k] = float(out.get(k, 0.0)) + float(p["fx"][k]) * int(passives[id])
	for k in out:
		if str(k).begins_with("cd:") or str(k).begins_with("cost:"):
			out[k] = minf(out[k], REDUCTION_CAP)
	return out

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.1))

## A passive's text at `stacks`; with `from` > 0 it shows the change: "Fire Arrow deals 24% -> 48% more damage."
static func passive_text(p: Dictionary, stacks: int, from := 0) -> String:
	var s := str(p.get("text", ""))
	for k in p["fx"]:
		var v: float = float(p["fx"][k])
		s = s.replace("{" + k + "}", (_num(v * from) + " → " + _num(v * stacks)) if from > 0 else _num(v * stacks))
	return s

# ---------------------------------------------------------------- skills

## The active skills this class can earn: its own and the shared ones (never the primary attack or Block).
static func skill_pool(cls: String) -> Array:
	var out := []
	for s in Data.skills_for(cls) + Data.shared_skills():
		if not (str(s["id"]) in ["attack", "block"]):
			out.append(s)
	return out

## A skill's rarity as a reward: the first ones common, the middle ones uncommon, the ultimates rare; the shared
## skills uncommon.
static func skill_rarity(sk: Dictionary) -> int:
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

## Roll an offer of three for a camp: each choice draws a rarity by the tier's odds, then an eligible skill or
## passive of that rarity (the nearest rarity when that one has nothing left); no repeats. While a slot is empty
## and a skill is still to be had, at least one of the three is a skill.
func roll_offer(cls: String, tier: int, key: String, binds: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [seed, key])
	var pool := {0: [], 1: [], 2: []}
	var skill_opts := []
	for sk in skill_pool(cls):
		if not skills.has(sk["id"]):
			var c := {"kind": "skill", "id": str(sk["id"]), "rarity": skill_rarity(sk)}
			pool[c["rarity"]].append(c)
			skill_opts.append(c)
	for p in passive_pool(cls):
		var have := int(passives.get(p["id"], 0))
		if have >= int(p["max"]):
			continue
		if p.has("needs") and not skills.has(p["needs"]):
			continue
		pool[int(p["rarity"])].append({"kind": "passive", "id": str(p["id"]), "rarity": int(p["rarity"])})
	var odds: Array = ODDS.get(clampi(tier, 1, 4), ODDS[1])
	var out := []
	for i in 3:
		var r := _draw(odds, rng)
		var pick = null
		for d in [0, -1, 1, -2, 2]:
			var rr: int = r + d
			if rr < 0 or rr > 2:
				continue
			var left: Array = pool[rr].filter(func(c): return not _has(out, c))
			if not left.is_empty():
				pick = left[rng.randi() % left.size()]
				break
		if pick != null:
			out.append(pick)
	var empty := SLOTS.any(func(s): return str(binds.get(s, "")) == "")
	if empty and not out.any(func(c): return c["kind"] == "skill"):
		var left: Array = skill_opts.filter(func(c): return not _has(out, c))
		if not left.is_empty():
			left.sort_custom(func(a, b): return int(a["rarity"]) < int(b["rarity"]))     # (the commoner first)
			var s = left[0] if rng.randf() < 0.6 else left[rng.randi() % left.size()]
			if out.size() >= 3:
				out[out.size() - 1] = s
			else:
				out.append(s)
	return out

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
		offers[key] = {"tier": tier, "choices": roll_offer(cls, tier, key, binds), "claimed": ""}
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
	return only == "" or only == cls

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
	var pool := own if not own.is_empty() else general
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
		"seed": seed, "camps": camps, "bosses": bosses}

static func from_dict(d: Dictionary) -> RunBuild:
	var r := RunBuild.new()
	r.skills = Array(d.get("skills", [])).map(func(x): return str(x))
	for k in d.get("passives", {}):
		r.passives[str(k)] = int(d["passives"][k])
	r.offers = d.get("offers", {}).duplicate(true)
	r.seed = int(d.get("seed", r.seed))
	r.camps = int(d.get("camps", 0))
	r.bosses = int(d.get("bosses", 0))
	return r
