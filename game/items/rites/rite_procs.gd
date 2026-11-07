class_name RiteProcs
extends RefCounted
## When a rite's or gem's proc fires: the hooks combat calls (through RunTalents) and the match on each proc's name.
## Procs run on the game that decides the hero's hits (Hero.decides: the match server in a match, the player's own
## game otherwise). What they do to foes is ProcHits; what they give the player themselves (a buff, a cooldown back,
## Hunger) on the match server's copy of them goes to their own game too (_tell_owner, Net.tell_self).

## [def, stacks] for every rite and gem with a proc this hero has (cached on the run; RunBuild.changed() clears it).
static func procs(h: Hero) -> Array:
	var r: RunBuild = h.run
	if r == null:
		return []
	if r.proc_cache != null:
		return r.proc_cache
	var out := []
	for id in r.passives:
		var t := RunBuild.passive_def(h.cls, id)
		if t.has("proc"):
			out.append([t, int(r.passives[id])])
	for g in r.gems:
		var gd := Gems.gem_def(str(g))
		if gd.has("proc"):
			out.append([gd, 1])
	r.proc_cache = out
	return out

static func _active(h: Hero, proc: String) -> Array:
	return procs(h).filter(func(p): return p[0]["proc"] == proc)

static func _src_ok(k: Dictionary, src: String) -> bool:
	var want := str(k.get("src", ""))
	return want == "" or want == src

## This hero struck `e` now: its death is theirs for the next 4 s (on_death). Every way a hero hurts a monster marks
## it: a blow (hit_mult), poison (PlagueSkill.damage), a burn set (Enemy.ignite), a proc (ProcHits.deal).
static func mark(h: Hero, e) -> void:
	if h != null and h.run != null and h.decides() and e != null and is_instance_valid(e):
		e.set_meta("run_hit", [h, Time.get_ticks_msec()])

## The multiplier on one of this hero's hits on `e` (before the roll): the conditional rites.
static func hit_mult(h: Hero, e, src: String) -> float:
	if h.run == null or e == null or not is_instance_valid(e):
		return 1.0
	mark(h, e)
	var m := 1.0
	var r: RunBuild = h.run
	for p in procs(h):
		var t: Dictionary = p[0]
		var k := Rites.k_at(t, int(p[1]))
		match str(t["proc"]):
			"more_vs_low":
				if e.max_life > 0.0 and e.life / e.max_life * 100.0 < float(k["below"]):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_burning":
				if ProcHits.burning(e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_chilled":
				if ProcHits.chilled(e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_poisoned":
				if ProcHits.poisoned(h, e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_marked":
				if h.mark == e and h.mark_t > 0.0:
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_big":
				if e.boss or e.champion:
					m *= 1.0 + float(k["more"]) / 100.0
			"berserk":
				var missing := 1.0 - h.life / maxf(1.0, h.max_life)
				m *= 1.0 + float(k["most"]) / 100.0 * clampf(missing / 0.8, 0.0, 1.0)
	if r.hunger > 0.0:
		m *= 1.0 + r.hunger / 100.0
	if e.has_meta("slipped_until"):
		# Banana Bonanza (Doug's run skill): the next blow on a foe that slipped on one of its peels
		if Time.get_ticks_msec() < int(e.get_meta("slipped_until")):
			m *= 2.0
		e.remove_meta("slipped_until")
	return m

## After one of this hero's hits landed on `e`.
static func on_hit(h: Hero, e, dealt: float, crit: bool, src: String) -> void:
	if h.run == null or not h.decides() or ProcHits.in_proc or e == null or not is_instance_valid(e):
		return
	e.set_meta("run_hit", [h, Time.get_ticks_msec()])
	var list := procs(h)
	if list.is_empty():
		return
	var foe_ok: bool = ProcHits.monster(e) or e.pvp_pid > 0
	for p in list:
		var t: Dictionary = p[0]
		var k := Rites.k_at(t, int(p[1]))
		match str(t["proc"]):
			"ignite_on_hit":
				if _src_ok(k, src) and not e.dead and foe_ok:
					e.ignite(dealt * float(k["pct"]) / 100.0, float(k["secs"]), "" if h.cls != "archer" else "fire")
					if h.cls == "archer":
						FlameFx.burn(h.game, e, "fire", float(k["secs"]))
			"ignite_on_crit":
				if crit and not e.dead and foe_ok:
					e.ignite(dealt * float(k["pct"]) / 100.0, float(k["secs"]))
			"chill_on_hit":
				if _src_ok(k, src) and not e.dead and foe_ok:
					e.chill(float(k["slow"]), float(k["secs"]))
			"freeze_after":
				if ProcHits.chilled(e) and not e.dead and ProcHits.monster(e):
					var n := int(e.get_meta("frost_hits", 0)) + 1
					if n >= int(k["n"]):
						n = 0
						ProcHits.freeze(h, e, float(k["secs"]))
					e.set_meta("frost_hits", n)
			"chain_on_hit":
				if _src_ok(k, src) and ProcHits.monster(e):
					ProcHits.chain(h, e, int(k["jumps"]), dealt * float(k["pct"]) / 100.0, float(k["r"]))
			"ricochet":
				if (src == "attack" or src == "") and ProcHits.monster(e):
					ProcHits.ricochet(h, e, int(k["bounces"]), dealt * float(k["pct"]) / 100.0, float(k["r"]))
			"bolt_on_crit":
				if crit and ProcHits.monster(e):
					ProcHits.bolt(h, e.global_position, ProcHits.weapon(h) * float(k["pct"]) / 100.0, float(k["r"]))
			"nth_hit_bolt":
				if ProcHits.monster(e):
					var c := int(h.run.counters.get("bolt", 0)) + 1
					if c >= int(k["n"]):
						c = 0
						ProcHits.bolt(h, e.global_position, ProcHits.weapon(h) * float(k["pct"]) / 100.0, float(k["r"]))
					h.run.counters["bolt"] = c
			"frenzy":
				if crit:
					buff(h, "frenzy", {"ias": float(k["ias"])}, float(k["secs"]))
			"bloodlust":
				if h.life < h.max_life * float(k["below"]) / 100.0:
					h.gain_life(dealt * float(k["pct"]) / 100.0)
			"spread_on_hit":
				if _src_ok(k, src) and ProcHits.poisoned(h, e):
					ProcHits.spread_poison(h, e, int(k["n"]), float(k["r"]))

## A monster died: the procs of the hero who struck it last (within 4 s), on that hero's game.
static func on_death(e) -> void:
	if not e.has_meta("run_hit"):
		return
	var rec: Array = e.get_meta("run_hit")
	var h = rec[0]
	if not is_instance_valid(h) or h.run == null or not h.decides() or h.dead:
		return
	if Time.get_ticks_msec() - int(rec[1]) > 4000 or not (e.pvp_pid == 0 and e.pvp_obj == 0 and e.sandbox_hero == null):
		return
	var was_burning := ProcHits.burning(e)
	var was_chilled := ProcHits.chilled(e)
	var was_poisoned := ProcHits.poisoned(h, e)
	for p in procs(h):
		var t: Dictionary = p[0]
		var k := Rites.k_at(t, int(p[1]))
		match str(t["proc"]):
			"momentum":
				var n := mini(int(h.run.counters.get("momentum", 0)) + 1, int(k["stacks"]))
				h.run.counters["momentum"] = n
				buff(h, "momentum", {"dmg": float(k["dmg"]) * n}, float(k["secs"]), "momentum")
			"heal_on_kill":
				if int(k.get("poisoned", 0)) == 0 or was_poisoned:
					h.gain_life(h.max_life * float(k["pct"]) / 100.0)
					if int(k.get("poisoned", 0)) == 1:
						buff(h, "rotfeast", {"frw": 15.0}, 3.0)
			"explode_on_kill":
				if ProcHits.depth < 3:
					var amt := minf(e.max_life * float(k["pct"]) / 100.0, ProcHits.weapon(h) * 4.0)
					ProcHits.area(h, e.global_position, float(k["r"]), amt, "fire" if h.cls != "warlock" else "fel", e)
			"spread_burn_on_death":
				if was_burning:
					var dps := maxf(e.burn_dps, ProcHits.weapon(h) * 0.25)
					var hit := 0
					for o in h.game.enemies_near(e.global_position, float(k["r"])):
						if o != e and ProcHits.monster(o):
							o.ignite(dps, maxf(2.5, e.burn_t), e.burn_look)
							if e.burn_look != "":
								FlameFx.burn(h.game, o, e.burn_look, 2.5)
							hit += 1
					h.fx("run", "flare", {"p": e.global_position, "r": float(k["r"]), "n": 0})
			"shards_on_death":
				if was_chilled and ProcHits.depth < 3:
					ProcHits.area(h, e.global_position, float(k["r"]), ProcHits.weapon(h) * float(k["pct"]) / 100.0, "frost", e)
			"spread_on_death":
				if was_poisoned:
					ProcHits.spread_poison(h, e, int(k["n"]), float(k["r"]))
			"cloud_on_death":
				if was_poisoned and ProcHits.depth < 3:
					ProcHits.area(h, e.global_position, float(k["r"]), ProcHits.weapon(h) * float(k["pct"]) / 100.0, "plague", e)
			"hunger":
				h.run.hunger = minf(float(k["most"]), h.run.hunger + float(k["per"]))
				_tell_owner(h, {"hunger": [float(k["per"]), float(k["most"])]})
			"speed_on_kill":
				buff(h, "adrenaline", {"frw": float(k["frw"])}, float(k["secs"]))
			"mark_reset":
				if e.has_meta("hunted_until") and Time.get_ticks_msec() < int(e.get_meta("hunted_until")):
					h.cds["a_mark"] = 0.0
					_tell_owner(h, {"cd": "a_mark"})
					buff(h, "marked_death", {"dmg": float(k["dmg"])}, float(k["secs"]))

## Poison ticking on `e`: Necrosis's growth (PlagueAffliction multiplies the tick by this).
static func poison_mult(h: Hero, age: float) -> float:
	if h.run == null:
		return 1.0
	var m := 1.0
	for p in _active(h, "necrosis"):
		var k := Rites.k_at(p[0], int(p[1]))
		m *= 1.0 + minf(float(k["most"]), float(k["grow"]) * age) / 100.0
	return m

## Poison (or another damage over time of his) dealt `amount` to `e`.
static func on_dot(h: Hero, _e, amount: float) -> void:
	if h.run == null or not h.decides() or amount <= 0.0:
		return
	for p in _active(h, "heal_on_dot"):
		var k := Rites.k_at(p[0], int(p[1]))
		h.gain_life(amount * float(k["pct"]) / 100.0)

## This hero was struck for `dmg` from `from` (after armour): Retribution's blow back.
static func struck(h: Hero, dmg: float, from: Vector3) -> void:
	if h.run == null or h.puppet or dmg <= 0.0:
		return
	var list := _active(h, "thorns")
	if list.is_empty():
		return
	if not h.decides():
		# a hero whose hits are the match server's: its copy there strikes back (server_struck)
		h.game.net.send_skill_make("run", "struck", {"dmg": dmg, "from": from})
		return
	_thorns(h, list, dmg, from)

## Match server: a server-run hero's game says it took a blow with thorns on (RunTalents.server_made "struck"): only a
## blow the server sent them counts (Net.took_blow). False when it doesn't add up.
static func server_struck(h: Hero, d: Dictionary) -> bool:
	var dmg := float(d.get("dmg", 0.0))
	var list := _active(h, "thorns")
	if list.is_empty() or not d.get("from") is Vector3 or not h.game.net.took_blow(int(h.peer_id), dmg):
		return false
	_thorns(h, list, dmg, d["from"])
	return true

static func _thorns(h: Hero, list: Array, dmg: float, from: Vector3) -> void:
	var best = null
	var bd := 4.0
	for e in h.game.enemies_near(from, 4.0):
		if ProcHits.monster(e):
			var d: float = e.global_position.distance_to(from)
			if d < bd:
				bd = d
				best = e
	if best == null:
		return
	var pct := 0.0
	for p in list:
		pct += float(Rites.k_at(p[0], int(p[1]))["pct"])
	ProcHits.deal(h, best, dmg * pct / 100.0, "holy" if h.cls == "knight" else "phys")

## A killing blow on this hero: true when a rite or gem refuses it (life is set; the caller doesn't die).
static func save_from_death(h: Hero) -> bool:
	if h.run == null or h.puppet:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	for p in _active(h, "undying"):
		var t: Dictionary = p[0]
		var k := Rites.k_at(t, int(p[1]))
		var key := "undying_" + str(t["id"])
		var last := float(h.run.counters.get(key, -100000.0))
		if now - last < float(k["secs"]):
			continue
		if int(k.get("burst", 0)) == 1 and h.run.counters.has(key):
			continue          # (the Phoenix Ember: once a run)
		h.run.counters[key] = now
		h.life = h.max_life * float(k["life"]) / 100.0
		h.fx("run", "undying", {"p": h.global_position, "n": int(k.get("burst", 0))})
		if int(k.get("burst", 0)) == 1:
			for e in h.game.enemies_near(h.global_position, 5.0):
				if ProcHits.monster(e):
					e.ignite(ProcHits.weapon(h) * 0.6, 4.0)
		if h._mine():
			h.game.ui.message(str(t["name"]) + ": not yet", RunTalents.RARITY_COLORS[3])
		return true
	return false

## A skill went on cooldown: Echo may bring it back at once.
static func on_cooldown(h: Hero, id: String) -> void:
	if h.run == null or h.puppet or h.cds.get(id, 0.0) <= 0.0:
		return
	for p in _active(h, "echo"):
		var k := Rites.k_at(p[0], int(p[1]))
		if randf() * 100.0 < float(k["chance"]):
			h.cds[id] = 0.0
			h.fx("run", "echo", {"p": h.global_position})
			return

## A plain shot was loosed (ArcherShot.impact): Phoenix Quiver's every-nth free skill.
static func on_shot(h: Hero) -> void:
	if h.run == null or h.puppet:
		return
	for p in _active(h, "nth_shot"):
		var k := Rites.k_at(p[0], int(p[1]))
		var c := int(h.run.counters.get("shot", 0)) + 1
		if c >= int(k["n"]):
			c = 0
			ClassSkills.free_cast(h, str(k["skill"]), h.atk_aim)
		h.run.counters["shot"] = c

# ---------------------------------------------------------------- timed buffs

## Every frame on the hero's own game: the timed buffs running out.
static func tick(h: Hero, delta: float) -> void:
	var r: RunBuild = h.run
	if r == null or r.buffs.is_empty():
		return
	var gone := false
	for key in r.buffs.keys():
		r.buffs[key]["t"] = float(r.buffs[key]["t"]) - delta
		if float(r.buffs[key]["t"]) <= 0.0:
			r.buffs.erase(key)
			if key == "momentum":
				r.counters["momentum"] = 0
			gone = true
	if gone:
		h.refresh_run()

## A timed buff of stats (momentum, frenzy, a consumable's, a skill's): added to the run's fx until it runs out.
static func buff(h: Hero, key: String, fx: Dictionary, secs: float, _kind := "") -> void:
	if h.run == null:
		return
	var had: bool = h.run.buffs.has(key)
	var same: bool = had and h.run.buffs[key]["fx"] == fx
	h.run.buffs[key] = {"t": secs, "fx": fx}
	if not same:
		h.refresh_run()
	_tell_owner(h, {"buff": [key, fx, secs]})

## A proc on the match server's copy of a player (its rules run there: ServerRules) that changes the player
## themselves (a buff, a cooldown back, Hunger): their own game gets it too (Net.cl_self).
static func _tell_owner(h: Hero, d: Dictionary) -> void:
	if h.puppet and h.game.net.server:
		h.game.net.tell_self(h, d)
