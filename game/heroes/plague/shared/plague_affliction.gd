class_name PlagueAffliction
extends PlagueSkill
## The Plague Doctor's poison, Blight and Fever: rules several of his skills share (one per hero, Hero.kit["poison"],
## wherever his rules run: his own game, or the match server's copy of him). Its numbers are Pestilence Vial's codex
## "k" (poison_flat/lvl/wpn: a second of the vial's poison; tick; blight_s; fever_s; fever_more).
##  Poison: one entry per foe and source ("toxic": his vials, pools and curses; "cane": his cane), refreshed, never
##    stacked; it ticks every `tick` through `damage` (green, no flinch; a player's stand-in forwards it to the server).
##  Blight: each DIFFERENT skill of his that touches a foe adds a stack (max 3, blight_s); at 3 the foe turns Feverish
##    for fever_s: seen by everyone, healing -40% (PvP), visible through his fog; monsters take fever_more % more from
##    his poison while Feverish. A player's stacks go through the server (PvpStatus "blight", "reveal").
## What is seen: "poisoned"/"cured" (the green haze on a monster), "blight" {n: stacks} and "fever" {x: secs} (the
## marks over a monster), drawn by PlagueFx on every game. Players' are their own game's (PvpStatusFx).

const CANE_DPS := [3.0, 0.55, 0.1]      # his cane's poison a second: flat, per level, per weapon roll (no codex entry)

var poisoned := {}      # enemy instance id -> {e, srcs: {src: [dps, secs]}, tick, age}
var blighted := {}      # enemy instance id -> {e, srcs: {src: secs}, fever: secs}

func tick() -> float:
	return val("tick", 0.5)

## What a second of each source's poison does. The per-level parts of all his damage are 0.55 of what they were before
## the PvP pass of 2026-11-02 (they had grown to twice anyone's; the pass cut the old kit's, and the new kit's follow).
func dps(src: String) -> float:
	match src:
		"toxic": return base_k("poison", 9.0, 1.26, 0.16, "toxic")
		"cane": return base(CANE_DPS[0], CANE_DPS[1], CANE_DPS[2], "attack")
	return 0.0

## Poisons a foe from one source: refreshed, never stacked.
func poison(e, src: String, secs: float) -> void:
	if e == null or not is_instance_valid(e) or e.dead or e.pvp_obj > 0:
		return
	var key: int = e.get_instance_id()
	if not poisoned.has(key):
		poisoned[key] = {"e": e, "srcs": {}, "tick": tick()}
		if _monster(e):
			hero.fx("toxic", "poisoned", {"t": [e]})
	var srcs: Dictionary = poisoned[key]["srcs"]
	var d := dps(src) * (1.0 + hero.talent("poison_dmg") / 100.0)
	var cur: Array = srcs.get(src, [0.0, 0.0])
	srcs[src] = [maxf(float(cur[0]), d), maxf(float(cur[1]), secs + hero.talent("poison_dur"))]

func is_poisoned(e) -> bool:
	return e != null and poisoned.has(e.get_instance_id())

## One stack per DIFFERENT skill of his (refreshed by the same one); three = Feverish.
func blight(e, src: String) -> void:
	if e == null or not is_instance_valid(e) or e.dead or e.pvp_obj > 0:
		return
	var key: int = e.get_instance_id()
	if not blighted.has(key):
		blighted[key] = {"e": e, "srcs": {}, "fever": 0.0}
	var b: Dictionary = blighted[key]
	var srcs: Dictionary = b["srcs"]
	var had := srcs.size()
	var secs := val("blight_s", 6.0)
	var fever_s := val("fever_s", 4.0)
	srcs[src] = secs
	if srcs.size() != had:
		if e.pvp_pid > 0:
			# a player: his own game shows it (PvpStatusFx, after the server's say), on his puppet for everyone
			PvpStatus.send(hero.game, e, "blight", secs, float(srcs.size()))
		elif _monster(e):
			hero.fx("toxic", "blight", {"t": [e], "n": srcs.size()})
	if srcs.size() >= 3 and float(b["fever"]) <= 0.0:
		b["fever"] = fever_s
		srcs.clear()
		if e.pvp_pid > 0:
			PvpStatus.send(hero.game, e, "blight", fever_s, 3.0)
			PvpStatus.send(hero.game, e, "reveal", fever_s, 1.0)
		hero.fx("toxic", "fever", {"t": [e] if _monster(e) else [], "p": e.global_position, "x": fever_s})

func feverish(e) -> bool:
	var b: Dictionary = blighted.get(e.get_instance_id(), {})
	return not b.is_empty() and float(b["fever"]) > 0.0

## A monster (not a player's stand-in or thing): its marks and haze are drawn on it.
static func _monster(e) -> bool:
	return int(e.get("pvp_pid")) <= 0 and int(e.get("pvp_obj")) <= 0

## It ticks on what his other skills laid this frame, so it runs after them (Skill.update_kit).
func late() -> bool:
	return true

func update(delta: float) -> void:
	_update_blight(delta)
	_update_poison(delta)

func _update_blight(delta: float) -> void:
	for key in blighted.keys():
		var b: Dictionary = blighted[key]
		var e = b["e"]
		if not is_instance_valid(e) or e.dead:
			blighted.erase(key)
			continue
		b["fever"] = maxf(float(b["fever"]) - delta, 0.0)
		var srcs: Dictionary = b["srcs"]
		var n := srcs.size()
		for s in srcs.keys():
			srcs[s] = float(srcs[s]) - delta
			if float(srcs[s]) <= 0.0:
				srcs.erase(s)
		if srcs.size() != n and e.pvp_pid <= 0:
			hero.fx("toxic", "blight", {"t": [e], "n": srcs.size()})
		if srcs.is_empty() and float(b["fever"]) <= 0.0:
			blighted.erase(key)

func _update_poison(delta: float) -> void:
	var t := tick()
	for key in poisoned.keys():
		var pz: Dictionary = poisoned[key]
		var e = pz["e"]
		if not is_instance_valid(e) or e.dead:
			poisoned.erase(key)
			continue
		var srcs: Dictionary = pz["srcs"]
		var total := 0.0
		for s in srcs.keys():
			var v: Array = srcs[s]
			v[1] = float(v[1]) - delta
			if float(v[1]) <= 0.0:
				srcs.erase(s)
			else:
				total += float(v[0])
		if srcs.is_empty():
			poisoned.erase(key)
			if _monster(e):
				hero.fx("toxic", "cured", {"t": [e]})
			continue
		pz["tick"] = float(pz["tick"]) - delta
		if float(pz["tick"]) <= 0.0:
			pz["tick"] = t
			var fever := 1.0 + val("fever_more", 20.0) / 100.0 if (feverish(e) and e.pvp_pid == 0) else 1.0
			pz["age"] = float(pz.get("age", 0.0)) + t
			var grow := RunTalents.poison_mult(hero, float(pz["age"])) if hero.run != null and e.pvp_pid == 0 else 1.0
			damage(e, total * t * fever * grow, e.global_position, false)
			if hero.run != null:
				RunTalents.on_dot(hero, e, total * t * fever * grow)

## Everything goes (a class change, a new character): the hazes and marks it put on monsters too, on every game.
func clear() -> void:
	var marked: Array = []
	for key in poisoned.keys():
		var e = poisoned[key]["e"]
		if is_instance_valid(e) and _monster(e):
			marked.append(e)
	for key in blighted.keys():
		var e = blighted[key]["e"]
		if is_instance_valid(e) and _monster(e) and not marked.has(e):
			marked.append(e)
	poisoned.clear()
	blighted.clear()
	if not marked.is_empty() and hero.game != null and hero.game.world != null:
		hero.fx("toxic", "cured", {"t": marked, "x": 1})
