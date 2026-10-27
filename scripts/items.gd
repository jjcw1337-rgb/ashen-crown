class_name Items
extends RefCounted
## Item generation, naming, stats, tooltips and prices.

const EQUIP_SLOTS := ["weapon", "shield", "helm", "armor", "gloves", "boots", "belt", "amulet", "ring1", "ring2"]

static func make(base_id: String, rarity: int = 0, ilvl: int = 1) -> Dictionary:
	var b: Dictionary = Data.BASES[base_id]
	var it := {"base": base_id, "rarity": rarity, "ilvl": ilvl, "affixes": [], "name": b["name"], "req": int(b.get("lvl", 1))}
	if b.has("dmg"):
		it["dmg"] = [b["dmg"][0], b["dmg"][1]]
	if b.has("def"):
		it["def"] = int(b["def"])
	if b.has("block"):
		it["block"] = int(b["block"])
	return it

static func pick_base(ilvl: int, rng: RandomNumberGenerator, slot_filter: String = "") -> String:
	var pool := []
	var weights := []
	for k in Data.BASES.keys():
		var b: Dictionary = Data.BASES[k]
		var slot: String = b["slot"]
		if slot in ["potion", "gold"]:
			continue
		if slot_filter != "" and slot != slot_filter:
			continue
		var bl: int = b.get("lvl", 1)
		if bl > ilvl + 1:
			continue
		pool.append(k)
		weights.append(1.0 / (1.0 + absf(ilvl - bl) * 0.15) * (0.6 if slot in ["ring", "amulet"] else 1.0))
	if pool.is_empty():
		return "short_sword"
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

static func slot_class(base_id: String) -> String:
	return Data.BASES[base_id]["slot"]

static func roll_affix(stat: String, ilvl: int, rng: RandomNumberGenerator) -> Array:
	for a in Data.AFFIXES:
		if a[0] == stat:
			var v: float = rng.randf_range(a[2], a[3]) + a[4] * ilvl * rng.randf_range(0.6, 1.0)
			return [stat, maxi(1, int(round(v)))]
	return [stat, 1]

static func affix_name(stat: String) -> String:
	for a in Data.AFFIXES:
		if a[0] == stat:
			return a[1]
	return ""

static func generate(base_id: String, ilvl: int, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var it := make(base_id, rarity, ilvl)
	var slot := slot_class(base_id)
	if it.has("def"):
		it["def"] = int(round(it["def"] * rng.randf_range(0.9, 1.2)))
	var pool: Array = Data.AFFIX_SLOTS.get(slot, []).duplicate()
	pool.shuffle()
	if rarity == 1:
		var n := rng.randi_range(1, 2)
		var prefix := ""
		var suffix := ""
		for i in mini(n, pool.size()):
			var af := roll_affix(pool[i], ilvl, rng)
			it["affixes"].append(af)
			var nm := affix_name(pool[i])
			if nm.begins_with("of "):
				suffix = nm
			else:
				prefix = nm
		it["name"] = (prefix + " " if prefix != "" else "") + Data.BASES[base_id]["name"] + (" " + suffix if suffix != "" else "")
	elif rarity == 2:
		var n2 := rng.randi_range(3, 5)
		for i in mini(n2, pool.size()):
			it["affixes"].append(roll_affix(pool[i], ilvl, rng))
		var tails: Array = Data.RARE_B.get(slot, ["Charm"])
		it["name"] = Data.RARE_A[rng.randi() % Data.RARE_A.size()] + " " + tails[rng.randi() % tails.size()]
		it["req"] = maxi(it["req"], int(ilvl * 0.75))
	elif rarity == 1:
		pass
	if rarity == 1:
		it["req"] = maxi(it["req"], int(ilvl * 0.5))
	return it

static func make_unique(uid: String) -> Dictionary:
	var u: Dictionary = Data.UNIQUES[uid]
	var it := make(u["base"], 3, u["lvl"])
	it["unique"] = uid
	it["name"] = u["name"]
	it["req"] = u["lvl"]
	for s in u["stats"]:
		it["affixes"].append([s[0], s[1]])
	return it

## Random loot roll for a monster of the given level.
static func random_drop(ilvl: int, mf: float, rng: RandomNumberGenerator, boss := false) -> Dictionary:
	var m := 1.0 + mf / 100.0
	var r := rng.randf()
	var uq := (0.18 if boss else 0.012) * m
	if r < uq:
		var cands := []
		for k in Data.UNIQUES.keys():
			if Data.UNIQUES[k]["lvl"] <= ilvl + 3 and not Data.UNIQUES[k].get("boss_only", false):
				cands.append(k)
		if cands.size() > 0:
			return make_unique(cands[rng.randi() % cands.size()])
	var base := pick_base(ilvl, rng)
	var rare := (0.3 if boss else 0.075) * (1.0 + mf / 200.0)
	var magic := (0.9 if boss else 0.3) * (1.0 + mf / 300.0)
	var slot := slot_class(base)
	var rr := rng.randf()
	var rarity := 0
	if rr < rare:
		rarity = 2
	elif rr < magic:
		rarity = 1
	if slot in ["ring", "amulet"] and rarity == 0:
		rarity = 1
	return generate(base, ilvl, rarity, rng)

## A2 loot: multiplies weapon damage, armour and every affix on an item.
## Bonuses that are percentages or chances. empower leaves them as rolled: multiplying them
## made A2/A3 items with 100%+ resist (immunity), 100%+ life steal or 25x run speed.
const PCT_STATS := ["ed", "edef", "ias", "ls", "res", "block", "gf", "mf", "frw"]

## A2/A3 loot: base damage, defense and every flat bonus times mult.
static func empower(it: Dictionary, mult: float) -> Dictionary:
	if it.get("base", "") in ["gold"] or Data.BASES[it["base"]]["slot"] == "potion":
		return it
	if it.has("dmg"):
		it["dmg"] = [int(round(it["dmg"][0] * mult)), int(round(it["dmg"][1] * mult))]
	if it.has("def"):
		it["def"] = int(round(it["def"] * mult))
	var aff: Array = []
	for a in it.get("affixes", []):
		aff.append([a[0], a[1] if a[0] in PCT_STATS else int(round(float(a[1]) * mult))])
	it["affixes"] = aff
	it["power"] = mult
	return it

static func potion(base_id: String) -> Dictionary:
	var it := make(base_id, 0, 1)
	it["count"] = 1
	return it

static func gold(amount: int) -> Dictionary:
	return {"base": "gold", "rarity": 0, "name": "%d Gold" % amount, "count": amount, "affixes": []}

static func stat_sum(it: Dictionary) -> Dictionary:
	var d := {}
	for a in it.get("affixes", []):
		d[a[0]] = d.get(a[0], 0) + int(a[1])
	var en := int(it.get("ench", 0))
	if en > 0:
		d["life"] = d.get("life", 0) + enchant_life(it, en)
	return d

# ---------------------------------------------------------------- armor enchanting
const ENCHANT_SLOTS := ["helm", "armor", "gloves", "boots", "belt", "shield"]
const ENCHANT_MAX := 10

## Each enchant level adds 15% defense and some life (more for stronger, A2/A3 items).
static func enchant_life(it: Dictionary, en: int) -> int:
	return int(en * 6 * float(it.get("power", 1.0)))

static func enchant_cost(it: Dictionary) -> int:
	var en := int(it.get("ench", 0))
	return maxi(60, int(price(it) * 0.45 * pow(en + 1, 1.7)))

static func can_enchant(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] in ["helm", "armor", "gloves", "boots", "belt", "shield"] and int(it.get("ench", 0)) < ENCHANT_MAX

static func defense_of(it: Dictionary) -> int:
	if not it.has("def"):
		return 0
	var s := stat_sum(it)
	var en := 1.0 + 0.15 * int(it.get("ench", 0))
	return int(round((it["def"] + s.get("def", 0)) * (1.0 + s.get("edef", 0) / 100.0) * en))

static func damage_of(it: Dictionary) -> Array:
	if not it.has("dmg"):
		return [0, 0]
	var s := stat_sum(it)
	var k: float = 1.0 + s.get("ed", 0) / 100.0
	return [int(round(it["dmg"][0] * k)) + s.get("dmg", 0), int(round(it["dmg"][1] * k)) + s.get("dmg", 0)]

static func price(it: Dictionary) -> int:
	var b: Dictionary = Data.BASES[it["base"]]
	var p: float = b.get("price", 10)
	p *= [1.0, 2.5, 5.0, 12.0][int(it.get("rarity", 0))]
	p *= 1.0 + it.get("affixes", []).size() * 0.35
	p *= 1.0 + it.get("ilvl", 1) * 0.04
	p *= float(it.get("power", 1.0))
	return int(p)

static func sell_price(it: Dictionary) -> int:
	if Data.BASES[it["base"]]["slot"] == "potion":
		return 3
	return maxi(1, price(it) / 5)

static func is_equip(it: Dictionary) -> bool:
	return not (Data.BASES[it["base"]]["slot"] in ["potion", "gold"])

## Which equipment slot an item would go in (rings prefer the empty one).
static func equip_slot(it: Dictionary, equipment: Dictionary) -> String:
	var s: String = Data.BASES[it["base"]]["slot"]
	if s == "ring":
		if equipment.get("ring1") == null:
			return "ring1"
		if equipment.get("ring2") == null:
			return "ring2"
		return "ring1"
	return s

## Tooltip lines: Array of [text, Color].
static func tooltip(it: Dictionary, hero_level: int = 99, mode: String = "") -> Array:
	var lines := []
	var col: Color = Data.RARITY_COLOR[int(it.get("rarity", 0))]
	var b: Dictionary = Data.BASES[it["base"]]
	var en := int(it.get("ench", 0))
	lines.append([("+%d " % en if en > 0 else "") + it["name"], col])
	if int(it.get("rarity", 0)) > 0:
		lines.append([b["name"], col])
	if float(it.get("power", 1.0)) > 1.0:
		var pw := int(it["power"])
		lines.append(["%s item  ·  stats x%d" % ["A3" if pw >= 25 else "A2", pw], Color(1.0, 0.55, 0.3)])
	var white := Color(0.88, 0.86, 0.82)
	var blue := Color(0.5, 0.6, 1.0)
	if it.has("dmg"):
		var d := damage_of(it)
		var mod: bool = d[0] != it["dmg"][0] or d[1] != it["dmg"][1]
		lines.append(["One-Hand Damage: %d to %d" % [d[0], d[1]], blue if mod else white])
		lines.append(["Attack Speed: %s" % ("Fast" if b.get("speed", 1.0) >= 1.05 else ("Normal" if b.get("speed", 1.0) >= 0.95 else "Slow")), white])
	if it.has("def"):
		var dv := defense_of(it)
		lines.append(["Defense: %d" % dv, blue if dv != it["def"] else white])
	if it.has("block"):
		lines.append(["Chance to Block: %d%%" % it["block"], white])
	if b.has("heal"):
		lines.append(["Heals %d life over 4 seconds" % b["heal"], white])
	if b.has("mana"):
		lines.append(["Restores %d mana over 4 seconds" % b["mana"], white])
	if b.has("rejuv"):
		lines.append(["Instantly restores %d%% life and mana" % int(b["rejuv"] * 100), white])
	var req: int = it.get("req", 1)
	if req > 1:
		lines.append(["Required Level: %d" % req, Color(1.0, 0.3, 0.3) if req > hero_level else white])
	for a in it.get("affixes", []):
		var fmt: String = Data.STAT_LABEL.get(a[0], a[0] + " %d")
		lines.append([fmt % a[1], blue])
	if en > 0:
		lines.append(["Enchanted +%d: +%d%% defense, +%d life" % [en, en * 15, enchant_life(it, en)], Color(0.55, 0.75, 1.0)])
	match mode:
		"buy": lines.append(["Cost: %d gold" % price(it), Color(1.0, 0.85, 0.4)])
		"sell": lines.append(["Sell value: %d gold   (Right-click to sell)" % sell_price(it), Color(1.0, 0.85, 0.4)])
		"gamble": lines.append(["Gamble: %d gold" % (price(it) * 2), Color(1.0, 0.85, 0.4)])
		"inv":
			if is_equip(it):
				lines.append(["Left-click to equip  ·  Ctrl-click to drop", Color(0.6, 0.6, 0.6)])
			else:
				lines.append(["Right-click to drink  ·  Left-click to move to belt", Color(0.6, 0.6, 0.6)])
		"stash": lines.append(["Right-click to move", Color(0.6, 0.6, 0.6)])
		"equipped": lines.append(["Left-click to unequip", Color(0.6, 0.6, 0.6)])
	return lines
