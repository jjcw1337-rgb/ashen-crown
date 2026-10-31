class_name Quests
extends RefCounted
## Quests: the quest log (J), the tracker on the HUD and the quest givers' "!" / "?" (VendorUI.Plates).
## Every quest is data (LINES, by run: 0 = Act I): who gives it (a camp role, Data.VENDORS), its texts (the offer,
## while it runs, the thanks), its goals and its reward. Goals:
##   {"kind": "kill", "ids": [Data.ENEMIES ids], "n": count, "text": "..."}   monsters of those kinds slain
##   {"kind": "pick", "ids": [Data.BASES ids], "n": count, "text": "..."}     those items picked up (materials)
##   {"kind": "flower", "n": count, "text": "..."}                            Sunstar Blooms picked
## "after": a quest that must be done first; "auto": active from the start (the act's main quest). Rewards:
## "gold", "xp", "items": [[base or "weapon" (his own kind) / "armor" / "unique", rarity, count]].
## State is per character and per run (`all[run][id]` = {"s": "active" | "ready" | "done", "c": [counts]}),
## saved in the character's save (Game.save_game). Counters move on every peer: kills reach partners through
## Net.cl_enemy_die, so a party's quests advance together.

signal changed

const LINES := {0: [
	{"id": "gilded_king", "name": "The Gilded King", "giver": "elder", "main": true, "auto": true,
		"offer": "",
		"busy": "Grubb holds his fort at the far end of Cairnfell Moor, behind a palisade and a ditch of black water. Go through the gate, past his guards, and end him in his own courtyard.",
		"done": "Grubb is dead and his gold is ours. The moor already feels lighter. The road north is open to you now, crusader.",
		"goals": [{"kind": "kill", "ids": ["goblin_king"], "n": 1, "text": "King Grubb slain"}],
		"reward": {"gold": 500, "xp": 1500, "items": [["unique", 0, 1]]}},
	{"id": "embers_road", "name": "Embers on the Road", "giver": "elder",
		"offer": "The Fallen have the Kingsroad. Skirmishers, reavers, stalkers: they come at our carts from the trees and leave nothing. Thin them out, ten of them, and the road may breathe again.",
		"busy": "The Fallen still hold the road. Ten of them, and we can send the carts out again.",
		"done": "Ten of the Fallen, and the road is quiet for the first time in weeks. Take this, you've earned it.",
		"goals": [{"kind": "kill", "ids": ["fallen_skirmisher", "fallen_reaver", "fallen_stalker", "fallen"], "n": 10, "text": "Fallen slain"}],
		"reward": {"gold": 150, "xp": 300, "items": [["ring", 1, 1]]}},
	{"id": "dying_forge", "name": "The Dying Forge", "giver": "smith",
		"offer": "Hear that? Neither do I. My forge fire is dying, and wood won't save it. Out on the moor there's a sloth made of embers, Cinderhide, and its heart burns hotter than any coal. Bring me its Cinderheart and I'll forge you something worth carrying.",
		"busy": "The fire's down to sparks. Cinderhide's lair is a burnt hollow off the road. Bring me its heart.",
		"done": "Now that is a fire. Feel the heat off it! Here, I forged this while it caught. Swing it well.",
		"goals": [{"kind": "pick", "ids": ["cinderheart"], "n": 1, "text": "Cinderheart taken from Cinderhide"}],
		"after": "embers_road",
		"reward": {"gold": 100, "xp": 500, "items": [["weapon", 2, 1]]}},
	{"id": "sunstar", "name": "Sunstar", "giver": "alch",
		"offer": "There's a flower out on the moor that glows like a little sun, the Sunstar Bloom. Only a few grow, far from the road. Pick one, and the light of it will sharpen you. Then come back and tell me where it grew.",
		"busy": "The Sunstar Bloom glows. You'll see it from a distance at dusk, away from the road.",
		"done": "You found one! I can smell it on your hands. These will serve you better than any I sell.",
		"goals": [{"kind": "flower", "n": 1, "text": "Sunstar Bloom picked"}],
		"reward": {"gold": 60, "xp": 250, "items": [["hp_potion", 0, 4], ["rejuv", 0, 2]]}},
	{"id": "forsaken", "name": "The Forsaken", "giver": "armor",
		"offer": "Two bears roam the moor that aren't bears any more. Antlers, rot, eyes like coals. They've taken three of our hunters. Kill them both, and I'll make you armour that remembers what they were.",
		"busy": "Both of the Forsaken Bears still walk. They keep to the moor, well off the road.",
		"done": "Both of them. Good. Here: hide and iron, the best I've made this winter.",
		"goals": [{"kind": "kill", "ids": ["bear"], "n": 2, "text": "Forsaken Bears slain"}],
		"reward": {"gold": 120, "xp": 600, "items": [["armor", 2, 1]]}},
	{"id": "three_hollows", "name": "Three Hollows", "giver": "elder",
		"offer": "Three giants sleep in the hollows of the moor: one of fire, one of frost, one of storm. While they live the moor won't heal. Kill all three.",
		"busy": "Cinderhide, Rimeclaw and Thundermaw. Each keeps its own hollow off the road. All three must fall.",
		"done": "All three hollows are quiet. I didn't think I'd live to see it. Take this, it was my father's.",
		"goals": [{"kind": "kill", "ids": ["sloth_fire"], "n": 1, "text": "Cinderhide slain"},
			{"kind": "kill", "ids": ["sloth_ice"], "n": 1, "text": "Rimeclaw slain"},
			{"kind": "kill", "ids": ["sloth_storm"], "n": 1, "text": "Thundermaw slain"}],
		"after": "embers_road",
		"reward": {"gold": 300, "xp": 1200, "items": [["unique", 0, 1]]}},
]}

var game
var all := {}          # str(run) -> {quest id: {"s": state, "c": [counts]}}

func _init(g) -> void:
	game = g

## The quests of the run being played (Act I's when difficulty is 0).
func line() -> Array:
	return LINES.get(int(game.difficulty), [])

func state() -> Dictionary:
	var k := str(int(game.difficulty))
	if not all.has(k):
		all[k] = {}
	var st: Dictionary = all[k]
	# the act's main quest is on from the start
	for q in line():
		if q.get("auto", false) and not st.has(q["id"]):
			st[q["id"]] = {"s": "active", "c": _zeros(q)}
	return st

func quest(id: String) -> Dictionary:
	for q in line():
		if q["id"] == id:
			return q
	return {}

func status(id: String) -> String:
	var st := state()
	return str(st[id]["s"]) if st.has(id) else ""

func counts(id: String) -> Array:
	var st := state()
	return st[id]["c"] if st.has(id) else _zeros(quest(id))

func _zeros(q: Dictionary) -> Array:
	var z := []
	for g in q.get("goals", []):
		z.append(0)
	return z

## A quest this giver can offer now (not taken, its "after" done), or {}.
func offer_for(role: String) -> Dictionary:
	for q in line():
		if q["giver"] == role and status(q["id"]) == "" and (str(q.get("after", "")) == "" or status(q["after"]) == "done"):
			return q
	return {}

func ready_for(role: String) -> Dictionary:
	for q in line():
		if q["giver"] == role and status(q["id"]) == "ready":
			return q
	return {}

## What floats over a giver: "?" when a quest waits to be handed in, "!" when one is on offer.
func mark(role: String) -> String:
	if not ready_for(role).is_empty():
		return "?"
	if not offer_for(role).is_empty():
		return "!"
	return ""

## The active and ready quests, the main quest first (the tracker and the log).
func current() -> Array:
	var out := []
	for q in line():
		var s := status(q["id"])
		if s == "active" or s == "ready":
			if q.get("main", false):
				out.push_front(q)
			else:
				out.append(q)
	return out

func accept(id: String) -> void:
	var q := quest(id)
	if q.is_empty():
		return
	state()[id] = {"s": "active", "c": _zeros(q)}
	game.ui.message("Quest accepted: " + str(q["name"]), Color(1.0, 0.82, 0.45), 3.0)
	Sfx.play("relic_ting", -6.0, 1.1)
	changed.emit()

## Something happened that quests count: a kill ("kill", the enemy's kind), an item picked up ("pick", its base),
## a Sunstar Bloom ("flower").
func progress(kind: String, key := "", n := 1) -> void:
	var st := state()
	var moved := false
	for q in line():
		var id: String = q["id"]
		if not st.has(id) or st[id]["s"] != "active":
			continue
		var c: Array = st[id]["c"]
		var goals: Array = q["goals"]
		for i in goals.size():
			var g: Dictionary = goals[i]
			if g["kind"] != kind or int(c[i]) >= int(g["n"]):
				continue
			if kind != "flower" and not (g.get("ids", []) as Array).has(key):
				continue
			c[i] = mini(int(c[i]) + n, int(g["n"]))
			moved = true
			if int(c[i]) < int(g["n"]):
				game.ui.message("%s: %d/%d" % [g["text"], c[i], g["n"]], Color(0.9, 0.84, 0.66), 2.0)
		if _complete(q, c):
			st[id]["s"] = "ready"
			var who: String = Data.VENDORS[0].get(q["giver"], "the camp")
			game.ui.message("%s complete: return to %s" % [q["name"], who], Color(1.0, 0.82, 0.45), 4.0)
			Sfx.play("levelup", -8.0, 1.2)
	if moved:
		changed.emit()

func _complete(q: Dictionary, c: Array) -> bool:
	var goals: Array = q["goals"]
	for i in goals.size():
		if int(c[i]) < int(goals[i]["n"]):
			return false
	return true

func on_kill(e) -> void:
	progress("kill", str(e.kind))

func on_pick(base: String) -> void:
	progress("pick", base)

## Hand a finished quest in: its reward, and it's done.
func turn_in(id: String) -> void:
	var q := quest(id)
	if q.is_empty() or status(id) != "ready":
		return
	state()[id]["s"] = "done"
	var r: Dictionary = q.get("reward", {})
	var h = game.hero
	if r.has("gold"):
		h.gold += int(r["gold"])
		Sfx.play("gold")
	if r.has("xp"):
		h.add_xp(int(r["xp"]))
	for spec in r.get("items", []):
		for k in int(spec[2]):
			var it := _reward_item(str(spec[0]), int(spec[1]))
			if it.is_empty():
				continue
			if not h.add_to_inventory(it):
				game.drop_item(it, h.global_position)
	game.ui.big_message("✦ " + str(q["name"]) + " ✦")
	game.ui.message("Quest complete: " + reward_text(q), Color(1.0, 0.82, 0.45), 4.0)
	Sfx.play("levelup", -2.0)
	game.save_game()
	changed.emit()

func _reward_item(what: String, rarity: int) -> Dictionary:
	var h = game.hero
	var lvl: int = h.level + 1
	match what:
		"unique":
			var cands := Data.UNIQUES.keys().filter(func(k): return Data.UNIQUES[k]["lvl"] <= lvl + 3 and not Data.UNIQUES[k].get("boss_only", false))
			if cands.is_empty():
				return {}
			return Items.make_unique(cands[randi() % cands.size()])
		"weapon":
			# his own kind of weapon (the archer's bow, the knight's blade), as good as the forge makes it
			var w = h.equipment.get("weapon")
			return Items.make(str(w["base"]) if w != null else "short_sword", rarity, lvl)
		"armor":
			var best := "quilted"
			for b in Data.BASES:
				var d: Dictionary = Data.BASES[b]
				if d["slot"] == "armor" and int(d["lvl"]) <= lvl and int(d["lvl"]) > int(Data.BASES[best]["lvl"]):
					best = b
			return Items.make(best, rarity, lvl)
	if not Data.BASES.has(what):
		return {}
	return Items.make(what, rarity, lvl)

## "500 gold, 1500 experience, a unique item"
func reward_text(q: Dictionary) -> String:
	var r: Dictionary = q.get("reward", {})
	var parts := []
	if r.has("gold"):
		parts.append("%d gold" % int(r["gold"]))
	if r.has("xp"):
		parts.append("%d experience" % int(r["xp"]))
	for spec in r.get("items", []):
		var what: String = spec[0]
		var n: int = spec[2]
		var nm: String = {"unique": "a unique item", "weapon": "a forged weapon", "armor": "a suit of armour"}.get(what, "")
		if nm == "":
			nm = str(Data.BASES[what]["name"]) if Data.BASES.has(what) else what
			nm = ("%d %ss" % [n, nm]) if n > 1 else ("a " + ("magic " if int(spec[1]) == 1 else ("rare " if int(spec[1]) == 2 else "")) + nm.to_lower())
		parts.append(nm)
	return ", ".join(parts)

## Talking to a camp role: a quest to hand in or one on offer comes first. `rest` is what they'd say otherwise
## (their trade, their news). Returns true when a quest dialog was shown.
func talk(role: String, who: String, rest: Callable) -> bool:
	var q := ready_for(role)
	if not q.is_empty():
		var id: String = q["id"]
		game.ui.open_dialog(who, str(q["done"]) + "\n\nReward: " + reward_text(q),
			[["Complete " + str(q["name"]), func(): turn_in(id)], ["Later", rest]])
		return true
	q = offer_for(role)
	if not q.is_empty():
		var id2: String = q["id"]
		var goals := "\n".join((q["goals"] as Array).map(func(g): return "•  %s (%d)" % [g["text"], g["n"]] if int(g["n"]) > 1 else "•  " + str(g["text"])))
		game.ui.open_dialog(who, str(q["offer"]) + "\n\n" + goals + "\nReward: " + reward_text(q),
			[["Accept: " + str(q["name"]), func(): accept(id2)], ["Not now", rest]])
		return true
	return false

func to_save() -> Dictionary:
	return all.duplicate(true)

func from_save(d) -> void:
	all = d.duplicate(true) if d is Dictionary else {}
	changed.emit()
