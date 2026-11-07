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

## Act I's quests: none today (the old ones all sent the hero onto the moor or into Grubb's fort, which are cut).
## A new quest goes here, for the camp's people to give.
const LINES := {0: []}

var game
var all := {}          # str(run) -> {quest id: {"s": state, "c": [counts]}}

func _init(g) -> void:
	game = g

## Act I's quests (the only act).
func line() -> Array:
	return LINES.get(0, [])

func state() -> Dictionary:
	var k := "0"
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
			var who: String = Data.VENDORS.get(q["giver"], "the camp")
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
