class_name WarlockHex
extends RefCounted
## The Warlock's three directions (Blaine, 2026-11-06; design in data/codex/heroes/warlock.json, the Hero Codex):
##   Corruption: curses (damage over time) that stack, grow with every curse on a foe and how long it has been cursed,
##     and Reckoning, a curse that deals as much as all the others.
##   Fear: Terrify, the Scarecrow Effigy, Dark Wind and Crowstorm. Feared monsters cower (stunned: the server owns
##     their AI, and the stun is the one message every server already understands); a feared player really runs
##     (PvpStatus "fear", through the server, diminishing returns). Feared or bound foes take more from his spells.
##   Drain: Leech Bolt, Bountiful Harvest and Soul Feast; healing past full life can harden into a shield.
## WarlockSkills hands every id in IDS here. Everything is the caster's own game's state in `h.wl` (dots, fears,
## effigies, winds, the storm, the feast, the shield) and reaches monsters and players through the usual calls
## (Enemy.take_damage / stun / slow, PvpStatus.send), so it works alike in single player, co-op and the
## Battlegrounds. What is seen goes out as fx events (WarlockHarrowFx), never per frame.
## Rite keys (Hero.talent) read here: RITE_KEYS; the codex lets rites made of them (and the shared stats) be offered.

const IDS := ["w_corruption", "w_malediction", "w_unending", "w_festering", "w_leeching", "w_reckoning",
	"w_terrify", "w_effigy", "w_darkwind", "w_crowstorm", "w_leechbolt", "w_harvest", "w_soulfeast"]
## The curses: [share of spell damage over the whole curse, seconds]. Reckoning's ticks copy the others instead.
const CURSES := {"w_corruption": [2.4, 10.0], "w_unending": [1.8, 12.0], "w_festering": [0.0, 15.0],
	"w_leeching": [1.6, 8.0], "w_reckoning": [0.0, 6.0]}
const TICK := 0.5
const UNENDING_RAMP := 0.15     # +15% a second the foe has been cursed without a break
const UNENDING_CAP := 4.0
const FESTER_EVERY := 5.0
const FESTER_BURST := 1.2
const FESTER_STUN := 0.5
const LEECH_HEAL := 0.5
const MALEDICT_BASE := 0.9
const MALEDICT_PER := 0.5       # per curse on the target, up to MALEDICT_MAX
const MALEDICT_MAX := 5
const FEARED_BONUS := 20.0      # % more spell damage on a feared foe
const TERRIFY_SECS := 1.5
const TERRIFY_RANGE := 8.0
const EFFIGY_SECS := 8.0
const EFFIGY_R := 4.0
const EFFIGY_CHARGES := 3
const EFFIGY_FEAR := 1.0
const WIND_HOPS := 5
const WIND_HOP_R := 6.0
const WIND_GAP := 0.14
const WIND_DMG := 0.9
const STORM_SECS := 5.0
const STORM_R := 5.0
const STORM_DMG := 0.8
const STORM_BLINK := 8.0
const LEECHBOLT_HEAL := 0.3
const HARVEST_R := 5.0
const HARVEST_DMG := 1.8
const HARVEST_HEAL := 4.0       # % of his life per foe hit (twice that when it is the only one)
const FEAST_R := 7.0
const FEAST_DPS := 0.8
const FEAST_HEAL := 0.25
const FEAST_SHIELD := 30.0      # % of his life the feast's overflow can harden into
const SHIELD_FADE := 5.0        # out of combat this long, the shield melts away
## PvP: a player gets this share of a fear's seconds (and never more than PVP_FEAR_MAX).
const PVP_FEAR := 0.7
const PVP_FEAR_MAX := 1.2
const RITE_KEYS := ["dot_flat", "dot_dur", "dot_heal", "dot_echo", "fear_dur", "dmg_feared", "fear_spread", "fear_kill",
	"fear_root", "overheal_shield", "drain_execute", "shield_fork"]
## The curse's tint on the numbers it deals.
const CURSE_TINT := Color(0.72, 0.95, 0.4)
const SHADOW_TINT := Color(0.78, 0.6, 1.0)

static func has(id: String) -> bool:
	return id in IDS

## Game seconds (GameClock.now: frame deltas added up), so fears and "cursed for N s" follow the game's clock.
static func _now() -> float:
	return GameClock.now()

static func _st(h: Hero) -> Dictionary:
	if h.wl.is_empty():
		h.wl = {"dots": [], "since": {}, "feared": {}, "effigies": [], "winds": [], "storm": {}, "feast": {},
			"shield": 0.0, "shield_shown": 0.0, "spread": {}}
	return h.wl

# ---------------------------------------------------------------- damage
## A spell's 100%: grows with level and the weapon, like Blight Bolt's.
static func spell(h: Hero) -> float:
	return (12.0 + h.level * 4.0 + (h.dmg_min + h.dmg_max) * 0.5) * h.buff_mult()

static func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead

static func feared(h: Hero, e) -> bool:
	if not _alive(e):
		return false
	var f = _st(h)["feared"].get(e.get_instance_id())
	return f != null and float(f["until"]) > _now()

## Spell damage `k` of skill `id` on `e`: his talents for it, and more on a feared or bound foe.
static func amount(h: Hero, id: String, k: float, e = null) -> float:
	var v := spell(h) * k * h.dmg_mult(id)
	if e != null and (feared(h, e) or (_alive(e) and e.stun_t > 0.0)):
		v *= 1.0 + (FEARED_BONUS + h.talent("dmg_feared")) / 100.0
	return v

static func hit(h: Hero, e, v: float, tint := CURSE_TINT, soft := false) -> float:
	if not _alive(e) or v <= 0.0:
		return 0.0
	e.dmg_tint = tint
	e.soft_hit = soft
	var dealt: float = e.take_damage(0.0, v, h.global_position, 0.0, false)
	e.dmg_tint = Color(0, 0, 0, 0)
	e.soft_hit = false
	return dealt

## The foe nearest the pointer (within 3 m of it and `reach` of him), else the nearest to him in reach.
static func pick(h: Hero, aim: Vector3, reach: float):
	var best = null
	var bd := 3.0
	for e in h.game.enemies_near(aim, 3.0):
		if e.get("pvp_hidden") or e.get("pvp_obj"):
			continue
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(h.global_position) <= reach:
			bd = d
			best = e
	if best != null:
		return best
	bd = reach
	for e in h.game.enemies_near(h.global_position, reach):
		if e.get("pvp_hidden") or e.get("pvp_obj"):
			continue
		var d: float = e.global_position.distance_to(h.global_position)
		if d < bd:
			bd = d
			best = e
	return best

static func _range(id: String) -> float:
	return float(Data.skill_def(id).get("range", 12.0))

# ---------------------------------------------------------------- the ClassSkills calls (from WarlockSkills)
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	if id in ["w_corruption", "w_malediction", "w_unending", "w_festering", "w_leeching", "w_reckoning", "w_terrify", "w_darkwind", "w_leechbolt"]:
		if pick(h, aim, _range(id)) == null:
			h.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
			return false
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var w := _st(h)
	h._start_attack("cast", id)
	if id in ["w_corruption", "w_malediction", "w_unending", "w_festering", "w_leeching", "w_reckoning", "w_terrify", "w_darkwind", "w_leechbolt"]:
		w["aim_" + id] = pick(h, aim, _range(id))
		if w["aim_" + id] != null:
			h._face(w["aim_" + id].global_position - h.global_position)
	elif id == "w_soulfeast":
		w["feast"] = {"t": 0.0, "tick": 0.15}
		h.fx(id, "feast", {"x": float(Data.skill_def(id).get("use", 3.0))})
	elif id == "w_crowstorm":
		w["storm_to"] = aim

static func impact(h: Hero) -> bool:
	var id := h.atk_skill
	if not has(id):
		return false
	var w := _st(h)
	var e = w.get("aim_" + id)
	w.erase("aim_" + id)
	if e != null and not _alive(e):
		e = pick(h, h.atk_aim, _range(id) + 2.0)
	match id:
		"w_corruption", "w_unending", "w_festering", "w_leeching", "w_reckoning":
			if e != null:
				curse(h, e, id)
		"w_malediction":
			if e != null:
				var n := mini(curses_on(h, e), MALEDICT_MAX)
				h.fx(id, "bolt", {"t": [e], "n": n})
				hit(h, e, amount(h, id, MALEDICT_BASE * (1.0 + MALEDICT_PER * n), e), SHADOW_TINT)
		"w_terrify":
			if e != null:
				h.fx(id, "scream", {"t": [e]})
				fear(h, e, TERRIFY_SECS, id)
		"w_darkwind":
			if e != null:
				var chain := _wind_chain(h, e)
				h.fx(id, "wind", {"t": chain})
				w["winds"].append({"t": chain, "i": 0, "next": 0.0, "src": h.global_position})
		"w_leechbolt":
			if e != null:
				h.fx(id, "bolt", {"t": [e]})
				var dealt := hit(h, e, amount(h, id, 1.4, e), Color(0.6, 1.0, 0.45))
				heal(h, dealt * LEECHBOLT_HEAL)
		"w_effigy":
			var to := h.atk_aim - h.global_position
			to.y = 0.0
			var at := h.global_position + to.limit_length(_range(id))
			at.y = h.game.world.height_at(at.x, at.z)
			var dur := EFFIGY_SECS + h.talent("fear_dur") * 4.0
			h.fx(id, "plant", {"p": at, "x": dur})
			w["effigies"].append({"p": at, "t": dur, "left": EFFIGY_CHARGES, "check": 0.3, "hit": {}})
		"w_harvest":
			var foes: Array = h.game.enemies_near(h.global_position, HARVEST_R).filter(func(x): return not x.get("pvp_obj"))
			h.fx(id, "sweep", {"r": HARVEST_R, "t": foes})
			var per := HARVEST_HEAL * (2.0 if foes.size() == 1 else 1.0)
			for f in foes:
				hit(h, f, amount(h, id, HARVEST_DMG, f), SHADOW_TINT)
				heal(h, h.max_life * per / 100.0)
		"w_crowstorm":
			_blink(h, w.get("storm_to", h.atk_aim))
			w["storm"] = {"t": STORM_SECS, "tick": 0.25}
			h.fx(id, "storm", {"x": STORM_SECS, "r": STORM_R})
			for f in h.game.enemies_near(h.global_position, STORM_R):
				fear(h, f, 1.0, id)
		"w_soulfeast":
			pass      # the feast ticks in `update` while the cast lasts
	return true

# ---------------------------------------------------------------- curses (damage over time)
static func curses_on(h: Hero, e) -> int:
	var n := 0
	for d in _st(h)["dots"]:
		if d["e"] == e:
			n += 1
	# standing in one of his plague pools counts as a curse
	for bl in h.blights:
		if e.global_position.distance_to(bl["pos"]) <= float(bl.get("r", 3.0)):
			n += 1
			break
	return n

static func _dot(h: Hero, e, id: String) -> Dictionary:
	for d in _st(h)["dots"]:
		if d["e"] == e and d["id"] == id:
			return d
	return {}

## Put (or refresh) a curse on e.
static func curse(h: Hero, e, id: String) -> void:
	var w := _st(h)
	var spec: Array = CURSES[id]
	var base_dur: float = spec[1]
	var dur := base_dur * (1.0 + h.talent("dot_dur") / 100.0)
	var per := amount(h, id, float(spec[0])) / (base_dur / TICK)
	var key: int = e.get_instance_id()
	if not w["since"].has(key):
		w["since"][key] = _now()
	var d := _dot(h, e, id)
	h.fx(id, "curse", {"t": [e], "x": dur})
	if not d.is_empty():
		d["t"] = dur
		d["per"] = per
		if h.talent("dot_echo") > 0.0:
			_echo(h, e)
		return
	w["dots"].append({"e": e, "id": id, "per": per, "t": dur, "tick": TICK, "fester": FESTER_EVERY})

## Echoing Corruption: every curse on e ticks once, now.
static func _echo(h: Hero, e) -> void:
	for d in _st(h)["dots"].duplicate():
		if d["e"] == e:
			_tick(h, d)

## How long e has carried at least one of his curses without a break.
static func afflicted(h: Hero, e) -> float:
	var s = _st(h)["since"].get(e.get_instance_id())
	return 0.0 if s == null else _now() - float(s)

static func _tick_amount(h: Hero, d: Dictionary) -> float:
	var e = d["e"]
	match str(d["id"]):
		"w_reckoning":
			var sum := 0.0
			for o in _st(h)["dots"]:
				if o["e"] == e and o != d and str(o["id"]) != "w_reckoning":
					sum += _tick_amount(h, o)
			return sum
		"w_festering":
			return 0.0
		"w_unending":
			return float(d["per"]) * minf(UNENDING_CAP, 1.0 + UNENDING_RAMP * afflicted(h, e)) + h.talent("dot_flat")
	return float(d["per"]) + h.talent("dot_flat")

static func _tick(h: Hero, d: Dictionary) -> void:
	var e = d["e"]
	if not _alive(e):
		return
	var v := _tick_amount(h, d)
	if v > 0.0:
		if feared(h, e) or e.stun_t > 0.0:
			v *= 1.0 + (FEARED_BONUS + h.talent("dmg_feared")) / 100.0
		var dealt := hit(h, e, v, CURSE_TINT, true)
		if d["id"] == "w_leeching":
			heal(h, dealt * LEECH_HEAL)
	if h.talent("dot_heal") > 0.0 and randf() * 100.0 < h.talent("dot_heal"):
		heal(h, h.max_life * 0.01)

static func _update_dots(h: Hero, delta: float) -> void:
	var w := _st(h)
	var live := {}
	for d in w["dots"].duplicate():
		var e = d["e"]
		if not _alive(e) or float(d["t"]) <= 0.0:
			w["dots"].erase(d)
			continue
		d["t"] -= delta
		d["tick"] -= delta
		if d["tick"] <= 0.0:
			d["tick"] += TICK
			_tick(h, d)
		if d["id"] == "w_festering" and _alive(e):
			d["fester"] -= delta
			if d["fester"] <= 0.0:
				d["fester"] = FESTER_EVERY
				h.fx("w_festering", "fester", {"t": [e]})
				hit(h, e, amount(h, "w_festering", FESTER_BURST, e), SHADOW_TINT)
				_stun(h, e, FESTER_STUN)
		if _alive(e):
			live[e.get_instance_id()] = true
	for k in w["since"].keys():
		if not live.has(k):
			w["since"].erase(k)

# ---------------------------------------------------------------- fear
static func _stun(h: Hero, e, secs: float) -> void:
	if PvpStatus.is_player(e):
		PvpStatus.send(h.game, e, "stagger", minf(secs, 0.5))
	elif _alive(e):
		e.stun(secs)

## Frighten e for `secs` (the Haunting rite adds to it).
static func fear(h: Hero, e, secs: float, src: String) -> void:
	if not _alive(e) or e.get("pvp_obj"):
		return
	secs += h.talent("fear_dur")
	var w := _st(h)
	if PvpStatus.is_player(e):
		PvpStatus.send(h.game, e, "fear", minf(secs * PVP_FEAR, PVP_FEAR_MAX), {"p": h.global_position})
	else:
		e.stun(secs)
	w["feared"][e.get_instance_id()] = {"e": e, "until": _now() + (secs * (0.3 if e.boss else 1.0)), "src": src}
	h.fx(src, "fear", {"t": [e], "x": secs})

static func _update_fears(h: Hero) -> void:
	var w := _st(h)
	var now := _now()
	for k in w["feared"].keys():
		var f: Dictionary = w["feared"][k]
		var e = f["e"]
		if e == null or not is_instance_valid(e):
			w["feared"].erase(k)
			continue
		if e.dead:
			# Dread Harvest: a foe that died afraid
			if h.talent("fear_kill") > 0.0:
				h.mana = minf(h.max_mana, h.mana + 15.0 * h.talent("fear_kill"))
				if h.cds.has("w_terrify"):
					h.cds["w_terrify"] = maxf(0.0, float(h.cds["w_terrify"]) - 2.0 * h.talent("fear_kill"))
			w["feared"].erase(k)
			continue
		if float(f["until"]) <= now:
			w["feared"].erase(k)
			# Paralysing Terror: rooted where the fear ends
			if h.talent("fear_root") > 0.0:
				if PvpStatus.is_player(e):
					PvpStatus.send(h.game, e, "snare", 1.0, 1.0)
				else:
					e.slow(1.0, 1.0)
				h.fx(str(f["src"]), "root", {"t": [e]})
			continue
		# Contagious Panic: running into another frightens it for half a second (once each)
		if h.talent("fear_spread") > 0.0 and not bool(f.get("spread", false)):
			for o in h.game.enemies_near(e.global_position, 1.8):
				if o != e and not w["feared"].has(o.get_instance_id()) and not w["spread"].has(o.get_instance_id()):
					w["spread"][o.get_instance_id()] = true
					fear(h, o, 0.5, "w_terrify")
					w["feared"][o.get_instance_id()]["spread"] = true

# ---------------------------------------------------------------- crows: the Effigy, Dark Wind, Crowstorm
static func _update_effigies(h: Hero, delta: float) -> void:
	var w := _st(h)
	for ef in w["effigies"].duplicate():
		ef["t"] -= delta
		ef["check"] -= delta
		if ef["t"] <= 0.0:
			w["effigies"].erase(ef)
			h.fx("w_effigy", "gone", {"p": ef["p"]})
			continue
		if ef["check"] > 0.0 or ef["left"] <= 0:
			continue
		ef["check"] = 0.2
		var caught := []
		for e in h.game.enemies_near(ef["p"], EFFIGY_R):
			if ef["left"] <= 0:
				break
			var k: int = e.get_instance_id()
			if ef["hit"].has(k) or e.get("pvp_obj"):
				continue
			ef["hit"][k] = true
			ef["left"] -= 1
			caught.append(e)
		if not caught.is_empty():
			h.fx("w_effigy", "caw", {"p": ef["p"], "t": caught})
			for e in caught:
				fear(h, e, EFFIGY_FEAR, "w_effigy")

## Dark Wind's path: the first foe, then the nearest one not yet struck, up to WIND_HOPS.
static func _wind_chain(h: Hero, first) -> Array:
	var chain := [first]
	var at: Vector3 = first.global_position
	while chain.size() < WIND_HOPS:
		var best = null
		var bd := WIND_HOP_R
		for e in h.game.enemies_near(at, WIND_HOP_R):
			if chain.has(e) or e.get("pvp_hidden") or e.get("pvp_obj"):
				continue
			var d: float = e.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		chain.append(best)
		at = best.global_position
	return chain

static func _update_winds(h: Hero, delta: float) -> void:
	var w := _st(h)
	for wd in w["winds"].duplicate():
		wd["next"] -= delta
		if wd["next"] > 0.0:
			continue
		wd["next"] = WIND_GAP
		var chain: Array = wd["t"]
		if wd["i"] >= chain.size():
			w["winds"].erase(wd)
			continue
		var e = chain[wd["i"]]
		wd["i"] += 1
		if not _alive(e):
			continue
		var k := WIND_DMG * (2.0 if (feared(h, e) or e.stun_t > 0.0) else 1.0)
		hit(h, e, spell(h) * k * h.dmg_mult("w_darkwind"), SHADOW_TINT)
		if PvpStatus.is_player(e):
			PvpStatus.send(h.game, e, "slow", 1.0, {"k": 0.3})
		elif _alive(e):
			e.slow(1.0, 0.35)

static func _blink(h: Hero, to: Vector3) -> void:
	var d := to - h.global_position
	d.y = 0.0
	d = d.limit_length(STORM_BLINK)
	var from := h.global_position
	var end: Vector3 = h.game.world.move(from, d, h.radius)
	end.y = h.game.world.height_at(end.x, end.z)
	h.fx("w_crowstorm", "blink", {"p": from, "q": end})
	h.global_position = end
	h.path = PackedVector3Array()
	h.moving = false
	h.target = null

static func _update_storm(h: Hero, delta: float) -> void:
	var s: Dictionary = _st(h)["storm"]
	if s.is_empty():
		return
	s["t"] -= delta
	s["tick"] -= delta
	if s["t"] <= 0.0:
		_st(h)["storm"] = {}
		return
	if s["tick"] <= 0.0:
		s["tick"] = 0.5
		for e in h.game.enemies_near(h.global_position, STORM_R):
			if not e.get("pvp_obj"):
				hit(h, e, amount(h, "w_crowstorm", STORM_DMG, e), SHADOW_TINT, true)

# ---------------------------------------------------------------- the drain: heals and the shield
## Heal him; past full life it can harden into a shield (Blood Ward, the Soul Feast, Undying Hunger's).
static func heal(h: Hero, v: float) -> void:
	if v <= 0.0 or h.dead:
		return
	var room := maxf(0.0, h.max_life - h.life)
	h.life = minf(h.max_life, h.life + v)
	var over := v - room
	var pct := h.talent("overheal_shield") + (FEAST_SHIELD if not _st(h)["feast"].is_empty() else 0.0)
	if over > 0.0 and pct > 0.0:
		var w := _st(h)
		w["shield"] = minf(h.max_life * pct / 100.0, float(w["shield"]) + over)
		_show_shield(h)
	h.stats_changed.emit()

static func shield(h: Hero) -> float:
	return 0.0 if h.wl.is_empty() else float(h.wl.get("shield", 0.0))

## Hero.take_hit: the shield soaks the blow first.
static func absorb(h: Hero, dmg: float) -> float:
	var s := shield(h)
	if s <= 0.0:
		return dmg
	var soak := minf(s, dmg)
	h.wl["shield"] = s - soak
	_show_shield(h)
	return dmg - soak

## The shield's look follows its size in steps (an event only when it changes by a tenth of his life, or breaks).
static func _show_shield(h: Hero) -> void:
	var w := _st(h)
	var frac := float(w["shield"]) / maxf(1.0, h.max_life)
	var was := float(w["shield_shown"])
	if (frac <= 0.0 and was > 0.0) or absf(frac - was) >= 0.1 or (frac > 0.0 and was <= 0.0):
		w["shield_shown"] = frac
		h.fx("drain", "shield", {"x": frac})

static func _update_feast(h: Hero, delta: float) -> void:
	var w := _st(h)
	var f: Dictionary = w["feast"]
	if f.is_empty():
		return
	if h.atk_skill != "w_soulfeast" or h.atk_t < 0.0:
		w["feast"] = {}
		h.fx("w_soulfeast", "end")
		return
	f["tick"] -= delta
	if f["tick"] > 0.0:
		return
	f["tick"] = 0.3
	var total := 0.0
	for e in h.game.enemies_near(h.global_position, FEAST_R):
		if e.get("pvp_obj") or e.get("pvp_hidden"):
			continue
		total += hit(h, e, amount(h, "w_soulfeast", FEAST_DPS * 0.3, e), Color(0.6, 1.0, 0.45), true)
	heal(h, total * FEAST_HEAL)

# ---------------------------------------------------------------- housekeeping
static func update(h: Hero, delta: float) -> void:
	if h.wl.is_empty():
		return
	_update_dots(h, delta)
	_update_fears(h)
	_update_effigies(h, delta)
	_update_winds(h, delta)
	_update_storm(h, delta)
	_update_feast(h, delta)
	var w := _st(h)
	if float(w["shield"]) > 0.0 and h.combat_t > SHIELD_FADE:
		w["shield"] = maxf(0.0, float(w["shield"]) - h.max_life * 0.1 * delta)
		_show_shield(h)

static func rooted(h: Hero) -> bool:
	return h.atk_t >= 0.0 and h.atk_skill in ["w_soulfeast", "w_crowstorm"]

static func clear(h: Hero) -> void:
	if not h.wl.is_empty() and float(h.wl.get("shield", 0.0)) > 0.0:
		h.wl["shield"] = 0.0
		_show_shield(h)
	h.wl = {}

static func died(h: Hero) -> void:
	clear(h)

static func sound(h: Hero, skill: String, at: float) -> bool:
	if not has(skill):
		return false
	var nm := {"w_corruption": "curse_cast", "w_unending": "curse_cast", "w_festering": "curse_cast", "w_leeching": "curse_cast",
		"w_reckoning": "reckoning", "w_malediction": "malediction", "w_terrify": "terrify", "w_effigy": "effigy_plant",
		"w_darkwind": "crow_caw", "w_crowstorm": "crowstorm", "w_leechbolt": "leech_bolt", "w_harvest": "harvest_sweep",
		"w_soulfeast": "soul_feast"}
	var s := str(nm.get(skill, ""))
	if s != "" and (Sfx.bank.has(s) or Sfx.streams.has(s)):
		Sfx.play_synced(s, at, -3.0)
	else:
		Sfx.play_synced("blight_cast", at, -4.0)
	return true
