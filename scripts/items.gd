class_name Items
extends RefCounted
## Item generation, naming, stats, tooltips and prices.

const EQUIP_SLOTS := ["weapon", "shield", "helm", "armor", "gloves", "boots", "belt", "amulet", "ring1", "ring2"]

static func make(base_id: String, rarity: int = 0, ilvl: int = 1) -> Dictionary:
	var b: Dictionary = Data.BASES[base_id]
	var it := {"base": base_id, "rarity": rarity, "ilvl": ilvl, "affixes": [], "name": b["name"], "req": int(b.get("lvl", 1)), "gen": Data.ITEM_GEN}
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
		if slot in ["potion", "gold", "material", "resource", "tool"]:
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
			return [stat, maxi(1, int(round(v * float(Data.AFFIX_SCALE.get(stat, 1.0)))))]
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
	# at most one utility affix (run speed, dodge cost, cooldowns, potions, crowd control) on an item
	var util_seen := false
	var kept: Array = []
	for st in pool:
		if st in Data.UTILITY:
			if util_seen:
				continue
			util_seen = true
		kept.append(st)
	pool = kept
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
		var n2 := rng.randi_range(Data.RARE_AFFIXES[0], Data.RARE_AFFIXES[1])
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
		it["affixes"].append([s[0], scaled(s[0], s[1])])
	return it

## An affix's value under the item rules (Data.AFFIX_SCALE), for the uniques' stats and old items.
static func scaled(stat: String, v) -> int:
	if not Data.AFFIX_SCALE.has(stat):
		return int(v)
	return maxi(1, int(round(float(v) * float(Data.AFFIX_SCALE[stat]))))

## An item from before the items rework (no "gen"), rebuilt once under the new rules: a unique made again from its
## table (keeping its enchant, temper and act strength), any other item's affixes rescaled and a rare's trimmed to
## its best Data.RARE_AFFIXES[1] (by how high each rolled for its range). Nothing is deleted. Returns the item.
static func upgrade(it):
	if not (it is Dictionary) or int(it.get("gen", 1)) >= Data.ITEM_GEN or not it.has("base") or not Data.BASES.has(it["base"]):
		return it
	var was := int(it.get("gen", 1))
	if was >= 2 and not it.has("unique"):
		it["gen"] = Data.ITEM_GEN        # (already the rework's sizes: only uniques change after gen 2)
		return it
	if it.has("unique") and Data.UNIQUES.has(it["unique"]):
		var u := make_unique(it["unique"])
		for k in ["ench", "temper", "count"]:
			if it.has(k):
				u[k] = it[k]
		if float(it.get("power", 1.0)) > 1.0:
			empower(u, new_power(float(it["power"])) if was < 2 else float(it["power"]))
		return u
	# an A2/A3 item: its old act strength (x5, x25) becomes the act's new one (Data.OLD_POWER)
	var power := float(it.get("power", 1.0))
	var np := new_power(power)
	if power > 1.0:
		if it.has("dmg"):
			it["dmg"] = [maxi(1, int(round(float(it["dmg"][0]) / power * np))), maxi(2, int(round(float(it["dmg"][1]) / power * np)))]
		if it.has("def"):
			it["def"] = int(round(float(it["def"]) / power * np))
		it["power"] = np
	var aff: Array = []
	for a in it.get("affixes", []):
		var flat: bool = flat_stat(a[0])
		var v: float = float(a[1]) / (power if flat else 1.0)
		aff.append([a[0], int(round(scaled(a[0], v) * (np if flat else 1.0)))])
	if int(it.get("rarity", 0)) == 2 and aff.size() > Data.RARE_AFFIXES[1]:
		aff.sort_custom(func(x, y): return _roll_share(x, it) > _roll_share(y, it))
		aff.resize(Data.RARE_AFFIXES[1])
	it["affixes"] = aff
	it["gen"] = Data.ITEM_GEN
	return it

static func can_reforge(it) -> bool:
	return it is Dictionary and int(it.get("rarity", 0)) in [1, 2] and not (it.get("affixes", []) as Array).is_empty()

## The bonfire's Reforge: the affix that rolled lowest for its range is replaced by a new roll of a stat the item
## doesn't have (nor the one replaced) (from its slot's pool, one utility affix at most), at the item's level and act strength. Returns the
## new affix as its label.
static func reforge(it: Dictionary, rng: RandomNumberGenerator) -> String:
	var aff: Array = it["affixes"]
	var worst := 0
	for i in aff.size():
		if _roll_share(aff[i], it) < _roll_share(aff[worst], it):
			worst = i
	var have := aff.map(func(a): return a[0])       # (the old stat is left out too: a reroll is something new)
	var keep := have.duplicate()
	keep.remove_at(worst)
	var has_util := keep.any(func(st): return st in Data.UTILITY)
	var pool: Array = (Data.AFFIX_SLOTS.get(slot_class(it["base"]), []) as Array).filter(func(st): return not (st in have) and not (has_util and st in Data.UTILITY))
	if pool.is_empty():
		return ""
	var na := roll_affix(pool[rng.randi() % pool.size()], int(it.get("ilvl", 1)), rng)
	var p := float(it.get("power", 1.0))
	if p > 1.0 and flat_stat(na[0]):
		na[1] = int(round(float(na[1]) * p))
	aff[worst] = na
	return str(Data.STAT_LABEL.get(na[0], na[0] + " %d")) % int(na[1])

## An old act strength (x5, x25) as the items rework's (Data.OLD_POWER); new ones pass through.
static func new_power(p: float) -> float:
	for k in Data.OLD_POWER:
		if is_equal_approx(p, float(k)):
			return float(Data.OLD_POWER[k])
	return p

## How high an affix rolled for its range at the item's level (0..1+).
static func _roll_share(a: Array, it: Dictionary) -> float:
	for d in Data.AFFIXES:
		if d[0] == a[0]:
			var top: float = (float(d[3]) + float(d[4]) * int(it.get("ilvl", 1))) * float(Data.AFFIX_SCALE.get(a[0], 1.0))
			return float(a[1]) / maxf(1.0, top * (float(it.get("power", 1.0)) if flat_stat(a[0]) else 1.0))
	return 0.0

## Every item of a character's save rebuilt under the item rules (Hero.from_save): the worn ones, the bag, the belt,
## the stash.
static func upgrade_all(lists: Array) -> void:
	for l in lists:
		if l is Array:
			for i in (l as Array).size():
				l[i] = upgrade(l[i])
		elif l is Dictionary:
			for k in (l as Dictionary).keys():
				l[k] = upgrade(l[k])

## Random loot roll for a monster of the given level.
static func random_drop(ilvl: int, mf: float, rng: RandomNumberGenerator, boss := false) -> Dictionary:
	var m := 1.0 + mf / 100.0
	var r := rng.randf()
	var uq := (0.04 if boss else 0.003) * m      # (the items rework: uniques come from bosses' tables, Data.BOSS_LOOT)
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
const PCT_STATS := ["ed", "edef", "ias", "ls", "res", "block", "gf", "mf", "frw", "stam", "cdr", "pot", "ten"]

## Does an act's strength (empower) multiply this affix? Not percentages, not the uniques' effects (seconds and
## shares: an A3 Stormstride's dash stays 25%, its roll's recharge stays as it is).
static func flat_stat(stat: String) -> bool:
	return not (stat in PCT_STATS) and not (stat in Data.ITEM_EFFECTS)

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
		aff.append([a[0], a[1] if not flat_stat(a[0]) else int(round(float(a[1]) * mult))])
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
	var tp := int(it.get("temper", 0))
	if tp > 0:
		# the hardened edge: a share more damage, and a little more even on the lightest blade
		d["ed"] = d.get("ed", 0) + tp * TEMPER_ED
		d["dmg"] = d.get("dmg", 0) + tp
	return d

# ---------------------------------------------------------------- weapon tempering (Furnace)
## A weapon held in the furnace's heat and quenched: each level adds TEMPER_ED% enhanced damage and +1 damage, up
## to TEMPER_MAX.
## Level n needs the fire at TEMPER_BANDS[n - 1] °C or hotter, held for the soak; the furnace must be charged with
## the logs (and, from +4, Ashen Heartwood) and the smith's fee in gold first (temper_cost).
const TEMPER_MAX := 5
const TEMPER_ED := 2         # (the item rules; was 6)
const TEMPER_BANDS := [600.0, 850.0, 1050.0, 1250.0, 1350.0]
const TEMPER_BAND_NAMES := ["Cherry red", "Orange", "Yellow", "White", "Searing white"]

static func can_temper(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] == "weapon" and int(it.get("temper", 0)) < TEMPER_MAX

## What the next level costs: {level, logs, heart, gold, soak (seconds), temp (°C), band}. Better and higher-level
## weapons need more wood, a longer soak and more gold.
static func temper_cost(it: Dictionary) -> Dictionary:
	var n := int(it.get("temper", 0)) + 1
	var il := float(it.get("ilvl", 1)) * float(it.get("power", 1.0)) ** 0.25
	var k := 1.0 + il / 30.0
	return {"level": n, "logs": int(ceil((4.0 + 4.0 * n) * k * (1.0 + 0.15 * int(it.get("rarity", 0))))),
		"heart": 2 * maxi(0, n - 3), "gold": maxi(25, int(price(it) * 0.2 * n)),
		"soak": (8.0 + 3.0 * (n - 1)) * (1.0 + il / 40.0), "temp": TEMPER_BANDS[clampi(n - 1, 0, TEMPER_MAX - 1)],
		"band": TEMPER_BAND_NAMES[clampi(n - 1, 0, TEMPER_MAX - 1)]}

# ---------------------------------------------------------------- armor enchanting
const ENCHANT_SLOTS := ["helm", "armor", "gloves", "boots", "belt", "shield"]
const ENCHANT_MAX := 10
const ENCHANT_DEF := 0.05     # defence a level (the item rules; was 15%)

## Each enchant level adds ENCHANT_DEF defense and some life (more for stronger, A2/A3 items).
static func enchant_life(it: Dictionary, en: int) -> int:
	return int(en * 2 * float(it.get("power", 1.0)))

static func enchant_cost(it: Dictionary) -> int:
	var en := int(it.get("ench", 0))
	return maxi(60, int(price(it) * 0.45 * pow(en + 1, 1.7)))

static func can_enchant(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] in ["helm", "armor", "gloves", "boots", "belt", "shield"] and int(it.get("ench", 0)) < ENCHANT_MAX

static func defense_of(it: Dictionary) -> int:
	if not it.has("def"):
		return 0
	var s := stat_sum(it)
	var en := 1.0 + ENCHANT_DEF * int(it.get("ench", 0))
	# (the base's defence counts for Data.GEAR_ARMOR under the item rules)
	return int(round((it["def"] * Data.GEAR_ARMOR + s.get("def", 0)) * (1.0 + s.get("edef", 0) / 100.0) * en))

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
		return 3 * int(it.get("count", 1))
	return maxi(1, price(it) / 5)

static func is_equip(it: Dictionary) -> bool:
	return not (Data.BASES[it["base"]]["slot"] in ["potion", "gold", "material", "resource", "tool"])

## A gathered resource (wood now; ore, coal later): stacks, never worn, fuel or crafting stock.
static func is_resource(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] == "resource"

## A tool (the woodsman's axe): carried, never equipped.
static func is_tool_item(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] == "tool"

## How many of a base share one inventory cell: potions INV_STACK, resources their "stack", else 1.
static func stack_cap(base_id: String) -> int:
	var b: Dictionary = Data.BASES[base_id]
	if b["slot"] == "potion":
		return 20
	return int(b.get("stack", 1))

## n of a resource, as one item (a stack may be split over cells when it's put in the inventory).
static func resource(base_id: String, n: int = 1) -> Dictionary:
	var it := make(base_id, 0, 1)
	it["count"] = n
	return it

## A crafting material (the Hollow Sloths' drops): one space, kept, never worn or drunk.
static func is_material(it) -> bool:
	return it != null and Data.BASES[it["base"]]["slot"] == "material"

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
	if b["slot"] in ["material", "resource"]:
		col = b["color"].lerp(Color.WHITE, 0.35)
	var en := int(it.get("ench", 0))
	var tp := int(it.get("temper", 0))
	lines.append([("+%d " % (en + tp) if en + tp > 0 else "") + it["name"], col])
	if int(it.get("rarity", 0)) > 0:
		lines.append([b["name"], col])
	if float(it.get("power", 1.0)) > 1.0:
		var pw := float(it["power"])
		lines.append(["%s item  ·  stats x%s" % ["A3" if pw >= float(Data.RUNS[2]["power"]) - 0.01 else "A2", ("%.1f" % pw).trim_suffix(".0")], Color(1.0, 0.55, 0.3)])
	var white := Color(0.88, 0.86, 0.82)
	var blue := Color(0.5, 0.6, 1.0)
	if it.has("dmg"):
		var d := damage_of(it)
		var mod: bool = d[0] != it["dmg"][0] or d[1] != it["dmg"][1]
		lines.append(["One-Hand Damage: %d to %d" % [d[0], d[1]], blue if mod else white])
		if hero_level < 99:
			# what it hits for in the hand of a hero of this level (the item rules: the level's damage x its quality)
			var ss := stat_sum(it)
			var you: Array = Data.weapon_damage(hero_level, it["dmg"], float(it.get("power", 1.0)), int(ss.get("ed", 0)), int(ss.get("dmg", 0)))
			lines.append(["Weapon damage at level %d: %d to %d" % [hero_level, you[0], you[1]], Color(1.0, 0.85, 0.45)])
		lines.append(["Attack Speed: %s" % ("Fast" if b.get("speed", 1.0) >= 1.05 else ("Normal" if b.get("speed", 1.0) >= 0.95 else "Slow")), white])
	if it.has("def"):
		var dv := defense_of(it)
		lines.append(["Defense: %d" % dv, blue if dv != int(round(it["def"] * Data.GEAR_ARMOR)) else white])
	if it.has("block"):
		lines.append(["Chance to Block: %d%%" % it["block"], white])
	if b.has("heal"):
		lines.append(["Heals %d life over 4 seconds" % b["heal"], white])
	if b.has("mana"):
		lines.append(["Restores %d mana over 4 seconds" % b["mana"], white])
	if b.has("rejuv"):
		lines.append(["Instantly restores %d%% life and mana" % int(b["rejuv"] * 100), white])
	if b.has("cls"):
		lines.append(["%s only" % Data.CLASSES[b["cls"]]["name"], Color(0.75, 0.7, 0.6)])
	if b["slot"] == "material":
		lines.append(["Crafting Material", Color(0.75, 0.7, 0.6)])
		lines.append([b["lore"], Color(0.7, 0.66, 0.58)])
	if b["slot"] == "resource":
		lines.append(["Resource  ·  %d / %d" % [int(it.get("count", 1)), int(b.get("stack", 1))], Color(0.75, 0.7, 0.6)])
		if b.has("fuel"):
			lines.append(["Furnace fuel: %s (up to %d°C)" % [b["fuel"]["name"], int(b["fuel"]["max_temp"])], Color(1.0, 0.62, 0.3)])
		lines.append([b["lore"], Color(0.7, 0.66, 0.58)])
	if b["slot"] == "tool":
		lines.append(["Tool  ·  click a marked tree to chop it", Color(0.75, 0.7, 0.6)])
		lines.append([b["lore"], Color(0.7, 0.66, 0.58)])
	if b.get("kind", "") == "axe" and b["slot"] == "weapon":
		lines.append(["Can fell trees", Color(0.7, 0.66, 0.58)])
	var req: int = it.get("req", 1)
	if req > 1:
		lines.append(["Required Level: %d" % req, Color(1.0, 0.3, 0.3) if req > hero_level else white])
	for a in it.get("affixes", []):
		var fmt: String = Data.STAT_LABEL.get(a[0], a[0] + " %d")
		lines.append([fmt % a[1], blue])
	if en > 0:
		lines.append(["Enchanted +%d: +%d%% defense, +%d life" % [en, int(round(en * ENCHANT_DEF * 100)), enchant_life(it, en)], Color(0.55, 0.75, 1.0)])
	if tp > 0:
		lines.append(["Tempered +%d%s: +%d%% damage, +%d damage" % [tp, " (max)" if tp >= TEMPER_MAX else "", tp * TEMPER_ED, tp], Color(1.0, 0.62, 0.28)])
	elif b["slot"] == "weapon":
		lines.append(["Untempered  ·  a furnace can harden it", Color(0.62, 0.55, 0.48)])
	match mode:
		"buy": lines.append(["Cost: %d gold" % price(it), Color(1.0, 0.85, 0.4)])
		"sell": lines.append(["Sell value: %d gold   (Right-click to sell)" % sell_price(it), Color(1.0, 0.85, 0.4)])
		"gamble": lines.append(["Gamble: %d gold" % (price(it) * 2), Color(1.0, 0.85, 0.4)])
		"inv":
			if is_material(it) or is_resource(it) or is_tool_item(it):
				lines.append(["Drag to move  ·  Ctrl-click to drop", Color(0.6, 0.6, 0.6)])
			elif is_equip(it):
				lines.append(["Left-click to equip  ·  Ctrl-click to drop", Color(0.6, 0.6, 0.6)])
			else:
				lines.append(["Right-click to drink  ·  Left-click to move to belt", Color(0.6, 0.6, 0.6)])
		"stash": lines.append(["Right-click to move", Color(0.6, 0.6, 0.6)])
		"equipped": lines.append(["Left-click to unequip", Color(0.6, 0.6, 0.6)])
	return lines
